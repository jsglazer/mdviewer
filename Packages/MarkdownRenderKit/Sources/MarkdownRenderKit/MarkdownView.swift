import SwiftUI
import WebKit
import AppKit

// WKWebView subclass that intercepts keyboard shortcuts before WebKit handles them.
// CMD+Left/Right would otherwise trigger browser back/forward history navigation.
private class MarkdownWebView: WKWebView {
    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        // Escape (keyCode 53) — close find bar if open
        if event.keyCode == 53 {
            NotificationCenter.default.post(name: .mdviewCloseFind, object: nil)
            return
        }

        guard event.modifierFlags.contains(.command) else {
            super.keyDown(with: event)
            return
        }

        // CMD + Arrow: document navigation
        switch event.specialKey {
        case .some(.upArrow):
            evaluateJavaScript("window.scrollToTop()", completionHandler: nil); return
        case .some(.downArrow):
            evaluateJavaScript("window.scrollToEnd()", completionHandler: nil); return
        case .some(.leftArrow):
            evaluateJavaScript("window.scrollPageUp()", completionHandler: nil); return
        case .some(.rightArrow):
            evaluateJavaScript("window.scrollPageDown()", completionHandler: nil); return
        default: break
        }

        // CMD-F: open app Find (prevents WebKit's built-in find panel)
        if event.characters?.lowercased() == "f" {
            NotificationCenter.default.post(name: .mdviewOpenFind, object: nil)
            return
        }

        super.keyDown(with: event)
    }
}

// Serves images referenced by the document via a custom scheme, streaming the
// file from the document's directory rather than embedding base64 in the source.
public final class ImageSchemeHandler: NSObject, WKURLSchemeHandler {
    public static let scheme = "mdview-img"
    private let baseDir: URL

    public init(baseDir: URL) { self.baseDir = baseDir }

    public static func mime(forExtension ext: String) -> String {
        switch ext.lowercased() {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "svg": return "image/svg+xml"
        case "webp": return "image/webp"
        case "bmp": return "image/bmp"
        case "": return "application/octet-stream"
        default: return "image/\(ext.lowercased())"
        }
    }

    public func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        // URL form: mdview-img://local/<percent-encoded relative path>
        guard let url = task.request.url else {
            task.didFailWithError(URLError(.badURL)); return
        }
        let rawPath = url.path.hasPrefix("/") ? String(url.path.dropFirst()) : url.path
        let relPath = rawPath.removingPercentEncoding ?? rawPath
        let fileURL = baseDir.appendingPathComponent(relPath).standardized
        // Guard against path traversal: resolve "../" sequences and verify the result
        // stays inside the document directory before reading any data.
        let basePath = baseDir.standardized.path
        guard fileURL.path == basePath || fileURL.path.hasPrefix(basePath + "/") else {
            task.didFailWithError(URLError(.badURL)); return
        }
        guard let data = try? Data(contentsOf: fileURL) else {
            task.didFailWithError(URLError(.fileDoesNotExist)); return
        }
        let mime = Self.mime(forExtension: fileURL.pathExtension)
        let response = URLResponse(
            url: url, mimeType: mime,
            expectedContentLength: data.count, textEncodingName: nil)
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    public func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}

public struct TOCItem: Identifiable, Equatable {
    public let id: String
    public let level: Int
    public let text: String

    public init(id: String, level: Int, text: String) {
        self.id = id
        self.level = level
        self.text = text
    }
}

public struct FindResult: Identifiable, Equatable {
    public let id: Int  // match index; used as scroll target
    public let before: String
    public let match: String
    public let after: String

    public init(id: Int, before: String, match: String, after: String) {
        self.id = id
        self.before = before
        self.match = match
        self.after = after
    }
}

public enum AutoScrollMode: Equatable {
    case none, firstNew, tail
}

public final class MarkdownController {
    weak var coordinator: MarkdownView.Coordinator?

    public init() {}

