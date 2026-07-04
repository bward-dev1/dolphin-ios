// Copyright 2026 DolphiniOS Project
// SPDX-License-Identifier: GPL-2.0-or-later

#import "NetPlayManager.h"

#import <mutex>

#import "Core/Boot/Boot.h"
#import "Core/NetPlayClient.h"
#import "Core/NetPlayServer.h"
#import "Core/SyncIdentifier.h"
#import "UICommon/GameFile.h"

#import "EmulationBootParameter.h"
#import "FoundationStringUtil.h"
#import "GameFileCacheManager.h"
#import "GameFilePtrWrapper.h"

@implementation NetPlayPlayerInfo
@end

namespace
{
// Bridges Dolphin's NetPlay::NetPlayUI callback interface (called from NetPlay's own
// networking thread) to NetPlayManager's published, main-thread-safe state. Every method here
// runs off the main thread - it must not touch UIKit directly, only update guarded state and
// ask NetPlayManager to notify on the main queue.
class IOSNetPlayUI final : public NetPlay::NetPlayUI
{
public:
  explicit IOSNetPlayUI(NetPlayManager* manager) : m_manager(manager) {}

  void BootGame(const std::string& filename,
                std::unique_ptr<BootSessionData> boot_session_data) override
  {
    [m_manager handleBootGame:filename sessionData:std::move(boot_session_data)];
  }

  void StopGame() override { [m_manager handleStopGame]; }
  bool IsHosting() const override { return [m_manager isHost]; }

  void Update() override { [m_manager handleRefresh]; }
  void AppendChat(const std::string& msg) override { [m_manager handleAppendChat:msg]; }

  void OnMsgChangeGame(const NetPlay::SyncIdentifier& sync_identifier,
                       const std::string& netplay_name) override
  {
    [m_manager handleStatus:"Game changed to " + netplay_name];
  }

  void OnMsgChangeGBARom(int pad, const NetPlay::GBAConfig& config) override {}

  void OnMsgStartGame() override { [m_manager handleGameStarting]; }
  void OnMsgStopGame() override { [m_manager handleStopGame]; }
  void OnMsgPowerButton() override { [m_manager handleStatus:"Remote power button pressed"]; }

  void OnPlayerConnect(const std::string& player) override
  {
    [m_manager handleAppendChat:player + " joined"];
    [m_manager handleRefresh];
  }

  void OnPlayerDisconnect(const std::string& player) override
  {
    [m_manager handleAppendChat:player + " left"];
    [m_manager handleRefresh];
  }

  void OnPadBufferChanged(u32 buffer) override {}
  void OnHostInputAuthorityChanged(bool enabled) override {}

  void OnDesync(u32 frame, const std::string& player) override
  {
    [m_manager handleStatus:"Desync detected with " + player + " at frame " +
                            std::to_string(frame)];
  }

  void OnConnectionLost() override { [m_manager handleStatus:"Connection to the host was lost"]; }

  void OnConnectionError(const std::string& message) override
  {
    [m_manager handleStatus:"Connection error: " + message];
  }

  void OnTraversalError(Common::TraversalClient::FailureReason error) override
  {
    std::string message;
    switch (error)
    {
    case Common::TraversalClient::FailureReason::BadHost:
      message = "Couldn't find that host code. Check it and try again.";
      break;
    case Common::TraversalClient::FailureReason::VersionTooOld:
      message = "The traversal server rejected this app version.";
      break;
    case Common::TraversalClient::FailureReason::ServerForgotAboutUs:
    case Common::TraversalClient::FailureReason::SocketSendError:
    case Common::TraversalClient::FailureReason::ResendTimeout:
    default:
      message = "Lost contact with the traversal server. Check your connection and try again.";
      break;
    }
    [m_manager handleStatus:message];
  }

  void OnTraversalStateChanged(Common::TraversalClient::State state) override
  {
    if (state == Common::TraversalClient::State::Connected)
    {
      const auto host_id = Common::g_TraversalClient->GetHostID();
      [m_manager handleHostCodeResolved:std::string(host_id.begin(), host_id.end())];
    }
  }

  void OnGameStartAborted() override { [m_manager handleStatus:"Game start was aborted"]; }

  void OnGolferChanged(bool is_golfer, const std::string& golfer_name) override {}
  void OnTtlDetermined(u8 ttl) override {}

  bool IsRecording() override { return false; }

