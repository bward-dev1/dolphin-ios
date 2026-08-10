// Copyright 2022 DolphiniOS Project
// SPDX-License-Identifier: GPL-2.0-or-later

#import <UIKit/UIKit.h>
#import <MetalKit/MetalKit.h>

#import "Swift.h"

@class EmulationBootParameter;

NS_ASSUME_NONNULL_BEGIN

@interface EmulationViewController : UIViewController <JitWaitViewControllerDelegate, NKitWarningViewControllerDelegate, PreGameCalibrationViewControllerDelegate>

@property (weak, nonatomic) IBOutlet UIView* rendererView;

@property (nonatomic) UIBarButtonItem* stopButton;
@property (nonatomic) UIBarButtonItem* pauseButton;
@property (nonatomic) UIBarButtonItem* playButton;
@property (nonatomic) UIBarButtonItem* hideBarButton;

@property (nonatomic) EmulationBootParameter* bootParameter;

- (void)updateNavigationBar:(bool)hidden;

// Presents the pointer-setup screen on demand, from the in-game menu, instead of as a gate in
// front of the boot. Finishing it does not (re)start emulation.
- (void)presentPointerSetupForRecalibration;

// Called once an on-demand recalibration finishes and its screen has been dismissed. No-op in
// this base class; EmulationiOSViewController overrides it to push the newly chosen mode onto the
// live Wii Remote pointer, since by then the pointer already exists and won't be re-initialised.
- (void)applyRecalibratedPointerMode;

@end

NS_ASSUME_NONNULL_END
