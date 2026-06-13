# Quiet Cast — Listen-state, Favorites & Library contract (iOS)

Scope: everything a SwiftUI client needs to implement **favorites**, **listen/progress
tracking**, and the **read-side understanding of playlists** against the same Supabase
project the web app uses. Playlist *management* is deferred from iOS v1; its data model
is documented here because the tables share the same content key.

All facts below were read from source on 2026-06-12. Citations are `path:line` relative
to `/Users/roblark/Projects/quietcast/front-end-astro/`.

---

## 1. The content key: `content_ref`

Every per-user table (favorites, listen_status, playlist_items) keys content by a single
string column `content_ref`. **For Sanity episodes this is the episode slug
(`slug.current`), not the Sanity `_id`.**

Authoritative comment, `src/lib/listen.ts:10-12`:

```ts
 * `content_ref` is the one cross-feature key for a content item: for Sanity
 * episodes it's the slug (== player Track.id); user uploads will use their
 * upload UUID. favorites/playlists key on the same value.
```

The player `Track.id` is set from the slug — `src/lib/content.ts:105-109`:

```ts
export function trackOf(e: Episode): Track {
  return {
    id: e.slug,
```

The slug itself comes from this GROQ projection and filter — `src/lib/content.ts:53` and
`src/lib/content.ts:89`:

```groq
"slug": slug.current,
```

```ts
const FILTER = `_type == "interview" && defined(slug.current) && defined(audio.asset)`;
```

There is a slug fallback `r.slug ?? String(r.cat)` in `src/lib/content.ts:68`, but the
GROQ filter requires `defined(slug.current)`, so every episode that can play has a real
slug. iOS MUST use the same slug string as `content_ref` or per-user state will not be
shared with the web app.

Pages stamp the same value into the DOM: `data-qc-ref={e.slug}` (`src/pages/index.astro:29`,
`src/pages/archive.astro:92`, `src/pages/show/[slug].astro:43`).

Future-proofing: user-uploaded mixes will use their `user_uploads` UUID as `content_ref`
(`src/lib/listen.ts:11`, `supabase/migrations/0001_init.sql:54`). iOS should treat
`content_ref` as an opaque string.

---

## 2. Access model (applies to every table here)

- Browser client = Supabase **anon/publishable key** + the signed-in user's session
  (magic-link auth). RLS scopes every row to its owner, so **selects/deletes carry no
  explicit `user_id` filter**; the policies do the scoping (`src/lib/supabase.ts:5-9`,
  `src/lib/listen.ts:6-8`).
- Inserts/upserts DO set `user_id` explicitly (required to satisfy the
  `with check (auth.uid() = user_id)` clauses).
- Logged out: every fetch resolves to empty (`src/lib/listen.ts:107`,
  `src/lib/library.ts:67`); writes are no-ops (`src/lib/listen.ts:58`,
  `src/lib/library.ts:84-85`). Tapping a favorite/playlist button while logged out
  redirects to `/login` on web (`src/islands/LibraryControls.tsx:57-59,76-78`).
- iOS equivalent: supabase-swift with the same project URL + anon key and an
  authenticated session; the JWT makes `auth.uid()` work in the policies.

The user id is read from the local session, no network round trip —
`src/lib/listen.ts:37-42`:

```ts
export async function currentUserId(): Promise<string | null> {
  if (_userId !== undefined) return _userId;
  const { data } = await db().auth.getSession();
  _userId = data.session?.user?.id ?? null;
  return _userId;
}
```

---

## 3. `favorites`

### 3.1 Schema + RLS (verbatim, `supabase/migrations/0001_init.sql:56-67`)

```sql
create table if not exists public.favorites (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users (id) on delete cascade,
  content_ref text not null,
  created_at  timestamptz not null default now(),
  unique (user_id, content_ref)
);
alter table public.favorites enable row level security;

drop policy if exists "favorites_rw_own" on public.favorites;
create policy "favorites_rw_own" on public.favorites
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
```

