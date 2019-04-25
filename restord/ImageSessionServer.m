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

#import "restord/ImageSessionServer.h"

#import <DiskArbitration/DiskArbitration.h>

#import <MOLXPCConnection/MOLXPCConnection.h>

#import "Common/Disk.h"
#import "Common/Image.h"
#import "Common/RestorProtocol.h"

NSString * const kImageInfo = @"/Library/Preferences/com.google.corp.imageinfo.plist";

// GUID Partition Table UUID Constants
NSString * const kGPTAPFSUUID = @"7C3457EF-0000-11AA-AA11-00306543ECAC";
NSString * const kGPTCoreStorageUUID = @"53746F72-6167-11AA-AA11-00306543ECAC";

@interface ImageSessionServer ()

/// Connection back to the client that began imaging
@property MOLXPCConnection *client;

/// The source URL of the image
@property(copy) Image *image;

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

// Unknown ASR lines
@property NSMutableArray *asrUnknownLines;

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
    _asrUnknownLines = [NSMutableArray array];

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
  [self unmountDisk:self.diskRef withOptions:kDADiskUnmountOptionWhole];

  // Remove any top level recovery partitions.
  [self removeRecovery];

  int asrReturnCode = [self applyImage];
  NSLog(@"%@ ASR exit code: %d", self, asrReturnCode);

  if (asrReturnCode != 0) {
    NSError *err = [self constructErrorFromReturnCode:asrReturnCode];
    [[self.client remoteObjectProxy] imageAppliedSuccess:NO error:err];
    return;
  }

  // Get the synthesized "Macintosh HD" apfs disk, if any.
  DADiskRef disk = NULL;
  NSString *apfsOSDisk = [self apfsOSDisk];
  if (apfsOSDisk) {
    NSString *apfsBootDisk = [NSString stringWithFormat:@"/dev/%@", apfsOSDisk];
    disk = DADiskCreateFromBSDName(NULL, self.diskArbSession, apfsBootDisk.UTF8String);
  }
  NSURL *mountURL = [self mountDisk:disk ?: self.diskRef];

  // Fail if the disk would not mount and the post script is required.
  // Succeed if the disk would not mount and the post script is not required.
  // Otherwise continue on.
  if (!mountURL) {
    if (self.image.postScript && self.image.postScriptMustSucceed) {
      NSString *s = @"Unable to remount target and the post script must succeed!";
      NSDictionary *info = @{ NSLocalizedDescriptionKey: s };
      NSError *err = [NSError errorWithDomain:@"com.google.corp.restord" code:777 userInfo:info];
      [[self.client remoteObjectProxy] imageAppliedSuccess:NO error:err];
    } else {
      NSLog(@"%@ Unable to remount target, skipping imaginfo.plist and post script", self);
      [[self.client remoteObjectProxy] imageAppliedSuccess:YES error:nil];
    }
    if (disk) CFRelease(disk);
    return;
  }

  NSLog(@"%@ Remounted target %@ as %@", self, self.destination.path, mountURL.path);

  // Lay down the image info first so the post script can use the data.
  [self applyImageInfo:mountURL];

  // Run the post script.
  // Fail if the post script failed and the post script is required.
  if (self.image.postScript) {
    [[self.client remoteObjectProxy] postScriptStarted];
    NSError *err;
    if ([self runPostScriptWithMountURL:mountURL error:&err] != 0 &&
        self.image.postScriptMustSucceed) {
      [[self.client remoteObjectProxy] imageAppliedSuccess:NO error:err];
      if (disk) CFRelease(disk);
      return;
    }
  }

  // Finish up.
  [self blessMountURL:mountURL];
  [self unmountDisk:disk ?: self.diskRef withOptions:kDADiskUnmountOptionWhole];
  if (disk) CFRelease(disk);
  [self ejectDisk:self.diskRef];
  [[self.client remoteObjectProxy] imageAppliedSuccess:YES error:nil];
}

