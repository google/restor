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

#import "Restor/Utilities/HashUtils.h"

#import <CommonCrypto/CommonDigest.h>

// Returns the hexadecimal string representation for an array of bytes.
// @param bytes is a byte array.
// @param len is the number of bytes in the array.
NSString *hexStringFromBytes(unsigned char *bytes, int len) {
  const char *digits = "0123456789abcdef";
  char str[2*len + 1];
  int slen = 0;
  for (int i = 0; i < len; i++) {
    unsigned char b = bytes[i];
    str[slen++] = digits[b >> 4];
    str[slen++] = digits[b & 0xf];
  }
  str[slen] = 0;
  return [NSString stringWithCString:str encoding:NSASCIIStringEncoding];
}

// Class for computing the SHA-256 checksum of data.
@interface SHA256Hasher : NSObject<Hasher>
@end

// Class for computing the SHA-512 checksum of data.
@interface SHA512Hasher : NSObject<Hasher>
@end

@implementation SHA256Hasher {
  CC_SHA256_CTX _context;
}

- (instancetype)init {
  self = [super init];
  if (self) {
    CC_SHA256_Init(&_context);
  }
  return self;
}

- (void)updateWithBytes:(const char *)bytes length:(unsigned int)length {
  CC_SHA256_Update(&_context, bytes, length);
}

- (NSString *)digest {
  unsigned char md[CC_SHA256_DIGEST_LENGTH];
  CC_SHA256_Final(md, &_context);
  return hexStringFromBytes(md, CC_SHA256_DIGEST_LENGTH);
}

@end

@implementation SHA512Hasher {
  CC_SHA512_CTX _context;
}

- (instancetype)init {
  self = [super init];
  if (self) {
    CC_SHA512_Init(&_context);
  }
  return self;
}

- (void)updateWithBytes:(const char *)bytes length:(unsigned int)length {
  CC_SHA512_Update(&_context, bytes, length);
}

- (NSString *)digest {
  unsigned char md[CC_SHA512_DIGEST_LENGTH];
  CC_SHA512_Final(md, &_context);
  return hexStringFromBytes(md, CC_SHA512_DIGEST_LENGTH);
}

@end

@implementation HashUtils

+ (id<Hasher>)hasherForAlgorithm:(HashAlgorithm)algorithm {
  switch (algorithm) {
    case HashAlgorithmSHA256: return [[SHA256Hasher alloc] init];
    case HashAlgorithmSHA512: return [[SHA512Hasher alloc] init];
    default: return nil;
  }
}

+ (NSString *)checksumForFileURL:(NSURL *)url algorithm:(HashAlgorithm)algorithm {
  // Open file
  NSFileHandle *fh = [NSFileHandle fileHandleForReadingAtPath:url.path];
  int fd = fh.fileDescriptor;

  // Get file size
  [fh seekToEndOfFile];
  long long fileSize = [fh offsetInFile];
  [fh seekToFileOffset:0];

  // Init state for hashing
  const int MAX_CHUNK_SIZE = 256 * 1024;  // 256 KB
  const size_t chunkSize = fileSize > MAX_CHUNK_SIZE ? MAX_CHUNK_SIZE : fileSize;
  char chunk[chunkSize];

  id<Hasher> hasher = [self hasherForAlgorithm:algorithm];
  if (!hasher) return nil;

  // Update the hash in chunks
  ssize_t bytesRead;
  for (uint64_t offset = 0; offset < fileSize;) {
    bytesRead = pread(fd, chunk, chunkSize, offset);
    if (bytesRead > 0) {
      [hasher updateWithBytes:chunk length:(CC_LONG)bytesRead];
      offset += bytesRead;
    } else if (bytesRead == -1 && errno == EINTR) {
      continue;
    } else {
      return nil;
    }
  }

  return [hasher digest];
}

@end
