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

#import "MainViewController.h"

#import <MOLXPCConnection/MOLXPCConnection.h>

#import "AutoImageWarningViewController.h"
#import "CollectionViewItemAvailable.h"
#import "CollectionViewItemImaging.h"
#import "ConfigViewController.h"
#import "CustomImageViewController.h"
#import "Disk.h"
#import "DiskWatcher.h"
#import "DiskFilter.h"
#import "DownloadImageViewController.h"
#import "ImageCacheController.h"
#import "ImagingSession.h"
#import "Image.h"

@interface MainViewController ()

@property IBOutlet NSCollectionView *collectionView;
@property IBOutlet NSPopUpButton *imageSelector;

@property Image *selectedImage;

@property DiskWatcher *diskWatcher;
@property NSMutableArray<Disk *> *connectedDisks;
@property NSMutableDictionary<NSString *, ImagingSession *> *imagingSessions;

@property SEL nextSelector;
@property BOOL autoImageMode;

@end

@implementation MainViewController

- (void)viewDidLoad {
  self.connectedDisks = [NSMutableArray array];
  self.imagingSessions = [NSMutableDictionary dictionary];

  [self createDiskWatcher];
}

- (void)viewDidAppear {
  self.selectedImage = self.imageCacheController.images.firstObject;
}

#pragma mark Disk Content

- (void)createDiskWatcher {
  WEAKIFY(self);

  self.diskWatcher = [[DiskWatcher alloc] init];
  self.diskWatcher.appearCallback = ^(Disk *disk) {
    if (![DiskFilter filterDisk:disk]) return;

    dispatch_async(dispatch_get_main_queue(), ^{
      STRONGIFY(self);
      [[self mutableArrayValueForKey:@"connectedDisks"] addObject:disk];
      [self.collectionView reloadData];

      if (self.collectionView.selectionIndexPaths.count == 0) {
        [self.collectionView selectAll:nil];
      }
    });

    STRONGIFY(self);
    if (self.autoImageMode) {
      [self imageDisk:disk];
    }

  };
  self.diskWatcher.disappearCallback = ^(Disk *disk) {
    STRONGIFY(self);
    ImagingSession *is = self.imagingSessions[disk.bsdName];
    self.imagingSessions[disk.bsdName] = nil;

    dispatch_sync(dispatch_get_main_queue(), ^{
      STRONGIFY(self);
      [[self mutableArrayValueForKey:@"connectedDisks"] removeObject:disk];
      [self.collectionView reloadData];
    });

    // Do this after the UI updates to avoid breaking KVO.
    [is cancel];
  };
  [self.diskWatcher beginWatching];
}

#pragma mark Actions

- (IBAction)image:(id)sender {
  if ([self.selectedImage.name isEqualToString:@"Custom Image"]) {
    self.nextSelector = @selector(downloadImage);
    [self performSegueWithIdentifier:@"PresentCustomImageSheet" sender:self];
  } else {
    [self downloadImage];
  }
}

- (void)downloadImage {
  if (!self.selectedImage.localURL) {
    self.selectedImage.localURL = [self.imageCacheController localPathForImage:self.selectedImage];
  }
  if (![self.selectedImage.localURL checkResourceIsReachableAndReturnError:NULL]) {
    self.nextSelector = @selector(imagePartTwo);
    [self performSegueWithIdentifier:@"PresentDownloadSheet" sender:self];
    return;
  }
  [self imagePartTwo];
}

- (void)imagePartTwo {
  for (NSIndexPath *indexPath in self.collectionView.selectionIndexPaths) {
    NSViewController *item = [self.collectionView itemAtIndexPath:indexPath];
    if (![item isKindOfClass:[CollectionViewItemAvailable class]]) continue;
    CollectionViewItemAvailable *cvia = (CollectionViewItemAvailable *)item;
    [self imageDisk:cvia.representedObject];
  }
}

- (IBAction)autoImage:(id)sender {
  [self performSegueWithIdentifier:@"PresentAutoImageWarningSheet" sender:self];
}

