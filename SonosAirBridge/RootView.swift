import SwiftUI

struct RootView: View {
    @StateObject private var app = AppState()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch app.permission.state {
            case .unknown, .requesting:
                PermissionView()
            case .denied:
                PermissionDeniedView()
            case .granted:
                MainTabView()
            }
        }
        .environmentObject(app)
        .task {
            await app.permission.request()
            if app.permission.state == .granted {
                app.discovery.startContinuous()
            }
        }
        // Neu prüfen wenn User aus Einstellungen zurückkommt
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task {
                    if app.permission.state == .denied || app.permission.state == .unknown {
                        app.permission.reset()
                        await app.permission.request()
                        if app.permission.state == .granted {
                            app.discovery.startContinuous()
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Permission Screen

struct PermissionView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "wifi.router")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)

            VStack(spacing: 12) {
                Text("Netzwerkzugriff")
                    .font(.title).fontWeight(.bold)
                Text("Sonos AirBridge benötigt Zugriff auf dein lokales Netzwerk, um Sonos-Lautsprecher zu finden und als AirPlay-Geräte bereitzustellen.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            if app.permission.state == .requesting {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Warte auf Erlaubnis…")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            } else {
                Button("Erlaubnis erteilen") {
                    Task { await app.permission.request() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            Spacer()

            Text("iOS zeigt einen Dialog an – tippe \u{201E}Erlauben\u{201C}.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
                .padding(.bottom, 32)
        }
        .padding()
    }
}

// MARK: - Permission Denied Screen

struct PermissionDeniedView: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "wifi.slash")
                .font(.system(size: 64))
                .foregroundColor(.red)

            Text("Netzwerkzugriff verweigert")
                .font(.title2).fontWeight(.bold)

            Text("Bitte erlaube den Netzwerkzugriff in:\nEinstellungen → Datenschutz & Sicherheit → Lokales Netzwerk → Sonos AirBridge")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Einstellungen öffnen") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)

            Spacer()
        }
        .padding()
    }
}
