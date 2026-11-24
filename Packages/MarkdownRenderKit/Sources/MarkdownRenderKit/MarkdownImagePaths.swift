import Foundation

/// Rewrites relative image references so the preview WebView requests them through
/// `ImageSchemeHandler`, which streams the bytes from the document's folder.
public enum MarkdownImagePaths {
    // Matches the URL part of ![alt](url ...) including the <angle-bracket> form.
    // swiftlint:disable:next force_try - constant pattern, verified by the image-path tests
    private static let imagePattern = try! NSRegularExpression(
        pattern: #"(!\[[^\]]*\]\()\s*(<[^>]*>|[^)\s]+)"#
    )

    /// Returns `markdown` with every relative image path pointed at the custom scheme.
    /// Absolute, remote, `data:` and already-rewritten URLs are left untouched. Only the
    /// URL text changes, never the line structure, so source line numbers still match.
    public static func rewrite(_ markdown: String) -> String {
        let mutableString = NSMutableString(string: markdown)
        var offset = 0
        let matches = imagePattern.matches(
            in: markdown, range: NSRange(markdown.startIndex..., in: markdown)
        )
        for match in matches {
            let nsPathRange = match.range(at: 2)
            guard nsPathRange.location != NSNotFound,
                let pathRange = Range(nsPathRange, in: markdown)
            else { continue }
            var path = String(markdown[pathRange])
            if path.hasPrefix("<") && path.hasSuffix(">") {
                path = String(path.dropFirst().dropLast())
            }
            // Leave absolute, remote, data: and already-handled URLs untouched.
            guard !path.isEmpty,
                !path.hasPrefix("http"), !path.hasPrefix("data:"),
                !path.hasPrefix("/"), !path.hasPrefix("file:"),
                !path.hasPrefix("\(ImageSchemeHandler.scheme):")
            else { continue }

            // Normalise any existing percent-encoding, then re-encode for the URL so
            // both "my image.png" and "my%20image.png" resolve to the same file.
            let decoded = path.removingPercentEncoding ?? path
            let encoded =
                decoded.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? decoded
            let replacement = "\(ImageSchemeHandler.scheme)://local/\(encoded)"

            let adjustedRange = NSRange(
                location: nsPathRange.location + offset, length: nsPathRange.length)
            mutableString.replaceCharacters(in: adjustedRange, with: replacement)
            offset += replacement.utf16.count - (nsPathRange.length)
        }
        return mutableString as String
    }
}
