import PDFKit
import SwiftUI

/// Hosts the PDFView the model owns, so page navigation can be driven imperatively.
private struct PDFViewHost: NSViewRepresentable {
    let pdfView: PDFView
    func makeNSView(context: Context) -> PDFView { pdfView }
    func updateNSView(_ nsView: PDFView, context: Context) {}
}

struct PrintPreviewView: View {
    @ObservedObject var model: PrintPreviewModel

    var body: some View {
        VStack(spacing: 0) {
            pageBar
            Divider()
            preview
            Divider()
            controls
        }
        .frame(minWidth: 480, minHeight: 420)
    }

    // MARK: - Page bar

    private var pageBar: some View {
        HStack(spacing: 8) {
            Button {
                model.goToPreviousPage()
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(model.currentPage <= 1)
            .help("Previous page")
            Text(
                model.pageCount > 0
                    ? "Page \(model.currentPage) of \(model.pageCount)" : "No pages"
            )
            .font(.caption)
            .monospacedDigit()
            .frame(minWidth: 110)
            Button {
                model.goToNextPage()
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(model.currentPage >= model.pageCount)
            .help("Next page")
            Spacer()
            Text(model.paperLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    // MARK: - Preview area

    private var preview: some View {
        ZStack {
            PDFViewHost(pdfView: model.pdfView)
            if model.isRendering {
                ProgressView("Preparing preview…")
                    .padding(20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            }
            if let message = model.errorMessage {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title)
                        .foregroundStyle(.secondary)
                    Text(message)
                        .font(.callout)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .padding(24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 4) {
                GridRow {
                    Toggle("Page numbers", isOn: $model.extras.pageNumbers)
                    Toggle("Title header", isOn: $model.extras.titleHeader)
                }
                GridRow {
                    Toggle("Print date", isOn: $model.extras.printDate)
                    Toggle("Link URLs", isOn: $model.extras.linkURLs)
                }
            }
            .toggleStyle(.checkbox)
            .font(.callout)
            .disabled(model.isRendering)

            HStack(spacing: 10) {
                Button("Page Setup…") { model.pageSetup() }
                    .disabled(model.isRendering)
                scaleControl
                Spacer()
                actionButtons
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var scaleControl: some View {
        HStack(spacing: 4) {
            Text("Scale:")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button {
                model.decreaseScale()
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .disabled(model.isRendering || !model.canDecreaseScale)
            .help("Shrink to fit more on the page")
            Text("\(model.scalePercent)%")
                .font(.callout)
                .monospacedDigit()
                .frame(minWidth: 40)
            Button {
                model.increaseScale()
            } label: {
                Image(systemName: "plus.circle")
            }
            .buttonStyle(.borderless)
            .disabled(model.isRendering || !model.canIncreaseScale)
            .help("Enlarge the printed content")
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        let save = Button("Save PDF…") { model.savePDF() }.disabled(!model.canAct)
        let output = Button("Print…") { model.printNow() }.disabled(!model.canAct)
        if model.intent == .exportPDF {
            save.keyboardShortcut(.defaultAction)
            output
        } else {
            save
            output.keyboardShortcut(.defaultAction)
        }
    }
}
