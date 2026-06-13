import SwiftUI

/// Listen — the broadcast catalog as a square grid (index.astro). Tapping a cover plays it and
/// seeds the full-catalog queue (cat desc); the title row opens the show detail.
struct ListenView: View {
    @Environment(\.palette) private var p
    @Environment(AudioPlayer.self) private var player
    @State private var episodes: [Episode] = []
    @State private var loaded = false

    private var queue: [Track] { episodes.map(\.track) }

    var body: some View {
        ThemedScreen {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    if episodes.isEmpty && loaded {
                        Notice(text: "Couldn't reach the broadcast archive.")
                            .padding(.horizontal, 16)
                    } else {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 2), GridItem(.flexible(), spacing: 2)], spacing: 2) {
                            ForEach(episodes) { ep in
                                EpisodeCard(episode: ep, queue: queue)
                            }
                        }
                        .padding(.horizontal, 2)
                    }
                }
                .padding(.bottom, 140)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow("Quiet Cast")
            DisplayTitle(text: "Broadcasts", size: 34, tracking: 3)
        }
        .padding(.horizontal, 16).padding(.top, 8)
    }

    private func load() async {
        if loaded { return }
        episodes = (try? await SanityService.shared.episodes()) ?? []
        loaded = true
        // QA demo hook: `-qc-demo dock|nowplaying` starts the first episode (and optionally expands
        // the player) so the playback surfaces can be screenshotted deterministically.
        let demo = UserDefaults.standard.string(forKey: "qc-demo")
        if let first = episodes.first, demo == "dock" || demo == "nowplaying" {
            player.play(first.track, queue: queue)
            if demo == "nowplaying" { player.isExpanded = true }
        }
    }
}

/// One episode tile: play-on-cover, listen-state overlay, favorite, and a title link to the show.
struct EpisodeCard: View {
    @Environment(\.palette) private var p
    @Environment(AudioPlayer.self) private var player
    @Environment(LibraryStore.self) private var library
    @Environment(AuthService.self) private var auth
    let episode: Episode
    let queue: [Track]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                player.play(episode.track, queue: queue)
            } label: {
                ZStack(alignment: .topTrailing) {
                    CoverImage(urlString: Sanity.sizedCover(episode.coverURL, 600), relaxed: state == .done)
                        .aspectRatio(1, contentMode: .fill)
                        .clipped()
                        .overlay(alignment: .bottomLeading) { band }
                        .overlay(alignment: .center) { playGlyphVisible }
                        .overlay { if state == .inProgress { Rectangle().stroke(p.ember, lineWidth: 1) } }
                    overlayControls
                }
            }
            .buttonStyle(.plain)

            NavigationLink(value: Route.show(slug: episode.slug)) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(episode.title).font(QCFont.bodyMedium(14)).foregroundStyle(p.ink).lineLimit(1)
                    Text(episode.artist).font(QCFont.mono(9)).tracking(0.5).foregroundStyle(p.ink2).lineLimit(1)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 4)
        }
        .padding(.bottom, 6)
    }

    private var state: ListenState { library.state(for: episode.slug) }

    private var band: some View {
        // over-art credit band
        HStack {
            Text(episode.catLabel)
                .font(QCFont.mono(9)).tracking(1.4)
                .foregroundStyle(Palette.overArt.ink2)
            Spacer()
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Palette.overArt.canvas.opacity(0.86), .clear], startPoint: .bottom, endPoint: .top)
        )
    }

    @ViewBuilder private var playGlyphVisible: some View {
        if player.current?.id == episode.slug {
            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Palette.overArt.onEmber)
                .frame(width: 40, height: 40)
                .background(Circle().fill(p.ember))
        }
    }

    private var overlayControls: some View {
        HStack(spacing: 6) {
            if state != .unplayed { ListenDot(state: state) }
            Button {
                Task { await library.toggleFavorite(episode.slug) }
            } label: {
                Image(systemName: library.isFavorite(episode.slug) ? "heart.fill" : "heart")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(library.isFavorite(episode.slug) ? p.ember : Palette.overArt.ink2)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Palette.overArt.canvas.opacity(0.66)))
            }
            .buttonStyle(.plain)
            .opacity(auth.isSignedIn ? 1 : 0)
        }
        .padding(6)
    }
}
