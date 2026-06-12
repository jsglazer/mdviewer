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
            NotificationCenter.default.post(name: Notification.Name("mdviewCloseFind"), object: nil)
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
final class ImageSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "mdview-img"
    private let baseDir: URL

    init(baseDir: URL) { self.baseDir = baseDir }

    static func mime(forExtension ext: String) -> String {
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

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        // URL form: mdview-img://local/<percent-encoded relative path>
        guard let url = task.request.url else {
            task.didFailWithError(URLError(.badURL)); return
        }
        let rawPath = url.path.hasPrefix("/") ? String(url.path.dropFirst()) : url.path
        let relPath = rawPath.removingPercentEncoding ?? rawPath
        let fileURL = baseDir.appendingPathComponent(relPath)
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

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}

struct TOCItem: Identifiable, Equatable {
    let id: String
    let level: Int
    let text: String
}

struct FindResult: Identifiable, Equatable {
    let id: Int  // match index; used as scroll target
    let before: String
    let match: String
    let after: String
}

enum AutoScrollMode: Equatable {
    case none, firstNew, tail
}

final class MarkdownController {
    weak var coordinator: MarkdownView.Coordinator?

    func scrollToHeading(id: String) { coordinator?.doScrollToHeading(id) }
    func findText(_ query: String, completion: @escaping ([FindResult]) -> Void) {
        coordinator?.doFindText(query, completion: completion)
    }
    func clearFind() { coordinator?.doClearFind() }
    func scrollToMatch(_ index: Int) { coordinator?.doScrollToMatch(index) }
    func setLineNumbers(_ enabled: Bool) { coordinator?.doSetLineNumbers(enabled) }
    func getDocumentCSS(completion: @escaping (String) -> Void) {
        coordinator?.doGetDocumentCSS(completion: completion)
    }
    func zoomIn() { coordinator?.doZoomIn() }
    func zoomOut() { coordinator?.doZoomOut() }
    func resetZoom() { coordinator?.doResetZoom() }
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

struct MarkdownView: NSViewRepresentable {
    let markdown: String
    let controller: MarkdownController
    let autoScrollMode: AutoScrollMode
    let customCSS: String
    let showLineNumbers: Bool
    var baseDir: URL?
    var onHeadingsUpdated: ([TOCItem]) -> Void = { _ in }
    var onActiveHeadingsChanged: ([String]) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator(controller: controller) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(
            WeakScriptHandler(context.coordinator), name: "activeHeadings")
        // Serve referenced images on demand instead of base64-inlining them into
        // the markdown (which re-encoded every file on each reload).
        if let baseDir {
            config.setURLSchemeHandler(
                ImageSchemeHandler(baseDir: baseDir), forURLScheme: ImageSchemeHandler.scheme)
        }
        let webView = MarkdownWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        if let htmlURL = Bundle.main.url(forResource: "render-template", withExtension: "html"),
            let resourcesURL = Bundle.main.resourceURL
        {
            webView.loadFileURL(htmlURL, allowingReadAccessTo: resourcesURL)
        }
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let c = context.coordinator
        c.autoScrollMode = autoScrollMode
        c.onHeadingsUpdated = onHeadingsUpdated
        c.onActiveHeadingsChanged = onActiveHeadingsChanged
        c.pendingMarkdown = markdown
        c.customCSS = customCSS

        guard c.isLoaded else { return }

        if markdown != c.lastRenderedMarkdown {
            c.render(markdown)
        } else if autoScrollMode == .tail {
            c.doScrollToBottom()
        }

        if customCSS != c.lastAppliedCSS {
            c.doApplyCSS(customCSS)
        }

        if showLineNumbers != c.lastLineNumbers {
            c.doSetLineNumbers(showLineNumbers)
        }
    }

    class Coordinator: NSObject, WKNavigationDelegate {
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

        init(controller: MarkdownController) {
            super.init()
            controller.coordinator = self  // weak back-reference for imperative scroll commands
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoaded = true
            render(pendingMarkdown)
            if !customCSS.isEmpty { doApplyCSS(customCSS) }
        }

        // Pin the WebView to the render template. Without this, clicking any link
        // (or a linkified URL) navigates the view away from the template, wiping
        // out every window.* helper and silently breaking the document.
        func webView(
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

            webView.evaluateJavaScript("window.setMarkdown(\(json))") {
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
                let items = arr.compactMap { d -> TOCItem? in
                    guard let id = d["id"] as? String,
                        let level = d["level"] as? Int,
                        let text = d["text"] as? String
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
                    let d = jsonStr.data(using: .utf8),
                    let arr = try? JSONSerialization.jsonObject(with: d) as? [[String: Any]]
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

        func handleScriptMessage(_ message: WKScriptMessage) {
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
            for i in 0..<min(oldLines.count, newLines.count) {
                if oldLines[i] != newLines[i] { return i }
            }
            return min(oldLines.count, newLines.count)
        }
    }
}
