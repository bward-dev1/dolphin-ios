// Copyright 2026 DolphiniOS Project
// SPDX-License-Identifier: GPL-2.0-or-later

#import "ControllersSkinsViewController.h"

#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#import "Swift.h"

static NSString* const kCellReuseIdentifier = @"ControllersSkinsCell";

@interface ControllersSkinsViewController () <UIDocumentPickerDelegate>

@end

@implementation ControllersSkinsViewController {
  NSArray<NSString*>* _skinNames;
}

- (void)viewDidLoad {
  [super viewDidLoad];

  self.title = @"Controller Skins";

  [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:kCellReuseIdentifier];

  UIAction* importAction = [UIAction actionWithTitle:@"Import Skin Folder..."
                                                image:[UIImage systemImageNamed:@"square.and.arrow.down"]
                                           identifier:nil
                                              handler:^(UIAction*) {
    [self presentImportPicker];
  }];

  UIAction* templateAction = [UIAction actionWithTitle:@"Create New Skin From Current Artwork..."
                                                  image:[UIImage systemImageNamed:@"plus.square.on.square"]
                                             identifier:nil
                                                handler:^(UIAction*) {
    [self presentCreateTemplatePrompt];
  }];

  UIMenu* menu = [UIMenu menuWithTitle:@"" image:nil identifier:nil options:0
                               children:@[ importAction, templateAction ]];

  self.navigationItem.rightBarButtonItem =
      [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"plus"]
                                        menu:menu];
}

- (void)viewWillAppear:(BOOL)animated {
  [super viewWillAppear:animated];

  [self reloadSkinList];
}

- (void)reloadSkinList {
  [[TCSkinManager shared] ensureSkinsFolderExists];
  _skinNames = [[TCSkinManager shared] availableSkinNames];
  [self.tableView reloadData];
}

#pragma mark - Import

- (void)presentImportPicker {
  NSArray<UTType*>* types = @[ [UTType typeWithIdentifier:@"public.folder"] ];
  UIDocumentPickerViewController* pickerController =
      [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:types];
  pickerController.delegate = self;
  pickerController.modalPresentationStyle = UIModalPresentationPageSheet;
  pickerController.allowsMultipleSelection = false;

  [self presentViewController:pickerController animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController*)controller
    didPickDocumentsAtURLs:(NSArray<NSURL*>*)urls {
  NSURL* url = urls.firstObject;
  if (url == nil) {
    return;
  }

  BOOL didStartAccessing = [url startAccessingSecurityScopedResource];

  NSString* suggestedName = url.lastPathComponent;
  NSString* finalName = [[TCSkinManager shared] importSkinFromFolder:url.path suggestedName:suggestedName];

  if (didStartAccessing) {
    [url stopAccessingSecurityScopedResource];
  }

  if (finalName == nil) {
    UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"Import Failed"
        message:@"Couldn't copy that folder. Make sure it contains PNG images named after "
                @"Dolphin's button assets (e.g. wiimote_a.png)."
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
    return;
  }

  [[TCSkinManager shared] setActiveSkinName:finalName];
  [self reloadSkinList];
}

#pragma mark - Create template

- (void)presentCreateTemplatePrompt {
  UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"New Skin"
      message:@"This creates a folder pre-filled with every default button image, correctly "
              @"named. Edit any of those PNGs (via the Files app) to reskin just that button - "
              @"everything you don't touch keeps the default look."
      preferredStyle:UIAlertControllerStyleAlert];

  [alert addTextFieldWithConfigurationHandler:^(UITextField* textField) {
    textField.placeholder = @"Skin name";
  }];

  __weak ControllersSkinsViewController* weakSelf = self;

  [alert addAction:[UIAlertAction actionWithTitle:@"Create" style:UIAlertActionStyleDefault
                                           handler:^(UIAlertAction*) {
    NSString* name = alert.textFields.firstObject.text;
    if (name.length == 0) {
      name = @"My Skin";
    }

    NSString* finalName = [[TCSkinManager shared] createSkinTemplateWithSuggestedName:name];
    if (finalName == nil) {
      return;
    }

    NSString* fullPath = [[[TCSkinManager shared] skinsFolder] stringByAppendingPathComponent:finalName];

    UIAlertController* doneAlert = [UIAlertController alertControllerWithTitle:@"Skin Created"
        message:[NSString stringWithFormat:@"Find it in the Files app under %@. It's now "
                 @"selected as your active skin.", fullPath]
        preferredStyle:UIAlertControllerStyleAlert];
    [doneAlert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [weakSelf presentViewController:doneAlert animated:YES completion:nil];

    [[TCSkinManager shared] setActiveSkinName:finalName];
    [weakSelf reloadSkinList];
  }]];
  [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

  [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView*)tableView {
  return 1;
}

- (NSInteger)tableView:(UITableView*)tableView numberOfRowsInSection:(NSInteger)section {
  return 1 + _skinNames.count;
}

- (nullable NSString*)tableView:(UITableView*)tableView titleForFooterInSection:(NSInteger)section {
  return @"Skins live in the Files app under DolphiniOS/Skins. Any PNG a skin doesn't "
         @"provide falls back to the default look, so partial skins work fine.";
}

- (UITableViewCell*)tableView:(UITableView*)tableView cellForRowAtIndexPath:(NSIndexPath*)indexPath {
  UITableViewCell* cell = [tableView dequeueReusableCellWithIdentifier:kCellReuseIdentifier
                                                           forIndexPath:indexPath];

  NSString* activeSkin = [TCSkinManager shared].activeSkinName;
  NSString* rowSkinName = nil;  // nil means "Default" row

  if (indexPath.row == 0) {
    cell.textLabel.text = @"Default";
    cell.accessoryType = (activeSkin == nil) ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
  } else {
    rowSkinName = _skinNames[indexPath.row - 1];
    cell.textLabel.text = rowSkinName;
    cell.accessoryType = [rowSkinName isEqualToString:activeSkin] ? UITableViewCellAccessoryCheckmark
                                                                   : UITableViewCellAccessoryNone;
  }

  cell.imageView.image = [[TCSkinManager shared] previewImageForSkinNamed:rowSkinName];
  cell.imageView.contentMode = UIViewContentModeScaleAspectFit;
  cell.imageView.layer.cornerRadius = 6;
  cell.imageView.layer.masksToBounds = YES;
  cell.imageView.frame = CGRectMake(0, 0, 36, 36);

  return cell;
}

- (BOOL)tableView:(UITableView*)tableView canEditRowAtIndexPath:(NSIndexPath*)indexPath {
  return indexPath.row != 0;
}

- (void)tableView:(UITableView*)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle
    forRowAtIndexPath:(NSIndexPath*)indexPath {
  if (editingStyle != UITableViewCellEditingStyleDelete || indexPath.row == 0) {
    return;
  }

  NSString* name = _skinNames[indexPath.row - 1];
  [[TCSkinManager shared] deleteSkinNamed:name];
  [self reloadSkinList];
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView*)tableView didSelectRowAtIndexPath:(NSIndexPath*)indexPath {
  if (indexPath.row == 0) {
    [TCSkinManager shared].activeSkinName = nil;
  } else {
    [TCSkinManager shared].activeSkinName = _skinNames[indexPath.row - 1];
  }

  [tableView deselectRowAtIndexPath:indexPath animated:YES];
  [self.tableView reloadData];
}

@end
