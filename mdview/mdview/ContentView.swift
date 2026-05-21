import SwiftUI

struct ContentView: View {
    let document: mdviewDocument

    var body: some View {
        MarkdownView(markdown: document.text)
            .frame(minWidth: 480, minHeight: 320)
    }
}

#Preview {
    ContentView(document: mdviewDocument())
}
