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

#import "Image.h"

@implementation Image

- (instancetype)initWithDictionary:(NSDictionary *)dict {
  self = [super init];
  if (self) {
    _name = dict[@"Name"];
    _URL = [NSURL URLWithString:dict[@"URL"]];
    if (!_URL.scheme && _URL) {
      _URL = [NSURL fileURLWithPath:dict[@"URL"]];
    }
    _sha256 = dict[@"SHA-256"];
    _sha512 = dict[@"SHA-512"];
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
}

- (instancetype)initWithCoder:(NSCoder *)decoder {
  self = [self initWithDictionary:nil];
  if (self) {
    _name = [decoder decodeObjectOfClass:[NSString class] forKey:@"name"];
    _URL = [decoder decodeObjectOfClass:[NSURL class] forKey:@"URL"];
    _sha256 = [decoder decodeObjectOfClass:[NSString class] forKey:@"sha256"];
    _sha512 = [decoder decodeObjectOfClass:[NSString class] forKey:@"sha512"];
    _localURL = [decoder decodeObjectOfClass:[NSURL class] forKey:@"localURL"];
  }
  return self;
}

+ (BOOL)supportsSecureCoding {
  return YES;
}

- (NSString *)description {
  return self.name;
}

@end
