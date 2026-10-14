import Foundation

/// Keeps the two log files from growing without bound: a file over the limit is moved aside once at the next launch.
struct LogStore: Sendable {
    static let rotateAboveBytes: UInt64 = 10_000_000

    let paths: AppPaths

    func prepareForLaunch() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: paths.logs, withIntermediateDirectories: true)
        for log in [paths.serverLog, paths.engineLog] {
            try rotateIfLarge(log, fileManager: fm)
        }
    }

    private func rotateIfLarge(_ log: URL, fileManager fm: FileManager) throws {
        let path = log.path(percentEncoded: false)
        guard let size = try? fm.attributesOfItem(atPath: path)[.size] as? UInt64, size > Self.rotateAboveBytes else {
            return
        }
        let previous = log.appendingPathExtension("1")
        if fm.fileExists(atPath: previous.path(percentEncoded: false)) {
            try fm.removeItem(at: previous)
        }
        try fm.moveItem(at: log, to: previous)
    }
}
