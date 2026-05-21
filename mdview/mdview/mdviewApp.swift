import SwiftUI

@main
struct mdviewApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        DocumentGroup(viewing: mdviewDocument.self) { config in
            ContentView(document: config.document)
        }
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}
