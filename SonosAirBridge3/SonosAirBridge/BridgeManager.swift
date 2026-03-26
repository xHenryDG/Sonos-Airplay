import Foundation
import Network

class BridgeManager: ObservableObject {
    @Published var activeGroupID: UUID?
    @Published var statusMessage = "Nicht aktiv"
    @Published var isRunning = false

    var onLog: ((LogEntry) -> Void)?

    private var services: [NetService] = []

    // MARK: - Start / Stop

    func start(group: SpeakerGroup, speakers: [SonosSpeaker]) {
        stop()
        guard !speakers.isEmpty else {
            log(.warning, "Keine Lautsprecher für diese Gruppe online"); return
        }

        switch group.mode {
        case .group:
            // Form Sonos group via UPnP, register ONE AirPlay entry
            formSonosGroup(coordinator: speakers[0], followers: Array(speakers.dropFirst()))
            registerAirPlay(name: group.name)
            statusMessage = "'\(group.name)' läuft in AirPlay"
            log(.success, "Gruppe '\(group.name)' als AirPlay gestartet (\(speakers.count) Lautsprecher)")

        case .individual:
            // Register each speaker as its own AirPlay device
            for s in speakers { registerAirPlay(name: s.name) }
            statusMessage = "\(speakers.count) Geräte einzeln in AirPlay"
            log(.success, "\(speakers.count) Lautsprecher einzeln in AirPlay registriert")
        }

        isRunning = true
        activeGroupID = group.id
    }

    func stop() {
        services.forEach { $0.stop() }
        services.removeAll()
        isRunning = false
        activeGroupID = nil
        statusMessage = "Nicht aktiv"
        log(.info, "AirPlay gestoppt")
    }

    // MARK: - Bonjour RAOP (AirPlay audio receiver advertisement)

    private func registerAirPlay(name: String) {
        // RAOP name format: AABBCCDDEEFF@Room Name
        let mac = (0..<6).map { _ in String(format: "%02X", Int.random(in: 0...255)) }.joined()
        let raopName = "\(mac)@\(name)"
        let port = Int32.random(in: 49152...65535)

        let svc = NetService(domain: "local.", type: "_raop._tcp.", name: raopName, port: port)
        svc.setTXTRecord(NetService.data(fromTXTRecord: airPlayTXTRecord()))
        svc.publish()
        services.append(svc)
        log(.info, "Bonjour: '\(name)' auf Port \(port) registriert")
    }

    private func airPlayTXTRecord() -> [String: Data] {
        // Standard RAOP TXT record fields that iOS recognises as AirPlay speaker
        let fields: [String: String] = [
            "txtvers": "1",
            "ch":      "2",           // channels
            "cn":      "0,1,2,3",     // codecs: PCM, ALAC, AAC, AAC-ELD
            "et":      "0,3,5",       // encryption
            "md":      "0,1,2",       // metadata
            "pw":      "false",       // no password
            "sr":      "44100",       // sample rate
            "ss":      "16",          // sample size
            "tp":      "UDP",
            "vs":      "130.14",      // AirPlay version
            "am":      "SonosAirBridge",
            "sf":      "0x4"
        ]
        return fields.mapValues { $0.data(using: .utf8)! }
    }

    // MARK: - Sonos UPnP Grouping

    private func formSonosGroup(coordinator: SonosSpeaker, followers: [SonosSpeaker]) {
        guard !followers.isEmpty else { return }
        log(.info, "Bilde Sonos-Gruppe: Koordinator \(coordinator.name)")
        for f in followers {
            log(.info, "Füge \(f.name) zur Gruppe hinzu")
            sonosSOAP(
                ip: coordinator.ip,
                path: "/MediaRenderer/AVTransport/Control",
                action: "urn:schemas-upnp-org:service:AVTransport:1#SetAVTransportURI",
                body: groupBody(coordinatorIP: coordinator.ip, followerUUID: f.uuid)
            )
        }
    }

    private func groupBody(coordinatorIP: String, followerUUID: String) -> String {
        """
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"
          s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
          <s:Body>
            <u:SetAVTransportURI xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
              <InstanceID>0</InstanceID>
              <CurrentURI>x-rincon:\(followerUUID)</CurrentURI>
              <CurrentURIMetaData></CurrentURIMetaData>
            </u:SetAVTransportURI>
          </s:Body>
        </s:Envelope>
        """
    }

    private func sonosSOAP(ip: String, path: String, action: String, body: String) {
        guard let url = URL(string: "http://\(ip):1400\(path)") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("text/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.setValue("\"\(action)\"", forHTTPHeaderField: "SOAPACTION")
        req.httpBody = body.data(using: .utf8)
        req.timeoutInterval = 5
        URLSession.shared.dataTask(with: req) { [weak self] _, _, err in
            if let err { self?.log(.error, "SOAP: \(err.localizedDescription)") }
        }.resume()
    }

    private func log(_ level: LogEntry.Level, _ msg: String) {
        let e = LogEntry(level: level, message: msg)
        DispatchQueue.main.async { self.onLog?(e) }
    }
}
