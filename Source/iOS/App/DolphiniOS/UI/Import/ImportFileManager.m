// Copyright 2022 DolphiniOS Project
// SPDX-License-Identifier: GPL-2.0-or-later

#import "ImportFileManager.h"

#import "Swift.h"

#import "GameFileCacheManager.h"
#import "LocalizationUtil.h"
#import "MainSceneCoordinator.h"

@implementation ImportFileManager {
  UIWindow* _window;
  NSMutableArray<NSURL*>* _queuedUrls;
  BOOL _isImporting;
}

+ (ImportFileManager*)shared {
  static ImportFileManager* sharedInstance = nil;
  static dispatch_once_t onceToken;

  dispatch_once(&onceToken, ^{
    sharedInstance = [[self alloc] init];
  });

  return sharedInstance;
}

- (void)showWindowOnScene:(UIWindowScene*)scene {
  self->_window = [[UIWindow alloc] initWithWindowScene:scene];
  self->_window.frame = [UIScreen mainScreen].bounds;
  self->_window.rootViewController = [[UIViewController alloc] init];
  self->_window.windowLevel = UIWindowLevelAlert;
  
  UIWindow* topWindow = scene.windows.lastObject;
  self->_window.windowLevel = topWindow.windowLevel + 1;
  
  [self->_window makeKeyAndVisible];
}

- (void)hideWindow {
  [self->_window setHidden:true];
  
  self->_window = nil;
}

- (void)presentViewControllerOnWindow:(UIViewController*)controller {
  [self->_window.rootViewController presentViewController:controller animated:true completion:nil];
}

- (void)importFileAtUrl:(NSURL*)url {
  [self importFilesAtUrls:@[url]];
}

- (void)importFilesAtUrls:(NSArray<NSURL*>*)urls {
  if (self->_queuedUrls == nil) {
    self->_queuedUrls = [[NSMutableArray alloc] init];
  }

  [self->_queuedUrls addObjectsFromArray:urls];

  [self processNextQueuedImportIfNeeded];
}

// importFileAtUrl's Copy/Move/Cancel alert and single shared _window can only handle one file
// at a time - this pops one URL off the queue, runs the existing per-file flow, and (via
// finish() below) calls itself again for the next one once the user has responded.
- (void)processNextQueuedImportIfNeeded {
  if (self->_isImporting || self->_queuedUrls.count == 0) {
    return;
  }

  NSURL* url = [self->_queuedUrls firstObject];
  [self->_queuedUrls removeObjectAtIndex:0];

  self->_isImporting = true;

  UIWindowScene* mainScene = [MainSceneCoordinator shared].mainScene;

  if (mainScene == nil) {
    self->_isImporting = false;
    return;
  }

  [self showWindowOnScene:mainScene];

  if (![url startAccessingSecurityScopedResource]) {
    UIAlertController* errorAlert = [UIAlertController alertControllerWithTitle:DOLCoreLocalizedString(@"Error") message:@"Failed to start accessing security scoped resource." preferredStyle:UIAlertControllerStyleAlert];
    
    [errorAlert addAction:[UIAlertAction actionWithTitle:DOLCoreLocalizedString(@"OK") style:UIAlertActionStyleDefault
      handler:^(UIAlertAction* action) {
      [self hideWindow];

      self->_isImporting = false;
      [self processNextQueuedImportIfNeeded];
    }]];

    [self presentViewControllerOnWindow:errorAlert];

    return;
  }

  void (^finish)(void) = ^void() {
    [url stopAccessingSecurityScopedResource];

    [self hideWindow];

    [[NSNotificationCenter defaultCenter] postNotificationName:DOLImportFileFinishedNotification object:self userInfo:nil];

    self->_isImporting = false;
    [self processNextQueuedImportIfNeeded];
  };
  
  NSString* sourcePath = [url path];
  NSString* destinationPath = [[UserFolderUtil getSoftwareFolder] stringByAppendingPathComponent:[sourcePath lastPathComponent]];
  
  NSFileManager* fileManager = [NSFileManager defaultManager];
  
  if ([fileManager fileExistsAtPath:destinationPath]) {
    UIAlertController* errorAlert = [UIAlertController alertControllerWithTitle:DOLCoreLocalizedString(@"Error") message:@"This software has already been imported." preferredStyle:UIAlertControllerStyleAlert];
    
    [errorAlert addAction:[UIAlertAction actionWithTitle:DOLCoreLocalizedString(@"OK") style:UIAlertActionStyleDefault
      handler:^(UIAlertAction* action) {
      finish();
    }]];
    
    [self presentViewControllerOnWindow:errorAlert];
    
    return;
  }
  
  UIAlertController* alert = [UIAlertController alertControllerWithTitle:DOLCoreLocalizedString(@"Import") message:nil preferredStyle:UIAlertControllerStyleAlert];

  [alert addAction:[UIAlertAction actionWithTitle:DOLCoreLocalizedString(@"Copy") style:UIAlertActionStyleDefault
    handler:^(UIAlertAction* action) {
    NSError* error = nil;
    if (![fileManager copyItemAtPath:sourcePath toPath:destinationPath error:&error]) {
      UIAlertController* errorAlert = [UIAlertController alertControllerWithTitle:DOLCoreLocalizedString(@"Error") message:[NSString stringWithFormat:@"The copy operation failed.\n\n%@", error.localizedDescription] preferredStyle:UIAlertControllerStyleAlert];
      
      [errorAlert addAction:[UIAlertAction actionWithTitle:DOLCoreLocalizedString(@"OK") style:UIAlertActionStyleDefault
        handler:^(UIAlertAction* action) {
        finish();
      }]];
      
      [self presentViewControllerOnWindow:errorAlert];
    } else {
      finish();
    }
  }]];
  
  [alert addAction:[UIAlertAction actionWithTitle:DOLCoreLocalizedString(@"Move") style:UIAlertActionStyleDefault
    handler:^(UIAlertAction* action) {
    NSError* error = nil;
    if (![fileManager moveItemAtPath:sourcePath toPath:destinationPath error:&error]) {
      UIAlertController* errorAlert = [UIAlertController alertControllerWithTitle:DOLCoreLocalizedString(@"Error") message:[NSString stringWithFormat:@"The move operation failed.\n\n%@", error.localizedDescription] preferredStyle:UIAlertControllerStyleAlert];
      
      [errorAlert addAction:[UIAlertAction actionWithTitle:DOLCoreLocalizedString(@"OK") style:UIAlertActionStyleDefault
        handler:^(UIAlertAction* action) {
        finish();
      }]];
      
      [self presentViewControllerOnWindow:errorAlert];
    } else {
      finish();
    }
  }]];
  
  [alert addAction:[UIAlertAction actionWithTitle:DOLCoreLocalizedString(@"Cancel") style:UIAlertActionStyleCancel
    handler:^(UIAlertAction* action) {
    finish();
  }]];
  
  [self presentViewControllerOnWindow:alert];
}

@end