- (NSError *)constructErrorFromReturnCode:(int)code {
  NSMutableString *s = [NSMutableString stringWithFormat:@"ASR failed with exit code: %d.", code];

  if (self.asrUnknownLines.count) {
    [s appendString:@"\nPotential Errors:"];
    for (NSString *line in self.asrUnknownLines) {
      [s appendFormat:@"\n%@", line];
    }
  }

  NSOperatingSystemVersion version = {10, 13, 4};
  if (![[NSProcessInfo processInfo] isOperatingSystemAtLeastVersion:version]) {
    [s appendString:@"\nHave you tried Restor on macOS 10.13.4 or above?"];
  }

  NSDictionary *info = @{ NSLocalizedDescriptionKey: s };
  return [NSError errorWithDomain:@"com.google.corp.restord" code:555 userInfo:info];
}

- (void)cancelImaging {
  NSLog(@"%@ Cancelling imaging!", self);
  if (self.asr.isRunning) [self.asr terminate];
  self.asr = nil;
}

- (NSString *)recoveryDevice {
  NSTask *diskUtil = [[NSTask alloc] init];
  diskUtil.standardOutput = [NSPipe pipe];
  diskUtil.launchPath = @"/usr/sbin/diskutil";
  diskUtil.arguments = @[ @"info", @"-plist", self.destination.path ];
  [diskUtil launch];
  [diskUtil waitUntilExit];

  NSData *sout = [[diskUtil.standardOutput fileHandleForReading] readDataToEndOfFile];
  if (sout) {
    NSDictionary *info = [NSPropertyListSerialization propertyListWithData:sout
                                                                   options:0
                                                                    format:NULL
                                                                     error:NULL];
    if ([info isKindOfClass:[NSDictionary class]]) return info[@"RecoveryDeviceIdentifier"];
  }
  return nil;
}

- (void)removeRecovery {
  NSString *recoveryDevice = [self recoveryDevice];
  if (!recoveryDevice) return;
  NSLog(@"%@ Removing recovery device: %@", self, recoveryDevice);
  NSTask *diskUtil = [[NSTask alloc] init];
  diskUtil.launchPath = @"/usr/sbin/diskutil";
  diskUtil.arguments = @[ @"eraseVolume", @"Free", @"Space", recoveryDevice ];
  [diskUtil launch];
  [diskUtil waitUntilExit];
  if (diskUtil.terminationStatus == 0) {
    NSLog(@"%@ Recovery device: %@ removed", self, recoveryDevice);
  } else {
    NSLog(@"%@ Failed to remove recovery device: %@", self, recoveryDevice);
  }
}

- (NSString *)apfsOSDisk {
  NSTask *diskUtil = [[NSTask alloc] init];
  diskUtil.standardOutput = [NSPipe pipe];
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
    // Find the APFS OS volume (Macintosh HD) and return its BSD disk name.
    for (NSDictionary *c in apfsDict[@"Containers"]) {
      if (![c isKindOfClass:[NSDictionary class]]) return nil;
      if (![c[@"DesignatedPhysicalStore"] isEqualToString:self.targetDisk.bsdName]) continue;
      // Find the first volume that does not have a role. This should be the OS volume.
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
  return self.asr ? self.asr.terminationStatus : -1;
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
    } else if ([line isEqualToString:@"Personalization over TDM succeeded"]) {
      NSLog(@"%@ %@", self, line);
    } else if ([line isEqualToString:@"Inverting target volume..."]) {
      [[self.client remoteObjectProxy] invertingStarted];
    } else if (line.length >= dirtyLine.length &&
               ![line isEqualToString:@"done"] &&
               ![line isEqualToString:@"Validating target..."] &&
               ![line isEqualToString:@"Validating source..."] &&
               ![line isEqualToString:@"Validating sizes..."] &&
               ![line isEqualToString:@"Repartitioning target device..."] &&
               ![line isEqualToString:@"Retrieving scan information..."] &&
               ![line hasPrefix:@"nx_kernel_mount"]) {
      // If line doesn't begin with a tab (an INFO message) and isn't a known info message,
      // save the line and surface it as an error if ASR fails.
      NSLog(@"%@ ASR unknown line: %@", self, line);
      [self.asrUnknownLines addObject:line];
    }
  }
}

