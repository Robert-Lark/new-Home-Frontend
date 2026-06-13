# Quiet Cast — UGC data-access + markdown contract (iOS)

Contract for the native SwiftUI app, extracted verbatim from the Astro web app at
`/Users/roblark/Projects/quietcast/front-end-astro`. Every fact cites `file:line` in that repo.
The iOS app talks to the **same** backends: Supabase (PostgREST + Auth, anon key + RLS) and the
R2 CDN (`cdn.quietcast.art`). Editorial episodes come from Sanity and are out of scope here except
for the R2-vs-Sanity split in §2.

Source files this contract is derived from:

- `src/lib/ugc.ts` (154 lines) — caps, MIME maps, `cdnUrl`, markdown, display helpers
- `src/lib/report.ts` (54 lines) — `handleReport`, `setVisibility`
- `src/pages/community.astro`, `src/pages/posts/[id].astro`, `src/pages/mixes/[id].astro`,
  `src/pages/lists/[id].astro`, `src/pages/photos/[id].astro`
- `src/pages/contribute/{index,post,list,mix,photos}.astro`,
  `src/islands/{MixUploadForm,PhotoUploadForm}.tsx`, `src/lib/upload-client.ts`
- `src/pages/api/uploads/sign.ts`, `src/lib/r2.ts`
- `src/components/{ReportForm,VisibilityToggle}.astro`
- `supabase/migrations/{0001_init,0002_ugc,0003_profile,0005_self_publish}.sql` (DDL + RLS)
- `astro.config.mjs` (env defaults), `src/lib/sanity.ts`, `src/lib/content.ts` (Sanity split)

---

## 1. `cdnUrl()` — R2 public read URLs

Exact implementation (`src/lib/ugc.ts:33-36`):

```ts
/** Public read URL for an R2 object (zero-egress custom domain). */
export function cdnUrl(key: string): string {
  return `${PUBLIC_CDN_URL.replace(/\/$/, '')}/${key}`;
}
```

`PUBLIC_CDN_URL` is a public (client-inlined) env var with default
`'https://cdn.quietcast.art'` (`astro.config.mjs:76`):

```js
PUBLIC_CDN_URL: envField.string({ context: 'client', access: 'public', default: 'https://cdn.quietcast.art' }),
```

So `cdnUrl(key)` ≡ `https://cdn.quietcast.art/<key>` (trailing slash on the base stripped).
Plain unauthenticated GET — no signing for reads. The backing bucket is `quietcast-audio`
(`astro.config.mjs:80`, `wrangler.toml` `bucket_name = "quietcast-audio"`); reads never hit the
S3 API host, only the custom domain (`src/lib/r2.ts:13-15` comment: "presigned URLs do NOT work
on custom domains — uploads go to the S3 API host, public reads come back via cdn.quietcast.art").

### Object key namespaces (all under `user/<uid>/…`)

| Key pattern | Minted at | Used for |
| --- | --- | --- |
| `user/<uid>/mix/<uuid>.<ext>` | `src/pages/api/uploads/sign.ts:77` | mix audio (`user_uploads.r2_key`) |
| `user/<uid>/cover/<uuid>.<ext>` | `src/pages/api/uploads/sign.ts:77` | mix cover art (`user_uploads.cover_r2_key`) |
| `user/<uid>/photo/<uuid>.<ext>` | `src/pages/api/uploads/sign.ts:77` | album photos (`photos.r2_key`) |
| `user/<uid>/avatar/<uuid>.<ext>` | `src/pages/settings.astro:91` | profile avatar (stored as full URL in `profiles.avatar_url`, `settings.astro:100-103`) |
| `user/<uid>/grid/<uuid>.<ext>` | `src/pages/dashboard.astro:98` | rotation-grid connection images (stored as full URL in `connections.image_url`, `dashboard.astro:105,112`) |

Minting line, verbatim (`src/pages/api/uploads/sign.ts:77`):

```ts
const key = `user/${user.id}/${kind}/${crypto.randomUUID()}.${ext}`;
```

`<ext>` comes from the MIME maps in §4. `<uid>` is the Supabase auth user UUID. RLS enforces the
prefix on metadata inserts — a row may only reference keys under the author's own prefix
(`supabase/migrations/0005_self_publish.sql:49-55` for `user_uploads`,
`0002_ugc.sql:188-193` for `photos`), e.g.:

```sql
and r2_key like 'user/' || auth.uid()::text || '/%'
and (cover_r2_key is null or cover_r2_key like 'user/' || auth.uid()::text || '/%')
```

### Important storage convention

`user_uploads.r2_key`, `user_uploads.cover_r2_key`, and `photos.r2_key` store the **bare key**
(pass through `cdnUrl()` to get a URL). `profiles.avatar_url` and `connections.image_url` store
the **full CDN URL** (already `cdnUrl(key)`-expanded at write time —
`settings.astro:102`, `dashboard.astro:105`). Do not double-prefix.

## 2. R2 vs cdn.sanity.io

- **R2 (`cdn.quietcast.art`)**: all UGC bytes — listener mix audio, mix covers, concert photos,
  avatars, grid images. "Image bytes live in R2 (same zero-egress path as audio); rows are
  metadata." (`supabase/migrations/0002_ugc.sql:135`).
- **cdn.sanity.io**: editorial episode audio and cover art. Episodes are Sanity `interview`
  documents; their media URLs come straight from Sanity asset references —
  `"coverUrl": cover.asset->url` and `"audioUrl": audio.asset->url`
  (`src/lib/content.ts:56-57`), served by the Sanity CDN (client config: project `vcfngr79`,
  dataset `production`, `apiVersion: '2025-01-01'`, `useCdn: true`, `perspective: 'published'` —
  `src/lib/sanity.ts:13-19`, defaults at `astro.config.mjs:69-70`).
- Sanity image resizing helper appends `?w=${w}&h=${h}&fit=crop&auto=format`
  (`src/lib/content.ts:84-87`). R2 images have **no** transform params — full-size only.
- A planned Phase 3 "moves audio to R2" for editorial too (`src/lib/content.ts:7-8` comment);
  not done as of 2026-06-12.

## 3. Supabase tables (DDL essentials)

Status vocabulary after migration `0005_self_publish.sql` for all four UGC tables:
**`'private' | 'published' | 'removed'`**, default `'private'`
(`0005_self_publish.sql:43-46,74-77,93-96,112-115`). Authors may write only
`'private'`/`'published'`; `'removed'` is curator-only (service role) and a removed row drops out
of the author's updatable set (`for update using (auth.uid() = user_id and status <> 'removed')`,
e.g. `0005_self_publish.sql:59`). Select policies are own-OR-published on every UGC table, e.g.
(`0001_init.sql:109-110`):

