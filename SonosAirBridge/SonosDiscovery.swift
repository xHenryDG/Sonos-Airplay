import Foundation
import Network
import Combine

// MARK: - Model

struct SonosSpeaker: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let ip: String
    let uuid: String
    var isSelected: Bool = false
    
    func hash(into hasher: inout Hasher) { hasher.combine(uuid) }
    static func == (lhs: SonosSpeaker, rhs: SonosSpeaker) -> Bool { lhs.uuid == rhs.uuid }
}

// MARK: - Discovery

class SonosDiscovery: ObservableObject {
    @Published var speakers: [SonosSpeaker] = []
    @Published var isScanning = false
    
    private var connection: NWConnection?
    private var cancelBag = Set<AnyCancellable>()
    
    // SSDP multicast address and port
    private let ssdpAddress = "239.255.255.250"
    private let ssdpPort: UInt16 = 1900
    
    func startDiscovery() {
        speakers = []
        isScanning = true
        sendSSDPSearch()
        
        // Stop scanning after 5 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.isScanning = false
        }
    }
    
    private func sendSSDPSearch() {
        let ssdpMessage = """
        M-SEARCH * HTTP/1.1\r
        HOST: 239.255.255.250:1900\r
        MAN: "ssdp:discover"\r
        MX: 3\r
        ST: urn:schemas-upnp-org:device:ZonePlayer:1\r
        \r
        
        """
        
        let host = NWEndpoint.Host(ssdpAddress)
        let port = NWEndpoint.Port(integerLiteral: ssdpPort)
        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true
        
        connection = NWConnection(host: host, port: port, using: params)
        connection?.stateUpdateHandler = { [weak self] state in
            if state == .ready {
                self?.sendData(ssdpMessage)
                self?.receiveData()
            }
        }
        connection?.start(queue: .global())
    }
    
    private func sendData(_ message: String) {
        guard let data = message.data(using: .utf8) else { return }
        connection?.send(content: data, completion: .contentProcessed { _ in })
    }
    
    private func receiveData() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65535) { [weak self] data, _, _, error in
            if let data = data, let response = String(data: data, encoding: .utf8) {
                self?.parseSSDPResponse(response)
            }
            if error == nil { self?.receiveData() }
        }
    }
    
    private func parseSSDPResponse(_ response: String) {
        guard response.contains("Sonos") || response.contains("ZonePlayer") else { return }
        
        var location: String?
        var uuid: String?
        
        for line in response.components(separatedBy: "\r\n") {
            let lower = line.lowercased()
            if lower.hasPrefix("location:") {
                location = line.components(separatedBy: ": ").dropFirst().joined(separator: ": ").trimmingCharacters(in: .whitespaces)
            }
            if lower.hasPrefix("usn:") {
                let usn = line.components(separatedBy: ": ").dropFirst().joined(separator: ": ")
                if let range = usn.range(of: "uuid:") {
                    let afterUUID = String(usn[range.upperBound...])
                    uuid = afterUUID.components(separatedBy: "::").first?.trimmingCharacters(in: .whitespaces)
                }
            }
        }
        
        guard let loc = location, let uid = uuid else { return }
        
        // Extract IP from location URL
        if let url = URL(string: loc), let host = url.host {
            fetchSpeakerName(ip: host, uuid: uid, location: loc)
        }
    }
    
    private func fetchSpeakerName(ip: String, uuid: String, location: String) {
        guard let url = URL(string: location) else { return }
        
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            var name = "Sonos Speaker"
            if let data = data, let xml = String(data: data, encoding: .utf8) {
                // Extract room name from UPnP XML
                if let range = xml.range(of: "<roomName>") {
                    let after = String(xml[range.upperBound...])
                    if let end = after.range(of: "</roomName>") {
                        name = String(after[..<end.lowerBound])
                    }
                } else if let range = xml.range(of: "<friendlyName>") {
                    let after = String(xml[range.upperBound...])
                    if let end = after.range(of: "</friendlyName>") {
                        let full = String(after[..<end.lowerBound])
                        // Sonos names are often "Room - ModelName"
                        name = full.components(separatedBy: " - ").first ?? full
                    }
                }
            }
            
            DispatchQueue.main.async {
                let speaker = SonosSpeaker(name: name, ip: ip, uuid: uuid)
                if !(self?.speakers.contains(speaker) ?? false) {
                    self?.speakers.append(speaker)
                }
            }
        }.resume()
    }
}
