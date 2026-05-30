import SwiftUI

struct TOCView: View {
    let items: [TOCItem]
    var activeIDs: Set<String> = []
    let onSelect: (String) -> Void

    @State private var collapsed: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            tocHeader
            Divider()
            if items.isEmpty {
                Spacer()
                Text("No headings")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(visibleItems) { item in
                            TOCRow(
                                item: item,
                                isCollapsed: collapsed.contains(item.id),
                                isCollapsible: hasChildren(item),
                                isActive: activeIDs.contains(item.id),
                                onToggle: { toggleCollapse(item) },
                                onSelect: { onSelect(item.id) }
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
        .onAppear {
            collapsed = Set(items.filter { hasChildren($0) }.map(\.id))
        }
    }

    private var tocHeader: some View {
        HStack(spacing: 6) {
            Text("Outline")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                collapsed = Set(items.filter { hasChildren($0) }.map(\.id))
            } label: {
                Image(systemName: "chevron.up")
                    .imageScale(.small)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Collapse all")

            Button {
                collapsed.removeAll()
            } label: {
                Image(systemName: "chevron.down")
                    .imageScale(.small)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Expand all")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var visibleItems: [TOCItem] {
        var result: [TOCItem] = []
        var hideBelowLevel: Int? = nil
        for item in items {
            if let cutoff = hideBelowLevel {
                if item.level <= cutoff { hideBelowLevel = nil } else { continue }
            }
            result.append(item)
            if collapsed.contains(item.id) { hideBelowLevel = item.level }
        }
        return result
    }

    private func hasChildren(_ item: TOCItem) -> Bool {
        guard let idx = items.firstIndex(where: { $0.id == item.id }), idx + 1 < items.count else { return false }
        for i in (idx + 1)..<items.count {
            if items[i].level <= item.level { break }
            return true
        }
        return false
    }

    private func toggleCollapse(_ item: TOCItem) {
        if collapsed.contains(item.id) { collapsed.remove(item.id) }
        else { collapsed.insert(item.id) }
    }
}

private let tocActiveColor = Color(red: 189/255, green: 1.0, blue: 217/255)

private struct TOCRow: View {
    let item: TOCItem
    let isCollapsed: Bool
    let isCollapsible: Bool
    let isActive: Bool
    let onToggle: () -> Void
    let onSelect: () -> Void

    private var indent: CGFloat { CGFloat((item.level - 1) * 12) }

    var body: some View {
        HStack(spacing: 2) {
            Spacer().frame(width: indent)

            if isCollapsible {
                Button(action: onToggle) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 14, height: 14)
                }
                .buttonStyle(.plain)
            } else {
                Spacer().frame(width: 14)
            }

            Button(action: onSelect) {
                Text(item.text)
                    .font(item.level == 1 ? .caption.weight(.semibold) : .caption)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(isActive ? tocActiveColor : Color.clear)
        .contentShape(Rectangle())
    }
}
