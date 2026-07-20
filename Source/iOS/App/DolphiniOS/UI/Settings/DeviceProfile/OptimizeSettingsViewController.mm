// Copyright 2026 DolphiniOS Project
// SPDX-License-Identifier: GPL-2.0-or-later

#import "OptimizeSettingsViewController.h"

#import "DeviceProfile.h"

typedef NS_ENUM(NSInteger, OptimizeRow) {
  OptimizeRowDevice,
  OptimizeRowChip,
  OptimizeRowRAM,
  OptimizeRowCores,
  OptimizeRowJIT,
  OptimizeRowTier,
  OptimizeRowCount,
};

@implementation OptimizeSettingsViewController {
  UIButton* _applyButton;
}

- (instancetype)init {
  return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewWillAppear:(BOOL)animated {
  [super viewWillAppear:animated];

  // Re-check JIT/etc every time this screen appears (not just once at init) so the preview
  // below stays accurate if e.g. JIT status changed since the user last looked at this screen.
  [[DeviceProfile shared] refresh];
  [self.tableView reloadData];
}

- (void)viewDidLoad {
  [super viewDidLoad];

  self.title = @"Optimize My Settings";

  [[DeviceProfile shared] refresh];

  UIView* footer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 0, 100)];

  _applyButton = [UIButton buttonWithType:UIButtonTypeSystem];
  [_applyButton setTitle:@"Apply Optimized Settings" forState:UIControlStateNormal];
  _applyButton.titleLabel.font = [UIFont boldSystemFontOfSize:18];
  _applyButton.translatesAutoresizingMaskIntoConstraints = NO;
  [_applyButton addTarget:self action:@selector(applyTapped) forControlEvents:UIControlEventTouchUpInside];
  [footer addSubview:_applyButton];

  [NSLayoutConstraint activateConstraints:@[
    [_applyButton.centerXAnchor constraintEqualToAnchor:footer.centerXAnchor],
    [_applyButton.topAnchor constraintEqualToAnchor:footer.topAnchor constant:24],
  ]];

  self.tableView.tableFooterView = footer;
}

- (void)applyTapped {
  [[DeviceProfile shared] applyOptimizedSettings];

  UIAlertController* alert =
      [UIAlertController alertControllerWithTitle:@"Settings Applied"
                                           message:[NSString stringWithFormat:@"Applied the %@ tier profile based on "
                                                    @"what was detected on this device.",
                                                    [DeviceProfile shared].tierDisplayName]
                                    preferredStyle:UIAlertControllerStyleAlert];
  [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
  [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - UITableViewDataSource

typedef NS_ENUM(NSInteger, OptimizeSection) {
  OptimizeSectionDetected,
  OptimizeSectionPreview,
  OptimizeSectionCount,
};

- (NSInteger)numberOfSectionsInTableView:(UITableView*)tableView {
  return OptimizeSectionCount;
}

- (NSInteger)tableView:(UITableView*)tableView numberOfRowsInSection:(NSInteger)section {
  if (section == OptimizeSectionPreview) {
    return [DeviceProfile shared].previewSettingsDescriptions.count;
  }

  return OptimizeRowCount;
}

- (nullable NSString*)tableView:(UITableView*)tableView titleForHeaderInSection:(NSInteger)section {
  return section == OptimizeSectionPreview ? @"Will Apply" : @"Detected Automatically";
}

- (nullable NSString*)tableView:(UITableView*)tableView titleForFooterInSection:(NSInteger)section {
  if (section != OptimizeSectionPreview) {
    return nil;
  }

  return [DeviceProfile shared].tierSummary;
}

- (UITableViewCell*)tableView:(UITableView*)tableView cellForRowAtIndexPath:(NSIndexPath*)indexPath {
  DeviceProfile* profile = [DeviceProfile shared];

  if (indexPath.section == OptimizeSectionPreview) {
    UITableViewCell* cell = [tableView dequeueReusableCellWithIdentifier:@"PreviewCell"];
    if (cell == nil) {
      cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"PreviewCell"];
    }
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.textLabel.text = profile.previewSettingsDescriptions[indexPath.row];
    return cell;
  }

  UITableViewCell* cell = [tableView dequeueReusableCellWithIdentifier:@"Cell"];
  if (cell == nil) {
    cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"Cell"];
  }
  cell.selectionStyle = UITableViewCellSelectionStyleNone;

  switch ((OptimizeRow)indexPath.row) {
  case OptimizeRowDevice:
    cell.textLabel.text = @"Device";
    cell.detailTextLabel.text = profile.deviceIdentifier;
    break;
  case OptimizeRowChip:
    cell.textLabel.text = @"Chip";
    cell.detailTextLabel.text = profile.chipName;
    break;
  case OptimizeRowRAM:
    cell.textLabel.text = @"Memory";
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%ld MB", (long)profile.physicalMemoryMB];
    break;
  case OptimizeRowCores:
    cell.textLabel.text = @"CPU Cores";
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%ld", (long)profile.processorCount];
    break;
  case OptimizeRowJIT:
    cell.textLabel.text = @"JIT";
    cell.detailTextLabel.text = profile.jitAvailable ? @"Available" : @"Not Available";
    break;
  case OptimizeRowTier:
  case OptimizeRowCount:
    cell.textLabel.text = @"Recommended Tier";
    cell.detailTextLabel.text = profile.tierDisplayName;
    break;
  }

  return cell;
}

@end