  std::shared_ptr<const UICommon::GameFile>
  FindGameFile(const NetPlay::SyncIdentifier& sync_identifier,
               NetPlay::SyncIdentifierComparison* found = nullptr) override
  {
    NetPlay::SyncIdentifierComparison temp;
    if (!found)
      found = &temp;
    *found = NetPlay::SyncIdentifierComparison::DifferentGame;

    NSArray<GameFilePtrWrapper*>* games = [[GameFileCacheManager sharedManager] getGames];
    for (GameFilePtrWrapper* wrapper in games)
    {
      const auto comparison = wrapper.gameFile->CompareSyncIdentifier(sync_identifier);
      *found = std::min(*found, comparison);
      if (*found == NetPlay::SyncIdentifierComparison::SameGame)
        return wrapper.gameFile;
    }
    return nullptr;
  }

  std::string FindGBARomPath(const std::array<u8, 20>& hash, std::string_view title,
                             int device_number) override
  {
    // GBA link-cable integration isn't wired up on iOS (no GBA rom picker exists yet); mirrors
    // upstream's own behavior on platforms built without libmgba support.
    return "";
  }

  void ShowGameDigestDialog(const std::string& title) override
  {
    [m_manager handleStatus:"Verifying game files: " + title];
  }

  void SetGameDigestProgress(int pid, int progress) override
  {
    [m_manager handleStatus:"Verifying game files... " + std::to_string(progress) + "%"];
  }

  void SetGameDigestResult(int pid, const std::string& result) override
  {
    [m_manager handleStatus:"Game file check: " + result];
  }

  void AbortGameDigest() override {}

  void OnIndexAdded(bool success, std::string error) override {}
  void OnIndexRefreshFailed(std::string error) override {}

  void ShowChunkedProgressDialog(const std::string& title, u64 data_size,
                                 const std::vector<int>& players) override
  {
    [m_manager handleStatus:"Syncing " + title + "..."];
  }

  void HideChunkedProgressDialog() override {}
  void SetChunkedProgress(int pid, u64 progress) override {}

  void SetHostWiiSyncData(std::vector<u64> titles, std::string redirect_folder) override
  {
    [m_manager handleSetHostWiiSyncData:std::move(titles)
                          redirectFolder:std::move(redirect_folder)];
  }

private:
  __weak NetPlayManager* m_manager;
};
}  // namespace

@implementation NetPlayManager {
  std::mutex _stateMutex;
  std::unique_ptr<IOSNetPlayUI> _ui;
  std::unique_ptr<NetPlay::NetPlayServer> _server;
  std::unique_ptr<NetPlay::NetPlayClient> _client;

  BOOL _isHost;
  NSString* _hostCode;
  NSString* _statusText;
  NSMutableArray<NSString*>* _chatLog;
  NSArray<NetPlayPlayerInfo*>* _players;
  BOOL _gameStarting;

  std::string _pendingBootPath;
  BootSessionData* _pendingBootSessionData;
}

+ (instancetype)shared {
  static NetPlayManager* instance = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    instance = [[NetPlayManager alloc] init];
  });
  return instance;
}

+ (NSNotificationName)didUpdateNotification {
  return @"NetPlayManagerDidUpdateNotification";
}

- (instancetype)init {
  self = [super init];
  if (self) {
    _statusText = @"";
    _chatLog = [NSMutableArray array];
    _players = @[];
    _pendingBootSessionData = nullptr;
  }
  return self;
}

- (BOOL)isActive {
  std::lock_guard<std::mutex> lock(_stateMutex);
  return _server != nullptr || _client != nullptr;
}

- (BOOL)isHost {
  std::lock_guard<std::mutex> lock(_stateMutex);
  return _server != nullptr;
}

- (BOOL)isConnected {
  std::lock_guard<std::mutex> lock(_stateMutex);
  return _client != nullptr && _client->IsConnected();
}

- (nullable NSString*)hostCode {
  std::lock_guard<std::mutex> lock(_stateMutex);
  return _hostCode;
}

- (NSString*)statusText {
  std::lock_guard<std::mutex> lock(_stateMutex);
  return _statusText;
}

- (NSArray<NSString*>*)chatLog {
  std::lock_guard<std::mutex> lock(_stateMutex);
  return [_chatLog copy];
}

- (NSArray<NetPlayPlayerInfo*>*)players {
  std::lock_guard<std::mutex> lock(_stateMutex);
  return _players;
}

- (BOOL)gameStarting {
  std::lock_guard<std::mutex> lock(_stateMutex);
  return _gameStarting;
}

- (void)postUpdateNotification {
  dispatch_async(dispatch_get_main_queue(), ^{
    [[NSNotificationCenter defaultCenter] postNotificationName:[NetPlayManager didUpdateNotification]
                                                         object:self];
  });
}

