import AppKit
import SwiftUI

final class CSSPanelController {
    static let shared = CSSPanelController()
    private var panel: NSPanel?
    private init() {}

    func show(css: String) {
        if panel == nil {
            panel = UtilityPanel.make(
                title: "Document CSS",
                size: NSSize(width: 620, height: 520),
                minSize: NSSize(width: 400, height: 300),
                miniaturizable: true
            )
        }
        // Recreate the hosting view each call so the CSS content stays current.
        panel?.contentView = NSHostingView(rootView: ShowCSSView(css: css))
        if let panel { UtilityPanel.present(panel) }
    }
}