#pragma mark Disk Mounting / Unmounting

//
// Mount and unmounts may take up to 5 minutes.
//

// Used by various disk operations to wait for completion before returning.
void MountUnmountEjectCallback(DADiskRef disk, DADissenterRef dissenter, void *context) {
  if (dissenter) {
    NSLog(@"MountUnmountEjectCallback: Error from Unmount %s: status=%X, string=%@", DADiskGetBSDName(disk),
          DADissenterGetStatus(dissenter), DADissenterGetStatusString(dissenter));
    LogDiskAndDissenter(disk, dissenter);
  }
  dispatch_semaphore_t sema = (__bridge dispatch_semaphore_t)context;
  dispatch_semaphore_signal(sema);
}

// Mount the given disk at a temporary location, returning the mount location.
- (NSURL *)mountDisk:(DADiskRef)disk {
  dispatch_semaphore_t sema = dispatch_semaphore_create(0);
  NSString *uuid = [[NSProcessInfo processInfo] globallyUniqueString];
  NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:uuid];
  NSURL *directoryURL = [NSURL fileURLWithPath:path isDirectory:YES];
  [[NSFileManager defaultManager] createDirectoryAtURL:directoryURL
                           withIntermediateDirectories:YES
                                            attributes:nil
                                                 error:NULL];
  DADiskMount(disk, (__bridge CFURLRef)directoryURL, 0, &MountUnmountEjectCallback,
              (__bridge void *)sema);
  if (dispatch_semaphore_wait(sema, dispatch_time(DISPATCH_TIME_NOW, 5 * 60 * NSEC_PER_SEC))) {
    NSLog(@"%@ Timed out while mounting disk", self);
    return nil;
  }
  [self disableSpotlight:directoryURL];
  NSDictionary *desc = CFBridgingRelease(DADiskCopyDescription(disk));
  return desc[(__bridge NSString *)kDADiskDescriptionVolumePathKey];
}

// Unmount a given disk/whole disk.
- (void)unmountDisk:(DADiskRef)disk withOptions:(DADiskUnmountOptions)options {
  dispatch_semaphore_t sema = dispatch_semaphore_create(0);
  if (options & kDADiskUnmountOptionWhole) {
    disk = DADiskCopyWholeDisk(disk);
  }
  DADiskUnmount(disk, options, &MountUnmountEjectCallback, (__bridge void *)sema);
  if (dispatch_semaphore_wait(sema, dispatch_time(DISPATCH_TIME_NOW, 5 * 60 * NSEC_PER_SEC))) {
    NSLog(@"%@ Timed out while unmounting disk: %@", self, disk);
  }
  if (options & kDADiskUnmountOptionWhole) {
    CFRelease(disk);
  }
}

// Eject the whole disk for a given diskref.
- (void)ejectDisk:(DADiskRef)disk {
  dispatch_semaphore_t sema = dispatch_semaphore_create(0);
  DADiskRef wholeDisk = DADiskCopyWholeDisk(disk);
  DADiskEject(wholeDisk, kDADiskEjectOptionDefault, &MountUnmountEjectCallback,
              (__bridge void *)sema);
  if (dispatch_semaphore_wait(sema, dispatch_time(DISPATCH_TIME_NOW, 5 * 60 * NSEC_PER_SEC))) {
    NSLog(@"%@ Timed out while unmounting disk", self);
  }
  CFRelease(wholeDisk);
}

