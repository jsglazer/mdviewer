import Foundation
import FuzzDocument
import FuzzImagePath
import FuzzDiffing

/// Local smoke test — runs each fuzz function against fixed inputs to verify
/// the logic and invariants without requiring libFuzzer.
/// Run with: cd Fuzz && swift run SmokeTest

func run(_ label: String, _ inputs: [String], _ fn: (UnsafePointer<UInt8>, Int) -> CInt) {
    for input in inputs {
        let bytes = Array(input.utf8)
        let result = bytes.withUnsafeBufferPointer { buf -> CInt in
            guard let base = buf.baseAddress else { return 0 }
            return fn(base, buf.count)
        }
        precondition(result == 0, "\(label): unexpected return value for input \(input.debugDescription)")
    }
    print("✓ \(label) — \(inputs.count) inputs passed")
}

// FuzzDocument
run("FuzzDocument", [
    "",
    "# Hello\n\nBasic markdown.",
    "日本語 • émoji 🎉",
    String(repeating: "a", count: 10_000),
    "\u{0000}\u{FEFF}\u{200B}",  // null, BOM, zero-width space
], fuzzDocument)

// FuzzImagePath
run("FuzzImagePath", [
    "image.png",
    "subdir/photo.jpg",
    "name%20with%20spaces.png",
    "a/b/c/deep.png",
    // These must NOT crash — the fix in MarkdownView.swift rejects them cleanly
    "../sibling.png",
    "../../escape.png",
    "../../../etc/passwd",
    "%2e%2e%2fetc%2fpasswd",
], fuzzImagePath)

// FuzzDiffing
run("FuzzDiffing", [
    "ab",
    "# Doc\n\nLine one.\nLine two.\n",
    "\n\n\n",
    String(repeating: "line\n", count: 500),
], fuzzDiffing)

print("\nAll smoke tests passed.")
