// swift-tools-version: 6.2
//
// MarkdownRenderKit — the rendering engine shared by mdview (viewer) and mdedit (editor):
// the WKWebView preview (markdown-it, KaTeX, highlight.js, callouts, highlights,
// frontmatter, relative images), Outline/Find sidebars, Print Preview + PDF export,
// and the CodeMirror 6 editor view.
//
// Resources are copied verbatim (not processed) so the render template, its scripts,
// stylesheets and the KaTeX fonts stay side by side in one folder: katex.min.css
// references its fonts by bare filename.
import PackageDescription

let package = Package(
    name: "MarkdownRenderKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MarkdownRenderKit", targets: ["MarkdownRenderKit"])
    ],
    targets: [
        .target(
            name: "MarkdownRenderKit",
            resources: [.copy("Resources")],
            swiftSettings: [
                // Match the app targets: UI code, main-actor by default.
                .defaultIsolation(MainActor.self),
                .swiftLanguageMode(.v5),
                .enableUpcomingFeature("InferIsolatedConformances"),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("MemberImportVisibility"),
            ]
        )
    ]
)
