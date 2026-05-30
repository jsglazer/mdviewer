import SwiftUI

struct ContentView: View {
    let document: mdviewDocument
    let fileURL: URL?

    @AppStorage("customCSS") private var customCSS: String = ""
    @State private var text: String = ""
    @State private var watcher: FileWatcher?
    @State private var autoScrollMode: AutoScrollMode = .none
    @State private var showTOC: Bool = false
    @State private var showFind: Bool = false
    @State private var showLineNumbers: Bool = false
    @State private var findQuery: String = ""
    @State private var findResults: [FindResult] = []
    @State private var currentFindIndex: Int? = nil
    @State private var tocItems: [TOCItem] = []
    @State private var activeHeadingChain: [String] = []
    @State private var markdownController = MarkdownController()
    @FocusState private var findFocused: Bool

    var body: some View {
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
                MarkdownView(
                    markdown: text,
                    controller: markdownController,
                    autoScrollMode: autoScrollMode,
                    customCSS: customCSS,
                    showLineNumbers: showLineNumbers,
                    onHeadingsUpdated: { tocItems = $0 },
                    onActiveHeadingsChanged: { activeHeadingChain = $0 }
                )
                if showTOC {
                    Divider()
                    TOCView(items: tocItems, activeChain: activeHeadingChain, onSelect: { markdownController.scrollToHeading(id: $0) })
                        .frame(width: 220)
                }
            }
        }
        .frame(minWidth: 520, minHeight: 320)
        .background(WindowFrameSaver())
        .onAppear {
            text = process(document.text)
            if let url = fileURL {
                watcher = FileWatcher(url: url) { updated in
                    text = process(updated)
                }
            }
        }
        .onDisappear { watcher = nil }
        .onChange(of: text) { _, _ in
            // Marks are cleared when innerHTML is replaced; clear results to match
            if showFind { findResults = []; currentFindIndex = nil }
        }
        .onReceive(NotificationCenter.default.publisher(for: .mdviewOpenFind)) { _ in
            showFind = true
            findFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("mdviewCloseFind"))) { _ in
            closeFind()
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
        .onReceive(NotificationCenter.default.publisher(for: .mdviewShowKeyboardShortcuts)) { _ in
            ShortcutsPanelController.shared.show()
        }
    }

    // MARK: - Ribbon

    private var ribbonBar: some View {
        ZStack {
            // Left + right anchored buttons
            HStack(spacing: 4) {
                RibbonButton(icon: "arrow.up.to.line",   label: "Jump to New",   isActive: autoScrollMode == .firstNew) {
                    autoScrollMode = autoScrollMode == .firstNew ? .none : .firstNew
                }
                RibbonButton(icon: "arrow.down.to.line", label: "Tail",          isActive: autoScrollMode == .tail) {
                    autoScrollMode = autoScrollMode == .tail ? .none : .tail
                }
                RibbonButton(icon: "list.number",        label: "Line Numbers",  isActive: showLineNumbers) {
                    showLineNumbers.toggle()
                }
                Spacer()
                RibbonButton(icon: "doc.plaintext",      label: "Show CSS",      isActive: false) {
                    showDocumentCSS()
                }
                RibbonButton(icon: "sidebar.right",      label: "Outline",       isActive: showTOC) {
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
                .onChange(of: findQuery) { _, q in performFind(q) }
                .onKeyPress(.escape) { closeFind(); return .handled }
                .onKeyPress(.downArrow) { navigateFind(delta: 1); return .handled }
                .onKeyPress(.upArrow)   { navigateFind(delta: -1); return .handled }
                .onSubmit { navigateFind(delta: 1) }
            if !findQuery.isEmpty {
                Button { findQuery = ""; findResults = []; markdownController.clearFind() } label: {
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
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.accentColor.opacity(0.5), lineWidth: 1))
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

    private func showDocumentCSS() {
        markdownController.getDocumentCSS { css in
            CSSPanelController.shared.show(css: css)
        }
    }

    // MARK: - Markdown processing

    private func process(_ markdown: String) -> String {
        guard let baseDir = fileURL?.deletingLastPathComponent() else { return markdown }
        return inlineImages(in: markdown, baseDir: baseDir)
    }

    private func inlineImages(in markdown: String, baseDir: URL) -> String {
        let pattern = try! NSRegularExpression(pattern: #"(!\[[^\]]*\]\()([^)\s"]+)"#)
        let mutableString = NSMutableString(string: markdown)
        var offset = 0
        let matches = pattern.matches(in: markdown, range: NSRange(markdown.startIndex..., in: markdown))
        for match in matches {
            let nsPathRange = match.range(at: 2)
            guard nsPathRange.location != NSNotFound,
                  let pathRange = Range(nsPathRange, in: markdown) else { continue }
            let path = String(markdown[pathRange])
            guard !path.hasPrefix("http"), !path.hasPrefix("data:"),
                  !path.hasPrefix("/"), !path.hasPrefix("file:") else { continue }
            let imageURL = baseDir.appendingPathComponent(path)
            guard let data = try? Data(contentsOf: imageURL) else { continue }
            let ext = imageURL.pathExtension.lowercased()
            let mime: String
            switch ext {
            case "png":        mime = "image/png"
            case "jpg","jpeg": mime = "image/jpeg"
            case "gif":        mime = "image/gif"
            case "svg":        mime = "image/svg+xml"
            case "webp":       mime = "image/webp"
            default:           mime = "image/\(ext)"
            }
            let dataURI = "data:\(mime);base64,\(data.base64EncodedString())"
            let adjustedRange = NSRange(location: nsPathRange.location + offset, length: nsPathRange.length)
            mutableString.replaceCharacters(in: adjustedRange, with: dataURI)
            offset += dataURI.utf16.count - path.utf16.count
        }
        return mutableString as String
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
private struct WindowFrameSaver: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async {
            v.window?.setFrameAutosaveName("mdviewDocumentWindow")
        }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

#Preview {
    ContentView(document: mdviewDocument(), fileURL: nil)
}
