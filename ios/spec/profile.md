# Quiet Cast — Profile / Dashboard Contract (iOS)

Contract for the listener profile surfaces, derived from the Astro web app at
`front-end-astro/`. A Swift engineer should be able to implement the iOS
profile screens from this file alone. Every fact cites `file:line` in the web
repo for provenance; quoted code is verbatim.

Scope note (iOS v1): the rotation grid ships **READ-ONLY with no reordering**.
All grid-write affordances are documented below but marked OUT OF SCOPE.

---

## 1. Backends

Two backends, both reachable directly from a native client:

- **Supabase** (Postgres + RLS + Auth). Client env:
  `PUBLIC_SUPABASE_URL`, `PUBLIC_SUPABASE_ANON_KEY`
  (`astro.config.mjs:61-62`). All profile data except episodes lives here.
  RLS is the authorization layer — the web app never uses a privileged key on
  these pages; the iOS app talks to PostgREST with the anon key + the user's
  JWT and gets identical visibility.
- **Sanity CDN** (editorial episodes). Read-only public client
  (`src/lib/sanity.ts:13-19`):

  ```ts
  export const sanity = createClient({
    projectId: PUBLIC_SANITY_PROJECT_ID,
    dataset: PUBLIC_SANITY_DATASET,
    apiVersion: '2025-01-01',
    useCdn: true,
    perspective: 'published',
  });
  ```

- **R2 CDN** for user-uploaded bytes (audio, covers, grid images). Public read
  URL = `${PUBLIC_CDN_URL}/<key>` with default
  `https://cdn.quietcast.art` (`astro.config.mjs:76`, `src/lib/ugc.ts:33-36`):

  ```ts
  export function cdnUrl(key: string): string {
    return `${PUBLIC_CDN_URL.replace(/\/$/, '')}/${key}`;
  }
  ```

---

## 2. Supabase data model (profile-relevant tables)

### 2.1 `profiles` — world-readable identity row

`supabase/migrations/0001_init.sql:10-28`:

```sql
create table if not exists public.profiles (
  id           uuid primary key references auth.users (id) on delete cascade,
  display_name text,
  avatar_url   text,
  created_at   timestamptz not null default now()
);
alter table public.profiles enable row level security;

drop policy if exists "profiles_select_all" on public.profiles;
create policy "profiles_select_all" on public.profiles
  for select using (true);

drop policy if exists "profiles_insert_own" on public.profiles;
create policy "profiles_insert_own" on public.profiles
  for insert with check (auth.uid() = id);

drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own" on public.profiles
  for update using (auth.uid() = id) with check (auth.uid() = id);
```

A trigger auto-creates a row on signup with `display_name` defaulted from user
metadata or the email local-part (`0001_init.sql:32-50`).

### 2.2 `profile_details` — privacy-sensitive 1:1 extension

`supabase/migrations/0003_profile.sql:13-37`:

```sql
create table if not exists public.profile_details (
  id               uuid primary key references auth.users (id) on delete cascade,
  is_public        boolean not null default false,
  bio              text,
  status_line      text,
  -- content_ref of the profile song: an episode slug or a published
  -- user_uploads id (same convention as favorites.content_ref).
  profile_song_ref text,
  -- Stored now, applied when light mode ships.
  theme            text not null default 'dark' check (theme in ('dark', 'light')),
  updated_at       timestamptz not null default now()
);
alter table public.profile_details enable row level security;

drop policy if exists "details_select_public_or_own" on public.profile_details;
create policy "details_select_public_or_own" on public.profile_details
  for select using (is_public or auth.uid() = id);

drop policy if exists "details_insert_own" on public.profile_details;
create policy "details_insert_own" on public.profile_details
  for insert with check (auth.uid() = id);

drop policy if exists "details_update_own" on public.profile_details;
create policy "details_update_own" on public.profile_details
  for update using (auth.uid() = id) with check (auth.uid() = id);
```

The row is "created lazily by app-level upsert" (`0003_profile.sql:11`) — it
may not exist; treat a missing row like `is_public = false` / all-null.

### 2.3 `connections` — the rotation grid

`supabase/migrations/0003_profile.sql:44-82`:

```sql
create table if not exists public.connections (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references auth.users (id) on delete cascade,
  kind       text not null default 'other'
               check (kind in ('artist', 'label', 'venue', 'podcast', 'photographer', 'listener', 'other')),
  name       text not null,
  image_url  text,
  link_url   text,
  position   integer not null default 0,
  created_at timestamptz not null default now(),
  unique (user_id, name)
);
alter table public.connections enable row level security;

drop policy if exists "connections_select" on public.connections;
create policy "connections_select" on public.connections
  for select using (
    auth.uid() = user_id
    or exists (
      select 1 from public.profile_details d
      where d.id = user_id and d.is_public
    )
  );

drop policy if exists "connections_insert_own" on public.connections;
create policy "connections_insert_own" on public.connections
  for insert with check (auth.uid() = user_id);

drop policy if exists "connections_update_own" on public.connections;
create policy "connections_update_own" on public.connections
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "connections_delete_own" on public.connections;
create policy "connections_delete_own" on public.connections
  for delete using (auth.uid() = user_id);

create index if not exists connections_user_idx on public.connections (user_id, position);
```