```sql
create policy "uploads_select_own_or_published" on public.user_uploads
  for select using (auth.uid() = user_id or status = 'published');
```

(Identical shape: posts `0001_init.sql:141-142`; lists `0002_ugc.sql:75-76`; photo_albums
`0002_ugc.sql:153-154`. Child tables `list_items`/`photos` derive access from the parent via
`exists(...)` subqueries — `0002_ugc.sql:104-111,178-185`.) Anonymous (no session) reads of
published rows work — the community page is "Anonymous-readable — RLS lets published rows through
without a session" (`community.astro:8`).

Columns (from `0001_init.sql` / `0002_ugc.sql`):

- `user_uploads` (`0001_init.sql:91-105`): `id uuid pk`, `user_id uuid` (FK **auth.users**),
  `title text not null`, `description text`, `cover_r2_key text`,
  `tracklist jsonb not null default '[]'::jsonb` (array of strings), `r2_key text not null`,
  `duration integer` (seconds, nullable), `mime text`, `status text`, `reviewed_at timestamptz`,
  `created_at timestamptz default now()`.
- `posts` (`0001_init.sql:127-137`): `id`, `user_id`, `slug text not null`, `title text not null`,
  `body_md text`, `status`, `created_at`, `unique (user_id, slug)`; plus `reviewed_at`
  (`0002_ugc.sql:19`).
- `lists` (`0002_ugc.sql:62-71`): `id`, `user_id`, `title text not null`, `description text`,
  `status`, `reviewed_at`, `created_at`.
- `list_items` (`0002_ugc.sql:91-100`): `id`, `list_id` (FK lists, cascade),
  `item_type text not null default 'other' check (item_type in ('record', 'artist', 'label', 'show', 'other'))`,
  `title text not null`, `note text`, `url text`, `position integer not null default 0`.
- `photo_albums` (`0002_ugc.sql:138-149`): `id`, `user_id`, `title text not null`, `venue text`,
  `event_date date`, `description text`, `status`, `reviewed_at`, `created_at`.
- `photos` (`0002_ugc.sql:169-175`): `id`, `album_id` (FK photo_albums, cascade),
  `r2_key text not null`, `caption text`, `position integer not null default 0`. Photos carry no
  status — visibility follows the album (`0002_ugc.sql:137`).
- `profiles` (`0001_init.sql:10-15`): `id uuid pk` (FK auth.users), `display_name text`,
  `avatar_url text`, `created_at`. World-readable (`for select using (true)`,
  `0001_init.sql:19-20`).
- `profile_details` (`0003_profile.sql:13-24`): `id uuid pk`, `is_public boolean not null default false`,
  `bio`, `status_line`, `profile_song_ref`, `theme` (`'dark'|'light'`), `updated_at`. Select policy
  (`0003_profile.sql:28-29`): `for select using (is_public or auth.uid() = id)`.
- `reports` (`0001_init.sql:290-298`):

```sql
create table if not exists public.reports (
  id           uuid primary key default gen_random_uuid(),
  reporter_id  uuid not null references auth.users (id) on delete cascade,
  content_type text not null check (content_type in ('upload', 'message', 'post', 'playlist')),
  content_ref  text not null,
  reason       text,
  status       text not null default 'open' check (status in ('open', 'reviewed', 'dismissed')),
  created_at   timestamptz not null default now()
);
```

  content_type check widened by `0002_ugc.sql:213-216` to
  `('upload', 'message', 'post', 'playlist', 'list', 'photo_album')` (and `'wall_comment'` is used
  by the wall feature — see moderation page handling at `moderation.astro:85`). RLS
  (`0001_init.sql:301-307`): users may insert rows where `auth.uid() = reporter_id` and select
  only their own reports. The curator reads the queue with the service-role key.

PostgREST embedding caveat (`src/lib/ugc.ts:94-98` comment): UGC tables FK `auth.users`, **not**
`profiles`, and `auth.users` is not exposed to PostgREST, so you **cannot** embed
`profiles(display_name)` in a UGC select. Author names always require the separate batched query
in §6. Embedding `photos(...)` in `photo_albums` and `list_items(...)` in `lists` works (real FK
between public tables).

