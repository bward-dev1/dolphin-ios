// Copyright 2026 DolphiniOS Project
// SPDX-License-Identifier: GPL-2.0-or-later

import UIKit

// Pointer setup for Wii titles: one question, plus the real gyro-bias calibration (which doesn't
// need the emulation core running, so it's safe to do here in the pre-boot gate chain alongside
// JitWaitViewController/NKitWarningViewController).
//
// This screen used to appear before *every* boot -- including GameCube titles, which have no Wii
// pointer at all -- and asked six questions: how you hold the device, which way it faces when laid
// flat, what you're calibrating the pointer to, whether you're playing on a TV, your TV's screen
// size, and your TV's screen type. Five of those six answers were read by nothing anywhere in the
// codebase, and three of them were about a television that most sessions don't involve. What's
// left is the single answer that has an effect (see PointerCalibrationMode), pre-selected from
// whether an external display is actually attached, remembered per display setup, and asked once
// rather than every time.
//
// EmulationViewController now only puts this in front of a boot for a Wii title whose current
// display setup hasn't been answered yet. It is otherwise reachable on demand from the in-game
// menu (Controllers -> Motion -> Pointer Setup), which is where recalibration belongs.
class PreGameCalibrationViewController: UIViewController {
  @objc weak var delegate: PreGameCalibrationViewControllerDelegate?

  // False: this is the one-time gate in front of a boot, and finishing it starts the game.
  // True: the player opened it mid-game from the Motion menu to change their answer, so it gets a
  // Cancel button and is dismissible.
  @objc(presentedForRecalibration) var presentedForRecalibration: Bool = false

  private let scrollView = UIScrollView()
  private let stackView = UIStackView()

  private let calibrationModeControl = UISegmentedControl(items: [
    DOLCoreLocalizedString("Point at TV"),
    DOLCoreLocalizedString("Point at device")
  ])

  private let detectedDisplayLabel = UILabel()

  private let continueButton = UIButton(type: .system)
  private let cancelButton = UIButton(type: .system)
  private let activityIndicator = UIActivityIndicatorView(style: .medium)

