import Foundation

@MainActor
class SonosDiscovery: ObservableObject {
    @Published var speakers:    [SonosSpeaker] = []
    @Published var isScanning   = false
    @Published var scanStatus   = "Bereit"
    @Published var scanCount    = 0

    var onLog: ((LogEntry) -> Void)?

    private var retryTask:  Task<Void, Never>?
    private var foundUUIDs = Set<String>()

    // MARK: - Public

    func startContinuous() {
        Task { await scan() }
        retryTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 Sekunden
                if !isScanning { await scan() }
            }
        }
    }

    func stop() {
        retryTask?.cancel()
        retryTask = nil
    }

    func scanNow() {
        Task { await scan() }
    }

    // MARK: - Scan

    private func scan() async {
        guard !isScanning else { return }
        isScanning = true
        scanCount += 1
        scanStatus = "Scan #\(scanCount) läuft…"
        log(.info, "Scan #\(scanCount) gestartet")

        guard let subnet = await getSubnet() else {
            scanStatus = "Netzwerk nicht erreichbar"
            log(.warning, "Konnte lokale IP nicht ermitteln – bitte WLAN prüfen")
            isScanning = false
            return
        }

        log(.info, "Subnet-Scan: \(subnet).1–254 auf Port 1400")

        // Max. 40 gleichzeitige Verbindungen – iOS verwirft sonst still viele Requests
        let maxConcurrent = 40
        let allIPs = (1...254).map { "\(subnet).\($0)" }
        let batches = stride(from: 0, to: allIPs.count, by: maxConcurrent).map {
            Array(allIPs[$0..<min($0 + maxConcurrent, allIPs.count)])
        }

        for batch in batches {
            await withTaskGroup(of: SonosSpeaker?.self) { group in
                for ip in batch {
                    group.addTask { await self.probeSonos(ip: ip) }
                }
                for await result in group {
                    guard let speaker = result else { continue }
                    if !foundUUIDs.contains(speaker.uuid) {
                        foundUUIDs.insert(speaker.uuid)
                        speakers.append(speaker)
                        log(.success, "Gefunden: \(speaker.name) @ \(speaker.ip)")
                    }
                }
            }
        }

        isScanning = false
        if speakers.isEmpty {
            scanStatus = "Keine Lautsprecher – nächster Scan in 10s"
            log(.warning, "Keine Sonos-Lautsprecher gefunden")
        } else {
            scanStatus = "\(speakers.count) Lautsprecher gefunden"
        }
    }

    // MARK: - Probe single IP

    private func probeSonos(ip: String) async -> SonosSpeaker? {
        guard let url = URL(string: "http://\(ip):1400/xml/device_description.xml") else { return nil }

        var req = URLRequest(url: url)
        req.timeoutInterval = 1.2

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            guard let xml = String(data: data, encoding: .utf8),
                  xml.contains("ZonePlayer") || xml.contains("Sonos") else { return nil }

            let name  = extractXML(xml, tag: "roomName")
                     ?? extractXML(xml, tag: "friendlyName")?.components(separatedBy: " - ").first
                     ?? "Sonos"
            let model = extractXML(xml, tag: "modelName") ?? "Sonos"
            let uuid  = extractXML(xml, tag: "UDN")?.replacingOccurrences(of: "uuid:", with: "")
                     ?? "ip-\(ip)"

            return SonosSpeaker(name: name, ip: ip, uuid: uuid, model: model)
        } catch {
            return nil
        }
    }

    // MARK: - Helpers

    private func extractXML(_ xml: String, tag: String) -> String? {
        guard let s = xml.range(of: "<\(tag)>"),
              let e = xml.range(of: "</\(tag)>", range: s.upperBound..<xml.endIndex)
        else { return nil }
        return String(xml[s.upperBound..<e.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func getSubnet() async -> String? {
        var addr: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        for p in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(p.pointee.ifa_flags)
            guard p.pointee.ifa_addr.pointee.sa_family == UInt8(AF_INET),
                  (flags & IFF_LOOPBACK) == 0,
                  (flags & IFF_UP) != 0 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(p.pointee.ifa_addr, socklen_t(p.pointee.ifa_addr.pointee.sa_len),
                           &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                let candidate = String(cString: host)
                // Link-Local (169.254.x.x) überspringen – kein echtes WLAN
                if !candidate.hasPrefix("169.254") && candidate != "127.0.0.1" {
                    addr = candidate
                }
            }
        }
        guard let ip = addr else { return nil }
        let parts = ip.components(separatedBy: ".")
        guard parts.count == 4 else { return nil }
        return parts.prefix(3).joined(separator: ".")
    }

    private func log(_ level: LogEntry.Level, _ msg: String) {
        let e = LogEntry(level: level, message: msg)
        onLog?(e)
    }
}
