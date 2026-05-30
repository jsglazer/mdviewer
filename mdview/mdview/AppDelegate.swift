import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )
    }

    @objc func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              !(window is NSPanel),
              window.styleMask.contains(.titled),
              window.level == .normal else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let remaining = NSApp.windows.filter {
                !($0 is NSPanel) &&
                ($0.isVisible || $0.isMiniaturized) &&
                $0.styleMask.contains(.titled) &&
                $0.level == .normal
            }
            if remaining.isEmpty {
                NSApp.terminate(nil)
            }
        }
    }

    @objc func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              !(window is NSPanel),
              window.styleMask.contains(.titled),
              window.level == .normal else { return }

        window.tabbingMode = .preferred

        DispatchQueue.main.async {
            guard window.isVisible,
                  window.tabbingMode != .disallowed,
                  window.tabbedWindows == nil || window.tabbedWindows!.count <= 1 else { return }

            let others = NSApp.windows.filter {
                $0 !== window &&
                $0.isVisible &&
                $0.styleMask.contains(.titled) &&
                $0.level == .normal &&
                !$0.isMiniaturized &&
                !($0.tabbedWindows ?? []).contains(where: { $0 === window })
            }

            guard let target = others.first else { return }

            target.addTabbedWindow(window, ordered: .above)
            window.makeKeyAndOrderFront(nil)
        }
    }
}