### 2.4 `wall_comments` — the comment wall

`supabase/migrations/0004_wall.sql:9-68`:

```sql
create table if not exists public.wall_comments (
  id         uuid primary key default gen_random_uuid(),
  -- whose wall the comment sits on
  profile_id uuid not null references auth.users (id) on delete cascade,
  author_id  uuid not null references auth.users (id) on delete cascade,
  body       text not null check (char_length(body) between 1 and 1000),
  status     text not null default 'published'
               check (status in ('published', 'removed')),
  created_at timestamptz not null default now()
);
alter table public.wall_comments enable row level security;

drop policy if exists "wall_select" on public.wall_comments;
create policy "wall_select" on public.wall_comments
  for select using (
    status = 'published'
    and (
      auth.uid() in (profile_id, author_id)
      or exists (
        select 1 from public.profile_details d
        where d.id = profile_id and d.is_public
      )
    )
  );

drop policy if exists "wall_insert_author" on public.wall_comments;
create policy "wall_insert_author" on public.wall_comments
  for insert with check (
    auth.uid() = author_id
    and status = 'published'
    and exists (
      select 1 from public.profile_details d
      where d.id = profile_id and d.is_public
    )
    and not exists (
      select 1 from public.blocks b
      where b.blocker_id = profile_id and b.blocked_id = author_id
    )
    and not exists (
      select 1 from public.blocks b
      where b.blocker_id = author_id and b.blocked_id = profile_id
    )
  );

drop policy if exists "wall_delete_owner_or_author" on public.wall_comments;
create policy "wall_delete_owner_or_author" on public.wall_comments
  for delete using (auth.uid() in (profile_id, author_id));

-- No user update policy: takedowns happen through the service-role client.

create index if not exists wall_comments_profile_idx
  on public.wall_comments (profile_id, created_at desc);
```

There is no review queue: "Comments go live immediately" (`0004_wall.sql:4`).

### 2.5 `reports` — report a wall note

Table from `0001_init.sql:290-307`; `content_type` widened by
`0004_wall.sql:73-76`:

```sql
alter table public.reports drop constraint if exists reports_content_type_check;
alter table public.reports
  add constraint reports_content_type_check
  check (content_type in ('upload', 'message', 'post', 'playlist', 'list', 'photo_album', 'wall_comment'));
```

Insert/select policies (`0001_init.sql:301-307`):

```sql
create policy "reports_insert_own" on public.reports
  for insert with check (auth.uid() = reporter_id);

create policy "reports_select_own" on public.reports
  for select using (auth.uid() = reporter_id);
```

Columns used by the wall report flow: `reporter_id uuid`, `content_type text`,
`content_ref text`, `reason text` (`0001_init.sql:290-298`).

### 2.6 Private activity sources (owner-only)

`favorites` (`0001_init.sql:56-67`) and `listen_status`
(`0001_init.sql:72-86`) are RLS'd `for all using (auth.uid() = user_id)` —
**only the owner can read them**. That is why the public profile's activity
feed has no favorite/listening rows (Section 7).

