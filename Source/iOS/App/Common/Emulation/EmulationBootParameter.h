// Copyright 2022 DolphiniOS Project
// SPDX-License-Identifier: GPL-2.0-or-later

#import <Foundation/Foundation.h>

#import <memory>

#import "DiscIO/Enums.h"

#import "EmulationBootType.h"

class BootParameters;
class BootSessionData;

NS_ASSUME_NONNULL_BEGIN

@interface EmulationBootParameter : NSObject

@property (nonatomic) EmulationBootType bootType;
@property (nonatomic) NSString* path;
@property (nonatomic) NSString* secondPath;
@property (nonatomic) bool isNKit;
@property (nonatomic) DiscIO::Region iplRegion;

// Whether this boot produces an emulated Wii Remote. Only meaningful for
// EmulationBootTypeFile (the other two boot types are unambiguous and are answered directly by
// -targetsWii). Defaults to true so any boot path that forgets to set it errs toward showing
// Wii-specific pre-boot UI rather than silently skipping it.
@property (nonatomic) bool isWiiTitle;

// Set only for a NetPlay-triggered boot: transfers ownership of a BootSessionData built by
// NetPlayClient (movie/save-sync settings for this session) instead of a default-constructed
// one. Consumed (and nulled out) the first time generateDolphinBootParameter runs.
@property (nonatomic) BootSessionData* _Nullable netplayBootSessionData;

- (std::unique_ptr<BootParameters>) generateDolphinBootParameter;

// True when this boot will emulate a Wii Remote, i.e. when Wii-only pre-boot UI applies.
- (BOOL)targetsWii;

@end

NS_ASSUME_NONNULL_END
