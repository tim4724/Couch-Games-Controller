import SwiftUI

// MARK: - MainScreen (home / launcher)

struct MainScreen: View {
    let deepLink: String?
    /// True while this screen is the visible top of the stack. Drives the rejoin
    /// poll: onAppear does NOT re-fire on NavigationStack pop-back, and scenePhase
    /// proved unreliable as a task trigger here (stuck .inactive at launch), so the
    /// router's path emptiness is the signal — mirroring Android's STARTED gating.
    let isTopVisible: Bool
    let onDeepLinkConsumed: () -> Void
    let onJoin: (String, String, [String]) -> Void   // (joinUrl, title, allowedHosts)

    init(deepLink: String?, isTopVisible: Bool, onDeepLinkConsumed: @escaping () -> Void,
         onJoin: @escaping (String, String, [String]) -> Void) {
        self.deepLink = deepLink
        self.isTopVisible = isTopVisible
        self.onDeepLinkConsumed = onDeepLinkConsumed
        self.onJoin = onJoin
    }

    // MARK: State

    @State private var games: [Game] = GamesManifest.load()
    @State private var profile: Profile = ProfileStore.load()
    // Item-based presentation: values are snapshotted into the request at
    // present time. @State read inside a sheet/cover content closure is not
    // dependency-tracked and can be stale (verified on-device), so the sheets
    // must receive their inputs through the item.
    @State private var profileRequest: ProfileSheetRequest? = nil
    @State private var afterName: AfterName? = nil
    @State private var showCodeEntry = false
    @State private var codeText = ""
    @State private var codeLoading = false
    @State private var codeError: String? = nil
    @State private var scanRequest: ScanRequest? = nil
    @State private var rejoin: RejoinTarget? = nil
    @State private var infoGame: Game? = nil
    @State private var joinCardHeight: CGFloat = 0
    // Haptic triggers (any change fires the paired sensoryFeedback).
    @State private var successTick = 0
    @State private var errorTick = 0

    @Environment(MessageCenter.self) private var messages
    @Environment(\.cgPalette) private var palette

    // MARK: Body

