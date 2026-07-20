// Copyright 2026 DolphiniOS Project
// SPDX-License-Identifier: GPL-2.0-or-later

#import "DeviceProfile.h"

#import <sys/utsname.h>

#import "Core/Config/GraphicsSettings.h"
#import "Core/Config/MainSettings.h"
#import "Core/PowerPC/PowerPC.h"

#import "JitManager.h"

// Best-effort hw.machine -> marketing chip name table. iPad numbering in particular mixes chip
// generations within the same "iPadN," family depending on the minor number (e.g. iPad13,4-7 is
// M1 while iPad13,18-19 is A14) - Apple doesn't expose the chip directly, so this is the same
// kind of identifier table every third-party "what chip is this" library maintains by hand.
// Display only - it does not feed into tier at all. RAM + core count + JIT availability (all
// queried directly, no guessing) are the only inputs to the actual settings that get applied.
static NSDictionary<NSString*, NSString*>* DeviceIdentifierToChipName() {
  static NSDictionary<NSString*, NSString*>* table = @{
    // iPhone
    @"iPhone8,1" : @"Apple A9", @"iPhone8,2" : @"Apple A9", @"iPhone8,4" : @"Apple A9",
    @"iPhone9,1" : @"Apple A10 Fusion", @"iPhone9,2" : @"Apple A10 Fusion",
    @"iPhone9,3" : @"Apple A10 Fusion", @"iPhone9,4" : @"Apple A10 Fusion",
    @"iPhone10,1" : @"Apple A11 Bionic", @"iPhone10,2" : @"Apple A11 Bionic",
    @"iPhone10,3" : @"Apple A11 Bionic", @"iPhone10,4" : @"Apple A11 Bionic",
    @"iPhone10,5" : @"Apple A11 Bionic", @"iPhone10,6" : @"Apple A11 Bionic",
    @"iPhone11,2" : @"Apple A12 Bionic", @"iPhone11,4" : @"Apple A12 Bionic",
    @"iPhone11,6" : @"Apple A12 Bionic", @"iPhone11,8" : @"Apple A12 Bionic",
    @"iPhone12,1" : @"Apple A13 Bionic", @"iPhone12,3" : @"Apple A13 Bionic",
    @"iPhone12,5" : @"Apple A13 Bionic", @"iPhone12,8" : @"Apple A13 Bionic",
    @"iPhone13,1" : @"Apple A14 Bionic", @"iPhone13,2" : @"Apple A14 Bionic",
    @"iPhone13,3" : @"Apple A14 Bionic", @"iPhone13,4" : @"Apple A14 Bionic",
    @"iPhone14,2" : @"Apple A15 Bionic", @"iPhone14,3" : @"Apple A15 Bionic",
    @"iPhone14,4" : @"Apple A15 Bionic", @"iPhone14,5" : @"Apple A15 Bionic",
    @"iPhone14,6" : @"Apple A15 Bionic", @"iPhone14,7" : @"Apple A15 Bionic",
    @"iPhone14,8" : @"Apple A15 Bionic",
    @"iPhone15,2" : @"Apple A16 Bionic", @"iPhone15,3" : @"Apple A16 Bionic",
    @"iPhone15,4" : @"Apple A16 Bionic", @"iPhone15,5" : @"Apple A16 Bionic",
    @"iPhone16,1" : @"Apple A17 Pro", @"iPhone16,2" : @"Apple A17 Pro",
    @"iPhone17,1" : @"Apple A18 Pro", @"iPhone17,2" : @"Apple A18 Pro",
    @"iPhone17,3" : @"Apple A18", @"iPhone17,4" : @"Apple A18", @"iPhone17,5" : @"Apple A18",
    @"iPhone18,1" : @"Apple A19 Pro", @"iPhone18,2" : @"Apple A19 Pro",
    @"iPhone18,3" : @"Apple A19", @"iPhone18,4" : @"Apple A19 Pro", @"iPhone18,5" : @"Apple A19",
    // iPad
    @"iPad6,11" : @"Apple A9", @"iPad6,12" : @"Apple A9",
    @"iPad7,5" : @"Apple A9", @"iPad7,6" : @"Apple A9",
    @"iPad7,11" : @"Apple A10 Fusion", @"iPad7,12" : @"Apple A10 Fusion",
    @"iPad11,6" : @"Apple A12 Bionic", @"iPad11,7" : @"Apple A12 Bionic",
    @"iPad11,3" : @"Apple A12 Bionic", @"iPad11,4" : @"Apple A12 Bionic",
    @"iPad7,3" : @"Apple A10X Fusion", @"iPad7,4" : @"Apple A10X Fusion",
    @"iPad8,1" : @"Apple A12X Bionic", @"iPad8,2" : @"Apple A12X Bionic",
    @"iPad8,3" : @"Apple A12X Bionic", @"iPad8,4" : @"Apple A12X Bionic",
    @"iPad8,5" : @"Apple A12X Bionic", @"iPad8,6" : @"Apple A12X Bionic",
    @"iPad8,7" : @"Apple A12X Bionic", @"iPad8,8" : @"Apple A12X Bionic",
    @"iPad8,9" : @"Apple A12Z Bionic", @"iPad8,10" : @"Apple A12Z Bionic",
    @"iPad8,11" : @"Apple A12Z Bionic", @"iPad8,12" : @"Apple A12Z Bionic",
    @"iPad11,1" : @"Apple A12 Bionic", @"iPad11,2" : @"Apple A12 Bionic",
    @"iPad12,1" : @"Apple A13 Bionic", @"iPad12,2" : @"Apple A13 Bionic",
    @"iPad14,1" : @"Apple A15 Bionic", @"iPad14,2" : @"Apple A15 Bionic",
    @"iPad13,1" : @"Apple A14 Bionic", @"iPad13,2" : @"Apple A14 Bionic",
    @"iPad13,18" : @"Apple A14 Bionic", @"iPad13,19" : @"Apple A14 Bionic",
    @"iPad13,4" : @"Apple M1", @"iPad13,5" : @"Apple M1",
    @"iPad13,6" : @"Apple M1", @"iPad13,7" : @"Apple M1",
    @"iPad13,8" : @"Apple M1", @"iPad13,9" : @"Apple M1",
    @"iPad13,10" : @"Apple M1", @"iPad13,11" : @"Apple M1",
    @"iPad13,16" : @"Apple M1", @"iPad13,17" : @"Apple M1",
    @"iPad14,3" : @"Apple M2", @"iPad14,4" : @"Apple M2",
    @"iPad14,5" : @"Apple M2", @"iPad14,6" : @"Apple M2",
    @"iPad14,8" : @"Apple M2", @"iPad14,9" : @"Apple M2",
    @"iPad14,10" : @"Apple M2", @"iPad14,11" : @"Apple M2",
    @"iPad16,1" : @"Apple A17 Pro", @"iPad16,2" : @"Apple A17 Pro",
    @"iPad16,3" : @"Apple M4", @"iPad16,4" : @"Apple M4",
    @"iPad16,5" : @"Apple M4", @"iPad16,6" : @"Apple M4",
    // iPad Air 11"/13" (M3, Mar 2025) - not to be confused with iPad15,7/8 below (the
    // plain "iPad (A16)"), same iPad15 family but a different model entirely.
    @"iPad15,3" : @"Apple M3", @"iPad15,4" : @"Apple M3",
    @"iPad15,5" : @"Apple M3", @"iPad15,6" : @"Apple M3",
    @"iPad15,7" : @"Apple A16 Bionic", @"iPad15,8" : @"Apple A16 Bionic",
  };
  return table;
}

