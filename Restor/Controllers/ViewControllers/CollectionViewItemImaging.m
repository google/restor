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

#import "Restor/Controllers/ViewControllers/CollectionViewItemImaging.h"

#import "Common/Disk.h"
#import "Restor/Model/ImagingSession.h"

// The percentage of the progress bar is dedicated to the imaging phase. The rest is 'verifying'
static const float kImagingRatioOfTotal = 0.85;

@implementation CollectionViewItemImaging

- (void)viewWillDisappear {
  [super viewWillDisappear];
  self.imagingSession = nil;
}

- (IBAction)showError:(id)sender {
  [self presentError:self.imagingSession.lastError
          modalForWindow:self.view.window
                delegate:nil
      didPresentSelector:nil
             contextInfo:nil];
}

- (NSString *)imagingStatusString {
  switch (self.imagingSession.imagingStage) {
    case ImagingStageNotStarted:
      return NSLocalizedString(@"Starting...", nil);
    case ImagingStageImaging:
      return NSLocalizedString(@"Imaging...", nil);
    case ImagingStageInverting:
      return NSLocalizedString(@"Inverting...", nil);
    case ImagingStageVerifying:
      return NSLocalizedString(@"Verifying...", nil);
    case ImagingStageComplete:
      return NSLocalizedString(@"Complete,\nplease disconnect", nil);
    case ImagingStageError:
      return NSLocalizedString(@"Error", nil);
  }
}

- (float)progressPercent {
  switch (self.imagingSession.imagingStage) {
    case ImagingStageNotStarted:
    case ImagingStageError:
      return 0.0;
    case ImagingStageImaging:
    case ImagingStageInverting:
      return self.imagingSession.percentComplete * kImagingRatioOfTotal;
    case ImagingStageVerifying:
      return (kImagingRatioOfTotal * 100) +
          self.imagingSession.percentComplete * (1.0 - kImagingRatioOfTotal);
    case ImagingStageComplete:
      return 100.0;
  }
}

+ (NSSet *)keyPathsForValuesAffectingImagingStatusString {
  return [NSSet setWithObjects:@"imagingSession", @"imagingSession.imagingStage", nil];
}

+ (NSSet *)keyPathsForValuesAffectingProgressPercent {
  return [NSSet setWithObjects:@"imagingSession", @"imagingSession.imagingStage",
             @"imagingSession.percentComplete", nil];
}

@end
