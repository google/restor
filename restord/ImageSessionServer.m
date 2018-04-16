/// Copyright 2017 Google Inc. All rights reserved.
///
/// Licensed under the Apache License, Version 2.0 (the "License");
/// you may not use this file except in compliance with the License.
/// You may obtain a copy of the License at
///
///    http://www.apache.org/licenses/LICENSE-2.0
///
///    Unless required by applicable law or agreed to in writing, software
///    distributed under the License is distributed on an "AS IS" BASIS,
///    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
///    See the License for the specific language governing permissions and
///    limitations under the License.

#import "ImageSessionServer.h"

@import DiskArbitration;

#import <MOLXPCConnection/MOLXPCConnection.h>

#import "Disk.h"
#import "Image.h"
#import "RestorProtocol.h"

NSString * const kImageInfo = @"/Library/Preferences/com.google.corp.imageinfo.plist";

// GUID Partition Table UUID Constants
NSString * const kGPTAPFSUUID = @"7C3457EF-0000-11AA-AA11-00306543ECAC";
NSString * const kGPTCoreStorageUUID = @"53746F72-6167-11AA-AA11-00306543ECAC";

@interface ImageSessionServer ()

/// Connection back to the client that began imaging
@property MOLXPCConnection *client;

/// The source URL of the image
@property(copy) Image *image;

@property BOOL isImageAPFS;

/// The target disk/partition.
@property(copy) Disk *targetDisk;

/// The destination URL, should be a file URL for a disk/partition.
@property(copy) NSURL *destination;

/// The percentage through the current part of the imaging process.
@property NSUInteger percentage;

/// Whether the image is applying (NO) or verifying (YES).
@property BOOL verifying;

/// Storage for the NSTask running ASR (to allow cancellation).
@property NSTask *asr;

/// The date/time that imaging started.
@property NSDate *startDate;

/// DiskArb references
@property DASessionRef diskArbSession;
@property DADiskRef diskRef;

@end

@implementation ImageSessionServer

- (instancetype)initWithImage:(nonnull Image *)image
                   targetDisk:(nonnull Disk *)targetDisk
                       client:(nonnull MOLXPCConnection *)conn {
  self = [super init];
  if (self) {
    _image = image;
    _targetDisk = targetDisk;
    _destination = [NSURL fileURLWithPathComponents:@[@"/dev", targetDisk.bsdName]];
    _client = conn;
    _startDate = [NSDate date];
    _isImageAPFS = [self isImageAPFSContainer];

    NSLog(@"%@ New imaging client: s: '%@', d: %@", self, _image.name, _destination.path);

    if (!_image.localURL) {
      NSLog(@"%@ Provided image (%@) has no local URL!? Aborting!", self, _image.name);
      return nil;
    }

    _diskArbSession = DASessionCreate(NULL);
    DASessionSetDispatchQueue(_diskArbSession,
                              dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0));
    _diskRef = DADiskCreateFromBSDName(NULL, _diskArbSession, self.destination.path.UTF8String);

    if (!_diskRef) {
      NSLog(@"%@ Unable to get DADiskRef for destination. Imaging might fail!", self);
    }
  }
  return self;
}

- (void)dealloc {
  if (_diskRef) CFRelease(_diskRef);
  if (_diskArbSession) CFRelease(_diskArbSession);
}

