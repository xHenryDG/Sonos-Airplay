import Foundation
import Network

/// Triggert den iOS Local-Network-Dialog zuverlässig per UDP-Broadcast.
/// Das ist die einfachste und zuverlässigste Methode — iOS zeigt den
/// Dialog sofort beim ersten Senden auf die Broadcast-Adresse.

@MainActor
class NetworkPermissionManager: ObservableObject {
    @Published var state: PermissionState = .unknown

    enum PermissionState {
        case unknown, requesting, granted, denied
    }

    private var connection: NWConnection?

    func request() async {
        guard state == .unknown || state == .denied else { return }
        state = .requesting

        // UDP-Paket an lokale Broadcast-Adresse senden —
        // das triggert den iOS-Dialog sofort und zuverlässig
        let host = NWEndpoint.Host("255.255.255.255")
        let port = NWEndpoint.Port(rawValue: 9)! // Discard-Port

        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true
        let conn = NWConnection(host: host, port: port, using: params)
        self.connection = conn

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            var resumed = false
            func finish() {
                guard !resumed else { return }
                resumed = true
                continuation.resume()
            }

            conn.stateUpdateHandler = { [weak self] newState in
                guard let self else { finish(); return }
                switch newState {
                case .ready:
                    // Sende ein leeres Paket — das triggert den iOS-Dialog
                    conn.send(content: Data([0x00]), completion: .contentProcessed { _ in
                        Task { @MainActor in
                            self.state = .granted
                            conn.cancel()
                            finish()
                        }
                    })
                case .failed(_), .cancelled:
                    Task { @MainActor in
                        // Wenn fehlgeschlagen = wahrscheinlich verweigert
                        // State nur ändern wenn noch nicht granted
                        if self.state == .requesting {
                            self.state = .denied
                        }
                        finish()
                    }
                case .waiting(let error):
                    if case .posix(let code) = error, code == .EPERM {
                        Task { @MainActor in
                            self.state = .denied
                            conn.cancel()
                            finish()
                        }
                    }
                default:
                    break
                }
            }
            conn.start(queue: .global())

            // Timeout nach 3 Sekunden — falls iOS keinen Dialog zeigt
            // (kann passieren wenn Permission schon gesetzt ist)
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                if !resumed {
                    Task { @MainActor [weak self] in
                        guard let self else { finish(); return }
                        if self.state == .requesting {
                            // Kein Fehler = wahrscheinlich granted (Dialog wurde
                            // schon früher beantwortet)
                            self.state = .granted
                        }
                        conn.cancel()
                        finish()
                    }
                }
            }
        }
    }

    func reset() {
        connection?.cancel()
        connection = nil
        state = .unknown
    }
}
