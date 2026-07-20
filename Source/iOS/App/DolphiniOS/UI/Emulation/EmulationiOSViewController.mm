// Copyright 2022 DolphiniOS Project
// SPDX-License-Identifier: GPL-2.0-or-later

#import "EmulationiOSViewController.h"

#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#import "Common/IOFile.h"

#import "Core/ConfigManager.h"
#import "Core/Config/GraphicsSettings.h"
#import "Core/Config/iOSSettings.h"
#import "Core/Config/MainSettings.h"
#import "Core/Config/WiimoteSettings.h"
#import "Core/HW/GCPad.h"
#import "Core/HW/SI/SI_Device.h"
#import "Core/HW/Wiimote.h"
#import "Core/HW/WiimoteEmu/WiimoteEmu.h"
#import "Core/IOS/USB/Emulated/Skylanders/Skylander.h"
#import "Core/State.h"
#import "Core/System.h"

#import "InputCommon/InputConfig.h"

#import "VideoCommon/Present.h"

#import "EmulationCoordinator.h"
#import "HostNotifications.h"
#import "HostQueue.h"
#import "LocalizationUtil.h"
#import "VirtualMFiControllerManager.h"

typedef NS_ENUM(NSInteger, DOLEmulationVisibleTouchPad) {
  DOLEmulationVisibleTouchPadNone,
  DOLEmulationVisibleTouchPadGameCube,
  DOLEmulationVisibleTouchPadWiimote,
  DOLEmulationVisibleTouchPadSidewaysWiimote,
  DOLEmulationVisibleTouchPadClassic
};

@interface EmulationiOSViewController ()

@end

@implementation EmulationiOSViewController {
  DOLEmulationVisibleTouchPad _visibleTouchPad;
  int _stateSlot;
  bool _didApplyPreGameTVCalibration;
}

- (void)viewDidLoad {
  [super viewDidLoad];

  for (int i = 0; i < [self.touchPads count]; i++) {
    TCView* padView = self.touchPads[i];

    if (i + 1 == DOLEmulationVisibleTouchPadGameCube) {
      padView.port = 0;
    } else {
      // Wii pads are mapped to touchscreen device 4
      padView.port = 4;
    }
  }

  if (@available(iOS 15.0, *)) {
    // Stupidity - iOS 15 now uses the scrollEdgeAppearance when the UINavigationBar is off screen.
    // https://developer.apple.com/forums/thread/682420
    UINavigationBar* bar = self.navigationController.navigationBar;
    bar.scrollEdgeAppearance = bar.standardAppearance;

    VirtualMFiControllerManager* virtualMfi = [VirtualMFiControllerManager shared];
    if (virtualMfi.shouldConnectController) {
      [virtualMfi connectControllerToView:self.view];
    }
  }

  _stateSlot = Config::GetBase(Config::MAIN_SELECTED_STATE_SLOT);
  
  // On iPadOS 26, the pull down button in the upper left can be blocked by window controls.
  if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
    self.pullDownLeftConstraint.active = false;
    self.pullDownCenterConstraint.active = true;
  }
}

- (void)viewWillAppear:(BOOL)animated {
  [super viewWillAppear:animated];

  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(receiveTitleChangedNotificationiOS) name:DOLHostTitleChangedNotification object:nil];
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(receiveRequestRenderWindowSizeNotificationiOS) name:DOLHostRequestRenderWindowSizeNotification object:nil];
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(receiveEmulationEndNotificationiOS) name:DOLEmulationDidEndNotification object:nil];
}

- (void)viewDidDisappear:(BOOL)animated {
  [super viewDidDisappear:animated];

  [[NSNotificationCenter defaultCenter] removeObserver:self name:DOLHostTitleChangedNotification object:nil];
  [[NSNotificationCenter defaultCenter] removeObserver:self name:DOLHostRequestRenderWindowSizeNotification object:nil];
  [[NSNotificationCenter defaultCenter] removeObserver:self name:DOLEmulationDidEndNotification object:nil];
}

