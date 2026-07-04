// Copyright 2026 DolphiniOS Project
// SPDX-License-Identifier: GPL-2.0-or-later

#import "DSUServerManager.h"

#import <algorithm>
#import <vector>

#import <arpa/inet.h>
#import <fcntl.h>
#import <ifaddrs.h>
#import <mach/mach_time.h>
#import <net/if.h>
#import <sys/socket.h>
#import <unistd.h>

// DualShockUDPProto.h's Message<T>::CheckAndCastTo<T>() references NOTICE_LOG_FMT/
// CONTROLLERINTERFACE - a non-dependent name, so it's checked when this header is parsed, not
// only if CheckAndCastTo is actually called. Must come before the proto header include.
#import "Common/Logging/Log.h"

#import "InputCommon/ControllerInterface/DualShockUDPClient/DualShockUDPProto.h"

using namespace ciface::DualShockUDPClient::Proto;

namespace
{
// A client (e.g. the host device's Dolphin "DSU Client" input source) that registered interest
// via PadDataRequest. We keep streaming PadDataResponse packets to it until stop is called;
// DSU has no explicit "unregister" message, real servers just keep broadcasting to everyone
// who's ever asked.
struct RegisteredClient
{
  struct sockaddr_in address;

  bool operator==(const RegisteredClient& other) const
  {
    return address.sin_addr.s_addr == other.address.sin_addr.s_addr &&
           address.sin_port == other.address.sin_port;
  }
};
}  // namespace

@implementation DSUServerManager {
  int _socketFD;
  dispatch_source_t _readSource;
  dispatch_source_t _timerSource;
  dispatch_queue_t _queue;

  uint32_t _serverUID;
  uint32_t _packetCounter;

  std::vector<RegisteredClient> _clients;

  // Current input state. Only ever touched on _queue.
  uint8_t _buttonAnalog[DSUButtonCount];
  int8_t _leftStickX, _leftStickYInverted, _rightStickX, _rightStickYInverted;
  float _accelX, _accelY, _accelZ;
  float _gyroPitch, _gyroYaw, _gyroRoll;
}

+ (instancetype)shared {
  static DSUServerManager* instance = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    instance = [[DSUServerManager alloc] init];
  });
  return instance;
}

- (instancetype)init {
  self = [super init];
  if (self) {
    _socketFD = -1;
    _serverUID = arc4random();
    _queue = dispatch_queue_create("me.oatmealdome.dolphinios.dsuserver", DISPATCH_QUEUE_SERIAL);
  }
  return self;
}

- (BOOL)isRunning {
  return _socketFD >= 0;
}

- (NSUInteger)connectedClientCount {
  __block NSUInteger count = 0;
  dispatch_sync(_queue, ^{
    count = self->_clients.size();
  });
  return count;
}

- (nullable NSString*)localIPAddress {
  struct ifaddrs* interfaces = nullptr;
  if (getifaddrs(&interfaces) != 0) {
    return nil;
  }

  NSString* address = nil;
  for (struct ifaddrs* interface = interfaces; interface != nullptr; interface = interface->ifa_next) {
    if (interface->ifa_addr == nullptr || interface->ifa_addr->sa_family != AF_INET) {
      continue;
    }

    NSString* name = [NSString stringWithUTF8String:interface->ifa_name];
    // "en0" is the WiFi interface on every iOS device; prefer it, but fall back to any other
    // non-loopback interface (e.g. a wired adapter) if it's not up.
    if ([name isEqualToString:@"en0"] || address == nil) {
      char buffer[INET_ADDRSTRLEN];
      struct sockaddr_in* addr_in = (struct sockaddr_in*)interface->ifa_addr;
      if (inet_ntop(AF_INET, &addr_in->sin_addr, buffer, sizeof(buffer)) != nullptr) {
        NSString* candidate = [NSString stringWithUTF8String:buffer];
        if (![candidate isEqualToString:@"127.0.0.1"]) {
          address = candidate;
          if ([name isEqualToString:@"en0"]) {
            break;
          }
        }
      }
    }
  }

  freeifaddrs(interfaces);
  return address;
}

