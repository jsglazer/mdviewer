import AppKit
import PDFKit

/// Shared geometry for the printed page.
enum PrintLayout {
    /// Space reserved above / below the content for the header and footer bands.
    static let bandHeight: CGFloat = 24
    /// Height of a single stamped line of header/footer text.
    static let bandLineHeight: CGFloat = 14
    /// Point size of stamped header/footer text.
    static let bandFontSize: CGFloat = 9
}

/// Optional decorations stamped onto each page of the generated PDF.
/// Persisted so the choices survive between print jobs and launches.
struct PrintExtras: Equatable {
    var titleHeader: Bool
    var printDate: Bool
    var pageNumbers: Bool
    var linkURLs: Bool

    /// A band is only reserved when something is actually drawn in it.
    var hasHeader: Bool { titleHeader || printDate }
    var hasFooter: Bool { pageNumbers }

    static let standard = PrintExtras(
        titleHeader: true, printDate: true, pageNumbers: true, linkURLs: false)

    private enum Key {
        static let title = "printHeaderTitle"
        static let date = "printHeaderDate"
        static let pages = "printFooterPageNumbers"
        static let links = "printLinkURLs"
    }

    static func load(from defaults: UserDefaults = .standard) -> PrintExtras {
        func flag(_ key: String, _ fallback: Bool) -> Bool {
            defaults.object(forKey: key) as? Bool ?? fallback
        }
        return PrintExtras(
            titleHeader: flag(Key.title, standard.titleHeader),
            printDate: flag(Key.date, standard.printDate),
            pageNumbers: flag(Key.pages, standard.pageNumbers),
            linkURLs: flag(Key.links, standard.linkURLs))
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(titleHeader, forKey: Key.title)
        defaults.set(printDate, forKey: Key.date)
        defaults.set(pageNumbers, forKey: Key.pages)
        defaults.set(linkURLs, forKey: Key.links)
    }
}

/// The app's page setup — paper, orientation and margins — persisted across launches.
///
/// Kept separate from `NSPrintInfo.shared` so Page Setup edits made here don't leak
/// into the print info AppKit hands to the document architecture elsewhere.
final class PrintSettings {
    static let shared = PrintSettings()

    /// 0.75" all round reads better for Markdown than AppKit's 1" default.
    private static let defaultMargin: CGFloat = 54
    private static let key = "printPageSetup"

    let printInfo: NSPrintInfo

    private init() {
        let info = NSPrintInfo()
        let saved = UserDefaults.standard.dictionary(forKey: Self.key)
        // Orientation first: assigning it rotates paperSize, so restoring the saved
        // paper size afterwards is what pins both back to their stored values.
        if let raw = saved?["orientation"] as? Int,
            let orientation = NSPrintInfo.PaperOrientation(rawValue: raw)
        {
            info.orientation = orientation
        }
        if let width = saved?["paperWidth"] as? Double,
            let height = saved?["paperHeight"] as? Double,
            width > 0, height > 0
        {
            info.paperSize = NSSize(width: width, height: height)
        }
        info.topMargin = CGFloat(saved?["top"] as? Double ?? Double(Self.defaultMargin))
        info.bottomMargin = CGFloat(saved?["bottom"] as? Double ?? Double(Self.defaultMargin))
        info.leftMargin = CGFloat(saved?["left"] as? Double ?? Double(Self.defaultMargin))
        info.rightMargin = CGFloat(saved?["right"] as? Double ?? Double(Self.defaultMargin))
        info.horizontalPagination = .automatic
        info.verticalPagination = .automatic
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        printInfo = info
    }

    func persist() {
        UserDefaults.standard.set(
            [
                "paperWidth": Double(printInfo.paperSize.width),
                "paperHeight": Double(printInfo.paperSize.height),
                "orientation": printInfo.orientation.rawValue,
                "top": Double(printInfo.topMargin),
                "bottom": Double(printInfo.bottomMargin),
                "left": Double(printInfo.leftMargin),
                "right": Double(printInfo.rightMargin),
            ], forKey: Self.key)
    }

