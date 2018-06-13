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

/// An Image represents an installable configuration with a given name.
@interface Image : NSObject<NSSecureCoding>

/// Initialize with an appropriate dictionary (from a plist).
- (instancetype)initWithDictionary:(NSDictionary *)dict NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

/// The name of this image configuration
@property(readonly, nonatomic) NSString *name;

/// The URL to download this image from
@property(readonly, nonatomic) NSURL *URL;

/// The SHA-256 hash of this image
@property(readonly, nonatomic) NSString *sha256;

/// The SHA-512 hash of this image
@property(readonly, nonatomic) NSString *sha512;

/// The URL of the image on disk, if it exists
@property NSURL *localURL;

@end