## 4. Constants, caps, MIME maps (`src/lib/ugc.ts:12-31`)

```ts
/** Plan default (to confirm with owner): mixes ≤ 250MB, mp3/m4a. */
export const MIX_MAX_BYTES = 250 * 1024 * 1024;
/** Covers + concert photos ≤ 10MB, JPG/PNG/WebP. */
export const IMAGE_MAX_BYTES = 10 * 1024 * 1024;
/** Max photos per album upload. */
export const ALBUM_MAX_PHOTOS = 24;
/** Abuse brake: refuse new pieces once this many were created in the trailing 24h. */
export const MAX_CREATED_PER_DAY = 20;

export const AUDIO_TYPES: Record<string, string> = {
  'audio/mpeg': 'mp3',
  'audio/mp4': 'm4a',
  'audio/x-m4a': 'm4a',
};

export const IMAGE_TYPES: Record<string, string> = {
  'image/jpeg': 'jpg',
  'image/png': 'png',
  'image/webp': 'webp',
};
```

List item types (`src/lib/ugc.ts:38`):

```ts
export const LIST_ITEM_TYPES = ['record', 'artist', 'label', 'show', 'other'] as const;
```

Client-side checks are "UX only" — the server enforces caps in `/api/uploads/sign`
(`src/lib/ugc.ts:8-9` comment).

## 5. `renderMarkdown()` — the exact markdown subset

This is the highest-fidelity section: the iOS app re-implements this for `AttributedString`.
Only consumer in the web app: `posts/[id].astro:40` → `renderMarkdown(post.body_md ?? '')`.
Stated design (`src/lib/ugc.ts:41-46` comment): "a deliberately tiny, view-source-friendly
subset. Input is HTML-escaped FIRST, then formatted, so there is no raw-HTML XSS surface and no
sanitizer dependency. Supported: # / ## headings, **bold**, *italic*, [text](https://…) links,
\"- \" lists, \"> \" blockquotes, paragraphs."

Verbatim source (`src/lib/ugc.ts:48-88`):

```ts
function escapeHtml(s: string): string {
  return s
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

function inline(s: string): string {
  return s
    .replace(/\[([^\]]+)\]\((https?:\/\/[^\s)]+)\)/g, (_, text: string, href: string) => {
      return `<a href="${href}" rel="nofollow noopener ugc" target="_blank">${text}</a>`;
    })
    .replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>')
    .replace(/\*([^*]+)\*/g, '<em>$1</em>');
}

/** Render the markdown subset to HTML. Safe for set:html. */
export function renderMarkdown(md: string): string {
  const blocks = escapeHtml(md.replace(/\r\n/g, '\n')).split(/\n{2,}/);
  const html: string[] = [];

  for (const block of blocks) {
    const lines = block.split('\n').filter((l) => l.trim() !== '');
    if (lines.length === 0) continue;

    if (lines.every((l) => l.startsWith('- '))) {
      html.push(`<ul>${lines.map((l) => `<li>${inline(l.slice(2).trim())}</li>`).join('')}</ul>`);
    } else if (lines.every((l) => l.startsWith('&gt;'))) {
      const quoted = lines.map((l) => inline(l.replace(/^&gt;\s?/, '').trim())).join('<br>');
      html.push(`<blockquote>${quoted}</blockquote>`);
    } else if (lines.length === 1 && lines[0]?.startsWith('## ')) {
      html.push(`<h3>${inline(lines[0].slice(3).trim())}</h3>`);
    } else if (lines.length === 1 && lines[0]?.startsWith('# ')) {
      html.push(`<h2>${inline(lines[0].slice(2).trim())}</h2>`);
    } else {
      html.push(`<p>${lines.map(inline).join('<br>')}</p>`);
    }
  }
  return html.join('\n');
}
```

### Algorithm in evaluation order (normative)

1. **CRLF normalize**: `md.replace(/\r\n/g, '\n')` (bare `\r` is NOT handled).
2. **HTML-escape the whole input** in this replacement order: `&`→`&amp;`, `<`→`&lt;`,
   `>`→`&gt;`, `"`→`&quot;`. Single quote `'` is NOT escaped. (`&` first prevents
   double-escaping.) On iOS you skip escaping entirely — but see "iOS divergence notes" below,
   because the web's later regexes run against the *escaped* text.
3. **Block split** on `/\n{2,}/` — two or more consecutive newlines separate blocks.
4. **Per block**: split on single `\n`, drop lines whose `trim()` is empty (a blank-only line
   inside a block disappears, it does not break the block). If no lines remain, skip the block.
5. **Block classification, first match wins** (order is the contract):
   1. Every line starts with `"- "` (dash + space) → `<ul>`; each line: strip first 2 chars,
      `trim()`, apply inline rules → `<li>`.
   2. Every line starts with `"&gt;"` (i.e. a literal `>` in the user's source, tested
      post-escape) → `<blockquote>`; each line: `replace(/^&gt;\s?/, '')` (strip `>` plus at most
      ONE following whitespace char), `trim()`, inline rules; lines joined with `<br>`.
   3. Block is exactly ONE line and it starts with `"## "` → `<h3>` of `slice(3).trim()` + inline.
   4. Block is exactly ONE line and it starts with `"# "` → `<h2>` of `slice(2).trim()` + inline.
   5. Otherwise → `<p>`; each line through inline rules, joined with `<br>`.
6. Blocks joined with `"\n"`.

