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

#import "DiskFilter.h"

#import "Disk.h"

@implementation DiskFilter

+ (BOOL)filterDisk:(Disk *)disk {
  if (disk.isInternal || disk.isWhole || disk.isNetwork || !disk.bsdName) return NO;
  if ([disk.mediaName isEqualToString:@"Recovery HD"]) {
    NSLog(@"DiskFilter, ignoring Recovery partition: %@", disk.bsdName);
    return NO;
  } else if ([disk.mediaName isEqualToString:@"Booter"]) {
    NSLog(@"DiskFilter, ignoring Booter partition: %@", disk.bsdName);
    return NO;
  } else if ([disk.volName isEqualToString:@"EFI"]) {
    NSLog(@"DiskFilter, ignoring EFI partition: %@", disk.bsdName);
    return NO;
  } else if ([disk.protocol isEqualToString:@"Virtual Interface"]) {
    NSLog(@"DiskFilter, ignoring virtual disk: %@", disk.bsdName);
    return NO;
  } else if ([disk.volKind isEqualToString:@"apfs"] && disk.isLeaf) {
    NSLog(@"DiskFilter, ignoring apfs volume: %@", disk.bsdName);
    return NO;
  }

  NSLog(@"DiskFilter, found available disk: %@ (%@)", disk.bsdName, disk.mediaName);
  return YES;
}

@end
