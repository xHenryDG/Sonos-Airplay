import SwiftUI

struct SpeakerListView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        NavigationView {
            List {
                Section {
                    HStack(spacing: 10) {
                        if app.discovery.isScanning {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Image(systemName: app.discovery.speakers.isEmpty ? "wifi.exclamationmark" : "checkmark.circle.fill")
                                .foregroundColor(app.discovery.speakers.isEmpty ? .orange : .green)
                        }
                        Text(app.discovery.scanStatus)
                            .font(.subheadline).foregroundColor(.secondary)
                    }
                    .padding(.vertical, 2)
                }

                Section {
                    if app.discovery.speakers.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "hifispeaker.slash")
                                .font(.system(size: 40)).foregroundColor(.secondary)
                            Text("Keine Lautsprecher gefunden")
                                .font(.headline)
                            Text("Die App sucht automatisch alle 10 Sekunden.\nStelle sicher, dass iPhone und Sonos-Boxen im selben WLAN sind.")
                                .font(.caption).foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 24)
                    } else {
                        ForEach(app.discovery.speakers) { s in
                            HStack(spacing: 14) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color(.secondarySystemBackground))
                                        .frame(width: 42, height: 42)
                                    Image(systemName: "hifispeaker.fill")
                                        .font(.system(size: 18)).foregroundColor(.accentColor)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(s.name).font(.body).fontWeight(.medium)
                                    Text("\(s.model) · \(s.ip)")
                                        .font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                Circle().fill(Color.green).frame(width: 8, height: 8)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                } header: {
                    Text("Im Netzwerk (\(app.discovery.speakers.count))")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Sonos AirBridge")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        app.discovery.performScan()
                    } label: {
                        if app.discovery.isScanning {
                            ProgressView().scaleEffect(0.75)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(app.discovery.isScanning)
                }
            }
        }
    }
}
