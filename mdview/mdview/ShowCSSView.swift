import SwiftUI

struct ShowCSSView: View {
    let css: String

    private var lineCount: Int { css.components(separatedBy: "\n").count }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Document CSS")
                    .font(.headline)
                Spacer()
                Text("\(lineCount) lines")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            Divider()
            ScrollView {
                Text(css.isEmpty ? "(no inline CSS found)" : css)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
        }
        .frame(minWidth: 560, minHeight: 400)
    }
}
