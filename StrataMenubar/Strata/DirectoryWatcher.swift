import Foundation

/// Reports changes to a directory's entries until it is released. A directory that does not exist cannot be watched
/// (nil); whoever watches its parent arms it once it appears.
final class DirectoryWatcher {
    private let source: DispatchSourceFileSystemObject
    private let lock = NSLock()
    private var stale = false

    /// The directory itself was deleted or renamed: the source follows the dead vnode, so the path needs a new one.
    var isStale: Bool { lock.withLock { stale } }

    init?(path: String, onChange: @escaping @Sendable () -> Void) {
        // O_EVTONLY opens for notifications only, so the watch neither blocks an unmount nor counts as a reader.
        let descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .delete, .rename],
            queue: .global()
        )
        self.source = source
        source.setEventHandler { [weak self] in
            if let self, !self.source.data.isDisjoint(with: [.delete, .rename]) {
                self.lock.withLock { self.stale = true }
            }
            onChange()
        }
        source.setCancelHandler { close(descriptor) }
        source.activate()
    }

    deinit {
        source.cancel()
    }
}
