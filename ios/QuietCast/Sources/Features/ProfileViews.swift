import SwiftUI

/// "You" tab: the signed-in dashboard, or the sign-in surface when logged out.
struct ProfileTabView: View {
    @Environment(\.palette) private var p
    @Environment(AuthService.self) private var auth

    var body: some View {
        Group {
            if auth.isSignedIn {
                DashboardView()
            } else {
                AuthView()
            }
        }
    }
}

/// Own dashboard (/dashboard).
struct DashboardView: View {
    @Environment(\.palette) private var p
    @Environment(AuthService.self) private var auth
    @State private var screen = ProfileScreen()
    @State private var loaded = false

    var body: some View {
        ThemedScreen {
            ScrollView {
                if loaded {
                    VStack(alignment: .leading, spacing: 24) {
                        ProfileCard(screen: screen, isOwn: true, email: auth.email)
                        if !screen.continueListening.isEmpty { continueListening }
                        SiteNewsSection(items: screen.siteNews)
                        BioSection(bio: screen.details?.bio, isOwn: true)
                        ActivitySection(events: screen.activity)
                        RotationSection(title: "\(screen.displayName)'s rotation", connections: screen.connections)
                        WallSection(profileID: auth.userID ?? "", entries: screen.wall, wallOpen: screen.details?.isPublic ?? false, isOwn: true, reload: reload)
                        ManageSection(content: screen.content)
                    }
                    .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 140)
                } else {
                    ProgressView().tint(p.ink3).padding(40)
                }
            }
        }
        .navigationTitle("You")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { SettingsView(reload: reload) } label: { Image(systemName: "gearshape").foregroundStyle(p.ink2) }
            }
        }
        .task { if !loaded { await reload() } }
    }

    private var continueListening: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow("Continue listening")
            ForEach(screen.continueListening) { row in
                if let route = Route.from(href: row.href) {
                    NavigationLink(value: route) {
                        HStack {
                            Text(row.title).font(QCFont.bodyMedium(15)).foregroundStyle(p.ink).lineLimit(1)
                            Spacer()
                            Text("\(row.minutesIn) min in").font(QCFont.mono(9)).foregroundStyle(p.ink3)
                        }
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    @MainActor private func reload() async {
        screen = await ProfileService.loadDashboard()
        loaded = true
    }
}

/// Public profile (/u/[id]) with the privacy gate.
struct PublicProfileView: View {
    @Environment(\.palette) private var p
    @Environment(AuthService.self) private var auth
    let id: String
    @State private var screen = ProfileScreen()
    @State private var loaded = false

    var body: some View {
        ThemedScreen {
            ScrollView {
                if !loaded {
                    ProgressView().tint(p.ink3).padding(40)
                } else if !screen.visible {
                    VStack(spacing: 12) {
                        Eyebrow("Private")
                        Text("This page is private.").font(QCFont.display(24)).foregroundStyle(p.ink)
                    }.padding(.top, 80)
                } else {
                    VStack(alignment: .leading, spacing: 24) {
                        ProfileCard(screen: screen, isOwn: false, email: nil)
                        SiteNewsSection(items: screen.siteNews)
                        BioSection(bio: screen.details?.bio, isOwn: false)
                        ActivitySection(events: screen.activity)
                        RotationSection(title: "\(screen.displayName)'s rotation", connections: screen.connections)
                        WallSection(profileID: id, entries: screen.wall, wallOpen: screen.details?.isPublic ?? false, isOwn: auth.userID == id, reload: reload)
                    }
                    .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 140)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if auth.isSignedIn, auth.userID != id, screen.visible {
                ToolbarItem(placement: .topBarTrailing) {
                    ModerationMenu(contentType: .wall_comment, contentRef: id, authorID: id)
                }
            }
        }
        .task { if !loaded { await reload() } }
    }

    @MainActor private func reload() async {
        screen = await ProfileService.loadPublic(id: id)
        loaded = true
    }
}

// MARK: - Sections

struct ProfileCard: View {
    @Environment(\.palette) private var p
    @Environment(AudioPlayer.self) private var player
    let screen: ProfileScreen
    let isOwn: Bool
    let email: String?

    var body: some View {
        Panel(padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                avatar
                Text(screen.displayName).font(QCFont.display(28)).tracking(1).foregroundStyle(p.ink)
                Text("listener\((screen.details?.isPublic ?? false) ? "" : " · private")")
                    .font(QCFont.mono(9)).tracking(1.4).foregroundStyle(p.ink3)
                if let status = screen.details?.statusLine, !status.isEmpty {
                    Text("“\(status)”").font(QCFont.bodyItalic(16)).foregroundStyle(p.ink2)
                }
                Text("Tuned in since \(Fmt.memberSince(screen.profile?.createdAt))")
                    .font(QCFont.mono(9)).foregroundStyle(p.ink3)
                if isOwn, let email { Text(email).font(QCFont.mono(9)).foregroundStyle(p.ink3) }
                if let song = screen.song, !song.src.isEmpty { songButton(song) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private var avatar: some View {
        if let url = screen.profile?.avatarURL, let u = URL(string: url) {
            AsyncImage(url: u) { img in img.resizable().scaledToFill() } placeholder: { p.recess }
                .frame(width: 96, height: 96).clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            RoundedRectangle(cornerRadius: 8).fill(p.recess)
                .frame(width: 96, height: 96)
                .overlay(Text(String(screen.displayName.prefix(1)).uppercased()).font(QCFont.display(44)).foregroundStyle(p.ink2))
        }
    }

    private func songButton(_ song: Track) -> some View {
        Button { player.play(song) } label: {
            HStack(spacing: 10) {
                Image(systemName: "play.circle.fill").font(.system(size: 22)).foregroundStyle(p.ember)
                VStack(alignment: .leading, spacing: 1) {
                    Eyebrow("Profile signal")
                    Text(song.title).font(QCFont.bodyMedium(14)).foregroundStyle(p.ink).lineLimit(1)
                }
            }
        }
        .padding(.top, 4)
    }
}

struct BioSection: View {
    @Environment(\.palette) private var p
    let bio: String?
    let isOwn: Bool
    var body: some View {
        if let bio, !bio.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Eyebrow("About")
                Text(bio).font(QCFont.body(16)).foregroundStyle(p.ink2).lineSpacing(5)
            }
        } else if isOwn {
            VStack(alignment: .leading, spacing: 8) {
                Eyebrow("About")
                Text("Add a bio in Settings.").font(QCFont.body(15)).foregroundStyle(p.ink3)
            }
        }
    }
}

struct ActivitySection: View {
    @Environment(\.palette) private var p
    let events: [ActivityEvent]
    var body: some View {
        if !events.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Eyebrow("Latest activity")
                ForEach(events) { e in
                    activityRow(e)
                    Divider().overlay(p.hairlineSoft)
                }
            }
        }
    }
    @ViewBuilder private func activityRow(_ e: ActivityEvent) -> some View {
        let content = VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Eyebrow(e.kind.rawValue)
                if let note = e.note { StatusBadge(text: note) }
            }
            Text(e.text).font(QCFont.body(15)).foregroundStyle(p.ink).lineLimit(2)
            if !e.at.isEmpty { Text(Fmt.ugcDate(e.at)).font(QCFont.mono(8)).foregroundStyle(p.ink3) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        if let route = Route.from(href: e.href) {
            NavigationLink(value: route) { content }.buttonStyle(.plain)
        } else {
            content
        }
    }
}

struct SiteNewsSection: View {
    @Environment(\.palette) private var p
    let items: [SiteNewsItem]
    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Eyebrow("Meanwhile on Quiet Cast")
                ForEach(items) { item in
                    if let route = Route.from(href: item.href) {
                        NavigationLink(value: route) {
                            HStack {
                                Text(item.title).font(QCFont.body(14)).foregroundStyle(p.ink).lineLimit(1)
                                Spacer()
                                Eyebrow(item.kind.rawValue)
                            }
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

struct ManageSection: View {
    @Environment(\.palette) private var p
    let content: UserContent
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Eyebrow("My pages")
            panel("My mixtapes", content.mixes, path: "mixes")
            panel("My posts", content.posts, path: "posts")
            panel("My lists", content.lists, path: "lists")
            panel("My concert photos", content.albums, path: "photos")
        }
    }
    @ViewBuilder private func panel(_ label: String, _ rows: [ContentRow], path: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(QCFont.bodyMedium(14)).foregroundStyle(p.ink2)
            if rows.isEmpty {
                Text("Nothing yet.").font(QCFont.body(13)).foregroundStyle(p.ink3)
            } else {
                ForEach(rows.prefix(4)) { row in
                    NavigationLink(value: route(path, row.id)) {
                        HStack {
                            Text(row.title).font(QCFont.body(14)).foregroundStyle(p.ink).lineLimit(1)
                            Spacer()
                            StatusBadge(text: row.status)
                        }
                    }.buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 4)
    }
    private func route(_ path: String, _ id: String) -> Route {
        switch path {
        case "mixes": return .mix(id: id)
        case "posts": return .post(id: id)
        case "lists": return .list(id: id)
        default: return .album(id: id)
        }
    }
}
