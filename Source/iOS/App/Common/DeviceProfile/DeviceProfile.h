// Copyright 2026 DolphiniOS Project
// SPDX-License-Identifier: GPL-2.0-or-later

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, DevicePerformanceTier) {
  DevicePerformanceTierLow,
  DevicePerformanceTierMedium,
  DevicePerformanceTierHigh,
  DevicePerformanceTierUltra,
};

// Detects what this specific device actually is - using only things Apple lets an app query
// directly (hw.machine model identifier, physical RAM, active core count) plus the app's own
// already-working JIT status - and derives a performance tier from that, with no user input
// required at all. Settings this maps to are picked from Dolphin's own real config keys
// (Config::GFX_*/MAIN_*), not anything invented for this feature.
@interface DeviceProfile : NSObject

+ (instancetype)shared;

// Raw hw.machine string, e.g. "iPad13,8" or "iPhone15,3". Never empty in practice.
@property (nonatomic, readonly) NSString* deviceIdentifier;

// Best-effort human-readable chip name derived from deviceIdentifier, e.g. "Apple M1" or
// "Apple A15 Bionic". Falls back to "Unknown Apple Silicon" for identifiers newer than this
// build's own knowledge, or "Simulator"/"Unknown Device" as appropriate - never nil.
@property (nonatomic, readonly) NSString* chipName;

@property (nonatomic, readonly) NSInteger physicalMemoryMB;
@property (nonatomic, readonly) NSInteger processorCount;
@property (nonatomic, readonly) BOOL jitAvailable;

@property (nonatomic, readonly) DevicePerformanceTier tier;
@property (nonatomic, readonly) NSString* tierDisplayName;
// One sentence explaining what the tier means practically, for display alongside the detected
// facts (e.g. "Internal resolution 2x, dual-core enabled, accurate audio").
@property (nonatomic, readonly) NSString* tierSummary;

// Re-runs JIT detection (cheap, synchronous) - call before reading jitAvailable/tier if the
// caller wants the freshest possible answer (e.g. right before showing the optimize screen).
- (void)refresh;

// Applies the Dolphin Config:: settings this device's tier implies. Real, current settings keys
// (GFX_EFB_SCALE, MAIN_CPU_THREAD, GFX_VSYNC, MAIN_DSP_HLE, GFX_SAFE_TEXTURE_CACHE_COLOR_SAMPLES,
// MAIN_SYNC_GPU) - not placeholders. Deliberately never touches MAIN_MMU: that's a per-game
// compatibility need, not a device-performance dial - see the comment in applyOptimizedSettings.
- (void)applyOptimizedSettings;

// One human-readable line per setting applyOptimizedSettings would change for the CURRENT tier,
// e.g. "Internal Resolution: 2x" - computed the same way applyOptimizedSettings decides values,
// but read-only, so a caller (the Optimize Settings screen) can show what tapping Apply will
// actually do before the user commits to it.
- (NSArray<NSString*>*)previewSettingsDescriptions;

@end

NS_ASSUME_NONNULL_END
