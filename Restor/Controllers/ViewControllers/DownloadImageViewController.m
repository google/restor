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

#import "Restor/Controllers/ViewControllers/DownloadImageViewController.h"

#import <CommonCrypto/CommonDigest.h>

#import <MOLAuthenticatingURLSession/MOLAuthenticatingURLSession.h>
#import <MOLXPCConnection/MOLXPCConnection.h>

#import "Common/Image.h"
#import "Restor/Utilities/HashUtils.h"

@interface DownloadImageViewController ()
@property(readwrite, nonatomic) BOOL isPausable;
@property(readwrite, nonatomic) BOOL isCancelled;
@property NSURLSessionDataTask *task;
@property float percentComplete;
@property NSProgress *progress;
@property NSTimeInterval startTime;
@property uint64_t startBytes;
@property NSTimer *progressTimer;
@end

@implementation DownloadImageViewController

- (void)viewDidAppear {
  if ([self.requestedImage.localURL checkResourceIsReachableAndReturnError:NULL]) {
    [self dismissWithSuccess];
  }

  // Reset download progress info in case this view is reappearing.
  self.progress = nil;
  self.startTime = [[NSDate date] timeIntervalSinceReferenceDate];
  self.startBytes = 0;

  // Start a task to download the requested image.
  self.authSession = [self createDownloadSession];
  self.task = [self.authSession.session dataTaskWithURL:self.requestedImage.URL];
  [self.task resume];
  self.isPausable = YES;

  // Compute download throughput and update the progress description every 1 second.
  self.progressTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                       repeats:YES
                                                         block:^(NSTimer *timer) {
    [self updateProgressDescription];
  }];
}

- (void)viewDidDisappear {
  [self.progressTimer invalidate];
}

- (MOLAuthenticatingURLSession *)createDownloadSession {
  NSString *downloadPath = [NSString stringWithFormat:@"%@.download",
                               self.requestedImage.localURL.path];
  NSFileHandle *download = [self imageDownloadFileHandleForPath:downloadPath];

  dispatch_queue_t fileQueue = dispatch_queue_create("com.google.corp.restor.file",
                                                     DISPATCH_QUEUE_SERIAL);

  __block int64_t receivedPercent = 0;
  __block id<Hasher> hasher;
  __block NSString *expectedChecksum;

  // Determine which checksum to use, with SHA-512 preferred to SHA-256.
  if (self.requestedImage.sha512) {
    hasher = [HashUtils hasherForAlgorithm:HashAlgorithmSHA512];
    expectedChecksum = self.requestedImage.sha512;
  } else if (self.requestedImage.sha256) {
    hasher = [HashUtils hasherForAlgorithm:HashAlgorithmSHA256];
    expectedChecksum = self.requestedImage.sha256;
  } else {
    hasher = nil;
    expectedChecksum = nil;
  }

  MOLAuthenticatingURLSession *authSession = [[MOLAuthenticatingURLSession alloc] init];

  WEAKIFY(self);
  authSession.dataTaskDidReceiveDataBlock = ^(NSURLSession *s, NSURLSessionDataTask *t, NSData *d) {
    STRONGIFY(self);
    dispatch_async(fileQueue, ^{
      if (hasher) [hasher updateWithBytes:d.bytes length:(CC_LONG)d.length];
      [download writeData:d];
    });

    // Deal with all progress indicator changes on the main thread.
    dispatch_async(dispatch_get_main_queue(), ^{
      if (!self.progress) {
        self.progress = [NSProgress progressWithTotalUnitCount:t.countOfBytesExpectedToReceive];
        self.progress.localizedDescription = @"";
      }
      self.progress.completedUnitCount = t.countOfBytesReceived;
      float percent = self.progress.fractionCompleted * 100;
      if (receivedPercent < (int64_t)percent) {
        receivedPercent = (int64_t)percent;
        self.percentComplete = percent;
      }
    });
  };

  authSession.taskDidCompleteWithErrorBlock = ^(NSURLSession *s, NSURLSessionTask *t, NSError *e) {
    STRONGIFY(self);
    dispatch_sync(fileQueue, ^{
      [download closeFile];
    });

    NSFileManager *fm = [NSFileManager defaultManager];
    NSHTTPURLResponse *resp = (NSHTTPURLResponse *)t.response;

    if (self.isCancelled) {
      [fm removeItemAtPath:downloadPath error:NULL];
    } else if (e || resp.statusCode != 200) {
      [fm removeItemAtPath:downloadPath error:NULL];
      NSString *text = e.localizedDescription;
      if (!text) {
        text = [NSString stringWithFormat:@"Error downloading image.\n"
                                          @"Received HTTP status code %ld.", resp.statusCode];
      }
      [self displayErrorWithFormat:text];
    } else {
      __block NSString *downloadSHA;
      if (hasher) {
        dispatch_sync(fileQueue, ^{
          downloadSHA = [hasher digest];
        });
      }
      if (expectedChecksum && ![expectedChecksum isEqualToString:downloadSHA]) {
        [fm removeItemAtPath:downloadPath error:NULL];
        [self displayErrorWithFormat:@"Downloaded image does not match requested image."];
        return;
      }
      [fm moveItemAtPath:downloadPath toPath:self.requestedImage.localURL.path error:NULL];
      dispatch_async(dispatch_get_main_queue(), ^{
        [self dismissWithSuccess];
      });
    }
  };

  return authSession;
}

// Display an error alert sheet with the given message, then dismiss this DownloadImageView.
- (void)displayErrorWithFormat:(NSString *)format, ... {
  va_list args;
  va_start(args, format);
  NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
  va_end(args);
  // Log the error message.
  NSLog(@"Error: %@", msg);

  WEAKIFY(msg);
  dispatch_async(dispatch_get_main_queue(), ^{
    STRONGIFY(msg);

    // Then display an alert.
    NSAlert *alert = [[NSAlert alloc] init];
    alert.alertStyle = NSAlertStyleCritical;
    alert.messageText = msg;
    [alert beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse rc) {
      [self cancel:self];
    }];
  });
}

- (void)updateProgressDescription {
  NSByteCountFormatter *bf = [[NSByteCountFormatter alloc] init];
  bf.zeroPadsFractionDigits = YES;

  // Calculate throughput, while guarding against division by zero.
  NSTimeInterval currTime = [[NSDate date] timeIntervalSinceReferenceDate];
  uint64_t currBytes = self.progress.completedUnitCount;
  NSTimeInterval dt = currTime - self.startTime;
  NSString *throughput = @"";
  if (dt > 1e-6) {
    throughput = [NSString stringWithFormat:@"(%@/sec)",
        [bf stringFromByteCount:(currBytes - self.startBytes) / dt]];
  }

  // Update the localized description that will be displayed by DownloadImageViewController.
  // NSProgress's localizedAdditionalDescription can auto format this same info, but it won't zero
  // pad the fraction digits and updates too frequently, resulting in horrible vibrating text.
  self.progress.localizedDescription = [NSString stringWithFormat:@"%@ of %@ %@",
      [bf stringFromByteCount:self.progress.completedUnitCount],
      [bf stringFromByteCount:self.progress.totalUnitCount],
      throughput];

  // Reset values for next call.
  self.startTime = currTime;
  self.startBytes = currBytes;
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
  if (self.cancelBlock) self.cancelBlock();
}

- (void)dismissWithSuccess {
  [self dismissController:self];
  if (self.completionBlock) self.completionBlock();
}

@end
