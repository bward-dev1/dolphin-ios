// Copyright 2026 DolphiniOS Project
// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation
import UIKit

// First-launch-only welcome screen, pushed onto BootNoticeManager's queue right after the
// existing unofficial-build notice. Previously a brand-new user landed straight on an empty
// game library with zero explanation of how to import a game, where Settings live, or how the
// touch controls work - this is the first thing that ever explains any of that.
@objc class WelcomeOnboardingViewController: UIViewController {
  private struct Point {
    let symbolName: String
    let title: String
    let body: String
  }

  private let points: [Point] = [
    Point(symbolName: "square.and.arrow.down.on.square",
          title: "Import a Game",
          body: "Tap the + button in your game library and choose a game file to add it."),
    Point(symbolName: "gamecontroller",
          title: "Touch Controls",
          body: "On-screen buttons appear automatically during play. You can also pair a "
              + "Bluetooth controller, or use a Wii Remote-style motion pointer for Wii games."),
    Point(symbolName: "gearshape",
          title: "Settings",
          body: "The Settings tab covers graphics, controllers, and an Optimize My Settings "
              + "tool that picks good defaults for this specific device."),
  ]

  init() {
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()

    view.backgroundColor = .systemBackground

    let titleLabel = UILabel()
    titleLabel.text = "Welcome"
    titleLabel.font = .preferredFont(forTextStyle: .largeTitle).withTraits(.traitBold)
    titleLabel.numberOfLines = 0

    let subtitleLabel = UILabel()
    subtitleLabel.text = "A few things to know before you dive in."
    subtitleLabel.font = .preferredFont(forTextStyle: .body)
    subtitleLabel.textColor = .secondaryLabel
    subtitleLabel.numberOfLines = 0

    let headerStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
    headerStack.axis = .vertical
    headerStack.spacing = 4

    let pointsStack = UIStackView(arrangedSubviews: points.map { makeRow(for: $0) })
    pointsStack.axis = .vertical
    pointsStack.spacing = 24

    let getStartedButton = UIButton(type: .system)
    getStartedButton.setTitle("Get Started", for: .normal)
    getStartedButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
    getStartedButton.backgroundColor = .systemBlue
    getStartedButton.setTitleColor(.white, for: .normal)
    getStartedButton.layer.cornerRadius = 14
    getStartedButton.heightAnchor.constraint(equalToConstant: 50).isActive = true
    getStartedButton.addTarget(self, action: #selector(getStartedTapped), for: .touchUpInside)

    let contentStack = UIStackView(arrangedSubviews: [headerStack, pointsStack, getStartedButton])
    contentStack.axis = .vertical
    contentStack.spacing = 32
    contentStack.translatesAutoresizingMaskIntoConstraints = false
    contentStack.setCustomSpacing(40, after: headerStack)

    view.addSubview(contentStack)

    NSLayoutConstraint.activate([
      contentStack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
      contentStack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
      contentStack.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
    ])
  }

  private func makeRow(for point: Point) -> UIView {
    let iconView = UIImageView(image: UIImage(systemName: point.symbolName))
    iconView.contentMode = .scaleAspectFit
    iconView.tintColor = .systemBlue
    iconView.setContentHuggingPriority(.required, for: .horizontal)
    iconView.widthAnchor.constraint(equalToConstant: 32).isActive = true

    let titleLabel = UILabel()
    titleLabel.text = point.title
    titleLabel.font = .preferredFont(forTextStyle: .headline)
    titleLabel.numberOfLines = 0

    let bodyLabel = UILabel()
    bodyLabel.text = point.body
    bodyLabel.font = .preferredFont(forTextStyle: .subheadline)
    bodyLabel.textColor = .secondaryLabel
    bodyLabel.numberOfLines = 0

    let textStack = UIStackView(arrangedSubviews: [titleLabel, bodyLabel])
    textStack.axis = .vertical
    textStack.spacing = 2

    let row = UIStackView(arrangedSubviews: [iconView, textStack])
    row.axis = .horizontal
    row.spacing = 16
    row.alignment = .top

    let accessibilityLabel = "\(point.title). \(point.body)"
    row.isAccessibilityElement = true
    row.accessibilityLabel = accessibilityLabel

    return row
  }

  @objc private func getStartedTapped() {
    navigationController?.popViewController(animated: true)
  }
}

private extension UIFont {
  func withTraits(_ traits: UIFontDescriptor.SymbolicTraits) -> UIFont {
    guard let descriptor = fontDescriptor.withSymbolicTraits(traits) else {
      return self
    }
    return UIFont(descriptor: descriptor, size: pointSize)
  }
}
