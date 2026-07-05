import SwiftUI
import WebKit
import UIKit

/// A read-only in-app viewer for a hosted legal document (privacy / imprint).
/// Deliberately separate from `GameWebView`: no navigation allow-list and no JS
/// bridge — these are trusted first-party pages, loaded so the documents stay
/// reachable from within the app.
struct WebDocScreen: View {
    let url: String
    let title: String

    @Environment(\.cgPalette) private var palette
    @State private var isLoading = true

    var body: some View {
        ZStack {
            // The screen chrome uses the same surface as home/About (and as the
            // hosted page itself), so nothing shows the stock WKWebView white.
            palette.background.ignoresSafeArea()
            WebDocView(url: url, surface: UIColor(palette.background), isLoading: $isLoading)
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
        Coordinator(isLoading: $isLoading)
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

        init(isLoading: Binding<Bool>) {
            self.isLoading = isLoading
        }

        // Dispatch async so we never mutate SwiftUI state during a view update.
        private func setLoading(_ value: Bool) {
            DispatchQueue.main.async { self.isLoading.wrappedValue = value }
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
