import AppKit
import MarkdownRenderKit
import SwiftUI

@main
// swiftlint:disable:next type_name
struct mdeditApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: mdeditDocument()) { config in
            EditorWindowView(document: config.$document, fileURL: config.fileURL)
        }
        .commands { EditorCommands() }

        Settings {
            EditorSettingsView()
        }
    }
}

/// Menu bar commands. Each acts on the focused document window's model; with no
/// document window focused (e.g. Print Preview is key) they are disabled.
struct EditorCommands: Commands {
    @FocusedValue(\.editorWindow) private var window

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About mdedit") { showAbout() }
        }
        // Undo/Redo belong to CodeMirror's history, not the document's whole-text
        // snapshots; the editor's own key handling covers ⌘Z while it has focus.
        CommandGroup(replacing: .undoRedo) {
            Button("Undo") { window?.editor.undo() }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(window == nil)
            Button("Redo") { window?.editor.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(window == nil)
        }
        CommandGroup(replacing: .printItem) {
            Button("Print…") { window?.printDocument(.printing) }
                .keyboardShortcut("p", modifiers: .command)
                .disabled(window == nil)
            Button("Export as PDF…") { window?.printDocument(.exportPDF) }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(window == nil)
        }
        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Find…") { window?.find() }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(window == nil)
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
        CommandGroup(before: .toolbar) {
            layoutButton(.edit, key: "1")
            layoutButton(.split, key: "2")
            layoutButton(.preview, key: "3")
            Divider()
            Button("Toggle Outline") { window?.cycleOutline() }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                .disabled(window == nil)
            Button("Editor Line Numbers") {
                let defaults = UserDefaults.standard
                defaults.set(
                    !defaults.bool(forKey: EditorSettings.Key.lineNumbers),
                    forKey: EditorSettings.Key.lineNumbers)
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])
            Button("Preview Line Numbers") { window?.previewLineNumbers.toggle() }
                .keyboardShortcut("l", modifiers: [.command, .shift, .option])
                .disabled(window == nil)
            Divider()
            Button("Zoom In Preview") { window?.preview.zoomIn() }
                .keyboardShortcut("+", modifiers: .command)
                .disabled(window == nil)
            Button("Zoom Out Preview") { window?.preview.zoomOut() }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(window == nil)
            Button("Actual Size Preview") { window?.preview.resetZoom() }
                .keyboardShortcut("0", modifiers: .command)
                .disabled(window == nil)
            Divider()
        }
    }

    private func formatButton(
        _ title: String, _ kind: EditorFormat, key: KeyEquivalent,
        modifiers: EventModifiers = .command
    ) -> some View {
        Button(title) {
            if window?.layout.showsEditor == false { window?.layout = .split }
            window?.editor.format(kind)
        }
        .keyboardShortcut(key, modifiers: modifiers)
        .disabled(window == nil)
    }

    private func layoutButton(_ layout: EditorLayout, key: KeyEquivalent) -> some View {
        Button(layout.title) { window?.layout = layout }
            .keyboardShortcut(key, modifiers: .command)
            .disabled(window == nil)
    }

    private func showAbout() {
        let info = Bundle.main.infoDictionary
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationIcon: NSApp.applicationIconImage as Any,
            .applicationName: "mdedit" as Any,
            .applicationVersion: (info?["CFBundleShortVersionString"] as? String ?? "") as Any,
            .version: (info?["CFBundleVersion"] as? String ?? "") as Any,
        ])
    }
}
