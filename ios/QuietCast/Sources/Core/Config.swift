import Foundation

/// Client-safe configuration. These mirror the web app's PUBLIC_* env vars (auth-account.md §1,
/// content-sanity.md §1). The Supabase anon key and Sanity reads are public by design — RLS and
/// the published perspective are the security boundary, not key secrecy.
enum Config {
    // Supabase (auth-account.md §1)
    static let supabaseURL = URL(string: "https://zzftxvxgnkuowipeylen.supabase.co")!
    static let supabaseAnonKey = "sb_publishable_7KYvjvCf_JN9r_jFuIGJWA_LAQmLgRh"

    // Sanity content CDN (content-sanity.md §1)
    static let sanityProjectID = "vcfngr79"
    static let sanityDataset = "production"
    static let sanityAPIVersion = "2025-01-01"
    /// apicdn host because the web client uses useCdn:true (content-sanity.md §1.1)
    static var sanityQueryBase: URL {
        URL(string: "https://\(sanityProjectID).apicdn.sanity.io/v\(sanityAPIVersion)/data/query/\(sanityDataset)")!
    }

    // R2 public read CDN for UGC bytes (ugc.md §1)
    static let cdnURL = "https://cdn.quietcast.art"

    /// Public read URL for an R2 object key. cdnUrl(key) ≡ <base>/<key> (ugc.ts:33-36).
    /// NOTE: profiles.avatar_url and connections.image_url already store the FULL url — do not
    /// double-prefix those (ugc.md §1 "Important storage convention").
    static func cdn(_ key: String) -> String {
        cdnURL.replacingOccurrences(of: "/+$", with: "", options: .regularExpression) + "/" + key
    }

    /// Astro web app base — host for the iOS-facing /api/account/delete endpoint (SHIP.md sets the
    /// production value). Overridable for local testing via the QC_WEB_BASE env var.
    static var webAppBase: URL {
        if let raw = ProcessInfo.processInfo.environment["QC_WEB_BASE"], let u = URL(string: raw) {
            return u
        }
        return URL(string: "https://quietcast.art")!
    }
}
