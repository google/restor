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

#import "HashUtils.h"

#import <CommonCrypto/CommonDigest.h>

@implementation HashUtils

+ (NSString *)SHA256ForDigest:(unsigned char *)digest {
  NSString *const SHA256FormatString =
      @"%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x"
      "%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x";

  return [[NSString alloc] initWithFormat:SHA256FormatString,
             digest[0], digest[1], digest[2], digest[3], digest[4],
             digest[5], digest[6], digest[7], digest[8], digest[9],
             digest[10], digest[11], digest[12], digest[13], digest[14],
             digest[15], digest[16], digest[17], digest[18], digest[19],
             digest[20], digest[21], digest[22], digest[23], digest[24],
             digest[25], digest[26], digest[27], digest[28], digest[29],
             digest[30], digest[31]];
}

+ (NSString *)SHA256ForFileURL:(NSURL *)url {
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

  CC_SHA256_CTX c256;
  CC_SHA256_Init(&c256);

  // Update the hash in chunks
  ssize_t bytesRead;
  for (uint64_t offset = 0; offset < fileSize;) {
    bytesRead = pread(fd, chunk, chunkSize, offset);
    if (bytesRead > 0) {
      CC_SHA256_Update(&c256, chunk, (CC_LONG)bytesRead);
      offset += bytesRead;
    } else if (bytesRead == -1 && errno == EINTR) {
      continue;
    } else {
      return nil;
    }
  }

  unsigned char digest[CC_SHA256_DIGEST_LENGTH];
  CC_SHA256_Final(digest, &c256);

  return [self SHA256ForDigest:digest];
}

@end
