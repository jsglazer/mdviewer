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
        Section(title: "Navigation", rows: [
            Row(key: "⌘ ↑",  desc: "Go to top"),
            Row(key: "⌘ ↓",  desc: "Go to bottom"),
            Row(key: "⌘ ←",  desc: "Page up"),
            Row(key: "⌘ →",  desc: "Page down"),
        ]),
        Section(title: "Scroll Mode", rows: [
            Row(key: "⌘ J",    desc: "Toggle Jump to New Content"),
            Row(key: "⌘ ⇧ T", desc: "Toggle Tail Mode"),
        ]),
        Section(title: "View", rows: [
            Row(key: "⌘ ⇧ L", desc: "Toggle Line Numbers"),
            Row(key: "⌘ ⇧ O", desc: "Toggle Outline panel"),
            Row(key: "⌘ ⇧ C", desc: "Show Document CSS"),
            Row(key: "⌘ +",   desc: "Zoom In"),
            Row(key: "⌘ −",   desc: "Zoom Out"),
            Row(key: "⌘ 0",   desc: "Actual Size"),
            Row(key: "⌘ ⇧ K", desc: "Keyboard Shortcuts (this window)"),
        ]),
        Section(title: "Find", rows: [
            Row(key: "⌘ F",  desc: "Open Find"),
            Row(key: "↩",    desc: "Jump to first result"),
            Row(key: "Esc",  desc: "Close Find"),
        ]),
        Section(title: "App", rows: [
            Row(key: "⌘ ,", desc: "Settings"),
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

import AppKit

// Shared NSPanel construction for the app's utility panels (Settings, Document
// CSS, Keyboard Shortcuts), which were otherwise three copies of the same setup.
enum UtilityPanel {
    static func make(
        title: String,
        size: NSSize,
        minSize: NSSize,
        miniaturizable: Bool = false
    ) -> NSPanel {
        var style: NSWindow.StyleMask = [.titled, .closable, .resizable]
        if miniaturizable { style.insert(.miniaturizable) }
        let p = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: style,
            backing: .buffered,
            defer: false
        )
        p.title = title
        p.isReleasedWhenClosed = false
        p.tabbingMode = .disallowed
        p.minSize = minSize
        return p
    }

    // Center only when the panel is not already on screen, then bring it forward.
    static func present(_ panel: NSPanel) {
        if !panel.isVisible { panel.center() }
        panel.makeKeyAndOrderFront(nil)
    }
}

final class ShortcutsPanelController {
    static let shared = ShortcutsPanelController()
    private var panel: NSPanel?
    private init() {}

    func show() {
        if panel == nil {
            let p = UtilityPanel.make(
                title: "Keyboard Shortcuts",
                size: NSSize(width: 360, height: 540),
                minSize: NSSize(width: 300, height: 300)
            )
            p.contentView = NSHostingView(rootView: KeyboardShortcutsView())
            panel = p
        }
        if let panel { UtilityPanel.present(panel) }
    }
}