- (BOOL)startOnPort:(uint16_t)port error:(NSError* _Nullable* _Nullable)error {
  if (self.isRunning) {
    [self stop];
  }

  int fd = socket(AF_INET, SOCK_DGRAM, 0);
  if (fd < 0) {
    if (error) {
      *error = [NSError errorWithDomain:@"DSUServerManager" code:errno userInfo:nil];
    }
    return NO;
  }

  int reuse = 1;
  setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse));

  struct sockaddr_in bind_address {};
  bind_address.sin_family = AF_INET;
  bind_address.sin_addr.s_addr = htonl(INADDR_ANY);
  bind_address.sin_port = htons(port);

  if (bind(fd, (struct sockaddr*)&bind_address, sizeof(bind_address)) != 0) {
    if (error) {
      *error = [NSError errorWithDomain:@"DSUServerManager" code:errno userInfo:nil];
    }
    close(fd);
    return NO;
  }

  int flags = fcntl(fd, F_GETFL, 0);
  fcntl(fd, F_SETFL, flags | O_NONBLOCK);

  _socketFD = fd;
  _port = port;
  _packetCounter = 0;
  _clients.clear();
  memset(_buttonAnalog, 0, sizeof(_buttonAnalog));
  _leftStickX = _rightStickX = 0;
  _leftStickYInverted = _rightStickYInverted = 0;
  _accelX = _accelY = _accelZ = 0;
  _gyroPitch = _gyroYaw = _gyroRoll = 0;

  __weak DSUServerManager* weakSelf = self;

  _readSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, fd, 0, _queue);
  dispatch_source_set_event_handler(_readSource, ^{
    [weakSelf handleReadableSocket];
  });
  dispatch_resume(_readSource);

  _timerSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _queue);
  dispatch_source_set_timer(_timerSource, DISPATCH_TIME_NOW, NSEC_PER_SEC / 60, NSEC_PER_MSEC);
  dispatch_source_set_event_handler(_timerSource, ^{
    [weakSelf broadcastPadData];
  });
  dispatch_resume(_timerSource);

  return YES;
}

- (void)stop {
  if (_readSource != nil) {
    dispatch_source_cancel(_readSource);
    _readSource = nil;
  }
  if (_timerSource != nil) {
    dispatch_source_cancel(_timerSource);
    _timerSource = nil;
  }
  if (_socketFD >= 0) {
    close(_socketFD);
    _socketFD = -1;
  }
  dispatch_sync(_queue, ^{
    self->_clients.clear();
  });
}

#pragma mark - Input state (called from the UI, main thread)

- (void)setButton:(NSInteger)index pressed:(BOOL)pressed {
  if (index < 0 || index >= DSUButtonCount) {
    return;
  }
  dispatch_async(_queue, ^{
    self->_buttonAnalog[index] = pressed ? 255 : 0;
  });
}

- (void)setLeftStickX:(float)x y:(float)y {
  int8_t clampedX = (int8_t)fmaxf(-127, fminf(127, x * 127));
  int8_t clampedYInverted = (int8_t)fmaxf(-127, fminf(127, -y * 127));
  dispatch_async(_queue, ^{
    self->_leftStickX = clampedX;
    self->_leftStickYInverted = clampedYInverted;
  });
}

- (void)setRightStickX:(float)x y:(float)y {
  int8_t clampedX = (int8_t)fmaxf(-127, fminf(127, x * 127));
  int8_t clampedYInverted = (int8_t)fmaxf(-127, fminf(127, -y * 127));
  dispatch_async(_queue, ^{
    self->_rightStickX = clampedX;
    self->_rightStickYInverted = clampedYInverted;
  });
}

- (void)setAccelerationX:(float)x y:(float)y z:(float)z {
  dispatch_async(_queue, ^{
    self->_accelX = x;
    self->_accelY = y;
    self->_accelZ = z;
  });
}

- (void)setRotationRatePitch:(float)pitch yaw:(float)yaw roll:(float)roll {
  dispatch_async(_queue, ^{
    self->_gyroPitch = pitch;
    self->_gyroYaw = yaw;
    self->_gyroRoll = roll;
  });
}

#pragma mark - Socket handling (always on _queue)

- (void)handleReadableSocket {
  uint8_t buffer[128];
  struct sockaddr_in from {};
  socklen_t from_len = sizeof(from);

  while (true) {
    ssize_t received = recvfrom(_socketFD, buffer, sizeof(buffer), 0, (struct sockaddr*)&from, &from_len);
    if (received <= 0) {
      break;
    }

    [self handlePacket:buffer length:(size_t)received from:from];
  }
}