    public func scrollToHeading(id: String) { coordinator?.doScrollToHeading(id) }
    public func findText(_ query: String, completion: @escaping ([FindResult]) -> Void) {
        coordinator?.doFindText(query, completion: completion)
    }
    public func clearFind() { coordinator?.doClearFind() }
    public func scrollToMatch(_ index: Int) { coordinator?.doScrollToMatch(index) }
    public func setLineNumbers(_ enabled: Bool) { coordinator?.doSetLineNumbers(enabled) }
    public func getDocumentCSS(completion: @escaping (String) -> Void) {
        coordinator?.doGetDocumentCSS(completion: completion)
    }
    /// Scrolls the preview so the (fractional, 0-based) source line is at the top.
    public func scrollToLine(_ line: Double) { coordinator?.doScrollToLine(line) }
    /// Looks up the 0-based source line of a heading (nil if unknown).
    public func sourceLine(forHeading id: String, completion: @escaping (Int?) -> Void) {
        guard let coordinator else { completion(nil); return }
        coordinator.doSourceLine(forHeading: id, completion: completion)
    }
    public func zoomIn() { coordinator?.doZoomIn() }
    public func zoomOut() { coordinator?.doZoomOut() }
    public func resetZoom() { coordinator?.doResetZoom() }
}

// Avoids a WKUserContentController → Coordinator retain cycle.
private class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    weak var target: MarkdownView.Coordinator?
    init(_ target: MarkdownView.Coordinator) { self.target = target }
    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage)
    {
        target?.handleScriptMessage(message)
    }
}

public struct MarkdownView: NSViewRepresentable {
    let markdown: String
    let controller: MarkdownController
    let autoScrollMode: AutoScrollMode
    let customCSS: String
    let showLineNumbers: Bool
    var baseDir: URL?
    var onHeadingsUpdated: ([TOCItem]) -> Void = { _ in }
    var onActiveHeadingsChanged: ([String]) -> Void = { _ in }
    /// When set, the preview reports the fractional source line at the top of the
    /// viewport whenever the user scrolls it (scroll sync). Programmatic scrolls
    /// (`scrollToLine`) are not echoed back.
    var onTopLineChanged: ((Double) -> Void)?
    /// Re-render with the same source line pinned to the top, instead of leaving the
    /// raw scroll offset (an editor re-renders on every keystroke pause).
    var keepsSourceLineOnRender = false

    public init(
        markdown: String,
        controller: MarkdownController,
        autoScrollMode: AutoScrollMode,
        customCSS: String,
        showLineNumbers: Bool,
        baseDir: URL? = nil,
        onHeadingsUpdated: @escaping ([TOCItem]) -> Void = { _ in },
        onActiveHeadingsChanged: @escaping ([String]) -> Void = { _ in },
        onTopLineChanged: ((Double) -> Void)? = nil,
        keepsSourceLineOnRender: Bool = false
    ) {
        self.markdown = markdown
        self.controller = controller
        self.autoScrollMode = autoScrollMode
        self.customCSS = customCSS
        self.showLineNumbers = showLineNumbers
        self.baseDir = baseDir
        self.onHeadingsUpdated = onHeadingsUpdated
        self.onActiveHeadingsChanged = onActiveHeadingsChanged
        self.onTopLineChanged = onTopLineChanged
        self.keepsSourceLineOnRender = keepsSourceLineOnRender
    }

    public func makeCoordinator() -> Coordinator { Coordinator(controller: controller) }

