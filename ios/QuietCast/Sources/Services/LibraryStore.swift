import Foundation
import Observation
import Supabase

/// Favorites + listen-state, mirroring the web's session-cached merge pattern (listen-library.md §5):
/// fetch the user's whole favorites Set and listen_status map once, hold them in memory, default
/// to not-favorite / unplayed, and update optimistically on each write (never refetch per write).
@MainActor
@Observable
final class LibraryStore {
    private(set) var favorites: Set<String> = []
    private(set) var listen: [String: ListenState] = [:]
    private(set) var progressByRef: [String: Int] = [:]   // resume points for "Continue listening"

    private var loaded = false

    private var uid: String? { Supa.client.auth.currentUser?.id.uuidString.lowercased() }

    /// Load (or reload) the whole state. No-op when logged out — everything stays empty.
    func load(force: Bool = false) async {
        guard uid != nil else { clear(); return }
        if loaded && !force { return }
        async let favs = fetchFavorites()
        async let states = fetchStates()
        favorites = await favs
        let (map, prog) = await states
        listen = map
        progressByRef = prog
        loaded = true
    }

    func clear() {
        favorites = []
        listen = [:]
        progressByRef = [:]
        loaded = false
    }

    func isFavorite(_ ref: String) -> Bool { favorites.contains(ref) }
    func state(for ref: String) -> ListenState { listen[ref] ?? .unplayed }

    /// Optimistic favorite toggle with rollback (library.ts:83-111). Returns the new state.
    @discardableResult
    func toggleFavorite(_ ref: String) async -> Bool {
        guard let uid else { return false }
        let wasFav = favorites.contains(ref)
        let next = !wasFav
        if next { favorites.insert(ref) } else { favorites.remove(ref) }   // optimistic

        do {
            if next {
                do {
                    try await Supa.client.from("favorites")
                        .insert(["user_id": uid, "content_ref": ref]).execute()
                } catch {
                    // unique(user_id, content_ref): a duplicate just means it's already saved.
                    if !Supa.isUniqueViolation(error) { throw error }
                }
            } else {
                try await Supa.client.from("favorites")
                    .delete().eq("content_ref", value: ref).execute()
            }
            return next
        } catch {
            // revert
            if wasFav { favorites.insert(ref) } else { favorites.remove(ref) }
            return wasFav
        }
    }

    // MARK: - Listen progress (called by the audio player) — listen-library.md §4.3, playback.md §6

    static let doneRatio = 0.9
    static let minRecordSeconds = 5.0

    /// recordProgress (listen.ts:52-81): skip <5s or logged out; status='played' iff ratio>=0.9;
    /// upsert on (user_id, content_ref) with floored seconds + client ISO updated_at.
    func recordProgress(ref: String, progressSeconds: Double, durationSeconds: Double) async {
        guard let uid, progressSeconds.isFinite, progressSeconds >= Self.minRecordSeconds else { return }
        let done = durationSeconds > 0 && progressSeconds / durationSeconds >= Self.doneRatio
        let status = done ? "played" : "playing"
        let payload = ListenUpsert(
            user_id: uid,
            content_ref: ref,
            status: status,
            progress_seconds: Int(progressSeconds.rounded(.down)),
            updated_at: ISO8601DateFormatter().string(from: Date())
        )
        do {
            try await Supa.client.from("listen_status")
                .upsert(payload, onConflict: "user_id,content_ref").execute()
            listen[ref] = ListenState(status: status)        // update in-memory map (no refetch)
            progressByRef[ref] = payload.progress_seconds
        } catch {
            // best-effort; playback is not blocked by a failed write
        }
    }

    /// fetchProgress for resume (listen.ts:84-96). RLS + unique constraint guarantee ≤1 row.
    func fetchProgress(ref: String) async -> ListenProgress? {
        guard uid != nil else { return nil }
        do {
            let row: ProgressRow? = try await Supa.client.from("listen_status")
                .select("progress_seconds, status")
                .eq("content_ref", value: ref)
                .firstRow(ProgressRow.self)
            guard let row else { return nil }
            return ListenProgress(status: row.status, progressSeconds: row.progress_seconds)
        } catch {
            return nil
        }
    }

    // MARK: - Fetches

    private func fetchFavorites() async -> Set<String> {
        do {
            let rows: [RefRow] = try await Supa.client.from("favorites")
                .select("content_ref").execute().value
            return Set(rows.map(\.content_ref))
        } catch { return [] }
    }

    private func fetchStates() async -> ([String: ListenState], [String: Int]) {
        do {
            let rows: [StatusRow] = try await Supa.client.from("listen_status")
                .select("content_ref, status, progress_seconds").execute().value
            var map: [String: ListenState] = [:]
            var prog: [String: Int] = [:]
            for r in rows {
                map[r.content_ref] = ListenState(status: r.status)
                prog[r.content_ref] = r.progress_seconds ?? 0
            }
            return (map, prog)
        } catch { return ([:], [:]) }
    }

    // MARK: - Decode/encode shapes

    private struct RefRow: Decodable { let content_ref: String }
    private struct StatusRow: Decodable { let content_ref: String; let status: String; let progress_seconds: Int? }
    private struct ProgressRow: Decodable { let progress_seconds: Int; let status: String }
    private struct ListenUpsert: Encodable {
        let user_id: String
        let content_ref: String
        let status: String
        let progress_seconds: Int
        let updated_at: String
    }
}
