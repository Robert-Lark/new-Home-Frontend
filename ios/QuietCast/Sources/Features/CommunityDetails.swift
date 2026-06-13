import SwiftUI

// Shared author-byline loading for the four UGC detail screens.
@MainActor
private struct AuthorBox {
    var name = "a listener"
    var isPublic = false
    static func load(_ userID: String) async -> AuthorBox {
        async let names = UGCService.displayNames([userID])
        async let pub = UGCService.publicProfileIds([userID])
        var box = AuthorBox()
        box.name = (await names)[userID] ?? "a listener"
        box.isPublic = (await pub).contains(userID)
        return box
    }
}

// MARK: - Mix

struct MixDetailView: View {
    @Environment(\.palette) private var p
    @Environment(AudioPlayer.self) private var player
    @Environment(AuthService.self) private var auth
    let id: String
    @State private var mix: MixDetail?
    @State private var author = AuthorBox()
    @State private var status = ""
    @State private var loaded = false

    private var own: Bool { auth.userID == mix?.userID }

    var body: some View {
        ThemedScreen {
            ScrollView {
                if let mix {
                    VStack(alignment: .leading, spacing: 18) {
                        Recess(padding: 16) {
                            CoverImage(urlString: mix.coverR2Key.map(Config.cdn), relaxed: true)
                                .aspectRatio(1, contentMode: .fit)
                        }
                        .padding(.horizontal, 16).padding(.top, 8)

                        DetailHeader(eyebrow: "Listener mixtape", title: mix.title,
                                     authorID: mix.userID, authorName: author.name, authorIsPublic: author.isPublic)
                            .padding(.horizontal, 16)

                        Button { player.play(track(mix)) } label: {
                            Label(isCurrent && player.isPlaying ? "Pause" : "Play", systemImage: isCurrent && player.isPlaying ? "pause.fill" : "play.fill")
                        }
                        .buttonStyle(SubmitPillStyle())
                        .padding(.horizontal, 16)

                        if let d = mix.description, !d.isEmpty {
                            Text(d).font(QCFont.body(16)).foregroundStyle(p.ink2).lineSpacing(6).padding(.horizontal, 16)
                        }
                        if let tl = mix.tracklist?.filter({ !$0.isEmpty }), !tl.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Eyebrow("Tracklist")
                                ForEach(Array(tl.enumerated()), id: \.offset) { i, t in
                                    HStack(alignment: .top, spacing: 10) {
                                        Text(String(format: "%02d", i + 1)).font(QCFont.mono(11)).foregroundStyle(p.ink3)
                                        Text(t).font(QCFont.body(15)).foregroundStyle(p.ink)
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                        if own {
                            OwnerVisibilityControl(table: .user_uploads, id: mix.id, status: $status).padding(.horizontal, 16)
                        }
                    }
                    .padding(.bottom, 140)
                } else if loaded {
                    Notice(text: "This mix isn't available.").padding(24)
                } else { ProgressView().tint(p.ink3).padding(40) }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { if !own, auth.isSignedIn, let mix { ToolbarItem(placement: .topBarTrailing) { ModerationMenu(contentType: .upload, contentRef: mix.id, authorID: mix.userID) } } }
        .task { await load() }
    }

    private var isCurrent: Bool { player.current?.id == id }
    private func track(_ m: MixDetail) -> Track {
        Track(id: m.id, title: m.title, artist: author.name == "a listener" ? "Listener mix" : author.name,
              cover: m.coverR2Key.map(Config.cdn) ?? "", src: Config.cdn(m.r2Key),
              durationLabel: Fmt.durationLabel(m.duration))
    }
    private func load() async {
        if loaded { return }
        mix = await UGCService.mix(id: id)
        if let mix { status = mix.status; author = await AuthorBox.load(mix.userID) }
        loaded = true
    }
}

// MARK: - Post

struct PostDetailView: View {
    @Environment(\.palette) private var p
    @Environment(AuthService.self) private var auth
    let id: String
    @State private var post: PostDetail?
    @State private var author = AuthorBox()
    @State private var status = ""
    @State private var loaded = false
    private var own: Bool { auth.userID == post?.userID }

    var body: some View {
        ThemedScreen {
            ScrollView {
                if let post {
                    VStack(alignment: .leading, spacing: 18) {
                        DetailHeader(eyebrow: Fmt.ugcDate(post.createdAt), title: post.title,
                                     authorID: post.userID, authorName: author.name, authorIsPublic: author.isPublic)
                        MarkdownView(blocks: Markdown.parse(post.bodyMd ?? ""))
                        if own { OwnerVisibilityControl(table: .posts, id: post.id, status: $status) }
                    }
                    .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 140)
                } else if loaded {
                    Notice(text: "This post isn't available.").padding(24)
                } else { ProgressView().tint(p.ink3).padding(40) }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { if !own, auth.isSignedIn, let post { ToolbarItem(placement: .topBarTrailing) { ModerationMenu(contentType: .post, contentRef: post.id, authorID: post.userID) } } }
        .task { await load() }
    }
    private func load() async {
        if loaded { return }
        post = await UGCService.post(id: id)
        if let post { status = post.status; author = await AuthorBox.load(post.userID) }
        loaded = true
    }
}

// MARK: - List

struct ListDetailView: View {
    @Environment(\.palette) private var p
    @Environment(AuthService.self) private var auth
    @Environment(\.openURL) private var openURL
    let id: String
    @State private var list: ListDetail?
    @State private var author = AuthorBox()
    @State private var status = ""
    @State private var loaded = false
    private var own: Bool { auth.userID == list?.userID }

    private var items: [ListItem] { (list?.listItems ?? []).sorted { $0.position < $1.position } }

    var body: some View {
        ThemedScreen {
            ScrollView {
                if let list {
                    VStack(alignment: .leading, spacing: 18) {
                        DetailHeader(eyebrow: "Listener list", title: list.title,
                                     authorID: list.userID, authorName: author.name, authorIsPublic: author.isPublic)
                        if let d = list.description, !d.isEmpty {
                            Text(d).font(QCFont.body(16)).foregroundStyle(p.ink2).lineSpacing(6)
                        }
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                                HStack(alignment: .top, spacing: 12) {
                                    Text(String(format: "%02d", i + 1)).font(QCFont.mono(12)).foregroundStyle(p.ink3)
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack(spacing: 8) {
                                            if let url = item.url, let u = URL(string: url) {
                                                Button { openURL(u) } label: { Text(item.title).font(QCFont.bodyMedium(16)).foregroundStyle(p.ember) }
                                            } else {
                                                Text(item.title).font(QCFont.bodyMedium(16)).foregroundStyle(p.ink)
                                            }
                                            Chip(text: item.itemType)
                                        }
                                        if let note = item.note, !note.isEmpty {
                                            Text(note).font(QCFont.body(14)).foregroundStyle(p.ink2)
                                        }
                                    }
                                }
                            }
                        }
                        if own { OwnerVisibilityControl(table: .lists, id: list.id, status: $status) }
                    }
                    .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 140)
                } else if loaded {
                    Notice(text: "This list isn't available.").padding(24)
                } else { ProgressView().tint(p.ink3).padding(40) }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { if !own, auth.isSignedIn, let list { ToolbarItem(placement: .topBarTrailing) { ModerationMenu(contentType: .list, contentRef: list.id, authorID: list.userID) } } }
        .task { await load() }
    }
    private func load() async {
        if loaded { return }
        list = await UGCService.list(id: id)
        if let list { status = list.status; author = await AuthorBox.load(list.userID) }
        loaded = true
    }
}

// MARK: - Album

struct AlbumDetailView: View {
    @Environment(\.palette) private var p
    @Environment(AuthService.self) private var auth
    let id: String
    @State private var album: AlbumDetail?
    @State private var author = AuthorBox()
    @State private var status = ""
    @State private var loaded = false
    private var own: Bool { auth.userID == album?.userID }
    private var photos: [PhotoItem] { (album?.photos ?? []).sorted { $0.position < $1.position } }

    var body: some View {
        ThemedScreen {
            ScrollView {
                if let album {
                    VStack(alignment: .leading, spacing: 16) {
                        DetailHeader(eyebrow: albumStamp(album), title: album.title,
                                     authorID: album.userID, authorName: author.name, authorIsPublic: author.isPublic)
                        if let d = album.description, !d.isEmpty {
                            Text(d).font(QCFont.body(16)).foregroundStyle(p.ink2).lineSpacing(6)
                        }
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 2), GridItem(.flexible(), spacing: 2)], spacing: 2) {
                            ForEach(photos) { ph in
                                CoverImage(urlString: Config.cdn(ph.r2Key), relaxed: true)
                                    .aspectRatio(1, contentMode: .fill).clipped()
                            }
                        }
                        if own { OwnerVisibilityControl(table: .photo_albums, id: album.id, status: $status) }
                    }
                    .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 140)
                } else if loaded {
                    Notice(text: "This album isn't available.").padding(24)
                } else { ProgressView().tint(p.ink3).padding(40) }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { if !own, auth.isSignedIn, let album { ToolbarItem(placement: .topBarTrailing) { ModerationMenu(contentType: .photo_album, contentRef: album.id, authorID: album.userID) } } }
        .task { await load() }
    }
    private func albumStamp(_ a: AlbumDetail) -> String {
        let parts = [a.venue, a.eventDate.map(Fmt.ugcDate)].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? Fmt.ugcDate(a.createdAt) : parts.joined(separator: " · ")
    }
    private func load() async {
        if loaded { return }
        album = await UGCService.album(id: id)
        if let album { status = album.status; author = await AuthorBox.load(album.userID) }
        loaded = true
    }
}
