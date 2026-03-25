import Foundation
import Combine

class GroupStore: ObservableObject {
    @Published var groups: [SpeakerGroup] = []

    private let key = "sonosairbridge_groups"

    init() { load() }

    func addGroup(name: String, speakerUUIDs: [String]) {
        let g = SpeakerGroup(name: name, speakerUUIDs: speakerUUIDs)
        groups.append(g)
        save()
    }

    func updateGroup(_ group: SpeakerGroup) {
        if let idx = groups.firstIndex(where: { $0.id == group.id }) {
            groups[idx] = group
            save()
        }
    }

    func deleteGroup(at offsets: IndexSet) {
        groups.remove(atOffsets: offsets)
        save()
    }

    func deleteGroup(id: UUID) {
        groups.removeAll { $0.id == id }
        save()
    }

    func setActive(groupID: UUID, active: Bool) {
        for i in groups.indices {
            groups[i].isActive = (groups[i].id == groupID) ? active : false
        }
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(groups) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([SpeakerGroup].self, from: data) {
            groups = decoded
        }
    }
}