- (void)recreateMenu {
  NSMutableArray<UIMenuElement*>* controllerActions = [[NSMutableArray alloc] init];

  NSMutableArray<UIMenuElement*>* visibleControllerActions = [[NSMutableArray alloc] init];

  bool wiimoteTouchPadAttached = [self isWiimoteTouchPadAttached] && Core::System::GetInstance().IsWii();
  bool gamecubeTouchPadAttached = [self isGameCubeTouchPadAttached];

  if (wiimoteTouchPadAttached) {
    UIAction* wiimoteAction = [UIAction actionWithTitle:DOLCoreLocalizedString(@"Wii Remote") image:nil identifier:nil handler:^(UIAction*) {
      [self updateVisibleTouchPadToWii];
      [self recreateMenu];

      [self.navigationController setNavigationBarHidden:true animated:true];
    }];

    if (_visibleTouchPad == DOLEmulationVisibleTouchPadWiimote ||
        _visibleTouchPad == DOLEmulationVisibleTouchPadSidewaysWiimote ||
        _visibleTouchPad == DOLEmulationVisibleTouchPadClassic) {
      wiimoteAction.state = UIMenuElementStateOn;
    } else {
      wiimoteAction.state = UIMenuElementStateOff;
    }

    [visibleControllerActions addObject:wiimoteAction];
  }

  if (gamecubeTouchPadAttached) {
    UIAction* gamecubeAction = [UIAction actionWithTitle:DOLCoreLocalizedString(@"GameCube Controller") image:nil identifier:nil handler:^(UIAction*) {
      [self updateVisibleTouchPadToGameCube];
      [self recreateMenu];

      [self.navigationController setNavigationBarHidden:true animated:true];
    }];

    if (_visibleTouchPad == DOLEmulationVisibleTouchPadGameCube) {
      gamecubeAction.state = UIMenuElementStateOn;
    } else {
      gamecubeAction.state = UIMenuElementStateOff;
    }

    [visibleControllerActions addObject:gamecubeAction];
  }

  if (wiimoteTouchPadAttached || gamecubeTouchPadAttached) {
    UIAction* noneAction = [UIAction actionWithTitle:DOLCoreLocalizedString(@"Hide") image:nil identifier:nil handler:^(UIAction*) {
      [self updateVisibleTouchPadWithType:DOLEmulationVisibleTouchPadNone];
      [self recreateMenu];

      [self.navigationController setNavigationBarHidden:true animated:true];
    }];

    if (_visibleTouchPad == DOLEmulationVisibleTouchPadNone) {
      noneAction.state = UIMenuElementStateOn;
    } else {
      noneAction.state = UIMenuElementStateOff;
    }

    [visibleControllerActions addObject:noneAction];
  }

  UIMenu* visibleControllerMenu = [UIMenu menuWithTitle:@"Touch Controller" image:[UIImage systemImageNamed:@"gamecontroller"] identifier:nil options:0 children:visibleControllerActions];
  [controllerActions addObject:visibleControllerMenu];

  if (wiimoteTouchPadAttached) {
    TCWiiTouchIRMode irMode = (TCWiiTouchIRMode)Config::Get(Config::MAIN_TOUCH_PAD_IR_MODE);

    // "Disabled" is the mode that hands pointing over to the Motion (gyro/IMU) system below -
    // touch and motion pointing are mutually exclusive (see updatePointerValuesOnWiiTouchPads),
    // so this needs to read as "use motion instead," not just "pointing off," or gyro aiming
    // never visibly does anything and looks completely broken.
    UIMenu* menu = [UIMenu menuWithTitle:@"Touch IR Pointer" image:[UIImage systemImageNamed:@"hand.point.up.left"] identifier:nil options:0 children:@[
      [UIAction actionWithTitle:@"Disabled (Use Motion)" image:nil identifier:nil handler:^(UIAction*) {
        Config::SetBaseOrCurrent(Config::MAIN_TOUCH_PAD_IR_MODE, TCWiiTouchIRModeNone);

        [self updatePointerValuesOnWiiTouchPads];
        [self recreateMenu];

        [self.navigationController setNavigationBarHidden:true animated:true];
      }],
      [UIAction actionWithTitle:@"Follow" image:nil identifier:nil handler:^(UIAction*) {
        Config::SetBaseOrCurrent(Config::MAIN_TOUCH_PAD_IR_MODE, TCWiiTouchIRModeFollow);

        [self updatePointerValuesOnWiiTouchPads];
        [self recreateMenu];

        [self.navigationController setNavigationBarHidden:true animated:true];
      }],
      [UIAction actionWithTitle:@"Drag" image:nil identifier:nil handler:^(UIAction*) {
        Config::SetBaseOrCurrent(Config::MAIN_TOUCH_PAD_IR_MODE, TCWiiTouchIRModeDrag);

        [self updatePointerValuesOnWiiTouchPads];
        [self recreateMenu];

        [self.navigationController setNavigationBarHidden:true animated:true];
      }]
    ]];

    UIAction* selectedAction = (UIAction*)menu.children[(int)irMode];
    selectedAction.state = UIMenuElementStateOn;

    [controllerActions addObject:menu];

    // Motion / gyroscope calibration.
    UIMenu* motionMenu = [UIMenu menuWithTitle:@"Motion" image:[UIImage systemImageNamed:@"gyroscope"] identifier:nil options:0 children:@[
      [UIAction actionWithTitle:@"Calibrate Gyroscope" image:[UIImage systemImageNamed:@"level"] identifier:nil handler:^(UIAction*) {
        [self promptFlatGyroCalibration];
      }],
      [UIAction actionWithTitle:@"Calibrate Gyroscope for TV" image:[UIImage systemImageNamed:@"tv"] identifier:nil handler:^(UIAction*) {
        [self promptTVGyroCalibration];
      }]
    ]];

    [controllerActions addObject:motionMenu];
  }

  NSMutableArray<UIMenuElement*>* stateSlotActions = [[NSMutableArray alloc] init];

  for (int i = 1; i <= State::NUM_STATES; i++) {
    // GetInfoStringOfSlot already returns "Empty" or a formatted save timestamp - previously
    // unused by the iOS UI despite existing precisely for this, so every slot looked identical
    // and a user had no way to tell which ones actually held a save without loading each blind.
    NSString* slotInfo = [NSString stringWithUTF8String:State::GetInfoStringOfSlot(i).c_str()];
    NSString* title = [NSString stringWithFormat:@"Slot %d — %@", i, slotInfo];

    [stateSlotActions addObject:[UIAction actionWithTitle:title image:nil identifier:nil handler:^(UIAction* action) {
      self->_stateSlot = i;
      Config::SetBase(Config::MAIN_SELECTED_STATE_SLOT, i);

      [self recreateMenu];
    }]];
  }

  UIAction* selectedSlotElement = (UIAction*)[stateSlotActions objectAtIndex:Config::GetBase(Config::MAIN_SELECTED_STATE_SLOT) - 1];
  selectedSlotElement.state = UIMenuElementStateOn;
  
  NSMutableArray<UIMenuElement*>* menuItems = [[NSMutableArray alloc] init];
  [menuItems addObject:[UIMenu menuWithTitle:DOLCoreLocalizedString(@"Controllers") image:nil identifier:nil options:UIMenuOptionsDisplayInline children:controllerActions]];
  [menuItems addObject:[UIMenu menuWithTitle:DOLCoreLocalizedString(@"Save State") image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[
    [UIMenu menuWithTitle:DOLCoreLocalizedString(@"Select State Slot") image:nil identifier:nil options:0 children:stateSlotActions],
    [UIAction actionWithTitle:DOLCoreLocalizedString(@"Load State") image:[UIImage systemImageNamed:@"tray.and.arrow.down"] identifier:nil handler:^(UIAction*) {
      DOLHostQueueRunAsync(^{
        State::Load(Core::System::GetInstance(), self->_stateSlot);
      });

      [self.navigationController setNavigationBarHidden:true animated:true];
    }],
    [UIAction actionWithTitle:DOLCoreLocalizedString(@"Save State") image:[UIImage systemImageNamed:@"tray.and.arrow.up"] identifier:nil handler:^(UIAction*) {
      DOLHostQueueRunAsync(^{
        State::Save(Core::System::GetInstance(), self->_stateSlot);
      });

      [self.navigationController setNavigationBarHidden:true animated:true];
    }]
  ]]];
  BOOL isMuted = Config::Get(Config::MAIN_AUDIO_MUTED);
  UIAction* muteAction = [UIAction actionWithTitle:isMuted ? DOLCoreLocalizedString(@"Unmute") : DOLCoreLocalizedString(@"Mute")
                                              image:[UIImage systemImageNamed:isMuted ? @"speaker.slash" : @"speaker.wave.2"]
                                         identifier:nil
                                            handler:^(UIAction*) {
    Config::SetBaseOrCurrent(Config::MAIN_AUDIO_MUTED, !isMuted);
    [self recreateMenu];
  }];

  BOOL showingFps = Config::Get(Config::GFX_SHOW_FPS);
  UIAction* fpsAction = [UIAction actionWithTitle:DOLCoreLocalizedString(@"Show FPS Counter")
                                             image:[UIImage systemImageNamed:@"speedometer"]
                                        identifier:nil
                                           handler:^(UIAction*) {
    Config::SetBaseOrCurrent(Config::GFX_SHOW_FPS, !showingFps);
    [self recreateMenu];
  }];
  fpsAction.state = showingFps ? UIMenuElementStateOn : UIMenuElementStateOff;

  // 0.0 is Dolphin's own "Unlimited" convention (see SpeedLimitViewController, row 0) - reused
  // here rather than inventing a new speed value, so this stays consistent with whatever the
  // Speed Limit setting itself already means. Restoring to 1.0 (100%) on toggle-off rather than
  // whatever the user's base speed limit was set to is a deliberate simplification: this is a
  // quick in-game toggle, not a replacement for the real per-user speed limit setting.
  BOOL isFastForwarding = Config::Get(Config::MAIN_EMULATION_SPEED) == 0.0f;
  UIAction* fastForwardAction = [UIAction actionWithTitle:DOLCoreLocalizedString(@"Fast Forward")
                                                      image:[UIImage systemImageNamed:@"forward.fill"]
                                                 identifier:nil
                                                    handler:^(UIAction*) {
    Config::SetBaseOrCurrent(Config::MAIN_EMULATION_SPEED, isFastForwarding ? 1.0f : 0.0f);
    [self recreateMenu];
  }];
  fastForwardAction.state = isFastForwarding ? UIMenuElementStateOn : UIMenuElementStateOff;

  [menuItems addObject:[UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[
    [UIAction actionWithTitle:DOLCoreLocalizedString(@"Take Screenshot") image:[UIImage systemImageNamed:@"camera"] identifier:nil handler:^(UIAction*) {
      [self takeScreenshot];
    }],
    muteAction,
    fpsAction,
    fastForwardAction
  ]]];

  if ([self emulateSkylanderPortal] && Core::System::GetInstance().IsWii()) {
    [menuItems addObject:[UIMenu menuWithTitle:DOLCoreLocalizedString(@"Tools") image:nil identifier:nil options:UIMenuOptionsDisplayInline
                 children:@[
        [UIAction actionWithTitle:DOLCoreLocalizedString(@"Skylanders Portal") image:[UIImage systemImageNamed:@"externalDrive"] identifier:nil handler:^(UIAction*) {
        UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"Skylanders Manager"
                                       message:nil
                                       preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction* loadAction = [UIAlertAction actionWithTitle:@"Load" style:UIAlertActionStyleDefault
                                                       handler:^(UIAlertAction* action) {
            NSArray<UTType*>* types = @[
                [UTType exportedTypeWithIdentifier:@"me.oatmealdome.dolphinios.skylander-dumps"]
              ];
            UIDocumentPickerViewController* pickerController = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:types];
            pickerController.delegate = self;
            pickerController.modalPresentationStyle = UIModalPresentationPageSheet;
            pickerController.allowsMultipleSelection = false;

            [self presentViewController:pickerController animated:true completion:nil];

        }];
        UIAlertAction* clearAction = [UIAlertAction actionWithTitle:@"Clear" style:UIAlertActionStyleDefault
                                                       handler:^(UIAlertAction* action) {
            auto& system = Core::System::GetInstance();
            if (self.skylanderSlot) {
              bool removed = system.GetSkylanderPortal().RemoveSkylander(self.skylanderSlot - 1);
              if (removed && self.skylanderSlot != 0) {
                  self.skylanderSlot--;
              }
            }
        }];
        UIAlertAction* clearAllAction = [UIAlertAction actionWithTitle:@"Clear All" style:UIAlertActionStyleDefault
                                                       handler:^(UIAlertAction* action) {
            auto& system = Core::System::GetInstance();
            if (self.skylanderSlot) {
              for (int i = 0; i < 16; i++) {
                  system.GetSkylanderPortal().RemoveSkylander(i);
              }
            }
            self.skylanderSlot = 0;
        }];
        [alert addAction:loadAction];
        [alert addAction:clearAction];
        [alert addAction:clearAllAction];
        [self presentViewController:alert animated:YES completion:nil];
    }]
    ]]];
  }

  self.navigationItem.leftBarButtonItem.menu = [UIMenu menuWithChildren:menuItems];
}

