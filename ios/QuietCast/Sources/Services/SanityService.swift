import Foundation

/// Read-only Sanity content layer (content-sanity.md). Unauthenticated GETs to the apicdn host;
/// GROQ + the air-date coalesce quirk are isolated here — the single seam for the planned Phase-3
/// document remodel.
actor SanityService {
    static let shared = SanityService()

    private let session = URLSession(configuration: .default)
    private var cache: [Episode]?

    // Verbatim filter + projection (content.ts:46-61, 89-93).
    private static let filter = #"_type == "interview" && defined(slug.current) && defined(audio.asset)"#
    private static let qaProjection: String = {
        let pairs = (1...20).map { #"{"q": question\#($0), "a": answer\#($0)}"# }.joined(separator: ", ")
        return #""qa": [\#(pairs)]"#
    }()
    private static var projection: String {
        #"{cat, name, "slug": slug.current, artist, description, "coverUrl": cover.asset->url, "audioUrl": audio.asset->url, "airDate": coalesce(date, _createdAt), tracklist, \#(qaProjection)}"#
    }

    /// getEpisodes() — entire catalog, cat desc. Cached for the session.
    func episodes(force: Bool = false) async throws -> [Episode] {
        if !force, let cache { return cache }
        let groq = "*[\(Self.filter)] | order(cat desc) \(Self.projection)"
        let raw: [RawEpisode] = try await query(groq, decode: [RawEpisode].self) ?? []
        let mapped = raw.map(Self.map)
        cache = mapped
        return mapped
    }

    /// getEpisode(slug) — single doc or nil.
    func episode(slug: String) async throws -> Episode? {
        let groq = "*[\(Self.filter) && slug.current == $slug][0] \(Self.projection)"
        let raw: RawEpisode? = try await query(groq, params: ["slug": "\"\(slug)\""], decode: RawEpisode.self)
        return raw.map(Self.map)
    }

    /// Convenience: slug → Episode index (used by activity/news/profile-song resolution).
    func episodeIndex(force: Bool = false) async throws -> [String: Episode] {
        let list = try await episodes(force: force)
        return Dictionary(list.map { ($0.slug, $0) }, uniquingKeysWith: { a, _ in a })
    }

    // MARK: - Transport

    private func query<T: Decodable>(_ groq: String, params: [String: String] = [:], decode: T.Type) async throws -> T? {
        func enc(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? s }
        var q = "query=\(enc(groq))&perspective=published"
        for (k, v) in params { q += "&\(enc("$\(k)"))=\(enc(v))" }
        let url = URL(string: Config.sanityQueryBase.absoluteString + "?" + q)!
        let (data, _) = try await session.data(from: url)
        let envelope = try JSONDecoder().decode(Envelope<T>.self, from: data)
        return envelope.result
    }

    private struct Envelope<T: Decodable>: Decodable { let result: T? }

    // MARK: - Mapping (content.ts:63-81)

    private static func map(_ r: RawEpisode) -> Episode {
        let cat = r.cat ?? 0
        let qa = (r.qa ?? []).compactMap { pair -> QAPair? in
            guard let q = pair.q?.trimmingCharacters(in: .whitespacesAndNewlines), !q.isEmpty,
                  let a = pair.a?.trimmingCharacters(in: .whitespacesAndNewlines), !a.isEmpty else { return nil }
            return QAPair(q: q, a: a)
        }
        return Episode(
            cat: cat,
            catLabel: Fmt.catLabel(cat),
            slug: r.slug ?? String(cat),
            title: Sanity.strippedTitle(r.name),
            artist: r.artist ?? "Various",
            description: r.description ?? "",
            coverURL: r.coverUrl,
            audioURL: r.audioUrl,
            airDate: r.airDate.map { String($0.prefix(10)) },
            year: r.airDate.map { String($0.prefix(4)) },
            tracklist: r.tracklist?.values ?? [],
            qa: qa
        )
    }
}

// MARK: - Raw decode shapes

private struct RawEpisode: Decodable {
    var cat: Int?
    var name: String?
    var slug: String?
    var artist: String?
    var description: String?
    var coverUrl: String?
    var audioUrl: String?
    var airDate: String?
    var tracklist: LenientStringArray?
    var qa: [RawQA]?
}

private struct RawQA: Decodable {
    var q: String?
    var a: String?
}

/// Decodes a JSON array keeping only string elements (mirrors the web's `typeof t === 'string'`
/// filter, content.ts:76). Non-string entries are skipped, never thrown on.
private struct LenientStringArray: Decodable {
    let values: [String]
    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var out: [String] = []
        while !container.isAtEnd {
            if let s = try? container.decode(String.self) {
                out.append(s)
            } else {
                _ = try? container.decode(AnyCodableSkip.self)
            }
        }
        values = out
    }
}

private struct AnyCodableSkip: Decodable {
    init(from decoder: Decoder) throws {
        if let c = try? decoder.singleValueContainer(), c.decodeNil() { return }
        // consume objects/arrays/numbers/bools without retaining
        if var arr = try? decoder.unkeyedContainer() {
            while !arr.isAtEnd { _ = try? arr.decode(AnyCodableSkip.self) }
        }
    }
}
