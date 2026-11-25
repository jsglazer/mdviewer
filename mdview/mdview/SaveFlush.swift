import AppKit
import ObjectiveC

/// Makes sure every save writes the editor's latest text.
///
/// The editor sends its text to the document ~100 ms after typing pauses. A save
/// that starts inside that window (⌘S right after a keystroke, closing the window,
/// autosave when the app is deactivated, quitting) would otherwise write the document
/// without the last few characters.
///
/// This hooks NSDocument's three asynchronous entry points that lead to a save:
/// - `saveDocumentWithDelegate:didSaveSelector:contextInfo:` (Save, ⌘S)
/// - `canCloseDocumentWithDelegate:shouldCloseSelector:contextInfo:` (closing a window,
///   and each document when the app quits)
/// - `autosaveWithImplicitCancellability:completionHandler:` (autosave in place)
///
/// and, on `NSDocumentController`, `reviewUnsavedDocumentsWithAlertTitle:cancellable:
/// delegate:didReviewAllSelector:contextInfo:`, which runs when the app quits: every
/// pending edit is handed over first, so a document whose only change is still in
/// flight counts as edited and is saved rather than dropped.
///
/// If an editor showing the document has an edit still inside its debounce window, the
/// call waits until the page has handed that edit over, then proceeds. Otherwise —
/// always, for a document that is only being viewed — it proceeds immediately and
/// unchanged. The hook sits at the entry points rather than on the inner
/// `saveToURL:…` because by then AppKit may already hold the document's file access,
/// and a save resumed a run-loop turn later would wait behind it forever.
enum SaveFlush {
    private struct WeakEditorWindow {
        weak var model: DocumentWindowModel?
    }

    private static var models: [WeakEditorWindow] = []
    private static var installed = false

    /// If a page never answers (a hung web process), the save goes ahead anyway.
    private static let timeout = 1.0

    /// Installs the hooks. Call once, before any document opens.
    static func install() {
        guard !installed else { return }
        installed = true
        swap(
            "saveDocumentWithDelegate:didSaveSelector:contextInfo:",
            #selector(NSDocument.mdview_saveDocument(withDelegate:didSave:contextInfo:)))
        swap(
            "canCloseDocumentWithDelegate:shouldCloseSelector:contextInfo:",
            #selector(NSDocument.mdview_canCloseDocument(withDelegate:shouldClose:contextInfo:)))
        swap(
            "autosaveWithImplicitCancellability:completionHandler:",
            #selector(NSDocument.mdview_autosave(withImplicitCancellability:completionHandler:)))
        swap(
            "reviewUnsavedDocumentsWithAlertTitle:cancellable:delegate:didReviewAllSelector:contextInfo:",
            #selector(
                NSDocumentController.mdview_reviewUnsavedDocuments(
                    withAlertTitle:cancellable:delegate:didReviewAll:contextInfo:)),
            in: NSDocumentController.self)
    }

    private static func swap(
        _ originalName: String, _ replacement: Selector, in cls: AnyClass = NSDocument.self
    ) {
        guard
            let originalMethod = class_getInstanceMethod(cls, NSSelectorFromString(originalName)),
            let replacementMethod = class_getInstanceMethod(cls, replacement)
        else { return }
        method_exchangeImplementations(originalMethod, replacementMethod)
    }

    static func register(_ model: DocumentWindowModel) {
        models.removeAll { $0.model == nil || $0.model === model }
        models.append(WeakEditorWindow(model: model))
    }

    /// Runs `proceed` once every editor showing `document` has delivered its latest
    /// text — synchronously when none has an edit in flight.
    /// With `document` nil, every editor in the app.
    fileprivate static func flushEditors(
        for document: NSDocument?, then proceed: @escaping () -> Void
    ) {
        models.removeAll { $0.model == nil }
        let pending = models.compactMap { entry -> DocumentWindowModel? in
            guard let model = entry.model, model.hasPendingEdit, let window = model.window
            else { return nil }
            if let document, NSDocumentController.shared.document(for: window) !== document {
                return nil
            }
            return model
        }
        guard !pending.isEmpty else {
            proceed()
            return
        }

        var remaining = pending.count
        var finished = false
        let finish = {
            guard !finished else { return }
            finished = true
            // One turn of the run loop lets the text binding reach the document
            // before AppKit asks it for its contents.
            DispatchQueue.main.async(execute: proceed)
        }
        for model in pending {
            model.flushPendingEdits {
                remaining -= 1
                if remaining == 0 { finish() }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: finish)
    }
}

// Each method below is swapped with the AppKit method of the matching name by
// `SaveFlush.install()`, so calling its own name from inside runs AppKit's original.
extension NSDocument {
    @objc fileprivate func mdview_saveDocument(
        withDelegate delegate: Any?, didSave selector: Selector?,
        contextInfo: UnsafeMutableRawPointer?
    ) {
        SaveFlush.flushEditors(for: self) { [self] in
            mdview_saveDocument(withDelegate: delegate, didSave: selector, contextInfo: contextInfo)
        }
    }

    @objc fileprivate func mdview_canCloseDocument(
        withDelegate delegate: Any, shouldClose selector: Selector?,
        contextInfo: UnsafeMutableRawPointer?
    ) {
        SaveFlush.flushEditors(for: self) { [self] in
            mdview_canCloseDocument(
                withDelegate: delegate, shouldClose: selector, contextInfo: contextInfo)
        }
    }

    @objc fileprivate func mdview_autosave(
        withImplicitCancellability implicitlyCancellable: Bool,
        completionHandler: @escaping (Error?) -> Void
    ) {
        SaveFlush.flushEditors(for: self) { [self] in
            mdview_autosave(
                withImplicitCancellability: implicitlyCancellable,
                completionHandler: completionHandler)
        }
    }
}

extension NSDocumentController {
    @objc fileprivate func mdview_reviewUnsavedDocuments(
        withAlertTitle title: String?, cancellable: Bool, delegate: Any?,
        didReviewAll selector: Selector?, contextInfo: UnsafeMutableRawPointer?
    ) {
        SaveFlush.flushEditors(for: nil) { [self] in
            mdview_reviewUnsavedDocuments(
                withAlertTitle: title, cancellable: cancellable, delegate: delegate,
                didReviewAll: selector, contextInfo: contextInfo)
        }
    }
}
