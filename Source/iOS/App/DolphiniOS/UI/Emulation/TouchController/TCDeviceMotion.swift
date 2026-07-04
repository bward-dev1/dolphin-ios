// Copyright 2022 DolphiniOS Project
// SPDX-License-Identifier: GPL-2.0-or-later

import CoreMotion
import Foundation

@objc public class TCDeviceMotion: NSObject {
  @objc public static let shared = TCDeviceMotion()

  private let motionManager = CMMotionManager()
  private let operationQueue = OperationQueue()

  private var orientation: UIInterfaceOrientation = .portrait
  private var motionEnabled = false
  private var port = 0

  // Gyroscope bias (drift) captured during a "flat" calibration, in raw device-frame
  // rad/s. Subtracted from every reading so a device sitting still reports ~zero rotation.
  // MEMS gyros have a small constant bias that otherwise integrates into pointer drift.
  private var gyroBiasX: Double = 0.0
  private var gyroBiasY: Double = 0.0
  private var gyroBiasZ: Double = 0.0

  // Flat-calibration sampling state.
  private var isCalibrating = false
  private var calibrationSamples = 0
  private var calibrationSumX = 0.0
  private var calibrationSumY = 0.0
  private var calibrationSumZ = 0.0
  private static let kCalibrationSampleTarget = 120  // ~0.6s at 200Hz
  private var calibrationCompletion: (() -> Void)?

  override required init() {
    //
  }

  @objc func registerMotionHandlers() {
    // Set our orientation properly
    self.statusBarOrientationChanged()

    // Set the sensor update times
    // 200Hz is the Wiimote update interval
    let updateInterval: Double = 1.0 / 200.0
    self.motionManager.accelerometerUpdateInterval = updateInterval
    self.motionManager.gyroUpdateInterval = updateInterval

    // Register the handlers
    self.motionManager.startAccelerometerUpdates(to: operationQueue) { (data, error) in
      if (error != nil) {
        return
      }

      // Get the data
      let acceleration = data!.acceleration

      var x, y: Double
      var z = acceleration.z

      switch (self.orientation) {
      case .portrait, .unknown:
        x = -acceleration.x
        y = -acceleration.y
      case .landscapeRight:
        x = acceleration.y
        y = -acceleration.x
      case .portraitUpsideDown:
        x = acceleration.x
        y = acceleration.y
      case .landscapeLeft:
        x = -acceleration.y
        y = acceleration.x
      @unknown default:
        return
      }

      // CMAccelerationData's units are G's
      let gravity = -9.81
      x *= gravity
      y *= gravity
      z *= gravity

      TCManagerInterface.setAxisValueFor(TCButtonType.wiiAccelLeft.rawValue, controller: self.port, value: Float(x))
      TCManagerInterface.setAxisValueFor(TCButtonType.wiiAccelRight.rawValue, controller: self.port, value: Float(x))
      TCManagerInterface.setAxisValueFor(TCButtonType.wiiAccelForward.rawValue, controller: self.port, value: Float(y))
      TCManagerInterface.setAxisValueFor(TCButtonType.wiiAccelBackward.rawValue, controller: self.port, value: Float(y))
      TCManagerInterface.setAxisValueFor(TCButtonType.wiiAccelUp.rawValue, controller: self.port, value: Float(z))
      TCManagerInterface.setAxisValueFor(TCButtonType.wiiAccelDown.rawValue, controller: self.port, value: Float(z))

      TCManagerInterface.setAxisValueFor(TCButtonType.nunchukAccelLeft.rawValue, controller: self.port, value: Float(x))
      TCManagerInterface.setAxisValueFor(TCButtonType.nunchukAccelRight.rawValue, controller: self.port, value: Float(x))
      TCManagerInterface.setAxisValueFor(TCButtonType.nunchukAccelForward.rawValue, controller: self.port, value: Float(y))
      TCManagerInterface.setAxisValueFor(TCButtonType.nunchukAccelBackward.rawValue, controller: self.port, value: Float(y))
      TCManagerInterface.setAxisValueFor(TCButtonType.nunchukAccelUp.rawValue, controller: self.port, value: Float(z))
      TCManagerInterface.setAxisValueFor(TCButtonType.nunchukAccelDown.rawValue, controller: self.port, value: Float(z))
    }

    self.motionManager.startGyroUpdates(to: operationQueue) { (data, error) in
      if (error != nil) {
        return
      }

      // Get the raw data (device frame, rad/s)
      let rotation_rate = data!.rotationRate

      // While calibrating, accumulate raw samples to estimate the resting bias, and
      // suppress output so the pointer doesn't twitch during the "hold still" moment.
      if (self.isCalibrating) {
        self.calibrationSumX += rotation_rate.x
        self.calibrationSumY += rotation_rate.y
        self.calibrationSumZ += rotation_rate.z
        self.calibrationSamples += 1

        if (self.calibrationSamples >= TCDeviceMotion.kCalibrationSampleTarget) {
          let n = Double(self.calibrationSamples)
          self.gyroBiasX = self.calibrationSumX / n
          self.gyroBiasY = self.calibrationSumY / n
          self.gyroBiasZ = self.calibrationSumZ / n
          self.isCalibrating = false

          let completion = self.calibrationCompletion
          self.calibrationCompletion = nil
          if let completion = completion {
            DispatchQueue.main.async { completion() }
          }
        }
        return
      }

      // Subtract the calibrated resting bias so a still device reports ~zero rotation.
      let raw_x = rotation_rate.x - self.gyroBiasX
      let raw_y = rotation_rate.y - self.gyroBiasY
      let raw_z = rotation_rate.z - self.gyroBiasZ

      var x, y: Double
      let z = raw_z

      switch (self.orientation) {
      case .portrait, .unknown:
        x = -raw_x
        y = -raw_y
      case .landscapeRight:
        x = raw_y
        y = -raw_x
      case .portraitUpsideDown:
        x = raw_x
        y = raw_y
      case .landscapeLeft:
        x = -raw_y
        y = raw_x
      @unknown default:
        return
      }

      TCManagerInterface.setAxisValueFor(TCButtonType.wiiGyroPitchUp.rawValue, controller: self.port, value: Float(x))
      TCManagerInterface.setAxisValueFor(TCButtonType.wiiGyroPitchDown.rawValue, controller: self.port, value: Float(x))
      TCManagerInterface.setAxisValueFor(TCButtonType.wiiGyroRollLeft.rawValue, controller: self.port, value: Float(y))
      TCManagerInterface.setAxisValueFor(TCButtonType.wiiGyroRollRight.rawValue, controller: self.port, value: Float(y))
      TCManagerInterface.setAxisValueFor(TCButtonType.wiiGyroYawLeft.rawValue, controller: self.port, value: Float(z))
      TCManagerInterface.setAxisValueFor(TCButtonType.wiiGyroYawRight.rawValue, controller: self.port, value: Float(z))
    }
  }

