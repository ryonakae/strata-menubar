import Foundation

/// Where this app keeps its own files. Nothing under the Strata checkout is written.
struct AppPaths: Equatable, Sendable {
    var applicationSupport: URL
    var logs: URL

    static let standard: AppPaths = {
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let library = fm.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        return AppPaths(
            applicationSupport: support.appending(path: "StrataMenubar", directoryHint: .isDirectory),
            logs: library.appending(path: "Logs/StrataMenubar", directoryHint: .isDirectory)
        )
    }()

    /// The run config written for one installed model: the base `strata-<tag>.json` with the managed keys changed.
    func runConfig(for tag: String) -> URL {
        applicationSupport.appending(path: "strata-\(tag).run.json")
    }

    var serverLog: URL { logs.appending(path: "server.log") }
    var engineLog: URL { logs.appending(path: "engine.log") }
    /// Setup's output, appended across runs; the progress is read from here.
    var setupLog: URL { logs.appending(path: "setup.log") }
}
