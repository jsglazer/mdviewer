import AppKit

/// Tracks which document window most recently held focus.
///
/// Menu commands are broadcast to every open document, so each one has to work out
/// whether it is the one the user meant. `NSApp.keyWindow` cannot answer that on
/// its own: a utility panel (Print Preview, Settings) is perfectly able to be the
/// key window, and while the app is inactive both `keyWindow` and `mainWindow` are
/// nil — so a command would be silently dropped rather than routed anywhere.
///
/// Panels never displace a document here, so "the front document" stays meaningful
/// no matter what else has focus.
final class FrontDocumentTracker {
    static let shared = FrontDocumentTracker()

    private struct WeakWindow {
        weak var window: NSWindow?
    }

    /// Registered document windows, most recently focused last.
    private var windows: [WeakWindow] = []
    private var observer: Any?

    private init() {
        observer = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let window = note.object as? NSWindow else { return }
            self?.promote(window)
        }
    }

    /// Called as soon as a document view learns its window, so a command that
    /// arrives before the window has ever been key still has somewhere to go.
    func register(_ window: NSWindow?) {
        guard let window, Self.isDocumentWindow(window) else { return }
        promote(window)
    }

    func isFront(_ window: NSWindow?) -> Bool {
        guard let window else { return false }
        prune()
        return windows.last?.window === window
    }

    private func promote(_ window: NSWindow) {
        guard Self.isDocumentWindow(window) else { return }
        prune()
        windows.removeAll { $0.window === window }
        windows.append(WeakWindow(window: window))
    }

    private func prune() {
        windows.removeAll { $0.window == nil }
    }

    private static func isDocumentWindow(_ window: NSWindow) -> Bool {
        !(window is NSPanel) && window.styleMask.contains(.titled) && window.level == .normal
    }
}
