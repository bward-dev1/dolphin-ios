// Copyright 2022 DolphiniOS Project
// SPDX-License-Identifier: GPL-2.0-or-later

#import "SoftwareListiOSViewController.h"

#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#import "Common/CommonPaths.h"
#import "Common/FileUtil.h"

#import "Core/CommonTitles.h"
#import "Core/Config/MainSettings.h"
#import "Core/IOS/ES/ES.h"
#import "Core/IOS/IOS.h"

#import "DiscIO/NANDImporter.h"

#import "UICommon/GameFile.h"

#import "EmulationBootParameter.h"
#import "FoundationStringUtil.h"
#import "GameFilePtrWrapper.h"
#import "ImportFileManager.h"
#import "LocalizationUtil.h"
#import "CoverArtPickerViewController.h"
#import "GameLibraryPreferences.h"
#import "NetPlaySetupViewController.h"
#import "RemoteControllerViewController.h"

typedef NS_ENUM(NSInteger, DOLSoftwareListDocumentPickerType) {
  DOLSoftwareListDocumentPickerTypeImportSoftware,
  DOLSoftwareListDocumentPickerTypeImportNAND,
  DOLSoftwareListDocumentPickerTypeOpenExternal,
};

@implementation SoftwareListiOSViewController {
  DOLSoftwareListDocumentPickerType _pickerType;
  NSURL* _openedUrl;
}

- (void)viewWillAppear:(BOOL)animated {
  [super viewWillAppear:animated];
  
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(receiveImportFileFinishedNotification) name:DOLImportFileFinishedNotification object:nil];
}

- (void)viewWillDisappear:(BOOL)animated {
  [super viewWillDisappear:animated];
  
  [[NSNotificationCenter defaultCenter] removeObserver:self name:DOLImportFileFinishedNotification object:nil];
}