Note the heading tag shift: source `#` renders as `<h2>`, source `##` renders as `<h3>` (there is
no `<h1>` in post bodies).

### Inline rules, evaluation order (normative)

Applied per-line (after block stripping), three sequential global regex replaces:

1. **Links**: `/\[([^\]]+)\]\((https?:\/\/[^\s)]+)\)/g` →
   `<a href="${href}" rel="nofollow noopener ugc" target="_blank">${text}</a>`.
   - URL must start with `http://` or `https://` (relative/`mailto:`/`javascript:` never match).
   - URL may not contain whitespace or `)` — first `)` closes the link.
   - Link text may not contain `]`. Link text is NOT recursively processed at this point, but
     later bold/italic passes run over the produced `<a>` tag string, so `[**x**](url)` ends up
     with `<strong>` inside the anchor text.
2. **Bold**: `/\*\*([^*]+)\*\*/g` → `<strong>$1</strong>`. Content may not contain `*` (so no
   nesting via asterisks inside bold).
3. **Italic**: `/\*([^*]+)\*/g` → `<em>$1</em>`. Runs AFTER bold, so leftover single-asterisk
   pairs become `<em>`. Consequence: `***text***` renders as `<em><strong>text</strong></em>`
   (bold pass matches the inner `**text**` leaving `*…*`, italic pass then wraps).

### Explicitly NOT supported (do not implement)

- `###` or deeper headings; headings inside a multi-line block (a `# ` line that shares a block
  with other lines renders as plain paragraph text — the heading branches require
  `lines.length === 1`).
- Ordered lists, nested lists, task lists. A `- ` line in a block where *any* sibling line is
  not `- `-prefixed renders the whole block as a paragraph (the `every()` checks).
- Mixed blockquote blocks — same `every()` rule.
- Inline code, code fences, backticks (render literally).
- Images (`![alt](url)` — the leading `!` is left as text and `[alt](url)` still becomes a link).
- Underscore emphasis (`_x_`, `__x__`), strikethrough, tables, horizontal rules, footnotes.
- Backslash escaping — there is NO way to write a literal `*` that would otherwise match, no `\*`.
- Raw HTML — angle brackets are escaped to entities and render literally as text.
- Hard line breaks via trailing spaces — a single newline inside a block always becomes `<br>`
  (web) / line break (iOS); double newline starts a new block.
- autolinking bare URLs (a bare `https://…` stays plain text).

### iOS divergence notes (escape-order artifacts to be aware of)

Because the web escapes BEFORE pattern matching, on raw (unescaped) iOS input:

- Blockquote test `l.startsWith('&gt;')` ≡ raw line starts with `>`; marker strip
  `/^&gt;\s?/` ≡ raw `/^>\s?/` (strip `>` plus at most one whitespace char, then trim).
- A markdown link whose URL contains `&` is matched by the web against `&amp;` — the produced
  `href="...&amp;..."` decodes back to `&` in the browser, so on iOS using the raw `&` URL is
  the equivalent behavior. A URL containing `"` becomes `&quot;` pre-match on the web (the `;`
  survives `[^\s)]+`), which corrupts the href — treat `"` in URLs as unsupported/undefined.
- `<` and `>` in body text are literal text on both platforms.

### Markdown styling on the web (reference for visual parity)

From `posts/[id].astro:102-145` (`.prose` styles): `p` 17px / line-height 1.75; `h2` 24px and
`h3` 19px in `'Cormorant Garamond', serif`, uppercase, letter-spacing 0.16em; `ul` indented 20px;
`li` 17px / 1.7; `blockquote` has a `border-left: 2px solid var(--ember)`, 20px padding-left,
italic serif 19px in `var(--stone)`; links colored `var(--ember)`. Token values
(`src/styles/tokens.css`): dark theme `--ember: #b08a5e` (line 39), `--stone: #8b8478` (line 24);
light theme `--ember: #84592e` (line 109), `--stone: #6b6353` (line 97).

The hint shown under the post composer (`contribute/post.astro:101-103`):
`Formatting: # heading · **bold** · *italic* · [link](https://…) · "- " lists · ">" quotes`.

## 6. Display helpers — names, bylines, dates, durations

### `displayNames` (`src/lib/ugc.ts:99-111`)

```ts
const { data } = await supabase.from('profiles').select('id, display_name').in('id', ids);
```

- Input user ids are de-duplicated; empty input short-circuits to an empty map.
- Rows with null/empty `display_name` are skipped (`if (row.display_name)`, ugc.ts:108).
- Every call site falls back to the literal string `'a listener'` when the map misses
  (`community.astro:92`, `posts/[id].astro:35`, `mixes/[id].astro:36`, `lists/[id].astro:35`,
  `photos/[id].astro:35`).

### `publicProfileIds` + byline linking semantics (`src/lib/ugc.ts:119-136`)

```ts
const { data, error } = await supabase
  .from('profile_details')
  .select('id')
  .in('id', ids)
  .eq('is_public', true);
```

- Returns the subset of the given user ids that have a public profile. Any error or thrown
  exception → empty set (byline stays plain text; this is also the pre-0003-migration fallback,
  ugc.ts:116-117 comment).
- Works anonymously: `profile_details` select policy is `is_public or auth.uid() = id`
  (`0003_profile.sql:28-29`).
