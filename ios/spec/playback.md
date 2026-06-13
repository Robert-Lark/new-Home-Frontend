# Quiet Cast — Playback & Now-Playing Contract (iOS / AVPlayer port)

Source of truth: the Astro web app at `front-end-astro/`. Every fact below carries a
`file:line` citation into that repo. Live-network checks were performed 2026-06-12 and are
labeled as such. This file is self-contained — implement from it without reading the web code.

---

## 1. The Track model (now-playing metadata contract)

The single playable unit everywhere (dock, queues, profile song) is `Track`
(`src/islands/PlayerDock.tsx:5-15`):

```ts
export interface Track {
  id: string;
  title: string;
  artist: string;
  cover: string;
  /** Absolute audio URL (cdn.quietcast.art/<audioKey>). */
  src: string;
  catalog?: string;
  /** Fallback duration label shown before metadata loads (e.g. "2:04:11"). */
  durationLabel?: string;
}
```

Semantics of `id` — it is the cross-feature `content_ref` (`src/lib/listen.ts:10-13`):

> `content_ref` is the one cross-feature key for a content item: for Sanity
> episodes it's the slug (== player Track.id); user uploads will use their
> upload UUID. favorites/playlists key on the same value.

- Episodes: `id = slug` (`src/lib/content.ts:107` — `id: e.slug`).
- Community mixes / profile-song mixes: `id = user_uploads.id` UUID
  (`src/pages/mixes/[id].astro:71`, `src/lib/profile.ts:272`).

Listen progress, favorites, and playlists all key on this exact string. The iOS app MUST use
the same values (episode slug, upload UUID) or per-user state will fork from the web.

Defaults when a play element omits optional attributes (`src/islands/PlayerDock.tsx:18-30`):
`title` → `'Untitled'`, `artist` → `'Unknown'`, `cover` → `''`. Elements missing `src` or
`id` are ignored entirely (`PlayerDock.tsx:20`: `if (!d.qcSrc || !d.qcId) return null;`).

---

## 2. Play triggers — every emitter and the attributes it carries

On the web, any element with `data-qc-play` is a play trigger; a document-level delegated
click listener reads the track off its `data-*` attributes (`PlayerDock.tsx:111-129`).
Attribute → Track field mapping (`PlayerDock.tsx:18-30`, HTML dataset camelCase):

| attribute          | Track field     | required |
|--------------------|-----------------|----------|
| `data-qc-id`       | `id`            | yes      |
| `data-qc-src`      | `src`           | yes      |
| `data-qc-title`    | `title`         | no       |
| `data-qc-artist`   | `artist`        | no       |
| `data-qc-cover`    | `cover`         | no       |
| `data-qc-catalog`  | `catalog`       | no       |
| `data-qc-duration` | `durationLabel` | no       |
| `data-qc-queue`    | seeds queue (JSON `Track[]`) | no |

There are exactly four static emitters plus one dynamic event (verified:
`grep -rn "data-qc-play" src/` hits PlayerDock + 4 emitting files).

### 2a. Home grid — episode cards (`src/pages/index.astro:38-49`)

```astro
data-qc-play
data-qc-id={t.id}
data-qc-title={t.title}
data-qc-artist={t.artist}
data-qc-cover={t.cover}
data-qc-src={t.src}
data-qc-catalog={t.catalog}
data-qc-queue={queueJson}
```

`t = trackOf(episode)`; `queueJson = JSON.stringify(episodes.map(trackOf))` — ALL episodes,
newest-first (`index.astro:7-8`; ordering `| order(cat desc)` in `src/lib/content.ts:92`).
So pressing play on any episode card seeds the queue with the full broadcast catalog.

### 2b. Episode detail page (`src/pages/show/[slug].astro:29-39`)

Identical attribute set to 2a, including the full-catalog `data-qc-queue`
(`show/[slug].astro:9` builds the same `queueJson` at build time).

### 2c. Community mix detail (`src/pages/mixes/[id].astro:68-77`)

```astro
data-qc-play
data-qc-id={mix.id}
data-qc-title={mix.title}
data-qc-artist={author}
data-qc-cover={cover}
data-qc-src={cdnUrl(mix.r2_key)}
data-qc-duration={durationLabel(mix.duration)}
```

- NO `data-qc-catalog`, NO `data-qc-queue` (single track; see queue caveat in §5).
- `author` = `profiles.display_name` of the uploader, fallback `'a listener'`
  (`mixes/[id].astro:35-36`).