- (void)viewDidAppear:(BOOL)animated {
  [super viewDidAppear:animated];
  
  if (_openedUrl != nil) {
    [_openedUrl stopAccessingSecurityScopedResource];
    _openedUrl = nil;
  }
  
  NSArray<UIMenuElement*>* wiiActions;
  
  UIMenuElement* wiiNandElement = [UIMenu menuWithTitle:DOLCoreLocalizedString(@"Manage NAND") image:[UIImage systemImageNamed:@"wrench.and.screwdriver"] identifier:nil options:0 children:@[
    [UIAction actionWithTitle:DOLCoreLocalizedString(@"Import BootMii NAND Backup...") image:[UIImage systemImageNamed:@"square.and.arrow.down"] identifier:nil handler:^(UIAction*) {
      [self openDocumentPickerWithContentTypes:@[
        [UTType typeWithFilenameExtension:@"bin"]
      ] pickerType:DOLSoftwareListDocumentPickerTypeImportNAND];
    }]
  ]];
  
  // Get the system menu TMD
  IOS::HLE::Kernel ios;
  const auto tmd = ios.GetESCore().FindInstalledTMD(Titles::SYSTEM_MENU);
  
  if (tmd.IsValid()) {
    NSString* loadFormat;
    
    if (tmd.IsvWii()) {
      loadFormat = DOLCoreLocalizedStringWithArgs(@"Load vWii System Menu %1", @"@");
    } else {
      loadFormat = DOLCoreLocalizedStringWithArgs(@"Load Wii System Menu %1", @"@");
    }
    
    std::string version = DiscIO::GetSysMenuVersionString(tmd.GetTitleVersion(), tmd.IsvWii());
    
    wiiActions = @[
      [UIAction actionWithTitle:[NSString stringWithFormat:loadFormat, CppToFoundationString(version)] image:[UIImage systemImageNamed:@"power.circle"] identifier:nil handler:^(UIAction*) {
        self->_bootParameter = [[EmulationBootParameter alloc] init];
        self->_bootParameter.bootType = EmulationBootTypeSystemMenu;
        
        [self performSegueWithIdentifier:@"emulation" sender:nil];
      }],
      wiiNandElement,
      [UIAction actionWithTitle:DOLCoreLocalizedString(@"Perform Online System Update") image:[UIImage systemImageNamed:@"icloud.and.arrow.down"] identifier:nil handler:^(UIAction*) {
        [self performSegueForWiiUpdateWithSource:@"" isOnline:true];
      }]
    ];
  } else {
    wiiActions = @[
      wiiNandElement,
      [UIMenu menuWithTitle:DOLCoreLocalizedString(@"Perform Online System Update") image:[UIImage systemImageNamed:@"icloud.and.arrow.down"] identifier:nil options:0 children:@[
        [UIAction actionWithTitle:DOLCoreLocalizedString(@"Europe") image:nil identifier:nil handler:^(UIAction*) {
          [self performSegueForWiiUpdateWithSource:@"EUR" isOnline:true];
        }],
        [UIAction actionWithTitle:DOLCoreLocalizedString(@"Japan") image:nil identifier:nil handler:^(UIAction*) {
          [self performSegueForWiiUpdateWithSource:@"JPN" isOnline:true];
        }],
        [UIAction actionWithTitle:DOLCoreLocalizedString(@"Korea") image:nil identifier:nil handler:^(UIAction*) {
          [self performSegueForWiiUpdateWithSource:@"KOR" isOnline:true];
        }],
        [UIAction actionWithTitle:DOLCoreLocalizedString(@"United States") image:nil identifier:nil handler:^(UIAction*) {
          [self performSegueForWiiUpdateWithSource:@"USA" isOnline:true];
        }]
      ]
    ]];
  }
  
  NSMutableArray<UIMenuElement*>* iplActions = [[NSMutableArray alloc] init];
  
  void(^addIPLAction)(DiscIO::Region, NSString*, std::string) = ^(DiscIO::Region region, NSString* regionName, std::string regionDir) {
    UIAction* iplAction = [UIAction actionWithTitle:DOLCoreLocalizedString(regionName) image:nil identifier:nil handler:^(UIAction*) {
      [self loadGameCubeIPLForRegion:region];
    }];
    
    if (!File::Exists(Config::GetBootROMPath(regionDir))) {
      [iplAction setAttributes:UIMenuElementAttributesDisabled];
    }
    
    [iplActions addObject:iplAction];
  };
  
  addIPLAction(DiscIO::Region::NTSC_J, @"NTSC-J", JAP_DIR);
  addIPLAction(DiscIO::Region::NTSC_U, @"NTSC-U", USA_DIR);
  addIPLAction(DiscIO::Region::PAL, @"PAL", EUR_DIR);
  
  GameLibraryPreferences* libraryPrefs = [GameLibraryPreferences shared];
  GameLibrarySortMode currentSortMode = libraryPrefs.sortMode;

  void (^addSortAction)(NSMutableArray<UIMenuElement*>*, NSString*, GameLibrarySortMode) =
      ^(NSMutableArray<UIMenuElement*>* elements, NSString* title, GameLibrarySortMode mode) {
    UIAction* action = [UIAction actionWithTitle:title image:nil identifier:nil handler:^(UIAction*) {
      libraryPrefs.sortMode = mode;
      [self refreshSortAndFilter];
    }];
    action.state = (currentSortMode == mode) ? UIMenuElementStateOn : UIMenuElementStateOff;
    [elements addObject:action];
  };

  NSMutableArray<UIMenuElement*>* sortActions = [[NSMutableArray alloc] init];
  addSortAction(sortActions, @"Name", GameLibrarySortModeName);
  addSortAction(sortActions, @"Recently Played", GameLibrarySortModeRecentlyPlayed);
  addSortAction(sortActions, @"Favorites First", GameLibrarySortModeFavoritesFirst);

  UIAction* favoritesOnlyAction = [UIAction actionWithTitle:@"Favorites Only" image:[UIImage systemImageNamed:@"star"] identifier:nil handler:^(UIAction*) {
    libraryPrefs.favoritesOnly = !libraryPrefs.favoritesOnly;
    [self refreshSortAndFilter];
  }];
  favoritesOnlyAction.state = libraryPrefs.favoritesOnly ? UIMenuElementStateOn : UIMenuElementStateOff;

  self.navigationItem.leftBarButtonItem.menu = [UIMenu menuWithChildren:@[
    [UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[
      [UIAction actionWithTitle:@"Play Together..." image:[UIImage systemImageNamed:@"person.2.fill"] identifier:nil handler:^(UIAction*) {
        [self playTogetherTapped];
      }],
      [UIAction actionWithTitle:@"Remote Controller Mode..." image:[UIImage systemImageNamed:@"gamecontroller"] identifier:nil handler:^(UIAction*) {
        [self remoteControllerModeTapped];
      }]
    ]],
    [UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[
      [UIMenu menuWithTitle:@"Sort By" image:[UIImage systemImageNamed:@"arrow.up.arrow.down"] identifier:nil options:0 children:sortActions],
      favoritesOnlyAction
    ]],
    [UIAction actionWithTitle:DOLCoreLocalizedString(@"Open") image:[UIImage systemImageNamed:@"externaldrive"] identifier:nil handler:^(UIAction*) {
      [self openDocumentPickerWithSoftwareContentTypesAndPickerType:DOLSoftwareListDocumentPickerTypeOpenExternal];
    }],
    [UIMenu menuWithTitle:DOLCoreLocalizedString(@"GameCube") image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[
      [UIMenu menuWithTitle:@"Load GameCube Main Menu" image:[UIImage systemImageNamed:@"power.circle"] identifier:nil options:0 children:iplActions]
    ]],
    [UIMenu menuWithTitle:DOLCoreLocalizedString(@"Wii") image:nil identifier:nil options:UIMenuOptionsDisplayInline children:wiiActions]
  ]];
}

