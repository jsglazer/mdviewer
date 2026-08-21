import AppKit
import PDFKit
import WebKit

/// Renders a document off-screen with print styling and returns paginated PDF data.
///
/// Printing and PDF export share this one path, so what the preview window shows is
/// byte-for-byte the file that gets saved or sent to the printer.
final class PrintRenderer: NSObject, WKNavigationDelegate {
    struct Job {
        let markdown: String
        let baseDir: URL?
        let customCSS: String
        let showLineNumbers: Bool
        let title: String
        let extras: PrintExtras
    }

    enum RenderError: LocalizedError, Equatable {
        case templateMissing
        case printOperationFailed
        case cancelled

        var errorDescription: String? {
            switch self {
            case .templateMissing:
                return "The render template is missing from the app bundle."
            case .printOperationFailed:
                return "macOS could not paginate this document for printing."
            case .cancelled:
                return "The preview was superseded by a newer one."
            }
        }
    }

    /// Poll budget while waiting for images and fonts (~3s at 50 ms).
    private static let readyPollLimit = 60
    private static let readyPollInterval = 0.05
    /// Settle time between "ready" and pagination, so the web process has painted
    /// the new content before it is asked to render it for print.
    private static let settleDelay = 0.15

    private var webView: WKWebView?
    private var hostWindow: NSWindow?
    private var job: Job?
    private var completion: ((Result<Data, Error>) -> Void)?
    private var readyAttempts = 0
    private var retryUsed = false
    private var pendingTmpURL: URL?
    private var pendingMargins: PDFStamper.Margins?

    func render(_ job: Job, completion: @escaping (Result<Data, Error>) -> Void) {
        finish(.failure(RenderError.cancelled))
        self.job = job
        self.completion = completion
        retryUsed = false
        start()
    }

