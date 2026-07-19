// Copyright 2026 DolphiniOS Project
// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation

@objc public enum DeviceHoldOrientation: Int {
  case upright
  case landscape
  case portrait
}

@objc public enum DeviceFlatFacing: Int {
  case screenUp
  case screenDown
}

@objc public enum PointerCalibrationMode: Int {
  case pointAtTV
  case pointAtDevice
}

@objc public enum TVScreenSize: Int {
  case widescreen
  case standard
}

@objc public enum TVScreenType: Int {
  case lcdOrLed
  case oled
  case projector
  case crtOrOlder
}

// Answers collected by PreGameCalibrationViewController, re-asked on every boot per product
// requirements (this is intentionally not persisted across launches as a "last answer" default
// beyond the current process, and every game boot re-presents the screen).
@objc public class PreGameCalibrationPreferences: NSObject {
  @objc public static let shared = PreGameCalibrationPreferences()

  @objc public var holdOrientation: DeviceHoldOrientation = .upright
  @objc public var flatFacing: DeviceFlatFacing = .screenUp
  @objc public var calibrationMode: PointerCalibrationMode = .pointAtTV
  @objc public var isPlayingOnTV: Bool = true
  @objc public var tvScreenSize: TVScreenSize = .widescreen
  @objc public var tvScreenType: TVScreenType = .lcdOrLed

  private override init() {
    //
  }
}