@implementation DeviceProfile {
  BOOL _jitAvailable;
}

+ (instancetype)shared {
  static DeviceProfile* instance = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    instance = [[DeviceProfile alloc] init];
  });
  return instance;
}

- (instancetype)init {
  self = [super init];
  if (self) {
    struct utsname systemInfo;
    uname(&systemInfo);
    _deviceIdentifier = [NSString stringWithCString:systemInfo.machine encoding:NSUTF8StringEncoding] ?: @"Unknown";

    _physicalMemoryMB = (NSInteger)(NSProcessInfo.processInfo.physicalMemory / (1024 * 1024));
    _processorCount = NSProcessInfo.processInfo.activeProcessorCount;

    [self refresh];
  }
  return self;
}

- (void)refresh {
  [[JitManager shared] recheckIfJitIsAcquired];
  _jitAvailable = [JitManager shared].acquiredJit;
}

- (NSString*)chipName {
  if ([_deviceIdentifier hasPrefix:@"i386"] || [_deviceIdentifier hasPrefix:@"x86_64"] ||
      [_deviceIdentifier hasPrefix:@"arm64"]) {
    return @"Simulator (Host CPU)";
  }

  NSString* known = DeviceIdentifierToChipName()[_deviceIdentifier];
  if (known != nil) {
    return known;
  }

  // Unknown to our table - most likely a device newer than this build knows about. Give a
  // reasonable, honest fallback rather than pretending to know.
  if ([_deviceIdentifier hasPrefix:@"iPhone"] || [_deviceIdentifier hasPrefix:@"iPad"]) {
    return [NSString stringWithFormat:@"Apple Silicon (%@, not yet in this build's chip table)", _deviceIdentifier];
  }

  return @"Unknown Device";
}

- (DevicePerformanceTier)tier {
  // RAM is the single most reliable, directly-measured signal for how much headroom Dolphin's
  // texture cache / hires-texture / MMU features actually have to work with, so it's the
  // primary driver; core count and JIT availability adjust it from there.
  DevicePerformanceTier tier;
  if (_physicalMemoryMB >= 15000) {
    tier = DevicePerformanceTierUltra;
  } else if (_physicalMemoryMB >= 7500) {
    tier = DevicePerformanceTierHigh;
  } else if (_physicalMemoryMB >= 3500) {
    tier = DevicePerformanceTierMedium;
  } else {
    tier = DevicePerformanceTierLow;
  }

  if (!_jitAvailable && tier > DevicePerformanceTierMedium) {
    // Without JIT, PowerPC::CPUCore falls back to the interpreter, which is drastically slower
    // regardless of how much RAM/cores are available - don't let a high RAM figure alone imply
    // settings that assume JIT-speed CPU emulation.
    tier = DevicePerformanceTierMedium;
  }

  if (_processorCount <= 2 && tier > DevicePerformanceTierLow) {
    tier = DevicePerformanceTierLow;
  }

  return tier;
}

