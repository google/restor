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

@import Foundation;

@class Image;

///  ImageCacheController is responsible for managing the local cache of images, ensuring
///  that old or invalid images are deleted.
@interface ImageCacheController : NSObject

// Initialize with an array of images
- (instancetype)initWithImages:(NSArray<Image *> *)images NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

// Validates that the images stored on disk still exist in the image array provided at
// initialization and that their hashes match. This might take a while as it involves
// enumerating files on disk and hashing them.
- (void)validateImageCache;

- (NSURL *)localPathForImage:(Image *)image;

// The array of images that was supplied at init.
@property(readonly) NSArray<Image *> *images;


@end
