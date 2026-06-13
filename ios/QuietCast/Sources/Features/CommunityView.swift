import SwiftUI

/// Community shelf (community.astro): four published-content sections, anonymous-readable.
struct CommunityView: View {
    @Environment(\.palette) private var p
    @State private var mixes: [MixSummary] = []
    @State private var posts: [PostSummary] = []
    @State private var lists: [ListSummary] = []
    @State private var albums: [AlbumSummary] = []
    @State private var names: [String: String] = [:]
    @State private var publicIDs: Set<String> = []
    @State private var loaded = false

    var body: some View {
        ThemedScreen {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    VStack(alignment: .leading, spacing: 6) {
                        Eyebrow("From the listeners")
                        DisplayTitle(text: "Community", size: 34, tracking: 3)
                    }
                    if loaded && mixes.isEmpty && posts.isEmpty && lists.isEmpty && albums.isEmpty {
                        Notice(text: "Nothing published yet — be the first on the web app.")
                    }
                    shelf("Mixtapes", items: mixes) { m in
                        NavigationLink(value: Route.mix(id: m.id)) {
                            mixRow(m)
                        }.buttonStyle(.plain)
                    }
                    shelf("Writing", items: posts) { p in
                        NavigationLink(value: Route.post(id: p.id)) {
                            textRow(title: p.title, sub: byline(p.userID), date: p.createdAt)
                        }.buttonStyle(.plain)
                    }
                    shelf("Lists", items: lists) { l in
                        NavigationLink(value: Route.list(id: l.id)) {
                            textRow(title: l.title, sub: l.description ?? byline(l.userID), date: l.createdAt)
                        }.buttonStyle(.plain)
                    }
                    shelf("Concert photos", items: albums) { a in
                        NavigationLink(value: Route.album(id: a.id)) {
                            albumRow(a)
                        }.buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 140)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    @ViewBuilder private func shelf<Item: Identifiable, Row: View>(_ title: String, items: [Item], @ViewBuilder row: @escaping (Item) -> Row) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Eyebrow(title)
                ForEach(items) { item in
                    row(item)
                    Divider().overlay(p.hairlineSoft)
                }
            }
        }
    }

    private func mixRow(_ m: MixSummary) -> some View {
        HStack(spacing: 14) {
            CoverImage(urlString: m.coverR2Key.map(Config.cdn))
                .frame(width: 56, height: 56).clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 3) {
                Text(m.title).font(QCFont.bodyMedium(15)).foregroundStyle(p.ink).lineLimit(1)
                Text(byline(m.userID)).font(QCFont.mono(9)).foregroundStyle(p.ink3)
            }
            Spacer()
            if let d = Fmt.durationLabel(m.duration) {
                Text(d).font(QCFont.mono(10)).foregroundStyle(p.ink3)
            }
        }
        .padding(.vertical, 6)
    }

    private func albumRow(_ a: AlbumSummary) -> some View {
        let thumb = a.photos?.min(by: { $0.position < $1.position })?.r2Key
        return HStack(spacing: 14) {
            CoverImage(urlString: thumb.map(Config.cdn))
                .frame(width: 56, height: 56).clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 3) {
                Text(a.title).font(QCFont.bodyMedium(15)).foregroundStyle(p.ink).lineLimit(1)
                Text(albumSub(a)).font(QCFont.mono(9)).foregroundStyle(p.ink3)
            }
            Spacer()
        }
        .padding(.vertical, 6)
    }

    private func textRow(title: String, sub: String, date: String?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(QCFont.bodyMedium(15)).foregroundStyle(p.ink).lineLimit(1)
            Text(sub).font(QCFont.mono(9)).foregroundStyle(p.ink3).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
    }

    private func albumSub(_ a: AlbumSummary) -> String {
        let parts = [a.venue, a.eventDate.map(Fmt.ugcDate)].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? byline(a.userID) : parts.joined(separator: " · ")
    }

    private func byline(_ userID: String) -> String { names[userID] ?? "a listener" }

    private func load() async {
        if loaded { return }
        async let m = UGCService.mixes()
        async let p = UGCService.posts()
        async let l = UGCService.lists()
        async let a = UGCService.albums()
        mixes = await m; posts = await p; lists = await l; albums = await a
        let ids = mixes.map(\.userID) + posts.map(\.userID) + lists.map(\.userID) + albums.map(\.userID)
        async let nm = UGCService.displayNames(ids)
        async let pub = UGCService.publicProfileIds(ids)
        names = await nm; publicIDs = await pub
        loaded = true
    }
}

/// Author byline that links to /u/<id> only when the author's profile is public (ugc.md §6).
struct Byline: View {
    @Environment(\.palette) private var p
    let userID: String
    let name: String
    let isPublic: Bool
    var body: some View {
        if isPublic {
            NavigationLink(value: Route.profile(id: userID)) {
                Text("by \(name)").font(QCFont.mono(10)).foregroundStyle(p.ember)
            }
        } else {
            Text("by \(name)").font(QCFont.mono(10)).foregroundStyle(p.ink3)
        }
    }
}
