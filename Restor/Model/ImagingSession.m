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

#import "ImagingSession.h"

#import <MOLXPCConnection/MOLXPCConnection.h>

#import "Disk.h"
#import "Image.h"
#import "RestorProtocol.h"

@interface ImagingSession ()
@property Disk *disk;
@property Image *image;
@property MOLXPCConnection *helperConn;
@property MOLXPCConnection *returnConn;

@property(readwrite) NSUInteger percentComplete;
@property(readwrite) ImagingStage imagingStage;
@property(readwrite) NSError *lastError;
@end

@implementation ImagingSession

- (instancetype)initWithImage:(Image *)image
                   targetDisk:(Disk *)disk
             helperConnection:(MOLXPCConnection *)connection {
  self = [super init];
  if (self) {
    _disk = disk;
    _image = image;
    _helperConn = connection;
  }
  return self;
}

- (void)begin {
  NSXPCListener *listener = [NSXPCListener anonymousListener];
  self.returnConn = [[MOLXPCConnection alloc] initServerWithListener:listener];
  self.returnConn.exportedInterface =
      [NSXPCInterface interfaceWithProtocol:@protocol(RestorClientProtocol)];
  self.returnConn.exportedObject = self;
  [self.returnConn resume];

  [[self.helperConn remoteObjectProxy] applyImage:self.image
                                           toDisk:self.disk
                                     withListener:listener.endpoint];
}

- (void)cancel {
  [self.returnConn invalidate];
  self.returnConn = nil;
}

#pragma mark Restor Client methods

- (void)imagingPercentage:(NSUInteger)percent {
  dispatch_async(dispatch_get_main_queue(), ^{
    self.imagingStage = ImagingStageImaging;
    self.percentComplete = percent;
  });
}

- (void)verifyingPercentage:(NSUInteger)percent {
  dispatch_async(dispatch_get_main_queue(), ^{
    self.imagingStage = ImagingStageVerifying;
    self.percentComplete = percent;
  });
}

- (void)invertingStarted {
  dispatch_async(dispatch_get_main_queue(), ^{
    self.imagingStage = ImagingStageInverting;
  });
}

- (void)imageAppliedSuccess:(BOOL)success error:(NSError *)error {
  dispatch_async(dispatch_get_main_queue(), ^{
    if (!success) {
      self.imagingStage = ImagingStageError;
      self.percentComplete = 0;
      self.lastError = error;
    } else {
      self.imagingStage = ImagingStageComplete;
      self.percentComplete = 100;
    }
  });
}

@end