```sql
create table if not exists public.favorites (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users (id) on delete cascade,
  content_ref text not null,
  created_at  timestamptz not null default now(),
  unique (user_id, content_ref)
);
```

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
```

`content_ref` convention (both tables, plus `profile_details.profile_song_ref`):
either a **Sanity episode slug** or a **`user_uploads` uuid**
(`0001_init.sql:54`, `0003_profile.sql:18-19`).

### 2.7 UGC tables (read on profiles)

Four content tables feed the profile: `user_uploads` (mixtapes), `posts`,
`lists`, `photo_albums`. After migration 0005 the status vocabulary on all
four is `check (status in ('private', 'published', 'removed'))` with default
`'private'` (`supabase/migrations/0005_self_publish.sql:44-46` for
user_uploads; same pattern at `:75-77`, `:94-96`, and photo_albums at `:110+`).
RLS lets anyone select `status = 'published'` rows and owners their own.

---

## 3. Routes and visibility

Two pages share one component (`src/components/ProfilePage.astro`):

- **`/dashboard`** — own profile, requires sign-in; anonymous users redirect
  to `/login` (`src/pages/dashboard.astro:28-29`).
- **`/u/[id]`** — public profile; `id` is the user uuid. Visible iff the
  `profiles` row exists AND (`profile_details.is_public` OR the viewer is the
  owner); otherwise the page 404s with a "This page is private" screen
  (`src/pages/u/[id].astro:85-89, 163-170`):

  ```ts
  const visible = Boolean(profile && (details?.is_public || own));
  if (!visible) Astro.response.status = 404;
  ```

Owners viewing their own `/u/[id]` see a preview banner
(`src/pages/u/[id].astro:155-161`):
`'Preview — this is how visitors see your page.'` when public, else
`'Preview — your page is private, so only you can see this. Make it public in Settings.'`

RLS makes the same restrictions hold server-side: a non-owner querying a
private user's `profile_details`, `connections`, or `wall_comments` simply
gets zero rows (Sections 2.2-2.4). iOS should replicate the `visible` check
client-side to choose between the profile screen and the private/404 screen.

---

## 4. Public profile `/u/[id]` — sections in render order

Layout: two columns — left sidebar (300px) then main column; single column
below 920px width (`ProfilePage.astro:509-514, 1076-1084`). Render order in
the markup (`ProfilePage.astro:93-441`):

1. **Preview banner** (owner-preview only, `:94`).
2. **Left sidebar** (`<aside class="p-side">`, `:97-194`):
   1. **Profile card** (`:98-158`) — see Section 5.
   2. **Account box** — editable view only, never on public (`:161-173`).
   3. **`side` slot** (`:175`) — dashboard fills it with "Continue
      listening"; empty on `/u/[id]`.
   4. **"Meanwhile on Quiet Cast" site-news box** (`:177-193`) — rendered on
      BOTH routes when non-empty. See Section 8.
3. **Main column** (`:196-439`):
   1. **About / bio** (`:197-213`) — shown when `bio` is set, or always on
      the editable view (empty state links to `/settings`). Bio renders as
      plain text with `white-space: pre-line` (`:776`).
   2. **Latest activity** (`:215-243`) — see Section 7. Header shows the
      count; rows are `kind` eyebrow + linked text + optional `note` chip +
      date.
   3. **Rotation grid** "`{displayName}'s rotation`" (`:245-350`) — see
      Section 6. Header shows `connections.length`. Empty state: public
      `'Nothing pinned yet.'`; editable
      `'Nothing pinned yet. Your rotation is the artists, labels, and places that shape your listening.'`
      (`:252-257`).
   4. **Wall** "`{displayName}'s wall`" (`:352-436`) — see Section 9.
   5. **`manage` slot** (`:438`) — dashboard-only "My pages"; empty on
      `/u/[id]`.

### Data fetched for `/u/[id]` (`src/pages/u/[id].astro:85-126`)

Performed with the viewer's Supabase session (or anon):

| # | Call | Table / source | Columns | Filters / order / limit |
|---|------|----------------|---------|--------------------------|
| 1 | `getProfileRow(supabase, id)` | `profiles` | `id, display_name, avatar_url, created_at` | `eq('id', id)`, `maybeSingle` (`profile.ts:97-101`) |
| 2 | `getProfileDetails(supabase, id)` | `profile_details` | `is_public, bio, status_line, profile_song_ref, theme` | `eq('id', id)`, `maybeSingle` (`profile.ts:104-115`) |
| 3 | `getEpisodes()` | Sanity GROQ | see Section 10 | all published interviews |
| 4 | `getConnections(supabase, id)` | `connections` | `id, kind, name, image_url, link_url, position, created_at` | `eq('user_id', id)`, `order('position', asc)` (`profile.ts:117-125`) |
| 5 | `getUserContent(supabase, id, true)` | `user_uploads`, `posts`, `lists`, `photo_albums` | `id, title, status, created_at` | `eq('user_id', id)`, `eq('status','published')` (publishedOnly=true), `order('created_at', desc)`, `limit(8)` each (`profile.ts:127-149`) |
| 6 | `getSiteNews(supabase, episodes)` | episodes + 4 UGC tables | see Section 8 | site-wide, not per-profile |
| 7 | `getWallComments(supabase, id)` | `wall_comments` | `id, author_id, body, created_at` | `eq('profile_id', id)`, `eq('status','published')`, `order('created_at', desc)`, `limit(30)` (`wall.ts:34-48`) |
| 8 | `resolveWallEntries` | `profiles` + `profile_details` | bylines | batched `.in('id', authorIds)` (`wall.ts:51-65`, `ugc.ts:99-136`) |
| 9 | profile song | see Section 11 | | only when `details.profile_song_ref` set (`u/[id].astro:119-121`) |

