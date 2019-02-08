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

#import "Common/Image.h"

@implementation Image

- (instancetype)initWithDictionary:(NSDictionary *)dict {
  self = [super init];
  if (self) {
    // TODO(bur): Validate keys / values before using.
    _name = dict[@"Name"];
    _URL = [NSURL URLWithString:dict[@"URL"]];
    if (!_URL.scheme && _URL) {
      _URL = [NSURL fileURLWithPath:dict[@"URL"]];
    }
    _sha256 = dict[@"SHA-256"];
    _sha512 = dict[@"SHA-512"];
    _custom = [dict[@"Custom"] boolValue];
    _postScript = dict[@"Post Script"];
    _postScriptMustSucceed = [dict[@"Post Script Must Succeed"] boolValue];
  }
  return self;
}

#pragma mark NSSecureCoding

- (void)encodeWithCoder:(NSCoder *)coder {
  [coder encodeObject:self.name forKey:@"name"];
  [coder encodeObject:self.URL forKey:@"URL"];
  [coder encodeObject:self.sha256 forKey:@"sha256"];
  [coder encodeObject:self.sha512 forKey:@"sha512"];
  [coder encodeObject:self.localURL forKey:@"localURL"];
  [coder encodeObject:@(self.custom) forKey:@"custom"];
  [coder encodeObject:self.postScript forKey:@"postScript"];
  [coder encodeObject:@(self.postScriptMustSucceed) forKey:@"postScriptMustSucceed"];
}

- (instancetype)initWithCoder:(NSCoder *)decoder {
  self = [self initWithDictionary:nil];
  if (self) {
    _name = [decoder decodeObjectOfClass:[NSString class] forKey:@"name"];
    _URL = [decoder decodeObjectOfClass:[NSURL class] forKey:@"URL"];
    _sha256 = [decoder decodeObjectOfClass:[NSString class] forKey:@"sha256"];
    _sha512 = [decoder decodeObjectOfClass:[NSString class] forKey:@"sha512"];
    _localURL = [decoder decodeObjectOfClass:[NSURL class] forKey:@"localURL"];
    _custom = [[decoder decodeObjectOfClass:[NSNumber class] forKey:@"custom"] boolValue];
    _postScript = [decoder decodeObjectOfClass:[NSString class] forKey:@"postScript"];
    _postScriptMustSucceed =
        [[decoder decodeObjectOfClass:[NSNumber class] forKey:@"postScriptMustSucceed"] boolValue];
  }
  return self;
}

+ (BOOL)supportsSecureCoding {
  return YES;
}

- (NSString *)description {
  return self.name;
}

#pragma mark Equality

- (BOOL)isEqualToImage:(Image *)image {
  // Two images are considered equal if they have the same name and same stored checksums.
  // Note the post script properties are not used for equality.
  if (![self.name isEqualToString:image.name]) return NO;
  if ((self.sha256 || image.sha256) && ![self.sha256 isEqualToString:image.sha256]) return NO;
  if ((self.sha512 || image.sha512) && ![self.sha512 isEqualToString:image.sha512]) return NO;
  return YES;
}

- (BOOL)isEqual:(id)object {
  return (self == object || ([object isKindOfClass:[Image class]] && [self isEqualToImage:object]));
}

- (NSUInteger)hash {
  return [self.name hash] ^ [self.sha256 hash] ^ [self.sha512 hash];
}

@end
