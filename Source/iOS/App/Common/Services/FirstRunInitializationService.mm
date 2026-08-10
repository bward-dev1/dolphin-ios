// Copyright 2022 DolphiniOS Project
// SPDX-License-Identifier: GPL-2.0-or-later

#import "FirstRunInitializationService.h"

#import "Common/FileUtil.h"
#import "Common/IniFile.h"

#import "Core/Config/MainSettings.h"
#import "Core/HW/GCPad.h"
#import "Core/HW/Wiimote.h"

#import "InputCommon/ControllerEmu/ControllerEmu.h"
#import "InputCommon/InputConfig.h"

#import "BootNoticeManager.h"

#import "Swift.h"

// Set on the very first launch, cleared by WelcomeOnboardingViewController once the user has
// actually finished the screen. Keep in sync with WelcomeOnboardingViewController.swift.
static NSString* const kWelcomeOnboardingPendingKey = @"welcome_onboarding_pending";

@implementation FirstRunInitializationService

- (void)importDefaultProfileForInputConfig:(InputConfig*)config {
  ControllerEmu::EmulatedController* controller = config->GetController(0);
  
  const std::string builtInPath = config->GetSysProfileDirectoryPath() + "Touchscreen.ini";
  
  Common::IniFile iniFile;
  iniFile.Load(builtInPath);
  
  controller->LoadConfig(iniFile.GetOrCreateSection("Profile"));
  controller->UpdateReferences(g_controller_interface);
  
  config->SaveConfig();
}

- (BOOL)application:(UIApplication*)application didFinishLaunchingWithOptions:(nullable NSDictionary<UIApplicationLaunchOptionsKey,id>*)launchOptions {
  NSUserDefaults* userDefaults = NSUserDefaults.standardUserDefaults;
  
  NSURL* defaultsPath = [[NSBundle mainBundle] URLForResource:@"DefaultPreferences" withExtension:@"plist"];
  NSDictionary* defaultsDict = [NSDictionary dictionaryWithContentsOfURL:defaultsPath];
  [userDefaults registerDefaults:defaultsDict];
  
  NSInteger launchTimes = [userDefaults integerForKey:@"launch_times"];
  
  [userDefaults setInteger:launchTimes + 1 forKey:@"launch_times"];
  
  if (launchTimes == 0) {
    [self importDefaultProfileForInputConfig:Pad::GetConfig()];
    [self importDefaultProfileForInputConfig:Wiimote::GetConfig()];
    
    Config::SetBase(Config::MAIN_GFX_BACKEND, "Metal");

    [userDefaults setBool:true forKey:kWelcomeOnboardingPendingKey];
  }

  // Deliberately outside the launchTimes == 0 block. launch_times is incremented above, before
  // the welcome screen has been shown, so gating the enqueue on it meant a crash or a force quit
  // during onboarding lost the app's only onboarding permanently. The flag below survives that
  // and is only cleared once the user taps Get Started.
  //
  // The unofficial-build notice used to be enqueued alongside this as a second full screen; it is
  // now a section inside the welcome screen, so first launch is one screen and one tap. (Because
  // the boot notice queue is a navigation stack, the two were also being shown in the reverse of
  // the intended order.)
  if ([userDefaults boolForKey:kWelcomeOnboardingPendingKey]) {
    [[BootNoticeManager shared] enqueueViewController:[[WelcomeOnboardingViewController alloc] init]];
  }

  return true;
}

@end