The public activity feed is built from #4, #5, and the wall entries ONLY —
no favorites/listens (`u/[id].astro:104`):

```ts
const activity = buildActivity({ content, episodesByRef: epByRef, connections, wallNotes: wall });
```

All Supabase reads degrade to empty arrays / null on error via
`safeRows`/`safeRow` (`profile.ts:75-95`) — iOS should treat query failures
on these surfaces as empty sections, not hard errors.

---

## 5. Profile card anatomy (`ProfilePage.astro:98-158`)

Top-to-bottom inside the card:

1. **Avatar** — `avatar_url` as a square (`aspect-ratio: 1`, `:535-543`)
   image; fallback is the uppercased first character of the display name in a
   large serif block (`:84`, `:100-104`):
   `const initial = (displayName.trim()[0] ?? 'Q').toUpperCase();`
2. **Display name** as the `h1` (`:107`).
   - `/u/[id]`: `profile?.display_name || 'A listener'` (`u/[id].astro:123`).
   - `/dashboard`: `profile?.display_name || user.email?.split('@')[0] || 'Listener'`
     (`dashboard.astro:206`).
3. **Kind line**: literally `listener`, with "` · private`" appended when
   `is_public` is false (`:108`):
   `listener{isPublic ? '' : ' · private'}`
4. **Status line** — `profile_details.status_line`, rendered in italic inside
   typographic quotes: `“{statusLine}”` (`:109`).
5. **Meta list** (`:110-113`): `Tuned in since {memberSince}` where
   memberSince = `created_at` formatted as long month + year, e.g. "June
   2026" (`u/[id].astro:124-126`,
   `new Intl.DateTimeFormat('en', { month: 'long', year: 'numeric' })`);
   plus the account **email** on the dashboard only (never passed on the
   public route — `ProfilePage.astro:26-27`).
6. **Profile song button** — only when a track resolved AND has a `src`
   (`:115-133`). Labelled `Profile signal` over the track title; tapping it
   plays the track in the global player. See Section 11.
7. **Action row**:
   - Editable (own dashboard): links `Edit profile` → `/settings` and
     `View public page` → `/u/{profileId}` (`:135-141`).
   - Public + signed-in non-owner: the **listener-pin** control (`:143-155`):
     `pinState === 'available'` renders a `Pin to my rotation` button
     (form action `pin-listener`); `'pinned'` renders the static label
     `In your rotation`. Failed pins render the message inline (`:156`).
     OUT OF SCOPE for iOS v1 (grid is read-only).

---

## 6. Rotation grid

### 6.1 Connection kinds (verbatim, `src/lib/connections.ts:14-22`)

```ts
export const CONNECTION_KINDS = [
  'artist',
  'label',
  'venue',
  'podcast',
  'photographer',
  'listener',
  'other',
] as const;
```

Mirrors the `connections.kind` check constraint (Section 2.3). Cap:

```ts
/** Grid cap (MySpace had a Top 8; we allow a 4-wide grid of three rows). */
export const MAX_CONNECTIONS = 12;
```

(`connections.ts:44-45`.)

### 6.2 Query and ordering

`getConnections` selects
`id, kind, name, image_url, link_url, position, created_at` for the profile
owner ordered by `position` ascending (`profile.ts:117-125`). Positions are
plain integers; ties resolve in Postgres order — render exactly as returned.

### 6.3 Tile anatomy (`src/islands/RotationGrid.tsx:18-24, 173-189`)

Tile props passed to the island are only
`{ id, name, kind, image_url, link_url }` (`ProfilePage.astro:90`). Each tile
is a link wrapping:

1. Square image from `image_url`; when null, a fallback block showing
   `name[0]` (`RotationGrid.tsx:182-186`).
2. Name label (`:187`).
3. Kind chip — the raw `kind` string in a small pill (`:188`).

Link behavior (`RotationGrid.tsx:31-32, 176-181`):

```ts
/** Off-site tile links open in a new tab; in-app links (listener pins) stay put. */
const offsite = (url: string | null) => Boolean(url && !url.startsWith('/'));
```

- `link_url` starting with `/` → **in-app navigation**. In practice this is
  listener pins (`/u/<id>`).
- Any other non-null `link_url` → **off-site** (web opens a new tab with
  `rel="nofollow noopener ugc"`). iOS: open in Safari /
  `SFSafariViewController`.
- `link_url` may be null (free-form entries with no link) — tile is not
  tappable as a link.

Layout: 4-column square grid, 2 columns on narrow screens
(`ProfilePage.astro:1089-1094, 1205-1209`). With `MAX_CONNECTIONS = 12`
that is at most 3 rows of 4.

### 6.4 Listener pins are snapshots

