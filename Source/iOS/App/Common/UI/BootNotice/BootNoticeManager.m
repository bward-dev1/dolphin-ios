// Copyright 2023 DolphiniOS Project
// SPDX-License-Identifier: GPL-2.0-or-later

#import "BootNoticeManager.h"

#import "BootNoticeNavigationViewController.h"
#import "MainSceneCoordinator.h"

@implementation BootNoticeManager {
  NSMutableArray<UIViewController*>* _queuedControllers;
  BootNoticeNavigationViewController* _navigationController;
  bool _hasQueuedNoExitController;
}

+ (BootNoticeManager*)shared {
  static BootNoticeManager* sharedInstance = nil;
  static dispatch_once_t onceToken;

  dispatch_once(&onceToken, ^{
    sharedInstance = [[self alloc] init];
  });

  return sharedInstance;
}

- (instancetype)init {
  if (self = [super init]) {
    _queuedControllers = [[NSMutableArray alloc] init];
    
    _navigationController = [[BootNoticeNavigationViewController alloc] init];
    _navigationController.navigationBarHidden = true;
    _navigationController.modalInPresentation = true;
    _navigationController.modalPresentationStyle = UIModalPresentationFormSheet;
    
    _hasQueuedNoExitController = false;
  }
  
  return self;
}

- (BOOL)isBeingPresented {
  // -windows can legitimately be empty for a scene that has not attached its window yet, and
  // indexing an empty array throws.
  UIWindow* window = [MainSceneCoordinator shared].mainScene.windows.firstObject;

  if (window == nil) {
    return false;
  }

  return window.rootViewController.presentedViewController == _navigationController;
}

- (void)enqueueViewController:(UIViewController*)viewController {
  if (_hasQueuedNoExitController) {
    return;
  }
  
  if (![self isBeingPresented]) {
    [_queuedControllers addObject:viewController];
  } else {
    [_navigationController pushViewController:viewController animated:true];
  }
}

- (void)enqueueNoExitViewController:(UIViewController*)viewController {
  if (_hasQueuedNoExitController) {
    return;
  }
  
  if (![self isBeingPresented]) {
    [_queuedControllers removeAllObjects];
    [_queuedControllers addObject:viewController];
  } else {
    [_navigationController pushViewController:viewController animated:true];
  }
  
  _hasQueuedNoExitController = true;
}

- (void)presentToSceneIfNecessary {
  if (_queuedControllers.count == 0) {
    return;
  }
  
  UIWindow* window = [MainSceneCoordinator shared].mainScene.windows.firstObject;

  if (window == nil) {
    return;
  }

  UIViewController* rootViewController = window.rootViewController;

  if (rootViewController == nil || rootViewController.presentedViewController == _navigationController) {
    return;
  }

  // Pushed in reverse so the queue is first-in-first-seen. A UINavigationController displays the
  // last controller pushed, so pushing in enqueue order showed the queue backwards - the notice
  // enqueued last was the first thing a new user saw, and dismissing it revealed the one that was
  // supposed to come first.
  for (UIViewController* controller in [_queuedControllers reverseObjectEnumerator]) {
    [_navigationController pushViewController:controller animated:false];
  }
  
  [_queuedControllers removeAllObjects];
  
  [rootViewController presentViewController:_navigationController animated:true completion:nil];
}

@end
