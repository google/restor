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

#import <CommonCrypto/CommonDigest.h>

// List of hashing algorithms that can be used with HashUtils.
typedef NS_ENUM(NSUInteger, HashAlgorithm) {
  SHA256,
  SHA512,
};

// Protocol for computing hashes incrementally.
@protocol Hasher

// Call repeatedly with chunks of the message to be hashed.
// @param bytes is next chunk of data to be hashed.
// @param length is number of bytes in array.
- (void)updateWithBytes:(const char *)bytes length:(CC_LONG)length;

// Returns a hexadecimal string representation of the message digest.
- (NSString *)finalize;

@end

// Class for computing the SHA-256 checksum of data.
@interface SHA256Hasher : NSObject<Hasher>
@end

// Class for computing the SHA-512 checksum of data.
@interface SHA512Hasher : NSObject<Hasher>
@end

///  Utility class for hashing large files on disk.
@interface HashUtils : NSObject

// Returns an object conforming to the Hasher protocol for the given algorithm.
+ (id<Hasher>)hasherForAlgorithm:(HashAlgorithm)algorithm;

// Get the checksum of a file using the given hash algorithm.
+ (NSString *)checksumForFileURL:(NSURL *)url algorithm:(HashAlgorithm)algorithm;

@end