When a viewer pins another listener from `/u/[id]`
(`src/pages/u/[id].astro:36-68`), the insert copies the target's CURRENT
identity into the viewer's `connections` row:

```ts
const { error } = await supabase.from('connections').insert({
  user_id: viewer.id,
  kind: 'listener',
  name,                       // target display_name || 'A listener'
  image_url: target.avatar_url,
  link_url: `/u/${id}`,
  position: Math.max(0, ...mine.map((c) => c.position)) + 1,
});
```

Per the comment at `u/[id].astro:36-41`: "a snapshot connection row — display
name, avatar, and the /u/<id> link are copied at pin time … so
renames/avatar changes don't propagate". **iOS must render listener tiles
from the connection row itself, never re-resolve from `profiles`.** A
listener tile may therefore show a stale name/avatar by design; the stable
part is the `/u/<id>` `link_url`, which is also the dedupe key
("already pinned" = `c.kind === 'listener' && c.link_url === `/u/${id}``,
`u/[id].astro:109`).

Pin preconditions enforced server-side (`u/[id].astro:42-57`): signed in; not
self; target public; viewer's grid `< MAX_CONNECTIONS`; not already present
by `link_url` or `name`.

### 6.5 Web grid-write affordances — ALL OUT OF SCOPE for iOS v1

iOS v1 renders the grid read-only with no reordering. The following web
affordances exist and are explicitly out of scope:

| Affordance | Web mechanics | Source |
|---|---|---|
| Catalog add ("Pin to the rotation") | POST `action=add-connection&slug=<slug>` against the 6-entry `CONNECTION_CATALOG`; inserts with `position = max+1`; dedupe by name, cap 12 | `dashboard.astro:46-60`, `connections.ts:35-42` |
| Free-form add ("Add your own") | POST `action=add-free-connection` with name (≤80), kind (any kind except `listener` — reserved for real pins), optional http(s) link (≤500), optional JPG/PNG/WebP image ≤10MB uploaded to R2 at key `user/{userId}/grid/{uuid}.{ext}`; insert error code `23505` = duplicate name | `dashboard.astro:61-129`, `ProfilePage.astro:305-345`, `ugc.ts:15,27-31` |
| Remove (unpin, "×") | POST `action=remove-connection&id=<uuid>`; delete scoped `eq('id', id).eq('user_id', user.id)` | `dashboard.astro:130-132`, `RotationGrid.tsx:242-248` |
| Reorder (drag handle ⠿ + ◂/▸ buttons) | POST `action=reorder-connections&order=<id,id,…>` with the full permutation; server validates it is exactly a permutation of the user's rows then writes `position = index` per row | `dashboard.astro:133-154`, `RotationGrid.tsx:59-87` |
| Listener pin (on `/u/[id]`) | POST `action=pin-listener` (Section 6.4) | `u/[id].astro:42-68, 79-82` |
| "Rotation full" hint | shown when `connections.length >= MAX_CONNECTIONS` | `ProfilePage.astro:349`, `dashboard.astro:249` |

If iOS later adds writes, note the server trusts RLS plus these same checks;
the reorder write is N individual `update connections set position = i`
calls (`dashboard.astro:146-150`).

---

## 7. Activity feed ("Latest activity")

Built client-of-database by `buildActivity` (`src/lib/profile.ts:170-219`).
All inputs are merged into one list, sorted by timestamp **descending via
string compare** (`events.sort((a, b) => b.at.localeCompare(a.at))`,
`profile.ts:217`), then sliced to `limit ?? 12` (`profile.ts:218`).

Row shape (`profile.ts:41-49`): `kind` (eyebrow tag), `text`, `href`
(nullable), `at` (ISO timestamp), optional `note` (own view only; the
content's status when not `'published'`, i.e. `private` or `removed` —
`profile.ts:183`).

### 7.1 Event kinds and construction (verbatim semantics, `profile.ts:185-215`)

| kind | source rows | text | href |
|---|---|---|---|
| `mixtape` | `content.mixes` (`user_uploads`) | `Uploaded “{title}”` | `/mixes/{id}` |
| `writing` | `content.posts` | `Posted “{title}”` | `/posts/{id}` |
| `list` | `content.lists` | `Made the list “{title}”` | `/lists/{id}` |
| `photos` | `content.albums` (`photo_albums`) | `Shared “{title}”` | `/photos/{id}` |
| `favorite` | `favorites` rows (own view only) | `Favorited “{title}”` | episode `/show/{slug}` or mix `/mixes/{ref}` |
| `listening` | `listen_status` rows with status `playing`/`played` (own view only) | `Listening to “{title}”` / `Finished “{title}”` | episode or mix link |
| `rotation` | `connections` rows | `Pinned {name} to the rotation` | the connection's `link_url` (may be null) |
| `wall` | wall entries received | `Got a wall note from {author_name}` | `#wall` (scroll to wall section) |

