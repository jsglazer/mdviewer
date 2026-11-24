import AppKit

// Shared NSPanel construction for the apps' utility panels (Settings, Document
// CSS, Keyboard Shortcuts, Print Preview), which were otherwise copies of the same setup.
public enum UtilityPanel {
    public static func make(
        title: String,
        size: NSSize,
        minSize: NSSize,
        miniaturizable: Bool = false
    ) -> NSPanel {
        var style: NSWindow.StyleMask = [.titled, .closable, .resizable]
        if miniaturizable { style.insert(.miniaturizable) }
        let newPanel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: style,
            backing: .buffered,
            defer: false
        )
        newPanel.title = title
        newPanel.isReleasedWhenClosed = false
        newPanel.tabbingMode = .disallowed
        newPanel.minSize = minSize
        return newPanel
    }

    // Center only when the panel is not already on screen, then bring it forward.
    public static func present(_ panel: NSPanel) {
        if !panel.isVisible { panel.center() }
        panel.makeKeyAndOrderFront(nil)
    }
}
