import Foundation

// MARK: - Episode (Sanity content) — content-sanity.md §3.4

/// A Quiet Cast episode (legacy `interview` doc). Mapping rules applied in SanityService.
struct Episode: Identifiable, Hashable {
    var cat: Int
    var catLabel: String          // "QC—013" (U+2014 em dash, 3-digit pad)
    var slug: String              // cross-system primary key (content_ref, route param)
    var title: String             // name with "Quiet Cast NNN:" prefix stripped
    var artist: String
    var description: String
    var coverURL: String?
    var audioURL: String?
    var airDate: String?          // "YYYY-MM-DD" (UTC string slice, never timezone-parsed)
    var year: String?             // "YYYY"
    var tracklist: [String]
    var qa: [QAPair]

    var id: String { slug }
}

struct QAPair: Hashable {
    var q: String
    var a: String
}

// MARK: - Track (playback unit) — playback.md §1

/// The single playable unit (dock, queues, profile song). `id` IS the Supabase content_ref:
/// episode slug for Sanity episodes, user_uploads UUID for mixes. Never invent ids.
struct Track: Identifiable, Hashable {
    var id: String
    var title: String
    var artist: String
    var cover: String             // may be "" — falls back to bundled placeholder
    var src: String               // absolute audio URL (cdn.sanity.io or cdn.quietcast.art)
    var catalog: String?
    var durationLabel: String?
}

extension Episode {
    /// trackOf(e) — content.ts:105-114. Cover requested at 160 (dock); larger sizes for now-playing
    /// are requested separately via Sanity sizedCover params.
    var track: Track {
        Track(
            id: slug,
            title: title,
            artist: artist,
            cover: Sanity.sizedCover(coverURL, 160) ?? "",
            src: audioURL ?? "",
            catalog: catLabel
        )
    }
}

// MARK: - Listen state — listen-library.md §4.2

enum ListenState: String {
    case unplayed
    case inProgress
    case done

    /// stateFromStatus (listen.ts:45-49): played→done, playing→in-progress, else unplayed.
    init(status: String?) {
        switch status {
        case "played": self = .done
        case "playing": self = .inProgress
        default: self = .unplayed
        }
    }
}

struct ListenProgress {
    var status: String            // 'unplayed' | 'playing' | 'played'
    var progressSeconds: Int
}

// MARK: - Profile — profile.md, auth-account.md §4

struct ProfileRow: Decodable, Hashable {
    var id: String
    var displayName: String?
    var avatarURL: String?
    var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case avatarURL = "avatar_url"
        case createdAt = "created_at"
    }
}

struct ProfileDetails: Decodable, Hashable {
    var isPublic: Bool
    var bio: String?
    var statusLine: String?
    var profileSongRef: String?
    var theme: String             // 'dark' | 'light'

    enum CodingKeys: String, CodingKey {
        case isPublic = "is_public"
        case bio
        case statusLine = "status_line"
        case profileSongRef = "profile_song_ref"
        case theme
    }

    /// Defaults for a missing row (auth-account.md §4.2: treat absence as private/dark).
    static let absent = ProfileDetails(isPublic: false, bio: nil, statusLine: nil, profileSongRef: nil, theme: "dark")
}

// MARK: - Connection (rotation grid) — profile.md §6

/// CONNECTION_KINDS verbatim (connections.ts:14-22).
enum ConnectionKind: String, CaseIterable {
    case artist, label, venue, podcast, photographer, listener, other
}

let MAX_CONNECTIONS = 12

struct Connection: Decodable, Identifiable, Hashable {
    var id: String
    var kind: String              // raw string (rendered as a chip); may be any of CONNECTION_KINDS
    var name: String
    var imageURL: String?         // full CDN url (or snapshot avatar for listener pins)
    var linkURL: String?          // "/..." = in-app; other = off-site; nil = not tappable
    var position: Int
    var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, kind, name, position
        case imageURL = "image_url"
        case linkURL = "link_url"
        case createdAt = "created_at"
    }

    /// Off-site tile links open in Safari; in-app links (listener pins, "/u/<id>") navigate.
    var isOffsite: Bool { (linkURL?.isEmpty == false) && !(linkURL!.hasPrefix("/")) }
}

// MARK: - UGC summaries (community shelf) — ugc.md §7

struct MixSummary: Decodable, Identifiable, Hashable {
    var id: String
    var userID: String
    var title: String
    var coverR2Key: String?
    var duration: Int?
    var createdAt: String?
    enum CodingKeys: String, CodingKey {
        case id, title, duration
        case userID = "user_id"
        case coverR2Key = "cover_r2_key"
        case createdAt = "created_at"
    }
}

