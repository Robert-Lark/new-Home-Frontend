# Quiet Cast — Sanity Content Contract (iOS)

Status: verified against the live Sanity CDN on 2026-06-12 (all `curl`/HTTP checks below were run against production and returned the quoted results).
Source of truth in the web app: `src/lib/sanity.ts` (client) and `src/lib/content.ts` (the single content seam — every page goes through it).

This document is self-contained: a Swift engineer can implement the content layer from this file alone.

---

## 1. Connection

| Setting | Value | Source |
|---|---|---|
| Project ID | `vcfngr79` | `astro.config.mjs:69` (default of `PUBLIC_SANITY_PROJECT_ID`); `studio/sanity.json:7` |
| Dataset | `production` | `astro.config.mjs:70`; `studio/sanity.json:8` |
| API version | `2025-01-01` | `src/lib/sanity.ts:16` |
| CDN | `useCdn: true` (read-only, published docs, no token) | `src/lib/sanity.ts:17` |
| Perspective | `published` | `src/lib/sanity.ts:18` |

Client construction, verbatim (`src/lib/sanity.ts:13-19`):

```ts
export const sanity = createClient({
  projectId: PUBLIC_SANITY_PROJECT_ID,
  dataset: PUBLIC_SANITY_DATASET,
  apiVersion: '2025-01-01',
  useCdn: true,
  perspective: 'published',
});
```

No authentication of any kind. There is a `SANITY_API_TOKEN` env var (`astro.config.mjs:71`) but it is server-only, optional, and used by no read path — iOS must NOT embed it.

### 1.1 HTTP endpoint format

Because `useCdn: true`, requests go to the **apicdn** host:

```
GET https://vcfngr79.apicdn.sanity.io/v2025-01-01/data/query/production
      ?perspective=published
      &query=<percent-encoded GROQ>
      [&$paramName=<percent-encoded JSON-encoded value>]
```

- The GROQ string is percent-encoded as a normal URL query value (RFC 3986; `encodeURIComponent` semantics — encode `"`, spaces, `&`, `=`, `+`, `#` etc.). In Swift: `addingPercentEncoding(withAllowedCharacters: .alphanumerics)` is the safe over-encoding, or use `URLComponents.queryItems` (but note `+` must not survive as a literal plus — it decodes to space).
- **Parameters** are passed as extra query items whose *name* is the GROQ variable including the `$` (so the literal query-item name is `$slug`, i.e. `%24slug` on the wire) and whose *value* is the **JSON encoding** of the value — a string parameter is sent with surrounding double quotes: `%24slug=%22subheim%22`.
- Verified live: `...?query=*%5B_type%20%3D%3D%20%22interview%22%20...%5D&%24slug=%22subheim%22` returned `{"result": {"cat": 1, "name": "Quiet Cast 001: Subheim"}}`.
- The full `getEpisodes` query (Section 3) produces a ~1.9 KB URL — comfortably within GET limits. POST fallback is unnecessary for this app.

### 1.2 Response envelope

```json
{
  "query": "<echo of the GROQ>",
  "result": <projection result — array, object, or null>,
  "syncTags": ["s1:..."],
  "ms": 26
}
```

