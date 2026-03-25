import SwiftUI

enum AirPlayMode: String, CaseIterable {
    case group = "Als Gruppe"
    case individual = "Einzeln"
}

struct ContentView: View {
    @StateObject private var discovery = SonosDiscovery()
    @StateObject private var bridge = AirPlayBridgeManager()

    @State private var groupName = "Meine Sonos-Gruppe"
    @State private var airPlayMode: AirPlayMode = .group

    var selectedSpeakers: [SonosSpeaker] { discovery.speakers.filter { $0.isSelected } }

    var body: some View {
        NavigationView {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()
                VStack(spacing: 0) {
                    if bridge.isRunning {
                        AirPlayStatusBanner(bridge: bridge)
                    }
                    List {
                        Section {
                            Picker("AirPlay-Modus", selection: $airPlayMode) {
                                ForEach(AirPlayMode.allCases, id: \.self) { mode in
                                    Text(mode.rawValue).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)
                            .padding(.vertical, 4)

                            if airPlayMode == .group {
                                HStack {
                                    Image(systemName: "speaker.wave.3")
                                        .foregroundColor(.secondary)
                                        .font(.subheadline)
                                    TextField("Gruppenname", text: $groupName)
                                        .font(.subheadline)
                                }
                            } else {
                                Label {
                                    Text("Jeder Lautsprecher erscheint einzeln in AirPlay")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                } icon: {
                                    Image(systemName: "info.circle")
                                        .foregroundColor(.accentColor)
                                        .font(.subheadline)
                                }
                            }
                        } header: { Text("AirPlay-Modus") }

                        Section {
                            if discovery.speakers.isEmpty {
                                if discovery.isScanning {
                                    HStack {
                                        ProgressView().scaleEffect(0.8)
                                        Text("Suche nach Sonos-Lautsprechern…")
                                            .foregroundColor(.secondary)
                                            .font(.subheadline)
                                    }
                                    .padding(.vertical, 8)
                                } else {
                                    VStack(spacing: 8) {
                                        Image(systemName: "wifi.slash").font(.title2).foregroundColor(.secondary)
                                        Text("Keine Lautsprecher gefunden").font(.subheadline).foregroundColor(.secondary)
                                        Text("Stelle sicher, dass du im selben WLAN bist wie deine Sonos-Boxen.")
                                            .font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
                                    }
                                    .frame(maxWidth: .infinity).padding(.vertical, 16)
                                }
                            } else {
                                ForEach($discovery.speakers) { $speaker in
                                    SpeakerRow(speaker: $speaker, isDisabled: bridge.isRunning)
                                }
                            }
                        } header: {
                            HStack {
                                Text("Lautsprecher im Netzwerk")
                                Spacer()
                                if selectedSpeakers.count > 0 {
                                    Text("\(selectedSpeakers.count) ausgewählt").font(.caption).foregroundColor(.accentColor)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)

                    VStack(spacing: 0) {
                        Divider()
                        Button(action: handleBridgeAction) {
                            HStack {
                                Image(systemName: bridge.isRunning ? "stop.circle.fill" : "airplayaudio")
                                Text(buttonLabel).fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(buttonColor)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        .disabled(selectedSpeakers.isEmpty && !bridge.isRunning)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color(.systemBackground))
                    }
                }
            }
            .navigationTitle("Sonos AirBridge")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        if !discovery.isScanning { discovery.startDiscovery() }
                    } label: {
                        if discovery.isScanning { ProgressView().scaleEffect(0.7) }
                        else { Image(systemName: "arrow.clockwise") }
                    }
                }
            }
            .onAppear { discovery.startDiscovery() }
        }
    }

    var buttonLabel: String {
        if bridge.isRunning { return "AirPlay stoppen" }
        return airPlayMode == .group ? "Als Gruppe in AirPlay anmelden" : "Einzeln in AirPlay anmelden"
    }

    var buttonColor: Color {
        if bridge.isRunning { return .red }
        return selectedSpeakers.isEmpty ? .gray : .accentColor
    }

    private func handleBridgeAction() {
        if bridge.isRunning {
            bridge.stopBridge()
        } else {
            let name = airPlayMode == .group ? groupName : nil
            bridge.startBridge(speakers: selectedSpeakers, groupName: name)
        }
    }
}

struct SpeakerRow: View {
    @Binding var speaker: SonosSpeaker
    var isDisabled: Bool

    var body: some View {
        Button {
            if !isDisabled { speaker.isSelected.toggle() }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(speaker.isSelected ? Color.accentColor : Color(.secondarySystemBackground))
                        .frame(width: 36, height: 36)
                    Image(systemName: "hifispeaker.fill")
                        .font(.system(size: 14))
                        .foregroundColor(speaker.isSelected ? .white : .secondary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(speaker.name).font(.body).foregroundColor(.primary)
                    Text(speaker.ip).font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: speaker.isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(speaker.isSelected ? .accentColor : .secondary)
                    .font(.title3)
            }
            .padding(.vertical, 4)
            .opacity(isDisabled && !speaker.isSelected ? 0.4 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct AirPlayStatusBanner: View {
    @ObservedObject var bridge: AirPlayBridgeManager

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "airplayaudio").foregroundColor(.white)
            VStack(alignment: .leading, spacing: 1) {
                Text(bridge.bridgeName).font(.subheadline).fontWeight(.semibold).foregroundColor(.white)
                Text("In AirPlay verfügbar").font(.caption).foregroundColor(.white.opacity(0.8))
            }
            Spacer()
            Circle().fill(Color.green).frame(width: 8, height: 8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.accentColor)
    }
}

#Preview { ContentView() }
