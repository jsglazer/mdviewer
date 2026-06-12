import Foundation

/// Exercises the firstDivergingLine() algorithm used to find where new content
/// starts after a file update (drives "jump to new content" scroll behaviour).
///
/// Invariants checked:
///   - Result is non-negative.
///   - Result does not exceed min(oldLineCount, newLineCount).
///   - Identical inputs always return the line count (no spurious divergence).
public func fuzzDiffing(_ start: UnsafePointer<UInt8>, _ count: Int) -> CInt {
    guard
        count >= 2,
        let input = String(
            bytes: UnsafeBufferPointer(start: start, count: count),
            encoding: .utf8)
    else { return 0 }

    let midOffset = count / 2
    let mid =
        input.index(input.startIndex, offsetBy: midOffset, limitedBy: input.endIndex)
        ?? input.endIndex
    let old = String(input[..<mid])
    let new = String(input[mid...])

    let result = firstDivergingLine(old: old, new: new)
    let oldLineCount = old.components(separatedBy: "\n").count
    let newLineCount = new.components(separatedBy: "\n").count

    precondition(result >= 0)
    precondition(
        result <= min(oldLineCount, newLineCount),
        "result \(result) out of bounds (old=\(oldLineCount), new=\(newLineCount))"
    )

    let selfResult = firstDivergingLine(old: old, new: old)
    precondition(
        selfResult == oldLineCount,
        "identical inputs must diverge at end, got \(selfResult)"
    )

    return 0
}

// Inlined from MarkdownView.swift — cannot import SwiftUI in a headless fuzz target.
private func firstDivergingLine(old: String, new: String) -> Int {
    let oldLines = old.components(separatedBy: "\n")
    let newLines = new.components(separatedBy: "\n")
    for i in 0..<min(oldLines.count, newLines.count) {
        if oldLines[i] != newLines[i] { return i }
    }
    return min(oldLines.count, newLines.count)
}
