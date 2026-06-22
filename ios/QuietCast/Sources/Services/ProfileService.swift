import Foundation
import Supabase

/// Aggregate row of a user's content piece (used for activity, news, and the manage panels).
struct ContentRow: Decodable, Identifiable, Hashable {
    var id: String
    var title: String
    var status: String
    var createdAt: String?
    enum CodingKeys: String, CodingKey { case id, title, status; case createdAt = "created_at" }
}

struct UserContent {
    var mixes: [ContentRow] = []
    var posts: [ContentRow] = []
    var lists: [ContentRow] = []
    var albums: [ContentRow] = []
}

struct ContinueRow: Identifiable, Hashable {
    var id: String
    var title: String
    var href: String
    var minutesIn: Int
}

/// Everything one profile screen needs (mirrors the web page-data fetch for /u/[id] and /dashboard).
struct ProfileScreen {
    var profile: ProfileRow?
    var details: ProfileDetails?
    var connections: [Connection] = []
    var content = UserContent()
    var wall: [WallEntry] = []
    var activity: [ActivityEvent] = []
    var siteNews: [SiteNewsItem] = []
    var song: Track?
    var continueListening: [ContinueRow] = []
    var visible = true              // /u/[id] privacy gate (profile.md §3)

    var displayName: String {
        profile?.displayName?.isEmpty == false ? profile!.displayName! : "A listener"
    }
}

/// Profile / dashboard / wall reads + settings & wall writes (profile.md, auth-account.md §5).
enum ProfileService {
    private static var uid: String? { Supa.client.auth.currentUser?.id.uuidString.lowercased() }

    // MARK: - Aggregate loaders

    /// Public profile /u/[id]. Visible iff profiles row exists AND (is_public OR viewer is owner).
    static func loadPublic(id: String) async -> ProfileScreen {
        let viewer = uid
        let own = viewer == id
        async let profileA = profileRow(id)
        async let detailsA = profileDetails(id)
        async let connsA = connections(id)
        async let contentA = userContent(id, publishedOnly: true)
        async let episodesA = (try? await SanityService.shared.episodeIndex()) ?? [:]

        var screen = ProfileScreen()
        screen.profile = await profileA
        screen.details = await detailsA
        screen.connections = await connsA
        screen.content = await contentA
        let episodes = await episodesA

        screen.visible = screen.profile != nil && ((screen.details?.isPublic ?? false) || own)
        guard screen.visible else { return screen }

        screen.wall = await wallEntries(profileID: id, viewerID: viewer)
        screen.siteNews = await siteNews(episodesByRef: episodes)
        if let ref = screen.details?.profileSongRef { screen.song = await resolveTrack(ref, episodesByRef: episodes) }

        let mixTitles = await resolveMixTitles(refsIn: screen.content)
        screen.activity = buildActivity(
            content: screen.content, favorites: [], listens: [],
            connections: screen.connections, wall: screen.wall,
            episodesByRef: episodes, mixTitles: mixTitles, ownView: false
        )
        return screen
    }

    /// Own dashboard. publishedOnly=false; adds favorites + listen_status for activity & continue-listening.
    static func loadDashboard() async -> ProfileScreen {
        guard let me = uid else { return ProfileScreen() }
        async let profileA = profileRow(me)
        async let detailsA = profileDetails(me)
        async let connsA = connections(me)
        async let contentA = userContent(me, publishedOnly: false)
        async let favsA = recentFavorites()
        async let listensA = recentListens()
        async let episodesA = (try? await SanityService.shared.episodeIndex()) ?? [:]

        var screen = ProfileScreen()
        screen.profile = await profileA
        screen.details = await detailsA
        screen.connections = await connsA
        screen.content = await contentA
        let favs = await favsA
        let listens = await listensA
        let episodes = await episodesA

        screen.wall = await wallEntries(profileID: me, viewerID: me)
        screen.siteNews = await siteNews(episodesByRef: episodes)
        if let ref = screen.details?.profileSongRef { screen.song = await resolveTrack(ref, episodesByRef: episodes) }

        // mix-title resolution spans content + favorite/listen refs
        var refs = contentRefs(screen.content)
        refs += favs.map(\.content_ref) + listens.map(\.content_ref)
        let mixTitles = await resolveMixTitles(refs.filter(ContentRef.isUUID))

        screen.activity = buildActivity(
            content: screen.content, favorites: favs, listens: listens,
            connections: screen.connections, wall: screen.wall,
            episodesByRef: episodes, mixTitles: mixTitles, ownView: true
        )
        screen.continueListening = listens
            .filter { $0.status == "playing" }
            .prefix(4)
            .compactMap { row -> ContinueRow? in
                guard let t = refTitle(row.content_ref, episodesByRef: episodes, mixTitles: mixTitles) else { return nil }
                let mins = max(1, (row.progress_seconds ?? 0) / 60)
                return ContinueRow(id: row.content_ref, title: t.title, href: t.href, minutesIn: mins)
            }
        return screen
    }

