import MarkdownRenderKit
import SwiftUI

/// One document window: the rendered preview (mdview's viewer), plus — once the
/// window leaves the Preview layout — a CodeMirror editor beside or instead of it.
struct ContentView: View {
    @Binding var document: mdviewDocument
    let fileURL: URL?

    @AppStorage("customCSS") private var customCSS: String = ""
    @AppStorage(EditorSettings.Key.fontFamily) private var fontFamily = EditorSettings
        .defaultFontFamily
    @AppStorage(EditorSettings.Key.fontSize) private var fontSize = EditorSettings.defaultFontSize
    @AppStorage(EditorSettings.Key.lineNumbers) private var editorLineNumbers = false
    @AppStorage(EditorSettings.Key.lineWrapping) private var lineWrapping = true
    @AppStorage(EditorSettings.Key.splitFraction) private var splitFraction = 0.5
    @State private var model: DocumentWindowModel
    /// The Markdown the preview renders (image paths rewritten). Follows the document
    /// at once while viewing, and 150 ms after the last keystroke while editing.
    @State private var text: String = ""
    @State private var autoScrollMode: AutoScrollMode = .none
    @State private var showTOC: Bool = false
    @State private var showFind: Bool = false
    @State private var showLineNumbers: Bool = false
    @State private var findQuery: String = ""
    @State private var findResults: [FindResult] = []
    @State private var currentFindIndex: Int?
    @State private var tocItems: [TOCItem] = []
    @State private var activeHeadingChain: [String] = []
    @State private var hostWindow: NSWindow?
    @FocusState private var findFocused: Bool

    /// Pause after the last edit before the preview re-renders.
    private static let previewDebounce = Duration.milliseconds(150)

    init(document: Binding<mdviewDocument>, fileURL: URL?) {
        _document = document
        self.fileURL = fileURL
        _model = State(initialValue: DocumentWindowModel(fileURL: fileURL))
    }

    private var markdownController: MarkdownController { model.preview }
    private var baseDir: URL? { fileURL?.deletingLastPathComponent() }

    private var editorOptions: EditorOptions {
        EditorOptions(
            lineNumbers: editorLineNumbers, lineWrapping: lineWrapping, fontFamily: fontFamily,
            fontSize: fontSize)
    }

