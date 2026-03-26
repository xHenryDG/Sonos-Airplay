import Foundation
import Network

// Triggers the iOS "Allow local network access?" dialog.
// Uses the technique from Nonstrict (2024): NWBrowser + NWListener on a
// dedicated _preflight_check._tcp Bonjour type.
// Info.plist must contain _preflight_check._tcp in NSBonjourServices.

@MainActor
class LocalNetworkPermission: ObservableObject {
    enum State { case unknown, requesting, granted, denied }

    @Published var state: State = .unknown

    private let bonjourType = "_preflight_check._tcp"
    private var listener: NWListener?
    private var browser: NWBrowser?
    private let queue = DispatchQueue(label: "com.sonosairbridge.permission")

    func request() async {
        guard state == .unknown else { return }
        state = .requesting

        let granted = await withCheckedContinuation { continuation in
            var resumed = false
            func finish(_ result: Bool) {
                guard !resumed else { return }
                resumed = true
                listener?.cancel(); listener = nil
                browser?.cancel();  browser  = nil
                continuation.resume(returning: result)
            }

            // Listener
            guard let lsnr = try? NWListener(
                using: NWParameters(tls: .none, tcp: NWProtocolTCP.Options())
            ) else { finish(false); return }
            lsnr.service = NWListener.Service(name: UUID().uuidString, type: bonjourType)
            lsnr.newConnectionHandler = { _ in }
            lsnr.stateUpdateHandler = { s in
                if case .failed = s { finish(false) }
                if case .waiting = s { finish(false) } // denied = policy error here
            }
            lsnr.start(queue: queue)
            listener = lsnr

            // Browser - finding the listener proves permission is granted
            let params = NWParameters()
            params.includePeerToPeer = true
            let brwsr = NWBrowser(for: .bonjour(type: bonjourType, domain: nil), using: params)
            brwsr.stateUpdateHandler = { s in
                if case .waiting(let err) = s {
                    // kDNSServiceErr_PolicyDenied (-65570) means denied
                    let denied = (err as NSError).code == -65570
                    finish(!denied)
                }
                if case .failed = s { finish(false) }
            }
            brwsr.browseResultsChangedHandler = { results, _ in
                if !results.isEmpty { finish(true) }
            }
            brwsr.start(queue: queue)
            browser = brwsr

            // Timeout after 10 s – assume denied if no answer
            queue.asyncAfter(deadline: .now() + 10) { finish(false) }
        }

        state = granted ? .granted : .denied
    }
}