// spotlight seems to start up very quickly once the disk is mounted.  Tell it to stop.
- (int)disableSpotlight:(NSURL *)mountPoint {
  NSLog(@"Running /usr/bin/mdutil -i off %@", mountPoint.path);
  NSTask *mdUtil = [[NSTask alloc] init];
  mdUtil.standardOutput = [NSPipe pipe];
  mdUtil.launchPath = @"/usr/bin/mdutil";
  mdUtil.arguments = @[ @"-i", @"off", @"-d", mountPoint.path ];
  [mdUtil launch];
  [mdUtil waitUntilExit];
  NSData *sout = [[mdUtil.standardOutput fileHandleForReading] readDataToEndOfFile];
  if (mdUtil.terminationStatus != 0) {
    NSLog(@"Error from mdUtil(%d): %@", mdUtil.terminationStatus,
          [[NSString alloc] initWithData:sout encoding:NSUTF8StringEncoding]);
  }
  return mdUtil.terminationStatus;
}

// log info on dissents from various callback routines.
void LogDiskAndDissenter(DADiskRef disk, DADissenterRef dissenter) {
  if (dissenter) {
    NSLog(@"Dissenter: %@", CFBridgingRelease(CFCopyDescription(dissenter)));
  }
  if (disk) {
    NSLog(@"Disk: %@", CFBridgingRelease(CFCopyDescription(disk)));
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
  imageInfo[@"ImageHash"] = self.image.sha512 ?: self.image.sha256;
  imageInfo[@"Imager"] = @"Restor.app";
  imageInfo[@"ImagerVersion"] =
      [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];

  NSError *error;
  NSData *plistData = [NSPropertyListSerialization dataWithPropertyList:imageInfo
                                                                 format:NSPropertyListXMLFormat_v1_0
                                                                options:0
                                                                  error:&error];
  if ([plistData writeToURL:imageInfoURL options:NSDataWritingAtomic error:&error]) {
    NSLog(@"%@ Successfully written: %@", self, imageInfoURL.path);
  } else {
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

- (int)runPostScriptWithMountURL:(NSURL *)mountURL error:(NSError **)error {
  if (!self.image.postScript) return 0;

  NSString *uuid = [[NSProcessInfo processInfo] globallyUniqueString];
  NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:uuid];
  NSURL *directoryURL = [NSURL fileURLWithPath:path isDirectory:YES];

  NSError *err;
  NSFileManager *fm = [NSFileManager defaultManager];

  // Paranoid about privileged escalation. If the dir already exists, really remove it.
  BOOL isDir = NO;
  if ([fm fileExistsAtPath:directoryURL.path isDirectory:&isDir] && isDir) {
    if (![fm removeItemAtURL:directoryURL error:&err]) {
      if (error) *error = err;
      return 1;
    }
  }

  if (![fm createDirectoryAtURL:directoryURL
    withIntermediateDirectories:YES
                     attributes:nil
                          error:&err]) {
    if (error) *error = err;
    return 1;
  }

  NSString *postscript = [directoryURL.path stringByAppendingPathComponent:@"postscript"];
  if (![self.image.postScript writeToFile:postscript
                               atomically:YES
                                 encoding:NSUTF8StringEncoding
                                    error:&err]) {
    if (error) *error = err;
    return 1;
  }

  if (![fm setAttributes:@{ NSFilePosixPermissions : @0700 } ofItemAtPath:postscript error:&err]) {
    if (error) *error = err;
    return 1;
  }

  NSTask *script = [[NSTask alloc] init];
  script.launchPath = postscript;
  script.arguments = @[ mountURL.path ];
  script.standardError = [NSPipe pipe];

  NSLog(@"%@ Launching post script: %@", self, postscript);

  [script launch];
  [script waitUntilExit];

  NSData *data = [script.standardError fileHandleForReading].availableData;
  NSString *standardError = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
  if (standardError.length && error) {
    NSDictionary *info = @{ NSLocalizedDescriptionKey: standardError };
    *error = [NSError errorWithDomain:@"com.google.corp.restord" code:666 userInfo:info];
  }

  [fm removeItemAtURL:directoryURL error:NULL];

  return script.terminationStatus;
}

@end
