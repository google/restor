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

#import "DiskWatcher.h"

#import "Disk.h"

@import DiskArbitration;

@interface DiskWatcher ()
@property DASessionRef daSession;
@property dispatch_queue_t dispatchQueue;
@end

@implementation DiskWatcher

- (instancetype)init {
  self = [super init];
  if (self) {
    _dispatchQueue = dispatch_queue_create(
        "com.google.corp.restor.diskwatcher", DISPATCH_QUEUE_SERIAL);

  }
  return self;
}

- (void)dealloc {
  [self stopWatching];
}

- (void)beginWatching {
  self.daSession = DASessionCreate(NULL);
  DASessionSetDispatchQueue(self.daSession, self.dispatchQueue);

  DARegisterDiskAppearedCallback(
      self.daSession, NULL, diskAppearedCallback, (__bridge void *)self);
  DARegisterDiskDisappearedCallback(
      self.daSession, NULL, diskDisappearedCallback, (__bridge void *)self);
  DARegisterDiskMountApprovalCallback(
      self.daSession, NULL, diskMountApprovalCallback, (__bridge void *)self);
}

- (void)stopWatching {
  if (self.daSession) {
    DASessionSetDispatchQueue(self.daSession, NULL);  // may not be necessary
    CFRelease(self.daSession);
  }
}

#pragma mark DiskArbitration Callbacks

void diskAppearedCallback(DADiskRef disk, void *context) {
  DiskWatcher *diskWatcher = (__bridge DiskWatcher *)context;
  if (diskWatcher.appearCallback) {
    Disk *d = [Disk diskWithDictionary:CFBridgingRelease(DADiskCopyDescription(disk))];
    diskWatcher.appearCallback(d);
  }
}

void diskDisappearedCallback(DADiskRef disk, void *context) {
  DiskWatcher *diskWatcher = (__bridge DiskWatcher *)context;
  if (diskWatcher.disappearCallback) {
    Disk *d = [Disk diskWithDictionary:CFBridgingRelease(DADiskCopyDescription(disk))];
    diskWatcher.disappearCallback(d);
  }
}

DADissenterRef diskMountApprovalCallback(DADiskRef disk, void *context) {
  DiskWatcher *diskWatcher = (__bridge DiskWatcher *)context;
  BOOL dissent = NO;
  if (diskWatcher.mountApprovalCallback) {
    Disk *d = [Disk diskWithDictionary:CFBridgingRelease(DADiskCopyDescription(disk))];
    dissent = !diskWatcher.mountApprovalCallback(d);
  }
  return dissent ? DADissenterCreate(NULL, kDAReturnNotPermitted, NULL) : NULL;
}

@end
