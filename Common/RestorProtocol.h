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

#import <Foundation/Foundation.h>

@class Disk;
@class Image;

/**
  Protocol implemented by the helper tool.

  Provides a single method, in which to start imaging with a listener endpoint to use
  for status updates.

  There is no method to cancel imaging as the way to do this is to invalidate the connection.
*/
@protocol RestorHelperProtocol<NSObject>

/*
  Replies with the CFBundleVersion of this helper tool.
*/
- (void)helperVersion:(void (^)(NSInteger version))reply;

/*
  Begins the process of applying a given image to a given disk.

  @param image The image to apply.
  @param targetDisk The disk to apply the image to
  @param listener A listener endpoint to use to send status updates to. Assumed to conform to
                  the RestorClientProtocol below.
*/
- (void)applyImage:(Image *)image
            toDisk:(Disk *)targetDisk
      withListener:(NSXPCListenerEndpoint *)listener;

@end

/**
  Protocol implemented by the app.

  Provides methods for the helper to provide status information back to the GUI for a particular
  imaging session.
*/
@protocol RestorClientProtocol<NSObject>

/*
  Notifies the UI that the percentage of applied image has changed.

  @param percent The new percentage of applied image.
*/
- (void)imagingPercentage:(NSUInteger)percent;

/*
  Notifies the UI that the percentage of verified image has changed.

  @param percent The new percentage of verified image.
*/
- (void)verifyingPercentage:(NSUInteger)percent;

/*
  Notifies the UI that inverting has started.
*/
- (void)invertingStarted;

/*
  Notifies the UI that imaging has completed and ASR has exited.

  @param success YES if ASR exited with 0.
  @param error An error object containing details of the error that occurred.
*/
- (void)imageAppliedSuccess:(BOOL)success error:(NSError *)error;

@end
