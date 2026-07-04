// Copyright 2026 DolphiniOS Project
// SPDX-License-Identifier: GPL-2.0-or-later

#import "NetPlaySetupViewController.h"

#import "GameFileCacheManager.h"
#import "GameFilePtrWrapper.h"
#import "NetPlayLobbyViewController.h"
#import "NetPlayManager.h"
#import "Swift.h"

#import "UICommon/GameFile.h"

// Simple modal list to pick a game to host. Not exposed outside this file - it's only ever
// code-instantiated, never used from a storyboard.
@interface NPGamePickerViewController : UITableViewController
@property (nonatomic, copy) void (^onPick)(GameFilePtrWrapper* _Nullable);
@end

@implementation NPGamePickerViewController {
  NSArray<GameFilePtrWrapper*>* _games;
}

- (void)viewDidLoad {
  [super viewDidLoad];
  self.title = @"Choose a Game";
  self.navigationItem.leftBarButtonItem =
      [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                     target:self
                                                     action:@selector(cancelTapped)];
  [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"Cell"];
  _games = [[GameFileCacheManager sharedManager] getGames];
}

- (void)cancelTapped {
  if (self.onPick) {
    self.onPick(nil);
  }
  [self dismissViewControllerAnimated:YES completion:nil];
}

- (NSInteger)tableView:(UITableView*)tableView numberOfRowsInSection:(NSInteger)section {
  return _games.count;
}

- (UITableViewCell*)tableView:(UITableView*)tableView cellForRowAtIndexPath:(NSIndexPath*)indexPath {
  UITableViewCell* cell = [tableView dequeueReusableCellWithIdentifier:@"Cell" forIndexPath:indexPath];
  GameFilePtrWrapper* wrapper = _games[indexPath.row];
  cell.textLabel.text = CppToFoundationString(wrapper.gameFile->GetInternalName());
  return cell;
}

- (void)tableView:(UITableView*)tableView didSelectRowAtIndexPath:(NSIndexPath*)indexPath {
  GameFilePtrWrapper* wrapper = _games[indexPath.row];
  if (self.onPick) {
    self.onPick(wrapper);
  }
  [self dismissViewControllerAnimated:YES completion:nil];
}

@end

@interface NetPlaySetupViewController () <UITextFieldDelegate>

@end

@implementation NetPlaySetupViewController {
  UISegmentedControl* _modeControl;
  UITextField* _nicknameField;
  UIButton* _chooseGameButton;
  UISwitch* _traversalSwitch;
  UITextField* _addressField;
  UITextField* _portField;
  UIActivityIndicatorView* _spinner;
  UIButton* _actionButton;
  UILabel* _statusLabel;

  GameFilePtrWrapper* _selectedGame;
}

- (void)viewDidLoad {
  [super viewDidLoad];

  self.title = @"NetPlay";
  self.view.backgroundColor = [UIColor systemBackgroundColor];

  _modeControl = [[UISegmentedControl alloc] initWithItems:@[ @"Host", @"Join" ]];
  _modeControl.selectedSegmentIndex = 0;
  _modeControl.translatesAutoresizingMaskIntoConstraints = NO;
  [_modeControl addTarget:self action:@selector(modeChanged) forControlEvents:UIControlEventValueChanged];

  _nicknameField = [self makeTextFieldWithPlaceholder:@"Nickname"];
  _nicknameField.text = [self defaultNickname];

  _chooseGameButton = [UIButton buttonWithType:UIButtonTypeSystem];
  [_chooseGameButton setTitle:@"Choose Game..." forState:UIControlStateNormal];
  _chooseGameButton.translatesAutoresizingMaskIntoConstraints = NO;
  _chooseGameButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
  [_chooseGameButton addTarget:self action:@selector(chooseGameTapped) forControlEvents:UIControlEventTouchUpInside];

  UILabel* traversalLabel = [[UILabel alloc] init];
  traversalLabel.text = @"Use host code (no port forwarding needed)";
  traversalLabel.font = [UIFont systemFontOfSize:14];
  traversalLabel.numberOfLines = 0;
  traversalLabel.translatesAutoresizingMaskIntoConstraints = NO;

  _traversalSwitch = [[UISwitch alloc] init];
  _traversalSwitch.on = YES;
  _traversalSwitch.translatesAutoresizingMaskIntoConstraints = NO;
  [_traversalSwitch addTarget:self action:@selector(traversalChanged) forControlEvents:UIControlEventValueChanged];

  _addressField = [self makeTextFieldWithPlaceholder:@"Host code"];
  _addressField.autocapitalizationType = UITextAutocapitalizationTypeAllCharacters;
  _addressField.autocorrectionType = UITextAutocorrectionTypeNo;

  _portField = [self makeTextFieldWithPlaceholder:@"Port (default 2626)"];
  _portField.keyboardType = UIKeyboardTypeNumberPad;

  _statusLabel = [[UILabel alloc] init];
  _statusLabel.numberOfLines = 0;
  _statusLabel.font = [UIFont systemFontOfSize:14];
  _statusLabel.textColor = [UIColor secondaryLabelColor];
  _statusLabel.translatesAutoresizingMaskIntoConstraints = NO;

  _actionButton = [UIButton buttonWithType:UIButtonTypeSystem];
  _actionButton.translatesAutoresizingMaskIntoConstraints = NO;
  _actionButton.titleLabel.font = [UIFont boldSystemFontOfSize:18];
  [_actionButton addTarget:self action:@selector(actionTapped) forControlEvents:UIControlEventTouchUpInside];

  _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
  _spinner.translatesAutoresizingMaskIntoConstraints = NO;
  _spinner.hidesWhenStopped = YES;

  UIStackView* stack = [[UIStackView alloc] initWithArrangedSubviews:@[
    _modeControl, _nicknameField, _chooseGameButton, traversalLabel, _traversalSwitch,
    _addressField, _portField, _statusLabel, _actionButton, _spinner
  ]];
  stack.axis = UILayoutConstraintAxisVertical;
  stack.spacing = 16;
  stack.translatesAutoresizingMaskIntoConstraints = NO;
  [self.view addSubview:stack];

  [NSLayoutConstraint activateConstraints:@[
    [stack.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:24],
    [stack.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:24],
    [stack.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-24],
  ]];

  [self updateForMode];
  [self updateActionButtonEnabled];
}

