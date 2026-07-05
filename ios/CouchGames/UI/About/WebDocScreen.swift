import SwiftUI
import WebKit
import UIKit

/// A read-only in-app viewer for a hosted legal document (privacy / imprint).
/// Deliberately separate from `GameWebView`: no navigation allow-list and no JS
/// bridge — these are trusted first-party pages, loaded so the documents stay
/// reachable from within the app.
///
/// Each screen shows exactly one document. Tapping the page's cross-link to the
/// other doc opens it as its own pushed screen (`onOpenDoc`), so the standard
/// system Back button and swipe just work — no custom back handling.
struct WebDocScreen: View {
    let url: String
    let title: String
    let onOpenDoc: (String) -> Void

    @Environment(\.cgPalette) private var palette
    @State private var isLoading = true

    var body: some View {
        ZStack {
            // The screen chrome uses the same surface as home/About (and as the
            // hosted page itself), so nothing shows the stock WKWebView white.
            palette.background.ignoresSafeArea()
            WebDocView(url: url, surface: UIColor(palette.background), isLoading: $isLoading, onOpenDoc: onOpenDoc)
                .ignoresSafeArea(.container, edges: .bottom)
            if isLoading {
                ProgressView()
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct WebDocView: UIViewRepresentable {
    let url: String
    let surface: UIColor
    @Binding var isLoading: Bool
    let onOpenDoc: (String) -> Void

    // The page renders its own <h1> title (e.g. "DATENSCHUTZERKLÄRUNG"); in-app the
    // native nav bar already shows it, so hide the page copy to avoid the duplicate.
    // Injected at document-start so the heading never flashes before it's hidden.
    private static let hideHeadingJS = """
    (function () {
      if (document.getElementById('cg-hide-heading')) return;
      var s = document.createElement('style');
      s.id = 'cg-hide-heading';
      s.textContent = '.legal-shell > h1{display:none !important;}';
      (document.head || document.documentElement).appendChild(s);
    })();
    """

    func makeCoordinator() -> Coordinator {
        Coordinator(isLoading: $isLoading, onOpenDoc: onOpenDoc)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.addUserScript(
            WKUserScript(source: Self.hideHeadingJS, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        )

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        // Match the app surface while the page is blank — kills the white flash and
        // the slight #FFFFFF-vs-#FAFAFB seam against the page background.
        webView.isOpaque = false
        webView.backgroundColor = surface
        webView.scrollView.backgroundColor = surface
        if let requestURL = URL(string: url) {
            webView.load(URLRequest(url: requestURL))
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let isLoading: Binding<Bool>
        private let onOpenDoc: (String) -> Void

        init(isLoading: Binding<Bool>, onOpenDoc: @escaping (String) -> Void) {
            self.isLoading = isLoading
            self.onOpenDoc = onOpenDoc
        }

        // Dispatch async so we never mutate SwiftUI state during a view update.
        private func setLoading(_ value: Bool) {
            DispatchQueue.main.async { self.isLoading.wrappedValue = value }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let target = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            if CG.legalTitle(for: target) != nil {
                // A tap on the cross-link to the other legal doc opens it as its own
                // pushed screen, so the system Back button returns here. The initial
                // page load (navigationType .other) just loads in place.
                if navigationAction.navigationType == .linkActivated {
                    let destination = target.absoluteString
                    DispatchQueue.main.async { self.onOpenDoc(destination) }
                    decisionHandler(.cancel)
                } else {
                    decisionHandler(.allow)
                }
            } else {
                // External references (e.g. the linked data-protection authority), the
                // site's home link, and non-web schemes like mailto:/tel: (which
                // WKWebView can't render and would surface an error page for) are handed
                // to the system app (browser/mail/dialer).
                UIApplication.shared.open(target)
                decisionHandler(.cancel)
            }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            setLoading(true)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            setLoading(false)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            setLoading(false)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            setLoading(false)
        }
    }
}
