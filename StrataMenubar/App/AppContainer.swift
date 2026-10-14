import Foundation

/// Wires the app's long-lived objects together once; views and the app delegate share them through here.
@MainActor
final class AppContainer {
    static let shared = AppContainer()

    let serverManager: ServerManager

    private init() {
        serverManager = ServerManager()
    }
}