- (UITextField*)makeTextFieldWithPlaceholder:(NSString*)placeholder {
  UITextField* field = [[UITextField alloc] init];
  field.placeholder = placeholder;
  field.borderStyle = UITextBorderStyleRoundedRect;
  field.translatesAutoresizingMaskIntoConstraints = NO;
  field.delegate = self;
  [field addTarget:self action:@selector(updateActionButtonEnabled) forControlEvents:UIControlEventEditingChanged];
  [field.heightAnchor constraintEqualToConstant:44].active = YES;
  return field;
}

- (NSString*)defaultNickname {
  NSString* deviceName = [UIDevice currentDevice].name;
  return deviceName.length > 0 ? deviceName : @"Player";
}

- (BOOL)isHostMode {
  return _modeControl.selectedSegmentIndex == 0;
}

- (void)modeChanged {
  [self updateForMode];
  [self updateActionButtonEnabled];
}

- (void)traversalChanged {
  _addressField.placeholder = _traversalSwitch.on ? @"Host code" : @"IP address";
  [self updateActionButtonEnabled];
}

- (void)updateForMode {
  BOOL host = [self isHostMode];
  _chooseGameButton.hidden = !host;
  _addressField.hidden = host;

  [_actionButton setTitle:(host ? @"Host" : @"Join") forState:UIControlStateNormal];
}

- (void)chooseGameTapped {
  NPGamePickerViewController* picker = [[NPGamePickerViewController alloc] init];
  __weak NetPlaySetupViewController* weakSelf = self;
  picker.onPick = ^(GameFilePtrWrapper* _Nullable game) {
    if (game != nil) {
      weakSelf->_selectedGame = game;
      [weakSelf->_chooseGameButton setTitle:CppToFoundationString(game.gameFile->GetInternalName())
                                    forState:UIControlStateNormal];
      [weakSelf updateActionButtonEnabled];
    }
  };
  UINavigationController* nav = [[UINavigationController alloc] initWithRootViewController:picker];
  [self presentViewController:nav animated:YES completion:nil];
}

- (void)updateActionButtonEnabled {
  BOOL host = [self isHostMode];
  BOOL nicknameOk = _nicknameField.text.length > 0;
  BOOL ready;

  if (host) {
    ready = nicknameOk && _selectedGame != nil;
  } else {
    ready = nicknameOk && _addressField.text.length > 0;
  }

  _actionButton.enabled = ready;
}

- (uint16_t)portValue {
  NSInteger value = _portField.text.integerValue;
  if (value <= 0 || value > 65535) {
    return 2626;
  }
  return (uint16_t)value;
}

- (void)actionTapped {
  _actionButton.enabled = NO;
  [_spinner startAnimating];
  _statusLabel.text = @"Connecting...";

  __weak NetPlaySetupViewController* weakSelf = self;
  void (^completion)(BOOL, NSString* _Nullable) = ^(BOOL success, NSString* _Nullable error) {
    dispatch_async(dispatch_get_main_queue(), ^{
      NetPlaySetupViewController* strongSelf = weakSelf;
      if (strongSelf == nil) {
        return;
      }

      [strongSelf->_spinner stopAnimating];

      if (success) {
        NetPlayLobbyViewController* lobby = [[NetPlayLobbyViewController alloc] init];
        [strongSelf.navigationController pushViewController:lobby animated:YES];
      } else {
        strongSelf->_actionButton.enabled = YES;
        strongSelf->_statusLabel.text = error ?: @"Something went wrong.";
      }
    });
  };

  if ([self isHostMode]) {
    [[NetPlayManager shared] hostGameWithFile:_selectedGame
                                          port:[self portValue]
                                  useTraversal:_traversalSwitch.on
                                       useUPnP:!_traversalSwitch.on
                                      nickname:_nicknameField.text
                                    completion:completion];
  } else {
    [[NetPlayManager shared] joinWithAddress:_addressField.text
                                         port:[self portValue]
                                 useTraversal:_traversalSwitch.on
                                     nickname:_nicknameField.text
                                   completion:completion];
  }
}

- (BOOL)textFieldShouldReturn:(UITextField*)textField {
  [textField resignFirstResponder];
  return YES;
}

@end
