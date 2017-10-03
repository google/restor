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

#import "DownloadImageViewController.h"

#import <CommonCrypto/CommonDigest.h>

#import <MOLAuthenticatingURLSession/MOLAuthenticatingURLSession.h>
#import <MOLXPCConnection/MOLXPCConnection.h>

#import "HashUtils.h"
#import "Image.h"

@interface DownloadImageViewController ()
@property(readwrite, nonatomic) BOOL isPausable;
@property(readwrite, nonatomic) BOOL isCancelled;
@property NSURLSessionDataTask *task;
@property float percentComplete;
@end

@implementation DownloadImageViewController

- (void)viewDidAppear {
  if ([self.requestedImage.localURL checkResourceIsReachableAndReturnError:NULL]) {
    [self dismissController:self];
  }

  NSString *downloadPath = [NSString stringWithFormat:@"%@.download",
                               self.requestedImage.localURL.path];
  NSFileHandle *download = [self imageDownloadFileHandleForPath:downloadPath];

  dispatch_queue_t fileQueue = dispatch_queue_create("com.google.corp.restor.file",
                                                     DISPATCH_QUEUE_SERIAL);

  __block int64_t sentPercent = 0;
  __block CC_SHA256_CTX context;
  CC_SHA256_Init(&context);

  if (!self.authSession) self.authSession = [[MOLAuthenticatingURLSession alloc] init];

  WEAKIFY(self);
  self.authSession.dataTaskDidReceiveDataBlock = ^(NSURLSession *s,
                                                   NSURLSessionDataTask *t,
                                                   NSData *d) {
    STRONGIFY(self);
    dispatch_async(fileQueue, ^{
      CC_SHA256_Update(&context, d.bytes, (CC_LONG)d.length);
      [download writeData:d];
    });
    float progress = ((float)t.countOfBytesReceived / (float)t.countOfBytesExpectedToReceive) * 100;
    if (sentPercent < (int64_t)progress) {
      sentPercent = (int64_t)progress;
      dispatch_async(dispatch_get_main_queue(), ^{
        self.percentComplete = progress;
      });
    }
  };

  self.authSession.taskDidCompleteWithErrorBlock = ^(NSURLSession *s,
                                                     NSURLSessionTask *t,
                                                     NSError *e) {
    STRONGIFY(self);
    dispatch_sync(fileQueue, ^{
      [download closeFile];
    });

    NSFileManager *fm = [NSFileManager defaultManager];
    NSHTTPURLResponse *resp = (NSHTTPURLResponse *)t.response;
    if (resp.statusCode == 200) {
      __block NSString *downloadSHA256;
      dispatch_sync(fileQueue, ^{
        unsigned char digest[CC_SHA256_DIGEST_LENGTH];
        CC_SHA256_Final(digest, &context);
        downloadSHA256 = [HashUtils SHA256ForDigest:digest];
      });
      if (![self.requestedImage.sha256 isEqualToString:downloadSHA256]) {
        NSLog(@"Downloaded image does not match requested image");
        [fm removeItemAtPath:downloadPath error:NULL];
        return;
      }
      [fm moveItemAtPath:downloadPath toPath:self.requestedImage.localURL.path error:NULL];
      dispatch_async(dispatch_get_main_queue(), ^{
        [self dismissController:self];
      });
    } else {
      NSLog(@"Error downloading image: %@", e);
      [fm removeItemAtPath:downloadPath error:NULL];
    }
  };

  self.task = [self.authSession.session dataTaskWithURL:self.requestedImage.URL];
  [self.task resume];
  self.isPausable = YES;
}

- (NSFileHandle *)imageDownloadFileHandleForPath:(NSString *)path {
  NSFileManager *fm = [NSFileManager defaultManager];

  // Ensure cache path exists
  NSURL *cacheFolder = [self.requestedImage.localURL URLByDeletingLastPathComponent];
  if (![fm fileExistsAtPath:cacheFolder.path]) {
    [fm createDirectoryAtURL:cacheFolder withIntermediateDirectories:YES attributes:nil error:NULL];
  }

  [fm createFileAtPath:path contents:nil attributes:nil];
  return [NSFileHandle fileHandleForWritingAtPath:path];
}

- (IBAction)pause:(id)sender {
  [self.task suspend];
  self.isPausable = NO;
}

- (IBAction)resume:(id)sender {
  [self.task resume];
  self.isPausable = YES;
}

- (IBAction)cancel:(id)sender {
  [self.task cancel];
  self.isCancelled = YES;
  [self dismissController:self];
}

@end