#pragma mark - NetPlayUI bridge handlers (called from the NetPlay networking thread)

- (void)handleRefresh {
  std::vector<const NetPlay::Player*> raw_players;
  {
    std::lock_guard<std::mutex> lock(_stateMutex);
    if (_client == nullptr) {
      return;
    }
  }

  // GetPlayers() takes its own internal lock; must not hold _stateMutex while calling it to
  // avoid a lock-order inversion with NetPlay's own threads.
  NetPlay::NetPlayClient* client;
  {
    std::lock_guard<std::mutex> lock(_stateMutex);
    client = _client.get();
  }
  if (client == nullptr) {
    return;
  }

  raw_players = client->GetPlayers();

  NSMutableArray<NetPlayPlayerInfo*>* players = [NSMutableArray array];
  for (const NetPlay::Player* player : raw_players) {
    NetPlayPlayerInfo* info = [[NetPlayPlayerInfo alloc] init];
    info.name = CppToFoundationString(player->name);
    info.ping = player->ping;
    info.isHost = player->IsHost();

    switch (player->game_status) {
    case NetPlay::SyncIdentifierComparison::SameGame:
      info.gameStatusText = @"Ready";
      break;
    case NetPlay::SyncIdentifierComparison::Unknown:
      info.gameStatusText = @"Unknown";
      break;
    default:
      info.gameStatusText = @"Different game";
      break;
    }

    [players addObject:info];
  }

  {
    std::lock_guard<std::mutex> lock(_stateMutex);
    _players = players;
  }

  [self postUpdateNotification];
}

- (void)handleAppendChat:(const std::string&)msg {
  NSString* line = CppToFoundationString(msg);
  {
    std::lock_guard<std::mutex> lock(_stateMutex);
    [_chatLog addObject:line];
  }
  [self postUpdateNotification];
}

- (void)handleStatus:(const std::string&)msg {
  NSString* text = CppToFoundationString(msg);
  {
    std::lock_guard<std::mutex> lock(_stateMutex);
    _statusText = text;
  }
  [self postUpdateNotification];
}

- (void)handleHostCodeResolved:(const std::string&)hostId {
  NSString* code = CppToFoundationString(hostId);
  {
    std::lock_guard<std::mutex> lock(_stateMutex);
    _hostCode = code;
  }
  [self postUpdateNotification];
}

- (void)handleBootGame:(const std::string&)filename
           sessionData:(std::unique_ptr<BootSessionData>)sessionData {
  {
    std::lock_guard<std::mutex> lock(_stateMutex);
    _pendingBootPath = filename;
    if (_pendingBootSessionData != nullptr) {
      delete _pendingBootSessionData;
    }
    _pendingBootSessionData = sessionData.release();
    _gameStarting = YES;
  }
  [self postUpdateNotification];
}

- (void)handleGameStarting {
  {
    std::lock_guard<std::mutex> lock(_stateMutex);
    _gameStarting = YES;
  }
  [self postUpdateNotification];
}

- (void)handleStopGame {
  {
    std::lock_guard<std::mutex> lock(_stateMutex);
    _gameStarting = NO;
  }
  [[NSNotificationCenter defaultCenter] postNotificationName:@"NetPlayManagerRequestStopNotification"
                                                       object:self];
  [self postUpdateNotification];
}

- (void)handleSetHostWiiSyncData:(std::vector<u64>)titles
                   redirectFolder:(std::string)redirectFolder {
  std::lock_guard<std::mutex> lock(_stateMutex);
  if (_client != nullptr) {
    _client->SetWiiSyncData(nullptr, std::move(titles), std::move(redirectFolder));
  }
}

#pragma mark - Public API

