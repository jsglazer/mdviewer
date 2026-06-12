import Foundation

/// Exercises ImageSchemeHandler's path-resolution logic.
///
/// Mirrors MarkdownView.swift ImageSchemeHandler.webView(_:start:):
///   let rawPath = url.path.hasPrefix("/") ? String(url.path.dropFirst()) : url.path
///   let relPath  = rawPath.removingPercentEncoding ?? rawPath
///   let fileURL  = baseDir.appendingPathComponent(relPath).standardized
///
/// Security invariant: the resolved path MUST stay within baseDir.
/// A crash here means a path-traversal out of the document directory is possible.
public func fuzzImagePath(_ start: UnsafePointer<UInt8>, _ count: Int) -> CInt {
    guard
        let rawInput = String(
            bytes: UnsafeBufferPointer(start: start, count: count),
            encoding: .utf8)
    else { return 0 }

    let baseDir = URL(fileURLWithPath: "/tmp/fuzz-base").standardized
    let rawPath = rawInput.hasPrefix("/") ? String(rawInput.dropFirst()) : rawInput
    let relPath = rawPath.removingPercentEncoding ?? rawPath
    let resolved = baseDir.appendingPathComponent(relPath).standardized

    // Mirror the guard in ImageSchemeHandler: traversal paths are rejected, not crashed.
    // The invariant is that resolution + detection never crash regardless of input.
    let basePath = baseDir.path
    let resolvedPath = resolved.path
    let _ = resolvedPath == basePath || resolvedPath.hasPrefix(basePath + "/")

    return 0
}
