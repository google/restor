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

#import "Restor/Controllers/ViewControllers/CustomImageViewController.h"

#import "Common/Image.h"

@implementation CustomImageViewController

- (IBAction)continue:(id)sender {
  if (self.imageURL.length == 0) return;
  [self dismissViewController:self];

  if (!self.completionBlock) return;

  // Create a new custom image and pass it to the completion block.
  Image *image = [[Image alloc] initWithDictionary:@{
      @"Name" : self.imageURL.pathComponents.lastObject.stringByDeletingPathExtension,
      @"URL" : self.imageURL,
      @"Custom": @YES,
  }];
  if ([image.URL.scheme isEqualToString:@"file"]) {
    image.localURL = image.URL;
  }
  self.completionBlock(image);
}

- (IBAction)cancel:(id)sender {
  [self dismissViewController:self];
  if (self.cancelBlock) self.cancelBlock();
}

@end
