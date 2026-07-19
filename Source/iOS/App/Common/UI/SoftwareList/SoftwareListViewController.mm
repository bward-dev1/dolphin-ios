// Copyright 2022 DolphiniOS Project
// SPDX-License-Identifier: GPL-2.0-or-later

#import "SoftwareListViewController.h"

#import "EmulationBootParameter.h"
#import "EmulationViewController.h"
#import "FoundationStringUtil.h"
#import "GameFileCacheManager.h"
#import "GameFilePtrWrapper.h"
#import "GameLibraryPreferences.h"
#import "LocalizationUtil.h"
#import "SoftwarePropertiesViewController.h"
#import "Swift.h"
#import "WiiSystemUpdateViewController.h"

#import "UICommon/GameFile.h"

@interface SoftwareListViewController ()

@end

@implementation SoftwareListViewController {
  NSString* _wiiUpdateSource;
  bool _wiiUpdateIsOnline;
}

- (void)viewDidLoad {
  [super viewDidLoad];

  self->_allGameFiles = [[GameFileCacheManager sharedManager] getGames];
  [self refreshSortAndFilter];

  UISearchController* searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
  searchController.searchResultsUpdater = self;
  searchController.obscuresBackgroundDuringPresentation = false;
  searchController.searchBar.placeholder = DOLCoreLocalizedString(@"Search Games");

  self.navigationItem.searchController = searchController;
  self.navigationItem.hidesSearchBarWhenScrolling = true;
  self.definesPresentationContext = true;
}

- (void)updateSearchResultsForSearchController:(UISearchController*)searchController {
  self->_searchText = searchController.searchBar.text;

  [self refreshSortAndFilter];
}

- (void)viewDidAppear:(BOOL)animated {
  [super viewDidAppear:animated];

  [self reloadGameFiles];
}

- (void)reloadGameFiles {
  [[GameFileCacheManager sharedManager] rescanAndFetchMetadataWithCompletionHandler:^{
    dispatch_async(dispatch_get_main_queue(), ^{
      self->_allGameFiles = [[GameFileCacheManager sharedManager] getGames];
      [self refreshSortAndFilter];
    });
  }];
}

- (void)refreshSortAndFilter {
  GameLibraryPreferences* prefs = [GameLibraryPreferences shared];
  NSArray<GameFilePtrWrapper*>* source = self->_allGameFiles ?: @[];

  if (self->_searchText.length > 0) {
    NSMutableArray<GameFilePtrWrapper*>* filtered = [NSMutableArray array];
    for (GameFilePtrWrapper* wrapper in source) {
      NSString* name = CppToFoundationString(wrapper.gameFile->GetName(UICommon::GameFile::Variant::LongAndPossiblyCustom));
      if ([name rangeOfString:self->_searchText options:NSCaseInsensitiveSearch].location != NSNotFound) {
        [filtered addObject:wrapper];
      }
    }
    source = filtered;
  }

  if (prefs.favoritesOnly) {
    NSMutableArray<GameFilePtrWrapper*>* filtered = [NSMutableArray array];
    for (GameFilePtrWrapper* wrapper in source) {
      if ([prefs isFavoriteGameID:CppToFoundationString(wrapper.gameFile->GetGameID())]) {
        [filtered addObject:wrapper];
      }
    }
    source = filtered;
  }

  NSArray<GameFilePtrWrapper*>* sorted;
  switch (prefs.sortMode) {
  case GameLibrarySortModeRecentlyPlayed: {
    sorted = [source sortedArrayUsingComparator:^NSComparisonResult(GameFilePtrWrapper* a, GameFilePtrWrapper* b) {
      NSTimeInterval timeA = [prefs lastPlayedTimeForGameID:CppToFoundationString(a.gameFile->GetGameID())];
      NSTimeInterval timeB = [prefs lastPlayedTimeForGameID:CppToFoundationString(b.gameFile->GetGameID())];
      if (timeA == timeB) {
        return NSOrderedSame;
      }
      return timeA > timeB ? NSOrderedAscending : NSOrderedDescending;
    }];
    break;
  }
  case GameLibrarySortModeFavoritesFirst: {
    sorted = [source sortedArrayUsingComparator:^NSComparisonResult(GameFilePtrWrapper* a, GameFilePtrWrapper* b) {
      BOOL favA = [prefs isFavoriteGameID:CppToFoundationString(a.gameFile->GetGameID())];
      BOOL favB = [prefs isFavoriteGameID:CppToFoundationString(b.gameFile->GetGameID())];
      if (favA == favB) {
        return NSOrderedSame;
      }
      return favA ? NSOrderedAscending : NSOrderedDescending;
    }];
    break;
  }
  case GameLibrarySortModeName:
  default: {
    sorted = [source sortedArrayUsingComparator:^NSComparisonResult(GameFilePtrWrapper* a, GameFilePtrWrapper* b) {
      NSString* nameA = CppToFoundationString(a.gameFile->GetName(UICommon::GameFile::Variant::LongAndPossiblyCustom));
      NSString* nameB = CppToFoundationString(b.gameFile->GetName(UICommon::GameFile::Variant::LongAndPossiblyCustom));
      return [nameA localizedCaseInsensitiveCompare:nameB];
    }];
    break;
  }
  }

  self->_gameFiles = sorted;
  [self.collectionView reloadData];
}

