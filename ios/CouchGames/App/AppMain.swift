import UIKit
import SwiftUI
import AVFAudio

// MARK: - App delegate

@main final class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // .playback so WebView game sound is audible even with the silent switch on;
        // .mixWithOthers so it layers over the user's music/podcasts instead of stopping
        // them (the trailer is muted, so it stays silent regardless).
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
        return true
    }
}

// MARK: - Scene delegate

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?
    let router = AppRouter()

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let window = UIWindow(windowScene: windowScene)
        let root = RootHostingController(rootView: RootView(router: router))
        ChromeState.shared.host = root
        // First frames before SwiftUI paints must already be the surface color
        // in the correct light/dark variant (no white flash in dark mode).
        window.backgroundColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0x0F / 255.0, green: 0x0F / 255.0, blue: 0x11 / 255.0, alpha: 1)
                : UIColor(red: 0xFA / 255.0, green: 0xFA / 255.0, blue: 0xFB / 255.0, alpha: 1)
        }
        window.rootViewController = root
        self.window = window
        window.makeKeyAndVisible()

        // Cold-start deep link: connectionOptions only exist at scene connect,
        // so "consumed once, never replayed" holds by construction.
        if let url = connectionOptions.urlContexts.first?.url {
            router.handleIncomingURL(url)
        } else if let url = connectionOptions.userActivities
            .first(where: { $0.activityType == NSUserActivityTypeBrowsingWeb })?.webpageURL {
            router.handleIncomingURL(url)
        }
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        // Custom scheme (couchgames://) while running.
        guard let url = URLContexts.first?.url else { return }
        router.handleIncomingURL(url)
    }

    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        // Universal Links while running.
        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
              let url = userActivity.webpageURL else { return }
        router.handleIncomingURL(url)
    }
}

// MARK: - Root hosting controller

final class RootHostingController: UIHostingController<RootView> {

    override var preferredStatusBarStyle: UIStatusBarStyle {
        ChromeState.shared.statusBarStyle ?? .default
    }
}

// MARK: - Chrome state

/// Status-bar style override for the game host (its chrome can be game-colored).
/// Home indicator and edge-gesture deferral are NOT here — those use SwiftUI's
/// view-scoped persistentSystemOverlays/defersSystemGestures on GameHostScreen,
/// which cannot leak past that view's lifetime.
@MainActor final class ChromeState {

    static let shared = ChromeState()

    weak var host: RootHostingController?

    var statusBarStyle: UIStatusBarStyle? {
        didSet { host?.setNeedsStatusBarAppearanceUpdate() }
    }

    func reset() {
        statusBarStyle = nil
    }

    private init() {}
}

// MARK: - Deep-link normalization

/// couchgames://host/path?q#f → "https://host/path?q#f" (scheme swap); any other URL → absoluteString.
func normalizeDeepLink(_ url: URL) -> String {
    guard url.scheme?.lowercased() == "couchgames",
          var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
        return url.absoluteString
    }
    components.scheme = "https"
    return components.url?.absoluteString ?? url.absoluteString
}
