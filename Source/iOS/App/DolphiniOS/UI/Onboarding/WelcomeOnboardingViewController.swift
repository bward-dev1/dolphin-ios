// Copyright 2026 DolphiniOS Project
// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation
import UIKit

// Set on first launch by FirstRunInitializationService, cleared once the user actually finishes
// the screen. Deliberately not keyed off "launch_times == 0": that counter is bumped before this
// screen is ever shown, so a crash or force quit mid-flow used to eat the app's only onboarding
// forever. Keep in sync with FirstRunInitializationService.mm.
private let kWelcomeOnboardingPendingKey = "welcome_onboarding_pending"

private enum Metrics {
  static let horizontalInset: CGFloat = 24
  static let iconBaseWidth: CGFloat = 32
  static let iconTextStyle: UIFont.TextStyle = .title2
}

// The one and only screen a brand-new user has to get through before the game library.
//
// It used to be two: this welcome screen *and* the separate unofficial-build notice, both pushed
// onto BootNoticeManager's queue on first launch. Worse, they appeared in the wrong order (a
// UINavigationController shows the last controller pushed), so "Get Started" took you to a legal
// disclaimer instead of the app. The notice is now a footnote at the bottom of this screen, so
// first launch costs one screen and one tap.
//
// BootNoticeManager presents this in a form sheet with modalInPresentation = true, so the button
// is the only way out. That is why everything scrolls and the button is pinned *outside* the
// scroll view: on a small phone in landscape, or at an accessibility text size, a centred
// non-scrolling layout pushes the only exit off-screen and soft-locks the app.
@objc class WelcomeOnboardingViewController: UIViewController {
  private struct Tip {
    let symbolName: String
    let title: String
    let body: String
  }

  private let tips: [Tip] = [
    Tip(symbolName: "plus.circle",
        title: "Add Your Games",
        body: "Tap + in the Games tab to import game files from Files or iCloud Drive."),
    Tip(symbolName: "gamecontroller",
        title: "Play",
        body: "On-screen controls appear automatically. Bluetooth controllers work too."),
    Tip(symbolName: "gearshape",
        title: "Settings",
        body: "Graphics, controllers, Help, and Optimize My Settings, which picks good defaults "
            + "for this device."),
  ]

  private var tipRows: [UIStackView] = []
  private var iconWidthConstraints: [NSLayoutConstraint] = []

