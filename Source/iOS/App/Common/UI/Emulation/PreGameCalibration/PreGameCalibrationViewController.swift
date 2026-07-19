// Copyright 2026 DolphiniOS Project
// SPDX-License-Identifier: GPL-2.0-or-later

import UIKit

// Shown before every single game boot, unconditionally. Collects pointer-aiming context (how
// the device is held, which way it faces the TV/device when laid flat, and whether play is
// happening on a TV vs. handheld) and runs a real gyro-bias calibration on the spot -- this part
// doesn't need the emulation core running, so it's safe to do here in the pre-boot gate chain
// alongside JitWaitViewController/NKitWarningViewController.
class PreGameCalibrationViewController: UIViewController {
  @objc weak var delegate: PreGameCalibrationViewControllerDelegate?

  private let scrollView = UIScrollView()
  private let stackView = UIStackView()

  private let holdOrientationControl = UISegmentedControl(items: [
    DOLCoreLocalizedString("Upright"),
    DOLCoreLocalizedString("Landscape"),
    DOLCoreLocalizedString("Portrait")
  ])

  private let flatFacingControl = UISegmentedControl(items: [
    DOLCoreLocalizedString("Screen Up"),
    DOLCoreLocalizedString("Screen Down")
  ])

  private let calibrationModeControl = UISegmentedControl(items: [
    DOLCoreLocalizedString("Point at TV"),
    DOLCoreLocalizedString("Point at Device")
  ])

  private let playingOnTVSwitch = UISwitch()

  private let tvSizeControl = UISegmentedControl(items: [
    DOLCoreLocalizedString("Widescreen"),
    DOLCoreLocalizedString("Standard")
  ])

  private let tvTypeControl = UISegmentedControl(items: [
    DOLCoreLocalizedString("LCD/LED"),
    DOLCoreLocalizedString("OLED"),
    DOLCoreLocalizedString("Projector"),
    DOLCoreLocalizedString("CRT/Older")
  ])

  private let tvOptionsStack = UIStackView()

  private let continueButton = UIButton(type: .system)
  private let activityIndicator = UIActivityIndicatorView(style: .medium)

