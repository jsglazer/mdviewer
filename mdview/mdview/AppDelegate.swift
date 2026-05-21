import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
    }

    @objc func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window.styleMask.contains(.titled),
              window.level == .normal else { return }

        window.tabbingMode = .preferred

        let others = NSApp.windows.filter {
            $0 !== window &&
            $0.isVisible &&
            $0.styleMask.contains(.titled) &&
            $0.level == .normal &&
            !$0.isMiniaturized
        }

        guard let target = others.first,
              !(target.tabbedWindows ?? []).contains(where: { $0 === window }) else { return }

        target.addTabbedWindow(window, ordered: .above)
        window.makeKeyAndOrderFront(nil)
    }
}