Uniqueness: one row per `(user_id, content_ref)`. Favorites are strictly private —
there is no public read policy.

### 3.2 Read

The web fetches the user's **entire** favorite set in one query and caches it as a
`Set<string>` for the session — `src/lib/library.ts:64-72`:

```ts
const { data, error } = await db().from('favorites').select('content_ref');
```

(no `user_id` filter — RLS scopes it; no pagination — the set is assumed small).

### 3.3 Toggle semantics (`src/lib/library.ts:83-111`)

Optimistic flip with rollback:

1. Logged out → return `false`, no write.
2. Flip the cached set immediately and emit the UI event, **before** the network call.
3. Favoriting → `insert({ user_id: uid, content_ref: ref })`
   (`src/lib/library.ts:96`). A Postgres unique-violation is treated as success:

   ```ts
   // unique(user_id, content_ref): a duplicate just means it's already saved.
   if (error && error.code === '23505') error = null;
   ```

   (`src/lib/library.ts:97-98`)
4. Unfavoriting → `delete().eq('content_ref', ref)` (`src/lib/library.ts:100`) — note
   **no `user_id` filter**; RLS restricts the delete to the caller's own row.
5. Any other error → revert the cache and re-emit the prior state; return the prior
   state (`src/lib/library.ts:103-109`).

### 3.4 UI surfaces

- Favorite buttons exist on the home grid (`src/pages/index.astro:53`) and the show page
  (`src/pages/show/[slug].astro:43`); state is painted as `data-qc-fav="on|off"`
  (`src/islands/LibraryControls.tsx:39-45`). Filled-heart accent color is `var(--ember)`
  (`src/pages/index.astro:232-240`).
- The `/playlists` "Library" page lists favorites (newest set order is whatever the
  select returns; no explicit order on the favorites select) with play-all and remove
  (`src/islands/PlaylistManager.tsx:166-216`).
- The SSR dashboard reads the 15 most recent favorites for the activity feed —
  `src/pages/dashboard.astro:167-173`:

  ```ts
  supabase.from('favorites')
    .select('content_ref, created_at')
    .order('created_at', { ascending: false })
    .limit(15),
  ```

---

## 4. `listen_status`

### 4.1 Schema + RLS (verbatim, `supabase/migrations/0001_init.sql:72-86`)

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

