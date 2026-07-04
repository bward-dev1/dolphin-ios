// Copyright 2026 DolphiniOS Project
// SPDX-License-Identifier: GPL-2.0-or-later

#import "NetPlayLobbyViewController.h"

#import "EmulationBootParameter.h"
#import "EmulationViewController.h"
#import "NetPlayManager.h"

@interface NetPlayLobbyViewController () <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate>

@end

@implementation NetPlayLobbyViewController {
  UILabel* _statusLabel;
  UILabel* _hostCodeLabel;
  UITableView* _playersTable;
  UITextView* _chatView;
  UITextField* _chatInputField;
  UIButton* _startButton;
}

- (void)viewDidLoad {
  [super viewDidLoad];

  self.title = @"NetPlay Lobby";
  self.view.backgroundColor = [UIColor systemBackgroundColor];

  self.navigationItem.hidesBackButton = YES;
  self.navigationItem.leftBarButtonItem =
      [[UIBarButtonItem alloc] initWithTitle:@"Leave"
                                        style:UIBarButtonItemStylePlain
                                       target:self
                                       action:@selector(leaveTapped)];

  _hostCodeLabel = [[UILabel alloc] init];
  _hostCodeLabel.font = [UIFont monospacedSystemFontOfSize:28 weight:UIFontWeightBold];
  _hostCodeLabel.textAlignment = NSTextAlignmentCenter;
  _hostCodeLabel.translatesAutoresizingMaskIntoConstraints = NO;

  _statusLabel = [[UILabel alloc] init];
  _statusLabel.font = [UIFont systemFontOfSize:14];
  _statusLabel.textColor = [UIColor secondaryLabelColor];
  _statusLabel.textAlignment = NSTextAlignmentCenter;
  _statusLabel.numberOfLines = 0;
  _statusLabel.translatesAutoresizingMaskIntoConstraints = NO;

  _playersTable = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
  _playersTable.dataSource = self;
  _playersTable.delegate = self;
  _playersTable.translatesAutoresizingMaskIntoConstraints = NO;

  _chatView = [[UITextView alloc] init];
  _chatView.editable = NO;
  _chatView.font = [UIFont systemFontOfSize:14];
  _chatView.translatesAutoresizingMaskIntoConstraints = NO;
  _chatView.layer.borderColor = [UIColor separatorColor].CGColor;
  _chatView.layer.borderWidth = 1;
  _chatView.layer.cornerRadius = 8;

  _chatInputField = [[UITextField alloc] init];
  _chatInputField.placeholder = @"Message";
  _chatInputField.borderStyle = UITextBorderStyleRoundedRect;
  _chatInputField.delegate = self;
  _chatInputField.translatesAutoresizingMaskIntoConstraints = NO;

  UIButton* sendButton = [UIButton buttonWithType:UIButtonTypeSystem];
  [sendButton setTitle:@"Send" forState:UIControlStateNormal];
  [sendButton addTarget:self action:@selector(sendTapped) forControlEvents:UIControlEventTouchUpInside];
  sendButton.translatesAutoresizingMaskIntoConstraints = NO;

  UIStackView* chatInputRow = [[UIStackView alloc] initWithArrangedSubviews:@[ _chatInputField, sendButton ]];
  chatInputRow.axis = UILayoutConstraintAxisHorizontal;
  chatInputRow.spacing = 8;
  chatInputRow.translatesAutoresizingMaskIntoConstraints = NO;

  _startButton = [UIButton buttonWithType:UIButtonTypeSystem];
  [_startButton setTitle:@"Start Game" forState:UIControlStateNormal];
  _startButton.titleLabel.font = [UIFont boldSystemFontOfSize:18];
  [_startButton addTarget:self action:@selector(startTapped) forControlEvents:UIControlEventTouchUpInside];
  _startButton.translatesAutoresizingMaskIntoConstraints = NO;
  _startButton.hidden = ![NetPlayManager shared].isHost;

  UIStackView* stack = [[UIStackView alloc] initWithArrangedSubviews:@[
    _hostCodeLabel, _statusLabel, _playersTable, _chatView, chatInputRow, _startButton
  ]];
  stack.axis = UILayoutConstraintAxisVertical;
  stack.spacing = 12;
  stack.translatesAutoresizingMaskIntoConstraints = NO;
  [self.view addSubview:stack];

  [NSLayoutConstraint activateConstraints:@[
    [stack.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:12],
    [stack.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
    [stack.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
    [stack.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-12],
    [_playersTable.heightAnchor constraintEqualToConstant:160],
    [_chatView.heightAnchor constraintEqualToConstant:120],
  ]];

  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(handleUpdate)
                                               name:[NetPlayManager didUpdateNotification]
                                             object:nil];

  [self handleUpdate];
}

- (void)dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)handleUpdate {
  NetPlayManager* manager = [NetPlayManager shared];

  if (!manager.isActive) {
    // The session was torn down elsewhere (connection lost, etc.) - back out.
    [self.navigationController popViewControllerAnimated:YES];
    return;
  }

  _hostCodeLabel.text = manager.hostCode.length > 0 ? manager.hostCode : @"";
  _hostCodeLabel.hidden = manager.hostCode.length == 0;
  _statusLabel.text = manager.statusText;
  _startButton.hidden = !manager.isHost;

  [_playersTable reloadData];

  NSArray<NSString*>* chat = manager.chatLog;
  _chatView.text = [chat componentsJoinedByString:@"\n"];
  if (chat.count > 0) {
    [_chatView scrollRangeToVisible:NSMakeRange(_chatView.text.length, 0)];
  }

  if (manager.gameStarting) {
    EmulationBootParameter* bootParameter = [manager takePendingBootParameter];
    if (bootParameter != nil) {
      [self presentEmulationWithBootParameter:bootParameter];
    }
  }
}