    // MARK: - Primitive reads

    static func profileRow(_ id: String) async -> ProfileRow? {
        try? await Supa.client.from("profiles")
            .select("id, display_name, avatar_url, created_at").eq("id", value: id).firstRow(ProfileRow.self)
    }

    static func profileDetails(_ id: String) async -> ProfileDetails? {
        try? await Supa.client.from("profile_details")
            .select("is_public, bio, status_line, profile_song_ref, theme").eq("id", value: id)
            .firstRow(ProfileDetails.self)
    }

    static func connections(_ userID: String) async -> [Connection] {
        (try? await Supa.client.from("connections")
            .select("id, kind, name, image_url, link_url, position, created_at")
            .eq("user_id", value: userID).order("position", ascending: true)
            .execute().value) ?? []
    }

    static func userContent(_ userID: String, publishedOnly: Bool) async -> UserContent {
        func table(_ name: String) async -> [ContentRow] {
            do {
                var q = Supa.client.from(name).select("id, title, status, created_at").eq("user_id", value: userID)
                if publishedOnly { q = q.eq("status", value: "published") }
                return try await q.order("created_at", ascending: false).limit(8).execute().value
            } catch { return [] }
        }
        async let m = table("user_uploads")
        async let p = table("posts")
        async let l = table("lists")
        async let a = table("photo_albums")
        return await UserContent(mixes: m, posts: p, lists: l, albums: a)
    }

    private struct FavRow: Decodable { let content_ref: String; let created_at: String? }
    private struct ListenRow: Decodable { let content_ref: String; let status: String; let progress_seconds: Int?; let updated_at: String? }

    private static func recentFavorites() async -> [FavRow] {
        (try? await Supa.client.from("favorites")
            .select("content_ref, created_at").order("created_at", ascending: false).limit(15)
            .execute().value) ?? []
    }
    private static func recentListens() async -> [ListenRow] {
        (try? await Supa.client.from("listen_status")
            .select("content_ref, status, progress_seconds, updated_at").order("updated_at", ascending: false).limit(15)
            .execute().value) ?? []
    }

    // MARK: - Wall (profile.md §9)

    static func wallEntries(profileID: String, viewerID: String?) async -> [WallEntry] {
        let rows: [WallCommentRow] = (try? await Supa.client.from("wall_comments")
            .select("id, author_id, body, created_at")
            .eq("profile_id", value: profileID).eq("status", value: "published")
            .order("created_at", ascending: false).limit(30)
            .execute().value) ?? []
        guard !rows.isEmpty else { return [] }
        let authorIDs = rows.map(\.authorID)
        let names = await UGCService.displayNames(authorIDs)
        let publicIDs = await UGCService.publicProfileIds(authorIDs)
        return rows.map { r in
            WallEntry(
                id: r.id, authorID: r.authorID, body: r.body, createdAt: r.createdAt,
                authorName: names[r.authorID] ?? "a listener",
                authorIsPublic: publicIDs.contains(r.authorID),
                canRemove: viewerID == profileID || viewerID == r.authorID
            )
        }
    }

