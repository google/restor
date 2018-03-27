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

@property Image *selectedImage;

@property DiskWatcher *diskWatcher;
@property NSMutableArray<Disk *> *connectedDisks;
@property NSMutableDictionary<NSString *, ImagingSession *> *imagingSessions;

@property BOOL autoImageMode;
@property BOOL showCachedCheckmark;
@property BOOL showDownloadButton;

- (IBAction)selectedImageDidChange:(id)sender;

@end

@implementation MainViewController

- (void)viewDidLoad {
  self.connectedDisks = [NSMutableArray array];
  self.imagingSessions = [NSMutableDictionary dictionary];

  [self createDiskWatcher];
}

- (void)viewDidAppear {
  self.selectedImage = self.imageCacheController.images.firstObject;
  [self selectedImageDidChange:self];
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

// Hide/show the cached button or download button whenever the selected image changes.
- (IBAction)selectedImageDidChange:(id)sender {
  if ([self.selectedImage.name isEqualToString:@"Custom Image"]) {
    self.showCachedCheckmark = NO;
    self.showDownloadButton = NO;
  } else {
    if (!self.selectedImage.localURL) {
      self.selectedImage.localURL =
          [self.imageCacheController localPathForImage:self.selectedImage];
    }
    if ([self.selectedImage.localURL checkResourceIsReachableAndReturnError:NULL]) {
      self.showCachedCheckmark = YES;
      self.showDownloadButton = NO;
    } else {
      self.showCachedCheckmark = NO;
      self.showDownloadButton = YES;
    }
  }
}

// This method is called when the user clicks the "Image..." button or if the user clicks through
// the "Auto Image..." warning sheet.  If "Custom Image" has been selected in the popup button,
// display the custom image sheet, which may display the download sheet, then do imaging.  If a
// regular item has been selected, then possibly display download sheet, then do imaging.
- (IBAction)image:(id)sender {
  if ([self.selectedImage.name isEqualToString:@"Custom Image"]) {
    [self showCustomImageView];
  } else {
    [self downloadIfNeededWithCompletionBlock:^{
      [self imageAllSelectedDisks];
    }];
  }
}

// Download the currently selected image to the image cache.
- (IBAction)downloadImage:(id)sender {
  [self downloadIfNeededWithCompletionBlock:nil];
}

- (IBAction)autoImage:(id)sender {
  [self showAutoImageWarningView];
}

- (IBAction)autoImageStop:(id)sender {
  self.autoImageMode = NO;
}

- (IBAction)showCachedImageInFinder:(id)sender {
  if (!self.selectedImage.localURL) {
    self.selectedImage.localURL = [self.imageCacheController localPathForImage:self.selectedImage];
  }
  [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[self.selectedImage.localURL]];
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

// If the selected image is not in the local cache, then presents the download sheet to get it and
// executes the completion block if download is successful.  If the selected image is already in
// the cache, then just immediately executes the completion block.
- (void)downloadIfNeededWithCompletionBlock:(nullable void (^)(void))block {
  if (!self.selectedImage.localURL) {
    self.selectedImage.localURL = [self.imageCacheController localPathForImage:self.selectedImage];
  }
  if (![self.selectedImage.localURL checkResourceIsReachableAndReturnError:NULL]) {
    [self showDownloadImageViewWithCompletionBlock:block];
  } else if (block) {
    block();
  }
}

// Start imaging all selected disks using the currently selected image.
- (void)imageAllSelectedDisks {
  for (NSIndexPath *indexPath in self.collectionView.selectionIndexPaths) {
    NSViewController *item = [self.collectionView itemAtIndexPath:indexPath];
    if (![item isKindOfClass:[CollectionViewItemAvailable class]]) continue;
    [self imageDisk:((CollectionViewItemAvailable *)item).representedObject];
  }
}

// Start imaging a single connected disk using the currently selected image.
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

// Display a warning about auto imaging before entering auto image mode.
// If user doesn't cancel, then immediately start imaging any connected disks.
- (void)showAutoImageWarningView {
  NSStoryboard *sb = [NSStoryboard storyboardWithName:@"App" bundle:nil];
  AutoImageWarningViewController *vc =
      [sb instantiateControllerWithIdentifier:@"AutoImageWarningSheet"];

  vc.completionBlock = ^{
    self.autoImageMode = YES;
    [self.collectionView selectAll:nil];
    [self image:self];
  };

  vc.cancelBlock = ^{
    self.autoImageMode = NO;
  };

  [self presentViewControllerAsSheet:vc];
}

// Display the download sheet to download a remote image.  If the download finishes successfully,
// then execute the given completion block.
- (void)showDownloadImageViewWithCompletionBlock:(nullable void (^)(void))block {
  NSStoryboard *sb = [NSStoryboard storyboardWithName:@"App" bundle:nil];
  DownloadImageViewController *vc = [sb instantiateControllerWithIdentifier:@"DownloadSheet"];
  vc.requestedImage = self.selectedImage;

  vc.completionBlock = ^{
    // If we successfully downloaded the image, we need to update the checkmark.
    [self selectedImageDidChange:self];
    if (block) block();
  };

  vc.cancelBlock = ^{
    self.autoImageMode = NO;
  };

  [self presentViewControllerAsSheet:vc];
}

// Display the custom image sheet so that user can specify a custom image to use.  If the user
// doesn't cancel, we immediately try to download the specified image and then image with it.
- (void)showCustomImageView {
  NSStoryboard *sb = [NSStoryboard storyboardWithName:@"App" bundle:nil];
  CustomImageViewController *vc = [sb instantiateControllerWithIdentifier:@"CustomImageSheet"];

  vc.completionBlock = ^(Image *customImage) {
    if (customImage) {
      self.selectedImage = customImage;
      [self downloadIfNeededWithCompletionBlock:^{
        [self imageAllSelectedDisks];
      }];
    } else {
      self.autoImageMode = NO;
    }
  };

  vc.cancelBlock = ^{
    self.autoImageMode = NO;
  };

  [self presentViewControllerAsSheet:vc];
}

@end
