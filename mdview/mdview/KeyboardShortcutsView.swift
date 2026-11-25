import AppKit
import MarkdownRenderKit
import SwiftUI

struct KeyboardShortcutsView: View {
    private struct Row: Identifiable {
        let id = UUID()
        let key: String
        let desc: String
    }
    private struct Section: Identifiable {
        let id = UUID()
        let title: String
        let rows: [Row]
    }

    private let sections: [Section] = [
        Section(
            title: "Navigation",
            rows: [
                Row(key: "⌘ ↑", desc: "Go to top"),
                Row(key: "⌘ ↓", desc: "Go to bottom"),
                Row(key: "⌘ ←", desc: "Page up"),
                Row(key: "⌘ →", desc: "Page down"),
            ]),
        Section(
            title: "Layout",
            rows: [
                Row(key: "⌘ 1", desc: "Edit"),
                Row(key: "⌘ 2", desc: "Split (editor + preview)"),
                Row(key: "⌘ 3", desc: "Preview"),
            ]),
        Section(
            title: "Editing",
            rows: [
                Row(key: "⌘ S", desc: "Save"),
                Row(key: "⌘ N", desc: "New document"),
                Row(key: "⌘ Z", desc: "Undo"),
                Row(key: "⌘ ⇧ Z", desc: "Redo"),
                Row(key: "⌘ B", desc: "Bold"),
                Row(key: "⌘ I", desc: "Italic"),
                Row(key: "⌘ K", desc: "Link"),
                Row(key: "⌘ ⇧ H", desc: "Highlight (==text==)"),
                Row(key: "⌘ /", desc: "Toggle comment"),
                Row(key: "⌘ ⌥ ⇧ L", desc: "Toggle Editor Line Numbers"),
            ]),
        Section(
            title: "Scroll Mode",
            rows: [
                Row(key: "⌘ J", desc: "Toggle Jump to New Content"),
                Row(key: "⌘ ⇧ T", desc: "Toggle Tail Mode"),
            ]),
        Section(
            title: "View",
            rows: [
                Row(key: "⌘ ⇧ L", desc: "Toggle Preview Line Numbers"),
                Row(key: "⌘ ⇧ O", desc: "Toggle Outline panel"),
                Row(key: "⌘ ⇧ C", desc: "Show Document CSS"),
                Row(key: "⌘ +", desc: "Zoom In"),
                Row(key: "⌘ −", desc: "Zoom Out"),
                Row(key: "⌘ 0", desc: "Actual Size"),
                Row(key: "⌘ ⇧ K", desc: "Keyboard Shortcuts (this window)"),
            ]),
        Section(
            title: "Print",
            rows: [
                Row(key: "⌘ P", desc: "Print… (opens Print Preview)"),
                Row(key: "⌘ ⇧ E", desc: "Export as PDF…"),
            ]),
        Section(
            title: "Find",
            rows: [
                Row(key: "⌘ F", desc: "Find (search & replace in the editor when it has focus)"),
                Row(key: "⌘ ⌥ F", desc: "Find in Preview"),
                Row(key: "↩", desc: "Jump to first result"),
                Row(key: "Esc", desc: "Close Find"),
            ]),
        Section(
            title: "App",
            rows: [
                Row(key: "⌘ ,", desc: "Settings")
            ]),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Keyboard Shortcuts")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(sections) { section in
                        Text(section.title.uppercased())
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 20)
                            .padding(.top, 14)
                            .padding(.bottom, 5)
                        ForEach(section.rows) { row in
                            HStack(spacing: 16) {
                                Text(row.key)
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 90, alignment: .trailing)
                                Text(row.desc)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 5)
                            Divider().padding(.leading, 20)
                        }
                    }
                }
                .padding(.bottom, 14)
            }
        }
    }
}

final class ShortcutsPanelController {
    static let shared = ShortcutsPanelController()
    private var panel: NSPanel?
    private init() {}

    func show() {
        if panel == nil {
            let newPanel = UtilityPanel.make(
                title: "Keyboard Shortcuts",
                size: NSSize(width: 400, height: 640),
                minSize: NSSize(width: 300, height: 300)
            )
            newPanel.contentView = NSHostingView(rootView: KeyboardShortcutsView())
            panel = newPanel
        }
        if let panel { UtilityPanel.present(panel) }
    }
}
