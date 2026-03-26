import Foundation
import Network
import AVFoundation

// MARK: - RAOP Server
// Lauscht auf eingehende AirPlay v1 (RAOP) Verbindungen,
// handelt den RTSP-Handshake und empfängt den RTP-Audiostream.
// Das empfangene ALAC-Audio wird dekodiert und per HTTP an Sonos gesendet.

@MainActor
class RAOPServer: ObservableObject {
    private let listenPort: UInt16
    private var raopPort: UInt16 = 6000

    init(port: UInt16 = 5000) { self.listenPort = port }
    @Published var isRunning = false
    @Published var isStreaming = false
    @Published var statusMessage = "Bereit"

    var onLog: ((LogEntry) -> Void)?

    private var listener: NWListener?
    private var audioForwarder: SonosAudioForwarder?
    private let raopPort: UInt16 = 5000

    // MARK: - Start / Stop

    func start(targetSpeaker: SonosSpeaker, allSpeakers: [SonosSpeaker] = []) {
        stop()
        log(.info, "RAOP-Server startet für \(targetSpeaker.name)...")

        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            let listener = try NWListener(using: params,
                                          on: NWEndpoint.Port(rawValue: listenPort)!)
            self.listener = listener

            listener.newConnectionHandler = { [weak self] conn in
                guard let self else { return }
                Task { @MainActor in
                    self.handleConnection(conn, speaker: targetSpeaker)
                }
            }

            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                Task { @MainActor in
                    switch state {
                    case .ready:
                        self.isRunning = true
                        self.statusMessage = "Wartet auf AirPlay-Verbindung…"
                        self.log(.success, "RAOP-Server bereit auf Port \(self.listenPort)")
                    case .failed(let e):
                        self.isRunning = false
                        self.log(.error, "RAOP-Server Fehler: \(e)")
                    default: break
                    }
                }
            }
            listener.start(queue: .global(qos: .userInitiated))
        } catch {
            log(.error, "RAOP-Server konnte nicht gestartet werden: \(error)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        audioForwarder?.stop()
        audioForwarder = nil
        isRunning = false
        isStreaming = false
        statusMessage = "Gestoppt"
    }

    // MARK: - RTSP Handshake

    private func handleConnection(_ conn: NWConnection, speaker: SonosSpeaker) {
        conn.start(queue: .global(qos: .userInitiated))
        log(.info, "AirPlay-Verbindung eingehend")

        // RTSP-Nachrichten lesen (AirPlay nutzt RTSP über TCP)
        receiveRTSP(conn: conn, speaker: speaker, buffer: Data())
    }

    private func receiveRTSP(conn: NWConnection, speaker: SonosSpeaker, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            guard let data, !data.isEmpty else {
                if isComplete { conn.cancel() }
                return
            }

            var newBuffer = buffer
            newBuffer.append(data)

            Task { @MainActor in
                // RTSP-Nachrichten sind durch \r\n\r\n getrennt
                while let range = newBuffer.range(of: Data("\r\n\r\n".utf8)) {
                    let messageData = newBuffer[..<range.upperBound]
                    newBuffer = Data(newBuffer[range.upperBound...])

                    if let message = String(data: messageData, encoding: .utf8) {
                        let response = self.processRTSP(message: message, conn: conn, speaker: speaker)
                        if let responseData = response.data(using: .utf8) {
                            conn.send(content: responseData, completion: .idempotent)
                        }
                    }
                }
                // Weiter lesen
                self.receiveRTSP(conn: conn, speaker: speaker, buffer: newBuffer)
            }
        }
    }

    private var rtspSession = UUID().uuidString
    private var rtpPort: UInt16 = 6000

    private func processRTSP(message: String, conn: NWConnection, speaker: SonosSpeaker) -> String {
        let lines = message.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return rtspError(500) }

        let parts = requestLine.components(separatedBy: " ")
        guard parts.count >= 2 else { return rtspError(400) }

        let method = parts[0]
        let cseq = lines.first(where: { $0.hasPrefix("CSeq:") })?.components(separatedBy: ": ").last ?? "1"

        log(.info, "RTSP \(method)")

        switch method {
        case "OPTIONS":
            return rtspOK(cseq: cseq, extra: "Public: ANNOUNCE, SETUP, RECORD, PAUSE, FLUSH, TEARDOWN, OPTIONS, GET_PARAMETER, SET_PARAMETER\r\n")

        case "ANNOUNCE":
            // SDP enthält Audio-Konfiguration (ALAC-Parameter)
            return rtspOK(cseq: cseq)

        case "SETUP":
            // Client sendet seinen RTP-Port, wir antworten mit unserem
            // Transport-Header parsen: Transport: RTP/AVP/UDP;...;client_port=XXXX
            var clientDataPort: UInt16 = 6000
            if let transport = lines.first(where: { $0.hasPrefix("Transport:") }) {
                let tParts = transport.components(separatedBy: ";")
                for p in tParts {
                    if p.trimmingCharacters(in: .whitespaces).hasPrefix("client_port=") {
                        let portStr = p.components(separatedBy: "=").last ?? ""
                        let ports = portStr.components(separatedBy: "-")
                        clientDataPort = UInt16(ports.first?.trimmingCharacters(in: .whitespaces) ?? "6000") ?? 6000
                    }
                }
            }
            rtpPort = clientDataPort

            let transport = "RTP/AVP/UDP;unicast;client_port=\(clientDataPort)-\(clientDataPort+1);server_port=\(rtpPort+2)-\(rtpPort+3);mode=record"
            return rtspOK(cseq: cseq, extra: "Transport: \(transport)\r\nSession: \(rtspSession)\r\n")

        case "RECORD":
            // Stream beginnt — Sonos-Forwarder starten
            startAudioForwarding(speaker: speaker)
            return rtspOK(cseq: cseq, extra: "Audio-Latency: 2205\r\n")

        case "SET_PARAMETER":
            // Lautstärke-Änderungen
            if let volLine = lines.first(where: { $0.hasPrefix("volume:") }) {
                let volStr = volLine.components(separatedBy: ": ").last ?? "0"
                if let vol = Double(volStr.trimmingCharacters(in: .whitespaces)) {
                    // RAOP Lautstärke: -144 (stumm) bis 0 (max)
                    // Sonos erwartet 0–100
                    let sonosVol = vol <= -144 ? 0 : Int((vol + 30) / 30 * 100)
                    let clamped = max(0, min(100, sonosVol))
                    Task { await self.setSonosVolume(speaker: speaker, volume: clamped) }
                }
            }
            return rtspOK(cseq: cseq)

        case "FLUSH", "PAUSE":
            audioForwarder?.pause()
            return rtspOK(cseq: cseq)

        case "TEARDOWN":
            audioForwarder?.stop()
            isStreaming = false
            statusMessage = "Verbindung beendet"
            conn.cancel()
            return rtspOK(cseq: cseq)

        default:
            return rtspOK(cseq: cseq)
        }
    }

    // MARK: - Audio Forwarding

    private func startAudioForwarding(speaker: SonosSpeaker) {
        isStreaming = true
        statusMessage = "Stream aktiv → \(speaker.name)"
        log(.success, "Audio-Stream startet → \(speaker.name)")

        let forwarder = SonosAudioForwarder(speaker: speaker, rtpPort: rtpPort)
        forwarder.onLog = { [weak self] entry in
            Task { @MainActor in self?.onLog?(entry) }
        }
        self.audioForwarder = forwarder
        forwarder.start()
    }

    // MARK: - Sonos Volume (UPnP SOAP)

    private func setSonosVolume(speaker: SonosSpeaker, volume: Int) async {
        guard let url = URL(string: "http://\(speaker.ip):1400/MediaRenderer/RenderingControl/Control") else { return }
        let body = """
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
          <s:Body>
            <u:SetVolume xmlns:u="urn:schemas-upnp-org:service:RenderingControl:1">
              <InstanceID>0</InstanceID><Channel>Master</Channel>
              <DesiredVolume>\(volume)</DesiredVolume>
            </u:SetVolume>
          </s:Body>
        </s:Envelope>
        """
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("text/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.setValue("\"urn:schemas-upnp-org:service:RenderingControl:1#SetVolume\"", forHTTPHeaderField: "SOAPACTION")
        req.httpBody = body.data(using: .utf8)
        req.timeoutInterval = 3
        try? await URLSession.shared.data(for: req)
    }

    // MARK: - RTSP Helpers

    private func rtspOK(cseq: String, extra: String = "") -> String {
        "RTSP/1.0 200 OK\r\nCSeq: \(cseq)\r\n\(extra)\r\n"
    }
    private func rtspError(_ code: Int) -> String {
        "RTSP/1.0 \(code) Error\r\nCSeq: 1\r\n\r\n"
    }

    private func log(_ level: LogEntry.Level, _ msg: String) {
        onLog?(LogEntry(level: level, message: msg))
    }
}