- (void)playTogetherTapped {
  NetPlaySetupViewController* setup = [[NetPlaySetupViewController alloc] init];
  UINavigationController* nav = [[UINavigationController alloc] initWithRootViewController:setup];
  nav.modalPresentationStyle = UIModalPresentationFullScreen;
  [self presentViewController:nav animated:YES completion:nil];
}

- (void)remoteControllerModeTapped {
  RemoteControllerViewController* remote = [[RemoteControllerViewController alloc] init];
  UINavigationController* nav = [[UINavigationController alloc] initWithRootViewController:remote];
  nav.modalPresentationStyle = UIModalPresentationFullScreen;
  [self presentViewController:nav animated:YES completion:nil];
}

- (void)openDocumentPickerWithSoftwareContentTypesAndPickerType:(DOLSoftwareListDocumentPickerType)pickerType {
  NSArray<UTType*>* types = @[
    [UTType exportedTypeWithIdentifier:@"me.oatmealdome.dolphinios.generic-software"],
    [UTType exportedTypeWithIdentifier:@"me.oatmealdome.dolphinios.gamecube-software"],
    [UTType exportedTypeWithIdentifier:@"me.oatmealdome.dolphinios.wii-software"]
  ];
  
  [self openDocumentPickerWithContentTypes:types pickerType:pickerType];
}

- (void)openDocumentPickerWithContentTypes:(NSArray<UTType*>*)contentTypes pickerType:(DOLSoftwareListDocumentPickerType)pickerType {
  UIDocumentPickerViewController* pickerController = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:contentTypes];
  pickerController.delegate = self;
  pickerController.modalPresentationStyle = UIModalPresentationPageSheet;
  // Importing is the only flow that can sensibly handle more than one file at once -- NAND
  // import and "Open" (launch a file directly) are both inherently single-file operations.
  pickerController.allowsMultipleSelection = pickerType == DOLSoftwareListDocumentPickerTypeImportSoftware;

  _pickerType = pickerType;
  
  [self presentViewController:pickerController animated:true completion:nil];
}

- (IBAction)addButtonPressed:(id)sender {
  [self openDocumentPickerWithSoftwareContentTypesAndPickerType:DOLSoftwareListDocumentPickerTypeImportSoftware];
}

- (void)documentPicker:(UIDocumentPickerViewController*)controller didPickDocumentsAtURLs:(NSArray<NSURL*>*)urls {
  void (^showError)(NSString*) = ^(NSString* error) {
    UIAlertController* errorAlert = [UIAlertController alertControllerWithTitle:DOLCoreLocalizedString(@"Error") message:error preferredStyle:UIAlertControllerStyleAlert];
    
    [errorAlert addAction:[UIAlertAction actionWithTitle:DOLCoreLocalizedString(@"OK") style:UIAlertActionStyleDefault
      handler:nil]];
    
    [self presentViewController:errorAlert animated:true completion:nil];
  };
  
  if (_pickerType == DOLSoftwareListDocumentPickerTypeImportSoftware) {
    [[ImportFileManager shared] importFilesAtUrls:urls];
  } else if (_pickerType == DOLSoftwareListDocumentPickerTypeOpenExternal) {
    NSURL* url = urls[0];
    
    if (![url startAccessingSecurityScopedResource]) {
      showError(@"Failed to start accessing security scoped resource.");
      return;
    }
    
    _openedUrl = url;
    
    NSString* sourcePath = [_openedUrl path];
    
    GameFilePtrWrapper* gameFileWrapper = [[GameFilePtrWrapper alloc] init];
    gameFileWrapper.gameFile = std::make_shared<UICommon::GameFile>(FoundationToCppString(sourcePath));
    
    if (!gameFileWrapper.gameFile->IsValid()) {
      [_openedUrl stopAccessingSecurityScopedResource];
      
      showError(@"File is invalid.");
      
      return;
    }
    
    [self loadGameFile:gameFileWrapper];
  } else if (_pickerType == DOLSoftwareListDocumentPickerTypeImportNAND) {
    NSURL* url = urls[0];
    
    if (![url startAccessingSecurityScopedResource]) {
      showError(@"Failed to start accessing security scoped resource.");
      return;
    }
    
    UIAlertController* waitAlert = [UIAlertController alertControllerWithTitle:DOLCoreLocalizedString(@"Importing NAND backup") message:nil preferredStyle:UIAlertControllerStyleAlert];
    
    [self presentViewController:waitAlert animated:true completion:^{
      dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        DiscIO::NANDImporter().ImportNANDBin(FoundationToCppString([url path]), [] {
          // Called to update the GUI. We don't need to do this.
        }, [] {
          // Called if we need to find NAND keys. Android doesn't implement this, so let's not do it either.
          PanicAlertFmtT("The decryption keys need to be appended to the NAND backup file.");
          return "";
        });
        
        [url stopAccessingSecurityScopedResource];
        
        dispatch_async(dispatch_get_main_queue(), ^{
          [waitAlert dismissViewControllerAnimated:true completion:nil];
        });
      });
    }];
  }
}