- `cover` = `cdnUrl(mix.cover_r2_key)` or fallback `'/images/cryo_01.jpg'`
  (`mixes/[id].astro:41`).
- `data-qc-duration` is preformatted from `user_uploads.duration` (integer seconds) by
  `durationLabel()` — `"1:24:06" / "54:02"` (`src/lib/ugc.ts:139-146`).

### 2d. Profile song ("Profile signal" button) (`src/components/ProfilePage.astro:116-124`)

```astro
data-qc-play
data-qc-id={song.id}
data-qc-title={song.title}
data-qc-artist={song.artist}
data-qc-cover={song.cover}
data-qc-src={song.src}
data-qc-catalog={song.catalog}
```

NO `data-qc-queue`, NO `data-qc-duration`. The `song` Track is resolved server-side from
`profile_details.profile_song_ref` (`src/pages/dashboard.astro:202-203`,
`src/pages/u/[id].astro:119-120`) by `resolveTrack()` (`src/lib/profile.ts:258-278`):
- if the ref matches an episode slug → `trackOf(episode)` (so `catalog` = `"QC—NNN"`);
- else if the ref is a UUID → look up `user_uploads` and build
  `{ id, title, artist: 'Listener mix', cover: cdnUrl(cover_r2_key) || '/images/cryo_01.jpg', src: cdnUrl(r2_key) }`
  (`profile.ts:271-277`) — note the hardcoded artist string `'Listener mix'` and no catalog.

### 2e. Dynamic queues — favorites & named playlists (`qc:play-queue` event)

The /playlists Library UI does not use `data-qc-play`. It builds a `Track[]` client-side and
dispatches a DOM CustomEvent (`src/islands/PlaylistManager.tsx:40-46`):

```ts
document.dispatchEvent(
  new CustomEvent('qc:play-queue', { detail: { tracks, startId: startId ?? first.id } }),
);
```

PlayerDock consumes it (`PlayerDock.tsx:135-146`): filters out tracks lacking `id`/`src`,
sets the queue, starts at `startId` (or the first track). Track resolution for refs comes
from a server-rendered JSON index of ALL episodes embedded in the page
(`src/pages/playlists.astro:23`:
`<script id="qc-track-index" type="application/json" …>` containing
`JSON.stringify(episodes.map(trackOf))`, `playlists.astro:10-11`). Refs that don't resolve
(e.g. uploads not in the index) are shown but skipped when building the queue
(`PlaylistManager.tsx:25-27,66`).

iOS equivalent: build the queue model directly from library state — the DOM event is a
web-only seam.

### Episode → Track mapping (what 2a/2b attribute values contain)

`trackOf` (`src/lib/content.ts:105-114`):

```ts
return {
  id: e.slug,
  title: e.title,
  artist: e.artist,
  cover: sizedCover(e.coverUrl, 160) ?? '',
  src: e.audioUrl ?? '',
  catalog: e.catLabel,
};
```

- `title` is the Sanity `name` with the `"Quiet Cast NNN:"` prefix stripped
  (`content.ts:64`, regex `/^\s*quiet\s*cast\s*\d+\s*[:\-–]\s*/i`).
- `catalog` (`catLabel`) = `` `QC—${String(r.cat ?? 0).padStart(3, '0')}` `` → e.g. `"QC—013"`
  (`content.ts:67`). The em dash U+2014 is part of the label.
- `artist` falls back to `'Various'` (`content.ts:70`).

---

## 3. Audio URL shapes

These are STATIC FILES served over plain HTTPS — there is no HLS, no DASH, no DRM, no auth
header on audio GETs. AVPlayer should treat them as progressive-download remote assets.

### 3a. Sanity-hosted episode audio (`cdn.sanity.io/files/...`)

GROQ projects the file asset URL directly: `"audioUrl": audio.asset->url`
(`src/lib/content.ts:57`). Live-verified sample (Sanity query API, 2026-06-12):

```
https://cdn.sanity.io/files/vcfngr79/production/3b24fba00822e5e6aa6dc902bc407b7820219257.mp3
```

Pattern: `https://cdn.sanity.io/files/<projectId>/<dataset>/<sha1-of-file>.<ext>` with
`projectId = vcfngr79`, `dataset = production` (`astro.config.mjs:69-70`, `.env:5-6`). No
query parameters. Range-request support live-verified 2026-06-12 with
`curl -I -r 0-1023` against the sample above:

```
HTTP/2 206
accept-ranges: bytes
content-type: audio/mpeg
content-range: bytes 0-1023/156471378
cache-control: public, max-age=31536000, s-maxage=2592000
```