- (void)beginImaging {
  [self unmountDisk:self.diskRef];

  int diskUtilReturnCode = [self eraseDisk];
  NSLog(@"%@ DiskUtil exit code: %d", self, diskUtilReturnCode);

  int asrReturnCode = [self applyImage];
  NSLog(@"%@ ASR exit code: %d", self, asrReturnCode);

  if (asrReturnCode == 0) {
    DADiskRef disk = NULL;
    if (self.isImageAPFS) {
      NSString *apfsBootDisk = [NSString stringWithFormat:@"/dev/%@", [self apfsBootDisk]];
      disk = DADiskCreateFromBSDName(NULL, self.diskArbSession, apfsBootDisk.UTF8String);
    }
    NSURL *mountURL = [self mountDisk:disk ?: self.diskRef];
    if (!mountURL) {
      NSLog(@"%@ Unable to remount target, skipping imaginfo.plist application", self);
    } else {
      NSLog(@"%@ Remounted target %@ as %@", self, self.destination.path, mountURL.path);

      // Set imageinfo.plist keys
      [self applyImageInfo:mountURL];

      [self blessMountURL:mountURL];
      [self unmountDisk:disk ?: self.diskRef];
    }
    if (disk) CFRelease(disk);
  }

  // Send final reply with task status.
  [[self.client remoteObjectProxy] imageAppliedSuccess:(asrReturnCode == 0)];
}

- (void)cancelImaging {
  NSLog(@"%@ Cancelling imaging!", self);
  if (self.asr.isRunning) [self.asr terminate];
  self.asr = nil;
}

- (int)eraseDisk {
  // Check the target disk's GPT to erase with the appropriate tools
  if ([self.targetDisk.mediaContent isEqualToString:kGPTAPFSUUID]) {
    NSLog(@"Delete APFS Container");
    return [self deleteAPFSContainer];
  } else if ([self.targetDisk.mediaContent isEqualToString:kGPTCoreStorageUUID]) {
    NSLog(@"Delete CoreStorage LogicalVolumeGroup");
    NSString *lvg = [self coreStorageLogicalVolumeGroup];
    return [self deleteCoreStorageLogicalVolumeGroup:lvg];
  } else {
    NSLog(@"Erase HFS Volume");
    NSTask *diskUtil = [[NSTask alloc] init];
    diskUtil.standardOutput = [NSPipe pipe];
    diskUtil.standardError = [NSPipe pipe];
    diskUtil.launchPath = @"/usr/sbin/diskutil";
    diskUtil.arguments = @[ @"eraseVolume", @"JHFS+", @"%noformat", self.destination.path ];
    [diskUtil launch];
    [diskUtil waitUntilExit];
    return diskUtil.terminationStatus;
  }
}

- (int)deleteCoreStorageLogicalVolumeGroup:(NSString *)lvg {
  if (!lvg) return -1;
  NSTask *diskUtil = [[NSTask alloc] init];
  diskUtil.launchPath = @"/usr/sbin/diskutil";
  diskUtil.arguments = @[ @"cs", @"delete", lvg ];
  [diskUtil launch];
  [diskUtil waitUntilExit];
  return diskUtil.terminationStatus;
}

- (NSString *)coreStorageLogicalVolumeGroup {
  NSTask *diskUtil = [[NSTask alloc] init];
  diskUtil.standardOutput = [NSPipe pipe];
  diskUtil.standardError = [NSPipe pipe];
  diskUtil.launchPath = @"/usr/sbin/diskutil";
  diskUtil.arguments = @[ @"cs", @"info", @"-plist", self.destination.path ];
  [diskUtil launch];
  [diskUtil waitUntilExit];

  NSData *sout = [[diskUtil.standardOutput fileHandleForReading] readDataToEndOfFile];
  if (sout) {
    NSDictionary *csDict = [NSPropertyListSerialization propertyListWithData:sout
                                                                     options:0
                                                                      format:NULL
                                                                       error:NULL];
    return csDict[@"MemberOfCoreStorageLogicalVolumeGroup"];
  }
  return nil;
}

- (int)deleteAPFSContainer {
  NSTask *diskUtil = [[NSTask alloc] init];
  diskUtil.launchPath = @"/usr/sbin/diskutil";
  diskUtil.arguments = @[ @"apfs", @"deleteContainer", self.destination.path ];
  [diskUtil launch];
  [diskUtil waitUntilExit];
  return diskUtil.terminationStatus;
}

