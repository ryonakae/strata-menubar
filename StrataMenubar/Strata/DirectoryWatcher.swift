import Foundation

/// Reports changes to a directory's entries until it is released. A directory that does not exist cannot be watched
/// (nil); whoever watches its parent arms it once it appears.
final class DirectoryWatcher {
    private let source: DispatchSourceFileSystemObject

    init?(path: String, onChange: @escaping @Sendable () -> Void) {
        // O_EVTONLY opens for notifications only, so the watch neither blocks an unmount nor counts as a reader.
        let descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .delete, .rename],
            queue: .global()
        )
        source.setEventHandler(handler: onChange)
        source.setCancelHandler { close(descriptor) }
        source.activate()
        self.source = source
    }

    deinit {
        source.cancel()
    }
}
