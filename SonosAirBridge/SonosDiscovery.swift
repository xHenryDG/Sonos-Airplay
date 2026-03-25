import Foundation
import Network
import Combine

class SonosDiscovery: ObservableObject {
    @Published var speakers: [SonosSpeaker] = []
    @Published var isScanning = false
    @Published var scanStatus = "Bereit"

    var onLog: ((LogEntry) -> Void)?

    private var retryTimer: Timer?
    private var scanCount = 0
    private var udpConnection: NWConnection?
    private var foundUUIDs = Set<String>()

    // MARK: - Public

    func startContinuousDiscovery() {
        log(.info, "Starte kontinuierliche Suche…")
        scan()
        retryTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { [weak self] _ in
            guard let self, !self.isScanning else { return }
            self.scan()
        }
    }

    func stopContinuousDiscovery() {
        retryTimer?.invalidate()
        retryTimer = nil
        udpConnection?.cancel()
        udpConnection = nil
    }

    func scan() {
        guard !isScanning else { return }
        scanCount += 1
        isScanning = true
        scanStatus = "Suche läuft (#\(scanCount))…"
        log(.info, "Scan #\(scanCount) gestartet")

        let group = DispatchGroup()

        // Method 1: SSDP multicast
        group.enter()
        sendSSDPSearch {
            group.leave()
        }

        // Method 2: Subnet IP scan (parallel)
        group.enter()
        scanSubnet {
            group.leave()
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            self.isScanning = false
            if self.speakers.isEmpty {
                self.scanStatus = "Keine Lautsprecher gefunden – versuche erneut in 8s"
                self.log(.warning, "Keine Sonos-Lautsprecher im Netzwerk gefunden")
            } else {
                self.scanStatus = "\(self.speakers.count) Lautsprecher gefunden"
                self.log(.success, "\(self.speakers.count) Lautsprecher gefunden")
            }
        }
    }

    // MARK: - SSDP

    private func sendSSDPSearch(completion: @escaping () -> Void) {
        let msg = "M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: \"ssdp:discover\"\r\nMX: 3\r\nST: urn:schemas-upnp-org:device:ZonePlayer:1\r\n\r\n"

        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true
        let conn = NWConnection(
            host: NWEndpoint.Host("239.255.255.250"),
            port: NWEndpoint.Port(integerLiteral: 1900),
            using: params
        )
        udpConnection = conn

        conn.stateUpdateHandler = { [weak self] state in
            if state == .ready {
                conn.send(content: msg.data(using: .utf8)!, completion: .contentProcessed { _ in })
                self?.receiveUDP(conn: conn)
            }
        }
        conn.start(queue: .global(qos: .userInitiated))

        // Stop listening after 4 seconds
        DispatchQueue.global().asyncAfter(deadline: .now() + 4) {
            conn.cancel()
            completion()
        }
    }

