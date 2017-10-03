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

///  Utility class for hashing large files on disk.
@interface HashUtils : NSObject

// Get the SHA-256 hash of a file
+ (NSString *)SHA256ForFileURL:(NSURL *)url;

// Generate a string representation of a SHA-256 digest.
// Ensure digest has a length of CC_SHA256_DIGEST_LENGTH.
+ (NSString *)SHA256ForDigest:(unsigned char *)digest;

@end
