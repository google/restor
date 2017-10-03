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

#import "HelperToolUtils.h"

#import <ServiceManagement/ServiceManagement.h>

#import <MOLXPCConnection/MOLXPCConnection.h>

#import "ErrorMaker.h"
#import "RestorProtocol.h"

static NSString *const kHelperToolLabel = @"com.google.corp.restord";

@implementation HelperToolUtils

/**
  Connect to privileged helper tool, installing it if necessary.

  @return MOLXPCConnection, the configured and established helper tool connection.
*/
+ (MOLXPCConnection *)connectToHelperToolWithError:(NSError **)error {
  dispatch_semaphore_t sema = dispatch_semaphore_create(0);

  __block BOOL correctHelperInstalled = NO;

  __block MOLXPCConnection *c = [self establishConnection];
  WEAKIFY(c);
  c.acceptedHandler = ^{
    STRONGIFY(c);
    [[c remoteObjectProxy] helperVersion:^(NSInteger version) {
      // Helper is installed, validate version.
      if (version == [self embeddedHelperVersion]) {
        correctHelperInstalled = YES;
      } else {
        NSLog(@"Installed helper tool doesn't match current version");
      }
      dispatch_semaphore_signal(sema);
    }];
  };
  c.invalidationHandler = ^{
    dispatch_semaphore_signal(sema);
  };
  [c resume];

  dispatch_semaphore_wait(sema, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));

  if (correctHelperInstalled) return c;

  if (![self installHelperToolWithError:error]) return nil;

  c = [self establishConnection];
  c.acceptedHandler = ^{
    dispatch_semaphore_signal(sema);
  };
  [c resume];

  if (dispatch_semaphore_wait(sema, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC))) {
    c = nil;
  }

  return c;
}

+ (NSInteger)embeddedHelperVersion {
  NSString *bndlPath = [[NSBundle mainBundle] bundlePath];
  NSString *currentHelperPath =
  [bndlPath stringByAppendingPathComponent:@"Contents/Library/LaunchServices"];
  currentHelperPath = [currentHelperPath stringByAppendingPathComponent:kHelperToolLabel];
  NSURL *url = [NSURL fileURLWithPath:currentHelperPath];
  NSDictionary *infoDict = CFBridgingRelease(
      CFBundleCopyInfoDictionaryForURL((__bridge CFURLRef)url));
  return [infoDict[@"CFBundleVersion"] integerValue];
}

/**
 Attempts to install and load the privileged helper tool if necessary.

 @return YES if helper tool is installed.
*/
+ (BOOL)installHelperToolWithError:(NSError **)error {
  // Using kAuthorizationRightExecute instead of kSMRightBlessPrivilegedHelper so that the
  // prompt string can be customized better.
  AuthorizationItem authItem = { kAuthorizationRightExecute, 0, NULL, 0 };
  AuthorizationRights authRights = { 1, &authItem };

  AuthorizationFlags flags = (kAuthorizationFlagDefaults |
                              kAuthorizationFlagInteractionAllowed |
                              kAuthorizationFlagPreAuthorize |
                              kAuthorizationFlagExtendRights);

  NSString *promptText = @"Restor needs to install a helper tool.\n";
  AuthorizationItem dialogConfiguration[1] = {
      kAuthorizationEnvironmentPrompt, promptText.length, (char *)[promptText UTF8String], 0 };
  AuthorizationEnvironment authorizationEnvironment = { 1, dialogConfiguration };

  AuthorizationRef authRef = NULL;
  OSStatus status = AuthorizationCreate(&authRights, &authorizationEnvironment, flags, &authRef);

  if (status != errAuthorizationSuccess) {
    if (error) {
      *error = [ErrorMaker errorWithCode:76
                                  string:@"Unable to authenticate to install helper tool"];
    }
    return NO;
  }

  // This installs the helper tool in /Library/PrivilegedHelperTools and the launchd.plist
  // in /Library/LaunchDaemons, then loads the job.
  CFErrorRef cfErrorRef;
  BOOL result = SMJobBless(
      kSMDomainSystemLaunchd, (__bridge CFStringRef)kHelperToolLabel, authRef, &cfErrorRef);
  *error = CFBridgingRelease(cfErrorRef);

  if (!result || *error) {
    NSLog(@"An error occurred installing the privileged helper tool: %@", *error);
  }

  return result;
}

+ (MOLXPCConnection *)establishConnection {
  MOLXPCConnection *c = [[MOLXPCConnection alloc] initClientWithName:kHelperToolLabel
                                                          privileged:YES];
  c.remoteInterface = [NSXPCInterface interfaceWithProtocol:@protocol(RestorHelperProtocol)];
  return c;
}

@end
