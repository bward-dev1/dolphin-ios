// Copyright 2026 DolphiniOS Project
// SPDX-License-Identifier: GPL-2.0-or-later

#import "CoverArtDatabaseDownloader.h"

#import "Common/FileUtil.h"

#import "FoundationStringUtil.h"

static NSInteger const kMaxConcurrentDownloads = 4;

@implementation CoverArtDatabaseDownloader {
  NSURLSession* _session;
  NSString* _coverCacheDir;

  // All state below is only ever touched on the main thread: every NSURLSessionDataTask
  // completion hops back via dispatch_async(dispatch_get_main_queue(), ...) before touching it,
  // and callers are expected to start/cancel from the main thread too (this is a UI-driven bulk
  // operation, not a real-time one) - so there's no locking, matching how a simple sequential
  // rate limiter should look given nothing here needs to race.
  NSArray<NSString*>* _pendingIDs;
  NSUInteger _nextIndex;
  NSInteger _activeCount;
  BOOL _cancelled;
  void (^_progressHandler)(NSInteger completed, NSInteger total);
  void (^_completionHandler)(BOOL wasCancelled);
}

+ (instancetype)shared {
  static CoverArtDatabaseDownloader* instance = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    instance = [[CoverArtDatabaseDownloader alloc] init];
  });
  return instance;
}

- (instancetype)init {
  self = [super init];
  if (self) {
    NSURLSessionConfiguration* config = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    config.HTTPMaximumConnectionsPerHost = kMaxConcurrentDownloads;
    _session = [NSURLSession sessionWithConfiguration:config];
  }
  return self;
}