  @objc func setMotionEnabled(_ mode: Bool) {
    if (self.motionEnabled == mode) {
      return
    }

    self.motionEnabled = mode

    if (self.motionEnabled) {
      self.registerMotionHandlers()
    } else {
      self.motionManager.stopAccelerometerUpdates()
      self.motionManager.stopGyroUpdates()
    }
  }

  @objc func setPort(_ port: Int) {
    self.port = port
  }

  // MARK: - Calibration

  // "Calibrate gyroscope": lay the device perfectly flat and still, then call this. It
  // measures the resting gyro bias over ~0.6s and subtracts it from all future readings,
  // eliminating the slow pointer/motion drift you otherwise fight during Wii games.
  // `completion` fires on the main queue once sampling finishes (or immediately if motion
  // isn't running).
  @objc func calibrateFlat(_ completion: (() -> Void)?) {
    guard self.motionEnabled else {
      completion?()
      return
    }

    self.calibrationSamples = 0
    self.calibrationSumX = 0.0
    self.calibrationSumY = 0.0
    self.calibrationSumZ = 0.0
    self.calibrationCompletion = completion
    self.isCalibrating = true
  }

  // "Calibrate gyroscope for TV": hold the device pointed straight at your TV, then call
  // this. It pulses the emulated Wiimote's IMU-IR "Recenter" control (bound to Button 800
  // in Touchscreen.ini), which makes the CURRENT device orientation the neutral forward
  // point. After this, aiming at the TV puts the cursor dead-center — no more twisting your
  // wrist away from the screen to find the pointer.
  @objc func recenterPointer() {
    let recenter = TCButtonType.wiiInfraredRecenter.rawValue
    let capturedPort = self.port

    // Hold the recenter button for a few emulated frames so it's guaranteed to be sampled,
    // then release it.
    TCManagerInterface.setButtonStateFor(recenter, controller: capturedPort, state: true)
    self.operationQueue.addOperation {
      Thread.sleep(forTimeInterval: 0.1)
      TCManagerInterface.setButtonStateFor(recenter, controller: capturedPort, state: false)
    }
  }

  // Whether a flat calibration has ever been captured this session.
  @objc func hasGyroCalibration() -> Bool {
    return self.gyroBiasX != 0.0 || self.gyroBiasY != 0.0 || self.gyroBiasZ != 0.0
  }

  // Clear the captured bias (revert to raw gyro).
  @objc func resetGyroCalibration() {
    self.gyroBiasX = 0.0
    self.gyroBiasY = 0.0
    self.gyroBiasZ = 0.0
  }

  // UIApplicationDidChangeStatusBarOrientationNotification is deprecated...
  @objc func statusBarOrientationChanged() {
    self.orientation = UIApplication.shared.statusBarOrientation
  }
}