- (IBAction)autoImageContinue:(id)sender {
  self.autoImageMode = YES;
  [self.collectionView selectAll:sender];
  [self image:self];
}

- (IBAction)autoImageStop:(id)sender {
  self.autoImageMode = NO;
}

#pragma mark Collection View Data Source/Delegate

- (NSInteger)collectionView:(NSCollectionView *)cv numberOfItemsInSection:(NSInteger)section {
  return self.connectedDisks.count;
}

- (NSCollectionViewItem *)collectionView:(NSCollectionView *)cv
     itemForRepresentedObjectAtIndexPath:(NSIndexPath *)indexPath {
  NSCollectionViewItem *item;
  Disk *disk = [self.connectedDisks objectAtIndex:indexPath.item];
  if (self.imagingSessions[disk.bsdName]) {
    CollectionViewItemImaging *cvi = [cv makeItemWithIdentifier:@"CollectionViewItemImaging"
                                                   forIndexPath:indexPath];
    cvi.representedObject = disk;
    cvi.imagingSession = self.imagingSessions[disk.bsdName];
    item = cvi;
  } else {
    CollectionViewItemAvailable *cvi = [cv makeItemWithIdentifier:@"CollectionViewItemAvailable"
                                                     forIndexPath:indexPath];
    cvi.representedObject = disk;
    item = cvi;
  }

  return item;
}

#pragma mark Begin Imaging

- (void)imageDisk:(Disk *)disk {
  ImagingSession *is = [[ImagingSession alloc] initWithImage:self.selectedImage
                                                  targetDisk:disk
                                            helperConnection:self.helperConnection];
  self.imagingSessions[disk.bsdName] = is;

  dispatch_async(dispatch_get_main_queue(), ^{
    [self.collectionView reloadData];
  });

  [is begin];
}

#pragma mark Sheet Presentation

- (void)prepareForSegue:(NSStoryboardSegue *)segue sender:(id)sender {
  [super prepareForSegue:segue sender:sender];

  if ([segue.destinationController isKindOfClass:[DownloadImageViewController class]]) {
    DownloadImageViewController *divc = (DownloadImageViewController *)segue.destinationController;
    divc.requestedImage = self.selectedImage;
  }
}

- (void)dismissViewController:(NSViewController *)viewController {
  [super dismissViewController:viewController];

  if ([viewController isKindOfClass:[AutoImageWarningViewController class]]) {
    AutoImageWarningViewController *aiwvc = (AutoImageWarningViewController *)viewController;
    self.nextSelector = nil;
    if (aiwvc.shouldContinue) {
      [self autoImageContinue:self];
    }
  } else if ([viewController isKindOfClass:[CustomImageViewController class]]) {
    CustomImageViewController *civc = (CustomImageViewController *)viewController;
    if (!civc.shouldContinue) {
      self.autoImageMode = NO;
      self.nextSelector = nil;
    } else {
      // Create a new custom image
      NSDictionary *ciDict = @{
        @"Name" : civc.imageURL.pathComponents.lastObject.stringByDeletingPathExtension,
        @"URL" : civc.imageURL
      };
      Image *ci = [[Image alloc] initWithDictionary:ciDict];
      if ([ci.URL.scheme isEqualToString:@"file"]) {
        ci.localURL = ci.URL;
      }
      self.selectedImage = ci;
      [self performSelectorOnMainThread:self.nextSelector withObject:self waitUntilDone:NO];
      self.nextSelector = nil;
    }
  } else if ([viewController isKindOfClass:[DownloadImageViewController class]]) {
    DownloadImageViewController *divc = (DownloadImageViewController *)viewController;
    if (divc.isCancelled) {
      self.autoImageMode = NO;
      self.nextSelector = nil;
    } else {
      [self performSelectorOnMainThread:self.nextSelector withObject:self waitUntilDone:NO];
      self.nextSelector = nil;
    }
  } else {
    [self performSelectorOnMainThread:self.nextSelector withObject:self waitUntilDone:NO];
    self.nextSelector = nil;
  }
}

@end
