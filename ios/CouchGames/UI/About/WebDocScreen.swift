import SwiftUI
import WebKit

/// A read-only in-app viewer for a hosted legal document (privacy / imprint).
/// Deliberately separate from `GameWebView`: no navigation allow-list and no JS
/// bridge — these are trusted first-party pages, loaded so the documents stay
/// reachable from within the app.
struct WebDocScreen: View {
    let url: String
    let title: String

    @State private var isLoading = true

    var body: some View {
        ZStack {
            WebDocView(url: url, isLoading: $isLoading)
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
    @Binding var isLoading: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(isLoading: $isLoading)
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        webView.navigationDelegate = context.coordinator
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
