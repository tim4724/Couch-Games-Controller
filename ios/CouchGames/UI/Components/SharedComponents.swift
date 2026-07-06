import SwiftUI
import UIKit

// MARK: - PlayerChip

/// Tappable player-identity chip (home header + in-game bar).
struct PlayerChip: View {
    let name: String
    var accented: Bool = false
    let action: () -> Void

    @Environment(\.cgPalette) private var palette

    init(name: String, accented: Bool = false, action: @escaping () -> Void) {
        self.name = name
        self.accented = accented
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "person.crop.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                Text(displayName)
                    .font(.cgLabelLarge)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        // Home inherits the root mono tint; the game host's remapped palette
        // makes this the game accent there.
        .tint(palette.primary)
    }

    private var displayName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? String(localized: "Set name") : name
    }
}

// MARK: - ArtCache

/// Process-wide memoized async decode of bundled artwork, keyed by asset path.
/// Assets are flattened into the bundle root, so lookup uses lastPathComponent only.
enum ArtCache {
    private static let lock = NSLock()
    private static var images: [String: UIImage] = [:]
    private static var failures: Set<String> = []
    private static var inFlight: [String: Task<UIImage?, Never>] = [:]

    /// Synchronous accessor: non-nil only after a successful decode has been memoized.
    static func cached(forAssetPath path: String) -> UIImage? {
        lock.lock()
        defer { lock.unlock() }
        return images[path]
    }

    /// Decode once per asset path, off-main, memoized forever.
    static func uiImage(forAssetPath path: String) async -> UIImage? {
        let pending: Task<UIImage?, Never>? = locked {
            if images[path] != nil || failures.contains(path) { return nil }
            if let task = inFlight[path] { return task }
            let task = Task<UIImage?, Never>.detached(priority: .userInitiated) {
                let result = decode(assetPath: path)
                locked {
                    if let result {
                        images[path] = result
                    } else {
                        failures.insert(path)
                    }
                    inFlight[path] = nil
                }
                return result
            }
            inFlight[path] = task
            return task
        }
        if let pending {
            return await pending.value
        }
        return locked { images[path] }
    }

    private static func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    private static func decode(assetPath: String) -> UIImage? {
        let file = (assetPath as NSString).lastPathComponent
        let name = (file as NSString).deletingPathExtension
        let ext = (file as NSString).pathExtension
        guard
            !name.isEmpty,
            let url = Bundle.main.url(forResource: name, withExtension: ext.isEmpty ? nil : ext),
            let data = try? Data(contentsOf: url),
            let image = UIImage(data: data)   // WebP decodes natively on iOS 17
        else { return nil }
        return image
    }
}

// MARK: - GameArt

/// Cover art for a game, or an accent-gradient fallback when art is missing / fails to decode.
struct GameArt: View {
    let game: Game

    @Environment(\.cgPalette) private var palette
    @State private var image: UIImage?
    @State private var decodeFailed = false

    init(game: Game) {
        self.game = game
        if let art = game.art {
            _image = State(initialValue: ArtCache.cached(forAssetPath: art))
        }
    }

    var body: some View {
        Rectangle()
            .fill(palette.surfaceVariant)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else if game.art == nil || decodeFailed {
                    fallbackGradient
                }
            }
            .clipped()
            .accessibilityLabel(game.name)
            .task(id: game.art) {
                guard image == nil, let art = game.art else { return }
                if let decoded = await ArtCache.uiImage(forAssetPath: art) {
                    image = decoded
                } else {
                    decodeFailed = true
                }
            }
    }

    private var fallbackGradient: LinearGradient {
        LinearGradient(
            colors: [game.accentColor.opacity(0.50), game.accentColor.opacity(0.14)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - StepRow

/// Numbered instruction row: 28pt solid-primary circle + attributed body text.
struct StepRow: View {
    let number: Int
    let text: AttributedString

    @Environment(\.cgPalette) private var palette

    init(number: Int, text: AttributedString) {
        self.number = number
        self.text = text
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                // Solid primary, not primaryContainer — the pale container tint is
                // nearly invisible against the sheet's surface in light mode.
                Circle()
                    .fill(palette.primary)
                    .frame(width: 28, height: 28)
                Text("\(number)")
                    .font(.cgLabelLarge)
                    .foregroundStyle(palette.onPrimary)
            }
            Text(text)
                .font(.cgBodyLarge)
                .foregroundStyle(palette.onSurface)
        }
    }
}

// MARK: - JoinButtons

/// The two join actions — shared by the home Join card and a live game's info sheet.
struct JoinButtons: View {
    let onScan: () -> Void
    let onEnterCode: () -> Void

    @Environment(\.cgPalette) private var palette

    var body: some View {
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
}

// MARK: - StatusLabel

/// Inline live/coming-soon status for the game info sheet header.
struct StatusLabel: View {
    let game: Game

    @Environment(\.cgPalette) private var palette

    init(game: Game) {
        self.game = game
    }

    var body: some View {
        if game.isLive {
            HStack(spacing: 6) {
                Circle()
                    .fill(palette.primary)
                    .frame(width: 8, height: 8)
                Text("Live")
                    .font(.cgLabelLarge)
                    .foregroundStyle(palette.primary)
            }
        } else {
            Text("Coming soon")
                .font(.cgLabelLarge)
                .foregroundStyle(palette.onSurfaceVariant)
        }
    }
}

// MARK: - PressableCardButtonStyle

/// Card press micro-interaction: spring scale to 0.97 while pressed.
struct PressableCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - AppSheetContainer

/// House-style sheet: opens fully expanded at its content height, no grabber,
/// 28pt corners, surfaceContainerHigh background.
struct AppSheetContainer<Content: View>: View {
    @Environment(\.cgPalette) private var palette
    @State private var measuredHeight: CGFloat = 0
    /// A game's theme-color, used as the sheet surface so an in-game sheet reads as
    /// part of the game. Nil (the default) keeps the neutral surface. Callers gate on
    /// luminance so the surface stays dark enough for the sheet's light text.
    private let surfaceTint: Color?
    private let content: () -> Content

    init(surfaceTint: Color? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.surfaceTint = surfaceTint
        self.content = content
    }

    var body: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .top)
            // Take the content's IDEAL height: the detent starts near zero, and
            // without this the compressed first layout (truncated text, collapsed
            // aspect-ratio views) self-consistently measures as the final height.
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { height in
                measuredHeight = height
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .presentationDetents([.height(max(measuredHeight, 1))])
            .presentationDragIndicator(.hidden)
            .presentationCornerRadius(28)
            .presentationBackground(surfaceTint ?? palette.surfaceContainerHigh)
    }
}

extension View {
    func appSheet<Content: View>(
        isPresented: Binding<Bool>,
        onDismiss: (() -> Void)? = nil,
        surfaceTint: Color? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        sheet(isPresented: isPresented, onDismiss: onDismiss) {
            AppSheetContainer(surfaceTint: surfaceTint, content: content)
        }
    }

    func appSheet<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        onDismiss: (() -> Void)? = nil,
        surfaceTint: Color? = nil,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        sheet(item: item, onDismiss: onDismiss) { item in
            AppSheetContainer(surfaceTint: surfaceTint) { content(item) }
        }
    }
}
