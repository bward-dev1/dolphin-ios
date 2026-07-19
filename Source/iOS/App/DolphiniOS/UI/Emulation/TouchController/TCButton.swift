// Copyright 2022 DolphiniOS Project
// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation
import UIKit

class TCButton: UIButton
{
  let hapticGenerator = UIImpactFeedbackGenerator(style: .medium)
    
  @IBInspectable var controllerButton: Int = 0 // default: GC A button
  {
    didSet
    {
      updateImage()
    }
  }
  
  @IBInspectable var isAxis: Bool = false
  
  var port: Int = 0
  var useHapicTouch: Bool = true
  var lastForce: CGFloat = CGFloat.zero
  
  override init(frame: CGRect)
  {
    super.init(frame: frame)
    sharedInit()
  }
  
  required init?(coder: NSCoder)
  {
    super.init(coder: coder)
    sharedInit()
  }
  
  func sharedInit()
  {
    self.setTitle("", for: .normal)
    self.addTarget(self, action: #selector(buttonPressed), for: .touchDown)
    self.addTarget(self, action: #selector(buttonReleased), for: .touchUpInside)

    // TODO: Setting for hapic touch analog triggers enabled
    self.useHapicTouch = self.traitCollection.forceTouchCapability == .available

    NotificationCenter.default.addObserver(self, selector: #selector(updateImage),
                                            name: TCSkinManager.skinChangedNotification, object: nil)
  }

  @objc func updateImage()
  {
    // updateImage() fires on every live TCButton whenever any skin changes
    // (skinChangedNotification is broadcast, not targeted), including buttons
    // mid-teardown or in states this class doesn't fully control -- a bad
    // controllerButton value here used to crash the whole app instead of
    // just leaving this one button's image unset.
    guard let buttonType = TCButtonType(rawValue: controllerButton) else
    {
      NSLog("TCButton: updateImage() called with unrecognized controllerButton %d, skipping", controllerButton)
      return
    }

    let buttonImage = getImage(named: buttonType.getImageName(), scale: buttonType.getButtonScale())
    self.setImage(buttonImage, for: .normal)

    let buttonPressedImage = getImage(named: buttonType.getImageName() + "_pressed", scale: buttonType.getButtonScale())
    self.setImage(buttonPressedImage, for: .selected)
  }

  func getImage(named: String, scale: CGFloat) -> UIImage
  {
    // In Interface Builder, the default bundle is not Dolphin's, so we must specify
    // the bundle for the image to load correctly. A missing bundle asset should
    // never happen for a real button name, but this is reachable from a custom
    // skin's notification firing on every button, so fail soft with a blank
    // placeholder instead of crashing the whole app over one missing image.
    guard let defaultImage = UIImage(named: named, in: Bundle(for: type(of: self)), compatibleWith: nil) else
    {
      NSLog("TCButton: missing bundled image \"%@\", using blank placeholder", named)
      return UIImage()
    }

    // A custom controller skin can override this specific image; falls back to the
    // bundled default if the active skin doesn't provide it.
    let image = TCSkinManager.shared.image(named: named, defaultImage: defaultImage) ?? defaultImage

    // Create a new CGSize with the new scale
    let newSize = CGSize(width: defaultImage.size.width * scale, height: defaultImage.size.height * scale)

    // Render the image into a context
    UIGraphicsBeginImageContext(newSize)
    image.draw(in: CGRect(origin: CGPoint.zero, size: newSize))
    let newImage = UIGraphicsGetImageFromCurrentImageContext() ?? image
    UIGraphicsEndImageContext()

    return newImage.withRenderingMode(.alwaysOriginal)
  }

  deinit
  {
    NotificationCenter.default.removeObserver(self)
  }

  @objc func buttonPressed()
  {
    if (isAxis && useHapicTouch)
    {
      return
    }
    
    hapticGenerator.impactOccurred()
    
    if (isAxis)
    {
      TCManagerInterface.setAxisValueFor(controllerButton, controller: port, value: 1.0)
    }
    else
    {
      TCManagerInterface.setButtonStateFor(controllerButton, controller: port, state: true)
    }
  }
  
  @objc func buttonReleased()
  {
    if (isAxis)
    {
      TCManagerInterface.setAxisValueFor(controllerButton, controller: port, value: 0.0)
    }
    else
    {
      TCManagerInterface.setButtonStateFor(controllerButton, controller: port, state: false)
    }
  }
  
  @objc override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?)
  {
    if (!isAxis || !useHapicTouch)
    {
      return
    }
    
    let touch = touches.first!
    let force = touch.force
    let maxForce = touch.maximumPossibleForce
    let percentage: Float = Float(force / maxForce);
    
    TCManagerInterface.setAxisValueFor(controllerButton, controller: port, value: percentage)
    
    if (self.lastForce != force && force == maxForce)
    {
      hapticGenerator.impactOccurred()
    }
    
    self.lastForce = force;
  }
  
}
