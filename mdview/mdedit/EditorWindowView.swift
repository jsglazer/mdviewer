import MarkdownRenderKit
import SwiftUI

/// One document window: CodeMirror editor on the left, live preview on the right,
/// with the preview's Find results and Outline as optional side panels.
struct EditorWindowView: View {
    @Binding var document: mdeditDocument
    let fileURL: URL?

    @AppStorage(EditorSettings.Key.customCSS, store: EditorSettings.mdviewDefaults)
    private var customCSS = ""
    @AppStorage(EditorSettings.Key.fontFamily) private var fontFamily = EditorSettings
        .defaultFontFamily
    @AppStorage(EditorSettings.Key.fontSize) private var fontSize = EditorSettings.defaultFontSize
    @AppStorage(EditorSettings.Key.lineNumbers) private var lineNumbers = false
    @AppStorage(EditorSettings.Key.lineWrapping) private var lineWrapping = true
    @AppStorage(EditorSettings.Key.splitFraction) private var splitFraction = 0.5

    @State private var model: EditorWindowModel
    @State private var previewText = ""
    @FocusState private var findFocused: Bool

    /// Pause after the last edit before the preview re-renders.
    private static let previewDebounce = Duration.milliseconds(150)

    init(document: Binding<mdeditDocument>, fileURL: URL?) {
        _document = document
        self.fileURL = fileURL
        let defaults = UserDefaults.standard
        let size = defaults.double(forKey: EditorSettings.Key.fontSize)
        let options = EditorOptions(
            lineNumbers: defaults.bool(forKey: EditorSettings.Key.lineNumbers),
            lineWrapping: defaults.object(forKey: EditorSettings.Key.lineWrapping) as? Bool
                ?? true,
            fontFamily: defaults.string(forKey: EditorSettings.Key.fontFamily)
                ?? EditorSettings.defaultFontFamily,
            fontSize: size > 0 ? size : EditorSettings.defaultFontSize)
        _model = State(initialValue: EditorWindowModel(options: options))
    }

    private var baseDir: URL? { fileURL?.deletingLastPathComponent() }

    private var editorOptions: EditorOptions {
        EditorOptions(
            lineNumbers: lineNumbers, lineWrapping: lineWrapping, fontFamily: fontFamily,
            fontSize: fontSize)
    }

    var body: some View {
        VStack(spacing: 0) {
            if model.showPreviewFind { findBar }
            HStack(spacing: 0) {
                if model.showPreviewFind {
                    FindResultsView(
                        results: model.findResults,
                        selectedIndex: Binding(
                            get: { model.currentFindIndex }, set: { model.currentFindIndex = $0 })
                    ) {
                        model.preview.scrollToMatch($0)
                        findFocused = true
                    }
                    .frame(width: 210)
                    Divider()
                }
                panes
                if model.showOutline {
                    Divider()
                    TOCView(
                        items: model.tocItems, activeChain: model.activeHeadingChain,
                        onSelect: { model.selectHeading($0) }
                    )
                    .frame(width: 220)
                }
            }
        }
        .frame(minWidth: 640, minHeight: 360)
        .toolbar { toolbarContent }
        .focusedSceneValue(\.editorWindow, model)
        .background(WindowAccessor { model.window = $0 })
        .onAppear(perform: start)
        .onDisappear { model.close() }
        .onChange(of: document.text) { _, newText in
            // Text that didn't come from the editor (revert, a reload after the file
            // changed on disk) is pushed into it as one undoable edit.
            if newText != model.editor.text { model.editor.setText(newText) }
        }
        .task(id: document.text) {
            try? await Task.sleep(for: Self.previewDebounce)
            guard !Task.isCancelled else { return }
            previewText = EditorWindowModel.processed(document.text, baseDir: baseDir)
        }
        .onChange(of: previewText) { _, _ in model.previewRerendered() }
        .onChange(of: editorOptions) { _, options in model.editor.setOptions(options) }
        .onChange(of: customCSS) { _, css in model.customCSS = css }
        .onChange(of: fileURL) { _, url in updatePrintInfo(url) }
        .onReceive(NotificationCenter.default.publisher(for: .mdviewOpenFind)) { _ in
            if model.window?.isKeyWindow == true { model.openPreviewFind() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .mdviewCloseFind)) { _ in
            if model.window?.isKeyWindow == true { model.closeFind() }
        }
    }

    private func start() {
        model.editor.onTextChange = { document.text = $0 }
        model.editor.load(text: document.text)
        model.customCSS = customCSS
        updatePrintInfo(fileURL)
        previewText = EditorWindowModel.processed(document.text, baseDir: baseDir)
    }

    private func updatePrintInfo(_ url: URL?) {
        model.fileURL = url
        model.printTitle = url?.lastPathComponent ?? "Untitled"
        model.printBaseDir = url?.deletingLastPathComponent()
    }

    // MARK: - Panes

    /// Both panes stay in the view hierarchy in every layout — a hidden pane is just
    /// collapsed to zero width — so the editor keeps its state and the Outline keeps
    /// working from the (unseen) preview while editing full-width.
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
                EditorView(controller: model.editor, isVisible: model.layout.showsEditor)
                    .frame(width: editorWidth)
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
            markdown: previewText,
            controller: model.preview,
            autoScrollMode: .none,
            customCSS: customCSS,
            showLineNumbers: model.previewLineNumbers,
            baseDir: baseDir,
            onHeadingsUpdated: { model.tocItems = $0 },
            onActiveHeadingsChanged: { model.activeHeadingChain = $0 },
            onTopLineChanged: { model.previewScrolled(to: $0) },
            keepsSourceLineOnRender: true
        )
        // The image scheme handler is bound to the folder when the WebView is made, so
        // a first save (Untitled → file) needs a fresh preview.
        .id(baseDir)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Picker("Layout", selection: $model.layout) {
                ForEach(EditorLayout.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .help("Edit ⌘1 · Split ⌘2 · Preview ⌘3")
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                model.printDocument(.printing)
            } label: {
                Label("Print", systemImage: "printer")
            }
            .help("Print Preview (⌘P)")
            Button {
                model.cycleOutline()
            } label: {
                Label("Outline", systemImage: "sidebar.right")
            }
            .help("Toggle Outline (⇧⌘O)")
        }
    }

    // MARK: - Preview find bar

    private var findBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 11))
            TextField("Find in preview…", text: $model.findQuery)
                .textFieldStyle(.plain)
                .font(.callout)
                .focused($findFocused)
                .onChange(of: model.findQuery) { _, query in model.performFind(query) }
                .onKeyPress(.escape) {
                    model.closeFind()
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    model.navigateFind(delta: 1)
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    model.navigateFind(delta: -1)
                    return .handled
                }
                .onSubmit { model.navigateFind(delta: 1) }
            Button("Done") { model.closeFind() }
                .controlSize(.small)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(Divider(), alignment: .bottom)
        .onAppear { findFocused = true }
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

/// Reports the hosting NSWindow once the view joins one.
private struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow?) -> Void

    func makeNSView(context: Context) -> WindowReportingView {
        let view = WindowReportingView()
        view.onWindow = onWindow
        return view
    }

    func updateNSView(_ nsView: WindowReportingView, context: Context) {
        nsView.onWindow = onWindow
    }

    final class WindowReportingView: NSView {
        var onWindow: (NSWindow?) -> Void = { _ in }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            let joined = window
            DispatchQueue.main.async { [onWindow] in onWindow(joined) }
        }
    }
}