Timestamps: content rows use `created_at`; listens use `updated_at`;
connections use `created_at`; wall notes use `created_at`
(`profile.ts:186-215`).

`favorite`/`listening` refs resolve through `refTitle` (`profile.ts:194-200`):
episode slug → Sanity episode (`/show/{slug}`), else uuid → `user_uploads`
title via `resolveMixTitles` (`profile.ts:158-168` — only refs matching
`UUID_RE` are queried: `supabase.from('user_uploads').select('id, title').in('id', ids)`).
Unresolvable refs are dropped.

### 7.2 Inputs per route

- **Dashboard** (`dashboard.astro:161-200`): content with
  `publishedOnly=false`, plus `favorites`
  (`select('content_ref, created_at')`, `order('created_at', desc)`,
  `limit(15)`), plus `listen_status`
  (`select('content_ref, status, progress_seconds, updated_at')`,
  `order('updated_at', desc)`, `limit(15)`), plus connections, plus wall
  notes. Non-published content rows carry the `note` chip (`private` /
  `removed`).
- **Public `/u/[id]`** (`u/[id].astro:104`): content with
  `publishedOnly=true`, connections, wall notes. No favorites/listens — RLS
  would return zero rows for a non-owner anyway (Section 2.6), and the page
  doesn't even query them.

Date stamps render via `ugcDate` — `'en'` locale, day-numeric, month-long,
year-numeric, e.g. "11 June 2026" (`src/lib/ugc.ts:148-154`,
`ProfilePage.astro:237`).

---

## 8. Site news ("Meanwhile on Quiet Cast")

`getSiteNews(supabase, episodes)` (`src/lib/profile.ts:225-256`). Site-wide
(not per-profile); shown on both routes when non-empty. Composition:

1. **3 latest broadcasts**: `episodes.slice(0, 3)` (episodes already ordered
   `cat desc`), each `kind: 'broadcast'`,
   `title: `${e.catLabel} — ${e.title}``, `href: /show/{slug}`,
   `at: airDate ?? ''` (`profile.ts:226-231`).
2. **5 latest community pieces**: per each of `user_uploads` (kind `mix`,
   path `/mixes`), `posts` (`writing`, `/posts`), `lists` (`list`, `/lists`),
   `photo_albums` (`photos`, `/photos`):
   `select('id, title, created_at').eq('status', 'published').order('created_at', desc).limit(4)`,
   then all 16 candidates flattened, sorted desc by `created_at` (string
   compare), `slice(0, 5)` (`profile.ts:233-253`).

Result list = broadcasts first, then community (`profile.ts:255`). Max 8 rows.

---

## 9. Wall

### 9.1 Read

`getWallComments` (`wall.ts:34-48`): `wall_comments` columns
`id, author_id, body, created_at`, filters `profile_id = <page owner>` and
`status = 'published'`, newest first, `limit 30`. RLS additionally hides the
whole wall of a private profile from non-owners (Section 2.4).

Bylines via `resolveWallEntries` (`wall.ts:51-65`): batch `profiles`
display-names (`ugc.ts:99-111`; fallback byline `'a listener'`) and batch
`profile_details` `is_public` (`ugc.ts:119-136`) — the author name links to
`/u/<author_id>` only when the author's own profile is public, else plain
text (`wall.ts:62-63`).

Body rendering: plain text, `white-space: pre-line`, max 1000 chars
(`ProfilePage.astro:413, 1037-1044`; DB check `0004_wall.sql:14`).

### 9.2 Post

Compose box appears when `wallOpen && viewer signed in`
(`ProfilePage.astro:361-380`). `wallOpen` = the page owner's
`details.is_public ?? false` on both routes (`dashboard.astro:254`,
`u/[id].astro:152`) — **private profiles take no notes, including from the
owner**; the editable view shows the hint "Your wall opens for notes once
your profile is public" (`ProfilePage.astro:381-387`). Signed-out viewers on
an open wall see a sign-in prompt (`:375-379`).

Insert (`wall.ts:83-101`): body trimmed and capped at 1000 chars
(`String(form.get('body') ?? '').trim().slice(0, 1000)`), then

```ts
const { error } = await supabase.from('wall_comments').insert({
  profile_id: profileId,
  author_id: user.id,
  body,
});
```

Error mapping: Postgres code `'42501'` (RLS refusal — private wall or a
block between the parties) → user message `"This wall isn't open to you."`
(`wall.ts:91-100`). Comments are live immediately; no moderation queue.

### 9.3 Delete