- **Linking rule** (identical on every UGC surface, e.g. `community.astro:145-149`,
  `posts/[id].astro:36-38,57`): if the author's id is in the public set, the byline text
  (display name or `'a listener'`) links to `/u/<user_id>`; otherwise it renders as plain,
  unlinked text. Never link a byline for a non-public profile.

### `durationLabel` (`src/lib/ugc.ts:139-146`)

`"1:24:06"` / `"54:02"` from stored integer seconds. Null/undefined/non-finite/≤0 → `undefined`
(web omits the label). `h:mm:ss` with zero-padded minutes only when hours > 0; seconds always
2-padded; minutes unpadded in the no-hours form.

### `ugcDate` (`src/lib/ugc.ts:149-154`)

`Intl.DateTimeFormat('en', { day: 'numeric', month: 'long', year: 'numeric' })` →
`"11 June 2026"`. Null/undefined → empty string. Used for `created_at` timestamps and
`event_date` dates.

## 7. Read queries (PostgREST), page by page

All run with the anon key (+ user JWT when signed in); RLS does the filtering. iOS equivalents
are plain PostgREST calls.

### Community shelf (`/community` — `community.astro`)

Four independent queries, each: `eq('status','published')`, `order('created_at', {ascending: false})`,
`limit(12)`. Errors/missing tables degrade to empty arrays (`community.astro:14-21`).

| Content | Table | `.select(...)` verbatim | Lines |
| --- | --- | --- | --- |
| Mixes | `user_uploads` | `'id, user_id, title, cover_r2_key, duration, created_at'` | 33-38 |
| Writing | `posts` | `'id, user_id, title, created_at'` | 42-47 |
| Lists | `lists` | `'id, user_id, title, description, created_at'` | 57-62 |
| Photo albums | `photo_albums` | `'id, user_id, title, venue, event_date, created_at, photos(r2_key, position)'` | 75-79 |

- Album thumbnail = photo with the lowest `position` (client-side sort), else fallback image
  `'/images/cryo_01.jpg'` (`community.astro:23,94-97`). Mix cover = `cdnUrl(cover_r2_key)` else
  the same fallback (`community.astro:138`).
- Author names + public ids fetched in one batch across all four result sets
  (`community.astro:82-91`).
- Album subline prefers `venue · event_date`; byline only shows when there's no `event_date`
  (`community.astro:231-240`).

### Mix detail (`/mixes/<id>` — `mixes/[id].astro:28-32`)

```ts
const { data: mix } = await supabase
  .from('user_uploads')
  .select('id, user_id, title, description, cover_r2_key, tracklist, r2_key, duration, status, created_at')
  .eq('id', id)
  .maybeSingle();
if (!mix) return Astro.redirect('/community');
```

