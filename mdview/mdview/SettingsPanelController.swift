import AppKit
import SwiftUI

final class SettingsPanelController {
    static let shared = SettingsPanelController()
    private var panel: NSPanel?
    private init() {}

    func show() {
        if panel == nil {
            let newPanel = UtilityPanel.make(
                title: "Settings",
                size: NSSize(width: 480, height: 500),
                minSize: NSSize(width: 380, height: 300)
            )
            newPanel.contentView = NSHostingView(rootView: SettingsView())
            panel = newPanel
        }
        if let panel { UtilityPanel.present(panel) }
    }
}
