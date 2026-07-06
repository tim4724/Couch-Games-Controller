import SwiftUI
import WebKit
import UIKit

/// The launcher-published safe zone, in points (CSS px == points on iOS).
struct SafeZone: Equatable {
    var top: Int = 0
    var left: Int = 0
    var right: Int = 0
    var bottom: Int = 0
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
    let onGameEnd: (String?) -> Void   // fire-once
    @Binding var failed: Bool          // main-doc load failed — drives the retry overlay
    let reloadToken: Int               // bumped by Retry → re-issue the join request
    let onThemeChanged: (PageTheme) -> Void
    let onTitleChanged: (String) -> Void  // the page's <title>, trimmed & non-empty

    init(joinUrl: String, allowedDomains: [String], playerName: String, safeZone: SafeZone,
         onLoaded: @escaping () -> Void, onGameEnd: @escaping (String?) -> Void,
         failed: Binding<Bool>, reloadToken: Int,
         onThemeChanged: @escaping (PageTheme) -> Void,
         onTitleChanged: @escaping (String) -> Void) {
        self.joinUrl = joinUrl
        self.allowedDomains = allowedDomains
        self.playerName = playerName
        self.safeZone = safeZone
        self.onLoaded = onLoaded
        self.onGameEnd = onGameEnd
        self._failed = failed
        self.reloadToken = reloadToken
        self.onThemeChanged = onThemeChanged
        self.onTitleChanged = onTitleChanged
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

        // A Retry tap bumps reloadToken → re-issue the original join request (reload()
        // is a no-op when the failed navigation never committed, e.g. offline at join).
        if reloadToken != coordinator.lastReloadToken {
            coordinator.lastReloadToken = reloadToken
            if let url = URL(string: joinUrl) {
                webView.load(URLRequest(url: url))
            }
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
        var lastReloadToken = 0
        // Fire-once for the game-reported end — a game spamming gameEnded must pop
        // home only once. (A load failure is NOT terminal: it flips `failed` for the
        // retry overlay, so it doesn't gate on this.)
        private var didEnd = false
        private var faviconCaptured = false  // once per session — didFinish fires on every navigation

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
            #if DEBUG
            // Debug only: keep http(s) navigations to a LAN dev host in-app (see isPrivateHost).
            if (scheme == "http" || scheme == "https"), isPrivateHost(url.host) {
                decisionHandler(.allow)
                return
            }
            #endif
            if scheme == "http" || scheme == "https" {
                // Off-list (plain http is never in-app, even on an allowed domain) → browser.
                decisionHandler(.cancel)
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
                return
            }
            // javascript:, file:, custom schemes, … — blocked entirely.
            decisionHandler(.cancel)
        }

        /// The main document failed to load at the network level — no connection, host
        /// unreachable, DNS/TLS/timeout. (An HTTP 4xx/5xx is a *successful* navigation
        /// to WebKit and shows the server's body, so it never lands here.) Provisional =
        /// the initial connection never committed (the offline-at-join case); the plain
        /// didFail = a committed load dropped. Both bail home with a message rather than
        /// leave a dead spinner up.
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                     withError error: Error) {
            reportLoadFailure(error)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            reportLoadFailure(error)
        }

        private func reportLoadFailure(_ error: Error) {
            // Ignore our own teardown and a game already ended. Off-list navigations we
            // cancel in decidePolicyFor also land here — as NSURLErrorCancelled or
            // WebKit's frame-load-interrupted (102) — and are deliberate, not failures.
            guard !isTearingDown, !didEnd else { return }
            let ns = error as NSError
            if ns.domain == NSURLErrorDomain, ns.code == NSURLErrorCancelled { return }
            if ns.domain == "WebKitErrorDomain", ns.code == 102 { return }
            // Not terminal — surface the in-place retry overlay; Retry re-issues the load.
            DispatchQueue.main.async { self.parent.failed = true }
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
            captureFavicon(webView)
            // The page's own name (ground truth over the manifest): drives the Leave
            // bar and feeds the home rejoin card, so games not in the bundled manifest
            // still show a real name instead of the generic fallback. putTitle returns
            // the sanitized text so the bar shows exactly what the card stores.
            if let raw = webView.title, let clean = RecentRoomStore.putTitle(raw) {
                parent.onTitleChanged(clean)
            }
        }

        /// Read the page's declared icon URL (WKWebView has no favicon API), fetch it
        /// off-main into the current room's slot, so the home rejoin card can show the
        /// game's own icon instead of a generic play glyph. Once per session; a miss
        /// (no icon, non-https, off allow-list, bad response) silently leaves the glyph
        /// in place. The href is untrusted page input, so its host is pinned to the same
        /// navigation allow-list — otherwise a page could aim the fetch at an arbitrary
        /// host and leak the user's IP there.
        private func captureFavicon(_ webView: WKWebView) {
            guard !faviconCaptured else { return }
            faviconCaptured = true
            let allowedDomains = parent.allowedDomains
            webView.evaluateJavaScript(GameHostJS.faviconHref) { result, _ in
                guard let href = result as? String, let url = URL(string: href), url.scheme == "https",
                      allowedDomains.contains(where: { hostInDomain(url.host, $0) }) else { return }
                Task.detached(priority: .utility) {
                    guard let (data, response) = try? await URLSession.shared.data(from: url),
                          (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? false,
                          data.count <= 512 * 1024,
                          let image = UIImage(data: data) else { return }
                    RecentRoomStore.putFavicon(image)
                }
            }
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
                guard !didEnd else { return }
                didEnd = true
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
