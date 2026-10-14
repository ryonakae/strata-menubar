import Foundation
import Testing
@testable import StrataMenubar

struct HealthResponseTests {
    @Test func onlyTalksToTheLoopbackInterface() {
        #expect(StrataEndpoint.health(port: 8080).absoluteString == "http://127.0.0.1:8080/health")
        #expect(StrataEndpoint.chat(port: 8090).absoluteString == "http://127.0.0.1:8090/")
    }

    @Test func recognisesAStrataServer() {
        let body = Data("""
        {"status": "ok", "max_context": 8192, "model": "qwen3.8-flash-next-q2_0", "images": false, "api_key": false,
         "image_generation": false, "loaded": true, "service": "strata"}
        """.utf8)
        #expect(HealthResponse.parse(status: 200, body: body) == .strata(StrataHealth(loaded: true, model: "qwen3.8-flash-next-q2_0", maxContext: 8192)))
    }

    @Test func aServerThatIsStillLoadingIsNotRunning() {
        let body = Data(#"{"status": "ok", "max_context": 0, "model": "qwen3.8-flash-next-q2_0", "loaded": false, "service": "strata"}"#.utf8)
        #expect(HealthResponse.parse(status: 200, body: body) == .strata(StrataHealth(loaded: false, model: "qwen3.8-flash-next-q2_0", maxContext: 0)))
    }

    @Test func anotherServiceOnThePortIsAConflictEvenWith200() {
        #expect(HealthResponse.parse(status: 200, body: Data(#"{"status": "ok"}"#.utf8)).isOccupied)
        #expect(HealthResponse.parse(status: 200, body: Data("<html>ok</html>".utf8)).isOccupied)
        #expect(HealthResponse.parse(status: 404, body: Data().self).isOccupied)
    }
}

private extension HealthProbeResult {
    var isOccupied: Bool {
        if case .occupied = self { return true }
        return false
    }
}
