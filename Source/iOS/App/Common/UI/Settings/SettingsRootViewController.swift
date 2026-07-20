// Copyright 2022 DolphiniOS Project
// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation
import UIKit

class SettingsRootViewController : UITableViewController {
  @IBOutlet weak var versionLabel: UILabel!
  @IBOutlet weak var coreVersionLabel: UILabel!
  
  override func viewDidLoad() {
    let versionManager = VersionManager.shared()
    
    versionLabel.text = versionManager.appVersion.userFacing
    coreVersionLabel.text = versionManager.coreVersion
  }
  
  // Cells are looked up by tag (set in SettingsRoot.storyboard) rather than raw section/row
  // indices, so reordering or regrouping rows in the storyboard can't silently point this at
  // the wrong cell.
  private enum RowTag: Int {
    case help = 1
    case coverArt = 2
    case appIcon = 3
    case optimizeSettings = 4
  }

  override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)

    guard let cell = tableView.cellForRow(at: indexPath), let tag = RowTag(rawValue: cell.tag) else {
      return
    }

    switch tag {
    case .help:
      UIApplication.shared.open(URL(string: "https://oatmealdome.me/dolphinios/")!)
    case .coverArt:
      navigationController?.pushViewController(CoverArtSettingsViewController(), animated: true)
    case .appIcon:
      navigationController?.pushViewController(AppIconSelectorViewController(), animated: true)
    case .optimizeSettings:
      navigationController?.pushViewController(OptimizeSettingsViewController(), animated: true)
    }
  }
  
  @IBAction func unwindToSettings( _ seg: UIStoryboardSegue) {}
}
