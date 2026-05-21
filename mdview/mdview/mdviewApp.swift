import SwiftUI
import AppKit

@main
struct mdviewApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        DocumentGroup(viewing: mdviewDocument.self) { config in
            ContentView(document: config.document, fileURL: config.fileURL)
        }
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandGroup(replacing: .appInfo) {
                Button("About mdview") {
                    NSApp.orderFrontStandardAboutPanel(options: [
                        .applicationIcon: NSApp.applicationIconImage as Any,
                        .applicationName: "mdview" as Any,
                        .version: "" as Any
                    ])
                }
            }
        }
    }
}
