import SwiftUI

struct ContentView: View {
    let document: mdviewDocument
    let fileURL: URL?

    @State private var text: String = ""
    @State private var watcher: FileWatcher?

    var body: some View {
        MarkdownView(markdown: text)
            .frame(minWidth: 480, minHeight: 320)
            .onAppear {
                text = document.text
                if let url = fileURL {
                    watcher = FileWatcher(url: url) { updated in
                        text = updated
                    }
                }
            }
            .onDisappear {
                watcher = nil
            }
    }
}

#Preview {
    ContentView(document: mdviewDocument(), fileURL: nil)
}
