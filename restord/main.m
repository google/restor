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

@import Foundation;

#import <MOLXPCConnection/MOLXPCConnection.h>

#import "Daemon.h"
#import "RestorProtocol.h"

int main(int argc, const char * argv[]) {
  @autoreleasepool {
    MOLXPCConnection *xpcListener =
        [[MOLXPCConnection alloc] initServerWithName:@"com.google.corp.restord"];
    xpcListener.exportedInterface =
        [NSXPCInterface interfaceWithProtocol:@protocol(RestorHelperProtocol)];
    xpcListener.exportedObject = [[Daemon alloc] init];
    xpcListener.acceptedHandler = ^{
      NSLog(@"Client connected.");
    };
    xpcListener.invalidationHandler = ^{
      NSLog(@"Client disconnected, exiting.");
      exit(0);
    };

    [xpcListener resume];

    dispatch_main();
  }
  return 0;
}