Per-note "×" shown when
`viewerId === profileId || viewerId === note.author_id`
(`ProfilePage.astro:86, 403-411`):
owner moderates the whole wall, authors take back their own notes. The
delete is simply `supabase.from('wall_comments').delete().eq('id', id)` —
RLS scopes it; anyone else matches zero rows (`wall.ts:107-113`).

### 9.4 Report

Shown to signed-in viewers on notes they can NOT remove
(`viewerId && !canRemove(note)`, `ProfilePage.astro:414-430`): an expandable
form with a required free-text reason. Insert (`wall.ts:115-124`):

```ts
const { error } = await supabase.from('reports').insert({
  reporter_id: user.id,
  content_type: 'wall_comment',
  content_ref: id,
  reason,
});
```

Reason trimmed + capped at 1000 chars. Success copy:
`'Reported — the curator will take a look.'` Reported notes are taken down
out-of-band by the curator's service-role client setting
`status = 'removed'` (`wall.ts:10-13`); they disappear from reads because of
the `status = 'published'` filter/policy.

### 9.5 Who sees what — summary

| Viewer | Sees wall? | Can post? | Can delete? | Can report? |
|---|---|---|---|---|
| Anonymous, public profile | yes (published notes) | no (sign-in prompt) | no | no |
| Anonymous, private profile | profile 404s | — | — | — |
| Signed-in non-owner, public profile | yes | yes (unless blocked either way) | own notes only | notes that aren't theirs |
| Owner | yes (even when private — own wall via RLS) | only when own profile is public | any note on their wall | n/a (can delete instead) |

---

## 10. Episodes from Sanity (needed for activity titles, news, profile song)

GROQ, verbatim (`src/lib/content.ts:46-61, 89-93`):

```ts
const QA_PROJECTION = `"qa": [
  ${Array.from({ length: 20 }, (_, i) => `{"q": question${i + 1}, "a": answer${i + 1}}`).join(',\n  ')}
]`;

const EPISODE_PROJECTION = `{
  cat,
  name,
  "slug": slug.current,
  artist,
  description,
  "coverUrl": cover.asset->url,
  "audioUrl": audio.asset->url,
  "airDate": coalesce(date, _createdAt),
  tracklist,
  ${QA_PROJECTION}
}`;

const FILTER = `_type == "interview" && defined(slug.current) && defined(audio.asset)`;

// getEpisodes:
sanity.fetch(`*[${FILTER}] | order(cat desc) ${EPISODE_PROJECTION}`)
```

Mapping notes (`content.ts:63-81`): `catLabel` = `QC—{cat zero-padded to 3}`;
`title` = `name` with leading `Quiet Cast NNN:`-style prefix stripped via
`/^\s*quiet\s*cast\s*\d+\s*[:\-–]\s*/i`; `artist` defaults `'Various'`;
`airDate` = first 10 chars (YYYY-MM-DD). The profile pages key episodes by
**slug**: `new Map(episodes.map((e) => [e.slug, e]))`
(`dashboard.astro:159`, `u/[id].astro:92`).

Cover sizing uses Sanity image-CDN params:
`` `${url}?w=${w}&h=${h}&fit=crop&auto=format` `` (`content.ts:84-87`).

---

## 11. Profile song

Field: `profile_details.profile_song_ref` — "an episode slug or a published
user_uploads id" (`0003_profile.sql:18-19`). Resolution
(`src/lib/profile.ts:259-278`):

```ts
export async function resolveTrack(
  supabase: SupabaseClient,
  ref: string,
  episodesByRef: Map<string, Episode>,
): Promise<Track | null> {
  const ep = episodesByRef.get(ref);
  if (ep) return trackOf(ep);
  if (!UUID_RE.test(ref)) return null;
  const mix = await safeRow<{ id: string; title: string; r2_key: string; cover_r2_key: string | null }>(
    supabase.from('user_uploads').select('id, title, r2_key, cover_r2_key').eq('id', ref).maybeSingle(),
  );
  if (!mix) return null;
  return {
    id: mix.id,
    title: mix.title,
    artist: 'Listener mix',
    cover: mix.cover_r2_key ? cdnUrl(mix.cover_r2_key) : '/images/cryo_01.jpg',
    src: cdnUrl(mix.r2_key),
  };
}
```

- Episode branch: `trackOf` yields
  `{ id: slug, title, artist, cover: sizedCover(coverUrl, 160) ?? '', src: audioUrl ?? '', catalog: catLabel }`
  (`content.ts:105-114`). `src` is the Sanity-hosted audio URL.
- Mix branch: only attempted when the ref matches
  `/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i`
  (`profile.ts:151`); audio/cover are R2 CDN URLs; the cover fallback
  `'/images/cryo_01.jpg'` is a web-app static asset — iOS should bundle its
  own placeholder. RLS note: a published mix is world-readable, so visitors
  can resolve it; if the mix has since gone private/removed the query returns
  null and the song button is simply absent.

