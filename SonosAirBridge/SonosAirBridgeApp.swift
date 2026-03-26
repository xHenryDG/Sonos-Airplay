import SwiftUI
import AVFoundation

@main
struct SonosAirBridgeApp: App {
    init() {
        setupBackgroundAudio()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }

    // AVAudioSession mit .playback aktivieren damit iOS die App im Hintergrund nicht beendet
    private func setupBackgroundAudio() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            print("AVAudioSession Fehler: \(error)")
        }
    }
}