- (int)createAPFSContainer {
  NSTask *diskUtil = [[NSTask alloc] init];
  diskUtil.launchPath = @"/usr/sbin/diskutil";
  diskUtil.arguments = @[ @"apfs", @"createContainer", self.destination.path ];
  [diskUtil launch];
  [diskUtil waitUntilExit];
  return diskUtil.terminationStatus;
}

- (NSArray *)partitionsForImageDict:(NSDictionary *)imageDict {
  if (![imageDict isKindOfClass:[NSDictionary class]]) return nil;
  if (![imageDict[@"partitions"] isKindOfClass:[NSDictionary class]]) return nil;
  if (![imageDict[@"partitions"][@"partitions"] isKindOfClass:[NSArray class]]) return nil;
  return imageDict[@"partitions"][@"partitions"];
}

- (BOOL)isImageAPFSContainer {
  NSTask *hdiUtil = [[NSTask alloc] init];
  hdiUtil.standardOutput = [NSPipe pipe];
  hdiUtil.standardError = [NSPipe pipe];
  hdiUtil.launchPath = @"/usr/bin/hdiutil";
  hdiUtil.arguments = @[ @"imageinfo", @"-plist", self.image.localURL.path ];
  [hdiUtil launch];
  [hdiUtil waitUntilExit];

  NSData *sout = [[hdiUtil.standardOutput fileHandleForReading] readDataToEndOfFile];
  if (sout) {
    NSDictionary *imageDict = [NSPropertyListSerialization propertyListWithData:sout
                                                                        options:0
                                                                         format:NULL
                                                                          error:NULL];
    for (NSDictionary *partition in [self partitionsForImageDict:imageDict]) {
      if (![partition isKindOfClass:[NSDictionary class]]) return NO;
      if ([partition[@"partition-hint-UUID"] isEqualToString:kGPTAPFSUUID]) return YES;
    }
  }
  return NO;
}

- (NSString *)apfsBootDisk {
  NSTask *diskUtil = [[NSTask alloc] init];
  diskUtil.standardOutput = [NSPipe pipe];
  diskUtil.standardError = [NSPipe pipe];
  diskUtil.launchPath = @"/usr/sbin/diskutil";
  diskUtil.arguments = @[ @"apfs", @"list", @"-plist" ];
  [diskUtil launch];
  [diskUtil waitUntilExit];

  NSData *sout = [[diskUtil.standardOutput fileHandleForReading] readDataToEndOfFile];
  if (sout) {
    NSDictionary *apfsDict = [NSPropertyListSerialization propertyListWithData:sout
                                                                        options:0
                                                                         format:NULL
                                                                          error:NULL];
    // Find the boot APFS volume and return it's BSD disk name.
    for (NSDictionary *c in apfsDict[@"Containers"]) {
      if (![c isKindOfClass:[NSDictionary class]]) return nil;
      if (![c[@"DesignatedPhysicalStore"] isEqualToString:self.targetDisk.bsdName]) continue;
      // Find the first volume that does not have a role. This should be the boot volume.
      for (NSDictionary *volume in c[@"Volumes"]) {
        if (![volume isKindOfClass:[NSDictionary class]]) return nil;
        if (![volume[@"Roles"] isKindOfClass:[NSArray class]]) return nil;
        if (![volume[@"Roles"] count]) return volume[@"DeviceIdentifier"];
      }
    }
  }
  return nil;
}

