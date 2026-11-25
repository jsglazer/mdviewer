import AppKit
import MarkdownRenderKit
import Observation
import SwiftUI

/// Per-window state and actions for one document. Published to the menu bar through
/// `focusedSceneValue`, so the editing commands act on the window the user is in.
///
/// The CodeMirror editor is created lazily, the first time the window leaves the
/// Preview layout: a file that is only ever viewed costs exactly what it did before
/// mdview could edit, and with no editor in the window no keystroke can change it.
@Observable
final class DocumentWindowModel {
    private(set) var editor: EditorController?
    let preview = MarkdownController()

    var layout: EditorLayout {
        didSet { if layout != oldValue { layoutChanged() } }
    }
    /// Bumped to ask the window to open the preview's Find bar.
    private(set) var previewFindRequest = 0

    /// Receives every edit made in the editor (the window binds it to the document).
    @ObservationIgnored var onEditorText: (String) -> Void = { _ in }
    /// The document's current text, used to seed the editor when it is first created.
    @ObservationIgnored var documentText: () -> String = { "" }
    @ObservationIgnored weak var window: NSWindow? {
        didSet { if window !== oldValue { restartMonitor() } }
    }
    @ObservationIgnored var fileURL: URL? {
        didSet { if fileURL != oldValue { restartMonitor() } }
    }
    @ObservationIgnored private var monitor: DocumentFileMonitor?
    /// The preview's smooth scroll after an Outline click reports positions as it
    /// moves; the editor, already placed on the heading, ignores them until then.
    @ObservationIgnored private var ignorePreviewScrollUntil = Date.distantPast

    init(fileURL: URL?) {
        self.fileURL = fileURL
        layout = LayoutMemory.initialLayout(for: fileURL)
        SaveFlush.register(self)
    }

    func close() {
        monitor?.stop()
        monitor = nil
    }

    private func restartMonitor() {
        monitor?.stop()
        monitor = nil
        guard let window, let fileURL else { return }
        monitor = DocumentFileMonitor(url: fileURL, window: window)
    }

    // MARK: - Editor

    /// Creates the editor on first use. The window calls this whenever the layout
    /// shows the editor.
    @discardableResult
    func makeEditorIfNeeded() -> EditorController {
        if let editor { return editor }
        let created = EditorController(options: EditorSettings.currentOptions)
        created.onScroll = { [weak self] line in self?.editorScrolled(to: line) }
        created.onTextChange = { [weak self] text in
            self?.onEditorText(text)
            // SwiftUI doesn't reliably count an edit to a just-opened document (the
            // first change after opening left it "clean"), so make sure every edit
            // from the editor leaves the document marked edited.
            DispatchQueue.main.async { self?.ensureDocumentEdited() }
        }
        // The first keystroke of a burst marks the document edited at once, before its
        // text arrives, so quitting or closing inside the editor's debounce still
        // reviews (and so flushes and saves) the document.
        created.onDirty = { [weak self] in self?.ensureDocumentEdited() }
        created.load(text: documentText())
        editor = created
        return created
    }

    /// Pushes outside text (revert, reload after a change on disk) into the editor as
    /// one undoable edit. Text that came from the editor itself is ignored.
    func documentTextChanged(_ text: String) {
        guard let editor, text != editor.text else { return }
        editor.setText(text)
    }

    /// The text a print or export should use: the editor's latest when it exists.
    func currentText(fallback: String) -> String { editor?.text ?? fallback }

    func flushPendingEdits(completion: @escaping () -> Void) {
        guard let editor else {
            completion()
            return
        }
        editor.flushPendingEdits(completion: completion)
    }

    private func ensureDocumentEdited() {
        guard let window, let document = NSDocumentController.shared.document(for: window),
            !document.isDocumentEdited
        else { return }
        document.updateChangeCount(.changeDone)
    }

    var editorHasFocus: Bool { editor?.hasFocus ?? false }

    /// True while the editor holds a keystroke its document hasn't received yet.
    var hasPendingEdit: Bool { editor?.hasPendingEdit ?? false }

    // MARK: - Scroll sync

    // Each side suppresses the scroll events its own programmatic scrolls cause
    // (see `mdeditScrollToLine` / `scrollToLine` in the pages), so following the
    // other pane never bounces back.
    private func editorScrolled(to line: Double) {
        guard layout == .split else { return }
        preview.scrollToLine(line)
    }

    func previewScrolled(to line: Double) {
        guard layout == .split, let editor, Date() >= ignorePreviewScrollUntil else { return }
        editor.scrollToLine(line)
    }

    /// Outline click: the preview scrolls to the heading; when the editor is showing it
    /// jumps to the heading's source line and puts the cursor there.
    func selectHeading(_ id: String) {
        ignorePreviewScrollUntil = Date().addingTimeInterval(1.0)
        preview.scrollToHeading(id: id)
        guard layout.showsEditor else { return }
        preview.sourceLine(forHeading: id) { [weak self] line in
            guard let self, let line, self.layout.showsEditor, let editor = self.editor else {
                return
            }
            editor.scrollToLine(Double(line))
            editor.setCursorLine(line)
        }
    }

    // MARK: - Layout

    private func layoutChanged() {
        LayoutMemory.remember(layout, for: fileURL)
        if layout.showsEditor {
            let editor = makeEditorIfNeeded()
            // Let SwiftUI unhide the editor first, then give it the keyboard.
            DispatchQueue.main.async { editor.focus() }
        } else if let window, let editor, editor.hasFocus {
            // Never leave keystrokes going into an editor the user can't see.
            window.makeFirstResponder(nil)
        }
    }

    // MARK: - Commands

    /// ⌘F: the editor's search/replace when the editor has focus (or is all that's
    /// showing), otherwise Find in the preview.
    func find() {
        if let editor, layout == .edit || (layout.showsEditor && editor.hasFocus) {
            editor.openSearch()
        } else {
            openPreviewFind()
        }
    }

    /// ⌥⌘F: always the preview's Find, bringing the preview into view if needed.
    func openPreviewFind() {
        if !layout.showsPreview { layout = .split }
        previewFindRequest += 1
    }

    /// Format commands only ever act on a visible editor.
    func format(_ kind: EditorFormat) {
        guard layout.showsEditor else { return }
        makeEditorIfNeeded().format(kind)
    }
}

extension FocusedValues {
    @Entry var documentWindow: DocumentWindowModel?
}
