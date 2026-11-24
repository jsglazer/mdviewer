import MarkdownRenderKit
import SwiftUI

/// Settings storage. Custom CSS lives in mdview's defaults domain so both apps style
/// the preview identically; editor-only settings live in mdedit's own domain.
enum EditorSettings {
    /// mdview's preferences, shared for the custom preview CSS.
    static let mdviewDefaults = UserDefaults(suiteName: "com.jsglazer.mdview") ?? .standard

    enum Key {
        static let customCSS = "customCSS"
        static let fontFamily = "editorFontFamily"
        static let fontSize = "editorFontSize"
        static let lineNumbers = "editorLineNumbers"
        static let lineWrapping = "editorLineWrapping"
        static let splitFraction = "editorSplitFraction"
    }

    static let defaultFontSize = 14.0
    static let fontSizeRange = 10.0...28.0

    /// Editor font choices: a label and the CSS font-family list sent to CodeMirror.
    static let fonts: [(name: String, css: String)] = [
        ("System Monospace", "ui-monospace, \"SF Mono\", Menlo, monospace"),
        ("Menlo", "Menlo, monospace"),
        ("Courier New", "\"Courier New\", Courier, monospace"),
        ("System (proportional)", "-apple-system, \"SF Pro Text\", sans-serif"),
        ("New York (serif)", "ui-serif, \"New York\", Georgia, serif"),
    ]
    static var defaultFontFamily: String { fonts[0].css }
}

struct EditorSettingsView: View {
    @AppStorage(EditorSettings.Key.fontFamily) private var fontFamily = EditorSettings
        .defaultFontFamily
    @AppStorage(EditorSettings.Key.fontSize) private var fontSize = EditorSettings.defaultFontSize
    @AppStorage(EditorSettings.Key.lineNumbers) private var lineNumbers = false
    @AppStorage(EditorSettings.Key.lineWrapping) private var lineWrapping = true
    @AppStorage(EditorSettings.Key.customCSS, store: EditorSettings.mdviewDefaults)
    private var savedCSS = ""
    @State private var draftCSS = ""

    var body: some View {
        Form {
            Section("Editor") {
                Picker("Font", selection: $fontFamily) {
                    ForEach(EditorSettings.fonts, id: \.css) { font in
                        Text(font.name).tag(font.css)
                    }
                }
                Stepper(
                    "Size: \(Int(fontSize)) pt", value: $fontSize, in: EditorSettings.fontSizeRange,
                    step: 1)
                Toggle("Line numbers", isOn: $lineNumbers)
                Toggle("Soft wrap long lines", isOn: $lineWrapping)
            }

            Section("Preview CSS (shared with mdview)") {
                Text("Applied on top of the default preview styles in both mdview and mdedit.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $draftCSS)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .background(Color(NSColor.textBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .frame(minHeight: 160)
                HStack {
                    Spacer()
                    Button("Revert") { draftCSS = savedCSS }
                        .disabled(draftCSS == savedCSS)
                    Button("Save") { savedCSS = draftCSS }
                        .disabled(draftCSS == savedCSS)
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .onAppear { draftCSS = savedCSS }
    }
}
