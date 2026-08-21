import AppKit
import Combine
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

/// Which action the preview window should offer as its default button.
enum PrintPreviewIntent {
    case printing
    case exportPDF
}

/// Snapshot of the document being previewed, taken when the window is opened.
struct PrintSource {
    let markdown: String
    let baseDir: URL?
    let customCSS: String
    let showLineNumbers: Bool
    let title: String
}

/// Drives the Print Preview window: regenerates the PDF whenever the page extras or
/// page setup change, then prints or saves that exact document.
final class PrintPreviewModel: NSObject, ObservableObject {
    @Published private(set) var isRendering = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var currentPage = 0
    @Published private(set) var pageCount = 0
    @Published private(set) var paperLabel = ""
    @Published var intent: PrintPreviewIntent = .printing
    @Published var extras: PrintExtras = .load() {
        didSet {
            guard extras != oldValue else { return }
            extras.save()
            regenerate()
        }
    }

    let pdfView = PDFView()
    weak var hostWindow: NSWindow?

    private let renderer = PrintRenderer()
    private var source: PrintSource?
    private var pdfData: Data?
    private var pendingRerender = false

    var canAct: Bool { pdfData != nil && !isRendering }

    override init() {
        super.init()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displaysPageBreaks = true
        pdfView.pageShadowsEnabled = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(pageChanged),
            name: .PDFViewPageChanged, object: pdfView)
    }

    func configure(source: PrintSource, intent: PrintPreviewIntent) {
        self.source = source
        self.intent = intent
    }

    // MARK: - Rendering

    func regenerate() {
        guard let source else { return }
        if isRendering {
            pendingRerender = true
            return
        }
        isRendering = true
        errorMessage = nil
        paperLabel = PrintSettings.shared.paperDescription

        let job = PrintRenderer.Job(
            markdown: source.markdown, baseDir: source.baseDir, customCSS: source.customCSS,
            showLineNumbers: source.showLineNumbers, title: source.title, extras: extras)
        renderer.render(job) { [weak self] result in
            guard let self else { return }
            if case .failure(let error) = result,
                (error as? PrintRenderer.RenderError) == .cancelled
            {
                return
            }
            self.isRendering = false
            switch result {
            case .success(let data): self.accept(data)
            case .failure(let error): self.reject(error)
            }
            if self.pendingRerender {
                self.pendingRerender = false
                self.regenerate()
            }
        }
    }

    private func accept(_ data: Data) {
        pdfData = data
        let doc = PDFDocument(data: data)
        pdfView.document = doc
        pageCount = doc?.pageCount ?? 0
        currentPage = pageCount > 0 ? 1 : 0
        if let first = doc?.page(at: 0) { pdfView.go(to: first) }
    }

    private func reject(_ error: Error) {
        pdfData = nil
        pdfView.document = nil
        pageCount = 0
        currentPage = 0
        errorMessage = error.localizedDescription
    }

    @objc private func pageChanged() {
        guard let doc = pdfView.document, let page = pdfView.currentPage else { return }
        currentPage = doc.index(for: page) + 1
    }

    // MARK: - Actions

    func goToPreviousPage() { pdfView.goToPreviousPage(nil) }
    func goToNextPage() { pdfView.goToNextPage(nil) }

    func pageSetup() {
        if PrintSettings.shared.runPageSetup() { regenerate() }
    }

    func printNow() {
        guard let doc = pdfView.document,
            let info = PrintSettings.shared.printInfo.copy() as? NSPrintInfo
        else { return }
        // The pages already carry their margins and extras, so they print 1:1 with
        // no further insets or scaling — exactly what the preview showed.
        info.topMargin = 0
        info.bottomMargin = 0
        info.leftMargin = 0
        info.rightMargin = 0
        info.jobDisposition = .spool
        guard
            let operation = doc.printOperation(
                for: info, scalingMode: .pageScaleNone, autoRotate: false)
        else { return }
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        if let window = hostWindow {
            operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
        } else {
            operation.run()
        }
    }

    func savePDF() {
        guard let data = pdfData else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = suggestedFileName
        panel.canCreateDirectories = true
        let write: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try data.write(to: url)
            } catch {
                NSAlert(error: error).runModal()
            }
        }
        if let window = hostWindow {
            panel.beginSheetModal(for: window, completionHandler: write)
        } else {
            write(panel.runModal())
        }
    }

    private var suggestedFileName: String {
        let base = (source?.title ?? "Document")
        let stem = (base as NSString).deletingPathExtension
        return (stem.isEmpty ? base : stem) + ".pdf"
    }
}

final class PrintPreviewController {
    static let shared = PrintPreviewController()
    private var panel: NSPanel?
    private let model = PrintPreviewModel()
    private init() {}

    func show(source: PrintSource, intent: PrintPreviewIntent) {
        model.configure(source: source, intent: intent)
        if panel == nil {
            let created = UtilityPanel.make(
                title: "Print Preview",
                size: NSSize(width: 720, height: 800),
                minSize: NSSize(width: 480, height: 420),
                miniaturizable: true
            )
            // NSPanel hides itself whenever the app deactivates. For a transient
            // inspector that's fine, but a preview you print from must survive
            // switching apps — and anything that steals activation while it opens
            // (a crash reporter, a notification) would otherwise make it vanish the
            // moment it appeared, looking exactly like the button did nothing.
            created.hidesOnDeactivate = false
            created.contentView = NSHostingView(rootView: PrintPreviewView(model: model))
            panel = created
        }
        panel?.title = "Print Preview — \(source.title)"
        model.hostWindow = panel
        if let panel { UtilityPanel.present(panel) }
        model.regenerate()
    }
}
