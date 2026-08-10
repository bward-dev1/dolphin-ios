// Copyright 2026 DolphiniOS Project
// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation

// The one and only thing the pre-game calibration screen collects that any code actually reads.
// EmulationiOSViewController consults it right after the Wii pointer goes live to decide whether
// to switch Touch IR Pointer to Motion and fire a one-off IMU-IR recenter.
//
// This used to sit alongside DeviceHoldOrientation, DeviceFlatFacing, TVScreenSize and
// TVScreenType. Those four (plus an "Are you playing on a TV?" switch) were collected on every
// single boot and then never read by anything -- not by TCDeviceMotion, not by the Wiimote
// emulation, not by the renderer. They have been deleted rather than kept as no-ops: a question
// whose answer changes nothing is pure delay in front of the game.
@objc public enum PointerCalibrationMode: Int {
  case pointAtTV
  case pointAtDevice
}

// Pointer-calibration state, persisted, and split by whether an external display is attached.
//
// Two things were wrong before. First, nothing persisted: every process launch reset the answers,
// so the same choices had to be re-entered before every boot, forever. Second, the reset values
// were hardcoded to "yes, TV" / "Point at TV", which is actively harmful handheld -- accepting
// them makes EmulationiOSViewController recenter the Wii Remote's neutral "forward" onto whatever
// direction the iPad happened to be facing at boot (flat on a table, mid-pickup) and drop Touch IR
// Pointer from Drag to None.
//
// Answers are now keyed by display configuration. "Point at TV" is the right answer with a TV
// attached and the wrong one without, so a single stored value would be wrong half the time; two
// slots let the same player be correct both docked and handheld without ever re-answering.
@objc public class PreGameCalibrationPreferences: NSObject {
  @objc public static let shared = PreGameCalibrationPreferences()

  private enum Key {
    static let hasAnsweredTV = "DOLPreGameCalibrationHasAnsweredTV"
    static let hasAnsweredHandheld = "DOLPreGameCalibrationHasAnsweredHandheld"
    static let calibrationModeTV = "DOLPreGameCalibrationModeTV"
    static let calibrationModeHandheld = "DOLPreGameCalibrationModeHandheld"
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

  private var answeredKey: String {
    return PreGameCalibrationPreferences.isExternalDisplayAttached
      ? Key.hasAnsweredTV : Key.hasAnsweredHandheld
  }

  private var modeKey: String {
    return PreGameCalibrationPreferences.isExternalDisplayAttached
      ? Key.calibrationModeTV : Key.calibrationModeHandheld
  }

  // True once the player has tapped through the screen at least once *in the display setup they
  // are in right now*. This is what gates the pre-boot screen: answered means never asked again.
  // Plugging in a TV for the first time is a genuinely different setup and does get asked once.
  @objc public var hasAnsweredForCurrentDisplay: Bool {
    return self.store.bool(forKey: self.answeredKey)
  }

  @objc public func markAnsweredForCurrentDisplay() {
    self.store.set(true, forKey: self.answeredKey)
  }

  @objc public var calibrationMode: PointerCalibrationMode {
    get {
      guard self.hasAnsweredForCurrentDisplay,
            let raw = self.store.object(forKey: self.modeKey) as? Int,
            let value = PointerCalibrationMode(rawValue: raw) else {
        // Never hardcode "you have a TV". With a real external display attached, pointing at it
        // is the only thing that makes sense; without one, the device *is* the screen.
        return PreGameCalibrationPreferences.isExternalDisplayAttached ? .pointAtTV : .pointAtDevice
      }

      return value
    }
    set {
      self.store.set(newValue.rawValue, forKey: self.modeKey)
    }
  }
}