    private func receiveUDP(conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65535) { [weak self] data, _, _, error in
            if let data, let str = String(data: data, encoding: .utf8) {
                self?.parseSSDPResponse(str)
            }
            if error == nil { self?.receiveUDP(conn: conn) }
        }
    }

    private func parseSSDPResponse(_ response: String) {
        guard response.uppercased().contains("SONOS") ||
              response.contains("ZonePlayer") ||
              response.contains("Rincon") else { return }

        var location: String?
        var uuid: String?

        for line in response.components(separatedBy: "\r\n") {
            let lo = line.lowercased()
            if lo.hasPrefix("location:") {
                location = line.dropFirst("location:".count).trimmingCharacters(in: .whitespaces)
            }
            if lo.hasPrefix("usn:") {
                let usn = String(line.dropFirst(4)).trimmingCharacters(in: .whitespaces)
                if let r = usn.range(of: "uuid:", options: .caseInsensitive) {
                    let after = String(usn[r.upperBound...])
                    uuid = after.components(separatedBy: "::").first?.trimmingCharacters(in: .whitespaces)
                }
            }
        }

        if let loc = location, let uid = uuid, !foundUUIDs.contains(uid) {
            if let url = URL(string: loc), let host = url.host {
                log(.info, "SSDP: Sonos gefunden bei \(host)")
                fetchDeviceInfo(ip: host, uuid: uid, from: loc)
            }
        }
    }

    // MARK: - Subnet Scan

    private func scanSubnet(completion: @escaping () -> Void) {
        // Get local IP and derive subnet
        guard let localIP = getLocalIP() else {
            log(.warning, "Lokale IP nicht ermittelbar – Subnet-Scan übersprungen")
            completion()
            return
        }

        let parts = localIP.components(separatedBy: ".")
        guard parts.count == 4 else { completion(); return }
        let subnet = parts.prefix(3).joined(separator: ".")
        log(.info, "Subnet-Scan auf \(subnet).1–254")

        let group = DispatchGroup()
        // Scan common Sonos port 1400 across subnet
        for i in 1...254 {
            let ip = "\(subnet).\(i)"
            group.enter()
            checkSonosPort(ip: ip) { [weak self] found in
                if found { self?.fetchDeviceInfo(ip: ip, uuid: "subnet-\(ip)", from: "http://\(ip):1400/xml/device_description.xml") }
                group.leave()
            }
        }

        group.notify(queue: .global()) { completion() }
    }

    private func checkSonosPort(ip: String, completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: "http://\(ip):1400/xml/device_description.xml") else {
            completion(false); return
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 1.5
        URLSession.shared.dataTask(with: req) { data, resp, _ in
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if let data, code == 200, let body = String(data: data, encoding: .utf8),
               body.contains("ZonePlayer") || body.contains("Sonos") {
                completion(true)
            } else {
                completion(false)
            }
        }.resume()
    }

    // MARK: - Device Info

    private func fetchDeviceInfo(ip: String, uuid: String, from location: String) {
        // Deduplicate: extract real UUID from location if possible
        let deviceURL = location.contains("device_description") ? location
            : "http://\(ip):1400/xml/device_description.xml"

        guard let url = URL(string: deviceURL) else { return }

        URLSession.shared.dataTask(with: URLRequest(url: url)) { [weak self] data, _, _ in
            guard let self, let data, let xml = String(data: data, encoding: .utf8) else { return }

            let name  = self.extractXML(xml, tag: "roomName")
                     ?? self.extractXML(xml, tag: "friendlyName")?.components(separatedBy: " - ").first
                     ?? "Sonos"
            let model = self.extractXML(xml, tag: "modelName") ?? "Sonos"
            let realUUID = self.extractXML(xml, tag: "UDN")?.replacingOccurrences(of: "uuid:", with: "") ?? uuid

            DispatchQueue.main.async {
                guard !self.foundUUIDs.contains(realUUID) else { return }
                self.foundUUIDs.insert(realUUID)
                let speaker = SonosSpeaker(name: name, ip: ip, uuid: realUUID, model: model)
                self.speakers.append(speaker)
                self.log(.success, "Lautsprecher: \(name) (\(ip))")
            }
        }.resume()
    }

    // MARK: - Helpers

    private func extractXML(_ xml: String, tag: String) -> String? {
        guard let start = xml.range(of: "<\(tag)>"),
              let end   = xml.range(of: "</\(tag)>", range: start.upperBound..<xml.endIndex)
        else { return nil }
        return String(xml[start.upperBound..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func getLocalIP() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            let addr  = ptr.pointee.ifa_addr.pointee
            if addr.sa_family == UInt8(AF_INET),
               (flags & IFF_LOOPBACK) == 0,
               (flags & IFF_UP) != 0 {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(ptr.pointee.ifa_addr, socklen_t(addr.sa_len),
                               &hostname, socklen_t(hostname.count),
                               nil, 0, NI_NUMERICHOST) == 0 {
                    address = String(cString: hostname)
                }
            }
        }
        return address
    }

    private func log(_ level: LogEntry.Level, _ message: String) {
        let entry = LogEntry(level: level, message: message)
        DispatchQueue.main.async { self.onLog?(entry) }
    }
}