// Motion/gyro pointing only ever actually moves the in-game cursor while Touch IR Pointer is
// set to "Disabled" (updatePointerValuesOnWiiTouchPads force-disables the IMUPoint group
// whenever touch mode is Follow/Drag) - a user calibrating gyro clearly means to use it, so
// switch modes for them here rather than leaving them to discover a separate, non-obviously
// related menu item first (this exact gap is why gyro aiming looked completely dead: it was
// silently ignored while the default touch mode, Drag, was still active).
- (void)switchToMotionPointingIfNeeded {
  if ((TCWiiTouchIRMode)Config::Get(Config::MAIN_TOUCH_PAD_IR_MODE) != TCWiiTouchIRModeNone) {
    Config::SetBaseOrCurrent(Config::MAIN_TOUCH_PAD_IR_MODE, TCWiiTouchIRModeNone);
    [self updatePointerValuesOnWiiTouchPads];
    [self recreateMenu];
  }
}

// "Calibrate Gyroscope": lay the device flat and still, then confirm. Measures the
// resting gyro bias and subtracts it from all future readings to kill motion drift.
- (void)promptFlatGyroCalibration {
  UIAlertController* alert = [UIAlertController
      alertControllerWithTitle:@"Calibrate Gyroscope"
                       message:@"Lay your device down perfectly flat and still on a level "
                               @"surface, then tap Calibrate. Hold still for a moment. This "
                               @"also switches Touch IR Pointer to Motion, so aiming the device "
                               @"actually moves the in-game pointer afterward."
                preferredStyle:UIAlertControllerStyleAlert];

  [alert addAction:[UIAlertAction actionWithTitle:@"Calibrate"
                                            style:UIAlertActionStyleDefault
                                          handler:^(UIAlertAction*) {
    [self switchToMotionPointingIfNeeded];

    [[TCDeviceMotion shared] calibrateFlat:^{
      UIAlertController* done = [UIAlertController
          alertControllerWithTitle:@"Gyroscope Calibrated"
                           message:@"Resting drift has been zeroed. Motion pointing is now active."
                    preferredStyle:UIAlertControllerStyleAlert];
      [done addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
      [self presentViewController:done animated:YES completion:nil];
    }];
  }]];
  [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

  [self presentViewController:alert animated:YES completion:nil];
}

// "Calibrate Gyroscope for TV": hold the device flat and point its front-middle edge
// straight at the TV, then confirm. Pulses the IMU-IR Recenter so the current orientation
// becomes forward — aiming at the TV then centers the pointer, no arm-strain tilt.
- (void)promptTVGyroCalibration {
  UIAlertController* alert = [UIAlertController
      alertControllerWithTitle:@"Calibrate Gyroscope for TV"
                       message:@"Hold your device flat and point the front-middle of it "
                               @"directly at your TV, then tap Calibrate. The pointer will "
                               @"re-center to face your TV. This also switches Touch IR Pointer "
                               @"to Motion, so aiming the device actually moves the in-game "
                               @"pointer afterward."
                preferredStyle:UIAlertControllerStyleAlert];

  [alert addAction:[UIAlertAction actionWithTitle:@"Calibrate"
                                            style:UIAlertActionStyleDefault
                                          handler:^(UIAlertAction*) {
    [self switchToMotionPointingIfNeeded];
    [[TCDeviceMotion shared] recenterPointer];
  }]];
  [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

  [self presentViewController:alert animated:YES completion:nil];
}

// Haptic-only feedback rather than a modal alert -- a screenshot should never interrupt
// gameplay the way a tap-to-dismiss dialog would.
- (void)takeScreenshot {
  [[EmulationCoordinator shared] captureScreenshotWithCompletion:^(UIImage* _Nullable image) {
    UINotificationFeedbackGenerator* feedback = [[UINotificationFeedbackGenerator alloc] init];

    if (image == nil) {
      [feedback notificationOccurred:UINotificationFeedbackTypeError];
      return;
    }

    UIImageWriteToSavedPhotosAlbum(image, self, @selector(screenshot:didFinishSavingWithError:contextInfo:), (__bridge void*)feedback);
  }];
}

- (void)screenshot:(UIImage*)image didFinishSavingWithError:(NSError* _Nullable)error contextInfo:(void*)contextInfo {
  UINotificationFeedbackGenerator* feedback = (__bridge UINotificationFeedbackGenerator*)contextInfo;

  [feedback notificationOccurred:error == nil ? UINotificationFeedbackTypeSuccess : UINotificationFeedbackTypeError];
}

- (void)viewDidLayoutSubviews {
  if (g_presenter) {
    g_presenter->ResizeSurface();
  }

  [[TCDeviceMotion shared] statusBarOrientationChanged];

  [self updatePointerValuesOnWiiTouchPads];
}

- (BOOL)prefersHomeIndicatorAutoHidden {
  return true;
}

- (void)receiveTitleChangedNotificationiOS {
  dispatch_async(dispatch_get_main_queue(), ^{
    if (Core::System::GetInstance().IsWii()) {
      [self updateVisibleTouchPadToWii];
    } else {
      [self updateVisibleTouchPadToGameCube];
    }

    [self recreateMenu];
  });
}

- (void)receiveRequestRenderWindowSizeNotificationiOS {
  dispatch_async(dispatch_get_main_queue(), ^{
    if (Core::System::GetInstance().IsWii()) {
      [self updatePointerValuesOnWiiTouchPads];
    }
  });
}

- (bool)isWiimoteTouchPadAttached {
  if (Config::Get(Config::GetInfoForWiimoteSource(0)) != WiimoteSource::Emulated) {
    // Nothing is plugged in to this port.
    return false;
  }

  const auto wiimote = static_cast<WiimoteEmu::Wiimote*>(Wiimote::GetConfig()->GetController(0));

  if (wiimote->GetDefaultDevice().source != "iOS") {
    // A real controller is mapped to this port.
    return false;
  }

  return true;
}

- (bool)emulateSkylanderPortal {
  return Config::Get(Config::MAIN_EMULATE_SKYLANDER_PORTAL);
}

- (bool)isGameCubeTouchPadAttached {
  if (Config::Get(Config::GetInfoForSIDevice(0)) == SerialInterface::SIDEVICE_NONE) {
    // Nothing is plugged in to this port.
    return false;
  }

  const auto device = Pad::GetConfig()->GetController(0);

  if (device->GetDefaultDevice().source != "iOS") {
    // A real controller is mapped to this port.
    return false;
  }

  return true;
}

- (void)updateVisibleTouchPadToWii {
  if (![self isWiimoteTouchPadAttached]) {
    // Fallback to GameCube in case port 1 is bound to the touchscreen.
    [self updateVisibleTouchPadToGameCube];

    return;
  }

  DOLEmulationVisibleTouchPad targetTouchPad;

  const auto wiimote = static_cast<WiimoteEmu::Wiimote*>(Wiimote::GetConfig()->GetController(0));

  if (wiimote->GetActiveExtensionNumber() == WiimoteEmu::ExtensionNumber::CLASSIC) {
    targetTouchPad = DOLEmulationVisibleTouchPadClassic;
  } else if (wiimote->IsSideways()) {
    targetTouchPad = DOLEmulationVisibleTouchPadSidewaysWiimote;
  } else {
    targetTouchPad = DOLEmulationVisibleTouchPadWiimote;
  }

  [self updateVisibleTouchPadWithType:targetTouchPad];

  [self updatePointerValuesOnWiiTouchPads];

  // The pre-game calibration screen already ran the flat gyro-bias calibration before boot
  // (that part doesn't need the core running). If the player chose "Point at TV" mode there,
  // finish the job now that the Wiimote pointer is actually live: switch Touch IR Pointer to
  // Motion and recenter on their current, presumably-still-aimed-at-the-TV orientation. Only
  // once per session -- later title changes (e.g. Wii Menu handing off to the game) shouldn't
  // re-recenter using whatever orientation the device happens to be in at that later moment.
  if (!_didApplyPreGameTVCalibration &&
      [[PreGameCalibrationPreferences shared] calibrationMode] == PointerCalibrationModePointAtTV) {
    _didApplyPreGameTVCalibration = true;

    [self switchToMotionPointingIfNeeded];
    [[TCDeviceMotion shared] recenterPointer];
  }
}

- (void)updateVisibleTouchPadToGameCube {
  if (![self isGameCubeTouchPadAttached]) {
    return;
  }

  [self updateVisibleTouchPadWithType:DOLEmulationVisibleTouchPadGameCube];
}

- (void)updateVisibleTouchPadWithType:(DOLEmulationVisibleTouchPad)touchPad {
  if (_visibleTouchPad == touchPad) {
    return;
  }

  TCDeviceMotion* motion = [TCDeviceMotion shared];

  if (touchPad == DOLEmulationVisibleTouchPadWiimote || touchPad == DOLEmulationVisibleTouchPadSidewaysWiimote || touchPad == DOLEmulationVisibleTouchPadClassic) {
    [motion setMotionEnabled:true];
    [motion setPort:4]; // Touchscreen device 4 is used for the Wiimote
  } else {
    [motion setMotionEnabled:false];
  }

  NSInteger targetIdx = touchPad - 1;

  for (int i = 0; i < [self.touchPads count]; i++) {
    TCView* padView = self.touchPads[i];
    padView.userInteractionEnabled = i == targetIdx;
  }

  const float targetOpacity = Config::Get(Config::MAIN_TOUCH_PAD_OPACITY);

  [UIView animateWithDuration:0.5f animations:^{
    for (int i = 0; i < [self.touchPads count]; i++) {
      TCView* padView = self.touchPads[i];
      padView.alpha = i == targetIdx ? targetOpacity : 0.0f;
    }
  }];

  _visibleTouchPad = touchPad;
}

- (void)updatePointerValuesOnWiiTouchPads {
  if (!g_presenter) {
    return;
  }

  TCWiiTouchIRMode irMode = TCWiiTouchIRModeNone;

  if ([self isWiimoteTouchPadAttached]) {
    irMode = (TCWiiTouchIRMode)Config::Get(Config::MAIN_TOUCH_PAD_IR_MODE);

    ControllerEmu::ControlGroup* group = Wiimote::GetWiimoteGroup(0, WiimoteEmu::WiimoteGroup::IMUPoint);
    group->enabled.SetValue(irMode == TCWiiTouchIRModeNone);
  }

  for (int i = 0; i < [self.touchPads count]; i++) {
    TCView* padView = self.touchPads[i];

    if ([padView isKindOfClass:[TCWiiPad class]]) {
      TCWiiPad* wiiPadView = (TCWiiPad*)padView;

      [wiiPadView setTouchIRMode:irMode];
      [wiiPadView resetPointer];
      [wiiPadView recalculatePointerValuesWithNew_rect:self.rendererView.bounds game_aspect:g_presenter->CalculateDrawAspectRatio()];
    }
  }
}

- (IBAction)pullDownPressed:(id)sender {
  [self updateNavigationBar:false];
}

- (void)receiveEmulationEndNotificationiOS {
  if (@available(iOS 15.0, *)) {
    dispatch_async(dispatch_get_main_queue(), ^{
      [[VirtualMFiControllerManager shared] disconnectController];
    });
  }

  [[TCDeviceMotion shared] setMotionEnabled:false];
}

- (void)documentPicker:(UIDocumentPickerViewController*)controller didPickDocumentsAtURLs:(NSArray<NSURL*>*)urls {
    NSString* sourcePath = [urls[0] path];
    std::string path = std::string([sourcePath UTF8String]);
    File::IOFile sky_file(path, "r+b");
    if (!sky_file)
    {
        UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"Failed to Open Skylander File!"
                                       message:nil
                                       preferredStyle:UIAlertControllerStyleAlert];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    std::array<u8, 0x40 * 0x10> file_data;
    if (!sky_file.ReadBytes(file_data.data(), file_data.size()))
    {
        UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"Failed to Read Skylander File!"
                                       message:nil
                                       preferredStyle:UIAlertControllerStyleAlert];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    auto& system = Core::System::GetInstance();
    std::pair<u16, u16> id_var = system.GetSkylanderPortal().CalculateIDs(file_data);
    u8 portal_slot = system.GetSkylanderPortal().LoadSkylander(std::make_unique<IOS::HLE::USB::SkylanderFigure>(std::move(sky_file)));
    if (portal_slot == 0xFF)
    {
        UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"Failed to Load Skylander File!"
                                       message:nil
                                       preferredStyle:UIAlertControllerStyleAlert];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    self.skylanderSlot = portal_slot + 1;
}

@end
