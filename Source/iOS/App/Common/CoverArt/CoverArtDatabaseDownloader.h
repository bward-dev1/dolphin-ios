// Copyright 2026 DolphiniOS Project
// SPDX-License-Identifier: GPL-2.0-or-later

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Downloads GameTDB cover art for EVERY game DiscIO/wiitdb.txt knows about - not just the ones
// currently installed - so the library browses with real box art even before you own a game
// (or just for completeness). Writes into the exact same on-disk cover cache
// UICommon::GameFile::DownloadDefaultCover() already uses, so anything downloaded here is
// picked up automatically the next time a game list rescan runs; already-cached covers are
// skipped, so re-running this after installing more games only fetches what's missing.
@interface CoverArtDatabaseDownloader : NSObject

+ (instancetype)shared;

@property (nonatomic, readonly) BOOL isDownloading;
@property (nonatomic, readonly) NSInteger totalCount;
@property (nonatomic, readonly) NSInteger completedCount;

// Counts how many covers are missing without downloading anything, for a "this will fetch
// about N images" estimate before the user commits. Runs synchronously; call off the main
// thread if the caller cares about not blocking briefly (parses a ~10k line file).
- (NSInteger)countMissingCovers;

// progressHandler is called on the main queue after every completed (or skipped) entry.
// completionHandler is called on the main queue once with whether the run finished the whole
// list (NO) or was cancelled partway through (YES).
- (void)startWithProgressHandler:(void (^)(NSInteger completed, NSInteger total))progressHandler
               completionHandler:(void (^)(BOOL wasCancelled))completionHandler;

- (void)cancel;

@end

NS_ASSUME_NONNULL_END
