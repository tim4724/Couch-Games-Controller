import SwiftUI
import WebKit
import UIKit

/// The launcher-published safe zone, in points (CSS px == points on iOS).
struct SafeZone: Equatable {
    var top: Int = 0
    var left: Int = 0
    var right: Int = 0
    var bottom: Int = 0

    init(top: Int = 0, left: Int = 0, right: Int = 0, bottom: Int = 0) {
        self.top = top
        self.left = left
        self.right = right
        self.bottom = bottom
    }
}

/// WKWebView whose safeAreaInsets are synthetic, so viewport-fit=cover pages see
/// the launcher's safe zone (chrome height on top, cutout/gutter elsewhere) via
/// standard `env(safe-area-inset-*)` — contract §7.5 mechanism 1. The `--cg-safe-*`
/// CSS vars stay the authoritative channel.
final class CGWebView: WKWebView {
    var syntheticSafeAreaInsets: UIEdgeInsets = .zero {
        didSet {
            if oldValue != syntheticSafeAreaInsets { safeAreaInsetsDidChange() }
        }
    }

    override var safeAreaInsets: UIEdgeInsets { syntheticSafeAreaInsets }
}

/// Hosts a game's remote controller as a TOP-LEVEL web view (the game's
/// `frame-ancestors` CSP doesn't apply) with the navigation allow-list as the
/// client-side trust boundary — the join URL can originate from an untrusted
/// relay lookup.
struct GameWebView: UIViewRepresentable {
    let joinUrl: String
    let allowedDomains: [String]       // already lowercased, includes CG.launcherHost
    let playerName: String             // "" = blank → never injected
    let safeZone: SafeZone             // points == CSS px
    let onLoaded: () -> Void           // every didFinish
    let onGameEnd: (String?) -> Void   // fire-once enforced by Coordinator
    let onThemeChanged: (PageTheme) -> Void

    init(joinUrl: String, allowedDomains: [String], playerName: String, safeZone: SafeZone,
         onLoaded: @escaping () -> Void, onGameEnd: @escaping (String?) -> Void,
         onThemeChanged: @escaping (PageTheme) -> Void) {
        self.joinUrl = joinUrl
        self.allowedDomains = allowedDomains
        self.playerName = playerName
        self.safeZone = safeZone
        self.onLoaded = onLoaded
        self.onGameEnd = onGameEnd
        self.onThemeChanged = onThemeChanged
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> CGWebView {
        let coordinator = context.coordinator

        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []   // game sounds must autoplay
        config.websiteDataStore = .default()                   // localStorage parity
        // The bridge must exist before load or the page won't see it.
        config.userContentController.addUserScript(
            WKUserScript(source: GameHostJS.bridgeShim, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        )
        config.userContentController.add(coordinator, name: "cgHost")

        let webView = CGWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        // Match the dark chrome while the page is blank — kills the white flash.
        let surface = UIColor(red: 0x0F / 255.0, green: 0x0F / 255.0, blue: 0x11 / 255.0, alpha: 1.0)
        webView.backgroundColor = surface
        webView.scrollView.backgroundColor = surface
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.bounces = false
        webView.allowsBackForwardNavigationGestures = false
        // Never expose a player's live game socket to the Web Inspector in production.
        #if DEBUG
        webView.isInspectable = true
        #endif
        webView.navigationDelegate = coordinator
        webView.syntheticSafeAreaInsets = UIEdgeInsets(
            top: CGFloat(safeZone.top), left: CGFloat(safeZone.left),
            bottom: CGFloat(safeZone.bottom), right: CGFloat(safeZone.right)
        )
        coordinator.lastInjectedName = playerName
        coordinator.lastPushedZone = safeZone
        if let url = URL(string: joinUrl) {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateUIView(_ webView: CGWebView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self  // always-current closures

        if playerName != coordinator.lastInjectedName {
            coordinator.lastInjectedName = playerName
            // Live rename (contract §2) — blank names are never injected.
            if let js = GameHostJS.nameInjection(name: playerName) {
                webView.evaluateJavaScript(js, completionHandler: nil)
            }
        }

        if safeZone != coordinator.lastPushedZone {
            coordinator.lastPushedZone = safeZone
            // env() re-derives from the synthetic insets — the iOS analog of
            // requestApplyInsets; the vars remain the source of truth.
            webView.syntheticSafeAreaInsets = UIEdgeInsets(
                top: CGFloat(safeZone.top), left: CGFloat(safeZone.left),
                bottom: CGFloat(safeZone.bottom), right: CGFloat(safeZone.right)
            )
            webView.evaluateJavaScript(GameHostJS.safeZonePush(safeZone), completionHandler: nil)
        }
    }

    /// Tear the web view down so the game's WebSocket/audio fully stop the moment we pop.
    static func dismantleUIView(_ webView: CGWebView, coordinator: Coordinator) {
        coordinator.isTearingDown = true
        webView.stopLoading()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "cgHost")
        webView.configuration.userContentController.removeAllUserScripts()
        if let blank = URL(string: "about:blank") {
            webView.load(URLRequest(url: blank))
        }
    }

    @MainActor final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: GameWebView
        var isTearingDown = false
        var lastInjectedName = ""
        var lastPushedZone = SafeZone()
        private var gameEndFired = false  // fire-once: a game spamming gameEnded must not pop extra entries

        init(parent: GameWebView) {
            self.parent = parent
        }

        /// The trust boundary. Only https navigations to an allow-listed domain stay
        /// in-app; off-list http(s) links open in the system browser (silently doing
        /// nothing on failure), and any other scheme is refused outright. Governs
        /// frame navigations only — subresources and the relay WebSocket are unaffected.
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }
            if isTearingDown, url.absoluteString == "about:blank" {
                decisionHandler(.allow)
                return
            }
            let scheme = url.scheme?.lowercased()
            if scheme == "https", parent.allowedDomains.contains(where: { hostInDomain(url.host, $0) }) {
                decisionHandler(.allow)
                return
            }
            if scheme == "http" || scheme == "https" {
                // Off-list (plain http is never in-app, even on an allowed domain) → browser.
                decisionHandler(.cancel)
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
                return
            }
            // javascript:, file:, custom schemes, … — blocked entirely.
            decisionHandler(.cancel)
        }

        /// Every page finish: loading done, then re-assert the name
        /// (belt-and-suspenders with cgName), re-install the theme observer
        /// (idempotent), re-push the safe zone.
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.onLoaded()
            if let js = GameHostJS.nameInjection(name: parent.playerName) {
                webView.evaluateJavaScript(js, completionHandler: nil)
            }
            webView.evaluateJavaScript(GameHostJS.watchPageTheme, completionHandler: nil)
            webView.evaluateJavaScript(GameHostJS.safeZonePush(parent.safeZone), completionHandler: nil)
        }

        /// The game→launcher half of the contract (v1). All arguments are untrusted page input.
        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard message.name == "cgHost",
                  let body = message.body as? [String: Any],
                  let type = body["type"] as? String
            else { return }
            switch type {
            case "gameEnded":
                guard !gameEndFired else { return }
                gameEndFired = true
                parent.onGameEnd(body["value"] as? String)  // null tolerated → generic message
            case "themeChanged":
                // Not fire-once: themes change repeatedly. Parsed strictly.
                parent.onThemeChanged(parsePageTheme(body["value"] as? String))
            default:
                break
            }
        }
    }
}
