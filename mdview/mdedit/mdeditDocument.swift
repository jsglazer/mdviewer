import SwiftUI
import UniformTypeIdentifiers

/// A Markdown file opened for editing.
///
/// The editor always works on `\n`-separated text; the file's own line-ending style
/// and UTF-8 byte-order mark are remembered on read and restored on write, so saving
/// an untouched CRLF or BOM file leaves it byte-for-byte identical. The trailing
/// newline (or its absence) is part of `text` and is never added or stripped.
struct mdeditDocument: FileDocument {  // swiftlint:disable:this type_name
    enum LineEnding: String {
        case lf = "\n"
        case crlf = "\r\n"
        case cr = "\r"
    }

    var text: String
    var lineEnding: LineEnding
    var hasByteOrderMark: Bool

    init(text: String = "") {
        self.text = text
        lineEnding = .lf
        hasByteOrderMark = false
    }

    static let readableContentTypes: [UTType] = [
        UTType(filenameExtension: "md") ?? .plainText,
        UTType(filenameExtension: "markdown") ?? .plainText,
    ]

    private static let bom = Data([0xEF, 0xBB, 0xBF])

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        try self.init(data: data)
    }

    init(data: Data) throws {
        var bytes = data
        hasByteOrderMark = bytes.starts(with: Self.bom)
        if hasByteOrderMark { bytes = bytes.dropFirst(Self.bom.count) }
        guard let string = String(data: bytes, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        lineEnding = Self.detectLineEnding(in: string)
        text = Self.normalized(string)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        .init(regularFileWithContents: encoded())
    }

    /// The bytes written to disk: `text` with the original line endings and BOM.
    func encoded() -> Data {
        let body =
            lineEnding == .lf
            ? text : text.replacingOccurrences(of: "\n", with: lineEnding.rawValue)
        var data = hasByteOrderMark ? Self.bom : Data()
        data.append(Data(body.utf8))
        return data
    }

    /// The first line break decides the style; a file with none counts as LF.
    static func detectLineEnding(in string: String) -> LineEnding {
        // Swift treats "\r\n" as one Character, so scan unicode scalars instead.
        let scalars = Array(string.unicodeScalars)
        for (index, scalar) in scalars.enumerated() {
            if scalar == "\n" { return .lf }
            if scalar == "\r" {
                return index + 1 < scalars.count && scalars[index + 1] == "\n" ? .crlf : .cr
            }
        }
        return .lf
    }

    static func normalized(_ string: String) -> String {
        string.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(
            of: "\r", with: "\n")
    }
}
