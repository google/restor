/// Copyright 2018 Google LLC. All rights reserved.
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

#import "ConfigController.h"

#import <MOLAuthenticatingURLSession/MOLAuthenticatingURLSession.h>

#import "ErrorMaker.h"
#import "HashUtils.h"
#import "HelperToolUtils.h"
#import "Image.h"
#import "MainViewController.h"

static NSString *kPreferenceDomain = @"com.google.corp.restor";
static NSString *kConfigURLKey = @"ConfigURL";
static NSString *kCustomImageKey = @"CustomImage";
static NSString *kConfigCheckIntervalKey = @"ConfigCheckInterval";
static NSString *kConfigDiskPredicateKey = @"DiskFilterPredicate";

@class MOLXPCConnection;

@interface ConfigController ()
@property NSArray<Image *> *images;
@property(nonatomic) MOLXPCConnection *helperConnection;
// The session to use when fetching the configuration.
@property NSURLSession *session;
@property NSUserDefaults *defaults;
@end

@implementation ConfigController

- (instancetype)init {
  self = [super init];
  if (self) {
    self.session = [[[MOLAuthenticatingURLSession alloc] init] session];
    self.images = [NSArray array];
    self.defaults = [[NSUserDefaults alloc] initWithSuiteName:kPreferenceDomain];
    [self.defaults registerDefaults:@{
      // Set the default value for the config check interval to be 15 minutes.
      kConfigCheckIntervalKey : @(15 * 60.0),
    }];
  }
  return self;
}

// Downloads the config from the config URL and applies any changes in it.
- (NSError *)checkConfiguration {
  NSError *error;
  NSURL *url = [NSURL URLWithString:[self stringPreferenceForKey:kConfigURLKey]];
  NSData *configData = [self downloadConfigFromURL:url error:&error];
  if (error) return error;  // status: @"Failed to download configuration"

  NSDictionary *configDict =
      [NSPropertyListSerialization propertyListWithData:configData
                                                options:NSPropertyListImmutable
                                                 format:NULL
                                                  error:&error];
  if (error) {
    return [ErrorMaker errorWithCode:17
                         description:@"Failed to parse configuration"
                              reason:error.localizedDescription];
  }

  NSOrderedSet<Image *> *newImages = [self parseConfig:configDict];
  if (!newImages.count) {
    return [ErrorMaker errorWithCode:17
                         description:@"Failed to parse configuration"
                              reason:@"No images found in configuration"];
  }

  // Delete any images from the cache that weren't in the new config.
  NSFileManager *fm = [NSFileManager defaultManager];
  for (Image *image in self.images) {
    if (![newImages containsObject:image]) {
      NSLog(@"deleting %@ from cache because no longer in config", image.name);
      [fm removeItemAtURL:image.localURL error:NULL];
    }
  }

  self.images = [NSArray arrayWithArray:newImages.array];
  return nil;
}

- (NSTimeInterval)configCheckInterval {
  return [self doublePreferenceForKey:kConfigCheckIntervalKey];
}

- (NSArray<NSPredicate *> *)diskFilterPredicates {
  // The default disk filter predicates:
  //   No disks with empty BSD Names (disk0s2, etc.)
  //   No internal, whole or network disks
  //   No 'Recovery HD' or 'Booter' volumes
  //   No EFI, Preboot, Recovery or VM volumes
  //   No "virtual interface" disks (disk images)
  //   No APFS leaf disks
  NSArray *defaultPredicates = @[
    @"bsdName.length > 0",
    @"NOT YES IN {isInternal, isWhole, isNetwork}",
    @"NOT mediaName IN {'Recovery HD', 'Booter'}",
    @"NOT volName IN {'EFI', 'Preboot', 'Recovery', 'VM'}",
    @"NOT protocol IN {'Virtual Interface'}",
    @"volKind != 'apfs' OR isLeaf = NO",
  ];

  NSMutableArray *predicates = [NSMutableArray array];
  for (NSString *p in defaultPredicates) {
    [predicates addObject:[NSPredicate predicateWithFormat:p]];
  }

  NSString *customPredicate = [self stringPreferenceForKey:kConfigDiskPredicateKey];
  if (customPredicate.length) {
    [predicates addObject:[NSPredicate predicateWithFormat:customPredicate]];
  }

  return predicates;
}

#pragma mark Configuration File