  override func viewDidLoad() {
    super.viewDidLoad()

    self.view.backgroundColor = .systemBackground
    self.isModalInPresentation = !self.presentedForRecalibration

    self.buildLayout()
    self.applyDefaults()

    self.continueButton.addTarget(self, action: #selector(continuePressed), for: .touchUpInside)
    self.cancelButton.addTarget(self, action: #selector(cancelPressed), for: .touchUpInside)
  }

  // PreGameCalibrationPreferences answers with the player's own persisted choice for the display
  // setup they're in, or -- the first time in that setup -- with a value derived from whether a TV
  // or AirPlay display is actually attached. Nothing here hardcodes "you have a TV" any more.
  private func applyDefaults() {
    self.calibrationModeControl.selectedSegmentIndex =
      PreGameCalibrationPreferences.shared.calibrationMode.rawValue

    self.detectedDisplayLabel.text = PreGameCalibrationPreferences.isExternalDisplayAttached
      ? DOLCoreLocalizedString("An external display is connected, so this is set to point at it.")
      : DOLCoreLocalizedString("No TV or external display is connected, so this is set for handheld play.")
  }

  private func buildLayout() {
    self.scrollView.translatesAutoresizingMaskIntoConstraints = false
    self.view.addSubview(self.scrollView)

    self.stackView.translatesAutoresizingMaskIntoConstraints = false
    self.stackView.axis = .vertical
    self.stackView.spacing = 20
    self.stackView.isLayoutMarginsRelativeArrangement = true
    self.stackView.layoutMargins = UIEdgeInsets(top: 24, left: 20, bottom: 24, right: 20)
    self.scrollView.addSubview(self.stackView)

    NSLayoutConstraint.activate([
      self.scrollView.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor),
      self.scrollView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
      self.scrollView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
      self.scrollView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),

      self.stackView.topAnchor.constraint(equalTo: self.scrollView.topAnchor),
      self.stackView.leadingAnchor.constraint(equalTo: self.scrollView.leadingAnchor),
      self.stackView.trailingAnchor.constraint(equalTo: self.scrollView.trailingAnchor),
      self.stackView.bottomAnchor.constraint(equalTo: self.scrollView.bottomAnchor),
      self.stackView.widthAnchor.constraint(equalTo: self.scrollView.widthAnchor)
    ])

    let titleLabel = UILabel()
    titleLabel.text = DOLCoreLocalizedString("Pointer Setup")
    titleLabel.font = .preferredFont(forTextStyle: .largeTitle)
    titleLabel.adjustsFontForContentSizeCategory = true
    titleLabel.numberOfLines = 0

    let subtitleLabel = UILabel()
    // Not "before every Wii game" any more: EmulationViewController skips this gate entirely for
    // GameCube titles, and for Wii titles only shows it until the current display setup has been
    // answered once.
    subtitleLabel.text = self.presentedForRecalibration
      ? DOLCoreLocalizedString("Change how the Wii Remote pointer is aimed, then recalibrate.")
      : DOLCoreLocalizedString("One question, asked once, so the Wii Remote pointer aims correctly. You won't see this again unless you plug in a TV or open it from the in-game menu.")
    subtitleLabel.font = .preferredFont(forTextStyle: .subheadline)
    subtitleLabel.adjustsFontForContentSizeCategory = true
    subtitleLabel.textColor = .secondaryLabel
    subtitleLabel.numberOfLines = 0

    self.detectedDisplayLabel.font = .preferredFont(forTextStyle: .footnote)
    self.detectedDisplayLabel.adjustsFontForContentSizeCategory = true
    self.detectedDisplayLabel.textColor = .secondaryLabel
    self.detectedDisplayLabel.numberOfLines = 0

    self.stackView.addArrangedSubview(titleLabel)
    self.stackView.addArrangedSubview(subtitleLabel)
    self.stackView.addArrangedSubview(self.detectedDisplayLabel)

    self.stackView.addArrangedSubview(self.buildSection(
      title: DOLCoreLocalizedString("What are you aiming the pointer at?"),
      description: DOLCoreLocalizedString("Point at TV centers the pointer on wherever the device is aimed when the game starts -- pick this if you're pointing across the room at a TV or external screen. Point at device leaves the pointer alone so your touch controls keep working, which is what you want playing handheld."),
      control: self.calibrationModeControl
    ))

    self.continueButton.setTitle(self.presentedForRecalibration
      ? DOLCoreLocalizedString("Save & Calibrate")
      : DOLCoreLocalizedString("Start Game"), for: .normal)
    self.continueButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
    self.continueButton.titleLabel?.adjustsFontForContentSizeCategory = true
    self.continueButton.backgroundColor = .systemBlue
    self.continueButton.setTitleColor(.white, for: .normal)
    self.continueButton.layer.cornerRadius = 12
    self.continueButton.translatesAutoresizingMaskIntoConstraints = false
    self.continueButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 50).isActive = true

    self.activityIndicator.hidesWhenStopped = true
    self.activityIndicator.translatesAutoresizingMaskIntoConstraints = false

    let buttonContainer = UIView()
    buttonContainer.addSubview(self.continueButton)
    buttonContainer.addSubview(self.activityIndicator)

    NSLayoutConstraint.activate([
      self.continueButton.leadingAnchor.constraint(equalTo: buttonContainer.leadingAnchor),
      self.continueButton.trailingAnchor.constraint(equalTo: buttonContainer.trailingAnchor),
      self.continueButton.topAnchor.constraint(equalTo: buttonContainer.topAnchor),
      self.continueButton.bottomAnchor.constraint(equalTo: buttonContainer.bottomAnchor),
      self.activityIndicator.centerXAnchor.constraint(equalTo: self.continueButton.trailingAnchor, constant: -30),
      self.activityIndicator.centerYAnchor.constraint(equalTo: self.continueButton.centerYAnchor)
    ])