- Lookup is by `id` only — RLS decides visibility ("published rows for everyone, plus everything
  of the author's own", `mixes/[id].astro:27`). Null result (not found OR not visible) →
  redirect to `/community`; iOS should treat both identically (no 403-vs-404 distinction exists).
- Playback: stream URL is `cdnUrl(mix.r2_key)` (`mixes/[id].astro:75`); cover
  `cdnUrl(cover_r2_key)` else `'/images/cryo_01.jpg'` (line 41).
- `tracklist` is a JSONB array; non-string entries are filtered out defensively (lines 42-44).
- Non-published rows (only ever the owner's) show a badge: status text, with `removed` rendered as
  `"removed by the curator"` + `"— only you can see this"` (lines 56-62; same pattern on all
  detail pages).

### Post detail (`/posts/<id>` — `posts/[id].astro:27-32,40`)

```ts
.from('posts')
.select('id, user_id, title, body_md, status, created_at')
.eq('id', id)
.maybeSingle();
```

Body rendered with `renderMarkdown(post.body_md ?? '')` (line 40). Null → redirect `/community`.

### List detail (`/lists/<id>` — `lists/[id].astro:27-32,40`)

```ts
.from('lists')
.select('id, user_id, title, description, status, created_at, list_items(id, item_type, title, note, url, position)')
.eq('id', id)
.maybeSingle();
```

Items sorted client-side by `position` ascending (line 40). Item rendering
(`lists/[id].astro:64-83`): 1-based zero-padded index (`01`, `02`…), title links to `item.url`
when present (external, `rel="nofollow noopener ugc"`), `item_type` shown as a pill, optional
`note` underneath. Note: `list_items.note`/`url` render as plain text/href — **no markdown**.

### Photo album detail (`/photos/<id>` — `photos/[id].astro:27-32,40-43`)

```ts
.from('photo_albums')
.select('id, user_id, title, venue, event_date, description, status, created_at, photos(id, r2_key, caption, position)')
.eq('id', id)
.maybeSingle();
```

Photos sorted client-side by `position` ascending (line 40). Each photo: image + link target both
`cdnUrl(p.r2_key)` (lines 69-70), optional `caption`. Header stamp = `venue · ugcDate(event_date)`
(whichever exist, `·`-joined), falling back to `ugcDate(created_at)` (lines 41-43,50).

### Detail-page commonalities

Every detail page (`mixes|posts|lists|photos/[id].astro`):
- `displayNames` + `publicProfileIds` for the single author; byline per §6.
- `own = user?.id === row.user_id` decides owner UI: owner sees the visibility toggle, never the
  report form; non-owners see the report form, never the toggle (e.g. `posts/[id].astro:39,58,63`).
- Descriptions (`mix.description`, `list.description`, `album.description`) are plain text
  (mix description preserves newlines via `white-space: pre-wrap`, `mixes/[id].astro:195`) —
  markdown applies ONLY to `posts.body_md`.

## 8. Creating content

### 8.1 Presigned upload flow (mixes, covers, photos)

Endpoint: `POST /api/uploads/sign` (SSR route, Supabase session cookie auth;
`src/pages/api/uploads/sign.ts`). The iOS app must replicate this call (it is the only way to
mint a write to R2 — there are no client-side R2 credentials).

Request schema (`sign.ts:23-27`, zod):

```ts
const signRequestSchema = z.object({
  kind: z.enum(['mix', 'cover', 'photo']),
  contentType: z.string().min(1),
  size: z.number().int().positive(),
});
```

Validation (`sign.ts:51-59`): `kind === 'mix'` → `AUDIO_TYPES`/`MIX_MAX_BYTES`, else
`IMAGE_TYPES`/`IMAGE_MAX_BYTES`. Responses:

| Status | Body | Condition (`sign.ts` lines) |
| --- | --- | --- |
| 401 | `{"error":"Sign in to upload."}` | no session (38) |
| 503 | `{"error":"Uploads are not configured on this deployment yet."}` | R2 creds missing (39) |
| 400 | `{"error":"Expected a JSON body."}` / `{"error":"Invalid upload request."}` | (41-48) |
| 415 | `{"error":"That file type isn't supported — use <MP3 or M4A audio|JPG, PNG, or WebP images>."}` | (54-57) |
| 413 | `{"error":"Too large — the limit is <N>MB."}` | (58-59) |
| 429 | `{"error":"Daily cap reached — twenty new pieces in 24 hours. Come back tomorrow."}` | (73-74) |
| 200 | `{ url, key, publicUrl }` | (79) |

Then the client PUTs the raw file bytes to `url` with header `Content-Type: <file MIME>`
(`src/lib/upload-client.ts:33-46`); 2xx = success. The presigned URL targets
`https://<ACCOUNT_ID>.r2.cloudflarestorage.com/<bucket>/<key>` and expires in 900 seconds by
default (`src/lib/r2.ts:60-64`); only the `host` header is signed, so any `Content-Type` is
accepted by the signature (`r2.ts:56-58`). `publicUrl` = `cdnUrl(key)`.

### 8.2 The 24h / 20-piece creation cap

`MAX_CREATED_PER_DAY = 20` (`ugc.ts:19`), trailing-24h window
`new Date(Date.now() - 24 * 3600 * 1000).toISOString()`. Enforced **app-side** (no DB constraint —
`0005_self_publish.sql:34-36`: "app-level like its predecessor, so no schema here"), in three
places, each with a **mandatory `.eq('user_id', user.id)` filter**:

> "The explicit user filter matters — the select policy is own-OR-published, so an unfiltered
> count would include everyone else's published work." (`sign.ts:63-65`; same comment at
> `contribute/post.astro:29-30` and `contribute/list.astro:52-53`.)

1. **`/api/uploads/sign`** (`sign.ts:66-75`) — gates mixes, covers, AND photos (any presign):

```ts
const since = new Date(Date.now() - 24 * 3600 * 1000).toISOString();
const [uploads, albums] = await Promise.all([
  supabase.from('user_uploads').select('id', { count: 'exact', head: true }).eq('user_id', user.id).gte('created_at', since),
  supabase.from('photo_albums').select('id', { count: 'exact', head: true }).eq('user_id', user.id).gte('created_at', since),
]);
const recentCount = (uploads.count ?? 0) + (albums.count ?? 0);
if (recentCount >= MAX_CREATED_PER_DAY) { /* 429 */ }
```

2. **Post composer** (`contribute/post.astro:31-38`) — counts `posts` only, same
   head-count/`eq('user_id')`/`gte('created_at', since)` shape.
3. **List composer** (`contribute/list.astro:54-61`) — counts `lists` only, same shape.

So the caps are per-bucket: posts ≤20/24h, lists ≤20/24h, (uploads + photo_albums combined)
≤20/24h at presign time. Error message is identical everywhere:
`'Daily cap reached — twenty new pieces in 24 hours. Come back tomorrow.'`
A direct PostgREST insert is NOT capped (the cap lives in app code) — the iOS app must perform
the same pre-insert count checks to honor the contract.

### 8.3 Mix creation (`MixUploadForm.tsx`)

Order: presign+PUT cover (if any) → presign+PUT audio → probe duration client-side
(`Math.round(audio.duration)` seconds, null on failure; `MixUploadForm.tsx:12-24,66`) → insert
metadata row under RLS (`MixUploadForm.tsx:73-87`):

```ts
const { data, error } = await supabase
  .from('user_uploads')
  .insert({
    user_id: uid,
    title: title.trim(),
    description: description.trim() || null,
    tracklist: tracks,                 // textarea split on '\n', trimmed, blanks dropped
    r2_key: audioObj.key,
    cover_r2_key: coverObj?.key ?? null,
    duration,                          // integer seconds or null
    mime: audio.type,
    status: visibility,                // 'published' | 'private' — author's choice
  })
  .select('id')
  .single();
```

UI limits: title `maxLength={120}` (line 127), description `maxLength={2000}` (line 139). On
success navigate to `/mixes/<id>`.

### 8.4 Post creation (`contribute/post.astro:15-71`)

Server-side validation: title and body required; title ≤ 160 chars; body ≤ 20,000 chars
(lines 22-27). `status = form.get('visibility') === 'private' ? 'private' : 'published'` (line 20
— note: defaults to **published**). Slug generation (lines 39-44):

```ts
const slugBase =
  title
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 80) || 'post';
```

Insert: `{ user_id, slug: slugBase, title, body_md: body, status }` with `.select('id').single()`
(lines 45-49). On Postgres error code `'23505'` (unique `(user_id, slug)` collision) retry ONCE
with `slug: `${slugBase}-${crypto.randomUUID().slice(0, 8)}`` (lines 50-63). Success → redirect
`/posts/<id>`.

### 8.5 List creation (`contribute/list.astro:18-81`)

Item assembly from parallel form arrays (`item_type[]`, `item_title[]`, `item_note[]`,
`item_url[]`): blank-title rows skipped; `item_type` coerced to `'other'` if not in
`LIST_ITEM_TYPES`; title clipped to 200 chars, note to 500, empty note/url → null; URLs must
match `/^https?:\/\//` or the whole submit fails (lines 28-41,49-50). Validation: title required,
≤160; ≥1 item. Then two inserts:

```ts
.from('lists').insert({ user_id: user.id, title, description: description || null, status }).select('id').single();
// then
.from('list_items').insert(items.map((it, i) => ({ ...it, list_id: list.id, position: i })));
```

(lines 63-73; `status` same published-default rule, line 62). A failed items insert leaves an
empty list row behind (error surfaced, no rollback, lines 74-75). Success → `/lists/<id>`.

### 8.6 Photo album creation (`PhotoUploadForm.tsx:34-100`)

Client checks: ≥1 photo, ≤ `ALBUM_MAX_PHOTOS` (24), each `IMAGE_TYPES`-valid and ≤
`IMAGE_MAX_BYTES`. Flow comment (lines 55-57): "Album row first, ALWAYS private, then photos
attach one by one; only a complete album flips to the chosen visibility."

1. Insert album with `status: 'private'` regardless of the user's choice:
   `{ user_id, title: title.trim(), venue: venue.trim() || null, event_date: eventDate || null, description: description.trim() || null, status: 'private' }`
   (lines 58-69). `event_date` is the date-input string `YYYY-MM-DD`.
2. For each file in order: presign (`kind: 'photo'`) + PUT, then
   `supabase.from('photos').insert({ album_id: album.id, r2_key: obj.key, position: i })`
   (lines 76-82). A mid-batch failure aborts, leaving a private partial album.
3. If the user chose public AND every photo landed:
   `supabase.from('photo_albums').update({ status: 'published' }).eq('id', album.id)` (lines 91-95).

The iOS app must preserve this private-first ordering — it is what prevents half-albums from
appearing on the community shelf.

## 9. `report.ts` — reports and the visibility toggle

### FormData dispatch contract (web detail pages)

Each detail page handles `POST` to its own URL, reads the body **once**, and dispatches on the
`action` field (identical at `posts/[id].astro:17-25`, `mixes/[id].astro:17-25`,
`lists/[id].astro:17-25`, `photos/[id].astro:17-25`):

```ts
if (Astro.request.method === 'POST') {
  const form = await Astro.request.formData();
  if (form.get('action') === 'set-visibility') {
    visError = await setVisibility(Astro.locals, '<table>', id, form);
    if (!visError) return Astro.redirect(`/<section>/${id}`, 303);   // PRG
  } else {
    reportResult = await handleReport(form, Astro.locals, '<contentType>', id);
  }
}
```

Form fields: the toggle posts hidden inputs `action="set-visibility"` and
`visibility=<"published"|"private">` (computed as the opposite of the current status,
`VisibilityToggle.astro:13,22-23`); the report form posts only `reason` (textarea, `required`,
`maxlength="1000"`, `ReportForm.astro:22-28` — no `action` field, so "anything that isn't
set-visibility is a report"). The iOS app talks to Supabase directly, so it implements the two
underlying writes instead of these form posts — but the page↔table↔content_type mapping is the
contract:

| Page | `setVisibility` table | `handleReport` content_type |
| --- | --- | --- |
| `/mixes/<id>` | `'user_uploads'` | `'upload'` |
| `/posts/<id>` | `'posts'` | `'post'` |
| `/lists/<id>` | `'lists'` | `'list'` |
| `/photos/<id>` | `'photo_albums'` | `'photo_album'` |

(`mixes/[id].astro:20,23`; `posts/[id].astro:20,23`; `lists/[id].astro:20,23`;
`photos/[id].astro:20,23`.) `content_ref` is always the row's UUID as a string (the `reports`
column is `text`).

### `handleReport` (`src/lib/report.ts:10-30`) — exact behavior

1. No signed-in user → `{ ok: false, message: 'Sign in to report content.' }`.
2. `reason = String(form.get('reason') ?? '').trim().slice(0, 1000)`; empty →
   `{ ok: false, message: 'Say briefly what the problem is.' }`.
3. Insert (RLS: `auth.uid() = reporter_id`; `status` defaults to `'open'` in the DB):

```ts
const { error } = await locals.supabase.from('reports').insert({
  reporter_id: user.id,
  content_type: contentType,   // 'upload' | 'post' | 'list' | 'photo_album'
  content_ref: contentRef,     // the content row's UUID, as text
  reason,
});
```

4. Error → `{ ok: false, message: 'Could not file the report — try again.' }`;
   success → `{ ok: true, message: 'Reported — the curator will take a look.' }`.

There is no duplicate-report guard — the same user can report the same piece repeatedly.
Reporters can only ever read their own reports (`reports_select_own`, `0001_init.sql:305-307`).

### `setVisibility` (`src/lib/report.ts:39-54`) — exact behavior

```ts
const next = form.get('visibility') === 'published' ? 'published' : 'private';
const { error } = await locals.supabase
  .from(table)                       // 'user_uploads' | 'posts' | 'lists' | 'photo_albums'
  .update({ status: next })
  .eq('id', id)
  .eq('user_id', user.id);
return error ? 'Could not change visibility — try again.' : null;
```

- Not signed in → returns `'Sign in first.'` (line 46).
- Anything other than the exact string `'published'` coerces to `'private'`.
- RLS already enforces ownership and blocks removed rows ("a takedown can't be edited around"),
  "but the explicit user_id filter keeps the query honest" (`report.ts:33-36` comment) — keep
  both `.eq` filters on iOS.
- Important PostgREST gotcha: updating a row you can't touch (someone else's, or your own
  `removed` row — `for update using (auth.uid() = user_id and status <> 'removed')`,
  `0005_self_publish.sql:59,85,104,123`) does **not** error; it matches 0 rows. The web treats
  that as success and redirects (PRG). On iOS, request the updated row back
  (`.select()` / `Prefer: return=representation`) if you need to detect the no-op.
