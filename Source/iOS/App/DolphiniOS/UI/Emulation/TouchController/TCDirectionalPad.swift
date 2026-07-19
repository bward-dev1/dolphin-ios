// Copyright 2022 DolphiniOS Project
// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation
import UIKit

class TCDirectionalPad: UIView
{
  let hapticGenerator = UIImpactFeedbackGenerator(style: .medium)

  var dpadNoPressed: UIImage? = nil
  var dpadOnePressed: UIImage? = nil
  var dpadTwoPressed: UIImage? = nil

  // Kept so updateImages() (fired on skin change) can refresh what's currently on screen -
  // previously a local var in sharedInit(), so a skin change while this pad was visible had
  // no way to reach it.
  private var imageView: UIImageView? = nil

  @IBInspectable var directionalPadType: Int = 6 // default: GC D-Pad

  var port: Int = 0
  var isPressed: Bool = false

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
    updateImages()

    // Create the image view
    let imageView = UIImageView(frame: CGRect(x: 0, y: 0, width: self.frame.width, height: self.frame.height))
    imageView.image = dpadNoPressed
    imageView.center = self.convert(self.center, from: self.superview)
    imageView.isUserInteractionEnabled = true
    self.imageView = imageView

    let pressHandler = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress))
    pressHandler.minimumPressDuration = 0
    imageView.addGestureRecognizer(pressHandler)

    self.addSubview(imageView)

    // Set background color to transparent
    self.backgroundColor = UIColor.clear

    NotificationCenter.default.addObserver(self, selector: #selector(updateImages),
                                            name: TCSkinManager.skinChangedNotification, object: nil)
  }

  @objc func updateImages()
  {
    dpadNoPressed = getImage(imageName: "gcwii_dpad")
    dpadOnePressed = getImage(imageName: "gcwii_dpad_pressed_one_direction")
    dpadTwoPressed = getImage(imageName: "gcwii_dpad_pressed_two_directions")

    // Only reset to the resting image - if a direction is actively held when the skin
    // changes, the next touch move/release will naturally pick the right pressed image.
    if !isPressed
    {
      imageView?.image = dpadNoPressed
    }
  }

  func getImage(imageName: String) -> UIImage
  {
    // In Interface Builder, the default bundle is not Dolphin's, so we must specify
    // the bundle for the image to load correctly. Fail soft rather than crash the
    // whole app over one missing bundle asset.
    guard let defaultImage = UIImage(named: imageName, in: Bundle(for: type(of: self)), compatibleWith: nil) else
    {
      NSLog("TCDirectionalPad: missing bundled image \"%@\", using blank placeholder", imageName)
      return UIImage()
    }

    // A custom controller skin can override this specific image; falls back to the
    // bundled default if the active skin doesn't provide it. TCButton has used this same
    // TCSkinManager path for years - the d-pad and joystick (see TCJoystick) never did,
    // so every existing skin's dpad/joystick art has silently gone unused until now.
    return TCSkinManager.shared.image(named: imageName, defaultImage: defaultImage) ?? defaultImage
  }

  @objc func handleLongPress(gesture: UILongPressGestureRecognizer)
  {
    let imageView = gesture.view as! UIImageView
    let point = gesture.location(in: self)
    var buttonPresses: [Bool] = [ false, false, false, false ]
    
    if (gesture.state == .ended)
    {
      imageView.image = dpadNoPressed
      self.isPressed = false
    }
    else
    {
      if (!self.isPressed)
      {
        hapticGenerator.impactOccurred()
        self.isPressed = true
      }
      
      // Get button boundary
      let buttonBounds = gesture.view!.frame.width / 3
      
      // Up
      if (point.y <= buttonBounds)
      {
        buttonPresses[0] = true;
      }
      else if (point.y >= buttonBounds * 2) // Down
      {
        buttonPresses[1] = true;
      }
      
      // Left
      if (point.x <= buttonBounds)
      {
        buttonPresses[2] = true;
      }
      else if (point.x >= buttonBounds * 2) // Right
      {
        buttonPresses[3] = true;
      }
      
      var rotation: CGFloat = 0
      
      // TODO: is there a better way to structure this?
      // Left and Up
      if (buttonPresses[2] && buttonPresses[0])
      {
        imageView.image = dpadTwoPressed
        rotation = 0
      }
      else if (buttonPresses[0] && buttonPresses[3]) // Up and Right
      {
        imageView.image = dpadTwoPressed
        rotation = 90
      }
      else if (buttonPresses[3] && buttonPresses[1]) // Right and Down
      {
        imageView.image = dpadTwoPressed
        rotation = 180
      }
      else if (buttonPresses[1] && buttonPresses[2]) // Down and Left
      {
        imageView.image = dpadTwoPressed
        rotation = 270
      }
      else if (buttonPresses[0]) // Up
      {
        imageView.image = dpadOnePressed
        rotation = 0
      }
      else if (buttonPresses[1]) // Down
      {
        imageView.image = dpadOnePressed
        rotation = 180
      }
      else if (buttonPresses[2]) // Left
      {
        imageView.image = dpadOnePressed
        rotation = 270
      }
      else if (buttonPresses[3]) // Right
      {
        imageView.image = dpadOnePressed
        rotation = 90
      }
      else
      {
        imageView.image = dpadNoPressed
      }
      
      let radians = rotation * (CGFloat.pi / 180)
      imageView.transform = CGAffineTransform.identity.rotated(by: radians)
    }
    
    // Send button values
    for (i, press) in buttonPresses.enumerated()
    {
      TCManagerInterface.setButtonStateFor(directionalPadType + i, controller: port, state: press)
    }
  }
  
}
