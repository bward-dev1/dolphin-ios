// Copyright 2022 DolphiniOS Project
// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation
import UIKit

class TCJoystick: UIView
{
  @IBInspectable var joystickType: Int = 10 // default: GC stick
  var port: Int = 0

  // Kept so updateImages() (fired on skin change) can refresh what's on screen.
  private var rangeImageView: UIImageView? = nil
  private var handleImageView: UIImageView? = nil
  private var handleImageName: String? = nil

  override init(frame: CGRect)
  {
    super.init(frame: frame)
  }

  required init?(coder: NSCoder)
  {
    super.init(coder: coder)
  }

  deinit
  {
    NotificationCenter.default.removeObserver(self)
  }

  override func awakeFromNib()
  {
    super.awakeFromNib()
    sharedInit()
  }

  func sharedInit()
  {
    // Create the range
    let rangeImage = createImageView(imageName: "gcwii_joystick_range")
    self.rangeImageView = rangeImage
    self.addSubview(rangeImage)

    // Create handle
    guard let buttonType = TCButtonType(rawValue: joystickType) else
    {
      NSLog("TCJoystick: unrecognized joystickType %d, skipping handle image", joystickType)
      return
    }

    self.handleImageName = buttonType.getImageName()

    let handleView = createImageView(imageName: buttonType.getImageName())
    self.handleImageView = handleView
    let panHandler = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
    handleView.isUserInteractionEnabled = true
    handleView.addGestureRecognizer(panHandler)
    self.addSubview(handleView)

    // Set background color to transparent
    self.backgroundColor = UIColor.clear

    NotificationCenter.default.addObserver(self, selector: #selector(updateImages),
                                            name: TCSkinManager.skinChangedNotification, object: nil)
  }

  @objc func updateImages()
  {
    rangeImageView?.image = loadImage(imageName: "gcwii_joystick_range")

    if let handleImageName
    {
      handleImageView?.image = loadImage(imageName: handleImageName)
    }
  }

  func createImageView(imageName: String) -> UIImageView
  {
    // Create the view
    let imageView = UIImageView(frame: CGRect(x: 0, y: 0, width: self.frame.width - (self.frame.width / 3), height: self.frame.height - (self.frame.height / 3)))
    imageView.image = loadImage(imageName: imageName)
    imageView.center = self.convert(self.center, from: self.superview)

    return imageView
  }

  func loadImage(imageName: String) -> UIImage?
  {
    // In Interface Builder, the default bundle is not Dolphin's, so we must specify
    // the bundle for the image to load correctly
    guard let defaultImage = UIImage(named: imageName, in: Bundle(for: type(of: self)), compatibleWith: nil) else
    {
      return nil
    }

    // A custom controller skin can override this specific image; falls back to the
    // bundled default if the active skin doesn't provide it. TCButton has used this same
    // TCSkinManager path for years - the joystick and d-pad (see TCDirectionalPad) never
    // did, so every existing skin's joystick/dpad art has silently gone unused until now.
    return TCSkinManager.shared.image(named: imageName, defaultImage: defaultImage) ?? defaultImage
  }

  @objc func handlePan(gesture: UIPanGestureRecognizer)
  {
    var point: CGPoint
    var joyAxises: [CGFloat] = [ 0, 0, 0, 0 ]
    
    if (gesture.state == .ended)
    {
      // Reset to center
      point = self.convert(self.center, from: self.superview)
    }
    else
    {
      // Get points
      point = gesture.location(in: self)
      let joystickCenter = self.convert(self.center, from: self.superview)
      
      // Calculate differences
      let xDiff = point.x - joystickCenter.x
      let yDiff = point.y - joystickCenter.y
      
      // Calculate distance
      var distance = sqrt(pow(xDiff, 2) + pow(yDiff, 2))
      let maxDistance = self.frame.width / 3

      if (distance > maxDistance)
      {
        // Calculate maximum points
        let xMax = joystickCenter.x + maxDistance * (xDiff / distance)
        let yMax = joystickCenter.y + maxDistance * (yDiff / distance)

        point = CGPoint(x: xMax, y: yMax)
      }

      // Calculate axis values for ButtonManager
      // Based on Android's getAxisValues()
      let axises = (y: yDiff / maxDistance, x: xDiff / maxDistance)
      joyAxises = [min(axises.y, 0), min(axises.y, 1), min(axises.x, 0), min(axises.x, 1)]
    }
    
    // Send axises values
    let axisStartIdx = joystickType
    for (i, axis) in joyAxises.enumerated()
    {
      TCManagerInterface.setAxisValueFor(axisStartIdx + i + 1, controller: port, value: Float(axis))
    }
    
    gesture.view?.center = point
  }
  
}
