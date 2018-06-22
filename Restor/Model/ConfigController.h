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
@class MOLXPCConnection;

// ConfigController parses a configuration plist, storing an array of image objects, verifying
// the download state of images and deleting previously downloaded images that no longer exist.
@interface ConfigController : NSObject

// List of images found in the config file.
@property(readonly) NSArray<Image *> *images;

// Connection to the helper tool.
@property(readonly, nonatomic) MOLXPCConnection *helperConnection;

// Download & parse config and validate image cache.
- (NSError *)checkConfiguration;

// Connects to the helper tool, setting helperConnection property.
- (NSError *)connectToHelperTool;

// Validates that the images stored on disk still exist in the image array provided at
// initialization and that their hashes match. This might take a while as it involves
// enumerating files on disk and hashing them.
- (void)validateImageCache;

// Returns the local filepath where a previously downloaded image would be located.
- (NSURL *)localPathForImage:(Image *)image;

@end
