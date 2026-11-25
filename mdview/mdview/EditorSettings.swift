import Foundation
import MarkdownRenderKit

/// Which panes a document window shows.
enum EditorLayout: Int, CaseIterable, Identifiable {
    case edit, split, preview

    var id: Int { rawValue }
    var title: String {
        switch self {
        case .edit: return "Edit"
        case .split: return "Split"
        case .preview: return "Preview"
        }
    }
    var showsEditor: Bool { self != .preview }
    var showsPreview: Bool { self != .edit }
}

/// Editor and layout preferences, stored in mdview's own defaults.
enum EditorSettings {
    enum Key {
        static let fontFamily = "editorFontFamily"
        static let fontSize = "editorFontSize"
        static let lineNumbers = "editorLineNumbers"
        static let lineWrapping = "editorLineWrapping"
        static let splitFraction = "editorSplitFraction"
        /// `EditorLayout.rawValue` new windows open in (default: Preview).
        static let openLayout = "openLayout"
        /// `[file path: EditorLayout.rawValue]`, the layout each file was last left in.
        static let layoutByFile = "layoutByFile"
    }

    static let defaultFontSize = 14.0
    static let fontSizeRange = 10.0...28.0

    /// Editor font choices: a label and the CSS font-family list sent to CodeMirror.
    static let fonts: [(name: String, css: String)] = [
        ("System Monospace", "ui-monospace, \"SF Mono\", Menlo, monospace"),
        ("Menlo", "Menlo, monospace"),
        ("Courier New", "\"Courier New\", Courier, monospace"),
        ("System (proportional)", "-apple-system, \"SF Pro Text\", sans-serif"),
        ("New York (serif)", "ui-serif, \"New York\", Georgia, serif"),
    ]
    static var defaultFontFamily: String { fonts[0].css }

    /// The editor options currently saved in Settings.
    static var currentOptions: EditorOptions {
        let defaults = UserDefaults.standard
        let size = defaults.double(forKey: Key.fontSize)
        return EditorOptions(
            lineNumbers: defaults.bool(forKey: Key.lineNumbers),
            lineWrapping: defaults.object(forKey: Key.lineWrapping) as? Bool ?? true,
            fontFamily: defaults.string(forKey: Key.fontFamily) ?? defaultFontFamily,
            fontSize: size > 0 ? size : defaultFontSize)
    }

    /// The "Open documents in" setting.
    static var openLayout: EditorLayout {
        let raw = UserDefaults.standard.object(forKey: Key.openLayout) as? Int
        return raw.flatMap(EditorLayout.init(rawValue:)) ?? .preview
    }
}

/// Remembers the layout each file was last left in, so it reopens the same way.
enum LayoutMemory {
    /// Upper bound on remembered files; entries for files that no longer exist go first.
    private static let limit = 400

    /// The layout a newly opened window should start in.
    static func initialLayout(for url: URL?) -> EditorLayout {
        guard let url else {
            // A new, untitled document is opened to be written in, so never start it
            // in the read-only Preview.
            let preferred = EditorSettings.openLayout
            return preferred == .preview ? .split : preferred
        }
        let stored = UserDefaults.standard.dictionary(forKey: EditorSettings.Key.layoutByFile)
        if let raw = stored?[url.path] as? Int, let layout = EditorLayout(rawValue: raw) {
            return layout
        }
        return EditorSettings.openLayout
    }

    static func remember(_ layout: EditorLayout, for url: URL?) {
        guard let url else { return }
        let defaults = UserDefaults.standard
        var stored = defaults.dictionary(forKey: EditorSettings.Key.layoutByFile) ?? [:]
        stored[url.path] = layout.rawValue
        if stored.count > limit {
            let fileManager = FileManager.default
            for path in stored.keys where !fileManager.fileExists(atPath: path) {
                stored[path] = nil
            }
            for path in stored.keys.sorted().prefix(max(stored.count - limit, 0))
            where path != url.path {
                stored[path] = nil
            }
        }
        defaults.set(stored, forKey: EditorSettings.Key.layoutByFile)
    }
}