    private func start() {
        tearDown()
        guard let job,
            let htmlURL = Bundle.main.url(forResource: "render-template", withExtension: "html"),
            let resourcesURL = Bundle.main.resourceURL
        else {
            finish(.failure(RenderError.templateMissing))
            return
        }
        readyAttempts = 0

        let info = PrintSettings.shared.printInfo
        let contentWidth = max(info.paperSize.width - info.leftMargin - info.rightMargin, 72)

        let config = WKWebViewConfiguration()
        if let baseDir = job.baseDir {
            config.setURLSchemeHandler(
                ImageSchemeHandler(baseDir: baseDir), forURLScheme: ImageSchemeHandler.scheme)
        }
        let web = WKWebView(
            frame: NSRect(x: 0, y: 0, width: contentWidth, height: 1200), configuration: config)
        // Printed output is always light; forcing the aqua appearance also makes the
        // template's prefers-color-scheme rules resolve to the light palette.
        web.appearance = NSAppearance(named: .aqua)
        web.navigationDelegate = self

        // WebKit only lays out — and therefore only paginates — content in a window,
        // so the render happens in a borderless one parked far off-screen.
        let host = NSWindow(
            contentRect: web.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        host.isReleasedWhenClosed = false
        host.contentView?.addSubview(web)
        host.setFrameOrigin(NSPoint(x: -30000, y: -30000))
        host.orderBack(nil)

        webView = web
        hostWindow = host
        web.loadFileURL(htmlURL, allowingReadAccessTo: resourcesURL)
    }

    // MARK: - Navigation

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let job else { return }
        var script = ""
        if let markdown = Self.jsString(job.markdown) {
            script += "window.setMarkdown(\(markdown));"
        }
        if !job.customCSS.isEmpty, let css = Self.jsString(job.customCSS) {
            script += "window.setCustomCSS(\(css));"
        }
        script += "window.setLineNumbers(\(job.showLineNumbers));"
        script += "window.setPrintMode({linkURLs:\(job.extras.linkURLs)});"
        webView.evaluateJavaScript(script) { [weak self] _, _ in
            self?.waitForReady()
        }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }
        let allowed =
            url.scheme == ImageSchemeHandler.scheme
            || (url.isFileURL && url.lastPathComponent == "render-template.html")
        decisionHandler(allowed ? .allow : .cancel)
    }

    func webView(
        _ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error
    ) {
        finish(.failure(error))
        tearDown()
    }

    // MARK: - Pipeline

    /// Images arrive asynchronously through the custom scheme handler and web fonts
    /// resolve on their own schedule; paginating early yields blanks and gaps.
    private func waitForReady() {
        webView?.evaluateJavaScript("window.printReady()") { [weak self] result, _ in
            guard let self else { return }
            let ready = (result as? Bool) ?? true
            if ready || self.readyAttempts >= Self.readyPollLimit {
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.settleDelay) {
                    self.measure()
                }
            } else {
                self.readyAttempts += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.readyPollInterval) {
                    self.waitForReady()
                }
            }
        }
    }

    private func measure() {
        webView?.evaluateJavaScript("window.contentHeight()") { [weak self] result, _ in
            let height = (result as? NSNumber)?.doubleValue ?? 0
            // Leave the JavaScript completion handler before starting the print
            // operation — it needs a free main run loop to talk to the web process.
            DispatchQueue.main.async { self?.produce(contentHeight: CGFloat(max(height, 1))) }
        }
    }

    private func produce(contentHeight: CGFloat) {
        guard let webView, let host = hostWindow, let job,
            let info = PrintSettings.shared.printInfo.copy() as? NSPrintInfo
        else {
            finish(.failure(RenderError.printOperationFailed))
            tearDown()
            return
        }

        pendingMargins = PDFStamper.Margins(
            top: info.topMargin, bottom: info.bottomMargin,
            side: min(info.leftMargin, info.rightMargin))
        if job.extras.hasHeader { info.topMargin += PrintLayout.bandHeight }
        if job.extras.hasFooter { info.bottomMargin += PrintLayout.bandHeight }
        info.jobDisposition = .save

        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mdview-print-\(UUID().uuidString).pdf")
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL.rawValue] = tmpURL
        pendingTmpURL = tmpURL

        let width = info.paperSize.width - info.leftMargin - info.rightMargin
        webView.frame = NSRect(x: 0, y: 0, width: width, height: contentHeight)
        let operation = webView.printOperation(with: info)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        // `run()` deadlocks here: WebKit paginates in the content process and the
        // reply can only arrive while the main run loop keeps turning, which the
        // synchronous form blocks. The modal form returns immediately instead.
        operation.runModal(
            for: host, delegate: self,
            didRun: #selector(printOperationDidRun(_:success:contextInfo:)), contextInfo: nil)
    }

    @objc private func printOperationDidRun(
        _ operation: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?
    ) {
        guard let tmpURL = pendingTmpURL, let margins = pendingMargins, let job else { return }
        pendingTmpURL = nil
        let data = success ? try? Data(contentsOf: tmpURL) : nil
        try? FileManager.default.removeItem(at: tmpURL)

        guard let data else {
            finish(.failure(RenderError.printOperationFailed))
            tearDown()
            return
        }
        // A cold web content process occasionally paginates before it has painted,
        // producing the right page count with nothing on the pages. One retry from
        // a fresh WebView is enough; a genuinely text-free document just retries once.
        if Self.isBlank(data), !job.markdown.isEmpty, !retryUsed {
            retryUsed = true
            start()
            return
        }
        tearDown()
        finish(
            .success(
                PDFStamper.stamp(
                    data, extras: job.extras, title: job.title, date: Date(), margins: margins)))
    }

    private static func isBlank(_ data: Data) -> Bool {
        guard let doc = PDFDocument(data: data), doc.pageCount > 0 else { return true }
        let text = doc.page(at: 0)?.string ?? ""
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func finish(_ result: Result<Data, Error>) {
        let handler = completion
        completion = nil
        job = nil
        handler?(result)
    }

    private func tearDown() {
        webView?.navigationDelegate = nil
        webView?.removeFromSuperview()
        webView = nil
        hostWindow?.orderOut(nil)
        hostWindow = nil
        pendingTmpURL = nil
        pendingMargins = nil
    }

    private static func jsString(_ value: String) -> String? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