Track shape (`src/islands/PlayerDock.tsx:5-15`):

```ts
export interface Track {
  id: string;
  title: string;
  artist: string;
  cover: string;
  /** Absolute audio URL (cdn.quietcast.art/<audioKey>). */
  src: string;
  catalog?: string;
  durationLabel?: string;
}
```

Playback: the card button only renders when `song && song.src`
(`ProfilePage.astro:115`), and tapping hands the Track to the global player
dock (web: `data-qc-*` attributes, `ProfilePage.astro:117-124`). iOS: play
the `src` URL in the app's shared player. It is a stream-on-tap affordance —
no autoplay.

---

## 12. Own dashboard extras (vs. public)

Everything in Section 4 plus:

1. **Account box** (sidebar, `ProfilePage.astro:161-173`): `Settings` link,
   `Moderation` link when the user is the admin
   (`showAdminLink={isAdmin(user)}`, `dashboard.astro:257`), `Sign out`.
2. **Continue listening** (sidebar `side` slot, `dashboard.astro:259-277`):
   from the same `listen_status` fetch — rows with `status === 'playing'`,
   resolved to episode/mix titles, `mins = max(1, floor(progress_seconds / 60))`
   rendered as `{mins} min in`, first 4 only (`dashboard.astro:211-222`).
3. **Email** in the profile-card meta list (`dashboard.astro:242`).
4. **Bio empty-state** with an "add a bio" `/settings` link
   (`ProfilePage.astro:206-210`).
5. **Activity `note` chips**: non-published own content shows its status
   (`private` / `removed`) as a pill (`profile.ts:183`,
   `ProfilePage.astro:236`).
6. **"My pages" manage section** (`manage` slot, `dashboard.astro:279-306`):
   four panels, one per UGC type, defined at `dashboard.astro:227-232`:

   ```ts
   const manage = [
     { label: 'My mixtapes', rows: content.mixes, path: '/mixes', cta: 'Upload a mix', ctaHref: '/contribute/mix' },
     { label: 'My posts', rows: content.posts, path: '/posts', cta: 'Write a post', ctaHref: '/contribute/post' },
     { label: 'My lists', rows: content.lists, path: '/lists', cta: 'Make a list', ctaHref: '/contribute/list' },
     { label: 'My concert photos', rows: content.albums, path: '/photos', cta: 'Share concert photos', ctaHref: '/contribute/photos' },
   ];
   ```

   Each panel lists `m.rows.slice(0, 4)` (`dashboard.astro:293`) — note the
   underlying fetch was `limit(8)` per table with `publishedOnly=false`, so
   these are the owner's 4 newest items of any status. Each row: title
   linking to `{path}/{id}` plus a **status chip** showing the raw `status`
   string (`private` / `published` / `removed`,
   `dashboard.astro:294-297`). Empty state `'Nothing yet.'`; every panel ends
   with its CTA link.
7. **Grid editing + theming**: the dashboard passes
   `theme={details?.theme ?? null}` to the layout (`dashboard.astro:235`) —
   `theme` is `'dark' | 'light'` per the check constraint (Section 2.2).

### iOS v1 out-of-scope checklist (grid READ-ONLY, no reorder)

- Catalog add, free-form add (incl. R2 image upload), unpin, drag/button
  reorder, listener pin — Section 6.5 table.
- Web-only mechanics that need no iOS equivalent: PRG redirects after form
  POSTs (`dashboard.astro:32-35, 155`), the no-JS `<form>` fallbacks and the
  `reorder rejected` redirect-sniffing fetch (`RotationGrid.tsx:65-74`), the
  catalog type-to-filter combobox (`ProfilePage.astro:443-491`).

---

## 13. Implementation notes for iOS

- **Identity of queries**: every read above is a plain PostgREST query the
  iOS Supabase SDK can express 1:1 (`from(...).select(...).eq/in/order/limit`).
  No RPCs, no views, no service-role access on these pages.
- **Trust RLS, mirror the UI gates**: the web hides affordances client-side
  (e.g. `canRemove`, `wallOpen`, `pinState`) but the database enforces them;
  replicate the same gating to avoid dead-end errors, and surface `42501` as
  "not allowed" rather than a generic failure.
- **Sorting**: activity and news sort by ISO-8601 string comparison
  descending; identical to date sort given the formats stored.
- **Counts in headers**: activity, rotation, and wall section headers show
  the length of the fetched (limited) arrays — activity ≤ 12, wall ≤ 30,
  rotation ≤ 12 — not server-side totals.
- **Defensive empty states**: every section has a designed empty state
  (Sections 4-9); missing `profile_details` is normal for new users.
