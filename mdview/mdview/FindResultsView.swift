import SwiftUI

struct FindResultsView: View {
    let results: [FindResult]
    @Binding var selectedIndex: Int?
    let onSelect: (Int) -> Void

    private static let highlightColor = Color.cyan.opacity(0.35)

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if results.isEmpty {
                Spacer()
                Text("No results")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(results) { result in
                                FindRow(
                                    result: result,
                                    isSelected: selectedIndex == result.id,
                                    highlightColor: Self.highlightColor,
                                    onSelect: {
                                        selectedIndex = result.id
                                        onSelect(result.id)
                                    }
                                )
                                .id(result.id)
                                Divider().padding(.leading, 8)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .onChange(of: selectedIndex) { _, idx in
                        if let idx {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                proxy.scrollTo(idx, anchor: .center)
                            }
                        }
                    }
                }
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
        .onChange(of: results) { _, _ in selectedIndex = nil }
    }

    private var header: some View {
        HStack {
            Text(results.isEmpty ? "No matches" : "\(results.count) match\(results.count == 1 ? "" : "es")")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(NSColor.controlBackgroundColor))
    }
}

private struct FindRow: View {
    let result: FindResult
    let isSelected: Bool
    let highlightColor: Color
    let onSelect: () -> Void

    var body: some View {
        snippet
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(isSelected ? highlightColor : Color(NSColor.controlBackgroundColor).opacity(0.001))
            .contentShape(Rectangle())
            .onTapGesture { onSelect() }
    }

    private var snippet: Text {
        var t = Text("")
        if !result.before.isEmpty {
            t = t + Text("…\(result.before) ").foregroundStyle(.secondary)
        }
        t = t + Text(result.match).bold()
        if !result.after.isEmpty {
            t = t + Text(" \(result.after)…").foregroundStyle(.secondary)
        }
        return t.font(.caption)
    }
}
