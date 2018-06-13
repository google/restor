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

#import "ImageCacheController.h"

#import "HashUtils.h"
#import "Image.h"

@implementation ImageCacheController

- (instancetype)initWithImages:(NSArray<Image *> *)images {
  self = [super init];
  if (self) {
    _images = images;
  }
  return self;
}

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
      if ([image.name isEqualToString:imageName]) {
        // Validate the image hash
        NSString *checksum, *expected;
        if (image.sha512) {
          expected = image.sha512;
          checksum = [HashUtils checksumForFileURL:url algorithm:SHA512];
        } else if (image.sha256) {
          expected = image.sha256;
          checksum = [HashUtils checksumForFileURL:url algorithm:SHA256];
        }
        if (expected && [expected isEqualToString:checksum]) {
          isValid = YES;
        }
        break;
      }
    }

    if (!isValid) {
      [fm removeItemAtURL:url error:NULL];
    }
  }
}

#pragma mark Helpers

- (NSURL *)cachePath {
  NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
  NSString *bundleName = [[NSBundle mainBundle] bundleIdentifier];
  return [NSURL fileURLWithPath:[paths[0] stringByAppendingPathComponent:bundleName]];
}

- (NSURL *)localPathForImage:(Image *)image {
  NSString *fileName = [image.name stringByAppendingString:@".dmg"];
  return [self.cachePath URLByAppendingPathComponent:fileName];
}

@end
