import Foundation

struct SonosSpeaker: Identifiable, Hashable, Codable {
    var id       = UUID()
    var name:    String
    var ip:      String
    var uuid:    String
    var model:   String = "Sonos"

    func hash(into hasher: inout Hasher) { hasher.combine(uuid) }
    static func == (l: SonosSpeaker, r: SonosSpeaker) -> Bool { l.uuid == r.uuid }
}

struct SpeakerGroup: Identifiable, Codable {
    var id           = UUID()
    var name:        String
    var speakerUUIDs: [String]
    var isIndividual: Bool = false   // false = Gruppe, true = einzeln
}

struct LogEntry: Identifiable {
    let id      = UUID()
    let date    = Date()
    let level:   Level
    let message: String

    enum Level { case info, success, warning, error }

    var symbol: String {
        switch level {
        case .info:    return "ℹ"
        case .success: return "✓"
        case .warning: return "⚠"
        case .error:   return "✗"
        }
    }
}
