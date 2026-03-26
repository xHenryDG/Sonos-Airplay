import Foundation
import Network

/// Triggert den iOS Local-Network-Dialog korrekt.
/// Strategie: NWListener + NWBrowser auf _preflight_check._tcp.
/// Sobald der Browser .ready erreicht (= DNS läuft = Erlaubnis erteilt)
/// ODER ein Ergebnis findet, gilt Permission als granted.
/// PolicyDenied-Error = verweigert.

@MainActor
class NetworkPermissionManager: ObservableObject {
    @Published var state: PermissionState = .unknown

    enum PermissionState {
        case unknown, requesting, granted, denied
    }

    private let serviceType = "_preflight_check._tcp"
    private var listener:  NWListener?
    private var browser:   NWBrowser?

    func request() async {
        guard state == .unknown || state == .denied else { return }
        state = .requesting

        do {
            let granted = try await requestAuthorization()
            state = granted ? .granted : .denied
        } catch {
            // Bei echtem Netzwerkfehler nochmal als unknown markieren
            // damit beim nächsten Foreground-Wechsel ein Retry passiert
            state = .unknown
        }
    }

    func reset() {
        listener?.cancel(); listener = nil
        browser?.cancel();  browser  = nil
        state = .unknown
    }

    // MARK: - Core

    private func requestAuthorization() async throws -> Bool {
        let queue = DispatchQueue(label: "net.sonosairbridge.preflight")

        let listener = try NWListener(
            using: NWParameters(tls: .none, tcp: NWProtocolTCP.Options())
        )
        listener.service = NWListener.Service(
            name: UUID().uuidString,
            type: serviceType
        )
        listener.newConnectionHandler = { _ in }
        self.listener = listener

        let params = NWParameters()
        params.includePeerToPeer = true
        let browser = NWBrowser(
            for: .bonjour(type: serviceType, domain: nil),
            using: params
        )
        self.browser = browser

        return try await withCheckedThrowingContinuation { continuation in
            var resumed = false

            func finish(_ result: Result<Bool, Error>) {
                guard !resumed else { return }
                resumed = true
                listener.stateUpdateHandler          = { _ in }
                browser.stateUpdateHandler           = { _ in }
                browser.browseResultsChangedHandler  = { _, _ in }
                listener.cancel()
                browser.cancel()
                continuation.resume(with: result)
            }

            listener.stateUpdateHandler = { state in
                switch state {
                case .failed(let e):  finish(.failure(e))
                case .waiting(let e): finish(.failure(e))
                default: break
                }
            }
            listener.start(queue: queue)

            browser.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    // .ready bedeutet: DNS läuft → Erlaubnis erteilt ✓
                    finish(.success(true))
                case .failed(let e):
                    finish(.failure(e))
                case .waiting(let e):
                    if case .dns(let code) = e, code == -65570 {
                        // kDNSServiceErr_PolicyDenied
                        finish(.success(false))
                    } else {
                        finish(.failure(e))
                    }
                default: break
                }
            }

            browser.browseResultsChangedHandler = { results, _ in
                // Zusätzlicher Trigger: Ergebnis gefunden → sicher granted
                if !results.isEmpty { finish(.success(true)) }
            }

            browser.start(queue: queue)
        }
    }
}
