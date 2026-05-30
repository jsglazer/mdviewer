import Foundation

class FileWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var fd: Int32 = -1
    private let url: URL
    private let onChange: (String) -> Void

    init(url: URL, onChange: @escaping (String) -> Void) {
        self.url = url
        self.onChange = onChange
        start()
    }

    private func start() {
        // Cancel any existing source before opening a new descriptor
        source?.cancel()
        source = nil

        fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else {
            // File doesn't exist yet (e.g., mid-rotation) — retry until it reappears
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.start()
            }
            return
        }

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete, .extend],
            queue: .main
        )

        src.setEventHandler { [weak self] in
            guard let self else { return }
            let flags = src.data
            // Small delay so writes are fully flushed before reading
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                guard let self else { return }
                if let text = try? String(contentsOf: self.url, encoding: .utf8) {
                    self.onChange(text)
                }
                // Editors like vim save via rename/delete+recreate — restart on the new inode
                if flags.contains(.rename) || flags.contains(.delete) {
                    self.source?.cancel()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                        self?.start()
                    }
                }
            }
        }

        src.setCancelHandler { [weak self] in
            guard let self, self.fd >= 0 else { return }
            close(self.fd)
            self.fd = -1
        }

        src.resume()
        source = src
    }

    deinit { source?.cancel() }
}
