import Foundation

/// The server is reached on the loopback interface only; nothing here takes a host.
enum StrataEndpoint {
    static let host = "127.0.0.1"

    static func health(port: Int) -> URL {
        URL(string: "http://\(host):\(port)/health")!
    }

    static func chat(port: Int) -> URL {
        URL(string: "http://\(host):\(port)/")!
    }
}
