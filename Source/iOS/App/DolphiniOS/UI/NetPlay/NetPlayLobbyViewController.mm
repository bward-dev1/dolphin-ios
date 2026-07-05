// Copyright 2026 DolphiniOS Project
// SPDX-License-Identifier: GPL-2.0-or-later

#import "NetPlayLobbyViewController.h"

#import "EmulationBootParameter.h"
#import "EmulationViewController.h"
#import "NetPlayManager.h"

@interface NetPlayLobbyViewController () <UITextFieldDelegate>

@end

@implementation NetPlayLobbyViewController {
  UILabel* _hostCodeLabel;
  UILabel* _statusLabel;
  UITextView* _chatView;
  UITextField* _chatInputField;
  UIButton* _startButton;

  // Snapshotted once per -handleUpdate, not re-queried per dataSource callback: players can be
  // reassigned on NetPlay's own networking thread at any moment (someone joins/leaves), and
  // numberOfRowsInSection/cellForRowAtIndexPath calling [NetPlayManager shared].players
  // independently could see two different array lengths mid-reload and crash out of bounds.
  NSArray<NetPlayPlayerInfo*>* _displayedPlayers;
}

- (instancetype)init {
  return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
  [super viewDidLoad];

  self.title = @"NetPlay Lobby";

  self.navigationItem.hidesBackButton = YES;
  self.navigationItem.leftBarButtonItem =
      [[UIBarButtonItem alloc] initWithTitle:@"Leave"
                                        style:UIBarButtonItemStylePlain
                                       target:self
                                       action:@selector(leaveTapped)];

  [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"PlayerCell"];

  _hostCodeLabel = [[UILabel alloc] init];
  _hostCodeLabel.font = [UIFont monospacedSystemFontOfSize:32 weight:UIFontWeightBold];
  _hostCodeLabel.textAlignment = NSTextAlignmentCenter;
  _hostCodeLabel.translatesAutoresizingMaskIntoConstraints = NO;

  _statusLabel = [[UILabel alloc] init];
  _statusLabel.font = [UIFont systemFontOfSize:14];
  _statusLabel.textColor = [UIColor secondaryLabelColor];
  _statusLabel.textAlignment = NSTextAlignmentCenter;
  _statusLabel.numberOfLines = 0;
  _statusLabel.translatesAutoresizingMaskIntoConstraints = NO;

  UIStackView* headerStack = [[UIStackView alloc] initWithArrangedSubviews:@[ _hostCodeLabel, _statusLabel ]];
  headerStack.axis = UILayoutConstraintAxisVertical;
  headerStack.spacing = 4;
  headerStack.translatesAutoresizingMaskIntoConstraints = NO;

  UIView* header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 0, 76)];
  [header addSubview:headerStack];
  [NSLayoutConstraint activateConstraints:@[
    [headerStack.topAnchor constraintEqualToAnchor:header.topAnchor constant:16],
    [headerStack.leadingAnchor constraintGreaterThanOrEqualToAnchor:header.leadingAnchor constant:16],
    [headerStack.trailingAnchor constraintLessThanOrEqualToAnchor:header.trailingAnchor constant:-16],
    [headerStack.centerXAnchor constraintEqualToAnchor:header.centerXAnchor],
  ]];
  self.tableView.tableHeaderView = header;

  _chatView = [[UITextView alloc] init];
  _chatView.editable = NO;
  _chatView.font = [UIFont systemFontOfSize:14];
  _chatView.translatesAutoresizingMaskIntoConstraints = NO;
  _chatView.layer.borderColor = [UIColor separatorColor].CGColor;
  _chatView.layer.borderWidth = 1;
  _chatView.layer.cornerRadius = 8;
  [_chatView.heightAnchor constraintEqualToConstant:120].active = YES;

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

  UIStackView* footerStack = [[UIStackView alloc] initWithArrangedSubviews:@[ _chatView, chatInputRow, _startButton ]];
  footerStack.axis = UILayoutConstraintAxisVertical;
  footerStack.spacing = 16;
  footerStack.translatesAutoresizingMaskIntoConstraints = NO;

  UIView* footer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 0, 220)];
  [footer addSubview:footerStack];
  [NSLayoutConstraint activateConstraints:@[
    [footerStack.topAnchor constraintEqualToAnchor:footer.topAnchor constant:16],
    [footerStack.leadingAnchor constraintEqualToAnchor:footer.leadingAnchor constant:16],
    [footerStack.trailingAnchor constraintEqualToAnchor:footer.trailingAnchor constant:-16],
    [footerStack.bottomAnchor constraintEqualToAnchor:footer.bottomAnchor constant:-16],
  ]];
  self.tableView.tableFooterView = footer;

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

  _displayedPlayers = manager.players;
  [self.tableView reloadData];

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

- (NSInteger)numberOfSectionsInTableView:(UITableView*)tableView {
  return 1;
}

- (NSInteger)tableView:(UITableView*)tableView numberOfRowsInSection:(NSInteger)section {
  return _displayedPlayers.count;
}

- (nullable NSString*)tableView:(UITableView*)tableView titleForHeaderInSection:(NSInteger)section {
  return @"Players";
}

- (UITableViewCell*)tableView:(UITableView*)tableView cellForRowAtIndexPath:(NSIndexPath*)indexPath {
  UITableViewCell* cell = [tableView dequeueReusableCellWithIdentifier:@"PlayerCell"];
  if (cell == nil) {
    cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"PlayerCell"];
  }

  NetPlayPlayerInfo* player = _displayedPlayers[indexPath.row];

  cell.textLabel.text = [NSString stringWithFormat:@"%@%@", player.name, player.isHost ? @" (Host)" : @""];
  cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ - %lu ms", player.gameStatusText,
                                                          (unsigned long)player.ping];
  return cell;
}

#pragma mark - Emulation handoff

// NetPlayLobbyViewController is always plain alloc/init, never loaded from a storyboard scene
// of its own, so a storyboard segue isn't available here. Instantiate the real
// Emulation.storyboard directly instead - same scene, same boot pipeline
// (EmulationViewController.bootParameter -> BootManager::BootCore) as every other boot path,
// just triggered in code rather than via a segue.
- (void)presentEmulationWithBootParameter:(EmulationBootParameter*)bootParameter {
  UIStoryboard* storyboard = [UIStoryboard storyboardWithName:@"Emulation" bundle:nil];
  EmulationViewController* viewController = [storyboard instantiateInitialViewController];
  viewController.bootParameter = bootParameter;
  [self presentViewController:viewController animated:YES completion:nil];
}

@end
