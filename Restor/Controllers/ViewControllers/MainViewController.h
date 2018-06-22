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

@class ConfigController;
@class MOLXPCConnection;

/// MainViewController mananges the main window containing the collection view,
/// image selection and image/auto-image buttons.
@interface MainViewController : NSViewController <NSCollectionViewDelegate,
                                                  NSCollectionViewDataSource>

/// The configController stores images specified in a configuration plist.
@property(nonatomic) ConfigController *configController;

- (IBAction)downloadImage:(id)sender;
- (IBAction)showCachedImageInFinder:(id)sender;

@end