// wiitdb-en.txt is "GAMEID = Name", one per line, the same bundled GameTDB title list
// Core::TitleDatabase already parses for name lookups - reusing it here means "download the
// whole database" covers exactly the same games Dolphin itself knows about, not a hand-curated
// or guessed list.
- (NSArray<NSString*>*)parseAllGameIDs {
  NSString* path = CppToFoundationString((File::GetSysDirectory() + "wiitdb-en.txt"));
  NSString* contents = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
  if (contents == nil) {
    return @[];
  }

  NSMutableArray<NSString*>* ids = [NSMutableArray array];
  [contents enumerateLinesUsingBlock:^(NSString* _Nonnull line, BOOL* _Nonnull stop) {
    NSRange equalsRange = [line rangeOfString:@"="];
    if (equalsRange.location == NSNotFound) {
      return;
    }
    NSString* gameID = [[line substringToIndex:equalsRange.location]
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (gameID.length >= 4) {
      [ids addObject:gameID];
    }
  }];
  return ids;
}

- (NSString*)coverCacheDirectory {
  if (_coverCacheDir == nil) {
    _coverCacheDir = CppToFoundationString(File::GetUserPath(D_COVERCACHE_IDX));
  }
  return _coverCacheDir;
}

// The 4th character of every Wii/GC Game ID is Nintendo's own region code - the same convention
// GameTDB's own cover directories are keyed on. This is a simpler, context-free version of what
// SConfig::GetGameTDBImageRegionCode() does for an actually-installed, actually-configured game
// (which also considers the Wii system menu's language for PAL titles); we have no such context
// for a bare ID from the master list, so PAL variants all fall back to GameTDB's general "EN"
// cover rather than guessing a language.
- (NSString*)regionCodeForGameID:(NSString*)gameID {
  switch ([gameID characterAtIndex:3]) {
  case 'E':
    return @"US";
  case 'J':
    return @"JA";
  case 'K':
    return @"KO";
  case 'W':
    return @"ZH";
  default:
    return @"EN";
  }
}

- (NSInteger)countMissingCovers {
  NSArray<NSString*>* allIDs = [self parseAllGameIDs];
  NSString* cacheDir = [self coverCacheDirectory];
  NSFileManager* fm = [NSFileManager defaultManager];

  NSInteger missing = 0;
  for (NSString* gameID in allIDs) {
    NSString* path = [cacheDir stringByAppendingPathComponent:[gameID stringByAppendingString:@".png"]];
    if (![fm fileExistsAtPath:path]) {
      missing++;
    }
  }
  return missing;
}

- (void)startWithProgressHandler:(void (^)(NSInteger, NSInteger))progressHandler
               completionHandler:(void (^)(BOOL))completionHandler {
  if (_isDownloading) {
    return;
  }

  NSArray<NSString*>* allIDs = [self parseAllGameIDs];
  NSString* cacheDir = [self coverCacheDirectory];
  NSFileManager* fm = [NSFileManager defaultManager];
  [fm createDirectoryAtPath:cacheDir withIntermediateDirectories:YES attributes:nil error:nil];

  NSMutableArray<NSString*>* pending = [NSMutableArray array];
  for (NSString* gameID in allIDs) {
    NSString* path = [cacheDir stringByAppendingPathComponent:[gameID stringByAppendingString:@".png"]];
    if (![fm fileExistsAtPath:path]) {
      [pending addObject:gameID];
    }
  }

  _pendingIDs = pending;
  _nextIndex = 0;
  _activeCount = 0;
  _cancelled = NO;
  _isDownloading = YES;
  _totalCount = pending.count;
  _completedCount = 0;
  _progressHandler = [progressHandler copy];
  _completionHandler = [completionHandler copy];

  if (pending.count == 0) {
    [self finishWithCancelled:NO];
    return;
  }

  NSInteger initialBatch = MIN(kMaxConcurrentDownloads, (NSInteger)pending.count);
  for (NSInteger i = 0; i < initialBatch; i++) {
    [self startNextDownload];
  }
}

- (void)startNextDownload {
  if (_cancelled || _nextIndex >= _pendingIDs.count) {
    return;
  }

  NSString* gameID = _pendingIDs[_nextIndex];
  _nextIndex++;
  _activeCount++;

  NSString* region = [self regionCodeForGameID:gameID];
  NSString* urlString =
      [NSString stringWithFormat:@"https://art.gametdb.com/wii/cover/%@/%@.png", region, gameID];
  NSURL* url = [NSURL URLWithString:urlString];
  NSString* destinationPath =
      [[self coverCacheDirectory] stringByAppendingPathComponent:[gameID stringByAppendingString:@".png"]];

  __weak CoverArtDatabaseDownloader* weakSelf = self;
  NSURLSessionDataTask* task = [_session
      dataTaskWithURL:url
    completionHandler:^(NSData* _Nullable data, NSURLResponse* _Nullable response, NSError* _Nullable error) {
      NSHTTPURLResponse* httpResponse = (NSHTTPURLResponse*)response;
      if (data != nil && error == nil && httpResponse.statusCode == 200) {
        [data writeToFile:destinationPath atomically:YES];
      }

      dispatch_async(dispatch_get_main_queue(), ^{
        [weakSelf handleDownloadFinished];
      });
    }];
  [task resume];
}

- (void)handleDownloadFinished {
  _activeCount--;
  _completedCount++;

  if (_progressHandler != nil) {
    _progressHandler(_completedCount, _totalCount);
  }

  if (_cancelled) {
    if (_activeCount == 0) {
      [self finishWithCancelled:YES];
    }
    return;
  }

  if (_nextIndex < _pendingIDs.count) {
    [self startNextDownload];
  } else if (_activeCount == 0) {
    [self finishWithCancelled:NO];
  }
}

- (void)finishWithCancelled:(BOOL)cancelled {
  _isDownloading = NO;
  void (^completion)(BOOL) = _completionHandler;
  _progressHandler = nil;
  _completionHandler = nil;
  _pendingIDs = nil;

  if (completion != nil) {
    completion(cancelled);
  }
}

- (void)cancel {
  _cancelled = YES;
}

@end
