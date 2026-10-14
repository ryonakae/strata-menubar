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

    var runConfig: URL { applicationSupport.appending(path: "strata-q2_0.run.json") }
    var serverLog: URL { logs.appending(path: "server.log") }
    var engineLog: URL { logs.appending(path: "engine.log") }
}
