import SwiftUI

/// Episode detail (/show/[slug]): hero cover, meta, play (seeds full catalog), favorite,
/// numbered tracklist, and the Q&A section when present.
struct ShowDetailView: View {
    @Environment(\.palette) private var p
    @Environment(AudioPlayer.self) private var player
    @Environment(LibraryStore.self) private var library
    @Environment(AuthService.self) private var auth
    let slug: String

    @State private var episode: Episode?
    @State private var queue: [Track] = []
    @State private var loaded = false

    var body: some View {
        ThemedScreen {
            ScrollView {
                if let ep = episode {
                    content(ep)
                } else if loaded {
                    Notice(text: "This show isn't available.").padding(24)
                } else {
                    ProgressView().tint(p.ink3).padding(40)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    @ViewBuilder private func content(_ ep: Episode) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Recess(padding: 16) {
                CoverImage(urlString: Sanity.sizedCover(ep.coverURL, 900), relaxed: true)
                    .aspectRatio(1, contentMode: .fit)
            }
            .padding(.horizontal, 16).padding(.top, 8)

            VStack(alignment: .leading, spacing: 8) {
                Eyebrow("\(ep.catLabel)\(ep.year.map { " · \($0)" } ?? "")")
                DisplayTitle(text: ep.title, size: 30, tracking: 2)
                Text(ep.artist).font(QCFont.bodyItalic(17)).foregroundStyle(p.ember)
            }
            .padding(.horizontal, 16)

            HStack(spacing: 12) {
                Button {
                    player.play(ep.track, queue: queue)
                } label: { Label(isCurrent && player.isPlaying ? "Pause" : "Play", systemImage: isCurrent && player.isPlaying ? "pause.fill" : "play.fill") }
                    .buttonStyle(SubmitPillStyle())

                if auth.isSignedIn {
                    Button {
                        Task { await library.toggleFavorite(ep.slug) }
                    } label: {
                        Image(systemName: library.isFavorite(ep.slug) ? "heart.fill" : "heart")
                            .font(.system(size: 16))
                            .frame(width: 52, height: 50)
                            .foregroundStyle(library.isFavorite(ep.slug) ? p.ember : p.ink2)
                            .overlay(Capsule().stroke(p.hairline, lineWidth: 1))
                    }
                }
            }
            .padding(.horizontal, 16)

            if !ep.description.isEmpty {
                Text(ep.description)
                    .font(QCFont.body(16)).foregroundStyle(p.ink2)
                    .lineSpacing(6)
                    .padding(.horizontal, 16)
            }

            if !ep.tracklist.isEmpty {
                section("Tracklist") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(ep.tracklist.enumerated()), id: \.offset) { i, t in
                            HStack(alignment: .top, spacing: 10) {
                                Text(String(format: "%02d", i + 1))
                                    .font(QCFont.mono(11)).foregroundStyle(p.ink3)
                                Text(t).font(QCFont.body(15)).foregroundStyle(p.ink)
                            }
                        }
                    }
                }
            }

            if !ep.qa.isEmpty {
                section("Interview") {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(Array(ep.qa.enumerated()), id: \.offset) { _, pair in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(pair.q).font(QCFont.bodySemiBold(16)).foregroundStyle(p.ink)
                                Text(pair.a).font(QCFont.body(16)).foregroundStyle(p.ink2).lineSpacing(6)
                            }
                        }
                    }
                }
            }
        }
        .padding(.bottom, 140)
    }

    private var isCurrent: Bool { player.current?.id == slug }

    @ViewBuilder private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow(title)
            content()
        }
        .padding(.horizontal, 16)
    }

    private func load() async {
        if loaded { return }
        async let epA = SanityService.shared.episode(slug: slug)
        async let allA = SanityService.shared.episodes()
        episode = (try? await epA) ?? nil
        queue = ((try? await allA) ?? []).map(\.track)
        loaded = true
    }
}
