import SwiftUI
import Observation
import UIKit

// MARK: - Routes

struct GameHostParams: Hashable {
    let joinUrl: String
    let title: String
    let allowedHosts: [String]

    init(joinUrl: String, title: String, allowedHosts: [String]) {
        self.joinUrl = joinUrl
        self.title = title
        self.allowedHosts = allowedHosts
    }
}

struct WebDocParams: Hashable {
    let url: String
    let title: String
}

enum Route: Hashable {
    case gameHost(GameHostParams)
    case about
    case webDoc(WebDocParams)
}

// MARK: - Router

@MainActor @Observable final class AppRouter {

    var path: [Route] = []
    var pendingDeepLink: String? = nil
    let messages = MessageCenter()

    init() {}

    func handleIncomingURL(_ url: URL) {
        // Deep link always lands on Main; MainScreen owns the resolve + name gate.
        path.removeAll()
        pendingDeepLink = normalizeDeepLink(url)
    }

    func consumeDeepLink() {
        pendingDeepLink = nil
    }

    func push(_ route: Route) {
        path.append(route)
    }

    func pop() {
        if !path.isEmpty { path.removeLast() }
    }

    func gameEnded(reason: String?) {
        // The player didn't choose to leave — silence would read as a crash.
        pop()
        messages.showSnackbar(gameEndMessage(reason))
    }
}

// MARK: - Transient messages

struct ToastItem: Identifiable, Equatable {
    let id: UUID
    let text: String
    let long: Bool
}

struct SnackbarItem: Identifiable, Equatable {
    let id: UUID
    let text: String
}

@MainActor @Observable final class MessageCenter {

    var toast: ToastItem? = nil
    var snackbar: SnackbarItem? = nil

    @ObservationIgnored private var toastTask: Task<Void, Never>? = nil
    @ObservationIgnored private var snackbarTask: Task<Void, Never>? = nil

    init() {}

    func showToast(_ text: String, long: Bool = false) {
        toastTask?.cancel()
        let item = ToastItem(id: UUID(), text: text, long: long)
        toast = item
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(long ? 3.5 : 2.0))
            guard !Task.isCancelled, let self, self.toast?.id == item.id else { return }
            self.toast = nil
        }
    }

    func showSnackbar(_ text: String) {
        snackbarTask?.cancel()
        let item = SnackbarItem(id: UUID(), text: text)
        snackbar = item
        snackbarTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4.0))
            guard !Task.isCancelled, let self, self.snackbar?.id == item.id else { return }
            self.snackbar = nil
        }
    }
}

// MARK: - Root view

struct RootView: View {

    @Bindable private var router: AppRouter

    init(router: AppRouter) {
        self.router = router
    }

    var body: some View {
        ZStack {
            NavigationStack(path: $router.path) {
                MainScreen(
                    deepLink: router.pendingDeepLink,
                    isTopVisible: router.path.isEmpty,
                    onDeepLinkConsumed: { router.consumeDeepLink() },
                    onJoin: { url, title, hosts in
                        router.push(.gameHost(GameHostParams(joinUrl: url, title: title, allowedHosts: hosts)))
                    },
                    onOpenAbout: { router.push(.about) }
                )
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .gameHost(let params):
                        GameHostScreen(
                            joinUrl: params.joinUrl,
                            title: params.title,
                            allowedHosts: params.allowedHosts,
                            onLeave: { router.pop() },
                            onGameEnd: { router.gameEnded(reason: $0) }
                        )
                        .navigationBarBackButtonHidden(true)
                        .toolbar(.hidden, for: .navigationBar)
                    case .about:
                        AboutScreen(
                            onOpenPrivacy: { router.push(.webDoc(WebDocParams(url: CG.privacyURL, title: String(localized: "Privacy Policy")))) },
                            onOpenImprint: { router.push(.webDoc(WebDocParams(url: CG.imprintURL, title: String(localized: "Impressum")))) }
                        )
                    case .webDoc(let params):
                        WebDocScreen(url: params.url, title: params.title)
                    }
                }
            }
            // Above the NavigationStack so the game-end snackbar survives the pop.
            MessageOverlay()
        }
        .cgThemed()
        .environment(router.messages)
        // Keep-awake and status-bar style follow the ROUTE, not view lifecycle:
        // onAppear/onDisappear don't fire reliably across NavigationStack
        // push/pop. (Indicator/edge-gesture chrome is view-scoped SwiftUI on
        // GameHostScreen and needs no reset.)
        .onChange(of: router.path, initial: true) { _, path in
            let inGame = path.contains { if case .gameHost = $0 { return true } else { return false } }
            UIApplication.shared.isIdleTimerDisabled = inGame
            if !inGame {
                ChromeState.shared.reset()
            }
        }
    }
}

// MARK: - Message overlay

struct MessageOverlay: View {

    @Environment(MessageCenter.self) private var messages
    @Environment(\.cgPalette) private var palette

    init() {}

    var body: some View {
        VStack(spacing: 8) {
            if let snackbar = messages.snackbar {
                Text(snackbar.text)
                    .font(.cgBodyMedium)
                    .foregroundStyle(palette.inverseOnSurface)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(palette.inverseSurface))
                    .padding(.horizontal, 16)
                    .transition(.opacity)
            }
            if let toast = messages.toast {
                Text(toast.text)
                    .font(.cgBodyMedium)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color(white: 0.15, opacity: 0.92)))
                    .padding(.horizontal, 32)
                    .transition(.opacity)
            }
        }
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.2), value: messages.toast)
        .animation(.easeInOut(duration: 0.2), value: messages.snackbar)
    }
}
