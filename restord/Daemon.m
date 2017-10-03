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

#import "Daemon.h"

#import <MOLXPCConnection/MOLXPCConnection.h>

#import "ImageSessionServer.h"


@implementation Daemon

- (void)helperVersion:(void (^)(NSInteger version))reply {
  reply([[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"] integerValue]);
}

- (void)applyImage:(Image *)image
            toDisk:(Disk *)targetDisk
      withListener:(NSXPCListenerEndpoint *)listener {
  if (!image || !targetDisk || !listener) {
    NSLog(@"Client sent invalid %@ message: %@ %@ %@. Ignoring.",
          NSStringFromSelector(_cmd), image, targetDisk, listener);
    return;
  };

  MOLXPCConnection *clientConn = [[MOLXPCConnection alloc] initClientWithListener:listener];
  NSXPCInterface *r = [NSXPCInterface interfaceWithProtocol:@protocol(RestorClientProtocol)];
  clientConn.remoteInterface = r;

  ImageSessionServer *is = [[ImageSessionServer alloc] initWithImage:image
                                                          targetDisk:targetDisk
                                                              client:clientConn];

  // If the connection is invalidated either the user decided to cancel or the GUI went away,
  // so cancel the image in progress. The WEAKIFY/STRONGIFY is necessary to avoid keeping
  // the `is` object around too long.
  WEAKIFY(is);
  clientConn.invalidationHandler = ^{
    STRONGIFY(is);
    [is cancelImaging];  // possible no-op
  };
  [clientConn resume];

  // The imaging process needs to be in the background otherwise multiple sessions won't
  // be able to start at once. The IS object is kept alive until beginImaging returns.
  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
    [is beginImaging];
  });
}

@end