- (int)applyImage {
  NSString *path = self.image.localURL.path;

  // asr chokes if the destination is not already an APFS container when applying an APFS image.
  if (self.isImageAPFS) {
    NSLog(@"Create APFS Container");
    int ret = [self createAPFSContainer];
    if (ret != 0) {
      NSError *e = [NSError errorWithDomain:@"com.google.corp.restord"
                                       code:555
                                   userInfo:@{
        NSLocalizedDescriptionKey:@"You can only apply a 10.13 or later image "
                                  @"from a Mac running 10.13 or later."
      }];
      [[self.client remoteObjectProxy] errorOccurred:e];
      return ret;
    }
  }

  self.asr = [[NSTask alloc] init];
  self.asr.launchPath = @"/usr/sbin/asr";
  self.asr.arguments = @[ @"restore",
                          @"--buffersize",
                          @"16m",
                          @"--source",
                          path,
                          @"--target",
                          self.destination.path,
                          @"--erase",
                          @"--noprompt",
                          @"--noverify",
                          @"--puppetstrings" ];

  // Set task environment.
  NSMutableDictionary *environment = [[[NSProcessInfo processInfo] environment] mutableCopy];
  environment[@"NSUnbufferedIO"] = @"YES";
  self.asr.environment = environment;

  // Create output pipe & file handle.
  self.asr.standardError = self.asr.standardOutput = [[NSPipe alloc] init];
  NSFileHandle *outputFh = [self.asr.standardOutput fileHandleForReading];
  outputFh.readabilityHandler = ^(NSFileHandle *h) {
    NSData *availableData = [h availableData];
    [self processOutput:(NSData *)availableData];
  };

  // Launch and wait for exit.
  [self.asr launch];
  [self.asr waitUntilExit];

  // Clear readability handler or the file handle is never released.
  outputFh.readabilityHandler = nil;

  return self.asr.terminationStatus;
}

- (void)processOutput:(NSData *)output {
  if (!output.length) return;

  NSCharacterSet *whitespace = [NSCharacterSet whitespaceCharacterSet];

  NSString *text = [[NSString alloc] initWithData:output encoding:NSUTF8StringEncoding];
  for (NSString *dirtyLine in [text componentsSeparatedByString:@"\n"]) {
    // Remove whitespace from both ends.
    NSString *line = [dirtyLine stringByTrimmingCharactersInSet:whitespace];

    // Skip empty and XSTA lines
    if (!line.length || [line hasPrefix:@"XSTA"]) continue;

    if ([line hasPrefix:@"PINF"] || [line hasPrefix:@"PSTT"] || [line hasPrefix:@"PSTP"]) {
      // Lines beginning PINF/PSTT/PSTP are indicating a percentage
      NSArray *components = [line componentsSeparatedByCharactersInSet:whitespace];
      if (components.count < 2) continue;
      NSUInteger percentage = [[components objectAtIndex:1] intValue];

      if (percentage < self.percentage) {
        self.verifying = YES;
      }
      self.percentage = percentage;

      if (self.verifying) {
        [[self.client remoteObjectProxy] verifyingPercentage:self.percentage];
      } else {
        [[self.client remoteObjectProxy] imagingPercentage:self.percentage];
      }
    } else if (line.length >= dirtyLine.length &&
               ![line isEqualToString:@"done"] &&
               ![line isEqualToString:@"Validating target..."] &&
               ![line isEqualToString:@"Validating sizes..."]) {
      // Print personalization successes
      if ([line isEqualToString:@"Personalization over TDM succeeded"]) {
        NSLog(@"%@: %@", self, line);
        return;
      }
      // If line doesn't begin with a tab (an INFO message) and isn't a known info message,
      // treat it as an error :-(
      NSLog(@"%@ ASR Error: %@", self, line);
      NSError *e = [NSError errorWithDomain:@"com.google.corp.restord"
                                       code:666
                                   userInfo:@{ NSLocalizedDescriptionKey: line }];
      [[self.client remoteObjectProxy] errorOccurred:e];
    }
  }
}

#pragma mark Disk Mounting / Unmounting

// Used by both mountDisk and unmountDisk to wait for mount/unmount to complete before returning.
void MountUnmountCallback(DADiskRef disk, DADissenterRef dissenter, void *context) {
  dispatch_semaphore_t sema = (__bridge dispatch_semaphore_t)context;
  dispatch_semaphore_signal(sema);
}