    var body: some View {
        ZStack(alignment: .bottom) {
            palette.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    if let rejoin {
                        RejoinCard(target: rejoin) {
                            resolveAndJoin(rejoin.room.joinUrl)
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    }

                    VStack(spacing: 12) {
                        ForEach(games) { game in
                            GameCard(game: game) { infoGame = game }
                        }
                    }

                    Color.clear
                        .frame(height: joinCardHeight + 12)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }

            JoinCard(
                host: joinHost,
                onScan: { requireName(.scan) },
                onEnterCode: { requireName(.enterCode) }
            )
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { height in
                joinCardHeight = height
            }
            .padding(.horizontal, 12)
            // The safe area already clears the home indicator — anything more
            // reads as a floating gap.
            .padding(.bottom, 4)

            if codeLoading {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Joining…")
                        .font(.cgLabelLarge)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(.regularMaterial, in: Capsule())
                .padding(.bottom, joinCardHeight + 28)
                .transition(.opacity)
            }
        }
        .navigationTitle("Couch Games")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            // Exactly ONE glass capsule: the toolbar wraps items in its own glass
            // container, so the item's shared background is hidden and the glass
            // button style is the sole container. Regular glass, not prominent —
            // the chip is not the screen's primary action. Label is .primary
            // (scheme-adaptive), never the mono tint, which would pin the color
            // and defeat the glass legibility adaptation over dark poster art.
            if #available(iOS 26.0, *) {
                ToolbarItem(placement: .topBarTrailing) {
                    chipButton(labelColor: nil)
                        .buttonStyle(.glass)
                }
                .sharedBackgroundVisibility(.hidden)
            } else {
                // Pre-26 bars always have a legible material background.
                ToolbarItem(placement: .topBarTrailing) {
                    chipButton(labelColor: nil)
                }
            }
        }
        .sensoryFeedback(.success, trigger: successTick)
        .sensoryFeedback(.error, trigger: errorTick)
        .ignoresSafeArea(.keyboard)
        .onChange(of: deepLink, initial: true) { _, newValue in
            guard let link = newValue else { return }
            resolveAndJoin(link)
            onDeepLinkConsumed()
        }
        .onChange(of: codeText) { _, newValue in
            if newValue.count > 16 {
                codeText = String(newValue.prefix(16))
            }
        }
        .task(id: isTopVisible) {
            guard isTopVisible else { return }
            await runRejoinPoll()
        }
        .alert("Enter room code", isPresented: $showCodeEntry) {
            TextField("e.g. A3KX9p", text: $codeText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Cancel", role: .cancel) { codeError = nil }
            Button("Join") { submitCode(codeText) }
                .disabled(codeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            if let codeError {
                Text(codeError)
            } else {
                Text("The code is on your TV.")
            }
        }
        .fullScreenCover(item: $scanRequest) { request in
            QRScannerScreen { result in
                scanRequest = nil
                switch result {
                case .code(let raw):
                    let outcome = JoinResolver.resolve(raw, games: request.games)
                    switch outcome {
                    case .success:
                        launchJoin(outcome, request.profile)
                    case .failure(let message):
                        errorTick += 1
                        messages.showToast(message)
                    }
                case .failure(let message):
                    errorTick += 1
                    messages.showToast("Scanner unavailable: \(message)", long: true)
                case .cancelled:
                    break
                }
            }
        }
        .appSheet(item: $profileRequest, onDismiss: { afterName = nil }) { request in
            ProfileSheet(
                initial: request.profile,
                title: request.gated ? "Enter your name" : "Your player",
                cta: request.gated ? "Save & continue" : "Save",
                onSave: { p in
                    ProfileStore.save(p)
                    profile = p
                    // Clear the pending action BEFORE dismissal so onDismiss
                    // doesn't cancel the just-run action.
                    let pending = afterName
                    afterName = nil
                    profileRequest = nil
                    if let pending {
                        perform(pending, p)
                    }
                }
            )
        }
        .appSheet(item: $infoGame) { game in
            GameInfoSheet(game: game)
        }
    }

    // MARK: Derived

    private var joinHost: String {
        games.first(where: { $0.isLive })?.displayHost ?? CG.launcherHost
    }

    private var profileDisplayName: String {
        let trimmed = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Set name" : trimmed
    }

    private func chipButton(labelColor: Color?) -> some View {
        Button {
            profileRequest = ProfileSheetRequest(gated: false, profile: profile)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "person.crop.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                Text(profileDisplayName)
                    .font(.cgLabelLarge)
                    .lineLimit(1)
            }
            .foregroundStyle(labelColor ?? Color.primary)
        }
    }

    // MARK: Join funnel

    @MainActor
    private func launchJoin(_ target: JoinOutcome, _ p: Profile) {
        guard case .success(let game, _, _, _, let joinUrl) = target else { return }
        successTick += 1
        RecentRoomStore.save(target)
        onJoin(withProfile(joinUrl, p), game.name, game.hosts)
    }

    @MainActor
    private func perform(_ action: AfterName, _ p: Profile) {
        switch action {
        case .scan:
            scanRequest = ScanRequest(games: games, profile: p)
        case .enterCode:
            codeError = nil
            showCodeEntry = true
        case .join(let target):
            launchJoin(target, p)
        }
    }

    @MainActor
    private func requireName(_ action: AfterName) {
        if !profile.isSet {
            afterName = action
            profileRequest = ProfileSheetRequest(gated: true, profile: profile)
        } else {
            perform(action, profile)
        }
    }

    @MainActor
    private func resolveAndJoin(_ raw: String) {
        let outcome = JoinResolver.resolve(raw, games: games)
        switch outcome {
        case .success:
            requireName(.join(outcome))
        case .failure(let message):
            errorTick += 1
            messages.showToast(message)
        }
    }

    @MainActor
    private func submitCode(_ text: String) {
        codeError = nil
        codeLoading = true
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        Task { @MainActor in
            let outcome = await resolveTypedCode(trimmed, games: games)
            codeLoading = false
            switch outcome {
            case .success:
                codeText = ""
                launchJoin(outcome, profile)
            case .failure(let message):
                // Alerts auto-dismiss on any action; re-present with the error
                // as the message so the player can correct the code.
                errorTick += 1
                codeError = message
                showCodeEntry = true
            }
        }
    }

    // MARK: Rejoin polling

    @MainActor
    private func runRejoinPoll() async {
        guard let recent = RecentRoomStore.load() else { return }
        guard let game = games.first(where: { $0.id == recent.gameId }) else { return }
        while !Task.isCancelled {
            let result = await RoomDirectory.lookup(code: recent.roomCode, relayBase: game.roomRelayBase)
            if Task.isCancelled { return }
            switch result {
            case .found:
                withAnimation(.spring(duration: 0.45)) {
                    rejoin = RejoinTarget(room: recent, game: game)
                }
            case .notFound:
                RecentRoomStore.clear()
                withAnimation(.spring(duration: 0.45)) {
                    rejoin = nil
                }
                return
            case .error:
                break // transient failure: keep last state
            }
            do {
                try await Task.sleep(for: .seconds(10))
            } catch {
                return
            }
        }
    }
}

