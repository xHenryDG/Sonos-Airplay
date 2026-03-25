import SwiftUI

struct GroupsView: View {
    @EnvironmentObject var app: AppState
    @State private var showCreateSheet = false
    @State private var editingGroup: SpeakerGroup?

    var body: some View {
        NavigationView {
            List {
                // Active bridge banner
                if app.bridge.isRunning {
                    Section {
                        HStack(spacing: 10) {
                            Image(systemName: "airplayaudio")
                                .foregroundColor(.white)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(app.bridge.statusMessage)
                                    .font(.subheadline).fontWeight(.semibold)
                                    .foregroundColor(.white)
                                Text("Tippe 'Stoppen' um AirPlay zu beenden")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.8))
                            }
                            Spacer()
                            Button("Stoppen") {
                                app.bridge.stop()
                                app.groupStore.groups.indices.forEach {
                                    app.groupStore.groups[$0].isActive = false
                                }
                            }
                            .font(.subheadline).fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Color.white.opacity(0.2))
                            .cornerRadius(8)
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowBackground(Color.accentColor)
                }

                // Groups
                Section {
                    if app.groupStore.groups.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "rectangle.stack.badge.plus")
                                .font(.system(size: 32))
                                .foregroundColor(.secondary)
                            Text("Noch keine Gruppen")
                                .font(.headline)
                            Text("Erstelle eine Gruppe und wähle die Lautsprecher aus, die gemeinsam als AirPlay-Gerät erscheinen sollen.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                            Button("Gruppe erstellen") { showCreateSheet = true }
                                .buttonStyle(.borderedProminent)
                                .padding(.top, 4)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    } else {
                        ForEach(app.groupStore.groups) { group in
                            GroupRow(group: group)
                                .contentShape(Rectangle())
                                .onTapGesture { editingGroup = group }
                        }
                        .onDelete { offsets in app.groupStore.deleteGroup(at: offsets) }
                    }
                } header: {
                    Text("Meine Gruppen")
                } footer: {
                    if !app.groupStore.groups.isEmpty {
                        Text("Tippe auf eine Gruppe um sie zu bearbeiten. Wische zum Löschen.")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Gruppen")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showCreateSheet = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showCreateSheet) {
                GroupEditorView(existingGroup: nil)
            }
            .sheet(item: $editingGroup) { group in
                GroupEditorView(existingGroup: group)
            }
        }
    }
}

// MARK: - Group Row

struct GroupRow: View {
    @EnvironmentObject var app: AppState
    let group: SpeakerGroup

    var speakers: [SonosSpeaker] {
        app.discovery.speakers.filter { group.speakerUUIDs.contains($0.uuid) }
    }

    var isActive: Bool { app.bridge.activeGroupID == group.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        if isActive {
                            Image(systemName: "airplayaudio")
                                .foregroundColor(.accentColor)
                                .font(.subheadline)
                        }
                        Text(group.name)
                            .font(.body).fontWeight(.medium)
                    }
                    Text("\(group.speakerUUIDs.count) Lautsprecher")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Speaker chips
            if !speakers.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(speakers) { s in
                            Text(s.name)
                                .font(.caption2)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Color(.secondarySystemBackground))
                                .cornerRadius(6)
                        }
                    }
                }
            }

            // Action button
            HStack(spacing: 8) {
                Spacer()
                if isActive {
                    Button {
                        app.bridge.stop()
                    } label: {
                        Label("Stoppen", systemImage: "stop.circle")
                    }
                    .font(.subheadline).fontWeight(.medium)
                    .foregroundColor(.red)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(10)
                } else {
                    Button {
                        let spkrs = app.discovery.speakers.filter { group.speakerUUIDs.contains($0.uuid) }
                        app.bridge.start(speakers: spkrs, groupName: group.name, groupID: group.id)
                    } label: {
                        Label("AirPlay starten", systemImage: "airplayaudio")
                    }
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(speakers.isEmpty ? Color.gray : Color.accentColor)
                    .cornerRadius(10)
                    .disabled(speakers.isEmpty)
                }
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Group Editor

struct GroupEditorView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) var dismiss

    let existingGroup: SpeakerGroup?

    @State private var name: String = ""
    @State private var selectedUUIDs: Set<String> = []
    @State private var airPlayMode: AirPlayMode2 = .group

    enum AirPlayMode2: String, CaseIterable {
        case group      = "Als Gruppe"
        case individual = "Einzeln"
    }

    var isEditing: Bool { existingGroup != nil }

    var body: some View {
        NavigationView {
            Form {
                Section("Gruppenname") {
                    TextField("z.B. Erdgeschoss", text: $name)
                }

                Section("AirPlay-Modus") {
                    Picker("Modus", selection: $airPlayMode) {
                        ForEach(AirPlayMode2.allCases, id: \.self) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.vertical, 4)

                    if airPlayMode == .group {
                        Label("Alle ausgewählten Lautsprecher erscheinen als ein AirPlay-Gerät.", systemImage: "info.circle")
                            .font(.caption).foregroundColor(.secondary)
                    } else {
                        Label("Jeder Lautsprecher erscheint einzeln in AirPlay.", systemImage: "info.circle")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }

                Section("Lautsprecher auswählen") {
                    if app.discovery.speakers.isEmpty {
                        HStack {
                            ProgressView().scaleEffect(0.8)
                            Text("Suche läuft…")
                                .foregroundColor(.secondary)
                                .font(.subheadline)
                        }
                    } else {
                        ForEach(app.discovery.speakers) { speaker in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(speaker.name).font(.body)
                                    Text(speaker.ip).font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                Image(systemName: selectedUUIDs.contains(speaker.uuid)
                                      ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(selectedUUIDs.contains(speaker.uuid) ? .accentColor : .secondary)
                                    .font(.title3)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if selectedUUIDs.contains(speaker.uuid) {
                                    selectedUUIDs.remove(speaker.uuid)
                                } else {
                                    selectedUUIDs.insert(speaker.uuid)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "Gruppe bearbeiten" : "Neue Gruppe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(isEditing ? "Speichern" : "Erstellen") {
                        save()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || selectedUUIDs.isEmpty)
                }
            }
            .onAppear {
                if let g = existingGroup {
                    name = g.name
                    selectedUUIDs = Set(g.speakerUUIDs)
                }
            }
        }
    }

    private func save() {
        let uuids = Array(selectedUUIDs)
        if var g = existingGroup {
            g.name = name
            g.speakerUUIDs = uuids
            app.groupStore.updateGroup(g)
        } else {
            app.groupStore.addGroup(name: name, speakerUUIDs: uuids)
        }
    }
}
