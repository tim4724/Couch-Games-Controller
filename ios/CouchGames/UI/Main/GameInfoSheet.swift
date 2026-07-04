import SwiftUI
import AVFoundation

// MARK: - GameInfoSheet

struct GameInfoSheet: View {
    let game: Game

    @Environment(\.cgPalette) private var palette

    init(game: Game) {
        self.game = game
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Text(game.name)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(palette.onSurface)
                StatusLabel(game: game)
            }

            if let video = game.video {
                GameplayLoopView(videoName: video)
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(game.tagline)
                    .font(.cgBodyLarge)
                    .foregroundStyle(palette.onSurfaceVariant)
                    .fixedSize(horizontal: false, vertical: true)
                if let players = game.players {
                    Text(players)
                        .font(.cgTitleMedium)
                        .foregroundStyle(palette.primary)
                }
            }

            if !game.isLive {
                Text(game.comingSoonNote ?? "Coming soon to Couch Games.")
                    .font(.cgBodyLarge)
                    .foregroundStyle(palette.onSurfaceVariant)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 28)
    }
}

// MARK: - GameplayLoopView

struct GameplayLoopView: View {
    let videoName: String     // bundle resource base name; extension "mp4"

    @Environment(\.cgPalette) private var palette

    init(videoName: String) {
        self.videoName = videoName
    }

    private var videoURL: URL? {
        // Resources are flattened into the bundle root — look up by last path component.
        let base = videoName.components(separatedBy: "/").last ?? videoName
        return Bundle.main.url(forResource: base, withExtension: "mp4")
    }

    var body: some View {
        if let url = videoURL {
            LoopingPlayerView(url: url)
        } else {
            Rectangle().fill(palette.surfaceVariant)
        }
    }
}

// MARK: - Looping player (private)

private struct LoopingPlayerView: UIViewRepresentable {
    let url: URL

    final class PlayerUIView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }

        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

        private var player: AVQueuePlayer?
        private var looper: AVPlayerLooper?

        func configure(url: URL) {
            guard player == nil else { return }
            let item = AVPlayerItem(url: url)
            let queuePlayer = AVQueuePlayer()
            queuePlayer.isMuted = true
            looper = AVPlayerLooper(player: queuePlayer, templateItem: item)
            player = queuePlayer
            playerLayer.player = queuePlayer
            playerLayer.videoGravity = .resizeAspectFill
            queuePlayer.play()
        }

        func teardown() {
            player?.pause()
            playerLayer.player = nil
            looper?.disableLooping()
            looper = nil
            player = nil
        }
    }

    func makeUIView(context: Context) -> PlayerUIView {
        let view = PlayerUIView()
        view.configure(url: url)
        return view
    }

    func updateUIView(_ uiView: PlayerUIView, context: Context) {}

    static func dismantleUIView(_ uiView: PlayerUIView, coordinator: ()) {
        uiView.teardown()
    }
}