  override func viewDidLoad() {
    super.viewDidLoad()

    self.view.backgroundColor = .systemBackground
    self.isModalInPresentation = true

    self.buildLayout()
    self.applyDefaults()

    self.playingOnTVSwitch.addTarget(self, action: #selector(playingOnTVChanged), for: .valueChanged)
    self.continueButton.addTarget(self, action: #selector(continuePressed), for: .touchUpInside)

    self.updateTVOptionsVisibility()
  }

  private func applyDefaults() {
    let prefs = PreGameCalibrationPreferences.shared

    self.holdOrientationControl.selectedSegmentIndex = prefs.holdOrientation.rawValue
    self.flatFacingControl.selectedSegmentIndex = prefs.flatFacing.rawValue
    self.calibrationModeControl.selectedSegmentIndex = prefs.calibrationMode.rawValue
    self.playingOnTVSwitch.isOn = prefs.isPlayingOnTV
    self.tvSizeControl.selectedSegmentIndex = prefs.tvScreenSize.rawValue
    self.tvTypeControl.selectedSegmentIndex = prefs.tvScreenType.rawValue
  }

  private func buildLayout() {
    self.scrollView.translatesAutoresizingMaskIntoConstraints = false
    self.view.addSubview(self.scrollView)

    self.stackView.translatesAutoresizingMaskIntoConstraints = false
    self.stackView.axis = .vertical
    self.stackView.spacing = 24
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
    titleLabel.numberOfLines = 0

    let subtitleLabel = UILabel()
    subtitleLabel.text = DOLCoreLocalizedString("Quickly confirm how you're holding your device so the Wii Remote pointer tracks correctly. This appears before every game.")
    subtitleLabel.font = .preferredFont(forTextStyle: .subheadline)
    subtitleLabel.textColor = .secondaryLabel
    subtitleLabel.numberOfLines = 0

    self.stackView.addArrangedSubview(titleLabel)
    self.stackView.addArrangedSubview(subtitleLabel)

    self.stackView.addArrangedSubview(self.buildSection(
      title: DOLCoreLocalizedString("How are you holding your device?"),
      control: self.holdOrientationControl
    ))

    self.stackView.addArrangedSubview(self.buildSection(
      title: DOLCoreLocalizedString("When laid flat, which way does the front face?"),
      control: self.flatFacingControl
    ))

    self.stackView.addArrangedSubview(self.buildSection(
      title: DOLCoreLocalizedString("Calibration mode"),
      control: self.calibrationModeControl
    ))

    let tvToggleRow = UIStackView()
    tvToggleRow.axis = .horizontal
    tvToggleRow.spacing = 12

    let tvToggleLabel = UILabel()
    tvToggleLabel.text = DOLCoreLocalizedString("Playing on a TV?")
    tvToggleLabel.font = .preferredFont(forTextStyle: .headline)

    tvToggleRow.addArrangedSubview(tvToggleLabel)
    tvToggleRow.addArrangedSubview(self.playingOnTVSwitch)

    self.stackView.addArrangedSubview(tvToggleRow)

    self.tvOptionsStack.axis = .vertical
    self.tvOptionsStack.spacing = 24

    self.tvOptionsStack.addArrangedSubview(self.buildSection(
      title: DOLCoreLocalizedString("Screen size"),
      control: self.tvSizeControl
    ))

    self.tvOptionsStack.addArrangedSubview(self.buildSection(
      title: DOLCoreLocalizedString("Screen type"),
      control: self.tvTypeControl
    ))

    self.stackView.addArrangedSubview(self.tvOptionsStack)

    self.continueButton.setTitle(DOLCoreLocalizedString("Calibrate & Continue"), for: .normal)
    self.continueButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
    self.continueButton.backgroundColor = .systemBlue
    self.continueButton.setTitleColor(.white, for: .normal)
    self.continueButton.layer.cornerRadius = 12
    self.continueButton.translatesAutoresizingMaskIntoConstraints = false
    self.continueButton.heightAnchor.constraint(equalToConstant: 50).isActive = true

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
  }

  private func buildSection(title: String, control: UISegmentedControl) -> UIView {
    let container = UIStackView()
    container.axis = .vertical
    container.spacing = 8

    let label = UILabel()
    label.text = title
    label.font = .preferredFont(forTextStyle: .headline)
    label.numberOfLines = 0

    container.addArrangedSubview(label)
    container.addArrangedSubview(control)

    return container
  }

  @objc private func playingOnTVChanged() {
    self.updateTVOptionsVisibility()
  }

  private func updateTVOptionsVisibility() {
    self.tvOptionsStack.isHidden = !self.playingOnTVSwitch.isOn
  }

  @objc private func continuePressed() {
    let prefs = PreGameCalibrationPreferences.shared

    prefs.holdOrientation = DeviceHoldOrientation(rawValue: self.holdOrientationControl.selectedSegmentIndex) ?? .upright
    prefs.flatFacing = DeviceFlatFacing(rawValue: self.flatFacingControl.selectedSegmentIndex) ?? .screenUp
    prefs.calibrationMode = PointerCalibrationMode(rawValue: self.calibrationModeControl.selectedSegmentIndex) ?? .pointAtTV
    prefs.isPlayingOnTV = self.playingOnTVSwitch.isOn
    prefs.tvScreenSize = TVScreenSize(rawValue: self.tvSizeControl.selectedSegmentIndex) ?? .widescreen
    prefs.tvScreenType = TVScreenType(rawValue: self.tvTypeControl.selectedSegmentIndex) ?? .lcdOrLed

    self.continueButton.isEnabled = false
    self.activityIndicator.startAnimating()

    // Calibrating flat gyro bias doesn't need the emulation core running -- it only touches
    // CoreMotion and TCDeviceMotion's own state, so it's safe and useful to do it right here,
    // before the game even boots. TV-aim recentering happens once the pointer is actually live
    // in-game (EmulationiOSViewController auto-fires it post-boot when calibrationMode == .pointAtTV).
    TCDeviceMotion.shared.calibrateFlat { [weak self] in
      guard let self = self else {
        return
      }

      self.activityIndicator.stopAnimating()
      self.delegate?.didFinishPreGameCalibrationScreen(sender: self)
    }
  }
}