So seeking via byte ranges works, files are immutable-cached, and episodes can be large
(the sample is ~156 MB, ~2 h of MP3).

### 3b. R2-hosted community audio (`https://cdn.quietcast.art/...`)

Public read URL builder (`src/lib/ugc.ts:33-36`):

```ts
/** Public read URL for an R2 object (zero-egress custom domain). */
export function cdnUrl(key: string): string {
  return `${PUBLIC_CDN_URL.replace(/\/$/, '')}/${key}`;
}
```

`PUBLIC_CDN_URL = "https://cdn.quietcast.art"` (`astro.config.mjs:76`, `.env:7`). Keys are
minted server-side at upload time (`src/pages/api/uploads/sign.ts:77`):

```ts
const key = `user/${user.id}/${kind}/${crypto.randomUUID()}.${ext}`;
```

with `kind ∈ {mix, cover, photo}`, so a mix URL is exactly:

```
https://cdn.quietcast.art/user/<uploader-uuid>/mix/<random-uuid>.<mp3|m4a>
```

No query parameters, no signing on reads (presigned URLs are PUT-only and go to the
`<ACCOUNT_ID>.r2.cloudflarestorage.com` S3 host — reads always come back via the custom
domain, `src/lib/r2.ts:12-15`). Allowed audio types and cap
(`src/lib/ugc.ts:13,21-25`): `audio/mpeg → mp3`, `audio/mp4 → m4a`, `audio/x-m4a → m4a`,
max 250 MB.

CAVEAT (live check 2026-06-12): `https://cdn.quietcast.art/` currently answers
`HTTP/2 404`, `server: Vercel`, `x-vercel-error: DEPLOYMENT_NOT_FOUND` — the custom domain
is not presently wired to the R2 bucket, and zero published `user_uploads` rows were
visible to the anon Supabase client, so R2 range behavior could NOT be verified live. The
URL shape above is the code contract; verify range support once the domain points at R2.
(R2 objects are still plain static files, not HLS.)

### 3c. Local fallback asset

`'/images/cryo_01.jpg'` (site-relative) is the cover fallback for coverless mixes and the
empty dock (`mixes/[id].astro:41`, `profile.ts:275`, `PlayerDock.tsx:230`). iOS must bundle
an equivalent placeholder — this path does not resolve outside the web origin.

---

## 4. Artwork URL shapes (incl. lock-screen artwork source)

- Sanity covers: `"coverUrl": cover.asset->url` (`content.ts:56`) →
  `https://cdn.sanity.io/images/vcfngr79/production/<hash>-<W>x<H>.<ext>` (live-verified
  sample: `.../f4043e6e800e3bb2cc0fe51901ce355eef6a798d-2240x1260.png`). Sizing is plain
  query params via `sizedCover` (`content.ts:84-87`):

  ```ts
  return `${url}?w=${w}&h=${h}&fit=crop&auto=format`;
  ```

  The web uses `w=160` for the Track cover (`content.ts:110`), `w=600` grid cells
  (`index.astro:32`), `w=900` detail pages (`show/[slug].astro:20`). For
  `MPMediaItemArtwork` request a larger size by changing `w`/`h` — same base URL.
- R2 covers: `https://cdn.quietcast.art/user/<uid>/cover/<uuid>.<jpg|png|webp>`
  (`sign.ts:77` with `kind = 'cover'`; consumed at `mixes/[id].astro:41`,
  `profile.ts:275`). No resizing parameters — R2 serves the original.
- Fallback: bundle a placeholder (see §3c).

The web sets no Media Session metadata at all (`grep -rn "mediaSession" src/` → zero
matches), so iOS owns the lock-screen/now-playing-center story outright:
`MPNowPlayingInfoCenter` + `MPRemoteCommandCenter` populated from
`Track.title / artist / cover / catalog`.

---

## 5. Player behavior to mirror (and what is web-only)

One persistent player, one `<audio>` element, one current track + one queue
(`PlayerDock.tsx:47-56`). No multi-player, no overlapping audio.

- **Queue model**: a flat `Track[]`. Pressing a play trigger that carries `data-qc-queue`
  REPLACES the queue (`PlayerDock.tsx:118-124`); a trigger without it (community mix,
  profile song) changes the track but LEAVES the previous queue in place — prev/next then
  operate over that stale queue, and because the current id is not in it, the next press
  jumps to `queue[0]` (`PlayerDock.tsx:163-164`: `i === -1 ? 0 : …`). This looks
  accidental; decide deliberately for iOS (e.g. clear the queue on single-track play).
