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

@class Disk;
@class Image;
@class MOLXPCConnection;

@interface ImageSessionServer : NSObject

/**
  Designated initializer.

  @param source The source of the image to use
  @param targetDisk The destination disk/partition
  @param conn The XPC connection back to the client.
*/
- (nullable instancetype)initWithImage:(nonnull Image *)source
                            targetDisk:(nonnull Disk *)targetDisk
                                client:(nonnull MOLXPCConnection *)conn NS_DESIGNATED_INITIALIZER;

/**
  Unavailable, see initWithSource:destination:client
*/
- (nullable instancetype)init NS_UNAVAILABLE;

/**
  Begin the imaging process, reporting progress and final status to the configured client.
*/
- (void)beginImaging;

/**
  Cancel the imaging process.
*/
- (void)cancelImaging;

@end
