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

#import "Disk.h"

@implementation Disk

+ (instancetype)diskWithDictionary:(NSDictionary *)dict {
  return [[self alloc] initWithDictionary:dict];
}

- (instancetype)initWithDictionary:(NSDictionary *)dict {
  self = [super init];
  if (self) {
    _bsdName = dict[(__bridge NSString *)kDADiskDescriptionMediaBSDNameKey];
    _volName = dict[(__bridge NSString *)kDADiskDescriptionVolumeNameKey];
    _volKind = dict[(__bridge NSString *)kDADiskDescriptionVolumeKindKey];
    _mediaName = dict[(__bridge NSString *)kDADiskDescriptionMediaNameKey];
    _mediaContent = dict[(__bridge NSString *)kDADiskDescriptionMediaContentKey];
    _diskSize = dict[(__bridge NSString *)kDADiskDescriptionMediaSizeKey];
    _protocol = dict[(__bridge NSString *)kDADiskDescriptionDeviceProtocolKey];
    _isWhole = [dict[(__bridge NSString *)kDADiskDescriptionMediaWholeKey] boolValue];
    _isNetwork = [dict[(__bridge NSString *)kDADiskDescriptionVolumeNetworkKey] boolValue];
    _isInternal = [dict[(__bridge NSString *)kDADiskDescriptionDeviceInternalKey] boolValue];
    _isLeaf = [dict[(__bridge NSString *)kDADiskDescriptionMediaLeafKey] boolValue];
  }
  return self;
}

- (BOOL)isEqual:(id)other {
  if (self == other) return YES;
  if (![other isKindOfClass:[Disk class]]) return NO;

  Disk *o = other;
  return [self.bsdName isEqual:o.bsdName] && [self.diskSize isEqual:o.diskSize];
}

- (NSUInteger)hash {
  NSUInteger prime = 31;
  NSUInteger result = 1;
  result = prime * result + [self.bsdName hash];
  result = prime * result + [self.diskSize hash];
  return result;
}

#pragma mark NSSecureCoding

- (void)encodeWithCoder:(NSCoder *)coder {
  [coder encodeObject:self.bsdName forKey:@"bsdName"];
  [coder encodeObject:self.volName forKey:@"volName"];
  [coder encodeObject:self.volKind forKey:@"volKind"];
  [coder encodeObject:self.mediaName forKey:@"mediaName"];
  [coder encodeObject:self.mediaContent forKey:@"mediaContent"];
  [coder encodeObject:self.diskSize forKey:@"diskSize"];
  [coder encodeObject:self.protocol forKey:@"protocol"];
  [coder encodeObject:@(self.isWhole) forKey:@"isWhole"];
  [coder encodeObject:@(self.isNetwork) forKey:@"isNetwork"];
  [coder encodeObject:@(self.isInternal) forKey:@"isInternal"];
  [coder encodeObject:@(self.isLeaf) forKey:@"isLeaf"];
}

- (instancetype)initWithCoder:(NSCoder *)decoder {
  self = [self initWithDictionary:nil];
  if (self) {
    _bsdName = [decoder decodeObjectOfClass:[NSString class] forKey:@"bsdName"];
    _volName = [decoder decodeObjectOfClass:[NSString class] forKey:@"volName"];
    _volKind = [decoder decodeObjectOfClass:[NSString class] forKey:@"volKind"];
    _mediaName = [decoder decodeObjectOfClass:[NSString class] forKey:@"mediaName"];
    _mediaContent = [decoder decodeObjectOfClass:[NSString class] forKey:@"mediaContent"];
    _diskSize = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"diskSize"];
    _protocol = [decoder decodeObjectOfClass:[NSString class] forKey:@"protocol"];
    _isWhole = [[decoder decodeObjectOfClass:[NSNumber class] forKey:@"isWhole"] boolValue];
    _isNetwork = [[decoder decodeObjectOfClass:[NSNumber class] forKey:@"isNetwork"] boolValue];
    _isInternal = [[decoder decodeObjectOfClass:[NSNumber class] forKey:@"isInternal"] boolValue];
    _isLeaf = [[decoder decodeObjectOfClass:[NSNumber class] forKey:@"isLeaf"] boolValue];
  }
  return self;
}

+ (BOOL)supportsSecureCoding {
  return YES;
}

@end