- **Prev/next wrap**: index arithmetic is modulo —
  `(i + delta + queue.length) % queue.length` (`PlayerDock.tsx:164`) — so the queue cycles
  endlessly in both directions. Prev/next are disabled when the queue is empty
  (`PlayerDock.tsx:278,288`).
- **On ended**: write final progress as fully played, then auto-advance `playAt(1)`
  (`PlayerDock.tsx:220-225`). With a non-empty queue this loops forever (modulo wrap, the
  last track advances to the first); with an empty queue playback just stops
  (`playAt` returns early, `PlayerDock.tsx:162`).
- **Up-next display**: the queue is shown rotated relative to the current track —
  `[...queue.slice(i + 1), ...queue.slice(0, i)]` (`PlayerDock.tsx:188-192`), i.e. "the
  rest, then the ones before me", current track excluded. Tapping a row plays it
  immediately without reordering the queue (`PlayerDock.tsx:299`).
- **Resume**: on every track load, fetch saved progress; seek IFF
  `status === 'playing' && progressSeconds > 10` (`MIN_RESUME_SECONDS = 10`,
  `PlayerDock.tsx:43-44,87-92`) AND the saved position is `< duration * 0.97`
  (`PlayerDock.tsx:70`). A 'played' (finished) track restarts from 0.
- **Seek/scrub**: the expanded view has a full `<input type="range" min=0 max=duration>`
  scrubber (`PlayerDock.tsx:264-272`); the compact dock's progress bar is `aria-hidden`,
  display-only — not interactive (`PlayerDock.tsx:236-238`). No ±15 s skip buttons, no
  playback-rate control.
- **Volume**: NO volume UI anywhere — system volume only. Mirror that (hardware
  buttons / MPVolumeView only).
- **Time display** (`fmt`, `PlayerDock.tsx:32-39`): `h:mm:ss` when ≥ 1 h else `m:ss`;
  seconds always 2-digit padded, minutes padded only when hours show, hours unpadded.
  Identical format to `durationLabel` (`ugc.ts:139-146`). The expanded view shows elapsed
  on the left and REMAINING on the right, rendered as `−{fmt(remaining)}` with U+2212 minus
  (`PlayerDock.tsx:273-276`). Before metadata loads the dock shows `durationLabel` if
  provided, else `'--:--'` (`PlayerDock.tsx:239`).
- **Empty state**: dock always visible; shows title `'Nothing playing'`, artist
  `'Quiet Cast'`, the placeholder cover, play disabled (`PlayerDock.tsx:230-240`).
- **Expanded ("now playing") view**: blurred-cover backdrop + recessed cover + title band +
  scrubber + prev/play/next + queue list; eyebrow text
  `Now playing · <catalog>` when `catalog` present (`PlayerDock.tsx:250-311`).

Web-only concerns (do NOT port literally):
- `transition:persist="player-dock"` + Astro `ClientRouter` keep the island and its playing
  `<audio>` alive across page swaps (`src/layouts/Base.astro:90-93,115-118`). iOS
  equivalent: a player layer above navigation — free with a persistent AVPlayer.
- The document-level delegated click listener and `data-*` dataset parsing
  (`PlayerDock.tsx:107-129`) — replace with direct view-model calls.
- `requestAnimationFrame` + `audio.load()` dance (`PlayerDock.tsx:94-102`), body scroll
  lock while expanded (`PlayerDock.tsx:179-184`), `preload="metadata"`
  (`PlayerDock.tsx:199`).
- Background audio: the web gets it for free from the browser; iOS must enable the `audio`
  background mode + configure `AVAudioSession` category `.playback` (no web citation —
  platform requirement).

---

## 6. Listen-progress persistence (Supabase `listen_status`)

Writes go straight from client to Supabase with the publishable anon key; RLS scopes rows
to the signed-in user; logged-out playback records nothing (`src/lib/listen.ts:4-13,57-58`).

Table + policy, quoted from `supabase/migrations/0001_init.sql:72-86`:

```sql
create table if not exists public.listen_status (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid not null references auth.users (id) on delete cascade,
  content_ref      text not null,
  status           text not null default 'unplayed'
                     check (status in ('unplayed', 'playing', 'played')),
  progress_seconds integer not null default 0,
  updated_at       timestamptz not null default now(),
  unique (user_id, content_ref)
);
alter table public.listen_status enable row level security;

create policy "listen_status_rw_own" on public.listen_status
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
```

