import Foundation
import AVFoundation

@MainActor
class BridgeManager: ObservableObject {
    @Published var isRunning      = false
    @Published var activeGroupID: UUID?
    @Published var statusMessage  = "Nicht aktiv"

    var onLog: ((LogEntry) -> Void)?

    private var bonjourServices: [NetService] = []

    // MARK: - Start / Stop

    func start(speakers: [SonosSpeaker], groupName: String?, individual: Bool, groupID: UUID) {
        stop()
        guard !speakers.isEmpty else { return }

        if individual {
            // Jeden Lautsprecher einzeln als AirPlay-Gerät registrieren
            for s in speakers {
                registerRAOP(name: s.name)
                log(.success, "'\(s.name)' in AirPlay registriert")
            }
            statusMessage = "\(speakers.count) Lautsprecher einzeln in AirPlay"
        } else {
            let name = groupName ?? "Sonos-Gruppe"
            // Sonos-Gruppe über UPnP bilden
            if speakers.count > 1 {
                formSonosGroup(coordinator: speakers[0], followers: Array(speakers.dropFirst()))
            }
            registerRAOP(name: name)
            statusMessage = "'\(name)' in AirPlay aktiv"
            log(.success, "Gruppe '\(name)' in AirPlay registriert")
        }

        isRunning     = true
        activeGroupID = groupID
        keepAlive()
    }

    func stop() {
        bonjourServices.forEach { $0.stop() }
        bonjourServices.removeAll()
        isRunning     = false
        activeGroupID = nil
        statusMessage = "Nicht aktiv"
        log(.info, "Bridge gestoppt")
    }

    // MARK: - Bonjour RAOP (_raop._tcp)

    private func registerRAOP(name: String) {
        let mac  = (0..<6).map { _ in String(format: "%02X", Int.random(in: 0...255)) }.joined(separator: "")
        let port = Int32.random(in: 49152...65535)

        // RAOP TXT-Record (Apple Remote Audio Protocol / AirPlay v1)
        let txt: [String: String] = [
            "txtvers": "1",
            "ch":      "2",          // 2-Kanal
            "cn":      "0,1",        // PCM + ALAC
            "et":      "0,3",        // Verschlüsselung: keine + RSA
            "md":      "0,1,2",
            "pw":      "false",
            "sr":      "44100",
            "ss":      "16",
            "tp":      "UDP",
            "vs":      "130.14",
            "am":      "SonosAirBridge,1",
            "sf":      "0x4"
        ]

        var data = [String: Data]()
        for (k, v) in txt { data[k] = v.data(using: .utf8)! }

        // Format: "AABBCCDDEEFF@Name" — wie echter RAOP-Eintrag
        let service = NetService(domain: "local.", type: "_raop._tcp.", name: "\(mac)@\(name)", port: port)
        service.setTXTRecord(NetService.data(fromTXTRecord: data))
        service.publish()
        bonjourServices.append(service)
    }

    // MARK: - Sonos UPnP Grouping

    private func formSonosGroup(coordinator: SonosSpeaker, followers: [SonosSpeaker]) {
        for follower in followers {
            let body = """
            <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"
              s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
              <s:Body>
                <u:SetAVTransportURI xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
                  <InstanceID>0</InstanceID>
                  <CurrentURI>x-rincon:\(coordinator.uuid)</CurrentURI>
                  <CurrentURIMetaData></CurrentURIMetaData>
                </u:SetAVTransportURI>
              </s:Body>
            </s:Envelope>
            """
            soapSend(ip: follower.ip,
                     path: "/MediaRenderer/AVTransport/Control",
                     action: "urn:schemas-upnp-org:service:AVTransport:1#SetAVTransportURI",
                     body: body)
            log(.info, "Gruppiere \(follower.name) unter \(coordinator.name)")
        }
    }

    private func soapSend(ip: String, path: String, action: String, body: String) {
        guard let url = URL(string: "http://\(ip):1400\(path)") else { return }
        var req = URLRequest(url: url)
        req.httpMethod  = "POST"
        req.setValue("text/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.setValue("\"\(action)\"",            forHTTPHeaderField: "SOAPACTION")
        req.httpBody    = body.data(using: .utf8)
        req.timeoutInterval = 5
        URLSession.shared.dataTask(with: req) { [weak self] _, _, err in
            if let err { Task { @MainActor in self?.log(.error, "SOAP: \(err.localizedDescription)") } }
        }.resume()
    }

    // MARK: - Background keep-alive
    // Spielt eine stille 1-Sekunde-Audiodatei in einer Endlosschleife
    // damit iOS die App mit UIBackgroundModes:audio am Leben lässt.

    private var silentPlayer: AVAudioPlayer?

    private func keepAlive() {
        // 44 bytes: minimaler gültiger WAV-Header mit 0 PCM-Samples
        let wav = Data([
            0x52,0x49,0x46,0x46, 0x24,0x00,0x00,0x00,  // RIFF....
            0x57,0x41,0x56,0x45,                         // WAVE
            0x66,0x6D,0x74,0x20, 0x10,0x00,0x00,0x00,   // fmt ....
            0x01,0x00,                                    // PCM
            0x01,0x00,                                    // 1 Kanal
            0x44,0xAC,0x00,0x00,                          // 44100 Hz
            0x88,0x58,0x01,0x00,                          // ByteRate
            0x02,0x00,                                    // BlockAlign
            0x10,0x00,                                    // 16 bit
            0x64,0x61,0x74,0x61, 0x00,0x00,0x00,0x00    // data chunk, 0 bytes
        ])
        do {
            silentPlayer = try AVAudioPlayer(data: wav)
            silentPlayer?.numberOfLoops = -1   // Endlos
            silentPlayer?.volume        = 0    // Lautlos
            silentPlayer?.play()
        } catch {
            log(.warning, "Keep-alive Player konnte nicht gestartet werden: \(error)")
        }
    }

    private func log(_ level: LogEntry.Level, _ msg: String) {
        onLog?(LogEntry(level: level, message: msg))
    }
}
