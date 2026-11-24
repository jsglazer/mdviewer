import AppKit
import MarkdownRenderKit
import Observation
import SwiftUI

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

/// Per-window state and actions. Published to the menu bar through
/// `focusedSceneValue`, so every menu command acts on the window the user is in.
@Observable
final class EditorWindowModel {
    let editor: EditorController
    let preview = MarkdownController()

    var layout: EditorLayout = .split {
        didSet { if layout != oldValue { layoutChanged() } }
    }
    var showOutline = false
    var showPreviewFind = false
    var previewLineNumbers = false
    var findQuery = ""
    var findResults: [FindResult] = []
    var currentFindIndex: Int?
    var tocItems: [TOCItem] = []
    var activeHeadingChain: [String] = []

    /// Snapshot inputs for Print / Export, kept current by the window view.
    @ObservationIgnored var printTitle = "Untitled"
    @ObservationIgnored var printBaseDir: URL?
    @ObservationIgnored var customCSS = ""
    @ObservationIgnored weak var window: NSWindow? {
        didSet { if window !== oldValue { restartMonitor() } }
    }
    @ObservationIgnored var fileURL: URL? {
        didSet { if fileURL != oldValue { restartMonitor() } }
    }
    @ObservationIgnored private var monitor: ExternalChangeMonitor?

    init(options: EditorOptions) {
        editor = EditorController(options: options)
        editor.onScroll = { [weak self] line in self?.editorScrolled(to: line) }
    }

    func close() {
        monitor?.stop()
        monitor = nil
    }

    private func restartMonitor() {
        monitor?.stop()
        monitor = nil
        guard let window, let fileURL else { return }
        monitor = ExternalChangeMonitor(url: fileURL, window: window)
    }

    // MARK: - Scroll sync

    // Each side suppresses the scroll events its own programmatic scrolls cause
    // (see `mdeditScrollToLine` / `scrollToLine` in the pages), so following the
    // other pane never bounces back.
    private func editorScrolled(to line: Double) {
        guard layout == .split else { return }
        preview.scrollToLine(line)
    }

    func previewScrolled(to line: Double) {
        guard layout == .split else { return }
        editor.scrollToLine(line)
    }

    /// Outline click: the preview scrolls to the heading; the editor jumps to its
    /// source line and puts the cursor there.
    func selectHeading(_ id: String) {
        preview.scrollToHeading(id: id)
        preview.sourceLine(forHeading: id) { [weak self] line in
            guard let self, let line, self.layout.showsEditor else { return }
            self.editor.scrollToLine(Double(line))
            self.editor.setCursorLine(line)
        }
    }

    // MARK: - Layout

    func cycleOutline() { showOutline.toggle() }

    private func layoutChanged() {
        if layout.showsEditor {
            // Let SwiftUI unhide the editor first, then give it the keyboard.
            DispatchQueue.main.async { [weak self] in self?.editor.focus() }
        } else if let window, let responder = window.firstResponder as? NSView,
            responder === editor.webView || responder.isDescendant(of: editor.webView)
        {
            // Never leave keystrokes going into an editor the user can't see.
            window.makeFirstResponder(nil)
        }
    }

    // MARK: - Find

    /// ⌘F: search/replace in the editor when it is visible, else find in the preview.
    func find() {
        if layout.showsEditor {
            editor.openSearch()
        } else {
            openPreviewFind()
        }
    }

    func openPreviewFind() {
        if !layout.showsPreview { layout = .split }
        showPreviewFind = true
    }

    func performFind(_ query: String) {
        guard !query.isEmpty else {
            findResults = []
            preview.clearFind()
            return
        }
        preview.findText(query) { [weak self] in self?.findResults = $0 }
    }

    func navigateFind(delta: Int) {
        guard !findResults.isEmpty else { return }
        let count = findResults.count
        let next =
            currentFindIndex.map { ($0 + delta + count) % count } ?? (delta > 0 ? 0 : count - 1)
        currentFindIndex = next
        preview.scrollToMatch(findResults[next].id)
    }

    func closeFind() {
        showPreviewFind = false
        findQuery = ""
        findResults = []
        currentFindIndex = nil
        preview.clearFind()
    }

    /// Find marks vanish when the preview re-renders, so drop stale results with them.
    func previewRerendered() {
        guard showPreviewFind, !findResults.isEmpty else { return }
        findResults = []
        currentFindIndex = nil
    }

    // MARK: - Print / export

    func printDocument(_ intent: PrintPreviewIntent) {
        PrintPreviewController.shared.show(
            source: PrintSource(
                markdown: Self.processed(editor.text, baseDir: printBaseDir),
                baseDir: printBaseDir,
                customCSS: customCSS,
                showLineNumbers: previewLineNumbers,
                title: printTitle),
            intent: intent)
    }

    /// Relative image paths are routed through the preview's image scheme handler,
    /// which can only resolve them once the document has a folder on disk.
    static func processed(_ markdown: String, baseDir: URL?) -> String {
        baseDir == nil ? markdown : MarkdownImagePaths.rewrite(markdown)
    }
}

extension FocusedValues {
    @Entry var editorWindow: EditorWindowModel?
}