    /// Shows the standard Page Setup dialog. Returns true when the user accepted.
    func runPageSetup() -> Bool {
        let accepted =
            NSPageLayout().runModal(with: printInfo)
            == NSApplication.ModalResponse.OK
            .rawValue
        if accepted { persist() }
        return accepted
    }

    /// Human-readable summary for the preview window, e.g. "US Letter · Portrait".
    var paperDescription: String {
        let name = printInfo.localizedPaperName ?? "Custom"
        let orientation = printInfo.orientation == .landscape ? "Landscape" : "Portrait"
        return "\(name) · \(orientation)"
    }
}

/// Draws the header / footer band onto an already-paginated PDF.
///
/// WebKit does not implement CSS `@page` margin boxes, so the extras are stamped
/// afterwards into margin space the renderer deliberately left empty.
enum PDFStamper {
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    struct Margins {
        let top: CGFloat
        let bottom: CGFloat
        let side: CGFloat
    }

    /// Everything one page's bands need to know about themselves.
    private struct Stamp {
        let extras: PrintExtras
        let title: String
        let dateText: String
        let page: Int
        let total: Int
        let margins: Margins
    }

    static func stamp(
        _ data: Data, extras: PrintExtras, title: String, date: Date, margins: Margins
    ) -> Data {
        guard extras.hasHeader || extras.hasFooter,
            let doc = PDFDocument(data: data), doc.pageCount > 0
        else { return data }

        let out = NSMutableData()
        guard let consumer = CGDataConsumer(data: out as CFMutableData),
            let ctx = CGContext(consumer: consumer, mediaBox: nil, nil)
        else { return data }

        let dateText = dateFormatter.string(from: date)
        let total = doc.pageCount
        for index in 0..<total {
            guard let cgPage = doc.page(at: index)?.pageRef else { continue }
            var box = cgPage.getBoxRect(.mediaBox)
            ctx.beginPage(mediaBox: &box)
            ctx.drawPDFPage(cgPage)

            let previous = NSGraphicsContext.current
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
            drawBands(
                in: box,
                stamp: Stamp(
                    extras: extras, title: title, dateText: dateText,
                    page: index + 1, total: total, margins: margins))
            NSGraphicsContext.current = previous
            ctx.endPage()
        }
        ctx.closePDF()
        return out as Data
    }

    private static func drawBands(in box: CGRect, stamp: Stamp) {
        let (extras, margins) = (stamp.extras, stamp.margins)
        let left = margins.side
        let right = box.maxX - margins.side
        let width = right - left
        guard width > 40 else { return }
        let lineHeight = PrintLayout.bandLineHeight

        if extras.hasHeader {
            let y = box.maxY - margins.top - lineHeight - 2
            if extras.titleHeader {
                draw(
                    stamp.title,
                    in: NSRect(x: left, y: y, width: width * 0.62, height: lineHeight),
                    align: .left)
            }
            if extras.printDate {
                let dateWidth = width * 0.35
                draw(
                    stamp.dateText,
                    in: NSRect(x: right - dateWidth, y: y, width: dateWidth, height: lineHeight),
                    align: .right)
            }
            drawRule(from: left, to: right, y: y - 4)
        }

        if extras.pageNumbers {
            draw(
                "Page \(stamp.page) of \(stamp.total)",
                in: NSRect(
                    x: left, y: box.minY + margins.bottom + 5, width: width, height: lineHeight),
                align: .center)
        }
    }

    private static func drawRule(from left: CGFloat, to right: CGFloat, y: CGFloat) {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: left, y: y))
        path.line(to: NSPoint(x: right, y: y))
        path.lineWidth = 0.5
        NSColor.black.withAlphaComponent(0.2).setStroke()
        path.stroke()
    }

    private static func draw(_ text: String, in rect: NSRect, align: NSTextAlignment) {
        guard !text.isEmpty else { return }
        let style = NSMutableParagraphStyle()
        style.alignment = align
        style.lineBreakMode = .byTruncatingMiddle
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: PrintLayout.bandFontSize),
            .foregroundColor: NSColor.black.withAlphaComponent(0.55),
            .paragraphStyle: style,
        ]
        NSAttributedString(string: text, attributes: attrs)
            .draw(with: rect, options: [.usesLineFragmentOrigin], context: nil)
    }
}