- (void)handlePacket:(const uint8_t*)data length:(size_t)length from:(struct sockaddr_in)from {
  if (length < sizeof(MessageHeader) + sizeof(u32)) {
    return;
  }

  u32 message_type;
  memcpy(&message_type, data + sizeof(MessageHeader), sizeof(message_type));

  if (message_type == MessageType::VersionRequest::TYPE) {
    Message<MessageType::VersionResponse> response(_serverUID);
    response.m_message.max_protocol_version = CEMUHOOK_PROTOCOL_VERSION;
    response.Finish();
    [self sendMessage:&response.m_message size:sizeof(response.m_message) to:from];
  } else if (message_type == MessageType::ListPorts::TYPE) {
    Message<MessageType::PortInfo> response(_serverUID);
    response.m_message.pad_id = 0;
    response.m_message.pad_state = DsState::Connected;
    response.m_message.model = DsModel::FullGyro;
    response.m_message.connection_type = DsConnection::Usb;
    response.m_message.battery_status = DsBattery::Full;
    response.Finish();
    [self sendMessage:&response.m_message size:sizeof(response.m_message) to:from];
  } else if (message_type == MessageType::PadDataRequest::TYPE) {
    RegisteredClient client{from};
    if (std::find(_clients.begin(), _clients.end(), client) == _clients.end()) {
      _clients.push_back(client);
    }
  }
}

- (void)sendMessage:(const void*)message size:(size_t)size to:(struct sockaddr_in)address {
  sendto(_socketFD, message, size, 0, (struct sockaddr*)&address, sizeof(address));
}

- (void)broadcastPadData {
  if (_clients.empty()) {
    return;
  }

  Message<MessageType::PadDataResponse> response(_serverUID);
  auto& pad = response.m_message;

  pad.pad_id = 0;
  pad.pad_state = DsState::Connected;
  pad.model = DsModel::FullGyro;
  pad.connection_type = DsConnection::Usb;
  pad.battery_status = DsBattery::Full;
  pad.active = 1;
  pad.hid_packet_counter = _packetCounter++;

  pad.button_states1 = static_cast<u8>((_buttonAnalog[DSUButtonShare] ? 0x1 : 0) |
                                        (_buttonAnalog[DSUButtonL3] ? 0x2 : 0) |
                                        (_buttonAnalog[DSUButtonR3] ? 0x4 : 0) |
                                        (_buttonAnalog[DSUButtonOptions] ? 0x8 : 0));
  pad.button_states2 = 0;
  pad.button_ps = _buttonAnalog[DSUButtonPS] ? 1 : 0;
  pad.button_touch = _buttonAnalog[DSUButtonTouch] ? 1 : 0;

  pad.left_stick_x = static_cast<u8>(128 + _leftStickX);
  pad.left_stick_y_inverted = static_cast<u8>(128 + _leftStickYInverted);
  pad.right_stick_x = static_cast<u8>(128 + _rightStickX);
  pad.right_stick_y_inverted = static_cast<u8>(128 + _rightStickYInverted);

  pad.button_dpad_left_analog = _buttonAnalog[DSUButtonDpadLeft];
  pad.button_dpad_down_analog = _buttonAnalog[DSUButtonDpadDown];
  pad.button_dpad_right_analog = _buttonAnalog[DSUButtonDpadRight];
  pad.button_dpad_up_analog = _buttonAnalog[DSUButtonDpadUp];
  pad.button_square_analog = _buttonAnalog[DSUButtonSquare];
  pad.button_cross_analog = _buttonAnalog[DSUButtonCross];
  pad.button_circle_analog = _buttonAnalog[DSUButtonCircle];
  pad.button_triangle_analog = _buttonAnalog[DSUButtonTriangle];
  pad.button_r1_analog = _buttonAnalog[DSUButtonR1];
  pad.button_l1_analog = _buttonAnalog[DSUButtonL1];
  pad.trigger_r2 = _buttonAnalog[DSUButtonR2];
  pad.trigger_l2 = _buttonAnalog[DSUButtonL2];

  pad.touch1.active = 0;
  pad.touch2.active = 0;

  pad.accelerometer_timestamp_us = mach_absolute_time() / 1000;
  pad.accelerometer_x_g = _accelX;
  pad.accelerometer_y_g = _accelY;
  pad.accelerometer_z_g = _accelZ;
  pad.gyro_pitch_deg_s = _gyroPitch;
  pad.gyro_yaw_deg_s = _gyroYaw;
  pad.gyro_roll_deg_s = _gyroRoll;

  response.Finish();

  for (const RegisteredClient& client : _clients) {
    [self sendMessage:&response.m_message size:sizeof(response.m_message) to:client.address];
  }
}

@end