Decode `result` only. A single-document query (`[0]`) returns `result: null` when nothing matches (this is the web app's 404 signal — `src/lib/content.ts:101`).

---

## 2. Document model

### 2.1 One content type: `interview`

There is **no show/category/season hierarchy**. The entire catalog is a flat list of legacy `interview` documents — each one IS an episode (a mix with audio + cover + tracklist + optional Q&A). Stated in the web app's own docs (`src/lib/content.ts:4-9`):

```
A Quiet Cast episode. In the current (legacy) Sanity schema these are stored
as `interview` docs — each is a mix with audio + cover + tracklist + a Q&A.
```

Schema type name `"interview"`: `studio/schemas/interviews.js:2`.

Dataset inventory (verified live with GROQ `count()` / `array::unique(*[]._type)`):
- `interview` docs total: **13**; all 13 match the app's filter (`defined(slug.current) && defined(audio.asset)`); **0** have the optional `date` field set.
- Other types present in the dataset but **never queried by the app**: `artist`, `label`, `release`, `style`, `test` (plus `sanity.imageAsset` / `sanity.fileAsset`). The schema wires `label` and `releases` reference arrays onto interview docs (`studio/schemas/interviews.js:511-522`) — the app ignores them; iOS should too.

### 2.2 Fields the app reads (live-verified on every one of the 13 docs)

| Sanity field | Type | Notes |
|---|---|---|
| `cat` | number | Catalog number 1–13, the de-facto episode ordering key (`studio/schemas/interviews.js:6-10`) |
| `name` | string | e.g. `"Quiet Cast 013: Franz Kirmann"` — display title has the prefix stripped client-side (Section 3.4) |
| `slug` | slug | Read as `slug.current`. **Not uniform**: live values include `subheim` (cat 1), `franz-kirmann` (cat 2), `quiet-cast-013-franz-kirmann` (cat 13). Treat as an opaque unique ID |
| `artist` | string | Present in the live data on all 13 docs (e.g. `"Franz Kirmann"`). NOTE: absent from the checked-in studio schema file — the repo schema (`studio/schemas/interviews.js`) is stale relative to the dataset |
| `description` | text | Plain text |
| `cover` | image | Read as `cover.asset->url`. Also stale vs. repo schema (which has an older `image` field, `interviews.js:32-39`); the live dataset uses `cover` |
| `audio` | file | Read as `audio.asset->url`. Stale vs. repo schema (which has a legacy `url` string field, `interviews.js:40-44`); the live dataset uses `audio` |
| `date` | date | Optional "Air date" (`studio/schemas/interviews.js:25-31`). Schema description: *"Original broadcast/publish date. Drives the Archive calendar; the site falls back to the document's creation date when unset."* Currently unset on all 13 docs |
| `tracklist` | array of strings | e.g. `"Franz Kirmann / Roberto Grosso - In Waves"` |
| `question1..question20` | string | Flat legacy Q&A fields (`interviews.js:51-510`) |
| `answer1..answer20` | text | Paired with questions; answers contain newlines (web renders with `white-space: pre-wrap`, `src/pages/show/[slug].astro:259`, `src/pages/interviews.astro:399`) |

Do not rely on the checked-in studio schema for `artist`/`cover`/`audio`/`tracklist` — they are dataset-verified, not schema-file-verified.

---

## 3. The content API (`src/lib/content.ts`) — every export

### 3.1 Filter and projection (verbatim)

Filter (`src/lib/content.ts:89`):

```groq
_type == "interview" && defined(slug.current) && defined(audio.asset)
```

QA projection — built at module load by a loop over 1..20 (`src/lib/content.ts:46-48`); expanded it is exactly:

```groq
"qa": [
  {"q": question1, "a": answer1},
  {"q": question2, "a": answer2},
  {"q": question3, "a": answer3},
  {"q": question4, "a": answer4},
  {"q": question5, "a": answer5},
  {"q": question6, "a": answer6},
  {"q": question7, "a": answer7},
  {"q": question8, "a": answer8},
  {"q": question9, "a": answer9},
  {"q": question10, "a": answer10},
  {"q": question11, "a": answer11},
  {"q": question12, "a": answer12},
  {"q": question13, "a": answer13},
  {"q": question14, "a": answer14},
  {"q": question15, "a": answer15},
  {"q": question16, "a": answer16},
  {"q": question17, "a": answer17},
  {"q": question18, "a": answer18},
  {"q": question19, "a": answer19},
  {"q": question20, "a": answer20}
]
```

Episode projection (`src/lib/content.ts:50-61`, with `${QA_PROJECTION}` as the last member):

```groq
{
  cat,
  name,
  "slug": slug.current,
  artist,
  description,
  "coverUrl": cover.asset->url,
  "audioUrl": audio.asset->url,
  "airDate": coalesce(date, _createdAt),
  tracklist,
  "qa": [ ...20 pairs as above... ]
}
```

### 3.2 `getEpisodes(): Promise<Episode[]>`

`src/lib/content.ts:91-94`. Full GROQ (filter + order + projection):

```groq
*[_type == "interview" && defined(slug.current) && defined(audio.asset)] | order(cat desc) { ...projection... }
```

No parameters. Returns the entire catalog **newest catalog number first** (cat 13 → 1). Live-verified: 13 rows; raw row keys are exactly `airDate, artist, audioUrl, cat, coverUrl, description, name, qa, slug, tracklist`. The `qa` array always has exactly 20 entries in the raw response; unset pairs come back as `{"q": null, "a": null}` and are filtered client-side (Section 3.4).

### 3.3 `getEpisode(slug: string): Promise<Episode | null>`

`src/lib/content.ts:96-102`. Full GROQ:

```groq
*[_type == "interview" && defined(slug.current) && defined(audio.asset) && slug.current == $slug][0] { ...projection... }
```

One parameter: `$slug` (string), sent as query item `$slug=<JSON string>` per Section 1.1. `result` is a single object or `null`.

### 3.4 `mapEpisode` — raw → `Episode` transformation rules

`src/lib/content.ts:63-81`. The iOS model must reproduce these exactly:

1. **title** — strip the catalog prefix from `name` with this regex (case-insensitive), then trim; if the result is empty fall back to the raw `name`, then to `'Untitled'` (`content.ts:64`):
   ```js
   /^\s*quiet\s*cast\s*\d+\s*[:\-–]\s*/i
   ```
   (Optional whitespace, "quiet cast" with optional internal spaces, digits, then `:`, `-`, or `–`.) Example: `"Quiet Cast 013: Franz Kirmann"` → `"Franz Kirmann"`.
2. **catLabel** — `` `QC—${String(cat ?? 0).padStart(3, '0')}` `` (`content.ts:67`). The dash is **U+2014 EM DASH**, not a hyphen: `QC—013`.
3. **slug** — `r.slug ?? String(r.cat)` (`content.ts:68`); the GROQ filter guarantees slug is present, the fallback is defensive.
4. **artist** — `r.artist ?? 'Various'` (`content.ts:70`).
5. **description** — `r.description ?? ''` (`content.ts:71`).
6. **airDate** — `r.airDate ? r.airDate.slice(0, 10) : null` → `"YYYY-MM-DD"` (`content.ts:74`). See Section 4.
7. **year** — `r.airDate ? r.airDate.slice(0, 4) : null` → `"YYYY"` string (`content.ts:75`).
8. **tracklist** — keep only entries where `typeof t === 'string'`; null array → `[]` (`content.ts:76`).
9. **qa** — keep only pairs where **both** `q` and `a` are truthy (drops the null padding and half-filled pairs), then `trim()` both strings (`content.ts:77-79`).

Resulting `Episode` shape (`src/lib/content.ts:10-29`):

```ts
export interface Episode {
  cat: number;
  catLabel: string;            // "QC—013"
  slug: string;
  title: string;               // name with the "Quiet Cast NNN:" prefix stripped
  artist: string;
  description: string;
  coverUrl: string | null;
  audioUrl: string | null;
  airDate: string | null;      // "YYYY-MM-DD" (UTC); date field or _createdAt
  year: string | null;
  tracklist: string[];
  qa: Array<{ q: string; a: string }>;
}
```

### 3.5 `sizedCover(url, w, h = w): string | undefined`

`src/lib/content.ts:84-87`, verbatim:

```ts
export function sizedCover(url: string | null, w: number, h: number = w): string | undefined {
  if (!url) return undefined;
  return `${url}?w=${w}&h=${h}&fit=crop&auto=format`;
}
```

Appends Sanity image-CDN transform params to the raw asset URL. Sizes used by the web app (logical px; the CDN serves exact-size crops):
- 160 — player dock cover (`content.ts:110`)
- 200 — interview header thumb, displayed at 84×84 (`src/pages/interviews.astro:62`)
- 600 — listen-grid cards (`src/pages/index.astro:32`)
- 900 — show-page hero cover (`src/pages/show/[slug].astro:20`)

For iOS, pass device-pixel sizes (e.g. `w=600&h=600&fit=crop&auto=format` for a 200pt @3x cell). `auto=format` lets the CDN serve WebP/AVIF per the `Accept` header.

### 3.6 `trackOf(e: Episode): Track`

`src/lib/content.ts:105-114`, verbatim:

```ts
export function trackOf(e: Episode): Track {
  return {
    id: e.slug,
    title: e.title,
    artist: e.artist,
    cover: sizedCover(e.coverUrl, 160) ?? '',
    src: e.audioUrl ?? '',
    catalog: e.catLabel,
  };
}
```

`Track` (`src/islands/PlayerDock.tsx:5-15`): `id`, `title`, `artist`, `cover`, `src`, optional `catalog`, optional `durationLabel`. **`Track.id` is the episode `slug`** — this is the cross-system join key: every Supabase user-data row (favorites, playlists, listen state) references episodes by slug via `data-qc-ref={e.slug}` (`src/pages/index.astro:29,53,56`; `src/pages/show/[slug].astro:43,47`; `src/pages/archive.astro:92`). The iOS app must use the slug, not `cat` or `_id`, when talking to Supabase.

---

## 4. Air-date fallback quirk (the archive's load-bearing hack)

### 4.1 Mechanism — GROQ-side coalesce, JS-side truncation

- The fallback happens **in GROQ**, not in JS: `"airDate": coalesce(date, _createdAt)` (`src/lib/content.ts:58`). `date` is a Sanity date (`"YYYY-MM-DD"`); `_createdAt` is a full UTC datetime (`"YYYY-MM-DDTHH:MM:SSZ"`).
- JS then truncates whatever comes back: `.slice(0, 10)` for the day, `.slice(0, 4)` for the year (`content.ts:74-75`). So the day is the **UTC** calendar day of document creation when `date` is unset. iOS must truncate the ISO string textually, NOT parse it into a local-timezone Date first — local-time conversion can shift the day.

### 4.2 Current live state (verified 2026-06-12)

- `count(*[_type == "interview" && defined(date)])` = **0** — every episode's `airDate` currently comes from `_createdAt`.
- The back catalog was bulk-imported, so creation timestamps cluster on the import days. Verified `_createdAt` values:

| cat | `coalesce(date, _createdAt)` | UTC day |
|---|---|---|
| 1 | `2020-12-19T23:19:00Z` | 2020-12-19 |
| 2 | `2020-12-20T21:11:49Z` | 2020-12-20 |
| 3 | `2020-12-30T19:36:38Z` | **2020-12-30** |
| 4 | `2020-12-30T22:03:32Z` | **2020-12-30** |
| 5 | `2020-12-30T23:59:18Z` | **2020-12-30** |
| 6 | `2020-12-31T00:22:14Z` | **2020-12-31** |
| 7 | `2020-12-31T00:52:47Z` | **2020-12-31** |
| 8 | `2020-12-31T00:01:24Z` | **2020-12-31** |
| 9 | `2020-12-31T01:07:42Z` | **2020-12-31** |
| 10 | `2020-12-31T18:07:35Z` | **2020-12-31** |
| 11 | `2021-02-25T17:29:23Z` | 2021-02-25 |
| 12 | `2021-03-28T01:26:51Z` | 2021-03-28 |
| 13 | `2021-06-29T00:01:05Z` | 2021-06-29 |

So **cats 3–5 share 2020-12-30 and cats 6–10 share 2020-12-31**. These clusters will dissolve as the curator backfills real `date` values in the studio (`studio/schemas/interviews.js:29-30`); when that happens `airDate` becomes a bare `"YYYY-MM-DD"` (slicing still works). The iOS implementation must tolerate both formats and must not assume one-show-per-day.

### 4.3 What the archive chronological browse does with it

`src/pages/archive.astro` builds a calendar "ledger" (one row per year, 12 month grids of day dots):

1. Drop episodes with no `airDate` (`archive.astro:12`).
2. Group by exact `"YYYY-MM-DD"` string into `byDay: Map<string, Episode[]>`; within a day sort **`cat` descending** (`archive.astro:17-21`).
3. Year range is **continuous** from `min(year)` to `max(year)`, rendered newest year first — a year with zero shows still renders as an empty grid ("the emptiness is the point of the ledger", `archive.astro:23-27,33`).
4. Month grids use real UTC month lengths: `new Date(Date.UTC(yr, mi + 1, 0)).getUTCDate()` (`archive.astro:36`).
5. A day with shows renders ONE link to the newest-cat show of that day (`c.shows[0]` after the desc sort); its tooltip/aria-label lists **all** shows on that day, joined with `' / '`, each formatted `` `${s.catLabel} · ${s.title} — ${s.artist}` `` (`archive.astro:52-53,86-97`). Silent days are inert.
6. The single "latest transmission" highlight is the episode with the **max `cat`** overall (not max date) (`archive.astro:29-31`).
7. Header stats: total shows, `minYear — maxYear` span, and total tracks = sum of `tracklist.length` (`archive.astro:49-50,60`).

### 4.4 Other consumers of episode ordering

- **Listen grid** (`/`, `src/pages/index.astro:7-8`): `getEpisodes()` order as-is (cat desc); whole catalog serialized as the play queue via `episodes.map(trackOf)`.
- **Show pages** (`/show/[slug]`, `src/pages/show/[slug].astro:7-14`): statically generated one per episode; shows `catLabel · year`, description, numbered tracklist (1-based, zero-padded to 2), and the Q&A section only when `qa.length > 0`.
- **Interviews** (`/interviews`, `src/pages/interviews.astro:8-10`): `getEpisodes().filter((e) => e.qa.length > 0)` sorted **`cat` ascending** (chronological ledger). "Interview" is not a type — it's any episode with at least one Q&A pair. Live-verified mix-only episodes (excluded): **cat 3 Saffronkeira (0 pairs)** and **cat 11 Olan Mill (0 pairs)**; the other 11 episodes have 8–16 pairs. (Matches the comment at `interviews.astro:5-7`.)
- Other pages (`dashboard.astro:158`, `settings.astro:20`, `playlists.astro:10-11`, `u/[id].astro:91`, `src/lib/profile.ts:262-265`) call `getEpisodes()` only to build a slug→Track index for resolving Supabase refs — same contract, no new queries.

---

## 5. Audio and image URLs

### 5.1 Audio

- Obtained exclusively via the GROQ dereference `"audioUrl": audio.asset->url` (`src/lib/content.ts:57`). The value is an absolute URL — treat it as opaque.
- **Live host today: `https://cdn.sanity.io/files/vcfngr79/production/<sha>.<ext>`** for all 13 episodes. Extensions verified: `.mp3` (12 episodes) and `.wav` (1 episode — cat 6, Jan Kleefstra). The player must handle both.
- Public, no auth, plain GET; Sanity's file CDN supports HTTP Range requests, which AVFoundation needs for streaming/seek.
- **Planned migration caveat:** the code comments declare a Phase-3 move of audio to Cloudflare R2 served from `https://cdn.quietcast.art` (`src/lib/sanity.ts:9`, `astro.config.mjs:73-76`, and `Track.src`'s doc comment "Absolute audio URL (cdn.quietcast.art/<audioKey>)" at `src/islands/PlayerDock.tsx:10`). That migration has NOT happened — the query still dereferences the Sanity asset and live URLs are on `cdn.sanity.io`. iOS must not hardcode either host; allow both `cdn.sanity.io` and `cdn.quietcast.art` (ATS is moot — both are HTTPS).

### 5.2 Images

- Obtained via `"coverUrl": cover.asset->url` (`src/lib/content.ts:56`). Live host: `https://cdn.sanity.io/images/vcfngr79/production/<id>-<W>x<H>.<ext>` — all 13 covers are currently `-2240x1260.png` (16:9 source art).
- The UI always displays covers **square**, relying on the CDN crop: append `?w=<w>&h=<h>&fit=crop&auto=format` (Section 3.5). Without the params you get the full 2240×1260 original.
- `coverUrl` is nullable in the type; the filter does not require it (interviews page guards with `e.coverUrl && ...`, `interviews.astro:59`). All 13 live docs currently have one.

---

## 6. Taxonomy summary (what iOS should and should not model)

- **Episodes**: flat list of `interview` docs. Canonical ordering: `cat` desc for browse/queue, `cat` asc for the interviews ledger, `airDate` day-grouping for the archive calendar.
- **Shows vs. interviews**: same documents. `qa.length > 0` ⇒ it appears on the Interviews screen; everything passing the base filter appears on Listen/Archive.
- **Categories**: none. `cat` is a *catalog number* (1, 2, 3 …), not a category. Display format `QC—NNN` (em dash, 3-digit zero pad).
- **Slugs**: opaque, unique, stable identifiers; historically inconsistent formats (see 2.2). They are the route param (`/show/[slug]`), the player Track id, and the Supabase foreign key (`ref` columns). Never derive a slug from the title.
- **Unused relations**: `label`/`releases` reference arrays and the `artist`/`label`/`release`/`style` document types exist in the dataset but have no read path in the app. Out of contract.
- **Forward-compat note** (`src/lib/content.ts:6-8`): a Phase-3 remodel into clean `show`/`mixtape`/`interview` types is planned; `content.ts` is "the single seam where that swap happens." Mirror that in iOS: isolate the GROQ + mapping behind one service so the document remodel is a single-file change.
