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
          fd = open(url.path, O_EVTONLY)
          guard fd >= 0 else { return }

          source = DispatchSource.makeFileSystemObjectSource(
              fileDescriptor: fd,
              eventMask: [.write, .rename, .delete],
              queue: .main
          )

          source?.setEventHandler { [weak self] in
              guard let self else { return }
              let flags = self.source?.data ?? []
              // Small delay so the write is fully flushed before we read
              DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                  if let text = try? String(contentsOf: self.url, encoding: .utf8) {
                      self.onChange(text)
                  }
                  // Editors like vim save via rename — restart watcher on the new inode
                  if flags.contains(.rename) || flags.contains(.delete) {
                      self.source?.cancel()
                      DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                          self.start()
                      }
                  }
              }
          }

          source?.setCancelHandler { [weak self] in
              guard let self, self.fd >= 0 else { return }
              close(self.fd)
              self.fd = -1
          }

          source?.resume()
      }

      deinit { source?.cancel() }
  }
