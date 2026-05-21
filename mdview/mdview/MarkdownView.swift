import SwiftUI
import WebKit

struct MarkdownView: NSViewRepresentable {
    let markdown: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        if let htmlURL = Bundle.main.url(forResource: "render-template", withExtension: "html"),
           let resourcesURL = Bundle.main.resourceURL {
            webView.loadFileURL(htmlURL, allowingReadAccessTo: resourcesURL)
        }
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.pendingMarkdown = markdown
        if context.coordinator.isLoaded {
            context.coordinator.render(markdown)
        }
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        weak var webView: WKWebView?
        var isLoaded = false
        var pendingMarkdown = ""

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoaded = true
            render(pendingMarkdown)
        }

        func render(_ markdown: String) {
            guard let webView,
                  let data = try? JSONEncoder().encode(markdown),
                  let json = String(data: data, encoding: .utf8) else { return }
            webView.evaluateJavaScript("window.setMarkdown(\(json))", completionHandler: nil)
        }
    }
}