- (void)loadGameFile:(GameFilePtrWrapper*)gameFileWrapper {
  std::shared_ptr<const UICommon::GameFile> game = gameFileWrapper.gameFile;
  
  std::shared_ptr<const UICommon::GameFile> second_game = nullptr;
  std::shared_ptr<const UICommon::GameFile> match_without_revision = nullptr;
  
  if (DiscIO::IsDisc(game->GetPlatform())) {
    for (GameFilePtrWrapper* otherWrapper in self->_allGameFiles) {
      std::shared_ptr<const UICommon::GameFile> other_game = otherWrapper.gameFile;
      
      if (game->GetGameID() == other_game->GetGameID() &&
          game->GetDiscNumber() != other_game->GetDiscNumber()) {
        if (game->GetRevision() == other_game->GetRevision()) {
          second_game = other_game;
          break;
        } else {
          match_without_revision = other_game;
        }
      }
    }
  }
  
  if (second_game == nullptr) {
    second_game = match_without_revision;
  }
  
  _bootParameter = [[EmulationBootParameter alloc] init];
  _bootParameter.bootType = EmulationBootTypeFile;
  _bootParameter.path = CppToFoundationString(game->GetFilePath());
  _bootParameter.secondPath = second_game != nullptr ? CppToFoundationString(second_game->GetFilePath()) : nil;
  _bootParameter.isNKit = gameFileWrapper.gameFile->IsNKit();

  [[GameLibraryPreferences shared] recordPlayedGameID:CppToFoundationString(game->GetGameID())];

  [self performSegueWithIdentifier:@"emulation" sender:nil];
}

- (void)loadGameCubeIPLForRegion:(DiscIO::Region)region {
  _bootParameter = [[EmulationBootParameter alloc] init];
  _bootParameter.bootType = EmulationBootTypeGCIPL;
  _bootParameter.iplRegion = region;
  
  [self performSegueWithIdentifier:@"emulation" sender:nil];
}

#pragma mark <UICollectionViewDataSource>

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView*)collectionView {
  return 1;
}

- (NSInteger)collectionView:(UICollectionView*)collectionView numberOfItemsInSection:(NSInteger)section {
  return self->_gameFiles.count;
}

- (UICollectionViewCell*)collectionView:(UICollectionView*)collectionView cellForItemAtIndexPath:(NSIndexPath*)indexPath {
  SoftwareListCell* cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"softwareCell" forIndexPath:indexPath];
  GameFilePtrWrapper* gameFileWrapper = [self->_gameFiles objectAtIndex:indexPath.item];
  
  NSString* gameName = CppToFoundationString(gameFileWrapper.gameFile->GetName(UICommon::GameFile::Variant::LongAndPossiblyCustom));
  
  const UICommon::GameCover& cover = gameFileWrapper.gameFile->GetCoverImage();
  
  UIImage* image;
  if (cover.buffer.empty()) {
    image = [UIImage imageNamed:@"NoCover"];
  } else {
    NSData* data = [NSData dataWithBytes:cover.buffer.data() length:cover.buffer.size()];
    image = [UIImage imageWithData:data];
  }
  
  cell.imageView.image = image;
  cell.nameLabel.text = gameName;
  
  return cell;
}

- (void)collectionView:(UICollectionView*)collectionView didSelectItemAtIndexPath:(NSIndexPath*)indexPath {
  GameFilePtrWrapper* gameFileWrapper = [self->_gameFiles objectAtIndex:indexPath.item];
  
  [self loadGameFile:gameFileWrapper];
}

#pragma mark <UICollectionViewDelegateFlowLayout>

- (CGSize)collectionView:(UICollectionView*)collectionView layout:(UICollectionViewLayout*)collectionViewLayout sizeForItemAtIndexPath:(NSIndexPath*)indexPath {
  const CGFloat cellsPerRow = 3.f;
  const CGFloat cellSpacing = 4.f;
  const CGFloat cellHeight = 218.f;
  
  CGFloat totalSpacing = ((cellsPerRow - 1) * cellSpacing);
  return CGSizeMake((collectionView.bounds.size.width - totalSpacing) / cellsPerRow, cellHeight);
}

#pragma mark Segue

- (void)performSegueForWiiUpdateWithSource:(NSString*)source isOnline:(bool)online {
  _wiiUpdateSource = source;
  _wiiUpdateIsOnline = online;
  
  [self performSegueWithIdentifier:@"wiiUpdate" sender:nil];
}

- (void)prepareForSegue:(UIStoryboardSegue*)segue sender:(id)sender
{
  if ([segue.identifier isEqualToString:@"emulation"]) {
    UINavigationController* navigationController = segue.destinationViewController;
    EmulationViewController* viewController = navigationController.viewControllers[0];
    
    viewController.bootParameter = _bootParameter;
  } else if ([segue.identifier isEqualToString:@"wiiUpdate"]) {
    WiiSystemUpdateViewController* updateController = segue.destinationViewController;
    
    updateController.updateSource = _wiiUpdateSource;
    updateController.isOnlineUpdate = _wiiUpdateIsOnline;
  } else if ([segue.identifier isEqualToString:@"properties"]) {
    UINavigationController* navigationController = segue.destinationViewController;
    SoftwarePropertiesViewController* propertiesController = navigationController.viewControllers[0];
    
    propertiesController.gameFileWrapper = _selectedFile;
  }
}

@end
