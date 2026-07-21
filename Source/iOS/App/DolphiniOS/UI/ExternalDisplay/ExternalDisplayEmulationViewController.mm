// Copyright 2022 DolphiniOS Project
// SPDX-License-Identifier: GPL-2.0-or-later

#import "ExternalDisplayEmulationViewController.h"

#import "Core/Core.h"
#import "Core/System.h"

#import "VideoCommon/Present.h"

#import "EmulationCoordinator.h"

@interface ExternalDisplayEmulationViewController ()

@end

@implementation ExternalDisplayEmulationViewController

- (void)viewDidLoad {
  [super viewDidLoad];

  [[EmulationCoordinator shared] registerExternalDisplayView:self.rendererView];

  if (Core::IsRunning(Core::System::GetInstance())) {
    self.rendererView.alpha = 1.0f;
    self.waitView.alpha = 0.0f;
  }
}

// EmulationiOSViewController (the main-display counterpart to this screen) has always had this
// same hook. This one never did, which was a latent gap even before anything this session
// touched -- registerExternalDisplayView: only sizes the render surface once, at the moment the
// TV scene's view first loads. If that view's real bounds hadn't settled yet at that exact
// moment (its layout can still be in flux right after an AirPlay/external-display scene
// connects), the surface would be sized wrong and nothing would ever ask it to resize again for
// the rest of the session -- consistent with a stretched frame that boots once and then never
// corrects itself.
- (void)viewDidLayoutSubviews {
  [super viewDidLayoutSubviews];

  if (g_presenter) {
    g_presenter->ResizeSurface();
  }
}

- (void)viewWillAppear:(BOOL)animated {
  [super viewWillAppear:animated];
  
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(receiveEmulationStartNotification) name:DOLEmulationDidStartNotification object:nil];
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(receiveEmulationEndNotification) name:DOLEmulationDidEndNotification object:nil];
}

- (void)viewDidDisappear:(BOOL)animated {
  [super viewDidDisappear:animated];
  
  [[NSNotificationCenter defaultCenter] removeObserver:self name:DOLEmulationDidStartNotification object:nil];
  [[NSNotificationCenter defaultCenter] removeObserver:self name:DOLEmulationDidEndNotification object:nil];
}

- (void)receiveEmulationStartNotification {
  dispatch_async(dispatch_get_main_queue(), ^{
    [UIView animateWithDuration:1.0f animations:^{
      self.rendererView.alpha = 1.0f;
      self.waitView.alpha = 0.0f;
    }];
  });
}

- (void)receiveEmulationEndNotification {
  dispatch_async(dispatch_get_main_queue(), ^{
    [UIView animateWithDuration:1.0f animations:^{
      self.rendererView.alpha = 0.0f;
      self.waitView.alpha = 1.0f;
    } completion:^(bool) {
      [[EmulationCoordinator shared] clearMetalLayer];
    }];
  });
}

@end