- (NSString*)tierDisplayName {
  switch (self.tier) {
  case DevicePerformanceTierUltra:
    return @"Ultra";
  case DevicePerformanceTierHigh:
    return @"High";
  case DevicePerformanceTierMedium:
    return @"Medium";
  case DevicePerformanceTierLow:
  default:
    return @"Low";
  }
}

- (NSString*)tierSummary {
  switch (self.tier) {
  case DevicePerformanceTierUltra:
    return @"Auto (display-matched) resolution scaling, dual-core enabled, accurate audio.";
  case DevicePerformanceTierHigh:
    return @"2x internal resolution, dual-core enabled, accurate audio.";
  case DevicePerformanceTierMedium:
    return @"1x internal resolution, single-core, fast audio - tuned for consistent frame pacing.";
  case DevicePerformanceTierLow:
  default:
    return @"Lowest-overhead settings across the board - prioritizes just running smoothly.";
  }
}

namespace {
// Single source of truth for what a tier means in terms of real settings values - both
// applyOptimizedSettings and previewSettingsDescriptions read from this, so the preview a user
// sees before tapping Apply can never drift out of sync with what Apply actually does.
struct TierSettings {
  int efb_scale;
  bool cpu_thread;
  bool vsync;
  bool dsp_hle;
  int texture_cache_samples;
  bool sync_gpu;
};

TierSettings SettingsForTier(DevicePerformanceTier tier) {
  switch (tier) {
  case DevicePerformanceTierUltra:
    return {0, true, true, false, 0, true};
  case DevicePerformanceTierHigh:
    return {2, true, true, false, 512, false};
  case DevicePerformanceTierMedium:
    return {1, false, true, true, 128, false};
  case DevicePerformanceTierLow:
  default:
    return {1, false, false, true, 128, false};
  }
}
}  // namespace

- (void)applyOptimizedSettings {
  [self refresh];

  const TierSettings settings = SettingsForTier(self.tier);

  // MMU emulation is deliberately never touched here. Whether a title needs it is a per-game
  // compatibility requirement handled by Dolphin's own per-game .ini overrides (see
  // GameConfigLoader), not a device-performance dial - forcing it on for every Ultra-tier game
  // would cost real overhead on titles that don't need it, and forcing it off for every
  // lower-tier game could break the rare title that does and doesn't have a curated override
  // yet. Leave whatever value the user or the per-game layer already has.
  Config::SetBaseOrCurrent(Config::GFX_EFB_SCALE, settings.efb_scale);
  Config::SetBaseOrCurrent(Config::MAIN_CPU_THREAD, settings.cpu_thread);
  Config::SetBaseOrCurrent(Config::GFX_VSYNC, settings.vsync);
  Config::SetBaseOrCurrent(Config::MAIN_DSP_HLE, settings.dsp_hle);
  Config::SetBaseOrCurrent(Config::GFX_SAFE_TEXTURE_CACHE_COLOR_SAMPLES, settings.texture_cache_samples);
  Config::SetBaseOrCurrent(Config::MAIN_SYNC_GPU, settings.sync_gpu);

  if (!_jitAvailable) {
    // No JIT acquired - CachedInterpreter is the correct/only sane choice; the full JIT64/JITArm64
    // backends require real JIT capability the app doesn't currently have.
    Config::SetBaseOrCurrent(Config::MAIN_CPU_CORE, PowerPC::CPUCore::CachedInterpreter);
  } else {
    Config::SetBaseOrCurrent(Config::MAIN_CPU_CORE, PowerPC::DefaultCPUCore());
  }
}

- (NSArray<NSString*>*)previewSettingsDescriptions {
  const TierSettings settings = SettingsForTier(self.tier);

  NSString* resolutionDescription =
      settings.efb_scale == 0 ? @"Auto (display-matched)" : [NSString stringWithFormat:@"%dx", settings.efb_scale];

  NSMutableArray<NSString*>* lines = [NSMutableArray array];
  [lines addObject:[NSString stringWithFormat:@"Internal Resolution: %@", resolutionDescription]];
  [lines addObject:[NSString stringWithFormat:@"Dual Core: %@", settings.cpu_thread ? @"On" : @"Off"]];
  [lines addObject:[NSString stringWithFormat:@"V-Sync: %@", settings.vsync ? @"On" : @"Off"]];
  [lines addObject:[NSString stringWithFormat:@"Audio: %@", settings.dsp_hle ? @"Fast (HLE)" : @"Accurate (LLE)"]];
  [lines addObject:[NSString stringWithFormat:@"CPU Core: %@",
                     _jitAvailable ? @"JIT" : @"Cached Interpreter (no JIT)"]];

  return lines;
}

@end