    self.stackView.addArrangedSubview(buttonContainer)

    // The gyro-bias reading below takes about half a second of stillness. Nothing ever said so
    // before, which made it possible to capture a "resting" bias mid-pickup and bake the resulting
    // drift into the whole session.
    let calibrationHintLabel = UILabel()
    calibrationHintLabel.text = DOLCoreLocalizedString("Hold the device still for a moment after tapping -- it takes a quick gyroscope reading to stop the pointer drifting.")
    calibrationHintLabel.font = .preferredFont(forTextStyle: .footnote)
    calibrationHintLabel.adjustsFontForContentSizeCategory = true
    calibrationHintLabel.textColor = .secondaryLabel
    calibrationHintLabel.textAlignment = .center
    calibrationHintLabel.numberOfLines = 0

    self.stackView.addArrangedSubview(calibrationHintLabel)

    if self.presentedForRecalibration {
      self.cancelButton.setTitle(DOLCoreLocalizedString("Cancel"), for: .normal)
      self.cancelButton.titleLabel?.font = .preferredFont(forTextStyle: .body)
      self.cancelButton.titleLabel?.adjustsFontForContentSizeCategory = true

      self.stackView.addArrangedSubview(self.cancelButton)
    }
  }

  private func buildSection(title: String, description: String, control: UISegmentedControl) -> UIView {
    let container = UIStackView()
    container.axis = .vertical
    container.spacing = 8

    let titleLabel = UILabel()
    titleLabel.text = title
    titleLabel.font = .preferredFont(forTextStyle: .headline)
    titleLabel.adjustsFontForContentSizeCategory = true
    titleLabel.numberOfLines = 0

    let descriptionLabel = UILabel()
    descriptionLabel.text = description
    descriptionLabel.font = .preferredFont(forTextStyle: .footnote)
    descriptionLabel.adjustsFontForContentSizeCategory = true
    descriptionLabel.textColor = .secondaryLabel
    descriptionLabel.numberOfLines = 0

    container.addArrangedSubview(titleLabel)
    container.addArrangedSubview(descriptionLabel)
    container.addArrangedSubview(control)

    return container
  }

  @objc private func cancelPressed() {
    self.dismiss(animated: true, completion: nil)
  }

  @objc private func continuePressed() {
    let prefs = PreGameCalibrationPreferences.shared

    // Falls back to .pointAtDevice rather than .pointAtTV: selectedSegmentIndex is -1 when no
    // segment is selected, and .pointAtTV is the one answer that switches Touch IR Pointer off,
    // so an out-of-range read must not be able to land on it.
    prefs.calibrationMode =
      PointerCalibrationMode(rawValue: self.calibrationModeControl.selectedSegmentIndex) ?? .pointAtDevice

    // Has to come after the write: until this is set, the getter above deliberately ignores the
    // stored value and reports the display-derived default instead.
    prefs.markAnsweredForCurrentDisplay()

    self.continueButton.isEnabled = false
    self.cancelButton.isEnabled = false
    self.activityIndicator.startAnimating()

    // Calibrating flat gyro bias doesn't need the emulation core running -- it only touches
    // CoreMotion and TCDeviceMotion's own state, so it's safe and useful to do here, before the
    // game even boots. Aim-at-TV recentering needs the pointer to actually be live, so it happens
    // post-boot in EmulationiOSViewController when calibrationMode == .pointAtTV.
    TCDeviceMotion.shared.calibrateFlat { [weak self] in
      guard let self = self else {
        return
      }

      self.activityIndicator.stopAnimating()
      self.delegate?.didFinishPreGameCalibrationScreen(sender: self)
    }
  }
}
