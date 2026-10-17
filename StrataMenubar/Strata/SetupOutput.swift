import Foundation

/// What a line of setup's output says.
enum SetupEvent: Equatable, Sendable {
    /// `=== Step N: title ===`; there are seven, the download is 5 and the preparation 6.
    case step(number: Int, title: String)
    /// `\r  <file>: X.XX / Y.YY GB (NN%)`, which setup prints every two seconds while a shard downloads.
    case shardProgress(name: String, haveBytes: Int64, totalBytes: Int64)
    /// `[ok] <file> already downloaded`
    case alreadyDownloaded(name: String)
    /// `[X]  message`, setup's own failure line; the last one explains an exit status of 1.
    case failure(message: String)
    /// `stopped.`, printed when setup catches an interrupt.
    case stopped
}

/// Reads setup's output as it is appended to the log. Progress lines end in a carriage return, which overwrites them
/// in a terminal, so both line endings separate lines; the last piece of a read may be cut mid-line and waits for
/// the rest.
struct SetupOutputParser: Sendable {
    private var remainder = ""

    mutating func feed(_ text: String) -> [SetupEvent] {
        var lines = (remainder + text).components(separatedBy: .newlines)
        remainder = lines.removeLast()
        var events = lines.compactMap(Self.event(for:))
        // A progress line is only terminated by the next one two seconds later; its closing percentage is its end.
        if let event = Self.event(for: remainder), case .shardProgress = event {
            events.append(event)
            remainder = ""
        }
        return events
    }

    /// The last line once the output has ended without a line break.
    mutating func finish() -> [SetupEvent] {
        let last = remainder
        remainder = ""
        return Self.event(for: last).map { [$0] } ?? []
    }

    private static func event(for line: String) -> SetupEvent? {
        let step = /^=== Step (\d+): (.+?) ===$/
        let progress = /^\s*(\S+): +([\d.]+) \/ ([\d.]+) GB \((\d+)%\)\s*$/
        let alreadyDownloaded = /^\[ok\] (\S+) already downloaded/
        let failure = /^\[X\]\s+(.*)$/
        if let match = line.wholeMatch(of: step), let number = Int(match.1) {
            return .step(number: number, title: String(match.2))
        }
        if let match = line.wholeMatch(of: progress), let have = Double(match.2), let total = Double(match.3) {
            return .shardProgress(name: String(match.1), haveBytes: Int64((have * 1e9).rounded()), totalBytes: Int64((total * 1e9).rounded()))
        }
        if let match = line.firstMatch(of: alreadyDownloaded) {
            return .alreadyDownloaded(name: String(match.1))
        }
        if let match = line.wholeMatch(of: failure) {
            return .failure(message: String(match.1).trimmingCharacters(in: .whitespaces))
        }
        if line.trimmingCharacters(in: .whitespaces) == "stopped." {
            return .stopped
        }
        return nil
    }
}
