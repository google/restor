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

#import "Restor/Controllers/ViewControllers/ConfigViewController.h"

#import <MOLAuthenticatingURLSession/MOLAuthenticatingURLSession.h>

#import "Restor/Controllers/ViewControllers/MainViewController.h"
#import "Restor/Model/ConfigController.h"

@class MOLXPCConnection;

@interface ConfigViewController ()
// configController is used to do the actual configuration.  It is passed on to MainViewController.
@property ConfigController *configController;
@property NSError *error;
@property NSString *statusText;
@end

@implementation ConfigViewController

- (void)viewDidAppear {
  [super viewDidAppear];

  if (!self.configController) {
    self.configController = [[ConfigController alloc] init];
  }

  [self attemptConfiguration:self];
}

- (IBAction)attemptConfiguration:(id)sender {
  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
    [self setVisibleError:nil];  // reset any previously displayed error

    [self setStatus:@"Downloading configuration..."];
    NSError *error = [self.configController checkConfiguration];
    if (error) {
      [self setVisibleError:error];
      return;
    }

    [self setStatus:@"Connecting to helper tool..."];
    error = [self.configController connectToHelperTool];
    if (error) {
      [self setVisibleError:error];
      return;
    }

    [self setStatus:@"Validating image cache..."];
    [self.configController validateImageCache];

    dispatch_async(dispatch_get_main_queue(), ^{
      NSTabViewController *tvc = (NSTabViewController *)self.parentViewController;
      NSInteger nextIndex = tvc.selectedTabViewItemIndex + 1;
      MainViewController *nextView = [tvc.childViewControllers objectAtIndex:nextIndex];
      nextView.configController = self.configController;
      tvc.selectedTabViewItemIndex = nextIndex;
    });
  });
}

- (void)setStatus:(NSString *)status {
  dispatch_async(dispatch_get_main_queue(), ^{
    self.statusText = NSLocalizedString(status, nil);
  });
}

- (void)setVisibleError:(NSError *)error {
  dispatch_async(dispatch_get_main_queue(), ^{
    self.statusText = error.localizedDescription;
    self.error = error;
  });
}

@end
