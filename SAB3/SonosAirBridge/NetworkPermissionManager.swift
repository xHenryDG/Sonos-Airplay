import Foundation
import Network

// Triggert den iOS-Netzwerk-Erlaubnisdialog korrekt.
// Benötigt _preflight_check._tcp in Info.plist > NSBonjourServices.
// Gibt true zurück wenn Erlaubnis erteilt, false wenn verweigert.

@MainActor
class NetworkPermissionManager: ObservableObject {
    @Published var state: PermissionState = .unknown

    enum PermissionState {
        case unknown, requesting, granted, denied
    }

    private let serviceType = "_preflight_check._tcp"
    private var listener:  NWListener?
    private var browser:   NWBrowser?
    private var continuation: CheckedContinuation<Bool, Error>?

    func request() async {
        guard state == .unknown else { return }
        state = .requesting

        do {
            let granted = try await requestAuthorization()
            state = granted ? .granted : .denied
        } catch {
            state = .denied
        }
    }

    private func requestAuthorization() async throws -> Bool {
        let queue = DispatchQueue(label: "net.sonosairbridge.preflight")

        // Listener
        let listener = try NWListener(
            using: NWParameters(tls: .none, tcp: NWProtocolTCP.Options())
        )
        listener.service = NWListener.Service(name: UUID().uuidString, type: serviceType)
        listener.newConnectionHandler = { _ in }
        self.listener = listener

        // Browser
        let params = NWParameters()
        params.includePeerToPeer = true
        let browser = NWBrowser(for: .bonjour(type: serviceType, domain: nil), using: params)
        self.browser = browser

        return try await withCheckedThrowingContinuation { continuation in
            var resumed = false
            func finish(_ result: Result<Bool, Error>) {
                guard !resumed else { return }
                resumed = true
                listener.stateUpdateHandler = { _ in }
                browser.stateUpdateHandler  = { _ in }
                browser.browseResultsChangedHandler = { _, _ in }
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
                case .failed(let e): finish(.failure(e))
                case .waiting(let e):
                    // kDNSServiceErr_PolicyDenied = Erlaubnis verweigert
                    if case .dns(let code) = e, code == -65570 {
                        finish(.success(false))
                    } else {
                        finish(.failure(e))
                    }
                default: break
                }
            }
            browser.browseResultsChangedHandler = { results, _ in
                // Wenn wir den eigenen Listener finden, haben wir Erlaubnis
                if !results.isEmpty { finish(.success(true)) }
            }
            browser.start(queue: queue)
        }
    }
}
