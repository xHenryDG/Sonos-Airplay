import Foundation
import Network

class BridgeManager: ObservableObject {
    @Published var activeGroupID: UUID?
    @Published var statusMessage = "Nicht aktiv"
    @Published var isRunning = false

    var onLog: ((LogEntry) -> Void)?

    private var bonjourService: NetService?
    private var listeners: [NWListener] = []

    // MARK: - Start

    /// groupName = nil → each speaker registered individually
    func start(speakers: [SonosSpeaker], groupName: String?, groupID: UUID) {
        stop()
        guard !speakers.isEmpty else { return }

        log(.info, "Starte Bridge für \(speakers.count) Lautsprecher")

        if let name = groupName {
            // Group mode: form Sonos group, register one AirPlay entry
            formSonosGroup(coordinator: speakers[0], followers: Array(speakers.dropFirst()))
            registerBonjour(name: name)
            statusMessage = "'\(name)' in AirPlay aktiv"
            log(.success, "Gruppe '\(name)' in AirPlay registriert")
        } else {
            // Individual mode: register each speaker separately
            for speaker in speakers {
                registerBonjour(name: speaker.name)
                log(.success, "'\(speaker.name)' einzeln in AirPlay registriert")
            }
            statusMessage = "\(speakers.count) Lautsprecher einzeln in AirPlay"
        }

        isRunning = true
        activeGroupID = groupID
    }

    func stop() {
        bonjourService?.stop()
        bonjourService = nil
        listeners.forEach { $0.cancel() }
        listeners.removeAll()
        isRunning = false
        activeGroupID = nil
        statusMessage = "Nicht aktiv"
        log(.info, "Bridge gestoppt")
    }

    // MARK: - Sonos UPnP Grouping

    private func formSonosGroup(coordinator: SonosSpeaker, followers: [SonosSpeaker]) {
        for follower in followers {
            soapsend(ip: coordinator.ip,
                     path: "/MediaRenderer/AVTransport/Control",
                     action: "urn:schemas-upnp-org:service:AVTransport:1#SetAVTransportURI",
                     body: avTransportBody(followerIP: follower.ip))
            log(.info, "Füge \(follower.name) zur Gruppe hinzu")
        }
    }

    private func avTransportBody(followerIP: String) -> String {
        """
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"
          s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
          <s:Body>
            <u:SetAVTransportURI xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
              <InstanceID>0</InstanceID>
              <CurrentURI>x-rincon:\(followerIP)</CurrentURI>
              <CurrentURIMetaData></CurrentURIMetaData>
            </u:SetAVTransportURI>
          </s:Body>
        </s:Envelope>
        """
    }

    private func soapsend(ip: String, path: String, action: String, body: String) {
        guard let url = URL(string: "http://\(ip):1400\(path)") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("text/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.setValue("\"\(action)\"", forHTTPHeaderField: "SOAPACTION")
        req.httpBody = body.data(using: .utf8)
        req.timeoutInterval = 5
        URLSession.shared.dataTask(with: req) { [weak self] _, resp, err in
            if let err { self?.log(.error, "SOAP-Fehler: \(err.localizedDescription)") }
        }.resume()
    }

    // MARK: - Bonjour / mDNS

    private func registerBonjour(name: String) {
        // Register as RAOP (AirPlay audio) device on a random port
        let port = Int32.random(in: 49152...65535)
        let service = NetService(domain: "local.", type: "_raop._tcp.", name: "\(randomMAC())@\(name)", port: port)

        // AirPlay device capabilities TXT record
        let txt: [String: String] = [
            "txtvers": "1",
            "ch":      "2",
            "cn":      "0,1,2,3",
            "et":      "0,3,5",
            "md":      "0,1,2",
            "pw":      "false",
            "sr":      "44100",
            "ss":      "16",
            "tp":      "UDP",
            "vs":      "130.14",
            "am":      "SonosAirBridge",
            "sf":      "0x4"
        ]

        var txtData = [String: Data]()
        for (k, v) in txt { txtData[k] = v.data(using: .utf8)! }
        service.setTXTRecord(NetService.data(fromTXTRecord: txtData))
        service.publish()
        bonjourService = service
    }

    private func randomMAC() -> String {
        (0..<6).map { _ in String(format: "%02X", Int.random(in: 0...255)) }.joined(separator: "")
    }

    private func log(_ level: LogEntry.Level, _ message: String) {
        let entry = LogEntry(level: level, message: message)
        DispatchQueue.main.async { self.onLog?(entry) }
    }
}
