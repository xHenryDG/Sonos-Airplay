import SwiftUI

struct GroupsView: View {
    @EnvironmentObject var app: AppState
    @State private var showCreate = false
    @State private var editGroup: SpeakerGroup?

    var body: some View {
        NavigationView {
            List {
                // Aktives Bridge-Banner
                if app.bridge.isRunning {
                    Section {
                        HStack(spacing: 10) {
                            Image(systemName: "airplayaudio").foregroundColor(.white)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(app.bridge.statusMessage)
                                    .font(.subheadline).fontWeight(.semibold).foregroundColor(.white)
                                Text("App kann jetzt minimiert werden")
                                    .font(.caption).foregroundColor(.white.opacity(0.8))
                            }
                            Spacer()
                            Button("Stoppen") { app.bridge.stop() }
                                .font(.subheadline).fontWeight(.semibold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(.white.opacity(0.2))
                                .cornerRadius(8)
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowBackground(Color.accentColor)
                }

                // Gruppen-Liste
                Section {
                    if app.groups.groups.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "rectangle.stack.badge.plus")
                                .font(.system(size: 36)).foregroundColor(.secondary)
                            Text("Noch keine Gruppen")
                                .font(.headline)
                            Text("Erstelle eine Gruppe und wähle Lautsprecher aus. Die Gruppe wird dann als ein AirPlay-Gerät in iOS angezeigt.")
                                .font(.caption).foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                            Button("Erste Gruppe erstellen") { showCreate = true }
                                .buttonStyle(.borderedProminent).padding(.top, 4)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 24)
                    } else {
                        ForEach(app.groups.groups) { g in
                            GroupRowView(group: g)
                                .contentShape(Rectangle())
                                .onTapGesture { editGroup = g }
                        }
                        .onDelete { app.groups.delete(at: $0) }
                    }
                } header: { Text("Meine Gruppen") }
                  footer: {
                      if !app.groups.groups.isEmpty {
                          Text("Tippe zum Bearbeiten · Wischen zum Löschen")
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
            .sheet(item: $editGroup)         { GroupEditorView(existing: $0) }
        }
    }
}

// MARK: - Group Row

struct GroupRowView: View {
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
                                .foregroundColor(.accentColor).font(.subheadline)
                        }
                        Text(group.name).font(.body).fontWeight(.medium)
                        if group.isIndividual {
                            Text("einzeln")
                                .font(.caption2).padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color(.secondarySystemBackground)).cornerRadius(4)
                        }
                    }
                    Text("\(group.speakerUUIDs.count) Lautsprecher")
                        .font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption).foregroundColor(.secondary)
            }

            // Speaker-Chips (nur die die gerade online sind)
            if !speakers.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(speakers) { s in
                            Text(s.name).font(.caption2)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Color(.secondarySystemBackground)).cornerRadius(6)
                        }
                    }
                }
            }

            // Aktion
            HStack {
                Spacer()
                if isActive {
                    Button { app.bridge.stop() } label: {
                        Label("Stoppen", systemImage: "stop.circle")
                    }
                    .font(.subheadline).fontWeight(.medium).foregroundColor(.red)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Color(.secondarySystemBackground)).cornerRadius(10)
                } else {
                    Button {
                        let spkrs = app.discovery.speakers.filter {
                            group.speakerUUIDs.contains($0.uuid)
                        }
                        app.bridge.start(
                            speakers: spkrs,
                            groupName: group.isIndividual ? nil : group.name,
                            individual: group.isIndividual,
                            groupID: group.id
                        )
                    } label: {
                        Label("AirPlay starten", systemImage: "airplayaudio")
                    }
                    .font(.subheadline).fontWeight(.semibold).foregroundColor(.white)
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

    let existing: SpeakerGroup?

    @State private var name       = ""
    @State private var selected   = Set<String>()
    @State private var individual = false

    var body: some View {
        NavigationView {
            Form {
                Section("Name") {
                    TextField("z.B. Erdgeschoss", text: $name)
                }

                Section("Modus") {
                    Toggle("Einzeln in AirPlay", isOn: $individual)
                    Text(individual
                         ? "Jeder Lautsprecher erscheint als eigenes AirPlay-Gerät."
                         : "Alle ausgewählten Lautsprecher als ein AirPlay-Gerät.")
                        .font(.caption).foregroundColor(.secondary)
                }

                Section("Lautsprecher") {
                    if app.discovery.speakers.isEmpty {
                        Label("Suche läuft…", systemImage: "arrow.clockwise")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(app.discovery.speakers) { s in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(s.name)
                                    Text(s.ip).font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                Image(systemName: selected.contains(s.uuid) ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(selected.contains(s.uuid) ? .accentColor : .secondary)
                                    .font(.title3)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if selected.contains(s.uuid) { selected.remove(s.uuid) }
                                else { selected.insert(s.uuid) }
                            }
                        }
                    }
                }
            }
            .navigationTitle(existing == nil ? "Neue Gruppe" : "Bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(existing == nil ? "Erstellen" : "Speichern") {
                        save(); dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || selected.isEmpty)
                }
            }
            .onAppear {
                if let g = existing {
                    name       = g.name
                    selected   = Set(g.speakerUUIDs)
                    individual = g.isIndividual
                }
            }
        }
    }

    private func save() {
        let uuids = Array(selected)
        if var g = existing {
            g.name         = name
            g.speakerUUIDs = uuids
            g.isIndividual = individual
            app.groups.update(g)
        } else {
            app.groups.add(name: name, uuids: uuids, individual: individual)
        }
    }
}
