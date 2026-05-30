import AppKit
import SwiftUI

final class CSSPanelController {
    static let shared = CSSPanelController()
    private var panel: NSPanel?
    private init() {}

    func show(css: String) {
        if panel == nil {
            let p = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 620, height: 520),
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            p.title = "Document CSS"
            p.isReleasedWhenClosed = false
            p.tabbingMode = .disallowed
            p.minSize = NSSize(width: 400, height: 300)
            panel = p
        }
        // Recreate the hosting view each call so the CSS content stays current.
        panel?.contentView = NSHostingView(rootView: ShowCSSView(css: css))
        if !(panel?.isVisible ?? false) { panel?.center() }
        panel?.makeKeyAndOrderFront(nil)
    }
}
