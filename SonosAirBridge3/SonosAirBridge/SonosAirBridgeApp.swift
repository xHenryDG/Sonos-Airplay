import SwiftUI
import AVFoundation

@main
struct SonosAirBridgeApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup {
            MainTabView()
        }
    }
}

/// Keeps the process alive in background via a silent AVAudioSession.
/// This is the same technique AirPlay receiver apps use.
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        activateBackgroundAudio()
        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        activateBackgroundAudio()
    }

    private func activateBackgroundAudio() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            print("AVAudioSession error: \(error)")
        }
    }
}
