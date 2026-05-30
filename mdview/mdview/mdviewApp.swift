import SwiftUI
import AppKit

extension Notification.Name {
    static let mdviewOpenFind              = Notification.Name("mdviewOpenFind")
    static let mdviewToggleLineNumbers     = Notification.Name("mdviewToggleLineNumbers")
    static let mdviewShowCSS               = Notification.Name("mdviewShowCSS")
    static let mdviewToggleJumpToNew       = Notification.Name("mdviewToggleJumpToNew")
    static let mdviewToggleTail            = Notification.Name("mdviewToggleTail")
    static let mdviewToggleOutline         = Notification.Name("mdviewToggleOutline")
    static let mdviewShowKeyboardShortcuts = Notification.Name("mdviewShowKeyboardShortcuts")
    static let mdviewZoomIn                = Notification.Name("mdviewZoomIn")
    static let mdviewZoomOut               = Notification.Name("mdviewZoomOut")
    static let mdviewResetZoom             = Notification.Name("mdviewResetZoom")
}

@main
struct mdviewApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        DocumentGroup(viewing: mdviewDocument.self) { config in
            ContentView(document: config.document, fileURL: config.fileURL)
        }
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandGroup(replacing: .appInfo) {
                Button("About mdview") {
                    NSApp.orderFrontStandardAboutPanel(options: [
                        .applicationIcon: NSApp.applicationIconImage as Any,
                        .applicationName: "mdview" as Any,
                        .version: "" as Any
                    ])
                    NSApp.keyWindow?.tabbingMode = .disallowed
                }
            }
            CommandGroup(after: .appInfo) {
                Button("Settings…") {
                    SettingsPanelController.shared.show()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(after: .pasteboard) {
                Divider()
                Button("Find…") {
                    NotificationCenter.default.post(name: .mdviewOpenFind, object: nil)
                }
                .keyboardShortcut("f", modifiers: .command)
            }
            CommandMenu("View") {
                Button("Jump to New Content") {
                    NotificationCenter.default.post(name: .mdviewToggleJumpToNew, object: nil)
                }
                .keyboardShortcut("j", modifiers: .command)

                Button("Tail Mode") {
                    NotificationCenter.default.post(name: .mdviewToggleTail, object: nil)
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])

                Divider()

                Button("Line Numbers") {
                    NotificationCenter.default.post(name: .mdviewToggleLineNumbers, object: nil)
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])

                Button("Toggle Outline") {
                    NotificationCenter.default.post(name: .mdviewToggleOutline, object: nil)
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])

                Button("Show Document CSS") {
                    NotificationCenter.default.post(name: .mdviewShowCSS, object: nil)
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])

                Divider()

                Divider()

                Button("Zoom In") {
                    NotificationCenter.default.post(name: .mdviewZoomIn, object: nil)
                }
                .keyboardShortcut("+", modifiers: .command)

                Button("Zoom Out") {
                    NotificationCenter.default.post(name: .mdviewZoomOut, object: nil)
                }
                .keyboardShortcut("-", modifiers: .command)

                Button("Actual Size") {
                    NotificationCenter.default.post(name: .mdviewResetZoom, object: nil)
                }
                .keyboardShortcut("0", modifiers: .command)

                Divider()

                Button("Keyboard Shortcuts") {
                    ShortcutsPanelController.shared.show()
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])
            }
        }
    }
}
