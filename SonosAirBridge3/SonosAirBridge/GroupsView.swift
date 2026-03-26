import SwiftUI

struct GroupsView: View {
    @EnvironmentObject var app: AppState
    @State private var showCreate = false
    @State private var editing: SpeakerGroup?

    var body: some View {
        NavigationView {
            List {
                // Active bridge banner
                if app.bridge.isRunning {
                    Section {
                        HStack(spacing: 12) {
                            Image(systemName: "airplayaudio").foregroundColor(.white)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(app.bridge.statusMessage)
                                    .font(.subheadline).fontWeight(.semibold).foregroundColor(.white)
                                Text("App kann jetzt im Hintergrund laufen")
                                    .font(.caption).foregroundColor(.white.opacity(0.8))
                            }
                            Spacer()
                            Button("Stopp") { app.bridge.stop() }
                                .font(.subheadline).fontWeight(.semibold).foregroundColor(.white)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(Color.white.opacity(0.2)).cornerRadius(8)
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowBackground(Color.accentColor)
                }

                // Groups list
                Section {
                    if app.groupStore.groups.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "rectangle.stack.badge.plus")
                                .font(.system(size: 36)).foregroundColor(.secondary)
                            Text("Noch keine Gruppen")
                                .font(.headline)
                            Text("Erstelle eine Gruppe und wähle Sonos-Lautsprecher aus. Die Gruppe erscheint dann in AirPlay.")
                                .font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
                            Button("Gruppe erstellen") { showCreate = true }
                                .buttonStyle(.borderedProminent).padding(.top, 4)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 20)
                    } else {
                        ForEach(app.groupStore.groups) { group in
                            GroupRow(group: group) { editing = group }
                        }
                        .onDelete { app.groupStore.delete(at: $0) }
                    }
                } header: { Text("Meine Gruppen") }
                  footer: {
                    if !app.groupStore.groups.isEmpty {
                        Text("Wische zum Löschen · Tippe zum Bearbeiten")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Gruppen")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showCreate = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showCreate) { GroupEditorView(existing: nil) }
            .sheet(item: $editing) { GroupEditorView(existing: $0) }
        }
    }
}

// MARK: - Group Row

struct GroupRow: View {
    @EnvironmentObject var app: AppState
    let group: SpeakerGroup
    let onEdit: () -> Void

    var onlineSpeakers: [SonosSpeaker] {
        app.discovery.speakers.filter { group.speakerUUIDs.contains($0.uuid) }
    }
    var isActive: Bool { app.bridge.activeGroupID == group.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header row
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        if isActive {
                            Image(systemName: "airplayaudio")
                                .foregroundColor(.accentColor).font(.subheadline)
                        }
                        Text(group.name).font(.body).fontWeight(.medium)
                    }
                    HStack(spacing: 8) {
                        Text(group.mode.rawValue)
                            .font(.caption2)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color(.tertiarySystemBackground))
                            .cornerRadius(4)
                        Text("\(group.speakerUUIDs.count) Lautsprecher · \(onlineSpeakers.count) online")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
                Spacer()
                Button(action: onEdit) {
                    Image(systemName: "pencil.circle")
                        .foregroundColor(.secondary).font(.title3)
                }
                .buttonStyle(.plain)
            }

            // Speaker chips
            if !onlineSpeakers.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(onlineSpeakers) { s in
                            Label(s.name, systemImage: "hifispeaker.fill")
                                .font(.caption2)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Color(.secondarySystemBackground))
                                .cornerRadius(6)
                        }
                    }
                }
            }

            // Action button
            HStack {
                Spacer()
                if isActive {
                    Button {
                        app.bridge.stop()
                    } label: {
                        Label("AirPlay stoppen", systemImage: "stop.circle.fill")
                            .font(.subheadline).fontWeight(.medium)
                    }
                    .foregroundColor(.red)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Color(.secondarySystemBackground)).cornerRadius(10)
                } else {
                    Button {
                        app.bridge.start(group: group, speakers: onlineSpeakers)
                    } label: {
                        Label("AirPlay starten", systemImage: "airplayaudio")
                            .font(.subheadline).fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(onlineSpeakers.isEmpty ? Color.gray : Color.accentColor)
                    .cornerRadius(10)
                    .disabled(onlineSpeakers.isEmpty)
                }
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Group Editor

struct GroupEditorView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) var dismiss

    let existing: SpeakerGroup?

    @State private var name = ""
    @State private var selectedUUIDs: Set<String> = []
    @State private var mode: SpeakerGroup.GroupMode = .group

    var isNew: Bool { existing == nil }

    var body: some View {
        NavigationView {
            Form {
                Section("Gruppenname") {
                    TextField("z.B. Wohnzimmer + Küche", text: $name)
                }

                Section {
                    Picker("Modus", selection: $mode) {
                        ForEach(SpeakerGroup.GroupMode.allCases, id: \.self) {
                            Text($0.rawValue).tag($0)
                        }
                    }
                    .pickerStyle(.segmented).padding(.vertical, 4)

                    Text(mode == .group
                         ? "Alle ausgewählten Lautsprecher erscheinen als ein AirPlay-Gerät."
                         : "Jeder Lautsprecher erscheint einzeln in AirPlay.")
                        .font(.caption).foregroundColor(.secondary)
                } header: { Text("AirPlay-Modus") }

                Section {
                    if app.discovery.speakers.isEmpty {
                        HStack {
                            ProgressView().scaleEffect(0.8)
                            Text("Suche läuft…").font(.subheadline).foregroundColor(.secondary)
                        }
                    } else {
                        ForEach(app.discovery.speakers) { s in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(s.name)
                                    Text(s.ip).font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                Image(systemName: selectedUUIDs.contains(s.uuid)
                                      ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(selectedUUIDs.contains(s.uuid) ? .accentColor : .secondary)
                                    .font(.title3)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedUUIDs.contains(s.uuid)
                                    ? selectedUUIDs.remove(s.uuid)
                                    : selectedUUIDs.insert(s.uuid)
                            }
                        }
                    }
                } header: { Text("Lautsprecher") }
            }
            .navigationTitle(isNew ? "Neue Gruppe" : "Bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(isNew ? "Erstellen" : "Speichern") { save(); dismiss() }
                        .fontWeight(.semibold)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || selectedUUIDs.isEmpty)
                }
            }
            .onAppear {
                if let g = existing {
                    name = g.name
                    selectedUUIDs = Set(g.speakerUUIDs)
                    mode = g.mode
                }
            }
        }
    }

    private func save() {
        let uuids = Array(selectedUUIDs)
        if var g = existing {
            g.name = name; g.speakerUUIDs = uuids; g.mode = mode
            app.groupStore.update(g)
        } else {
            app.groupStore.add(name: name, uuids: uuids, mode: mode)
        }
    }
}
