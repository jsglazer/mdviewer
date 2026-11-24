import AppKit

/// Reloads a document window when its file changes on disk while it has no unsaved
/// edits.
///
/// SwiftUI's `DocumentGroup` documents are `NSDocument`s and already present the file
/// (NSFilePresenter), so a save over a file changed by another app gets AppKit's
/// standard "changed by another application" conflict alert. What they don't do is
/// pick up an outside change on their own while clean — the window keeps showing the
/// old text. This adds only that piece, through the same file-coordination system
/// (no polling, no FileWatcher): when the file changes, or the app becomes active,
/// a clean document is reverted to what's on disk with the standard
/// `revert(toContentsOf:ofType:)`. A document with unsaved edits is never touched.
final class ExternalChangeMonitor: NSObject, NSFilePresenter {
    private(set) var presentedItemURL: URL?
    let presentedItemOperationQueue = OperationQueue.main
    private weak var window: NSWindow?
    private var pendingCheck: DispatchWorkItem?
    private var activationObserver: Any?

    /// Coalesces the burst of events a single save produces (write + attribute
    /// changes, or the remove/rename pair of an atomic save).
    private static let settleDelay = 0.25

    init(url: URL, window: NSWindow?) {
        presentedItemURL = url
        self.window = window
        super.init()
        NSFileCoordinator.addFilePresenter(self)
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleCheck() }
        }
    }

    func stop() {
        pendingCheck?.cancel()
        NSFileCoordinator.removeFilePresenter(self)
        if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) }
        activationObserver = nil
    }

    // MARK: - NSFilePresenter

    func presentedItemDidChange() { scheduleCheck() }

    func presentedItemDidMove(to newURL: URL) { presentedItemURL = newURL }

    // MARK: - Reload

    private func scheduleCheck() {
        pendingCheck?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.reloadIfCleanAndStale() }
        pendingCheck = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.settleDelay, execute: work)
    }

    private func reloadIfCleanAndStale() {
        guard let window,
            let document = NSDocumentController.shared.document(for: window),
            !document.isDocumentEdited,
            let url = document.fileURL,
            let type = document.fileType,
            let onDisk = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate,
            let known = document.fileModificationDate,
            onDisk > known
        else { return }
        // The file may be mid-replace (atomic save); a failed read is retried on the
        // next change event or activation rather than surfaced as an error.
        try? document.revert(toContentsOf: url, ofType: type)
    }
}
