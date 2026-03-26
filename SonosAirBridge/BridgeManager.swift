import Foundation
import AVFoundation

@MainActor
class BridgeManager: ObservableObject {
    @Published var isRunning      = false
    @Published var activeGroupID: UUID?
    @Published var statusMessage  = "Nicht aktiv"

    var onLog: ((LogEntry) -> Void)?

    // Ein RAOP-Server pro registriertem Lautsprecher
    private var raopServers: [RAOPServer] = []
    private var bonjourServices: [NetService] = []
    private var silentPlayer: AVAudioPlayer?
    private var basePort: UInt16 = 5100

    // MARK: - Start / Stop

    func start(speakers: [SonosSpeaker], groupName: String?, individual: Bool, groupID: UUID) {
        stop()
        guard !speakers.isEmpty else { return }

        if individual {
            // Jeden Lautsprecher einzeln: eigener RAOP-Server + eigener Bonjour-Eintrag
            var port = basePort
            for s in speakers {
                let server = RAOPServer(port: port)
                server.onLog = { [weak self] e in self?.onLog?(e) }
                server.start(targetSpeaker: s)
                raopServers.append(server)

                registerRAOP(name: s.name, port: port)
                log(.success, "'\(s.name)' als AirPlay registriert (Port \(port))")
                port += 10
            }
            statusMessage = "\(speakers.count) Lautsprecher einzeln in AirPlay"
        } else {
            // Gruppe: ein RAOP-Server, der an alle Lautsprecher weiterleitet
            // Coordinator = erster Lautsprecher, Rest per UPnP gruppieren
            if speakers.count > 1 {
                formSonosGroup(coordinator: speakers[0], followers: Array(speakers.dropFirst()))
            }
            let server = RAOPServer(port: basePort)
            server.onLog = { [weak self] e in self?.onLog?(e) }
            server.start(targetSpeaker: speakers[0], allSpeakers: speakers)
            raopServers.append(server)

            let name = groupName ?? "Sonos-Gruppe"
            registerRAOP(name: name, port: basePort)
            statusMessage = "'\(name)' in AirPlay aktiv"
            log(.success, "Gruppe '\(name)' als AirPlay registriert")
        }

        isRunning     = true
        activeGroupID = groupID
        keepAlive()
    }

    func stop() {
        raopServers.forEach { $0.stop() }
        raopServers.removeAll()
        bonjourServices.forEach { $0.stop() }
        bonjourServices.removeAll()
        silentPlayer?.stop()
        silentPlayer = nil
        isRunning     = false
        activeGroupID = nil
        statusMessage = "Nicht aktiv"
        log(.info, "Bridge gestoppt")
    }

    // MARK: - Bonjour RAOP (_raop._tcp)

    private func registerRAOP(name: String, port: UInt16) {
        let mac = (0..<6).map { _ in String(format: "%02X", Int.random(in: 0...255)) }.joined()

        let txt: [String: String] = [
            "txtvers": "1",
            "ch":      "2",
            "cn":      "0,1",
            "et":      "0,3",
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

        let service = NetService(domain: "local.", type: "_raop._tcp.",
                                 name: "\(mac)@\(name)", port: Int32(port))
        service.setTXTRecord(NetService.data(fromTXTRecord: data))
        service.publish()
        bonjourServices.append(service)
    }

    // MARK: - Sonos UPnP Grouping

    private func formSonosGroup(coordinator: SonosSpeaker, followers: [SonosSpeaker]) {
        for follower in followers {
            let body = """
            <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
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
        req.httpMethod = "POST"
        req.setValue("text/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.setValue("\"\(action)\"", forHTTPHeaderField: "SOAPACTION")
        req.httpBody = body.data(using: .utf8)
        req.timeoutInterval = 5
        URLSession.shared.dataTask(with: req) { [weak self] _, _, err in
            if let err { Task { @MainActor in self?.log(.error, "SOAP: \(err.localizedDescription)") } }
        }.resume()
    }

    // MARK: - Background Keep-Alive

    private func keepAlive() {
        let wav = Data([
            0x52,0x49,0x46,0x46, 0x24,0x00,0x00,0x00,
            0x57,0x41,0x56,0x45,
            0x66,0x6D,0x74,0x20, 0x10,0x00,0x00,0x00,
            0x01,0x00, 0x01,0x00,
            0x44,0xAC,0x00,0x00, 0x88,0x58,0x01,0x00,
            0x02,0x00, 0x10,0x00,
            0x64,0x61,0x74,0x61, 0x00,0x00,0x00,0x00
        ])
        do {
            silentPlayer = try AVAudioPlayer(data: wav)
            silentPlayer?.numberOfLoops = -1
            silentPlayer?.volume = 0
            silentPlayer?.play()
        } catch {
            log(.warning, "Keep-alive konnte nicht gestartet werden: \(error)")
        }
    }

    private func log(_ level: LogEntry.Level, _ msg: String) {
        onLog?(LogEntry(level: level, message: msg))
    }
}
