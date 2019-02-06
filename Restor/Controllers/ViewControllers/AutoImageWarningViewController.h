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

///  Controls a modal view shown before auto-imaging mode is enabled
@interface AutoImageWarningViewController : NSViewController

- (IBAction)continue:(id)sender;
- (IBAction)cancel:(id)sender;

@property(copy) void (^completionBlock)(void);
@property(copy) void (^cancelBlock)(void);
@end
