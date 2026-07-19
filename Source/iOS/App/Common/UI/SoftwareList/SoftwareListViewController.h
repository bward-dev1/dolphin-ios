// Copyright 2022 DolphiniOS Project
// SPDX-License-Identifier: GPL-2.0-or-later

#import <UIKit/UIKit.h>

namespace DiscIO {
enum class Region;
}

@class EmulationBootParameter;
@class GameFilePtrWrapper;

NS_ASSUME_NONNULL_BEGIN

@interface SoftwareListViewController : UICollectionViewController<UICollectionViewDelegateFlowLayout, UISearchResultsUpdating> {
  // The full, unsorted/unfiltered library, refreshed on each rescan.
  NSArray<GameFilePtrWrapper*>* _allGameFiles;
  // What's actually shown - _allGameFiles after the current search text, sort mode, and
  // favorites-only filter are applied. Every existing index-based lookup
  // (cellForItemAtIndexPath, context menu, etc) reads this, unchanged from before
  // sorting/filtering existed.
  NSArray<GameFilePtrWrapper*>* _gameFiles;
  GameFilePtrWrapper* _selectedFile;
  EmulationBootParameter* _bootParameter;
  // Transient, not persisted like GameLibraryPreferences' sort/favorites state - a fresh launch
  // (or leaving and re-entering the library) should always start with an empty search.
  NSString* _searchText;
}

- (void)reloadGameFiles;
- (void)loadGameFile:(GameFilePtrWrapper*)gameFileWrapper;
- (void)loadGameCubeIPLForRegion:(DiscIO::Region)region;

// Re-derives _gameFiles from _allGameFiles using the current GameLibraryPreferences sort mode
// and favorites-only filter, then reloads the collection view. Call after changing either.
- (void)refreshSortAndFilter;

- (void)performSegueForWiiUpdateWithSource:(NSString*)source isOnline:(bool)online;

@end

NS_ASSUME_NONNULL_END