- (void)hostGameWithFile:(GameFilePtrWrapper*)gameFile
                     port:(uint16_t)port
             useTraversal:(BOOL)useTraversal
                  useUPnP:(BOOL)useUPnP
                 nickname:(NSString*)nickname
               completion:(void (^)(BOOL success, NSString* _Nullable error))completion {
  [self stop];

  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    auto ui = std::make_unique<IOSNetPlayUI>(self);

    NetPlay::NetTraversalConfig traversal_config(useTraversal, "stun.dolphin-emu.org", 6262, 6226);
    auto server = std::make_unique<NetPlay::NetPlayServer>(port, useUPnP, ui.get(), traversal_config);

    if (!server->is_connected) {
      dispatch_async(dispatch_get_main_queue(), ^{
        completion(NO, [NSString stringWithFormat:@"Failed to listen on port %u. Is another "
                                                    @"instance already hosting?", port]);
      });
      return;
    }

    NetPlay::SyncIdentifier sync_identifier = gameFile.gameFile->GetSyncIdentifier();
    std::string netplay_name = gameFile.gameFile->GetInternalName();
    if (netplay_name.empty()) {
      netplay_name = "Game";
    }
    server->ChangeGame(sync_identifier, netplay_name);

    // The host also runs a normal client pointed at its own local server - matching Dolphin's
    // own hosting flow exactly (upstream MainWindow::NetPlayHost + NetPlayJoin).
    NetPlay::NetTraversalConfig local_config(false, "", 0);
    auto client = std::make_unique<NetPlay::NetPlayClient>("127.0.0.1", server->GetPort(), ui.get(),
                                                            FoundationToCppString(nickname),
                                                            local_config);

    bool connected = client->IsConnected();

    {
      std::lock_guard<std::mutex> lock(self->_stateMutex);
      self->_ui = std::move(ui);
      self->_server = std::move(server);
      self->_client = std::move(client);
      self->_isHost = YES;
      self->_statusText = connected ? @"Hosting - waiting for players" : @"Failed to connect locally";
    }

    dispatch_async(dispatch_get_main_queue(), ^{
      if (connected) {
        completion(YES, nil);
      } else {
        completion(NO, @"Failed to connect to the local server.");
      }
    });

    [self postUpdateNotification];
  });
}

- (void)joinWithAddress:(NSString*)address
                    port:(uint16_t)port
            useTraversal:(BOOL)useTraversal
                nickname:(NSString*)nickname
              completion:(void (^)(BOOL success, NSString* _Nullable error))completion {
  [self stop];

  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    auto ui = std::make_unique<IOSNetPlayUI>(self);

    NetPlay::NetTraversalConfig traversal_config(useTraversal, "stun.dolphin-emu.org", 6262);
    auto client = std::make_unique<NetPlay::NetPlayClient>(FoundationToCppString(address), port, ui.get(),
                                                            FoundationToCppString(nickname),
                                                            traversal_config);

    bool connected = client->IsConnected();

    {
      std::lock_guard<std::mutex> lock(self->_stateMutex);
      self->_ui = std::move(ui);
      self->_client = std::move(client);
      self->_isHost = NO;
      self->_statusText = connected ? @"Connected - waiting for the host" : @"Failed to connect";
    }

    dispatch_async(dispatch_get_main_queue(), ^{
      if (connected) {
        completion(YES, nil);
      } else {
        completion(NO, @"Couldn't connect. Check the address/host code and try again.");
      }
    });

    [self postUpdateNotification];
  });
}

- (void)sendChatMessage:(NSString*)message {
  std::lock_guard<std::mutex> lock(_stateMutex);
  if (_client != nullptr) {
    _client->SendChatMessage(FoundationToCppString(message));
  }
}

- (void)startGame {
  std::lock_guard<std::mutex> lock(_stateMutex);
  if (_server != nullptr) {
    _server->StartGame();
  }
}

- (void)stop {
  std::unique_ptr<NetPlay::NetPlayServer> serverToDestroy;
  std::unique_ptr<NetPlay::NetPlayClient> clientToDestroy;
  std::unique_ptr<IOSNetPlayUI> uiToDestroy;

  {
    std::lock_guard<std::mutex> lock(_stateMutex);
    // Client must be torn down before the server it's connected to.
    clientToDestroy = std::move(_client);
    serverToDestroy = std::move(_server);
    uiToDestroy = std::move(_ui);

    _isHost = NO;
    _hostCode = nil;
    _statusText = @"";
    [_chatLog removeAllObjects];
    _players = @[];
    _gameStarting = NO;

    if (_pendingBootSessionData != nullptr) {
      delete _pendingBootSessionData;
      _pendingBootSessionData = nullptr;
    }
    _pendingBootPath.clear();
  }

  if (clientToDestroy != nullptr) {
    clientToDestroy->Stop();
  }

  [self postUpdateNotification];
}

- (nullable EmulationBootParameter*)takePendingBootParameter {
  std::string path;
  BootSessionData* sessionData;

  {
    std::lock_guard<std::mutex> lock(_stateMutex);
    if (_pendingBootPath.empty()) {
      return nil;
    }
    path = _pendingBootPath;
    sessionData = _pendingBootSessionData;
    _pendingBootSessionData = nullptr;
    _pendingBootPath.clear();
    _gameStarting = NO;
  }

  EmulationBootParameter* parameter = [[EmulationBootParameter alloc] init];
  parameter.bootType = EmulationBootTypeFile;
  parameter.path = CppToFoundationString(path);
  parameter.netplayBootSessionData = sessionData;
  return parameter;
}

@end
