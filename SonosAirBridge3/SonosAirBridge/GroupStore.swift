import Foundation

class GroupStore: ObservableObject {
    @Published var groups: [SpeakerGroup] = []
    private let key = "sab_groups_v3"

    init() { load() }

    func add(name: String, uuids: [String], mode: SpeakerGroup.GroupMode) {
        groups.append(SpeakerGroup(name: name, speakerUUIDs: uuids, mode: mode))
        save()
    }

    func update(_ group: SpeakerGroup) {
        if let i = groups.firstIndex(where: { $0.id == group.id }) {
            groups[i] = group; save()
        }
    }

    func delete(at offsets: IndexSet) { groups.remove(atOffsets: offsets); save() }

    private func save() {
        if let d = try? JSONEncoder().encode(groups) { UserDefaults.standard.set(d, forKey: key) }
    }

    private func load() {
        if let d = UserDefaults.standard.data(forKey: key),
           let g = try? JSONDecoder().decode([SpeakerGroup].self, from: d) { groups = g }
    }
}
