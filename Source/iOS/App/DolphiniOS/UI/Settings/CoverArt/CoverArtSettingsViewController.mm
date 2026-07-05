// Copyright 2026 DolphiniOS Project
// SPDX-License-Identifier: GPL-2.0-or-later

#import "CoverArtSettingsViewController.h"

#import "Core/Config/UISettings.h"

#import "CoverArtDatabaseDownloader.h"

typedef NS_ENUM(NSInteger, CoverArtRow) {
  CoverArtRowAutoDownload,
};

@implementation CoverArtSettingsViewController {
  UISwitch* _autoDownloadSwitch;
  UITableViewCell* _databaseCell;
  BOOL _isEstimating;
}

- (instancetype)init {
  return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
  [super viewDidLoad];

  self.title = @"Cover Art";
  [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"Cell"];

  _autoDownloadSwitch = [[UISwitch alloc] init];
  _autoDownloadSwitch.on = Config::Get(Config::MAIN_USE_GAME_COVERS);
  [_autoDownloadSwitch addTarget:self action:@selector(autoDownloadChanged) forControlEvents:UIControlEventValueChanged];

  [self updateDatabaseCellTitle];
}

- (void)autoDownloadChanged {
  Config::SetBaseOrCurrent(Config::MAIN_USE_GAME_COVERS, (bool)_autoDownloadSwitch.on);
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView*)tableView {
  return 2;
}

- (NSInteger)tableView:(UITableView*)tableView numberOfRowsInSection:(NSInteger)section {
  return 1;
}

- (nullable NSString*)tableView:(UITableView*)tableView titleForFooterInSection:(NSInteger)section {
  if (section == 0) {
    return @"Fetches box art from GameTDB for each game, matched exactly by that game's own "
           @"disc ID - no guessing involved for games you actually own.";
  }
  return @"Downloads cover art for every game GameTDB knows about, not just the ones you own - "
         @"about 10,000 images, roughly a few hundred MB to a couple GB depending on how many "
         @"you already have cached. This can take a while; keep the app open while it runs.";
}

- (UITableViewCell*)tableView:(UITableView*)tableView cellForRowAtIndexPath:(NSIndexPath*)indexPath {
  UITableViewCell* cell = [tableView dequeueReusableCellWithIdentifier:@"Cell" forIndexPath:indexPath];
  cell.accessoryView = nil;
  cell.accessoryType = UITableViewCellAccessoryNone;
  cell.selectionStyle = UITableViewCellSelectionStyleNone;
  cell.textLabel.textColor = [UIColor labelColor];

  if (indexPath.section == 0) {
    cell.textLabel.text = @"Automatically Download Cover Art";
    cell.accessoryView = _autoDownloadSwitch;
  } else {
    _databaseCell = cell;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    [self updateDatabaseCellTitle];
  }

  return cell;
}

- (void)tableView:(UITableView*)tableView didSelectRowAtIndexPath:(NSIndexPath*)indexPath {
  [tableView deselectRowAtIndexPath:indexPath animated:YES];

  if (indexPath.section != 1) {
    return;
  }

  if ([CoverArtDatabaseDownloader shared].isDownloading) {
    [[CoverArtDatabaseDownloader shared] cancel];
    return;
  }

  if (_isEstimating) {
    return;
  }

  [self promptDownloadEntireDatabase];
}

- (void)updateDatabaseCellTitle {
  if (_databaseCell == nil) {
    return;
  }

  CoverArtDatabaseDownloader* downloader = [CoverArtDatabaseDownloader shared];
  if (downloader.isDownloading) {
    _databaseCell.textLabel.text =
        [NSString stringWithFormat:@"Cancel Download (%ld / %ld)", (long)downloader.completedCount,
                                    (long)downloader.totalCount];
    _databaseCell.textLabel.textColor = [UIColor systemRedColor];
  } else if (_isEstimating) {
    _databaseCell.textLabel.text = @"Checking what's missing...";
    _databaseCell.textLabel.textColor = [UIColor secondaryLabelColor];
  } else {
    _databaseCell.textLabel.text = @"Download Entire Database...";
    _databaseCell.textLabel.textColor = [UIColor labelColor];
  }
}

- (void)promptDownloadEntireDatabase {
  _isEstimating = YES;
  [self updateDatabaseCellTitle];

  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    NSInteger missing = [[CoverArtDatabaseDownloader shared] countMissingCovers];

    dispatch_async(dispatch_get_main_queue(), ^{
      self->_isEstimating = NO;
      [self updateDatabaseCellTitle];

      if (missing == 0) {
        UIAlertController* alert =
            [UIAlertController alertControllerWithTitle:@"Already Complete"
                                                 message:@"Every cover GameTDB has is already downloaded."
                                          preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
      }

      UIAlertController* alert = [UIAlertController
          alertControllerWithTitle:@"Download Entire Database?"
                           message:[NSString stringWithFormat:@"This will download about %ld cover images. "
                                    @"You can cancel at any point and keep what's already been downloaded.",
                                    (long)missing]
                    preferredStyle:UIAlertControllerStyleAlert];
      [alert addAction:[UIAlertAction actionWithTitle:@"Download" style:UIAlertActionStyleDefault
                                               handler:^(UIAlertAction*) {
        [self beginDatabaseDownload];
      }]];
      [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
      [self presentViewController:alert animated:YES completion:nil];
    });
  });
}

- (void)beginDatabaseDownload {
  __weak CoverArtSettingsViewController* weakSelf = self;

  [[CoverArtDatabaseDownloader shared]
      startWithProgressHandler:^(NSInteger completed, NSInteger total) {
        [weakSelf updateDatabaseCellTitle];
      }
      completionHandler:^(BOOL wasCancelled) {
        [weakSelf updateDatabaseCellTitle];
      }];

  [self updateDatabaseCellTitle];
}

@end