- (void)leaveTapped {
  [[NetPlayManager shared] stop];
  [self.navigationController popViewControllerAnimated:YES];
}

- (void)startTapped {
  [[NetPlayManager shared] startGame];
}

- (void)sendTapped {
  if (_chatInputField.text.length == 0) {
    return;
  }
  [[NetPlayManager shared] sendChatMessage:_chatInputField.text];
  _chatInputField.text = @"";
}

- (BOOL)textFieldShouldReturn:(UITextField*)textField {
  [self sendTapped];
  [textField resignFirstResponder];
  return YES;
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView*)tableView numberOfRowsInSection:(NSInteger)section {
  return [NetPlayManager shared].players.count;
}

- (UITableViewCell*)tableView:(UITableView*)tableView cellForRowAtIndexPath:(NSIndexPath*)indexPath {
  UITableViewCell* cell = [tableView dequeueReusableCellWithIdentifier:@"PlayerCell"];
  if (cell == nil) {
    cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"PlayerCell"];
  }

  NetPlayPlayerInfo* player = [NetPlayManager shared].players[indexPath.row];

  cell.textLabel.text = [NSString stringWithFormat:@"%@%@", player.name, player.isHost ? @" (Host)" : @""];
  cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ - %lu ms", player.gameStatusText,
                                                          (unsigned long)player.ping];
  return cell;
}

#pragma mark - Emulation handoff

// NetPlayLobbyViewController is always plain alloc/init (see NetPlaySetupViewController), never
// loaded from a storyboard scene of its own, so a storyboard segue isn't available here.
// Instantiate the real Emulation.storyboard directly instead - same scene, same boot pipeline
// (EmulationViewController.bootParameter -> BootManager::BootCore) as every other boot path,
// just triggered in code rather than via a segue.
- (void)presentEmulationWithBootParameter:(EmulationBootParameter*)bootParameter {
  UIStoryboard* storyboard = [UIStoryboard storyboardWithName:@"Emulation" bundle:nil];
  EmulationViewController* viewController = [storyboard instantiateInitialViewController];
  viewController.bootParameter = bootParameter;
  [self presentViewController:viewController animated:YES completion:nil];
}

@end