// Mount the given disk at a temporary location, returning the mount location.
// May take up to 5 seconds.
- (NSURL *)mountDisk:(DADiskRef)disk {
  dispatch_semaphore_t sema = dispatch_semaphore_create(0);
  NSString *uuid = [[NSProcessInfo processInfo] globallyUniqueString];
  NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:uuid];
  NSURL *directoryURL = [NSURL fileURLWithPath:path isDirectory:YES];
  [[NSFileManager defaultManager] createDirectoryAtURL:directoryURL
                           withIntermediateDirectories:YES
                                            attributes:nil
                                                 error:NULL];
  DADiskMount(disk, (__bridge CFURLRef)directoryURL, 0,
              &MountUnmountCallback, (__bridge void *)sema);
  if (dispatch_semaphore_wait(sema, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC))) {
    NSLog(@"%@ timed out while mounting disk", self);
    return nil;
  }

  NSDictionary *desc = CFBridgingRelease(DADiskCopyDescription(disk));
  return desc[(__bridge NSString *)kDADiskDescriptionVolumePathKey];
}

// Unmount a given disk forcibly. May take up to 5 seconds.
- (void)unmountDisk:(DADiskRef)disk {
  dispatch_semaphore_t sema = dispatch_semaphore_create(0);
  DADiskUnmount(disk, kDADiskUnmountOptionForce, &MountUnmountCallback, (__bridge void *)sema);
  if (dispatch_semaphore_wait(sema, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC))) {
    NSLog(@"%@ timed out while unmounting disk", self);
  }
}

// Save image and imaging session information to the target mount, in the imageinfo.plist file.
- (void)applyImageInfo:(NSURL *)mountURL {
  NSURL *imageInfoURL = [mountURL URLByAppendingPathComponent:kImageInfo];
  NSMutableDictionary *imageInfo = [NSMutableDictionary dictionaryWithContentsOfURL:imageInfoURL];
  if (!imageInfo) imageInfo = [[NSMutableDictionary alloc] init];

  NSDateFormatter *dateFormat = [[NSDateFormatter alloc] init];
  /// Purposefully not using the z format specifier as GMT and UTC
  /// are special-cased. GMT shows the +0000 offset and UTC shows as GMT :-/
  dateFormat.dateFormat = @"yyyy'-'MM'-'dd HH':'mm':'ss 'UTC'";
  dateFormat.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
  NSString *imageStartTime = [dateFormat stringFromDate:self.startDate];
  NSString *imageEndTime = [dateFormat stringFromDate:[NSDate date]];
  imageInfo[@"ImageStartTime"] = imageStartTime;
  imageInfo[@"ImageEndTime"] = imageEndTime;

  imageInfo[@"ImageURL"] = self.image.URL.absoluteString;
  imageInfo[@"ImageHash"] = self.image.sha256;
  imageInfo[@"Imager"] = @"Restor.app";
  imageInfo[@"ImagerVersion"] =
      [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];

  NSError *error;
  NSData *plistData = [NSPropertyListSerialization dataWithPropertyList:imageInfo
                                                                 format:NSPropertyListXMLFormat_v1_0
                                                                options:0
                                                                  error:&error];
  if (!error) {
    [plistData writeToURL:imageInfoURL options:NSDataWritingAtomic error:&error];
  }

  if (error) {
    NSLog(@"%@ Failed to write imageinfo.plist: %@", self, error);
  }
}

- (void)blessMountURL:(NSURL *)mountURL {
  NSTask *bless = [[NSTask alloc] init];
  bless.launchPath = @"/usr/sbin/bless";
  bless.arguments = @[ @"--folder", mountURL.path ];
  [bless launch];
  [bless waitUntilExit];
  if (bless.terminationStatus != 0) NSLog(@"%@ Failed to bless: %@", self, mountURL.path);
}

@end
