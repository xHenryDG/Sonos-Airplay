import SwiftUI

@MainActor
class AppState: ObservableObject {
    let permission = NetworkPermissionManager()
    let discovery  = SonosDiscovery()
    let groups     = GroupStore()
    let bridge     = BridgeManager()

    @Published var logs: [LogEntry] = []

    init() {
        discovery.onLog = { [weak self] e in self?.logs.insert(e, at: 0) }
        bridge.onLog    = { [weak self] e in self?.logs.insert(e, at: 0) }
    }

    func log(_ level: LogEntry.Level, _ msg: String) {
        logs.insert(LogEntry(level: level, message: msg), at: 0)
    }
}
