import SwiftUI

struct MainTabView: View {
    var body: some View {
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
