import Foundation

/// Locates the bundled render template and its sibling assets (scripts, stylesheets,
/// KaTeX fonts) inside this package's resource bundle.
public enum RenderResources {
    /// `render-template.html`, the page every preview and print WebView loads.
    public static var templateURL: URL? {
        Bundle.module.url(
            forResource: "render-template", withExtension: "html", subdirectory: "Resources")
    }

    /// The folder holding the template and everything it references; WebViews are
    /// granted read access to exactly this directory.
    public static var directoryURL: URL? { templateURL?.deletingLastPathComponent() }

    /// URL of any other bundled asset (e.g. the editor page and its script).
    public static func url(forResource name: String, withExtension ext: String) -> URL? {
        Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Resources")
    }
}

extension Notification.Name {
    /// Posted when the user asks for in-document Find (⌘F inside a preview).
    public static let mdviewOpenFind = Notification.Name("mdviewOpenFind")
    /// Posted when Escape is pressed inside a preview, to dismiss the find bar.
    public static let mdviewCloseFind = Notification.Name("mdviewCloseFind")
}
