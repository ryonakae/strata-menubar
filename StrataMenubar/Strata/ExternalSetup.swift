import Foundation

/// A Strata setup running outside this app, found by its command line. It is only reported, never signalled: the
/// pack it works on must not be downloaded or deleted from here meanwhile.
struct ExternalSetup: Equatable, Sendable {
    var pid: pid_t
    /// The `--model` on its command line; nil when it was started interactively and may be preparing any pack.
    var model: String?

    /// Every `setup_mac.py` process (setup.sh and setup.py end up running it) outside the group `excludingGroup`,
    /// which is the setup this app runs itself.
    static func running(excludingGroup: pid_t?) -> [ExternalSetup] {
        let pgrep = Process()
        pgrep.executableURL = URL(filePath: "/usr/bin/pgrep")
        pgrep.arguments = ["-fl", "setup_mac.py"]
        let pipe = Pipe()
        pgrep.standardOutput = pipe
        pgrep.standardError = FileHandle.nullDevice
        guard (try? pgrep.run()) != nil else { return [] }
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        pgrep.waitUntilExit()
        return output.split(separator: "\n").compactMap { line in
            let words = line.split(separator: " ").map(String.init)
            guard let first = words.first, let pid = pid_t(first) else { return nil }
            if let excludingGroup, getpgid(pid) == excludingGroup {
                return nil
            }
            return ExternalSetup(pid: pid, model: model(in: Array(words.dropFirst())))
        }
    }

    private static func model(in arguments: [String]) -> String? {
        for (index, argument) in arguments.enumerated() {
            if argument == "--model", index + 1 < arguments.count {
                return arguments[index + 1]
            }
            if argument.hasPrefix("--model=") {
                return String(argument.dropFirst("--model=".count))
            }
        }
        return nil
    }
}
