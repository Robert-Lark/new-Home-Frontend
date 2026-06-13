import Foundation

// Time, date, and content-ref helpers ported from the web (ugc.md §6, playback.md §5, content-sanity.md).

enum Fmt {
    private static let englishMonths = [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December",
    ]

    /// h:mm:ss when >= 1h else m:ss; seconds always 2-padded; minutes padded only with hours
    /// (PlayerDock.tsx:32-39 / durationLabel ugc.ts:139-146).
    static func clock(_ totalSeconds: Double) -> String {
        guard totalSeconds.isFinite, totalSeconds >= 0 else { return "0:00" }
        let s = Int(totalSeconds)
        let h = s / 3600
        let m = (s % 3600) / 60
        let sec = s % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, sec)
        }
        return String(format: "%d:%02d", m, sec)
    }

    /// durationLabel: integer seconds → "1:24:06"/"54:02"; nil/<=0/non-finite → nil (ugc.ts:139-146).
    static func durationLabel(_ seconds: Int?) -> String? {
        guard let seconds, seconds > 0 else { return nil }
        return clock(Double(seconds))
    }

    /// "11 June 2026" from an ISO timestamp or YYYY-MM-DD string; nil/empty → "" (ugc.ts:149-154).
    /// Parses the leading date textually to avoid timezone day-shift (content-sanity.md §4.1).
    static func ugcDate(_ iso: String?) -> String {
        guard let parts = dateParts(iso) else { return "" }
        return "\(parts.day) \(englishMonths[parts.month - 1]) \(parts.year)"
    }

    /// "June 2026" — member-since stamp (u/[id].astro:124-126).
    static func memberSince(_ iso: String?) -> String {
        guard let parts = dateParts(iso) else { return "" }
        return "\(englishMonths[parts.month - 1]) \(parts.year)"
    }

    private static func dateParts(_ iso: String?) -> (year: Int, month: Int, day: Int)? {
        guard let iso, iso.count >= 10 else { return nil }
        let head = String(iso.prefix(10))           // YYYY-MM-DD
        let comps = head.split(separator: "-")
        guard comps.count == 3,
              let y = Int(comps[0]), let m = Int(comps[1]), let d = Int(comps[2]),
              (1...12).contains(m) else { return nil }
        return (y, m, d)
    }

    /// QC—NNN with U+2014 em dash, 3-digit zero pad (content.ts:67).
    static func catLabel(_ cat: Int) -> String {
        "QC\u{2014}" + String(format: "%03d", cat)
    }
}

/// Episode-slug-or-UUID content_ref convention (supabase-rls.md §Conventions, profile.ts:151).
enum ContentRef {
    private static let uuidRE = try! NSRegularExpression(
        pattern: "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$",
        options: [.caseInsensitive]
    )

    /// true when the ref is a user_uploads UUID; false → treat as a Sanity episode slug.
    /// Never pass a non-uuid into a uuid .in()/.eq() filter.
    static func isUUID(_ ref: String) -> Bool {
        let ns = ref as NSString
        return uuidRE.firstMatch(in: ref, range: NSRange(location: 0, length: ns.length)) != nil
    }
}

// MARK: - Sanity helpers

enum Sanity {
    /// Title strip regex /^\s*quiet\s*cast\s*\d+\s*[:\-–]\s*/i (content.ts:64).
    private static let prefixRE = try! NSRegularExpression(
        pattern: "^\\s*quiet\\s*cast\\s*\\d+\\s*[:\\-\u{2013}]\\s*",
        options: [.caseInsensitive]
    )

    static func strippedTitle(_ name: String?) -> String {
        guard let name else { return "Untitled" }
        let ns = name as NSString
        let stripped = prefixRE.stringByReplacingMatches(
            in: name, range: NSRange(location: 0, length: ns.length), withTemplate: ""
        ).trimmingCharacters(in: .whitespaces)
        if !stripped.isEmpty { return stripped }
        let raw = name.trimmingCharacters(in: .whitespaces)
        return raw.isEmpty ? "Untitled" : raw
    }

    /// sizedCover: append Sanity image-CDN transform params; nil url → nil (content.ts:84-87).
    static func sizedCover(_ url: String?, _ w: Int, _ h: Int? = nil) -> String? {
        guard let url, !url.isEmpty else { return nil }
        return "\(url)?w=\(w)&h=\(h ?? w)&fit=crop&auto=format"
    }
}