  override func viewDidLoad() {
    super.viewDidLoad()

    view.backgroundColor = .systemBackground

    let titleLabel = UILabel()
    titleLabel.text = "Welcome to DolphiniOS"
    // Bold largeTitle that still tracks Dynamic Type. Building the font from a descriptor alone
    // would freeze it at the size in effect when the view loaded.
    titleLabel.font = UIFontMetrics(forTextStyle: .largeTitle)
        .scaledFont(for: .systemFont(ofSize: 34, weight: .bold))
    titleLabel.adjustsFontForContentSizeCategory = true
    titleLabel.numberOfLines = 0
    titleLabel.accessibilityTraits = .header

    let subtitleLabel = UILabel()
    subtitleLabel.text = "Three things, then you're in."
    subtitleLabel.font = .preferredFont(forTextStyle: .body)
    subtitleLabel.adjustsFontForContentSizeCategory = true
    subtitleLabel.textColor = .secondaryLabel
    subtitleLabel.numberOfLines = 0

    let headerStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
    headerStack.axis = .vertical
    headerStack.spacing = 4

    tipRows = tips.map { makeRow(for: $0) }

    let tipsStack = UIStackView(arrangedSubviews: tipRows)
    tipsStack.axis = .vertical
    tipsStack.spacing = 20

    let contentStack = UIStackView(arrangedSubviews: [headerStack, tipsStack, makeUnofficialBuildNotice()])
    contentStack.axis = .vertical
    contentStack.spacing = 28
    contentStack.setCustomSpacing(32, after: headerStack)
    contentStack.translatesAutoresizingMaskIntoConstraints = false

    let scrollView = UIScrollView()
    scrollView.translatesAutoresizingMaskIntoConstraints = false
    scrollView.alwaysBounceVertical = false
    // The scroll view is already pinned to the safe area; letting UIKit add its own adjustment on
    // top of that would double-inset the content.
    scrollView.contentInsetAdjustmentBehavior = .never
    scrollView.addSubview(contentStack)
    view.addSubview(scrollView)

    let getStartedButton = makeGetStartedButton()
    view.addSubview(getStartedButton)

    let safeArea = view.safeAreaLayoutGuide
    let frameGuide = scrollView.frameLayoutGuide
    let contentGuide = scrollView.contentLayoutGuide

    NSLayoutConstraint.activate([
      scrollView.topAnchor.constraint(equalTo: safeArea.topAnchor),
      scrollView.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor),
      scrollView.bottomAnchor.constraint(equalTo: getStartedButton.topAnchor, constant: -16),

      contentStack.topAnchor.constraint(equalTo: contentGuide.topAnchor, constant: 32),
      contentStack.bottomAnchor.constraint(equalTo: contentGuide.bottomAnchor, constant: -24),
      contentStack.leadingAnchor.constraint(equalTo: contentGuide.leadingAnchor,
                                            constant: Metrics.horizontalInset),
      contentStack.trailingAnchor.constraint(equalTo: contentGuide.trailingAnchor,
                                             constant: -Metrics.horizontalInset),
      // Pins the scrollable width so the labels wrap instead of scrolling sideways.
      contentStack.widthAnchor.constraint(equalTo: frameGuide.widthAnchor,
                                          constant: -Metrics.horizontalInset * 2),

      getStartedButton.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor,
                                                constant: Metrics.horizontalInset),
      getStartedButton.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor,
                                                 constant: -Metrics.horizontalInset),
      getStartedButton.bottomAnchor.constraint(equalTo: safeArea.bottomAnchor, constant: -16),
    ])

    applyContentSizeCategory()
  }

  private func makeRow(for tip: Tip) -> UIStackView {
    let iconView = UIImageView(
        image: UIImage(systemName: tip.symbolName,
                       withConfiguration: UIImage.SymbolConfiguration(textStyle: Metrics.iconTextStyle)))
    iconView.contentMode = .scaleAspectFit
    iconView.tintColor = .systemBlue
    iconView.adjustsImageSizeForAccessibilityContentSizeCategory = true
    iconView.setContentHuggingPriority(.required, for: .horizontal)
    iconView.setContentCompressionResistancePriority(.required, for: .horizontal)

    let iconWidth = iconView.widthAnchor.constraint(equalToConstant: Metrics.iconBaseWidth)
    iconWidth.isActive = true
    iconWidthConstraints.append(iconWidth)

    let titleLabel = UILabel()
    titleLabel.text = tip.title
    titleLabel.font = .preferredFont(forTextStyle: .headline)
    titleLabel.adjustsFontForContentSizeCategory = true
    titleLabel.numberOfLines = 0

    let bodyLabel = UILabel()
    bodyLabel.text = tip.body
    bodyLabel.font = .preferredFont(forTextStyle: .subheadline)
    bodyLabel.adjustsFontForContentSizeCategory = true
    bodyLabel.textColor = .secondaryLabel
    bodyLabel.numberOfLines = 0

    let textStack = UIStackView(arrangedSubviews: [titleLabel, bodyLabel])
    textStack.axis = .vertical
    textStack.spacing = 2

    let row = UIStackView(arrangedSubviews: [iconView, textStack])
    row.axis = .horizontal
    row.spacing = 16
    row.alignment = .top

    // One VoiceOver stop per tip rather than three (icon, title, body).
    row.isAccessibilityElement = true
    row.accessibilityLabel = "\(tip.title). \(tip.body)"

    return row
  }

  // Folded in from the old standalone UnofficialBuildNotice screen. Same three points (not
  // official Dolphin, don't file bugs upstream, help lives in Settings), one paragraph, no extra
  // tap.
  private func makeUnofficialBuildNotice() -> UIView {
    let label = UILabel()
    label.text = "DolphiniOS is not an official version of Dolphin. It is a separate app built "
        + "on Dolphin's code, so please don't report bugs or ask for help on the official Dolphin "
        + "forums or bug tracker. Use Help in the Settings tab instead."
    label.font = .preferredFont(forTextStyle: .footnote)
    label.adjustsFontForContentSizeCategory = true
    label.textColor = .secondaryLabel
    label.numberOfLines = 0
    label.translatesAutoresizingMaskIntoConstraints = false

    let container = UIView()
    container.backgroundColor = .secondarySystemBackground
    container.layer.cornerRadius = 12
    container.layer.cornerCurve = .continuous
    container.addSubview(label)

    NSLayoutConstraint.activate([
      label.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
      label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
      label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
      label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
    ])

    return container
  }

  private func makeGetStartedButton() -> UIButton {
    let button = UIButton(type: .system)
    button.setTitle("Get Started", for: .normal)
    button.titleLabel?.font = .preferredFont(forTextStyle: .headline)
    button.titleLabel?.adjustsFontForContentSizeCategory = true
    button.titleLabel?.numberOfLines = 0
    button.titleLabel?.textAlignment = .center
    button.backgroundColor = .systemBlue
    button.setTitleColor(.white, for: .normal)
    button.layer.cornerRadius = 14
    button.layer.cornerCurve = .continuous
    button.contentEdgeInsets = UIEdgeInsets(top: 14, left: 20, bottom: 14, right: 20)
    button.isPointerInteractionEnabled = true
    button.translatesAutoresizingMaskIntoConstraints = false
    // Minimum, not a fixed height, so the label can grow with Dynamic Type instead of clipping.
    button.heightAnchor.constraint(greaterThanOrEqualToConstant: 50).isActive = true
    button.addTarget(self, action: #selector(getStartedTapped), for: .touchUpInside)

    return button
  }

  override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
    super.traitCollectionDidChange(previousTraitCollection)

    guard traitCollection.preferredContentSizeCategory
        != previousTraitCollection?.preferredContentSizeCategory else {
      return
    }

    applyContentSizeCategory()
  }

  private func applyContentSizeCategory() {
    let scaledIconWidth = UIFontMetrics(forTextStyle: Metrics.iconTextStyle)
        .scaledValue(for: Metrics.iconBaseWidth, compatibleWith: traitCollection)

    for constraint in iconWidthConstraints {
      constraint.constant = scaledIconWidth
    }

    // At accessibility text sizes a 32pt-plus icon beside wrapped text leaves the body a sliver
    // wide, so stack the icon above its text instead. Standard HIG large-content-size behaviour.
    let stacked = traitCollection.preferredContentSizeCategory.isAccessibilityCategory

    for row in tipRows {
      row.axis = stacked ? .vertical : .horizontal
      row.alignment = stacked ? .leading : .top
      row.spacing = stacked ? 8 : 16
    }
  }

  @objc private func getStartedTapped() {
    // Cleared only once the user has actually been through the screen.
    UserDefaults.standard.set(false, forKey: kWelcomeOnboardingPendingKey)

    if let navigationController = navigationController {
      // BootNoticeNavigationViewController dismisses itself when the last notice pops.
      navigationController.popViewController(animated: true)
    } else {
      dismiss(animated: true)
    }
  }
}