    /// Post a wall note. 42501 → private wall or a block between the parties.
    static func postWallComment(profileID: String, body: String) async -> Result<Void, QCError> {
        guard let me = uid else { return .failure("Sign in to post.") }
        let trimmed = String(body.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1000))
        guard !trimmed.isEmpty else { return .failure("Write something first.") }
        do {
            try await Supa.client.from("wall_comments")
                .insert(WallInsert(profile_id: profileID, author_id: me, body: trimmed)).execute()
            return .success(())
        } catch {
            return .failure(Supa.isRLSRefusal(error) ? "This wall isn't open to you." : "Could not post — try again.")
        }
    }

    static func deleteWallComment(id: String) async -> Bool {
        do {
            try await Supa.client.from("wall_comments").delete().eq("id", value: id).execute()
            return true
        } catch { return false }
    }

    // MARK: - Block (Apple UGC requirement, guideline 1.2)

    static func blockUser(_ blockedID: String) async -> Bool {
        guard let me = uid, me != blockedID else { return false }
        do {
            try await Supa.client.from("blocks")
                .insert(["blocker_id": me, "blocked_id": blockedID]).execute()
            return true
        } catch {
            return Supa.isUniqueViolation(error)   // already blocked = success
        }
    }

    // MARK: - Settings writes (auth-account.md §5)

    /// save-profile: profiles.display_name UPDATE + profile_details upsert (status/bio/song).
    static func saveProfile(displayName: String, statusLine: String, bio: String, songRef: String?) async -> Result<Void, QCError> {
        guard let me = uid else { return .failure("Sign in first.") }
        let name = String(displayName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
        guard !name.isEmpty else { return .failure("A display name is required.") }
        do {
            try await Supa.client.from("profiles").update(["display_name": name]).eq("id", value: me).execute()
            let ok = await upsertDetails([
                "status_line": jsonOrNull(statusLine, max: 140),
                "bio": jsonOrNull(bio, max: 2000),
                "profile_song_ref": songRef.map(AnyJSON.string) ?? .null,
            ])
            return ok ? .success(()) : .failure("Could not save — has the 0003 migration run?")
        } catch {
            return .failure("Could not save your profile — try again.")
        }
    }

    static func savePrivacy(isPublic: Bool) async -> Bool {
        await upsertDetails(["is_public": .bool(isPublic)])
    }

    static func saveTheme(_ theme: QCTheme) async -> Bool {
        await upsertDetails(["theme": .string(theme.rawValue)])
    }

    private static func upsertDetails(_ fields: [String: AnyJSON]) async -> Bool {
        guard let me = uid else { return false }
        var payload = fields
        payload["id"] = .string(me)
        payload["updated_at"] = .string(ISO8601DateFormatter().string(from: Date()))
        do {
            try await Supa.client.from("profile_details").upsert(payload).execute()
            return true
        } catch { return false }
    }

    private static func jsonOrNull(_ s: String, max: Int) -> AnyJSON {
        let t = String(s.trimmingCharacters(in: .whitespacesAndNewlines).prefix(max))
        return t.isEmpty ? .null : .string(t)
    }

    // MARK: - Profile song + mix-title resolution (profile.ts:151-278)

    static func resolveTrack(_ ref: String, episodesByRef: [String: Episode]) async -> Track? {
        if let ep = episodesByRef[ref] { return ep.track }
        guard ContentRef.isUUID(ref) else { return nil }
        struct MixRow: Decodable { let id: String; let title: String; let r2_key: String; let cover_r2_key: String? }
        let mix: MixRow? = try? await Supa.client.from("user_uploads")
            .select("id, title, r2_key, cover_r2_key").eq("id", value: ref).firstRow(MixRow.self)
        guard let mix else { return nil }
        return Track(
            id: mix.id, title: mix.title, artist: "Listener mix",
            cover: mix.cover_r2_key.map(Config.cdn) ?? "",
            src: Config.cdn(mix.r2_key), catalog: nil
        )
    }

    static func resolveMixTitles(_ refs: [String]) async -> [String: String] {
        let ids = Array(Set(refs.filter(ContentRef.isUUID)))
        guard !ids.isEmpty else { return [:] }
        struct Row: Decodable { let id: String; let title: String }
        let rows: [Row] = (try? await Supa.client.from("user_uploads")
            .select("id, title").in("id", values: ids).execute().value) ?? []
        return Dictionary(rows.map { ($0.id, $0.title) }, uniquingKeysWith: { a, _ in a })
    }

    private static func resolveMixTitles(refsIn content: UserContent) async -> [String: String] {
        await resolveMixTitles(contentRefs(content))
    }

    private static func contentRefs(_ c: UserContent) -> [String] {
        (c.mixes + c.posts + c.lists + c.albums).map(\.id)
    }

    // MARK: - Site news (profile.ts:225-256)

    static func siteNews(episodesByRef: [String: Episode]) async -> [SiteNewsItem] {
        let episodes = episodesByRef.values.sorted { $0.cat > $1.cat }
        var items: [SiteNewsItem] = episodes.prefix(3).map {
            SiteNewsItem(kind: .broadcast, title: "\($0.catLabel) — \($0.title)", href: "/show/\($0.slug)", at: $0.airDate ?? "")
        }
        struct NewsRow: Decodable { let id: String; let title: String; let created_at: String? }
        func recent(_ table: String) async -> [NewsRow] {
            (try? await Supa.client.from(table).select("id, title, created_at")
                .eq("status", value: "published").order("created_at", ascending: false).limit(4)
                .execute().value) ?? []
        }
        async let m = recent("user_uploads")
        async let p = recent("posts")
        async let l = recent("lists")
        async let a = recent("photo_albums")
        var community: [SiteNewsItem] = []
        community += (await m).map { SiteNewsItem(kind: .mixtape, title: $0.title, href: "/mixes/\($0.id)", at: $0.created_at ?? "") }
        community += (await p).map { SiteNewsItem(kind: .writing, title: $0.title, href: "/posts/\($0.id)", at: $0.created_at ?? "") }
        community += (await l).map { SiteNewsItem(kind: .list, title: $0.title, href: "/lists/\($0.id)", at: $0.created_at ?? "") }
        community += (await a).map { SiteNewsItem(kind: .photos, title: $0.title, href: "/photos/\($0.id)", at: $0.created_at ?? "") }
        community.sort { $0.at > $1.at }
        return items + Array(community.prefix(5))
    }

    // MARK: - Activity (profile.ts:170-219)

    private static func refTitle(_ ref: String, episodesByRef: [String: Episode], mixTitles: [String: String]) -> (title: String, href: String)? {
        if let ep = episodesByRef[ref] { return (ep.title, "/show/\(ep.slug)") }
        if ContentRef.isUUID(ref), let t = mixTitles[ref] { return (t, "/mixes/\(ref)") }
        return nil
    }

    private static func buildActivity(
        content: UserContent,
        favorites: [FavRow], listens: [ListenRow],
        connections: [Connection], wall: [WallEntry],
        episodesByRef: [String: Episode], mixTitles: [String: String], ownView: Bool
    ) -> [ActivityEvent] {
        var events: [ActivityEvent] = []
        func note(_ status: String) -> String? { (ownView && status != "published") ? status : nil }

        for m in content.mixes { events.append(.init(kind: .mixtape, text: "Uploaded “\(m.title)”", href: "/mixes/\(m.id)", at: m.createdAt ?? "", note: note(m.status))) }
        for p in content.posts { events.append(.init(kind: .writing, text: "Posted “\(p.title)”", href: "/posts/\(p.id)", at: p.createdAt ?? "", note: note(p.status))) }
        for l in content.lists { events.append(.init(kind: .list, text: "Made the list “\(l.title)”", href: "/lists/\(l.id)", at: l.createdAt ?? "", note: note(l.status))) }
        for a in content.albums { events.append(.init(kind: .photos, text: "Shared “\(a.title)”", href: "/photos/\(a.id)", at: a.createdAt ?? "", note: note(a.status))) }

        if ownView {
            for f in favorites {
                if let t = refTitle(f.content_ref, episodesByRef: episodesByRef, mixTitles: mixTitles) {
                    events.append(.init(kind: .favorite, text: "Favorited “\(t.title)”", href: t.href, at: f.created_at ?? "", note: nil))
                }
            }
            for l in listens where l.status == "playing" || l.status == "played" {
                if let t = refTitle(l.content_ref, episodesByRef: episodesByRef, mixTitles: mixTitles) {
                    let verb = l.status == "played" ? "Finished" : "Listening to"
                    events.append(.init(kind: .listening, text: "\(verb) “\(t.title)”", href: t.href, at: l.updated_at ?? "", note: nil))
                }
            }
        }
        for c in connections { events.append(.init(kind: .rotation, text: "Pinned \(c.name) to the rotation", href: c.linkURL, at: c.createdAt ?? "", note: nil)) }
        for w in wall { events.append(.init(kind: .wall, text: "Got a wall note from \(w.authorName)", href: "#wall", at: w.createdAt ?? "", note: nil)) }

        return events.sorted { $0.at > $1.at }.prefix(12).map { $0 }
    }

    private struct WallInsert: Encodable { let profile_id: String; let author_id: String; let body: String }
}
