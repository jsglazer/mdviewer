import AppKit
import SwiftUI
import WebKit

/// Appearance and behaviour settings pushed into the CodeMirror editor.
public struct EditorOptions: Equatable {
    public var lineNumbers: Bool
    public var lineWrapping: Bool
    /// A CSS font-family list, e.g. `ui-monospace, Menlo, monospace`.
    public var fontFamily: String
    public var fontSize: Double

    public init(lineNumbers: Bool, lineWrapping: Bool, fontFamily: String, fontSize: Double) {
        self.lineNumbers = lineNumbers
        self.lineWrapping = lineWrapping
        self.fontFamily = fontFamily
        self.fontSize = fontSize
    }

    fileprivate var json: String {
        let dict: [String: Any] = [
            "lineNumbers": lineNumbers, "lineWrapping": lineWrapping,
            "fontFamily": fontFamily, "fontSize": fontSize,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
            let string = String(data: data, encoding: .utf8)
        else { return "{}" }
        return string
    }
}

/// Markdown formatting commands offered by the editor (and its Format menu).
public enum EditorFormat: String {
    case bold, italic, link, highlight, comment
}

/// Owns one CodeMirror editor WebView for the lifetime of a document window.
///
/// The WebView lives here rather than in the SwiftUI view so that switching between
/// Edit / Split / Preview layouts never tears it down — the editor's undo history,
/// selection and scroll position survive every layout change.
public final class EditorController: NSObject {
    /// Called (debounced ~100 ms in the page) with the full text after user edits.
    public var onTextChange: (String) -> Void = { _ in }
    /// Called with the fractional 0-based source line at the top of the editor.
    public var onScroll: (Double) -> Void = { _ in }
    /// Called with the 0-based line of the main cursor.
    public var onCursorLine: (Int) -> Void = { _ in }
    /// Called at once on the first user edit after a quiet period, before the debounced
    /// `onTextChange`, so the owner can mark its document edited without waiting.
    public var onDirty: () -> Void = {}

    public let webView: WKWebView
    /// The text both sides agree on: the last text received from the page or sent to it.
    public private(set) var text: String = ""
    /// True from the first keystroke of a burst until its text has reached Swift.
    public private(set) var hasPendingEdit = false
    private var isReady = false
    /// A focus request that arrived before the page loaded or the view joined a window.
    private var wantsFocus = false
    private var options: EditorOptions

    public init(options: EditorOptions) {
        self.options = options
        let config = WKWebViewConfiguration()
        webView = EditorWebView(frame: .zero, configuration: config)
        super.init()
        config.userContentController.add(WeakEditorHandler(self), name: "mdedit")
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
        if let page = RenderResources.url(forResource: "editor", withExtension: "html"),
            let dir = RenderResources.directoryURL
        {
            webView.loadFileURL(page, allowingReadAccessTo: dir)
        }
    }

    // MARK: - Swift → editor

    /// Loads text as the starting content (fresh undo history). Use once per document.
    public func load(text newText: String) {
        text = newText
        guard isReady, let json = Self.jsString(newText) else { return }
        webView.evaluateJavaScript(
            "window.mdeditInit(\(json), \(options.json))", completionHandler: nil)
    }

    /// Replaces the text from outside the editor (revert, external change) as a single
    /// undoable edit, keeping the cursor and scroll position where possible.
    public func setText(_ newText: String) {
        guard newText != text else { return }
        text = newText
        guard isReady, let json = Self.jsString(newText) else { return }
        webView.evaluateJavaScript("window.mdeditSetText(\(json))", completionHandler: nil)
    }

    public func setOptions(_ newOptions: EditorOptions) {
        guard newOptions != options else { return }
        options = newOptions
        guard isReady else { return }
        webView.evaluateJavaScript(
            "window.mdeditSetOptions(\(newOptions.json))", completionHandler: nil)
    }

    public func scrollToLine(_ line: Double) {
        guard isReady, line.isFinite else { return }
        webView.evaluateJavaScript("window.mdeditScrollToLine(\(line))", completionHandler: nil)
    }

    public func setCursorLine(_ line: Int) {
        guard isReady else { return }
        webView.evaluateJavaScript("window.mdeditSetCursorLine(\(line))", completionHandler: nil)
    }

    public func format(_ kind: EditorFormat) { run("window.mdeditFormat('\(kind.rawValue)')") }
    public func undo() { run("window.mdeditUndo()") }
    public func redo() { run("window.mdeditRedo()") }
    public func openSearch() {
        focus()
        run("window.mdeditOpenSearch()")
    }

    /// Gives the editor keyboard focus. Asked for before the editor is ready (it was
    /// just created and hasn't loaded or joined a window yet), it happens once it is.
    public func focus() {
        guard isReady, let window = webView.window else {
            wantsFocus = true
            return
        }
        wantsFocus = false
        window.makeFirstResponder(webView)
        run("window.mdeditFocus()")
    }

