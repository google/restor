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

@import Cocoa;

@class ImageCacheController;

// ConfigController parses a configuration plist, storing an array of image objects, verifying
// the download state of images and deleting previously downloaded images that no longer exist.
@interface ConfigViewController : NSViewController

// The session to use when fetching the configuration.
@property IBOutlet NSURLSession *session;

@property(readonly, nonatomic) ImageCacheController *imageCacheController;

// Download & parse config, connect to helper tool, and validate image cache.
- (IBAction)attemptConfiguration:(id)sender;

@end
