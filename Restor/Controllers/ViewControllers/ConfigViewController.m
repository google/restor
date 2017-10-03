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

#import "ConfigViewController.h"

#import <MOLAuthenticatingURLSession/MOLAuthenticatingURLSession.h>

#import "ErrorMaker.h"
#import "HelperToolUtils.h"
#import "Image.h"
#import "ImageCacheController.h"
#import "MainViewController.h"

static NSString *kPreferenceDomain = @"com.google.corp.restor";
static NSString *kConfigURLKey = @"ConfigURL";
static NSString *kCustomImageKey = @"CustomImage";


@class MOLXPCConnection;

@interface ConfigViewController ()
@property NSMutableArray<Image *> *images;

@property NSError *error;

@property NSString *loadingField;
@end

@implementation ConfigViewController

- (void)viewDidAppear {
  [super viewDidAppear];

  self.loadingField = NSLocalizedString(@"Downloading configuration...", nil);

  if (!self.session) {
    self.session = [[[MOLAuthenticatingURLSession alloc] init] session];
  }

  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
    NSError *error;

    NSURL *u = [NSURL URLWithString:[self stringPreferenceForKey:kConfigURLKey]];
    NSData *configData = [self downloadConfigFromURL:u error:&error];
    if ([self showError:error withHeader:@"Failed to download configuration"]) return;

    NSDictionary *configDict =
        [NSPropertyListSerialization propertyListWithData:configData
                                                  options:NSPropertyListImmutable
                                                   format:NULL
                                                    error:&error];
    if ([self showError:error
             withHeader:NSLocalizedString(@"Failed to parse configuration", nil)]) return;

    error = [self parseConfig:configDict];
    if ([self showError:error
             withHeader:NSLocalizedString(@"Failed to parse configuration", nil)]) return;

    MOLXPCConnection *helperConnection = [self connectToHelperToolWithError:&error];
    if ([self showError:error
             withHeader:NSLocalizedString(@"Failed to connect to helper tool", nil)]) return;

    [self validateImageCache];

    dispatch_async(dispatch_get_main_queue(), ^{
      NSTabViewController *tvc = (NSTabViewController *)self.parentViewController;
      NSInteger nextIndex = tvc.selectedTabViewItemIndex + 1;
      MainViewController *nextView =
          (MainViewController *)[tvc.childViewControllers objectAtIndex:nextIndex];

      nextView.URLSession = self.session;
      nextView.imageCacheController = self.imageCacheController;
      nextView.helperConnection = helperConnection;

      tvc.selectedTabViewItemIndex = nextIndex;
    });
  });
}

- (NSError *)parseConfig:(NSDictionary *)d {
  self.images = [NSMutableArray array];

  for (id o in d[@"Images"]) {
    if (![o isKindOfClass:[NSDictionary class]]) {
      NSLog(@"Parsing config file, found non-dictionary in Images array.");
      continue;
    }
    Image *image = [[Image alloc] initWithDictionary:(NSDictionary *)o];
    if ([image.name isEqualToString:@"Custom Image"]) continue;
    [self.images addObject:image];
  }

  if ([self boolPreferenceForKey:kCustomImageKey]) {
    NSDictionary *d = @{
      @"Name" : @"Custom Image",
      @"URL" : @"/"
    };
    Image *ci = [[Image alloc] initWithDictionary:d];
    [self.images addObject:ci];
  }

  if (!self.images.count) {
    return [ErrorMaker errorWithCode:17
                              string:NSLocalizedString(@"No images found in configuration", nil)];
  }

  return nil;
}

- (NSData *)downloadConfigFromURL:(NSURL *)configURL error:(NSError **)error {
  __block NSData *configData;

  dispatch_semaphore_t sema = dispatch_semaphore_create(0);

  [[self.session dataTaskWithURL:configURL completionHandler:^(NSData *data,
                                                               NSURLResponse *response,
                                                               NSError *e) {
    if (e) {
      *error = e;
      dispatch_semaphore_signal(sema);
      return;
    }
    NSInteger statusCode = [(NSHTTPURLResponse *)response statusCode];
    if (statusCode != 200 || !data) {
      NSString *errorStr = [NSString stringWithFormat:@"HTTP Error: %ld", statusCode];
      *error = [ErrorMaker errorWithCode:18 string:errorStr];
      dispatch_semaphore_signal(sema);
      return;
    }
    configData = data;
    dispatch_semaphore_signal(sema);
  }] resume];

  if (dispatch_semaphore_wait(sema, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC))) {
    *error = [ErrorMaker errorWithCode:19 string:@"Timed out while downloading config"];
  }

  return configData;
}

- (void)validateImageCache {
  dispatch_async(dispatch_get_main_queue(), ^{
    self.loadingField = @"Validating image cache...";
  });

  _imageCacheController = [[ImageCacheController alloc] initWithImages:self.images];
  [_imageCacheController validateImageCache];
}

- (MOLXPCConnection *)connectToHelperToolWithError:(NSError **)error {
  dispatch_async(dispatch_get_main_queue(), ^{
    self.loadingField = @"Connecting to helper tool...";
  });

  return [HelperToolUtils connectToHelperToolWithError:error];
}

- (BOOL)showError:(NSError *)error withHeader:(NSString *)header {
  dispatch_async(dispatch_get_main_queue(), ^{
    self.loadingField = header;
    self.error = error;
  });
  return error != nil;
}

- (id)preferenceForKey:(NSString *)key {
  static NSUserDefaults *defaults;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    defaults = [[NSUserDefaults alloc] initWithSuiteName:kPreferenceDomain];
  });
  return [defaults valueForKey:key];
}

- (NSString *)stringPreferenceForKey:(NSString *)key {
  id value = [self preferenceForKey:key];
  if (![value isKindOfClass:[NSString class]]) return nil;
  return value;
}

- (BOOL)boolPreferenceForKey:(NSString *)key {
  id value = [self preferenceForKey:key];
  if (![value isKindOfClass:[NSNumber class]]) return NO;
  return [value boolValue];
}

@end