// MARK: - Private types

private enum AfterName {
    case scan
    case enterCode
    case join(JoinOutcome)
}

private struct ProfileSheetRequest: Identifiable {
    let id = UUID()
    let gated: Bool
    let profile: Profile
}

private struct ScanRequest: Identifiable {
    let id = UUID()
    let games: [Game]
    let profile: Profile
}

private struct RejoinTarget {
    let room: RecentRoom
    let game: Game
}

// MARK: - RejoinCard

private struct RejoinCard: View {
    let target: RejoinTarget
    let onTap: () -> Void

    @Environment(\.cgPalette) private var palette

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 34))
                    .symbolRenderingMode(.hierarchical)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Rejoin \(target.game.name)")
                        .font(.cgTitleMedium)
                        .foregroundStyle(palette.onSecondaryContainer)
                    Text("Room \(target.room.roomCode)")
                        .font(.cgBodyMedium)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(
                palette.secondaryContainer,
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
        }
        .buttonStyle(PressableCardButtonStyle())
    }
}

// MARK: - GameCard

private struct GameCard: View {
    let game: Game
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottom) {
                GameArt(game: game)
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .frame(maxWidth: .infinity)

                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: .clear, location: 0.55),
                        .init(color: Color.black.opacity(0.86), location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(game.name)
                            .font(.cgTitleMedium)
                            .foregroundStyle(.white)
                        Text(game.tagline)
                            .font(.cgBodySmall)
                            .foregroundStyle(.white.opacity(0.82))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    PosterStatusChip(game: game)
                }
                .padding(14)
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: Color.black.opacity(0.15), radius: 4, y: 2)
        }
        .buttonStyle(PressableCardButtonStyle())
    }
}

private struct PosterStatusChip: View {
    let game: Game

    var body: some View {
        if game.isLive {
            Text("Live")
                .font(.cgLabelMedium)
                .foregroundStyle(Color.black.opacity(0.85))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(game.accentColor))
        } else {
            Text("Coming soon")
                .font(.cgLabelMedium)
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    ZStack {
                        Capsule().fill(Color.black.opacity(0.55))
                        Capsule().fill(game.accentColor.opacity(0.32))
                    }
                )
        }
    }
}

// MARK: - JoinCard (floating, material blur over the poster list)

private struct JoinCard: View {
    let host: String
    let onScan: () -> Void
    let onEnterCode: () -> Void

    @Environment(\.cgPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Join")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(palette.onSurface)

                (Text("Open ")
                    + Text(host).fontWeight(.semibold)
                    + Text(" on your TV or laptop."))
                    .font(.cgBodyMedium)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 10) {
                Button(action: onScan) {
                    Label("Scan code", systemImage: "qrcode.viewfinder")
                        .font(.cgTitleMedium)
                        .foregroundStyle(palette.onPrimary)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: 14))
                .controlSize(.large)

                Button(action: onEnterCode) {
                    Text("Enter code manually")
                        .font(.cgTitleMedium)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle(radius: 14))
                .controlSize(.large)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.15), radius: 18, y: 6)
    }
}
