import SwiftUI

@MainActor
class AppState: ObservableObject {
    let permission  = LocalNetworkPermission()
    let discovery   = SonosDiscovery()
    let groupStore  = GroupStore()
    let bridge      = BridgeManager()
    @Published var logs: [LogEntry] = []

    init() {
        discovery.onLog = { [weak self] e in self?.logs.insert(e, at: 0) }
        bridge.onLog    = { [weak self] e in self?.logs.insert(e, at: 0) }
    }

    func boot() {
        Task {
            await permission.request()
            if permission.state == .granted {
                discovery.startContinuousDiscovery()
            }
        }
    }
}

struct MainTabView: View {
    @StateObject private var app = AppState()

    var body: some View {
        Group {
            if app.permission.state == .unknown || app.permission.state == .requesting {
                PermissionView()
            } else if app.permission.state == .denied {
                PermissionDeniedView()
            } else {
                TabView {
                    SpeakerListView()
                        .tabItem { Label("Lautsprecher", systemImage: "hifispeaker.2") }
                    GroupsView()
                        .tabItem { Label("Gruppen", systemImage: "list.bullet.rectangle") }
                    LogView()
                        .tabItem { Label("Log", systemImage: "terminal") }
                }
            }
        }
        .environmentObject(app)
        .onAppear { app.boot() }
    }
}