    /// Pushes any edit still inside the page's debounce window to `onTextChange` now.
    public func flushPendingEdits() { run("window.mdeditFlush && window.mdeditFlush()") }

    /// Delivers any edit still inside the page's debounce window through `onTextChange`,
    /// then calls `completion` on the main thread. Waits for the real round trip, so
    /// a save that runs after `completion` always sees the editor's latest text.
    public func flushPendingEdits(completion: @escaping () -> Void) {
        guard isReady else { completion(); return }
        webView.evaluateJavaScript("window.mdeditTakePending()") { [weak self] result, _ in
            if let self {
                self.hasPendingEdit = false
                if let newText = result as? String, newText != self.text {
                    self.text = newText
                    self.onTextChange(newText)
                }
            }
            completion()
        }
    }

    /// True when the editor WebView (or something inside it) has keyboard focus.
    public var hasFocus: Bool {
        guard let responder = webView.window?.firstResponder as? NSView else { return false }
        return responder === webView || responder.isDescendant(of: webView)
    }

    private func run(_ script: String) {
        guard isReady else { return }
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    // MARK: - Editor → Swift

    fileprivate func handle(_ message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String
        else { return }
        switch type {
        case "ready":
            pageBecameReady()
        case "dirty":
            hasPendingEdit = true
            onDirty()
        case "change":
            receiveChange(body["text"] as? String)
        case "scroll":
            if let line = (body["line"] as? NSNumber)?.doubleValue { onScroll(line) }
        case "cursor":
            if let line = (body["line"] as? NSNumber)?.intValue { onCursorLine(line) }
        default:
            break
        }
    }

    private func pageBecameReady() {
        isReady = true
        load(text: text)
        if wantsFocus { DispatchQueue.main.async { [weak self] in self?.focus() } }
    }

    private func receiveChange(_ newText: String?) {
        hasPendingEdit = false
        guard let newText, newText != text else { return }
        text = newText
        onTextChange(newText)
    }

    private static func jsString(_ value: String) -> String? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

extension EditorController: WKNavigationDelegate {
    // Keep the editor page pinned: links typed into the text are never navigated.
    public func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        let url = navigationAction.request.url
        let allowed = url?.isFileURL == true && url?.lastPathComponent == "editor.html"
        decisionHandler(allowed ? .allow : .cancel)
    }
}

/// Avoids the WKUserContentController → EditorController retain cycle.
private final class WeakEditorHandler: NSObject, WKScriptMessageHandler {
    weak var target: EditorController?
    init(_ target: EditorController) { self.target = target }
    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage)
    {
        target?.handle(message)
    }
}

/// Routes the editing key equivalents straight to CodeMirror while the editor has
/// focus, so the app's menus (whose Undo would otherwise act on the document's
/// whole-text undo stack) never see them.
private final class EditorWebView: WKWebView {
    /// WebKit registers an undo step for every native text edit (the editor's own
    /// contenteditable, the search panel's fields) on the responder chain's undo
    /// manager — in a document window, the document's. That marked the document
    /// edited when the user merely typed a search term. CodeMirror keeps its own
    /// history, so WebKit's steps go to a private manager that records nothing.
    private let privateUndoManager: UndoManager = {
        let manager = UndoManager()
        manager.disableUndoRegistration()
        return manager
    }()
    override var undoManager: UndoManager? { privateUndoManager }

    private static let commands: [String: String] = [
        "z": "window.mdeditUndo()",
        "Z": "window.mdeditRedo()",
        "b": "window.mdeditFormat('bold')",
        "i": "window.mdeditFormat('italic')",
        "k": "window.mdeditFormat('link')",
        "H": "window.mdeditFormat('highlight')",
        "/": "window.mdeditFormat('comment')",
    ]

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard event.type == .keyDown,
            flags == .command || flags == [.command, .shift],
            isFirstResponderInside,
            var key = event.charactersIgnoringModifiers
        else { return super.performKeyEquivalent(with: event) }
        if flags.contains(.shift) { key = key.uppercased() }
        guard let script = Self.commands[key] else {
            return super.performKeyEquivalent(with: event)
        }
        evaluateJavaScript(script, completionHandler: nil)
        return true
    }

    private var isFirstResponderInside: Bool {
        guard let responder = window?.firstResponder as? NSView else { return false }
        return responder === self || responder.isDescendant(of: self)
    }
}

/// SwiftUI host for an `EditorController`'s WebView.
public struct EditorView: NSViewRepresentable {
    let controller: EditorController
    let isVisible: Bool

    /// `isVisible: false` hides the WebView (it can then never hold keyboard focus)
    /// without tearing the editor down.
    public init(controller: EditorController, isVisible: Bool = true) {
        self.controller = controller
        self.isVisible = isVisible
    }

    public func makeNSView(context: Context) -> WKWebView { controller.webView }
    public func updateNSView(_ nsView: WKWebView, context: Context) {
        nsView.isHidden = !isVisible
    }
}
