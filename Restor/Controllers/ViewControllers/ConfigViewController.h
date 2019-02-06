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

#import <Cocoa/Cocoa.h>

/// ConfigViewController creates a ConfigController and displays the process of downloading and
/// parsing a configuration plist and verifying the state of cached images, deleting previously
/// downloaded images that no longer exist in the configuration.
@interface ConfigViewController : NSViewController
/// Set if an error occurs.
@property(readonly) NSError *error;
/// String describing current state of ConfigController.
@property(readonly) NSString *statusText;
@end
