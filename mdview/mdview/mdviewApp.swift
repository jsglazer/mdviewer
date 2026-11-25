import AppKit
import MarkdownRenderKit
import SwiftUI

extension Notification.Name {
    static let mdviewToggleLineNumbers = Notification.Name("mdviewToggleLineNumbers")
    static let mdviewShowCSS = Notification.Name("mdviewShowCSS")
    static let mdviewToggleJumpToNew = Notification.Name("mdviewToggleJumpToNew")
    static let mdviewToggleTail = Notification.Name("mdviewToggleTail")
    static let mdviewToggleOutline = Notification.Name("mdviewToggleOutline")
    static let mdviewShowKeyboardShortcuts = Notification.Name("mdviewShowKeyboardShortcuts")
    static let mdviewZoomIn = Notification.Name("mdviewZoomIn")
    static let mdviewZoomOut = Notification.Name("mdviewZoomOut")
    static let mdviewResetZoom = Notification.Name("mdviewResetZoom")
    static let mdviewPrint = Notification.Name("mdviewPrint")
    static let mdviewExportPDF = Notification.Name("mdviewExportPDF")
}

@main
// swiftlint:disable:next type_name
struct mdviewApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        DocumentGroup(newDocument: mdviewDocument()) { config in
            ContentView(document: config.$document, fileURL: config.fileURL)
        }
        .commands {
            EditingCommands()
            CommandGroup(replacing: .appInfo) {
                Button("About mdview") {
                    let info = Bundle.main.infoDictionary
                    let shortVersion = info?["CFBundleShortVersionString"] as? String ?? ""
                    let build = info?["CFBundleVersion"] as? String ?? ""
                    NSApp.orderFrontStandardAboutPanel(options: [
                        .applicationIcon: NSApp.applicationIconImage as Any,
                        .applicationName: "mdview" as Any,
                        .applicationVersion: shortVersion as Any,
                        .version: build as Any,
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
            CommandGroup(replacing: .printItem) {
                Button("Print…") {
                    NotificationCenter.default.post(name: .mdviewPrint, object: nil)
                }
                .keyboardShortcut("p", modifiers: .command)

                Button("Export as PDF…") {
                    NotificationCenter.default.post(name: .mdviewExportPDF, object: nil)
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            }
            CommandMenu("View") {
                LayoutCommands()

                Divider()

                Button("Jump to New Content") {
                    NotificationCenter.default.post(name: .mdviewToggleJumpToNew, object: nil)
                }
                .keyboardShortcut("j", modifiers: .command)

                Button("Tail Mode") {
                    NotificationCenter.default.post(name: .mdviewToggleTail, object: nil)
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])

                Divider()

                Button("Preview Line Numbers") {
                    NotificationCenter.default.post(name: .mdviewToggleLineNumbers, object: nil)
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])

                Button("Editor Line Numbers") {
                    let defaults = UserDefaults.standard
                    defaults.set(
                        !defaults.bool(forKey: EditorSettings.Key.lineNumbers),
                        forKey: EditorSettings.Key.lineNumbers)
                }
                .keyboardShortcut("l", modifiers: [.command, .shift, .option])

                Button("Toggle Outline") {
                    NotificationCenter.default.post(name: .mdviewToggleOutline, object: nil)
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])

                Button("Show Document CSS") {
                    NotificationCenter.default.post(name: .mdviewShowCSS, object: nil)
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])

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

/// The View menu's layout switches. Each acts on the focused document window.
private struct LayoutCommands: View {
    @FocusedValue(\.documentWindow) private var window

    var body: some View {
        ForEach(EditorLayout.allCases) { layout in
            Button(layout.title) { window?.layout = layout }
                .keyboardShortcut(
                    KeyEquivalent(Character("\(layout.rawValue + 1)")), modifiers: .command
                )
                .disabled(window == nil)
        }
    }
}

/// Undo/Redo, Find and the Format menu. Editing commands act only on a visible editor
/// in the focused window, so in the Preview layout no command can change the file.
struct EditingCommands: Commands {
    @FocusedValue(\.documentWindow) private var window

    private var canEdit: Bool { window?.layout.showsEditor == true && window?.editor != nil }

    var body: some Commands {
        // Undo/Redo belong to CodeMirror's history, not the document's whole-text
        // snapshots. Anywhere else (a text field, the Settings CSS editor) they go to
        // the responder chain as usual.
        CommandGroup(replacing: .undoRedo) {
            Button("Undo") {
                if canEdit, let editor = window?.editor {
                    editor.undo()
                } else {
                    NSApp.sendAction(Selector(("undo:")), to: nil, from: nil)
                }
            }
            .keyboardShortcut("z", modifiers: .command)
            Button("Redo") {
                if canEdit, let editor = window?.editor {
                    editor.redo()
                } else {
                    NSApp.sendAction(Selector(("redo:")), to: nil, from: nil)
                }
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
        }
        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Find…") {
                if let window {
                    window.find()
                } else {
                    NotificationCenter.default.post(name: .mdviewOpenFind, object: nil)
                }
            }
            .keyboardShortcut("f", modifiers: .command)
            Button("Find in Preview…") { window?.openPreviewFind() }
                .keyboardShortcut("f", modifiers: [.command, .option])
                .disabled(window == nil)
        }
        CommandMenu("Format") {
            formatButton("Bold", .bold, key: "b")
            formatButton("Italic", .italic, key: "i")
            formatButton("Link", .link, key: "k")
            formatButton("Highlight", .highlight, key: "h", modifiers: [.command, .shift])
            Divider()
            formatButton("Toggle Comment", .comment, key: "/")
        }
    }

    private func formatButton(
        _ title: String, _ kind: EditorFormat, key: KeyEquivalent,
        modifiers: EventModifiers = .command
    ) -> some View {
        Button(title) { window?.format(kind) }
            .keyboardShortcut(key, modifiers: modifiers)
            .disabled(!canEdit)
    }
}