    public func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(
            WeakScriptHandler(context.coordinator), name: "activeHeadings")
        if onTopLineChanged != nil {
            config.userContentController.add(
                WeakScriptHandler(context.coordinator), name: "previewScroll")
        }
        // Serve referenced images on demand instead of base64-inlining them into
        // the markdown (which re-encoded every file on each reload).
        if let baseDir {
            config.setURLSchemeHandler(
                ImageSchemeHandler(baseDir: baseDir), forURLScheme: ImageSchemeHandler.scheme)
        }
        let webView = MarkdownWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        if let htmlURL = RenderResources.templateURL,
            let resourcesURL = RenderResources.directoryURL
        {
            webView.loadFileURL(htmlURL, allowingReadAccessTo: resourcesURL)
        }
        return webView
    }

    public func updateNSView(_ webView: WKWebView, context: Context) {
        let coordinator = context.coordinator
        coordinator.autoScrollMode = autoScrollMode
        coordinator.onHeadingsUpdated = onHeadingsUpdated
        coordinator.onActiveHeadingsChanged = onActiveHeadingsChanged
        coordinator.onTopLineChanged = onTopLineChanged
        coordinator.keepsSourceLineOnRender = keepsSourceLineOnRender
        coordinator.pendingMarkdown = markdown
        coordinator.customCSS = customCSS

        guard coordinator.isLoaded else { return }

        if markdown != coordinator.lastRenderedMarkdown {
            coordinator.render(markdown)
        } else if autoScrollMode == .tail {
            coordinator.doScrollToBottom()
        }

        if customCSS != coordinator.lastAppliedCSS {
            coordinator.doApplyCSS(customCSS)
        }

        if showLineNumbers != coordinator.lastLineNumbers {
            coordinator.doSetLineNumbers(showLineNumbers)
        }
    }

    public class Coordinator: NSObject, WKNavigationDelegate {
        weak var webView: WKWebView?
        var isLoaded = false
        var pendingMarkdown = ""
        var lastRenderedMarkdown = ""
        var lastAppliedCSS = ""
        var customCSS = ""
        var lastLineNumbers = false
        var autoScrollMode: AutoScrollMode = .none
        var onHeadingsUpdated: ([TOCItem]) -> Void = { _ in }
        var onActiveHeadingsChanged: ([String]) -> Void = { _ in }
        var onTopLineChanged: ((Double) -> Void)?
        var keepsSourceLineOnRender = false

        init(controller: MarkdownController) {
            super.init()
            controller.coordinator = self  // weak back-reference for imperative scroll commands
        }

        // swiftlint:disable:next implicitly_unwrapped_optional - WKNavigationDelegate's exact @objc signature; `WKNavigation?` would silently stop the callback
        public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoaded = true
            render(pendingMarkdown)
            if !customCSS.isEmpty { doApplyCSS(customCSS) }
        }

        // Pin the WebView to the render template. Without this, clicking any link
        // (or a linkified URL) navigates the view away from the template, wiping
        // out every window.* helper and silently breaking the document.
        public func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel); return
            }
            // Allow the initial template load and image scheme requests.
            if url.scheme == ImageSchemeHandler.scheme {
                decisionHandler(.allow); return
            }
            if url.isFileURL, url.lastPathComponent == "render-template.html" {
                decisionHandler(.allow); return
            }
            // Everything else (link clicks, redirects) opens in the user's browser.
            if navigationAction.navigationType == .linkActivated
                || navigationAction.targetFrame == nil
            {
                NSWorkspace.shared.open(url)
            }
            decisionHandler(.cancel)
        }

        func render(_ markdown: String) {
            let capturedMode = autoScrollMode
            let prevMd = lastRenderedMarkdown
            let markdownChanged = markdown != prevMd

            let firstNewLine: Int? =
                (capturedMode == .firstNew && markdownChanged)
                ? Self.firstDivergingLine(old: prevMd, new: markdown)
                : nil

            lastRenderedMarkdown = markdown

            guard let webView,
                let data = try? JSONEncoder().encode(markdown),
                let json = String(data: data, encoding: .utf8)
            else { return }

            let setter = keepsSourceLineOnRender ? "setMarkdownKeepingLine" : "setMarkdown"
            webView.evaluateJavaScript("window.\(setter)(\(json))") {
                [weak self, capturedMode, firstNewLine] _, _ in
                guard let self else { return }
                self.fetchHeadings()
                switch capturedMode {
                case .tail:
                    self.doScrollToBottom()
                case .firstNew:
                    if let line = firstNewLine { self.doScrollToNewContent(line) }
                case .none:
                    break
                }
            }
        }

        private func fetchHeadings() {
            webView?.evaluateJavaScript("window.getHeadings()") { [weak self] result, _ in
                guard let self,
                    let jsonStr = result as? String,
                    let data = jsonStr.data(using: .utf8),
                    let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
                else { return }
                let items = arr.compactMap { dict -> TOCItem? in
                    guard let id = dict["id"] as? String,
                        let level = dict["level"] as? Int,
                        let text = dict["text"] as? String
                    else { return nil }
                    return TOCItem(id: id, level: level, text: text)
                }
                DispatchQueue.main.async { self.onHeadingsUpdated(items) }
            }
        }

        func doScrollToNewContent(_ line: Int) {
            webView?.evaluateJavaScript(
                "window.scrollToNewContent(\(line))", completionHandler: nil)
        }

        func doScrollToBottom() {
            webView?.evaluateJavaScript("window.scrollToBottom()", completionHandler: nil)
        }

        func doApplyCSS(_ css: String) {
            lastAppliedCSS = css
            guard let data = try? JSONEncoder().encode(css),
                let json = String(data: data, encoding: .utf8)
            else { return }
            webView?.evaluateJavaScript("window.setCustomCSS(\(json))", completionHandler: nil)
        }

        func doScrollToHeading(_ id: String) {
            guard let data = try? JSONEncoder().encode(id),
                let json = String(data: data, encoding: .utf8)
            else { return }
            webView?.evaluateJavaScript("window.scrollToHeading(\(json))", completionHandler: nil)
        }

        func doFindText(_ query: String, completion: @escaping ([FindResult]) -> Void) {
            guard let webView,
                let data = try? JSONEncoder().encode(query),
                let json = String(data: data, encoding: .utf8)
            else { completion([]); return }
            webView.evaluateJavaScript("window.findText(\(json))") { result, _ in
                guard let jsonStr = result as? String,
                    let data = jsonStr.data(using: .utf8),
                    let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
                else {
                    DispatchQueue.main.async { completion([]) }
                    return
                }
                let items = arr.compactMap { dict -> FindResult? in
                    guard let idx = dict["index"] as? Int,
                        let before = dict["before"] as? String,
                        let match = dict["match"] as? String,
                        let after = dict["after"] as? String
                    else { return nil }
                    return FindResult(id: idx, before: before, match: match, after: after)
                }
                DispatchQueue.main.async { completion(items) }
            }
        }

        func doClearFind() {
            webView?.evaluateJavaScript("window.clearFind()", completionHandler: nil)
        }

        func doScrollToMatch(_ index: Int) {
            webView?.evaluateJavaScript("window.scrollToMatch(\(index))", completionHandler: nil)
        }

        func doSetLineNumbers(_ enabled: Bool) {
            lastLineNumbers = enabled
            webView?.evaluateJavaScript(
                "window.setLineNumbers(\(enabled ? "true" : "false"))", completionHandler: nil)
        }

        func doScrollToLine(_ line: Double) {
            guard line.isFinite else { return }
            webView?.evaluateJavaScript("window.scrollToLine(\(line))", completionHandler: nil)
        }

        func doSourceLine(forHeading id: String, completion: @escaping (Int?) -> Void) {
            guard let webView,
                let data = try? JSONEncoder().encode(id),
                let json = String(data: data, encoding: .utf8)
            else { completion(nil); return }
            webView.evaluateJavaScript("window.headingLine(\(json))") { result, _ in
                let line = (result as? NSNumber)?.intValue ?? -1
                DispatchQueue.main.async { completion(line >= 0 ? line : nil) }
            }
        }

        func handleScriptMessage(_ message: WKScriptMessage) {
            if message.name == "previewScroll" {
                if let line = (message.body as? NSNumber)?.doubleValue {
                    onTopLineChanged?(line)
                }
                return
            }
            guard message.name == "activeHeadings",
                let jsonStr = message.body as? String,
                let data = jsonStr.data(using: .utf8),
                let ids = try? JSONSerialization.jsonObject(with: data) as? [String]
            else { return }
            DispatchQueue.main.async { self.onActiveHeadingsChanged(ids) }
        }

        func doGetDocumentCSS(completion: @escaping (String) -> Void) {
            webView?.evaluateJavaScript("window.getDocumentCSS()") { result, _ in
                let css = result as? String ?? ""
                DispatchQueue.main.async { completion(css) }
            }
        }

        func doZoomIn() { webView?.pageZoom = min((webView?.pageZoom ?? 1.0) * 1.1, 5.0) }
        func doZoomOut() { webView?.pageZoom = max((webView?.pageZoom ?? 1.0) / 1.1, 0.2) }
        func doResetZoom() { webView?.pageZoom = 1.0 }

        private static func firstDivergingLine(old: String, new: String) -> Int {
            let oldLines = old.components(separatedBy: "\n")
            let newLines = new.components(separatedBy: "\n")
            for i in 0..<min(oldLines.count, newLines.count) where oldLines[i] != newLines[i] {
                return i
            }
            return min(oldLines.count, newLines.count)
        }
    }
}
