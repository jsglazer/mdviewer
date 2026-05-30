import AppKit
import SwiftUI

final class SettingsPanelController {
    static let shared = SettingsPanelController()
    private var panel: NSPanel?
    private init() {}

    func show() {
        if panel == nil {
            let p = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 500),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            p.title = "Settings"
            p.isReleasedWhenClosed = false
            p.tabbingMode = .disallowed
            p.minSize = NSSize(width: 380, height: 300)
            p.contentView = NSHostingView(rootView: SettingsView())
            panel = p
        }
        if !(panel?.isVisible ?? false) { panel?.center() }
        panel?.makeKeyAndOrderFront(nil)
    }
}