Write semantics (`src/lib/listen.ts:52-81`) — upsert with
`onConflict: 'user_id,content_ref'`, payload:

```ts
{
  user_id: uid,
  content_ref: ref,
  status,                                  // 'played' | 'playing'
  progress_seconds: Math.floor(progressSeconds),
  updated_at: new Date().toISOString(),
}
```

Rules the iOS app must reproduce exactly:
- `status = 'played'` iff `progress / duration >= 0.9` — `DONE_RATIO = 0.9` is a "locked
  feature rule" (`listen.ts:18-19,60-61`); else `'playing'`.
- Skip writes under 5 s of progress — `MIN_RECORD_SECONDS = 5` (`listen.ts:21,58`).
- Write cadence while playing: every 20 s of media time —
  `WRITE_EVERY_SECONDS = 20` (`PlayerDock.tsx:41-42,205-208`); plus a flush on pause
  (`PlayerDock.tsx:215-219`) and a final `recordProgress(id, duration, duration)` on ended
  (`PlayerDock.tsx:220-223`).
- Read-back for resume: `select progress_seconds, status … eq('content_ref', ref)`,
  no user filter needed under RLS (`listen.ts:84-96`).
- Display states elsewhere in the app: `'played' → done`, `'playing' → in-progress`, row
  absent → unplayed (`listen.ts:44-49`).

Supabase endpoint: `https://zzftxvxgnkuowipeylen.supabase.co` (`.env:3`); anon key in
`.env` as `PUBLIC_SUPABASE_ANON_KEY` — publishable by design (`src/lib/supabase.ts:6-9`).

---

## 7. Theme-INVARIANT now-playing surface (overart tokens)

The app has dark (default) and light themes, but every surface that sits ON ARTWORK —
including the entire now-playing view — deliberately stays dark in both. Quoted from
`src/styles/tokens.css:56-65`:

```css
/* over-art constants — DELIBERATELY theme-invariant. Scrims, pills, and
   washes that sit on artwork (hero hover bands, tile controls, the
   now-playing view) stay dark in both themes; the art doesn't change.
   Consumed via color-mix alphas at the use site. */
--overart: #08090b;
--overart-ink: #d9d5c8;
--overart-ink-2: #9a9ca0;
--overart-ink-3: #6e6e66;
--overart-hairline: rgba(217, 213, 200, 0.12);
--overart-hairline-soft: rgba(217, 213, 200, 0.06);
```

In light mode the now-playing view re-pins its ink tokens to the overart ramp
(`tokens.css:126-143`): `[data-theme='light'] .now-playing { color-scheme: dark;
--ink: var(--overart-ink); … --on-ember: #0d0e10; --recess: #08090b; }`.

Backdrop recipe (`src/styles/global.css:189-206`): the cover image, blurred and darkened —
`filter: grayscale(0.5) brightness(0.32) contrast(1.05) blur(28px); transform: scale(1.15);`
under a scrim ending in `color-mix(in srgb, var(--overart) 55%, transparent)`.

iOS rule: the full-screen player ALWAYS renders dark-over-artwork — bone ink `#d9d5c8` on
near-black `#08090b` scrims over the blurred cover — regardless of the app's light/dark
setting. Do not let the player surface follow the system theme.

---

## 8. Quick checklist for the AVPlayer port

1. `Track {id, title, artist, cover, src, catalog?, durationLabel?}`; `id` doubles as
   Supabase `content_ref` (episode slug / upload UUID) — never invent ids.
2. Audio = static MP3/M4A over HTTPS, two hosts: `cdn.sanity.io/files/vcfngr79/production/…`
   (range-verified) and `https://cdn.quietcast.art/user/<uid>/mix/…` (shape per code;
   domain currently dark — see §3b). Not HLS.
3. Episode plays seed a full-catalog queue (cat desc); mix/profile-song plays are
   single-track; queue wraps modulo on prev/next and on ended.
4. Resume iff saved `status == 'playing' && progress > 10s && progress < 97% of duration`.
5. Progress writes: ≥5 s only, every 20 s + on pause + on ended; `played` at ≥90 %.
6. Now-playing screen is theme-invariant dark-over-artwork (§7 tokens).
7. Lock screen: web has no Media Session — populate `MPNowPlayingInfoCenter` from Track,
   using `sizedCover` params to fetch artwork at an appropriate size.
8. No volume UI; no skip-±15s; full scrubber only in the expanded view.
