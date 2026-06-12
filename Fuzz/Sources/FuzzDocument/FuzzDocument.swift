import Foundation

/// Exercises mdviewDocument's UTF-8 decoding and text round-trip.
///
/// Mirrors mdviewDocument.init(configuration:):
///   guard let data = ..., let string = String(data: data, encoding: .utf8)
///
/// Invariants checked:
///   - UTF-8 round-trip: re-encoding must produce identical bytes.
///   - Unicode views are consistent (no crash on surrogate pairs / combining chars).
///   - JSON encoding for WKWebView handoff does not crash.
public func fuzzDocument(_ start: UnsafePointer<UInt8>, _ count: Int) -> CInt {
    let data = Data(bytes: start, count: count)

    if let text = String(data: data, encoding: .utf8) {
        if let reEncoded = text.data(using: .utf8) {
            precondition(reEncoded == data, "UTF-8 round-trip mismatch")
        }
        _ = text.unicodeScalars.count
        _ = text.utf16.count
        _ = text.count
        _ = try? JSONEncoder().encode(text)
    }

    _ = String(data: data, encoding: .utf16)
    _ = String(data: data, encoding: .isoLatin1)
    _ = String(data: data, encoding: .windowsCP1252)

    return 0
}
