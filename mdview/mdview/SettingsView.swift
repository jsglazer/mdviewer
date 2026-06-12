import SwiftUI

struct SettingsView: View {
    @AppStorage("customCSS") private var savedCSS: String = ""
    @AppStorage("maxRecentFiles") private var maxRecentFiles: Int = 10
    @State private var draftCSS: String = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section("Recent Files") {
                Stepper(
                    "Show \(maxRecentFiles) recent files", value: $maxRecentFiles, in: 5...50,
                    step: 5
                )
                .help("Controls how many files appear in the Open Recent submenu")
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
