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
@class MOLXPCConnection;

///  ImageSession represents a disk currently being imaged and manages the connection
///  to the daemon for this particular session.
@interface ImagingSession : NSObject

- (instancetype)initWithImage:(Image *)url
                   targetDisk:(Disk *)disk
             helperConnection:(MOLXPCConnection *)connection;

- (void)begin;
- (void)cancel;

typedef NS_ENUM(NSInteger, ImagingStage) {
  ImagingStageNotStarted,
  ImagingStageImaging,
  ImagingStageInverting,
  ImagingStagePostScript,
  ImagingStageVerifying,
  ImagingStageComplete,
  ImagingStageError,
};

@property(readonly) NSUInteger percentComplete;
@property(readonly) ImagingStage imagingStage;
@property(readonly) NSError *lastError;

@end
