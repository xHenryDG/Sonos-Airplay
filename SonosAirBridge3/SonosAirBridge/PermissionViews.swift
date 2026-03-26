import SwiftUI

struct PermissionView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "wifi.circle")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)

            VStack(spacing: 8) {
                Text("Netzwerk-Zugriff")
                    .font(.title2).fontWeight(.bold)
                Text("SonosAirBridge benötigt Zugriff auf dein lokales Netzwerk um Sonos-Lautsprecher zu finden.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            if app.permission.state == .requesting {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Warte auf Erlaubnis…")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
            Text("Tippe auf 'Erlauben' wenn iOS fragt.")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.bottom, 32)
        }
    }
}

struct PermissionDeniedView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 64))
                .foregroundColor(.orange)

            VStack(spacing: 8) {
                Text("Zugriff verweigert")
                    .font(.title2).fontWeight(.bold)
                Text("Ohne Netzwerkzugriff kann die App keine Sonos-Lautsprecher finden.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Label("Einstellungen öffnen", systemImage: "gear")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 32)

            Button("Erneut versuchen") {
                Task { await app.permission.request() }
            }
            .foregroundColor(.accentColor)

            Spacer()
        }
    }
}
