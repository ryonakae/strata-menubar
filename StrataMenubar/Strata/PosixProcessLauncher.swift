import Darwin
import Foundation

struct SpawnError: Error, LocalizedError, Equatable {
    let step: String
    let code: Int32

    var errorDescription: String? {
        "\(step) failed: \(String(cString: strerror(code))) (\(code))"
    }
}

/// Spawns the server with posix_spawn in a new process group, with stdin from /dev/null and stdout/stderr appended to a
/// log file, so that nothing blocks on an unread pipe and the whole group can be signalled later.
struct PosixProcessLauncher: ProcessLaunching {
    func launch(_ plan: LaunchPlan) throws -> any OwnedProcess {
        let logPath = plan.standardOutputLog.path(percentEncoded: false)
        try FileManager.default.createDirectory(
            at: plan.standardOutputLog.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var attributes: posix_spawnattr_t? = nil
        try check(posix_spawnattr_init(&attributes), "posix_spawnattr_init")
        defer { posix_spawnattr_destroy(&attributes) }
        let flags = POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF
        try check(posix_spawnattr_setflags(&attributes, Int16(flags)), "posix_spawnattr_setflags")
        try check(posix_spawnattr_setpgroup(&attributes, 0), "posix_spawnattr_setpgroup")
        var unblocked = sigset_t()
        sigemptyset(&unblocked)
        try check(posix_spawnattr_setsigmask(&attributes, &unblocked), "posix_spawnattr_setsigmask")
        var defaults = sigset_t()
        sigfillset(&defaults)
        try check(posix_spawnattr_setsigdefault(&attributes, &defaults), "posix_spawnattr_setsigdefault")

        var actions: posix_spawn_file_actions_t? = nil
        try check(posix_spawn_file_actions_init(&actions), "posix_spawn_file_actions_init")
        defer { posix_spawn_file_actions_destroy(&actions) }
        try check(posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0), "stdin")
        try check(posix_spawn_file_actions_addopen(&actions, STDOUT_FILENO, logPath, O_WRONLY | O_CREAT | O_APPEND, 0o644), "stdout")
        try check(posix_spawn_file_actions_adddup2(&actions, STDOUT_FILENO, STDERR_FILENO), "stderr")
        try check(posix_spawn_file_actions_addchdir_np(&actions, plan.workingDirectory.path(percentEncoded: false)), "chdir")

        let executable = plan.executable.path(percentEncoded: false)
        let argv = [executable] + plan.arguments
        let envp = plan.environment.map { "\($0.key)=\($0.value)" }
        var pid: pid_t = 0
        let rc = withCStringArray(argv) { argvPointer in
            withCStringArray(envp) { envPointer in
                posix_spawn(&pid, executable, &actions, &attributes, argvPointer, envPointer)
            }
        }
        guard rc == 0 else {
            throw SpawnError(step: "posix_spawn \(executable)", code: rc)
        }
        return PosixOwnedProcess(pid: pid)
    }

    private func check(_ rc: Int32, _ step: String) throws {
        guard rc == 0 else {
            throw SpawnError(step: step, code: rc)
        }
    }

    private func withCStringArray<R>(_ strings: [String], _ body: (UnsafePointer<UnsafeMutablePointer<CChar>?>) -> R) -> R {
        var pointers: [UnsafeMutablePointer<CChar>?] = strings.map { strdup($0) }
        pointers.append(nil)
        defer { pointers.forEach { free($0) } }
        return pointers.withUnsafeBufferPointer { body($0.baseAddress!) }
    }
}

final class PosixOwnedProcess: OwnedProcess, @unchecked Sendable {
    let pid: pid_t
    var processGroup: pid_t { pid }

    private let lock = NSLock()
    private var result: ProcessExit?
    private var waiters: [CheckedContinuation<ProcessExit, Never>] = []
    private var source: DispatchSourceProcess?

    init(pid: pid_t) {
        self.pid = pid
        let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .global())
        self.source = source
        source.setEventHandler { self.reap(blocking: true) }
        source.activate()
        // The child may already have ended before the source was armed.
        reap(blocking: false)
    }

    func waitForExit() async -> ProcessExit {
        await withCheckedContinuation { continuation in
            lock.lock()
            if let result {
                lock.unlock()
                continuation.resume(returning: result)
            } else {
                waiters.append(continuation)
                lock.unlock()
            }
        }
    }

    func exitIfFinished() -> ProcessExit? {
        lock.withLock { result }
    }

    func signal(_ signal: Int32) throws {
        guard kill(pid, signal) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    func signalGroup(_ signal: Int32) throws {
        guard kill(-pid, signal) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    func isGroupAlive() -> Bool {
        kill(-pid, 0) == 0 || errno == EPERM
    }

    private func reap(blocking: Bool) {
        var status: Int32 = 0
        var rc: pid_t
        repeat {
            rc = waitpid(pid, &status, blocking ? 0 : WNOHANG)
        } while rc == -1 && errno == EINTR
        guard rc == pid else {
            return
        }
        let exit: ProcessExit = (status & 0x7f) == 0 ? .exited((status >> 8) & 0xff) : .signaled(status & 0x7f)
        lock.lock()
        guard result == nil else {
            lock.unlock()
            return
        }
        result = exit
        let pending = waiters
        waiters = []
        let source = self.source
        self.source = nil
        lock.unlock()
        source?.cancel()
        pending.forEach { $0.resume(returning: exit) }
    }
}
