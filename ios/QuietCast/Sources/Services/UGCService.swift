import Foundation
import Supabase

/// Community UGC reads + report/visibility writes + byline resolution (ugc.md §6-9).
/// All reads run with the anon key (+ JWT when signed in); RLS does the filtering. "Not found" and
/// "not visible to you" are indistinguishable — detail fetches return nil for both.
enum UGCService {
    // MARK: - Community shelf (each: status=published, created_at desc, limit 12)

    static func mixes() async -> [MixSummary] {
        await rows {
            try await Supa.client.from("user_uploads")
                .select("id, user_id, title, cover_r2_key, duration, created_at")
                .eq("status", value: "published").order("created_at", ascending: false).limit(12)
                .execute().value
        }
    }

    static func posts() async -> [PostSummary] {
        await rows {
            try await Supa.client.from("posts")
                .select("id, user_id, title, created_at")
                .eq("status", value: "published").order("created_at", ascending: false).limit(12)
                .execute().value
        }
    }

    static func lists() async -> [ListSummary] {
        await rows {
            try await Supa.client.from("lists")
                .select("id, user_id, title, description, created_at")
                .eq("status", value: "published").order("created_at", ascending: false).limit(12)
                .execute().value
        }
    }

    static func albums() async -> [AlbumSummary] {
        await rows {
            try await Supa.client.from("photo_albums")
                .select("id, user_id, title, venue, event_date, created_at, photos(r2_key, position)")
                .eq("status", value: "published").order("created_at", ascending: false).limit(12)
                .execute().value
        }
    }

    // MARK: - Details (lookup by id; RLS decides visibility → nil when not visible)

    static func mix(id: String) async -> MixDetail? {
        await maybe {
            try await Supa.client.from("user_uploads")
                .select("id, user_id, title, description, cover_r2_key, tracklist, r2_key, duration, status, created_at")
                .eq("id", value: id).firstRow(MixDetail.self)
        }
    }

    static func post(id: String) async -> PostDetail? {
        await maybe {
            try await Supa.client.from("posts")
                .select("id, user_id, title, body_md, status, created_at")
                .eq("id", value: id).firstRow(PostDetail.self)
        }
    }

    static func list(id: String) async -> ListDetail? {
        await maybe {
            try await Supa.client.from("lists")
                .select("id, user_id, title, description, status, created_at, list_items(id, item_type, title, note, url, position)")
                .eq("id", value: id).firstRow(ListDetail.self)
        }
    }

    static func album(id: String) async -> AlbumDetail? {
        await maybe {
            try await Supa.client.from("photo_albums")
                .select("id, user_id, title, venue, event_date, description, status, created_at, photos(id, r2_key, caption, position)")
                .eq("id", value: id).firstRow(AlbumDetail.self)
        }
    }

    // MARK: - Byline resolution (ugc.ts:99-136)

    /// profiles.display_name for ids; fallback handled at call sites with "a listener".
    static func displayNames(_ ids: [String]) async -> [String: String] {
        let unique = Array(Set(ids))
        guard !unique.isEmpty else { return [:] }
        do {
            let rows: [NameRow] = try await Supa.client.from("profiles")
                .select("id, display_name").in("id", values: unique).execute().value
            var map: [String: String] = [:]
            for r in rows { if let n = r.display_name, !n.isEmpty { map[r.id] = n } }
            return map
        } catch { return [:] }
    }

    /// The subset of ids whose profile is public — only these bylines link to /u/<id>.
    static func publicProfileIds(_ ids: [String]) async -> Set<String> {
        let unique = Array(Set(ids))
        guard !unique.isEmpty else { return [] }
        do {
            let rows: [IDRow] = try await Supa.client.from("profile_details")
                .select("id").in("id", values: unique).eq("is_public", value: true).execute().value
            return Set(rows.map(\.id))
        } catch { return [] }
    }

    // MARK: - Report + visibility (report.ts:10-54)

    enum ContentType: String { case upload, post, list, photo_album, wall_comment }

    /// handleReport: insert {reporter_id, content_type, content_ref, reason(trim, ≤1000)}.
    static func report(contentType: ContentType, contentRef: String, reason: String) async -> Result<String, QCError> {
        guard let uid = Supa.client.auth.currentUser?.id.uuidString.lowercased() else {
            return .failure("Sign in to report content.")
        }
        let trimmed = String(reason.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1000))
        guard !trimmed.isEmpty else { return .failure("Say briefly what the problem is.") }
        do {
            try await Supa.client.from("reports").insert(ReportInsert(
                reporter_id: uid, content_type: contentType.rawValue, content_ref: contentRef, reason: trimmed
            )).execute()
            return .success("Reported — the curator will take a look.")
        } catch {
            return .failure("Could not file the report — try again.")
        }
    }

    enum VisibilityTable: String { case user_uploads, posts, lists, photo_albums }

    /// setVisibility: update {status} eq id eq user_id, requesting the row back so the silent
    /// zero-row refusal on a removed/non-owned row is detected (supabase-rls.md §Silent-refusal).
    /// Returns nil on success, an error string otherwise, and .removed when the row is locked.
    enum VisibilityOutcome: Equatable { case ok, locked, error(String) }

    static func setVisibility(table: VisibilityTable, id: String, published: Bool) async -> VisibilityOutcome {
        guard let uid = Supa.client.auth.currentUser?.id.uuidString.lowercased() else { return .error("Sign in first.") }
        let next = published ? "published" : "private"
        do {
            let updated: [IDRow] = try await Supa.client.from(table.rawValue)
                .update(["status": next]).eq("id", value: id).eq("user_id", value: uid)
                .select("id").execute().value
            return updated.isEmpty ? .locked : .ok    // 0 rows = removed/locked, no error raised
        } catch {
            return .error("Could not change visibility — try again.")
        }
    }

    // MARK: - Plumbing

    private static func rows<T>(_ op: () async throws -> [T]) async -> [T] {
        (try? await op()) ?? []
    }
    private static func maybe<T>(_ op: () async throws -> T?) async -> T? {
        (try? await op()) ?? nil
    }

    private struct NameRow: Decodable { let id: String; let display_name: String? }
    private struct IDRow: Decodable { let id: String }
    private struct ReportInsert: Encodable {
        let reporter_id: String
        let content_type: String
        let content_ref: String
        let reason: String
    }
}