// Returns an ordered set of images based on the given configuration dictionary.
- (NSOrderedSet<Image *> *)parseConfig:(NSDictionary *)d {
  NSMutableOrderedSet<Image *> *images = [NSMutableOrderedSet orderedSet];
  for (id o in d[@"Images"]) {
    if (![o isKindOfClass:[NSDictionary class]]) {
      NSLog(@"Parsing config file, found non-dictionary in Images array.");
      continue;
    }
    Image *image = [[Image alloc] initWithDictionary:(NSDictionary *)o];
    if ([image.name isEqualToString:@"Custom Image"]) continue;
    [images addObject:image];
  }
  if ([self boolPreferenceForKey:kCustomImageKey]) {
    Image *ci = [[Image alloc] initWithDictionary:@{@"Name" : @"Custom Image", @"URL" : @"/"}];
    [images addObject:ci];
  }
  return images;
}

- (NSData *)downloadConfigFromURL:(NSURL *)configURL error:(NSError **)outError {
  __block NSData *configData;
  __block NSError *error;

  dispatch_semaphore_t sema = dispatch_semaphore_create(0);

  [[self.session dataTaskWithURL:configURL
               completionHandler:^(NSData *data, NSURLResponse *response, NSError *e) {
                 if (e) {
                   error = [ErrorMaker errorWithCode:18
                                         description:@"Failed to download configuration"
                                              reason:e.localizedDescription];
                   dispatch_semaphore_signal(sema);
                   return;
                 }
                 NSInteger statusCode = [(NSHTTPURLResponse *)response statusCode];
                 if (statusCode != 200 || !data) {
                   NSString *reason = [NSString stringWithFormat:@"HTTP Error: %ld", statusCode];
                   error = [ErrorMaker errorWithCode:18
                                         description:@"Failed to download configuration"
                                              reason:reason];
                   dispatch_semaphore_signal(sema);
                   return;
                 }
                 configData = data;
                 dispatch_semaphore_signal(sema);
               }] resume];

  if (dispatch_semaphore_wait(sema, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC))) {
    error = [ErrorMaker errorWithCode:19
                          description:@"Failed to download configuration"
                               reason:@"Timed out while downloading config"];
  }

  if (outError) *outError = error;

  return configData;
}

#pragma mark Helper Tool

- (NSError *)connectToHelperTool {
  NSLog(@"connecting to helper tool");
  NSError *error;
  self.helperConnection = [HelperToolUtils connectToHelperToolWithError:&error];
  return error;
}

#pragma mark Image Cache

- (void)validateImageCache {
  NSFileManager *fm = [NSFileManager defaultManager];
  NSDirectoryEnumerator *dirEnum = [fm enumeratorAtURL:self.cachePath
                            includingPropertiesForKeys:nil
                                               options:0
                                          errorHandler:NULL];
  for (NSURL *url in dirEnum) {
    if (![url.path.pathExtension isEqualToString:@"dmg"]) continue;
    NSString *imageName = [[[url path] lastPathComponent] stringByDeletingPathExtension];
    BOOL isValid = NO;

    for (Image *image in self.images) {
      if (image.custom) continue;  // don't validate or remove custom user images
      if ([image.name isEqualToString:imageName]) {
        // Validate the image hash
        NSString *checksum, *expected;
        if (image.sha512) {
          expected = image.sha512;
          checksum = [HashUtils checksumForFileURL:url algorithm:HashAlgorithmSHA512];
        } else if (image.sha256) {
          expected = image.sha256;
          checksum = [HashUtils checksumForFileURL:url algorithm:HashAlgorithmSHA256];
        }
        if (expected && [expected isEqualToString:checksum]) {
          isValid = YES;
        }
        break;
      }
    }

    if (!isValid) {
      NSLog(@"deleting %@ from cache because invalid", imageName);
      [fm removeItemAtURL:url error:NULL];
    }
  }
}

#pragma mark Helper methods

- (NSString *)stringPreferenceForKey:(NSString *)key {
  id value = [self.defaults valueForKey:key];
  if (![value isKindOfClass:[NSString class]]) return nil;
  return value;
}

- (BOOL)boolPreferenceForKey:(NSString *)key {
  id value = [self.defaults valueForKey:key];
  if (![value isKindOfClass:[NSNumber class]]) return NO;
  return [value boolValue];
}

- (double)doublePreferenceForKey:(NSString *)key {
  id value = [self.defaults valueForKey:key];
  if (![value isKindOfClass:[NSNumber class]]) return 0;
  return [value doubleValue];
}

- (NSURL *)cachePath {
  NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
  NSString *bundleName = [[NSBundle mainBundle] bundleIdentifier];
  return [NSURL fileURLWithPath:[paths[0] stringByAppendingPathComponent:bundleName]];
}

- (NSURL *)localPathForImage:(Image *)image {
  if (!image) return nil;
  NSString *fileName = [image.name stringByAppendingString:@".dmg"];
  return [self.cachePath URLByAppendingPathComponent:fileName];
}

@end