- (UIContextMenuConfiguration*)collectionView:(UICollectionView*)collectionView contextMenuConfigurationForItemAtIndexPath:(NSIndexPath*)indexPath point:(CGPoint)point {
  return [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:nil actionProvider:^(NSArray<UIMenuElement*>*) {
    GameFilePtrWrapper* gameFileWrapper = [self->_gameFiles objectAtIndex:indexPath.row];
    
    NSMutableArray<UIAction*>* actions = [[NSMutableArray alloc] init];
    
    [actions addObject:[UIAction actionWithTitle:DOLCoreLocalizedString(@"Properties") image:[UIImage systemImageNamed:@"square.and.pencil"] identifier:nil handler:^(UIAction*) {
      self->_selectedFile = gameFileWrapper;

      [self performSegueWithIdentifier:@"properties" sender:nil];
    }]];

    [actions addObject:[UIAction actionWithTitle:@"Change Cover..." image:[UIImage systemImageNamed:@"photo"] identifier:nil handler:^(UIAction*) {
      CoverArtPickerViewController* picker = [[CoverArtPickerViewController alloc] initWithGameFileWrapper:gameFileWrapper];
      UINavigationController* nav = [[UINavigationController alloc] initWithRootViewController:picker];
      [self presentViewController:nav animated:YES completion:nil];
    }]];

    NSString* gameID = CppToFoundationString(gameFileWrapper.gameFile->GetGameID());
    BOOL isFavorite = [[GameLibraryPreferences shared] isFavoriteGameID:gameID];
    NSString* favoriteTitle = isFavorite ? @"Remove from Favorites" : @"Add to Favorites";
    NSString* favoriteImage = isFavorite ? @"star.slash" : @"star";
    [actions addObject:[UIAction actionWithTitle:favoriteTitle image:[UIImage systemImageNamed:favoriteImage] identifier:nil handler:^(UIAction*) {
      [[GameLibraryPreferences shared] setFavorite:!isFavorite forGameID:gameID];
      [self refreshSortAndFilter];
    }]];
    
    UIAction* deleteAction = [UIAction actionWithTitle:DOLCoreLocalizedString(@"Delete") image:[UIImage systemImageNamed:@"trash"] identifier:nil handler:^(UIAction*) {
      UIAlertController* confirmAlert = [UIAlertController alertControllerWithTitle:DOLCoreLocalizedString(@"Confirm") message:DOLCoreLocalizedString(@"Are you sure you want to delete this file?") preferredStyle:UIAlertControllerStyleAlert];
        
      [confirmAlert addAction:[UIAlertAction actionWithTitle:DOLCoreLocalizedString(@"No") style:UIAlertActionStyleDefault handler:nil]];
      
      [confirmAlert addAction:[UIAlertAction actionWithTitle:DOLCoreLocalizedString(@"Yes") style:UIAlertActionStyleDestructive handler:^(UIAlertAction*) {
        if (File::Delete(gameFileWrapper.gameFile->GetFilePath())) {
          [self reloadGameFiles];
        }
      }]];
      
      [self presentViewController:confirmAlert animated:true completion:nil];
    }];
    
    [deleteAction setAttributes:UIMenuElementAttributesDestructive];
    
    [actions addObject:deleteAction];
    
    NSString* gameName = CppToFoundationString(gameFileWrapper.gameFile->GetName(UICommon::GameFile::Variant::LongAndPossiblyCustom));
    
    return [UIMenu menuWithTitle:gameName children:[actions copy]];
  }];
}

- (void)receiveImportFileFinishedNotification {
  [self reloadGameFiles];
}

@end
