import SwiftUI

struct SettingsView: View {
    @AppStorage("customCSS") private var savedCSS: String = ""
    @AppStorage("maxRecentFiles") private var maxRecentFiles: Int = 10
    @AppStorage(EditorSettings.Key.openLayout) private var openLayout = EditorLayout.preview
        .rawValue
    @AppStorage(EditorSettings.Key.fontFamily) private var fontFamily = EditorSettings
        .defaultFontFamily
    @AppStorage(EditorSettings.Key.fontSize) private var fontSize = EditorSettings.defaultFontSize
    @AppStorage(EditorSettings.Key.lineNumbers) private var lineNumbers = false
    @AppStorage(EditorSettings.Key.lineWrapping) private var lineWrapping = true
    @State private var draftCSS: String = ""
    @Environment(\.dismiss) private var dismiss

    private static let openLayoutHelp =
        "The layout a file opens in the first time. "
        + "After that, each file reopens in the layout you last left it in."

    var body: some View {
        Form {
            Section("Recent Files") {
                Stepper(
                    "Show \(maxRecentFiles) recent files", value: $maxRecentFiles, in: 5...50,
                    step: 5
                )
                .help("Controls how many files appear in the Open Recent submenu")
            }

            Section("Editing") {
                Picker("Open documents in", selection: $openLayout) {
                    ForEach(EditorLayout.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .help(Self.openLayoutHelp)
                Picker("Editor font", selection: $fontFamily) {
                    ForEach(EditorSettings.fonts, id: \.css) { font in
                        Text(font.name).tag(font.css)
                    }
                }
                Stepper(
                    "Editor font size: \(Int(fontSize)) pt", value: $fontSize,
                    in: EditorSettings.fontSizeRange, step: 1)
                Toggle("Editor line numbers", isOn: $lineNumbers)
                Toggle("Soft wrap long lines", isOn: $lineWrapping)
            }

            Section("Custom CSS") {
                Text("Applied on top of the default document styles.")
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
                    .frame(minHeight: 180)

                HStack {
                    if !savedCSS.isEmpty {
                        Button("Clear CSS", role: .destructive) {
                            draftCSS = ""
                            savedCSS = ""
                        }
                    }
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
