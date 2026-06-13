import Foundation
import Supabase

/// Lightweight error carrying a user-facing message. String-literal-expressible so producers can
/// write `.failure("…")` directly; read at call sites via `error.message`.
struct QCError: Error, ExpressibleByStringLiteral {
    let message: String
    init(_ message: String) { self.message = message }
    init(stringLiteral value: String) { self.message = value }
}

/// Single shared Supabase client: anon (publishable) key + the user's session. RLS is the
/// authorization boundary (supabase-rls.md). The SDK stores the JWT in its own keychain-backed
/// session store — no cookies (auth-account.md §2.2).
enum Supa {
    static let client = SupabaseClient(
        supabaseURL: Config.supabaseURL,
        supabaseKey: Config.supabaseAnonKey
    )

    /// PostgREST/Postgres error code detection. supabase-swift surfaces these in the thrown
    /// PostgrestError; we extract the code defensively (reflection, then description scan) so the
    /// caller can honor the silent-refusal and unique-violation semantics (supabase-rls.md §Silent-refusal).
    static func pgCode(_ error: Error) -> String? {
        let mirror = Mirror(reflecting: error)
        for child in mirror.children where child.label == "code" {
            if let s = child.value as? String { return s }
            if let s = child.value as? String? { return s }
        }
        let desc = String(describing: error)
        for code in ["23505", "42501", "42P01"] where desc.contains(code) { return code }
        return nil
    }

    static func isUniqueViolation(_ error: Error) -> Bool { pgCode(error) == "23505" }
    static func isRLSRefusal(_ error: Error) -> Bool { pgCode(error) == "42501" }
}

/// Helpers to express the web's `.maybeSingle()` (not-found → nil, no throw) on supabase-swift.
extension PostgrestFilterBuilder {
    /// Decode at most one row; nil when none. Avoids `.single()` throwing on zero rows.
    func firstRow<T: Decodable>(_ type: T.Type) async throws -> T? {
        let rows: [T] = try await self.limit(1).execute().value
        return rows.first
    }
}