struct PostSummary: Decodable, Identifiable, Hashable {
    var id: String
    var userID: String
    var title: String
    var createdAt: String?
    enum CodingKeys: String, CodingKey {
        case id, title
        case userID = "user_id"
        case createdAt = "created_at"
    }
}

struct ListSummary: Decodable, Identifiable, Hashable {
    var id: String
    var userID: String
    var title: String
    var description: String?
    var createdAt: String?
    enum CodingKeys: String, CodingKey {
        case id, title, description
        case userID = "user_id"
        case createdAt = "created_at"
    }
}

struct AlbumSummary: Decodable, Identifiable, Hashable {
    var id: String
    var userID: String
    var title: String
    var venue: String?
    var eventDate: String?
    var createdAt: String?
    var photos: [PhotoRef]?
    enum CodingKeys: String, CodingKey {
        case id, title, venue, photos
        case userID = "user_id"
        case eventDate = "event_date"
        case createdAt = "created_at"
    }
}

struct PhotoRef: Decodable, Hashable {
    var r2Key: String
    var position: Int
    enum CodingKeys: String, CodingKey {
        case position
        case r2Key = "r2_key"
    }
}

// MARK: - UGC details

struct MixDetail: Decodable, Identifiable, Hashable {
    var id: String
    var userID: String
    var title: String
    var description: String?
    var coverR2Key: String?
    var tracklist: [String]?
    var r2Key: String
    var duration: Int?
    var status: String
    var createdAt: String?
    enum CodingKeys: String, CodingKey {
        case id, title, description, tracklist, duration, status
        case userID = "user_id"
        case coverR2Key = "cover_r2_key"
        case r2Key = "r2_key"
        case createdAt = "created_at"
    }
}

struct PostDetail: Decodable, Identifiable, Hashable {
    var id: String
    var userID: String
    var title: String
    var bodyMd: String?
    var status: String
    var createdAt: String?
    enum CodingKeys: String, CodingKey {
        case id, title, status
        case userID = "user_id"
        case bodyMd = "body_md"
        case createdAt = "created_at"
    }
}

struct ListItem: Decodable, Identifiable, Hashable {
    var id: String
    var itemType: String
    var title: String
    var note: String?
    var url: String?
    var position: Int
    enum CodingKeys: String, CodingKey {
        case id, title, note, url, position
        case itemType = "item_type"
    }
}

struct ListDetail: Decodable, Identifiable, Hashable {
    var id: String
    var userID: String
    var title: String
    var description: String?
    var status: String
    var createdAt: String?
    var listItems: [ListItem]?
    enum CodingKeys: String, CodingKey {
        case id, title, description, status
        case userID = "user_id"
        case createdAt = "created_at"
        case listItems = "list_items"
    }
}

struct PhotoItem: Decodable, Identifiable, Hashable {
    var id: String
    var r2Key: String
    var caption: String?
    var position: Int
    enum CodingKeys: String, CodingKey {
        case id, caption, position
        case r2Key = "r2_key"
    }
}

struct AlbumDetail: Decodable, Identifiable, Hashable {
    var id: String
    var userID: String
    var title: String
    var venue: String?
    var eventDate: String?
    var description: String?
    var status: String
    var createdAt: String?
    var photos: [PhotoItem]?
    enum CodingKeys: String, CodingKey {
        case id, title, venue, description, status, photos
        case userID = "user_id"
        case eventDate = "event_date"
        case createdAt = "created_at"
    }
}

// MARK: - Wall — profile.md §9

struct WallCommentRow: Decodable, Identifiable, Hashable {
    var id: String
    var authorID: String
    var body: String
    var createdAt: String?
    enum CodingKeys: String, CodingKey {
        case id, body
        case authorID = "author_id"
        case createdAt = "created_at"
    }
}

/// A wall comment with its byline resolved (display name + whether to link to /u/<author>).
struct WallEntry: Identifiable, Hashable {
    var id: String
    var authorID: String
    var body: String
    var createdAt: String?
    var authorName: String        // fallback "a listener"
    var authorIsPublic: Bool      // link the byline only when true
    var canRemove: Bool           // viewer is wall owner or the author
}

// MARK: - Activity + site news — profile.md §7, §8

enum ActivityKind: String {
    case mixtape, writing, list, photos, favorite, listening, rotation, wall, broadcast
}

struct ActivityEvent: Identifiable, Hashable {
    var id = UUID()
    var kind: ActivityKind
    var text: String
    var href: String?
    var at: String                // ISO timestamp (string-compare sorted desc)
    var note: String?             // own view only: 'private' / 'removed'
}

struct SiteNewsItem: Identifiable, Hashable {
    var id = UUID()
    var kind: ActivityKind
    var title: String
    var href: String
    var at: String
}