// MARK: - Sonos Audio Forwarder
// Empfängt RTP-Pakete auf UDP, dekodiert ALAC und streamt als HTTP an Sonos.

class SonosAudioForwarder {
    var onLog: ((LogEntry) -> Void)?

    private let speaker: SonosSpeaker
    private let rtpPort: UInt16
    private var udpListener: NWListener?
    private var sonosConnection: URLSessionDataTask?
    private var audioBuffer = Data()
    private var httpServer: LocalHTTPAudioServer?
    private var isPaused = false

    init(speaker: SonosSpeaker, rtpPort: UInt16) {
        self.speaker = speaker
        self.rtpPort = rtpPort
    }

    func start() {
        // 1. Lokalen HTTP-Server starten der Audio-Buffer an Sonos ausliefert
        let server = LocalHTTPAudioServer()
        self.httpServer = server
        server.start()

        // 2. Sonos anweisen, von unserem lokalen HTTP-Server zu streamen
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            self.tellSonosToPlay(serverPort: server.port)
        }

        // 3. RTP-Pakete empfangen
        listenForRTP()
    }

    func pause() {
        isPaused = true
        sendSoapCommand(action: "Pause",
                       service: "AVTransport",
                       body: "<InstanceID>0</InstanceID>")
    }

    func stop() {
        udpListener?.cancel()
        udpListener = nil
        httpServer?.stop()
        httpServer = nil
        sendSoapCommand(action: "Stop",
                       service: "AVTransport",
                       body: "<InstanceID>0</InstanceID>")
    }

    private func listenForRTP() {
        do {
            let params = NWParameters.udp
            params.allowLocalEndpointReuse = true
            let listener = try NWListener(using: params,
                                          on: NWEndpoint.Port(rawValue: rtpPort)!)
            self.udpListener = listener

            listener.newConnectionHandler = { [weak self] conn in
                self?.receiveRTPPackets(conn: conn)
            }
            listener.start(queue: .global(qos: .userInitiated))
        } catch {
            log(.error, "RTP-Listener Fehler: \(error)")
        }
    }

    private func receiveRTPPackets(conn: NWConnection) {
        conn.start(queue: .global(qos: .userInitiated))
        func receive() {
            conn.receiveMessage { [weak self] data, _, _, _ in
                guard let self, let data, !data.isEmpty else { return }
                // RTP-Header ist 12 Bytes (kann Extension haben)
                // Payload-Typ 96 = ALAC bei AirPlay
                if data.count > 12 {
                    let rtpHeader = data[0]
                    let hasExtension = (rtpHeader & 0x10) != 0
                    var offset = 12
                    if hasExtension && data.count > 16 {
                        let extLen = Int(data[14]) << 8 | Int(data[15])
                        offset += 4 + extLen * 4
                    }
                    if offset < data.count {
                        let audioPayload = Data(data[offset...])
                        self.httpServer?.appendAudio(audioPayload)
                    }
                }
                receive()
            }
        }
        receive()
    }

    private func tellSonosToPlay(serverPort: UInt16) {
        // Eigene lokale IP ermitteln
        guard let localIP = getLocalIP() else { return }
        let uri = "x-rincon-mp3radio://\(localIP):\(serverPort)/stream.pcm"

        let setBody = """
        <InstanceID>0</InstanceID>
        <CurrentURI>\(uri)</CurrentURI>
        <CurrentURIMetaData>&lt;DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/"
          xmlns:dc="http://purl.org/dc/elements/1.1/"
          xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/"&gt;
          &lt;item id="1" parentID="0" restricted="1"&gt;
            &lt;dc:title&gt;AirBridge&lt;/dc:title&gt;
            &lt;upnp:class&gt;object.item.audioItem.audioBroadcast&lt;/upnp:class&gt;
          &lt;/item&gt;
        &lt;/DIDL-Lite&gt;
        """
        sendSoapCommand(action: "SetAVTransportURI", service: "AVTransport", body: setBody)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.sendSoapCommand(action: "Play", service: "AVTransport",
                                 body: "<InstanceID>0</InstanceID><Speed>1</Speed>")
            self?.log(.success, "Sonos spielt von lokalem Stream")
        }
    }

    private func sendSoapCommand(action: String, service: String, body: String) {
        let path = service == "AVTransport"
            ? "/MediaRenderer/AVTransport/Control"
            : "/MediaRenderer/RenderingControl/Control"
        let serviceUrn = "urn:schemas-upnp-org:service:\(service):1"

        guard let url = URL(string: "http://\(speaker.ip):1400\(path)") else { return }
        let envelope = """
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
          <s:Body><u:\(action) xmlns:u="\(serviceUrn)">\(body)</u:\(action)></s:Body>
        </s:Envelope>
        """
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("text/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.setValue("\"\(serviceUrn)#\(action)\"", forHTTPHeaderField: "SOAPACTION")
        req.httpBody = envelope.data(using: .utf8)
        req.timeoutInterval = 5
        URLSession.shared.dataTask(with: req).resume()
    }

    private func getLocalIP() -> String? {
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
                let ip = String(cString: host)
                if !ip.hasPrefix("169.254") && ip != "127.0.0.1" { addr = ip }
            }
        }
        return addr
    }

    private func log(_ level: LogEntry.Level, _ msg: String) {
        onLog?(LogEntry(level: level, message: msg))
    }
}

