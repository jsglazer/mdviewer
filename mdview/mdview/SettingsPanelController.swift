import AppKit
import SwiftUI

final class SettingsPanelController {
    static let shared = SettingsPanelController()
    private var panel: NSPanel?
    private init() {}

    func show() {
        if panel == nil {
            let p = UtilityPanel.make(
                title: "Settings",
                size: NSSize(width: 480, height: 500),
                minSize: NSSize(width: 380, height: 300)
            )
            p.contentView = NSHostingView(rootView: SettingsView())
            panel = p
        }
        if let panel { UtilityPanel.present(panel) }
    }
}