- For `removed` content the web hides the toggle entirely and shows:
  `"Taken down by the curator — reply to the takedown notice if you think that's wrong."`
  (`VisibilityToggle.astro:18-19`).

### Curator side (context only — service-role, never shipped in the iOS app)

`/admin/moderation` is gated on `ADMIN_EMAIL` and uses the service-role key (the only RLS bypass,
`moderation.astro:7-14`). Queue read: `reports.select('id, reporter_id, content_type, content_ref, reason, created_at').eq('status', 'open').order('created_at', { ascending: true })`
(`moderation.astro:74-78`). Report resolution: `reports.update({ status: <'reviewed'|'dismissed'> }).eq('id', id)`
(`moderation.astro:37-39`). Takedown: `update({ status: 'removed', reviewed_at: new Date().toISOString() })`
on the mapped content table (`moderation.astro:44-49`). Removed rows stay visible to their author
(select policies unchanged — `0005_self_publish.sql:14-19,127-131`); authors may still DELETE
their own rows, removed included (`0005_self_publish.sql:18-19`, delete policies at
`0001_init.sql:120-122,152-154`, `0002_ugc.sql:87-89,165-167`).

## 10. RLS write policies the iOS app must satisfy (verbatim, post-0005)

`user_uploads` (`0005_self_publish.sql:48-65`):

