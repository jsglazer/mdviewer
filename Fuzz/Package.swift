// swift-tools-version: 5.9
//
// Fuzz target layout:
//   FuzzDocument, FuzzImagePath, FuzzDiffing — library targets compiled with
//     -parse-as-library -sanitize=fuzzer,address inside the OSS-Fuzz Docker image.
//     They export LLVMFuzzerTestOneInput, which libFuzzer drives.
//
//   SmokeTest — local executable that calls each fuzz function with fixed inputs
//     so you can verify the logic builds and asserts cleanly WITHOUT libFuzzer.
//     Run with: swift run SmokeTest   (from inside Fuzz/)
import PackageDescription

let package = Package(
    name: "mdview-fuzz",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "FuzzDocument",  path: "Sources/FuzzDocument"),
        .target(name: "FuzzImagePath", path: "Sources/FuzzImagePath"),
        .target(name: "FuzzDiffing",   path: "Sources/FuzzDiffing"),
        .executableTarget(
            name: "SmokeTest",
            dependencies: ["FuzzDocument", "FuzzImagePath", "FuzzDiffing"],
            path: "Sources/SmokeTest"
        ),
    ]
)
