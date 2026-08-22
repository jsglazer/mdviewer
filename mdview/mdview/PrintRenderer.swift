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
        let scalePercent: Int
    }

    /// A finished render, plus the unscaled measurements behind it. `contentHeight`
    /// and `availableHeight` don't depend on `scalePercent` — layout happens before
    /// scaling is applied — so callers can solve for "what scale fits N pages" from
    /// a single render instead of needing a dedicated measurement pass.
    struct RenderResult {
        let data: Data
        let contentHeight: CGFloat
        let availableHeight: CGFloat
    }

    enum RenderError: LocalizedError, Equatable {
        case templateMissing
        case printOperationFailed
        case timedOut
        case cancelled

        var errorDescription: String? {
            switch self {
            case .templateMissing:
                return "The render template is missing from the app bundle."
            case .printOperationFailed:
                return "macOS could not paginate this document for printing."
            case .timedOut:
                return "Preparing the preview timed out. Try again."
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
    /// Ceiling on a whole render. Every stage here depends on a callback from
    /// WebKit or AppKit's print machinery, and if one never arrives the model
    /// would sit in `isRendering` forever — silently swallowing every later
    /// Print/Export click. The watchdog turns that into a visible error instead.
    private static let watchdogTimeout = 45.0

    private var webView: WKWebView?
    private var hostWindow: NSWindow?
    private var job: Job?
    private var completion: ((Result<RenderResult, Error>) -> Void)?
    private var readyAttempts = 0
    private var retryUsed = false
    private var pendingTmpURL: URL?
    private var pendingMargins: PDFStamper.Margins?
    private var pendingContentHeight: CGFloat?
    private var pendingAvailableHeight: CGFloat?
    private var watchdog: DispatchWorkItem?

    func render(_ job: Job, completion: @escaping (Result<RenderResult, Error>) -> Void) {
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
        armWatchdog()

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
        // Content lays out at the full printable width regardless of scale; letting
        // AppKit's own view-printing pagination apply scalingFactor here means a
        // shrink fits more of that layout onto each page and an enlarge fits less,
        // with no need to re-measure content height per scale.
        info.scalingFactor = CGFloat(job.scalePercent) / 100.0
        info.isHorizontallyCentered = true

        pendingContentHeight = contentHeight
        pendingAvailableHeight = info.paperSize.height - info.topMargin - info.bottomMargin

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

    /// AppKit spawns a worker thread for the modal print operation and calls this
    /// back **on that thread**. Everything below touches the WebView, AppKit
    /// drawing and `@Published` state, so it all has to hop back to main first —
    /// tearing the WebView down from the worker crashes inside WebKit's window
    /// observer.
    @objc private func printOperationDidRun(
        _ operation: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?
    ) {
        DispatchQueue.main.async { [weak self] in self?.handlePrintFinished(success: success) }
    }

    private func handlePrintFinished(success: Bool) {
        guard let tmpURL = pendingTmpURL, let margins = pendingMargins, let job,
            let contentHeight = pendingContentHeight, let availableHeight = pendingAvailableHeight
        else { return }
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
        let stamped = PDFStamper.stamp(
            data, extras: job.extras, title: job.title, date: Date(), margins: margins)
        finish(
            .success(
                RenderResult(
                    data: stamped, contentHeight: contentHeight, availableHeight: availableHeight))
        )
    }

    private static func isBlank(_ data: Data) -> Bool {
        guard let doc = PDFDocument(data: data), doc.pageCount > 0 else { return true }
        let text = doc.page(at: 0)?.string ?? ""
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func armWatchdog() {
        watchdog?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.completion != nil else { return }
            self.finish(.failure(RenderError.timedOut))
            self.tearDown()
        }
        watchdog = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.watchdogTimeout, execute: item)
    }

    private func finish(_ result: Result<RenderResult, Error>) {
        watchdog?.cancel()
        watchdog = nil
        let handler = completion
        completion = nil
        job = nil
        handler?(result)
    }

    private func tearDown() {
        webView?.navigationDelegate = nil
        webView?.removeFromSuperview()
        webView = nil
        // close(), not just orderOut() — the window is created with
        // isReleasedWhenClosed = false, so merely ordering it out leaves a live
        // off-screen NSWindow behind on every render.
        hostWindow?.close()
        hostWindow = nil
        pendingTmpURL = nil
        pendingMargins = nil
        pendingContentHeight = nil
        pendingAvailableHeight = nil
    }

    private static func jsString(_ value: String) -> String? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