// MARK: - Lokaler HTTP-Server
// Liefert den empfangenen Audiostream per HTTP an Sonos aus.
// Sonos erwartet einen kontinuierlichen HTTP-Stream (wie ein Internetradio).

class LocalHTTPAudioServer {
    private(set) var port: UInt16 = 0
    private var listener: NWListener?
    private var audioQueue = DispatchQueue(label: "audio.buffer")
    private var buffer = Data()
    private var activeConnections: [NWConnection] = []

    func start() {
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            // Port 0 = OS wählt freien Port
            let listener = try NWListener(using: params, on: 0)
            self.listener = listener

            listener.stateUpdateHandler = { [weak self] state in
                if case .ready = state, let port = self?.listener?.port?.rawValue {
                    self?.port = port
                }
            }

            listener.newConnectionHandler = { [weak self] conn in
                self?.handleHTTPConnection(conn)
            }
            listener.start(queue: .global(qos: .userInitiated))

            // Kurz warten bis Port zugewiesen
            Thread.sleep(forTimeInterval: 0.2)
            if let p = listener.port?.rawValue { port = p }
        } catch {}
    }

    func stop() {
        activeConnections.forEach { $0.cancel() }
        activeConnections.removeAll()
        listener?.cancel()
        listener = nil
    }

    func appendAudio(_ data: Data) {
        audioQueue.async { [weak self] in
            self?.buffer.append(data)
            // An alle aktiven Verbindungen senden
            self?.activeConnections.forEach { conn in
                conn.send(content: data, completion: .idempotent)
            }
        }
    }

    private func handleHTTPConnection(_ conn: NWConnection) {
        conn.start(queue: .global(qos: .userInitiated))

        // HTTP-Request lesen
        conn.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, _, _ in
            guard let self else { return }
            // HTTP-Response senden: Chunked-Stream Header
            let response = "HTTP/1.1 200 OK\r\n" +
                          "Content-Type: audio/L16;rate=44100;channels=2\r\n" +
                          "Transfer-Encoding: chunked\r\n" +
                          "Cache-Control: no-cache\r\n\r\n"
            conn.send(content: response.data(using: .utf8)!, completion: .idempotent)

            // Verbindung offen halten und Audio streamen
            self.audioQueue.async {
                self.activeConnections.append(conn)
                // Bereits gepufferte Daten senden
                if !self.buffer.isEmpty {
                    conn.send(content: self.buffer, completion: .idempotent)
                }
            }
        }
    }
}
