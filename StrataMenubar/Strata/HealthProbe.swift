import Foundation

struct StrataHealth: Equatable, Sendable {
    var loaded: Bool
    var model: String?
    var maxContext: Int?
}

enum HealthProbeResult: Equatable, Sendable {
    /// Nothing listens on the port.
    case unreachable
    /// A Strata server answered; `loaded` says whether it can serve requests.
    case strata(StrataHealth)
    /// Something else holds the port, or whatever holds it gave no usable answer.
    case occupied(String)
}

protocol HealthProbing: Sendable {
    func probe(port: Int) async -> HealthProbeResult
}

enum HealthResponse {
    /// An HTTP 200 alone proves nothing: only a body that names the service counts as Strata.
    static func parse(status: Int, body: Data) -> HealthProbeResult {
        guard let object = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] else {
            return .occupied("HTTP \(status) with a body that is not Strata's health JSON")
        }
        guard object["service"] as? String == "strata" else {
            return .occupied("HTTP \(status) from another service (service: \(object["service"].map { "\($0)" } ?? "none"))")
        }
        return .strata(StrataHealth(
            loaded: object["loaded"] as? Bool ?? false,
            model: object["model"] as? String,
            maxContext: object["max_context"] as? Int
        ))
    }
}

struct URLSessionHealthProbe: HealthProbing {
    private let session: URLSession
    private let timeout: TimeInterval

    init(timeout: TimeInterval = 2) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration)
        self.timeout = timeout
    }

    func probe(port: Int) async -> HealthProbeResult {
        var request = URLRequest(url: StrataEndpoint.health(port: port))
        request.timeoutInterval = timeout
        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            return HealthResponse.parse(status: status, body: data)
        } catch let error as URLError where error.code == .cannotConnectToHost {
            return .unreachable
        } catch {
            return .occupied("no usable answer from port \(port): \(error.localizedDescription)")
        }
    }
}