```sql
create policy "uploads_insert_own" on public.user_uploads
  for insert with check (
    auth.uid() = user_id
    and status in ('private', 'published')
    and r2_key like 'user/' || auth.uid()::text || '/%'
    and (cover_r2_key is null or cover_r2_key like 'user/' || auth.uid()::text || '/%')
  );

create policy "uploads_update_own" on public.user_uploads
  for update using (auth.uid() = user_id and status <> 'removed')
  with check (
    auth.uid() = user_id
    and status in ('private', 'published')
    and r2_key like 'user/' || auth.uid()::text || '/%'
    and (cover_r2_key is null or cover_r2_key like 'user/' || auth.uid()::text || '/%')
  );
```

`posts` (`0005_self_publish.sql:79-86`):

```sql
create policy "posts_insert_own" on public.posts
  for insert with check (auth.uid() = user_id and status in ('private', 'published'));

create policy "posts_update_own" on public.posts
  for update using (auth.uid() = user_id and status <> 'removed')
  with check (auth.uid() = user_id and status in ('private', 'published'));
```

`lists` and `photo_albums` have the identical shape (`0005_self_publish.sql:98-105,117-124`).
`photos` insert additionally requires album ownership AND the key prefix (`0002_ugc.sql:188-193`):

```sql
create policy "photos_insert" on public.photos
  for insert with check (
    exists (select 1 from public.photo_albums a where a.id = album_id and a.user_id = auth.uid())
    and r2_key like 'user/' || auth.uid()::text || '/%'
  );
```

`list_items` insert/update/delete require owning the parent list (`0002_ugc.sql:113-131`).

## 11. Cross-cutting facts and gotchas

- **Self-publish, no review queue**: status is purely the author's visibility choice; published
  content is live immediately (migration 0005 header, `0005_self_publish.sql:3-9`).
- **`maybeSingle()` + redirect**: "not found" and "not visible to you" are indistinguishable on
  detail reads; the web redirects to `/community` in both cases.
- **Fallback artwork**: `'/images/cryo_01.jpg'` (a static asset of the web app, e.g.
  `community.astro:23`) — the iOS app needs its own bundled placeholder.
- **`tracklist`** is JSONB but contractually a flat array of strings; filter non-strings on read
  (`mixes/[id].astro:42-44`).
- **Markdown applies only to `posts.body_md`.** All other descriptive text fields render as plain
  text.
- **Author display fallback** is the exact string `'a listener'`.
- **Cap checks are client-of-the-API responsibility** for posts/lists (no server endpoint exists
  for them — the web page does the count inline before insert); for uploads the `/api/uploads/sign`
  endpoint enforces it server-side per presign.
- The `playlists`/`favorites`/`listen_status`/`wall_comments` tables exist in the same database
  (e.g. `0001_init.sql:56-86,159`) but are outside this contract.
