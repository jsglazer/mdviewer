import AppKit

/// Keeps a document window in step with its file on disk.
///
/// One mechanism for both jobs mdview needs:
/// - **Live reload / Tail Mode.** A kernel file-system event source on the file
///   (write, extend, rename, delete) fires within milliseconds of another process
///   writing, so a log being appended to several times a second is followed smoothly.
///   Editors that save by rename or delete-and-recreate (vim, atomic writes) replace
///   the inode, so the source is re-opened on the new file.
/// - **Never clobber edits.** The reload is the standard
///   `NSDocument.revert(toContentsOf:ofType:)`, and it only runs when the document has
///   no unsaved changes and the file on disk is newer than what the document last read
///   or wrote. A document with unsaved edits is never touched; saving it over an
///   outside change gets AppKit's "changed by another application" sheet.
///
/// The app becoming active also triggers a check, which catches anything the event
/// source missed (e.g. a file replaced while its folder was briefly unavailable).
final class DocumentFileMonitor {
    private let url: URL
    private weak var window: NSWindow?
    private var source: DispatchSourceFileSystemObject?
    private var descriptor: Int32 = -1
    private var pendingCheck: DispatchWorkItem?
    private var activationObserver: Any?
    private var stopped = false

    /// Coalesces the burst of events a single write produces (large writes arrive in
    /// chunks; an atomic save is a remove + rename pair).
    private static let settleDelay = 0.08
    /// How often to look for the file again while it is missing (mid-rotation).
    private static let retryDelay = 0.5

    init(url: URL, window: NSWindow) {
        self.url = url
        self.window = window
        openSource()
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleCheck() }
        }
    }

    func stop() {
        stopped = true
        pendingCheck?.cancel()
        source?.cancel()
        source = nil
        if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) }
        activationObserver = nil
    }

    deinit { stop() }

    // MARK: - Event source

    private func openSource() {
        source?.cancel()
        source = nil
        guard !stopped else { return }

        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else {
            // The file doesn't exist right now (log rotation, atomic replace in
            // progress): keep looking until it reappears.
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.retryDelay) { [weak self] in
                self?.openSource()
            }
            return
        }
        descriptor = fd

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .extend, .rename, .delete], queue: .main)
        src.setEventHandler { [weak self, weak src] in
            guard let self, let src else { return }
            let flags = src.data
            self.scheduleCheck()
            if flags.contains(.rename) || flags.contains(.delete) {
                // The path now names a different inode (or nothing yet): follow it.
                src.cancel()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                    self?.openSource()
                }
            }
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
    }

    // MARK: - Reload

    private func scheduleCheck() {
        pendingCheck?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.reloadIfCleanAndStale() }
        pendingCheck = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.settleDelay, execute: work)
    }

    private func reloadIfCleanAndStale() {
        guard !stopped, let window,
            let document = NSDocumentController.shared.document(for: window),
            !document.isDocumentEdited,
            let fileURL = document.fileURL,
            let type = document.fileType,
            let onDisk = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate
        else { return }
        if let known = document.fileModificationDate, onDisk <= known { return }
        // The file may be mid-replace; a failed read is retried on the next change
        // event or activation rather than surfaced as an error.
        try? document.revert(toContentsOf: fileURL, ofType: type)
    }
}
