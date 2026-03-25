import SwiftUI

class AppState: ObservableObject {
    let discovery = SonosDiscovery()
    let groupStore = GroupStore()
    let bridge = BridgeManager()
    @Published var logs: [LogEntry] = []

    init() {
        discovery.onLog = { [weak self] entry in self?.logs.insert(entry, at: 0) }
        bridge.onLog    = { [weak self] entry in self?.logs.insert(entry, at: 0) }
    }
}

struct MainTabView: View {
    @StateObject private var app = AppState()

    var body: some View {
        TabView {
            SpeakerListView()
                .tabItem { Label("Lautsprecher", systemImage: "hifispeaker.2") }

            GroupsView()
                .tabItem { Label("Gruppen", systemImage: "list.bullet.rectangle") }

            LogView()
                .tabItem { Label("Log", systemImage: "terminal") }
        }
        .environmentObject(app)
        .onAppear {
            app.discovery.startContinuousDiscovery()
        }
    }
}
