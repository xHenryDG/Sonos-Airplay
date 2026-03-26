import Foundation
import Network

class SonosDiscovery: ObservableObject {
    @Published var speakers: [SonosSpeaker] = []
    @Published var isScanning = false
    @Published var scanStatus = "Bereit"

    var onLog: ((LogEntry) -> Void)?

    private var retryTimer: Timer?
    private var scanCount = 0
    private var foundUUIDs = Set<String>()
    private var scanSession: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 1.5
        cfg.timeoutIntervalForResource = 1.5
        return URLSession(configuration: cfg)
    }()

    // MARK: - Public

    func startContinuousDiscovery() {
        log(.info, "Kontinuierliche Suche gestartet")
        performScan()
        retryTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            guard let self, !self.isScanning else { return }
            self.performScan()
        }
    }

    func stopContinuousDiscovery() {
        retryTimer?.invalidate()
        retryTimer = nil
    }

    func performScan() {
        guard !isScanning else { return }
        scanCount += 1
        isScanning = true
        scanStatus = "Scan #\(scanCount) läuft…"
        log(.info, "Scan #\(scanCount) gestartet")

        guard let subnet = localSubnet() else {
            log(.warning, "Lokale IP nicht gefunden. Bist du im WLAN?")
            DispatchQueue.main.async {
                self.isScanning = false
                self.scanStatus = "Kein WLAN gefunden"
            }
            return
        }

        log(.info, "Scanne Subnetz \(subnet).1–254 auf Port 1400")

        let group = DispatchGroup()
        let concurrentQueue = DispatchQueue(label: "com.sonosairbridge.scan", attributes: .concurrent)
        // Semaphore limits parallel connections to avoid overwhelming the network stack
        let semaphore = DispatchSemaphore(value: 40)

        for i in 1...254 {
            group.enter()
            concurrentQueue.async { [weak self] in
                semaphore.wait()
                defer { semaphore.signal(); group.leave() }
                guard let self else { return }
                let ip = "\(subnet).\(i)"
                self.checkHost(ip: ip)
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            self.isScanning = false
            if self.speakers.isEmpty {
                self.scanStatus = "Keine Sonos-Boxen gefunden – nächster Scan in 10s"
                self.log(.warning, "Keine Sonos-Lautsprecher gefunden")
            } else {
                self.scanStatus = "\(self.speakers.count) Lautsprecher online"
            }
        }
    }

    // MARK: - Check one host

    private func checkHost(ip: String) {
        guard let url = URL(string: "http://\(ip):1400/xml/device_description.xml") else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 1.5

        let sema = DispatchSemaphore(value: 0)
        scanSession.dataTask(with: req) { [weak self] data, resp, _ in
            defer { sema.signal() }
            guard let self,
                  let data,
                  (resp as? HTTPURLResponse)?.statusCode == 200,
                  let xml = String(data: data, encoding: .utf8),
                  xml.contains("ZonePlayer") || xml.contains("Sonos") || xml.contains("Rincon")
            else { return }

            let name  = self.extractXML(xml, "roomName")
                     ?? self.extractXML(xml, "friendlyName")?.components(separatedBy: " - ").first
                     ?? "Sonos"
            let model = self.extractXML(xml, "modelName") ?? "Sonos"
            let uuid  = self.extractXML(xml, "UDN")?.replacingOccurrences(of: "uuid:", with: "")
                     ?? "ip-\(ip)"

            DispatchQueue.main.async {
                guard !self.foundUUIDs.contains(uuid) else { return }
                self.foundUUIDs.insert(uuid)
                let speaker = SonosSpeaker(name: name, ip: ip, uuid: uuid, model: model)
                self.speakers.append(speaker)
                self.scanStatus = "\(self.speakers.count) Lautsprecher gefunden…"
                self.log(.success, "Gefunden: \(name) (\(model)) bei \(ip)")
            }
        }.resume()
        sema.wait()
    }

    // MARK: - Helpers

    private func extractXML(_ xml: String, _ tag: String) -> String? {
        guard let s = xml.range(of: "<\(tag)>"),
              let e = xml.range(of: "</\(tag)>", range: s.upperBound..<xml.endIndex)
        else { return nil }
        return String(xml[s.upperBound..<e.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func localSubnet() -> String? {
        var addr: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            guard ptr.pointee.ifa_addr.pointee.sa_family == UInt8(AF_INET),
                  (flags & IFF_LOOPBACK) == 0,
                  (flags & IFF_UP) != 0 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(ptr.pointee.ifa_addr, socklen_t(ptr.pointee.ifa_addr.pointee.sa_len),
                           &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                let ip = String(cString: host)
                // Skip link-local (169.254.x.x) and loopback
                if !ip.hasPrefix("169.254") && ip != "127.0.0.1" {
                    addr = ip
                }
            }
        }
        guard let ip = addr else { return nil }
        let parts = ip.components(separatedBy: ".")
        guard parts.count == 4 else { return nil }
        return parts.prefix(3).joined(separator: ".")
    }

    private func log(_ level: LogEntry.Level, _ msg: String) {
        let entry = LogEntry(level: level, message: msg)
        DispatchQueue.main.async { self.onLog?(entry) }
    }
}