    var body: some View {
        receivingDocumentChanges(receivingViewCommands(receivingFindCommands(mainContent)))
            .focusedSceneValue(\.documentWindow, model)
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            ribbonBar
            HStack(spacing: 0) {
                if showFind {
                    FindResultsView(results: findResults, selectedIndex: $currentFindIndex) {
                        markdownController.scrollToMatch($0)
                        findFocused = true
                    }
                    .frame(width: 210)
                    Divider()
                }
                panes
                if showTOC {
                    Divider()
                    TOCView(
                        items: tocItems, activeChain: activeHeadingChain,
                        onSelect: { model.selectHeading($0) }
                    )
                    .frame(width: 220)
                }
            }
        }
        .frame(minWidth: 520, minHeight: 320)
        .background(
            WindowFrameSaver {
                hostWindow = $0
                model.window = $0
            }
        )
        .onAppear(perform: start)
        .onDisappear { model.close() }
        .onChange(of: text) { _, _ in
            // Marks are cleared when innerHTML is replaced; clear results to match
            if showFind { findResults = []; currentFindIndex = nil }
        }
    }

    private func start() {
        model.onEditorText = { document.text = $0 }
        model.documentText = { document.text }
        // A window that opens on the editor (a new document, or a file last left in
        // Edit / Split) puts the cursor there, ready to type.
        if model.layout.showsEditor { model.makeEditorIfNeeded().focus() }
        text = process(document.text)
    }

    /// The document changing (typing, revert, a reload after the file changed on disk)
    /// and the window's own settings changing.
    private func receivingDocumentChanges(_ content: some View) -> some View {
        content
            .onChange(of: document.text) { _, newText in
                // Text that didn't come from the editor is pushed into it.
                model.documentTextChanged(newText)
            }
            .task(id: document.text) {
                // Viewing renders at once (live reload, Tail Mode); while editing, the
                // preview waits for a pause in typing.
                if model.layout.showsEditor {
                    try? await Task.sleep(for: Self.previewDebounce)
                    guard !Task.isCancelled else { return }
                }
                text = process(document.text)
            }
            .onChange(of: editorOptions) { _, options in model.editor?.setOptions(options) }
            .onChange(of: fileURL) { _, url in model.fileURL = url }
            .onChange(of: model.previewFindRequest) { _, _ in
                showFind = true
                findFocused = true
            }
    }

    // MARK: - Panes

    /// The editor (once created) and the preview stay in the view hierarchy in every
    /// layout — a hidden pane is just collapsed to zero width — so the editor keeps
    /// its undo history and the Outline keeps working from the preview while editing
    /// full-width.
    private var panes: some View {
        GeometryReader { geo in
            let total = geo.size.width
            let editorWidth: CGFloat =
                switch model.layout {
                case .edit: total
                case .preview: 0
                case .split: (total * splitFraction).rounded()
                }
            HStack(spacing: 0) {
                if let editor = model.editor {
                    EditorView(controller: editor, isVisible: model.layout.showsEditor)
                        .frame(width: editorWidth)
                }
                if model.layout == .split {
                    SplitDivider(fraction: $splitFraction, totalWidth: total)
                }
                preview
                    .frame(maxWidth: .infinity)
                    .opacity(model.layout.showsPreview ? 1 : 0)
            }
        }
    }

    private var preview: some View {
        MarkdownView(
            markdown: text,
            controller: markdownController,
            autoScrollMode: autoScrollMode,
            customCSS: customCSS,
            showLineNumbers: showLineNumbers,
            baseDir: baseDir,
            onHeadingsUpdated: { tocItems = $0 },
            onActiveHeadingsChanged: { activeHeadingChain = $0 },
            onTopLineChanged: { model.previewScrolled(to: $0) },
            keepsSourceLineOnRender: model.layout.showsEditor
        )
        // The image scheme handler is bound to the folder when the WebView is made, so
        // a first save (Untitled → file) needs a fresh preview.
        .id(baseDir)
    }

    /// Find, outline and auto-scroll menu commands. Split out of `body`: as one modifier chain
    /// it exceeded the Swift type checker's time limit ("unable to type-check this expression").
    private func receivingFindCommands(_ content: some View) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .mdviewOpenFind)) { _ in
                guard isFrontDocument else { return }
                if !model.layout.showsPreview { model.layout = .split }
                showFind = true
                findFocused = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .mdviewCloseFind)) { _ in
                if isFrontDocument { closeFind() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .mdviewToggleLineNumbers)) { _ in
                showLineNumbers.toggle()
            }
            .onReceive(NotificationCenter.default.publisher(for: .mdviewShowCSS)) { _ in
                showDocumentCSS()
            }
            .onReceive(NotificationCenter.default.publisher(for: .mdviewToggleJumpToNew)) { _ in
                autoScrollMode = autoScrollMode == .firstNew ? .none : .firstNew
            }
            .onReceive(NotificationCenter.default.publisher(for: .mdviewToggleTail)) { _ in
                autoScrollMode = autoScrollMode == .tail ? .none : .tail
            }
            .onReceive(NotificationCenter.default.publisher(for: .mdviewToggleOutline)) { _ in
                showTOC.toggle()
            }
    }

    /// Zoom, print, export and panel menu commands (see `receivingFindCommands`).
    private func receivingViewCommands(_ content: some View) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .mdviewShowKeyboardShortcuts)) {
                _ in
                ShortcutsPanelController.shared.show()
            }
            .onReceive(NotificationCenter.default.publisher(for: .mdviewZoomIn)) { _ in
                markdownController.zoomIn()
            }
            .onReceive(NotificationCenter.default.publisher(for: .mdviewZoomOut)) { _ in
                markdownController.zoomOut()
            }
            .onReceive(NotificationCenter.default.publisher(for: .mdviewResetZoom)) { _ in
                markdownController.resetZoom()
            }
            .onReceive(NotificationCenter.default.publisher(for: .mdviewPrint)) { _ in
                if isFrontDocument { openPrintPreview(intent: .printing) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .mdviewExportPDF)) { _ in
                if isFrontDocument { openPrintPreview(intent: .exportPDF) }
            }
    }

    // MARK: - Ribbon

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    private var ribbonBar: some View {
        ZStack {
            // Left + right anchored buttons
            HStack(spacing: 4) {
                Picker("Layout", selection: $model.layout) {
                    ForEach(EditorLayout.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .fixedSize()
                .help("Edit ⌘1 · Split ⌘2 · Preview ⌘3")
                .padding(.trailing, 4)
                RibbonButton(icon: "arrow.clockwise", label: "Reload", isActive: false) {
                    reloadFile()
                }
                RibbonButton(
                    icon: "arrow.up.to.line", label: "Jump to New",
                    isActive: autoScrollMode == .firstNew
                ) {
                    autoScrollMode = autoScrollMode == .firstNew ? .none : .firstNew
                }
                RibbonButton(
                    icon: "arrow.down.to.line", label: "Tail", isActive: autoScrollMode == .tail
                ) {
                    autoScrollMode = autoScrollMode == .tail ? .none : .tail
                }
                RibbonButton(icon: "list.number", label: "Line Numbers", isActive: showLineNumbers)
                {
                    showLineNumbers.toggle()
                }
                Spacer()
                RibbonButton(icon: "printer", label: "Print", isActive: false) {
                    openPrintPreview(intent: .printing)
                }
                RibbonButton(icon: "arrow.down.doc", label: "PDF", isActive: false) {
                    openPrintPreview(intent: .exportPDF)
                }
                RibbonButton(icon: "doc.plaintext", label: "Show CSS", isActive: false) {
                    showDocumentCSS()
                }
                RibbonButton(icon: "sidebar.right", label: "Outline", isActive: showTOC) {
                    showTOC.toggle()
                }
                Button {
                    SettingsPanelController.shared.show()
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .help("Settings")

                Text("v\(appVersion)")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 2)
                    .help("mdview version")
            }

            // Search field centred in the available space
            if showFind {
                findBar.frame(maxWidth: 260)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(Divider(), alignment: .bottom)
    }

    private var findBar: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 11))
            TextField("Find…", text: $findQuery)
                .textFieldStyle(.plain)
                .font(.caption)
                .focused($findFocused)
                .onChange(of: findQuery) { _, query in performFind(query) }
                .onKeyPress(.escape) {
                    closeFind(); return .handled
                }
                .onKeyPress(.downArrow) {
                    navigateFind(delta: 1); return .handled
                }
                .onKeyPress(.upArrow) {
                    navigateFind(delta: -1); return .handled
                }
                .onSubmit { navigateFind(delta: 1) }
            if !findQuery.isEmpty {
                Button {
                    findQuery = ""; findResults = []; markdownController.clearFind()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(NSColor.textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6).stroke(Color.accentColor.opacity(0.5), lineWidth: 1))
    }

    // MARK: - Find logic

    private func navigateFind(delta: Int) {
        guard !findResults.isEmpty else { return }
        let count = findResults.count
        let next: Int
        if let current = currentFindIndex {
            next = (current + delta + count) % count
        } else {
            next = delta > 0 ? 0 : count - 1
        }
        currentFindIndex = next
        markdownController.scrollToMatch(findResults[next].id)
    }

    private func performFind(_ query: String) {
        guard !query.isEmpty else {
            findResults = []
            markdownController.clearFind()
            return
        }
        markdownController.findText(query) { findResults = $0 }
    }

    private func closeFind() {
        showFind = false
        findFocused = false
        findQuery = ""
        findResults = []
        currentFindIndex = nil
        markdownController.clearFind()
    }

    /// Reload from disk. A document with unsaved edits asks first (AppKit's standard
    /// "Revert to Saved" confirmation), so the button can never silently discard work.
    private func reloadFile() {
        guard let window = hostWindow,
            let doc = NSDocumentController.shared.document(for: window),
            let url = doc.fileURL, let type = doc.fileType
        else { return }
        if doc.isDocumentEdited {
            doc.revertToSaved(nil)
        } else {
            try? doc.revert(toContentsOf: url, ofType: type)
        }
    }

    // Menu commands broadcast to every open document; only the frontmost one
    // should act on them, or a background tab would hijack the shared panel.
    // The tracker answers this without depending on NSApp.keyWindow, which is the
    // Print Preview panel while it has focus and nil whenever the app is inactive.
    private var isFrontDocument: Bool {
        FrontDocumentTracker.shared.isFront(hostWindow)
    }

    private func openPrintPreview(intent: PrintPreviewIntent) {
        PrintPreviewController.shared.show(
            source: PrintSource(
                markdown: process(model.currentText(fallback: document.text)),
                baseDir: baseDir,
                customCSS: customCSS,
                showLineNumbers: showLineNumbers,
                title: fileURL?.lastPathComponent ?? "Untitled"
            ),
            intent: intent)
    }

    private func showDocumentCSS() {
        markdownController.getDocumentCSS { css in
            CSSPanelController.shared.show(css: css)
        }
    }

    // MARK: - Markdown processing

    private func process(_ markdown: String) -> String {
        // Image bytes are served lazily by ImageSchemeHandler; here we only rewrite
        // relative paths to the custom scheme so the WebView requests them.
        guard fileURL != nil else { return markdown }
        return MarkdownImagePaths.rewrite(markdown)
    }
}

// MARK: - Ribbon button

private struct RibbonButton: View {
    let icon: String
    let label: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .font(.caption)
                .foregroundStyle(isActive ? Color.accentColor : Color.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isActive ? Color.accentColor.opacity(0.12) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .help(label)
    }
}

// Hooks into the underlying NSWindow to enable automatic frame (size + position)
// persistence. macOS saves the frame to UserDefaults under the autosave name and
// restores it on the next launch.
// Reports its window whenever the view actually joins one.
//
// Sampling `window` once on the next runloop turn is a race: if the view is not in
// a window yet, the sample is nil and never retried. That left the document unable
// to tell whether it was frontmost, so every Print / Export menu command was
// silently dropped for the rest of that launch — and the frame autosave name went
// unset too, quietly losing window-position persistence.
private final class WindowReportingView: NSView {
    var onWindow: (NSWindow?) -> Void = { _ in }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        let joined = window
        joined?.setFrameAutosaveName("mdviewDocumentWindow")
        FrontDocumentTracker.shared.register(joined)
        // Out of the layout pass before touching SwiftUI state.
        DispatchQueue.main.async { [onWindow] in onWindow(joined) }
    }
}

private struct WindowFrameSaver: NSViewRepresentable {
    var onWindow: (NSWindow?) -> Void = { _ in }

    func makeNSView(context: Context) -> WindowReportingView {
        let view = WindowReportingView()
        view.onWindow = onWindow
        return view
    }
    func updateNSView(_ nsView: WindowReportingView, context: Context) {
        nsView.onWindow = onWindow
    }
}

/// Draggable divider between the editor and preview in Split layout.
private struct SplitDivider: View {
    @Binding var fraction: Double
    let totalWidth: CGFloat
    @State private var startFraction: Double?

    private static let range = 0.15...0.85

    var body: some View {
        Rectangle()
            .fill(Color(NSColor.separatorColor))
            .frame(width: 1)
            .padding(.horizontal, 3)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let start = startFraction ?? fraction
                        startFraction = start
                        guard totalWidth > 0 else { return }
                        let proposed = start + Double(value.translation.width / totalWidth)
                        fraction = min(max(proposed, Self.range.lowerBound), Self.range.upperBound)
                    }
                    .onEnded { _ in startFraction = nil }
            )
    }
}
