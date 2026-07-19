// Copyright 2022 DolphiniOS Project
// SPDX-License-Identifier: GPL-2.0-or-later

#import <Foundation/Foundation.h>

@class EmulationBootParameter;
@class UIView;
@class UIImage;

NSString* const DOLEmulationDidStartNotification = @"DOLEmulationDidStartNotification";
NSString* const DOLEmulationDidEndNotification = @"DOLEmulationDidEndNotification";

NS_ASSUME_NONNULL_BEGIN

@interface EmulationCoordinator : NSObject

+ (EmulationCoordinator*)shared;

@property (nonatomic, setter=setIsExternalDisplayConnected:) bool isExternalDisplayConnected;
@property (nonatomic) bool userRequestedPause;

- (void)registerMainDisplayView:(UIView*)mainView;
- (void)registerExternalDisplayView:(UIView*)externalView;
- (void)runEmulationWithBootParameter:(EmulationBootParameter*)bootParameter;
- (void)clearMetalLayer;
// Snapshots whatever's currently on screen in the emulation view. completion is called on the
// main queue with nil if the view isn't currently in a window (e.g. called too early/late).
- (void)captureScreenshotWithCompletion:(void (^)(UIImage* _Nullable))completion;

@end

NS_ASSUME_NONNULL_END
