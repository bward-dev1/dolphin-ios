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

// Answers collected by PreGameCalibrationViewController. The screen itself still appears before
// every boot (that's deliberate), but the answers now persist across launches and, until the
// player has answered even once, the starting values are derived from whether a TV/AirPlay
// display is *actually* attached rather than being hardcoded to "yes, TV".
//
// The hardcoded-TV defaults were a real problem for handheld play: every fresh launch reset the
// player to "Are you playing on a TV? -> Yes" and "What are you calibrating the pointer to? ->
// Point at TV". Accepting those defaults on a device with no TV makes EmulationiOSViewController
// fire a pointer recenter right after boot, pinning the Wii Remote's neutral "forward" to
// whatever direction the iPad happened to be facing at that instant (flat on a table, propped on
// a stand, mid-pickup) instead of to how the player is actually holding it. Combined with the
// values never being remembered, a handheld-only player had to correct the same two controls
// before every single game boot, forever.
@objc public class PreGameCalibrationPreferences: NSObject {
  @objc public static let shared = PreGameCalibrationPreferences()

  private enum Key {
    static let hasAnswered = "DOLPreGameCalibrationHasAnswered"
    static let holdOrientation = "DOLPreGameCalibrationHoldOrientation"
    static let flatFacing = "DOLPreGameCalibrationFlatFacing"
    static let calibrationMode = "DOLPreGameCalibrationMode"
    static let isPlayingOnTV = "DOLPreGameCalibrationIsPlayingOnTV"
    static let tvScreenSize = "DOLPreGameCalibrationTVScreenSize"
    static let tvScreenType = "DOLPreGameCalibrationTVScreenType"
  }

  private let store = UserDefaults.standard

  private override init() {
    super.init()
  }

  // Whether an external display scene (AirPlay to an Apple TV, a USB-C/HDMI display, a capture
  // dongle) is attached right now. EmulationCoordinator is the authority here -- its flag is set
  // and cleared by ExternalDisplaySceneDelegate's own connect/disconnect callbacks, so it tracks
  // the scene the renderer would actually be handed to, not merely "some second UIScreen exists"
  // (which is also true for plain mirroring, where there is no separate scene and the game keeps
  // rendering to the device's own screen).
  @objc public static var isExternalDisplayAttached: Bool {
    return EmulationCoordinator.shared().isExternalDisplayConnected
  }

  // True once the player has actually tapped through the screen at least once. Before that, the
  // getters below fall back to display-derived defaults instead of stored values.
  @objc public var hasAnswered: Bool {
    return self.store.bool(forKey: Key.hasAnswered)
  }

  @objc public func markAnswered() {
    self.store.set(true, forKey: Key.hasAnswered)
  }

  private func storedInt(_ key: String) -> Int? {
    guard self.hasAnswered else {
      return nil
    }

    return self.store.object(forKey: key) as? Int
  }

  @objc public var holdOrientation: DeviceHoldOrientation {
    get {
      guard let raw = self.storedInt(Key.holdOrientation),
            let value = DeviceHoldOrientation(rawValue: raw) else {
        // Upright (one-handed, pointed like a real Wii Remote) only makes sense when there's a
        // separate screen to point at. Held in your hands, the device is the screen, so the
        // two-handed landscape grip is the sane starting point.
        return PreGameCalibrationPreferences.isExternalDisplayAttached ? .upright : .landscape
      }

      return value
    }
    set {
      self.store.set(newValue.rawValue, forKey: Key.holdOrientation)
    }
  }

  @objc public var flatFacing: DeviceFlatFacing {
    get {
      guard let raw = self.storedInt(Key.flatFacing),
            let value = DeviceFlatFacing(rawValue: raw) else {
        return .screenUp
      }

      return value
    }
    set {
      self.store.set(newValue.rawValue, forKey: Key.flatFacing)
    }
  }

  @objc public var calibrationMode: PointerCalibrationMode {
    get {
      guard let raw = self.storedInt(Key.calibrationMode),
            let value = PointerCalibrationMode(rawValue: raw) else {
        return PreGameCalibrationPreferences.isExternalDisplayAttached ? .pointAtTV : .pointAtDevice
      }

      return value
    }
    set {
      self.store.set(newValue.rawValue, forKey: Key.calibrationMode)
    }
  }

  @objc public var isPlayingOnTV: Bool {
    get {
      guard self.hasAnswered, self.store.object(forKey: Key.isPlayingOnTV) != nil else {
        return PreGameCalibrationPreferences.isExternalDisplayAttached
      }

      return self.store.bool(forKey: Key.isPlayingOnTV)
    }
    set {
      self.store.set(newValue, forKey: Key.isPlayingOnTV)
    }
  }

  @objc public var tvScreenSize: TVScreenSize {
    get {
      guard let raw = self.storedInt(Key.tvScreenSize),
            let value = TVScreenSize(rawValue: raw) else {
        return .widescreen
      }

      return value
    }
    set {
      self.store.set(newValue.rawValue, forKey: Key.tvScreenSize)
    }
  }

  @objc public var tvScreenType: TVScreenType {
    get {
      guard let raw = self.storedInt(Key.tvScreenType),
            let value = TVScreenType(rawValue: raw) else {
        return .lcdOrLed
      }

      return value
    }
    set {
      self.store.set(newValue.rawValue, forKey: Key.tvScreenType)
    }
  }
}
