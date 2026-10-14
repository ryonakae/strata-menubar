import Foundation

/// The process to spawn. Arguments stay an array all the way to posix_spawn; no shell is involved.
struct LaunchPlan: Equatable, Sendable {
    var executable: URL
    var arguments: [String]
    var workingDirectory: URL
    var environment: [String: String]
    var standardOutputLog: URL
}

enum LaunchPlanError: Error, Equatable, LocalizedError {
    case invalidSettings([String])
    case installation([String])
    case configuration(String)

    var errorDescription: String? {
        switch self {
        case .invalidSettings(let messages): "The settings are invalid. " + messages.joined(separator: " ")
        case .installation(let problems): "Strata is not ready. " + problems.joined(separator: " ")
        case .configuration(let message): "The run config could not be written. \(message)"
        }
    }
}

protocol LaunchPlanning: Sendable {
    func makePlan(settings: StrataSettings) throws -> LaunchPlan
}

/// Checks the settings and the installation, writes the run config, and describes the process to spawn.
struct StrataLaunchPlanner: LaunchPlanning {
    let paths: AppPaths

    func makePlan(settings: StrataSettings) throws -> LaunchPlan {
        let errors = settings.validate().filter { $0.severity == .error }.map(\.message)
        guard errors.isEmpty else {
            throw LaunchPlanError.invalidSettings(errors)
        }
        let installation = StrataInstallation(root: settings.strataDirectoryURL)
        let problems = installation.check(model: settings.model)
        guard problems.isEmpty else {
            throw LaunchPlanError.installation(problems)
        }
        let runConfig = paths.runConfig(for: settings.model)
        do {
            try FileManager.default.createDirectory(at: paths.applicationSupport, withIntermediateDirectories: true)
            try LogStore(paths: paths).prepareForLaunch()
            let base = try Data(contentsOf: installation.configURL(for: settings.model))
            let run = try RunConfig.make(base: base, settings: settings, engineLog: paths.engineLog)
            try run.write(to: runConfig, options: .atomic)
        } catch {
            throw LaunchPlanError.configuration(error.localizedDescription)
        }
        return LaunchPlan(
            executable: installation.python,
            arguments: [
                installation.server.path(percentEncoded: false),
                "--engine", "strata",
                "--config", runConfig.path(percentEncoded: false),
                "--host", StrataEndpoint.host,
                "--port", String(settings.port),
            ],
            workingDirectory: installation.root,
            environment: ProcessInfo.processInfo.environment.merging(["PYTHONUNBUFFERED": "1"]) { _, new in new },
            standardOutputLog: paths.serverLog
        )
    }
}
