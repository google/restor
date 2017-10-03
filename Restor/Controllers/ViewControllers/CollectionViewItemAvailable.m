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

#import "CollectionViewItemAvailable.h"

// The border width for a selected disk in the collection view
static const float kSelectedBorderWidth = 3.0;

@implementation CollectionViewItemAvailable

- (void)viewDidLoad {
  [super viewDidLoad];

  self.view.wantsLayer = YES;
  self.view.layer.borderWidth = 0.0;
  self.view.layer.borderColor = [[NSColor selectedControlColor] CGColor];
  self.view.layer.cornerRadius = 4;
}

- (void)setSelected:(BOOL)selected {
  [super setSelected:selected];
  self.view.layer.borderWidth = selected ? kSelectedBorderWidth : 0.0;
}

@end
