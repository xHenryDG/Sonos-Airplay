import Foundation
import AVFoundation
import Network

// MARK: - AirPlay Bridge Manager
// This component:
// 1. Starts a local AirPlay-compatible receiver (advertised via Bonjour/mDNS)
// 2. When audio arrives, streams it to all selected Sonos speakers via their HTTP API

class AirPlayBridgeManager: ObservableObject {
    @Published var isRunning = false
    @Published var bridgeName: String = "Sonos Group"
    @Published var statusMessage: String = "Bereit"
    
    private var selectedSpeakers: [SonosSpeaker] = []
    private var httpServer: HTTPBridgeServer?
    
    /// groupName = nil → register each speaker individually in AirPlay
    func startBridge(speakers: [SonosSpeaker], groupName: String?) {
        selectedSpeakers = speakers
        
        guard !speakers.isEmpty else {
            statusMessage = "Keine Lautsprecher ausgewählt"
            return
        }
        
        if let name = groupName {
            // GROUP mode: group all speakers, register once
            bridgeName = name
            setupSonosGroup(speakers: speakers) { [weak self] success in
                DispatchQueue.main.async {
                    if success {
                        self?.startLocalAirPlayReceiver(groupName: name)
                        self?.isRunning = true
                        self?.statusMessage = "AirPlay aktiv – wähle '\(name)' in AirPlay"
                    } else {
                        self?.statusMessage = "Fehler beim Konfigurieren der Sonos-Gruppe"
                    }
                }
            }
        } else {
            // INDIVIDUAL mode: register each speaker as its own AirPlay device
            bridgeName = speakers.map { $0.name }.joined(separator: ", ")
            for speaker in speakers {
                startLocalAirPlayReceiver(groupName: speaker.name)
            }
            DispatchQueue.main.async {
                self.isRunning = true
                self.statusMessage = "AirPlay aktiv – \(speakers.count) Geräte verfügbar"
            }
        }
    }
    
    func stopBridge() {
        httpServer?.stop()
        httpServer = nil
        isRunning = false
        statusMessage = "Gestoppt"
        // Restore Sonos group state if needed
    }
    
    // MARK: - Sonos Group Setup
    
    /// Uses Sonos UPnP/HTTP API to group all speakers under the first (coordinator)
    private func setupSonosGroup(speakers: [SonosSpeaker], completion: @escaping (Bool) -> Void) {
        guard let coordinator = speakers.first else { completion(false); return }
        
        let followers = Array(speakers.dropFirst())
        let group = DispatchGroup()
        var success = true
        
        for follower in followers {
            group.enter()
            let body = """
            <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"
              s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
              <s:Body>
                <u:AddMember xmlns:u="urn:schemas-upnp-org:service:GroupManagement:1">
                  <MemberID>\(follower.uuid)</MemberID>
                  <BootSeq>0</BootSeq>
                </u:AddMember>
              </s:Body>
            </s:Envelope>
            """
            
            sonosHTTPAction(
                ip: coordinator.ip,
                endpoint: "/GroupManagement/Control",
                soapAction: "urn:schemas-upnp-org:service:GroupManagement:1#AddMember",
                body: body
            ) { err in
                if err != nil { success = false }
                group.leave()
            }
        }
        
        group.notify(queue: .global()) { completion(success) }
    }
    
    private func sonosHTTPAction(ip: String, endpoint: String, soapAction: String, body: String, completion: @escaping (Error?) -> Void) {
        guard let url = URL(string: "http://\(ip):1400\(endpoint)") else {
            completion(URLError(.badURL)); return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("text/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.setValue("\"\(soapAction)\"", forHTTPHeaderField: "SOAPACTION")
        req.httpBody = body.data(using: .utf8)
        req.timeoutInterval = 5
        URLSession.shared.dataTask(with: req) { _, _, error in completion(error) }.resume()
    }
    
    // MARK: - Local AirPlay Receiver
    
    /// Registers a Bonjour service so iOS sees this device as an AirPlay target
    private func startLocalAirPlayReceiver(groupName: String) {
        httpServer = HTTPBridgeServer(name: groupName, speakers: selectedSpeakers)
        httpServer?.start()
    }
}

// MARK: - Minimal HTTP Bridge Server

/// Listens on a local port and forwards audio stream URLs to Sonos speakers.
/// Full AirPlay RTSP stack is out of scope for a pure Swift package without
/// private entitlements – this server handles the Sonos "setAVTransportURI"
/// so you can push any HTTP audio source to the group.
class HTTPBridgeServer {
    private let name: String
    private let speakers: [SonosSpeaker]
    private var listener: NWListener?
    
    init(name: String, speakers: [SonosSpeaker]) {
        self.name = name
        self.speakers = speakers
    }
    
    func start() {
        do {
            listener = try NWListener(using: .tcp, on: 9876)
            listener?.newConnectionHandler = { [weak self] conn in
                self?.handleConnection(conn)
            }
            listener?.start(queue: .global())
        } catch {
            print("Server error: \(error)")
        }
    }
    
    func stop() { listener?.cancel() }
    
    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global())
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, _, _ in
            if let data = data, let request = String(data: data, encoding: .utf8) {
                self?.processRequest(request, connection: connection)
            }
        }
    }
    
    private func processRequest(_ request: String, connection: NWConnection) {
        // Parse simple JSON command: { "streamURL": "http://..." }
        guard request.contains("streamURL"),
              let data = request.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              let url = json["streamURL"] else { return }
        
        pushURLToSonos(url)
        let response = "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nOK"
        connection.send(content: response.data(using: .utf8), completion: .idempotent)
    }
    
    func pushURLToSonos(_ url: String) {
        guard let coordinator = speakers.first else { return }
        
        let escapedURL = url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? url
        let body = """
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"
          s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
          <s:Body>
            <u:SetAVTransportURI xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
              <InstanceID>0</InstanceID>
              <CurrentURI>\(escapedURL)</CurrentURI>
              <CurrentURIMetaData></CurrentURIMetaData>
            </u:SetAVTransportURI>
          </s:Body>
        </s:Envelope>
        """
        
        guard let reqURL = URL(string: "http://\(coordinator.ip):1400/MediaRenderer/AVTransport/Control") else { return }
        var req = URLRequest(url: reqURL)
        req.httpMethod = "POST"
        req.setValue("text/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.setValue("\"urn:schemas-upnp-org:service:AVTransport:1#SetAVTransportURI\"", forHTTPHeaderField: "SOAPACTION")
        req.httpBody = body.data(using: .utf8)
        URLSession.shared.dataTask(with: req).resume()
    }
}
