import SwiftUI

/// Cross-tab push destinations. Hrefs from the web ("/show/<slug>", "/u/<id>") map onto these.
enum Route: Hashable {
    case show(slug: String)
    case mix(id: String)
    case post(id: String)
    case list(id: String)
    case album(id: String)
    case profile(id: String)

    /// Parse a web-style href into a Route (used for activity/news/byline links).
    static func from(href: String?) -> Route? {
        guard let href, href.hasPrefix("/") else { return nil }
        let parts = href.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return nil }
        switch parts[0] {
        case "show": return .show(slug: parts[1])
        case "mixes": return .mix(id: parts[1])
        case "posts": return .post(id: parts[1])
        case "lists": return .list(id: parts[1])
        case "photos": return .album(id: parts[1])
        case "u": return .profile(id: parts[1])
        default: return nil
        }
    }
}

/// A NavigationStack pre-wired with the shared route destinations.
struct QCNavStack<Root: View>: View {
    var initialPath: [Route] = []     // seeded from the `-qc-open` launch arg for QA screenshots
    @ViewBuilder var root: Root
    @State private var path: [Route] = []
    var body: some View {
        NavigationStack(path: $path) {
            root.navigationDestination(for: Route.self) { route in
                switch route {
                case .show(let slug): ShowDetailView(slug: slug)
                case .mix(let id): MixDetailView(id: id)
                case .post(let id): PostDetailView(id: id)
                case .list(let id): ListDetailView(id: id)
                case .album(let id): AlbumDetailView(id: id)
                case .profile(let id): PublicProfileView(id: id)
                }
            }
        }
        .onAppear { if path.isEmpty, !initialPath.isEmpty { path = initialPath } }
    }
}

struct RootView: View {
    @Environment(\.palette) private var p
    @Environment(AudioPlayer.self) private var player

    // Seed the selected tab from a launch arg (`-qc-tab listen|archive|interviews|community|you`)
    // so screens can be screenshotted deterministically; defaults to Listen otherwise.
    @State private var tab = UserDefaults.standard.string(forKey: "qc-tab") ?? "listen"

    /// `-qc-open <slug>` seeds the Listen stack with a pushed show detail (QA screenshots only).
    static var demoListenPath: [Route] {
        UserDefaults.standard.string(forKey: "qc-open").map { [Route.show(slug: $0)] } ?? []
    }

    var body: some View {
        @Bindable var player = player
        ZStack(alignment: .bottom) {
            TabView(selection: $tab) {
                QCNavStack(initialPath: Self.demoListenPath) { ListenView() }
                    .tabItem { Label("Listen", systemImage: "waveform") }.tag("listen")
                QCNavStack { ArchiveView() }
                    .tabItem { Label("Archive", systemImage: "calendar") }.tag("archive")
                QCNavStack { InterviewsView() }
                    .tabItem { Label("Interviews", systemImage: "text.quote") }.tag("interviews")
                QCNavStack { CommunityView() }
                    .tabItem { Label("Community", systemImage: "person.2") }.tag("community")
                QCNavStack { ProfileTabView() }
                    .tabItem { Label("You", systemImage: "person.crop.circle") }.tag("you")
            }

            if player.hasTrack {
                PlayerDock()
                    .padding(.horizontal, 10)
                    .padding(.bottom, 52)   // float above the tab bar
            }
        }
        .fullScreenCover(isPresented: $player.isExpanded) {
            NowPlayingView()
        }
    }
}