drop policy if exists "listen_status_rw_own" on public.listen_status;
create policy "listen_status_rw_own" on public.listen_status
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
```

Strictly private (owner-only policy). One row per `(user_id, content_ref)`.

### 4.2 States and display mapping

DB statuses: `'unplayed' | 'playing' | 'played'` (check constraint above). The client
**never writes `'unplayed'`** — absence of a row means unplayed. Display mapping,
`src/lib/listen.ts:16` and `src/lib/listen.ts:45-49`:

```ts
export type ListenState = 'unplayed' | 'in-progress' | 'done';
```

```ts
export function stateFromStatus(status: string | null | undefined): ListenState {
  if (status === 'played') return 'done';
  if (status === 'playing') return 'in-progress';
  return 'unplayed';
}
```

### 4.3 When writes happen — ALL automatic from playback; there is no manual control

There is no "mark as played/unplayed" UI anywhere; the only writer is the player.
Constants (`src/lib/listen.ts:18-21`, `src/islands/PlayerDock.tsx:41-44`):

```ts
/** ≥90% played counts as "done" (locked feature rule). */
export const DONE_RATIO = 0.9;
/** Don't persist trivial scrubbing / mis-clicks. */
const MIN_RECORD_SECONDS = 5;
```

```ts
/** How often to persist progress while playing (throttles DB writes). */
const WRITE_EVERY_SECONDS = 20;
/** Only resume if the saved position is past this (avoids tiny jumps). */
const MIN_RESUME_SECONDS = 10;
```

The single write path, `src/lib/listen.ts:52-81` (verbatim core):

```ts
export async function recordProgress(
  ref: ContentRef,
  progressSeconds: number,
  durationSeconds: number,
): Promise<void> {
  const uid = await currentUserId();
  if (!uid || !Number.isFinite(progressSeconds) || progressSeconds < MIN_RECORD_SECONDS) return;

  const done = durationSeconds > 0 && progressSeconds / durationSeconds >= DONE_RATIO;
  const status = done ? 'played' : 'playing';

  const { error } = await db().from('listen_status').upsert(
    {
      user_id: uid,
      content_ref: ref,
      status,
      progress_seconds: Math.floor(progressSeconds),
      updated_at: new Date().toISOString(),
    },
    { onConflict: 'user_id,content_ref' },
  );
```

Exact upsert/conflict contract: PostgREST upsert with
`onConflict: 'user_id,content_ref'` (matches the table's unique constraint);
`progress_seconds` is floored to an integer; `updated_at` is a **client-supplied** ISO
timestamp.

Call sites (`src/islands/PlayerDock.tsx`):

| Trigger | Code | Effect |
|---|---|---|
| While playing, throttled | `onTimeUpdate`: write when `t - lastWriteRef.current >= WRITE_EVERY_SECONDS` and `!a.paused` (`PlayerDock.tsx:204-208`) | upsert roughly every 20s of media time |
| Pause | `onPause`: flush current position (`PlayerDock.tsx:215-219`) | upsert at the paused position |
| Track ends | `onEnded`: `recordProgress(track.id, d, d)` where `d = a.duration \|\| duration` (`PlayerDock.tsx:220-225`) | ratio 1.0 ≥ 0.9 → `status='played'` |

Transition rules implied by the code (iOS must replicate):

- no row → `'playing'` once ≥5s have been played (first throttled write or pause).
- `'playing'` → `'played'` when `progress/duration ≥ 0.9` at any write, or on ended.
- `'played'` → `'playing'` **can happen**: the upsert recomputes status on every write,
  so re-listening to a finished episode from the start flips it back to in-progress
  until 90% is crossed again. There is no terminal/sticky "done".
- Writes with progress `< 5s` are dropped entirely (`listen.ts:58`), so a finished
  episode replayed for under 5 seconds keeps its `'played'` row untouched.

### 4.4 Resume positions — they exist

`progress_seconds` doubles as the resume point. Fetch, `src/lib/listen.ts:84-96`:

```ts
const { data, error } = await db()
  .from('listen_status')
  .select('progress_seconds, status')
  .eq('content_ref', ref)
  .maybeSingle();
```

(again no `user_id` filter — RLS + the unique constraint guarantee ≤1 row).

Resume policy on track load, `src/islands/PlayerDock.tsx:87-92`:

```ts
void fetchProgress(next.id).then((p) => {
  if (p && p.status === 'playing' && p.progressSeconds > MIN_RESUME_SECONDS) {
    resumeRef.current = { id: next.id, seconds: p.progressSeconds };
```

and the seek guard, `src/islands/PlayerDock.tsx:70-73`:

```ts
if (r.seconds > 0 && r.seconds < a.duration * 0.97) {
  a.currentTime = r.seconds;
```

So: resume **only** when `status === 'playing'` AND saved position `> 10s` AND saved
position `< 97%` of the real duration. Episodes with `status === 'played'` restart from
0. There is exactly one position per (user, episode) — no per-device positions, no
listening history rows.

### 4.5 Reading the whole state map

`src/lib/listen.ts:104-112` — one unpaginated select of every row for the user, cached
per session:

```ts
const { data, error } = await db().from('listen_status').select('content_ref, status');
const map = new Map<ContentRef, ListenState>();
if (!error && data) for (const r of data) map.set(r.content_ref, stateFromStatus(r.status));
```

The SSR dashboard also reads the 15 most recent rows for "recent activity" —
`src/pages/dashboard.astro:174-180`:

```ts
supabase.from('listen_status')
  .select('content_ref, status, progress_seconds, updated_at')
  .order('updated_at', { ascending: false })
  .limit(15),
```

---

## 5. How the web merges per-user state into episode lists (the iOS pattern)

Web architecture: episode lists are **static, anonymous HTML** (built from Sanity).
Per-user state is overlaid client-side after load — the catalog data and the user data
never mix server-side.

1. Each episode cell carries `data-qc-ref={slug}` (`src/pages/index.astro:29`,
   `src/pages/archive.astro:92`).
2. An invisible island fetches the full state map once and stamps
   `data-qc-state="unplayed|in-progress|done"` onto every `[data-qc-ref]` element;
   **missing entries default to `'unplayed'`** — `src/islands/ListenState.tsx:18-25`:

   ```ts
   const states = await fetchStates(force);
   document.querySelectorAll<HTMLElement>('[data-qc-ref]').forEach((el) => {
     const ref = el.dataset.qcRef;
     if (ref) el.dataset.qcState = states.get(ref) ?? 'unplayed';
   });
   ```

3. After each successful progress write the player emits a `qc:listen` event
   (`src/lib/listen.ts:28,78-80`) carrying `{ ref, state }`; the island updates just the
   matching cells without refetching (`src/islands/ListenState.tsx:27-35`). Favorites
   mirror this with `qc:favorite` `{ ref, favorite }` (`src/lib/library.ts:37,50-52`).
4. Caches are session-long, in-memory, invalidated on auth change
   (`src/lib/listen.ts:115-118`, `src/lib/library.ts:304-308`).

**iOS translation:** fetch `listen_status (content_ref, status)` and
`favorites (content_ref)` once per session, hold `[slug: ListenState]` and `Set<slug>`
in memory, join against the Sanity episode list by slug with `'unplayed'` / not-favorite
as defaults, and update the in-memory maps optimistically on each local write (the web
never refetches after a write).

Visual semantics (for design parity; theme tokens in `src/styles/tokens.css` — dark
`--ember: #b08a5e` line 39, light `--ember: #84592e` line 109):

- Home grid (`src/pages/index.astro:281-303`): `in-progress` → ember dot + 1px ember
  outline on the card; `done` → small ✓ badge and the cover desaturation is *relaxed*
  (`grayscale(0.2)` vs the resting `0.55`) — "filed away" reads as visited.
- Archive calendar (`src/pages/archive.astro:231-239`): `in-progress` → ember ring/text
  on the day cell; `done` → 22% ember fill + ember border.

---

## 6. Playlists (read-side contract; management deferred from iOS v1)

### 6.1 Schema + RLS (verbatim, `supabase/migrations/0001_init.sql:159-223`)

```sql
create table if not exists public.playlists (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users (id) on delete cascade,
  name        text not null,
  description text,
  is_public   boolean not null default false,
  created_at  timestamptz not null default now()
);
```

```sql
create policy "playlists_select_own_or_public" on public.playlists
  for select using (auth.uid() = user_id or is_public);
```

(insert/update/delete are owner-only: `with check (auth.uid() = user_id)` /
`using (auth.uid() = user_id)`, `0001_init.sql:173-183`.)

```sql
create table if not exists public.playlist_items (
  id          uuid primary key default gen_random_uuid(),
  playlist_id uuid not null references public.playlists (id) on delete cascade,
  content_ref text not null,
  position    integer not null default 0,
  added_at    timestamptz not null default now()
);
```

`playlist_items` access follows the parent playlist (select if owner or public; writes
owner-only), e.g. `0001_init.sql:197-203`:

```sql
create policy "playlist_items_select" on public.playlist_items
  for select using (
    exists (
      select 1 from public.playlists p
      where p.id = playlist_id and (p.user_id = auth.uid() or p.is_public)
    )
  );
```

Note: there is **no unique constraint on `(playlist_id, content_ref)`** — duplicate
prevention is client-side only (`src/lib/library.ts:217-218` no-ops if the ref is
already present).

### 6.2 How the web reads them (replicate if iOS ever lists playlists read-only)

- My playlists, newest first, with item counts via a PostgREST embedded aggregate —
  `src/lib/library.ts:144-149`:

  ```ts
  .from('playlists')
  .select('id, name, description, is_public, created_at, playlist_items(count)')
  .eq('user_id', uid)
  .order('created_at', { ascending: false });
  ```

- Items in order — `src/lib/library.ts:203-208`:

  ```ts
  .from('playlist_items')
  .select('id, content_ref, position')
  .eq('playlist_id', playlistId)
  .order('position', { ascending: true })
  .order('added_at', { ascending: true });
  ```

- Membership check for one ref across my playlists (inner-join filter) —
  `src/lib/library.ts:288-292`:

  ```ts
  .from('playlist_items')
  .select('playlist_id, playlists!inner(user_id)')
  .eq('content_ref', ref)
  .eq('playlists.user_id', uid);
  ```

- Append semantics: `position = (last item's position ?? -1) + 1`
  (`src/lib/library.ts:219`); reorder rewrites `position = 0..n-1` row-by-row
  (`src/lib/library.ts:258-261`). Name length is capped at 80 chars in the UI only
  (`src/islands/PlaylistManager.tsx:232`, `src/islands/LibraryControls.tsx:215`); no DB
  constraint.

### 6.3 Do playlists affect anything in iOS-v1 scope?

**No.** Verified interactions:

- Favorites and listen_status never read or join playlists
  (`src/lib/listen.ts`, `src/lib/library.ts:61-111` — favorites section is independent).
- Playing a playlist just dispatches a queue of Tracks whose `id`s are `content_ref`s
  (`src/islands/PlaylistManager.tsx:40-46`); playback then writes `listen_status` through
  the normal player path. Same for "play all favorites".
- `content_ref → Track` resolution on the web library page comes from a server-rendered
  JSON index of **all episodes** (`src/pages/playlists.astro:10-11,23`,
  `src/islands/PlaylistManager.tsx:29-38`); refs that don't resolve (future uploads) are
  displayed by raw ref and skipped when building the play queue
  (`src/islands/PlaylistManager.tsx:62,66`). iOS can resolve refs against its own Sanity
  episode list by slug the same way.
- `is_public` playlists are readable by anyone per RLS, but no current page consumes
  other users' public playlists (`src/lib/library.ts:147` — "this UI is 'my playlists'
  only").

So an iOS v1 that ships favorites + listen-state and ignores playlists entirely loses
nothing and breaks nothing; web-created playlists keep working.

---

## 7. Time/progress summary (explicit)

- **Resume positions exist**: `listen_status.progress_seconds` (integer seconds,
  floored), one per (user, episode), resumed only when `status='playing'`, position
  `>10s` and `<97%` of duration (section 4.4).
- **No** listening-history table, **no** per-device positions, **no** scrobble log,
  **no** server timestamps (`updated_at` is client-set), **no** playback-rate or
  completion-count tracking. `created_at` on favorites is the only other timestamp.

## 8. Implementation checklist for iOS

1. Sign in with Supabase (magic-link parity) → JWT makes RLS work.
2. `content_ref` = Sanity episode `slug.current` everywhere.
3. On launch/sign-in: `select content_ref, status from listen_status` and
   `select content_ref from favorites`; default unplayed/not-favorite.
4. Favorite toggle: optimistic; insert `{user_id, content_ref}` treating Postgres
   `23505` as success; delete by `content_ref`; rollback on other errors.
5. Progress: write every ~20s while playing, on pause, and on end (`duration/duration`);
   skip writes under 5s of progress; status = `progress/duration ≥ 0.9 ? 'played' :
   'playing'`; upsert on `user_id,content_ref`; floor seconds; ISO `updated_at`.
6. Resume on play per the three guards in section 4.4.
7. Playlists: nothing required for v1; do not write `playlist_items` without
   replicating the client-side dedupe and `position` append rule.
