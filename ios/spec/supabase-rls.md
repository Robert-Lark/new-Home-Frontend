# Quiet Cast — Supabase Schema + RLS Contract (iOS)

**Status: authoritative contract for the native iOS client.** This documents the FINAL database
state after all five migrations are applied, in order:

| # | File | Lines |
|---|------|-------|
| 1 | `supabase/migrations/0001_init.sql` | 307 |
| 2 | `supabase/migrations/0002_ugc.sql` | 226 |
| 3 | `supabase/migrations/0003_profile.sql` | 82 |
| 4 | `supabase/migrations/0004_wall.sql` | 76 |
| 5 | `supabase/migrations/0005_self_publish.sql` | 139 |

All five are confirmed run in production as of 2026-06-12 (a prod gap where 0002 had never run
was found and repaired the same day: 0002 → 0004 → 0005 re-run; 0003 was already live).
Production therefore equals "all five applied in order" — exactly what this file describes.

There are **17 tables**, **55 effective RLS policies**, **1 function**, **1 trigger**,
**8 named indexes**, **no Supabase Storage buckets**, and **no explicit GRANT statements**
(verified: `grep -rni 'storage\.'` and `grep -rni 'grant '` over `supabase/` return nothing).
Media bytes (audio, covers, photos, avatars, grid images) live in **Cloudflare R2**, not
Supabase Storage — only R2 *keys* are stored in Postgres, and RLS enforces their prefix
(see §Conventions).

---

## Conventions every Swift type must respect

### Roles and how policies bind

- No policy in any migration carries a `TO role` clause → every policy applies to `public`,
  i.e. both the `anon` and `authenticated` Postgres roles. For an anonymous client
  `auth.uid()` is NULL, so every `auth.uid() = …` comparison is non-true: **anon can never
  insert/update/delete anywhere**, and anon SELECT succeeds only through the
  published/public branches of the select policies.
- The **service role bypasses RLS** entirely (curator moderation runs through it server-side),
  but **CHECK constraints still bind the service role** — stated explicitly in
  `0005_self_publish.sql:24-25`:
  ```
  --     constraint-rejected (check constraints bind the service role too).
  ```
  The iOS app must never embed the service-role key; it uses only the anon key + user JWT.

### Silent-refusal semantics (critical for UI)

PostgREST/supabase-swift behavior the UI must be built around:

- An **INSERT** that violates a `WITH CHECK` fails loudly: HTTP 403, Postgres error `42501`
  ("new row violates row-level security policy").
- An **UPDATE** whose `USING` clause filters the target row out of the updatable set
  **matches zero rows and returns success with an empty result** — no error. Example:
  trying to update a `status = 'removed'` row. The client MUST check the returned row
  count (use `.select()` on the mutation) and reflect the refusal, not assume success.
- A **DELETE** filtered out by `USING` likewise silently affects zero rows.

### `content_ref` convention

`favorites.content_ref`, `listen_status.content_ref`, `playlist_items.content_ref`, and
`profile_details.profile_song_ref` hold **either a Sanity episode slug (text) or a
`user_uploads.id` (uuid)** in the same text column:

```sql
-- content_ref = Sanity doc id (public content) or a user_uploads id.
```
(`0001_init.sql:54`)

```sql
  -- content_ref of the profile song: an episode slug or a published
  -- user_uploads id (same convention as favorites.content_ref).
```
(`0003_profile.sql:18-19`)

Resolution rule (mirrors `src/lib/profile.ts:151-167`): test against
`^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$` (case-insensitive);
match → look up in `user_uploads` by uuid; no match → treat as episode slug. Never pass a
non-uuid ref into a uuid `.in()`/`.eq()` filter — Postgres rejects invalid uuid literals.

### R2 key prefix rule

A user's R2 objects live under `user/<uid>/…`. RLS *requires* this prefix on
`user_uploads.r2_key`, `user_uploads.cover_r2_key`, and `photos.r2_key` (verbatim policies
below). Keys are opaque strings to the iOS client; upload signing happens via the web app's
API routes, not Supabase.

### Status vocabularies (final, post-0005)

| Table | Allowed values | Default | Who can write what |
|---|---|---|---|
| `user_uploads` | `'private', 'published', 'removed'` | `'private'` | author: private/published only; `removed` is service-role-only |
| `posts` | `'private', 'published', 'removed'` | `'private'` | same (old `'draft'` was folded into `'private'` by 0005) |
| `lists` | `'private', 'published', 'removed'` | `'private'` | same |
| `photo_albums` | `'private', 'published', 'removed'` | `'private'` | same |
| `wall_comments` | `'published', 'removed'` | `'published'` | author inserts `published` only; `removed` is service-role-only |
| `listen_status` | `'unplayed', 'playing', 'played'` | `'unplayed'` | owner, freely |
| `reports` | `'open', 'reviewed', 'dismissed'` | `'open'` | reporter inserts only; status changes are service-role-only |

The 0005 backfill set every non-published UGC row (`pending`, `rejected`, posts' `draft`)
to `'private'` (`0005_self_publish.sql:42,73,92,111`).

**`removed` semantics (UGC tables — uploads/posts/lists/albums):** rows stay
**author-visible** (select policies unchanged: own-or-published), but the author is
**locked out of updating** them — update `USING … and status <> 'removed'` removes the row
from the updatable set, and `WITH CHECK … status in ('private','published')` blocks ever
writing `removed` or un-removing. Deleting a removed row **is** allowed (deletion ≠
un-removal). Verbatim rationale, `0005_self_publish.sql:12-19`:

```
-- is the curator's service-role client setting status = 'removed' (stamp
-- reviewed_at while at it). Users can never write 'removed', and a removed
-- row drops out of their updatable set entirely — so a takedown can't be
-- undone or edited around. Unlike wall comments, removed rows STAY VISIBLE
-- to their author (the select policies don't change): their own work
-- shouldn't silently vanish from their dashboard, they just can't touch it.
-- Deleting a removed row remains allowed (same as wall comments) — that
-- removes the content outright, which is not an un-remove.
```

**`removed` semantics (wall_comments):** the select policy requires
`status = 'published'`, so removed wall comments vanish for **everyone, author included**
— a deliberate divergence from the UGC tables.

`reviewed_at` on the four UGC tables is now the **takedown timestamp**
(`0005_self_publish.sql:136`).

### App-level (NOT database) limits the iOS client should mirror

- Rotation grid cap: `MAX_CONNECTIONS = 12` (`src/lib/connections.ts:45`). DB does not enforce it.
- Creation brake: refuse new UGC pieces when 20 were created in the trailing 24h —
  app-level, no schema (`0005_self_publish.sql:34-36`). When counting own rows, always
  filter `.eq('user_id', me)` — the own-or-published select policy means an unfiltered
  count sees *everyone's published rows*.

---

## Function + trigger

`public.handle_new_user()` — `0001_init.sql:32-50`, verbatim:

```sql
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = ''
as $$
begin
  insert into public.profiles (id, display_name)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'display_name', split_part(new.email, '@', 1))
  );
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();
```

**iOS consequence:** after sign-up, a `profiles` row already exists (display_name seeded
from `raw_user_meta_data.display_name` or the email local-part). Never INSERT into
`profiles` on first launch — UPDATE it. `profile_details` is the opposite: **no trigger
creates it**; it is "created lazily by app-level upsert" (`0003_profile.sql:11`), so the
iOS client must UPSERT `profile_details` when the user first edits profile settings.

---

## Tables

Each section: final columns → indexes → verbatim policies → plain-English access matrix
(anonymous / authenticated non-owner / owner).

### 1. `public.profiles` (1:1 with `auth.users`)

Definition `0001_init.sql:10-15`:

```sql
create table if not exists public.profiles (
  id           uuid primary key references auth.users (id) on delete cascade,
  display_name text,
  avatar_url   text,
  created_at   timestamptz not null default now()
);
```

Policies `0001_init.sql:19-28`:

```sql
create policy "profiles_select_all" on public.profiles
  for select using (true);

create policy "profiles_insert_own" on public.profiles
  for insert with check (auth.uid() = id);

create policy "profiles_update_own" on public.profiles
  for update using (auth.uid() = id) with check (auth.uid() = id);
```

- **Anonymous:** read every profile (world-readable by design — bylines on published content). No writes.
- **Authed non-owner:** read every profile. No writes to others' rows.
- **Owner:** read all; update own row; insert own row (normally moot — the trigger already
  made it). **No delete policy** — rows die only via `auth.users` cascade.

### 2. `public.profile_details` (1:1 with `auth.users`, lazy-created)

Definition `0003_profile.sql:13-24`:

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
```

Policies `0003_profile.sql:28-37`:

```sql
create policy "details_select_public_or_own" on public.profile_details
  for select using (is_public or auth.uid() = id);

create policy "details_insert_own" on public.profile_details
  for insert with check (auth.uid() = id);

create policy "details_update_own" on public.profile_details
  for update using (auth.uid() = id) with check (auth.uid() = id);
```

- **Anonymous:** read rows where `is_public = true` only. A missing or private row reads
  as "no row" — the iOS client must treat both the same (profile is private).
- **Authed non-owner:** same as anonymous.
- **Owner:** read/insert/update own row. No delete policy.

`is_public` is the single privacy gate: it cascades into `connections` and `wall_comments`
visibility via subqueries (below). `theme` (`'dark'`/`'light'`, default `'dark'`) is the
server-persisted theme preference — light mode shipped; the iOS app should honor it.
`profile_song_ref` follows the `content_ref` convention (§Conventions).

### 3. `public.connections` (the "rotation" grid; MySpace top-friends analog)

Definition `0003_profile.sql:44-55`:

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
```

Index `0003_profile.sql:82`:

```sql
create index if not exists connections_user_idx on public.connections (user_id, position);
```

Policies `0003_profile.sql:61-80`:

```sql
create policy "connections_select" on public.connections
  for select using (
    auth.uid() = user_id
    or exists (
      select 1 from public.profile_details d
      where d.id = user_id and d.is_public
    )
  );

create policy "connections_insert_own" on public.connections
  for insert with check (auth.uid() = user_id);

create policy "connections_update_own" on public.connections
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "connections_delete_own" on public.connections
  for delete using (auth.uid() = user_id);
```

- **Anonymous / authed non-owner:** read a user's grid only if that user's
  `profile_details.is_public` is true.
- **Owner:** full CRUD on own rows.

**Listener-pin snapshot contract.** There are NO `display_name`/`avatar_url` columns on
this table — pinning another listener writes a **snapshot at pin time** into the existing
columns (renames/avatar changes deliberately do not propagate). Exact mapping, from the
web implementation `src/pages/u/[id].astro:58-65`:

```ts
const { error } = await supabase.from('connections').insert({
  user_id: viewer.id,
  kind: 'listener',
  name,                              // = target profiles.display_name || 'A listener'
  image_url: target.avatar_url,      // snapshot of the pinned user's avatar
  link_url: `/u/${id}`,              // in-app profile link
  position: Math.max(0, ...mine.map((c) => c.position)) + 1,
});
```

iOS must replicate the same shape: `kind='listener'`, `name` ← target's
`profiles.display_name` (fallback `'A listener'`), `image_url` ← target's
`profiles.avatar_url`, `link_url` ← `/u/<target-id>` (this is how a tile is recognized as
an in-app listener pin), next free `position`. App-level guards before insert (DB does not
enforce them, except `unique (user_id, name)`): target must exist and be public, no
self-pin, grid < 12 tiles, no duplicate `link_url` or `name` (`src/pages/u/[id].astro:43-57`).
`kind='listener'` is **reserved for real pins** — free-form entries use every kind except
`listener` (`src/components/ProfilePage.astro:87-88`). Free-form tile images live under
R2 `user/<uid>/grid/<uuid>.<ext>`; `link_url` values starting with `/` are in-app, others
are off-site (web renders off-site with `rel="nofollow noopener ugc"`, new tab).
Reordering = rewrite `position` to array index for all rows.

### 4. `public.favorites`

Definition `0001_init.sql:56-62`:

```sql
create table if not exists public.favorites (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users (id) on delete cascade,
  content_ref text not null,
  created_at  timestamptz not null default now(),
  unique (user_id, content_ref)
);
```

Policy `0001_init.sql:66-67`:

```sql
create policy "favorites_rw_own" on public.favorites
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
```

- **Anonymous / authed non-owner:** nothing. Favorites are fully private.
- **Owner:** full CRUD (`for all`). One row per `(user_id, content_ref)`; favoriting is
  insert, unfavoriting is delete. `content_ref` per §Conventions (episode slug or
  user_uploads uuid).

### 5. `public.listen_status`

Definition `0001_init.sql:72-81`:

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

Policy `0001_init.sql:85-86`:

```sql
create policy "listen_status_rw_own" on public.listen_status
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
```

- **Anonymous / authed non-owner:** nothing. Listen state is fully private.
- **Owner:** full CRUD. Upsert on `(user_id, content_ref)`; track playback with
  `status` ∈ `unplayed|playing|played` and `progress_seconds` (integer seconds).
  **`updated_at` has no trigger** — the client must set it explicitly on writes
  (default only covers insert).

### 6. `public.user_uploads` (community mixes — metadata only; audio in R2)

Final columns: definition `0001_init.sql:91-105` with the status check/default replaced by
`0005_self_publish.sql:41-46`:

```sql
create table if not exists public.user_uploads (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references auth.users (id) on delete cascade,
  title        text not null,
  description  text,
  cover_r2_key text,
  tracklist    jsonb not null default '[]'::jsonb,
  r2_key       text not null,
  duration     integer,
  mime         text,
  status       text not null default 'pending'      -- superseded by 0005, see below
                 check (status in ('pending', 'published', 'rejected')),
  reviewed_at  timestamptz,
  created_at   timestamptz not null default now()
);
```

```sql
alter table public.user_uploads
  add constraint user_uploads_status_check
  check (status in ('private', 'published', 'removed'));
alter table public.user_uploads alter column status set default 'private';
```

Index `0002_ugc.sql:221`:

```sql
create index if not exists user_uploads_status_created_idx on public.user_uploads (status, created_at desc);
```

Final policies — select+delete from 0001, insert+update from 0005.
`0001_init.sql:109-110,121-122`:

```sql
create policy "uploads_select_own_or_published" on public.user_uploads
  for select using (auth.uid() = user_id or status = 'published');

create policy "uploads_delete_own" on public.user_uploads
  for delete using (auth.uid() = user_id);
```

`0005_self_publish.sql:49-65`:

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

- **Anonymous / authed non-owner:** read `status = 'published'` rows only. No writes.
- **Owner:** read all own rows (including `private` and `removed`); insert with
  `status` ∈ {private, published} and R2 keys under own `user/<uid>/` prefix; update only
  rows that are not `removed`, and only into {private, published}; delete any own row,
  `removed` included.
- `tracklist` is a JSONB array (default `[]`); `duration` integer seconds; `mime` free text.

### 7. `public.posts` (user blog / reviews)

Final columns: `0001_init.sql:127-137` + `reviewed_at` from `0002_ugc.sql:19` + status
check/default from `0005_self_publish.sql:74-77`:

```sql
create table if not exists public.posts (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references auth.users (id) on delete cascade,
  slug       text not null,
  title      text not null,
  body_md    text,
  status     text not null default 'draft'           -- superseded by 0005
               check (status in ('draft', 'published')),
  created_at timestamptz not null default now(),
  unique (user_id, slug)
);
```

```sql
alter table public.posts add column if not exists reviewed_at timestamptz;
```

```sql
alter table public.posts
  add constraint posts_status_check
  check (status in ('private', 'published', 'removed'));
alter table public.posts alter column status set default 'private';
```

The old `'draft'` value no longer exists: `0005_self_publish.sql:73` folded it in —

```sql
update public.posts set status = 'private' where status in ('draft', 'pending', 'rejected');
```

Index `0002_ugc.sql:222`:

```sql
create index if not exists posts_status_created_idx        on public.posts (status, created_at desc);
```

Final policies — select+delete from 0001 (`0001_init.sql:141-142,153-154`), insert+update
from 0005 (`0005_self_publish.sql:80-86`):

```sql
create policy "posts_select_own_or_published" on public.posts
  for select using (auth.uid() = user_id or status = 'published');

create policy "posts_delete_own" on public.posts
  for delete using (auth.uid() = user_id);

create policy "posts_insert_own" on public.posts
  for insert with check (auth.uid() = user_id and status in ('private', 'published'));

create policy "posts_update_own" on public.posts
  for update using (auth.uid() = user_id and status <> 'removed')
  with check (auth.uid() = user_id and status in ('private', 'published'));
```

- **Anonymous / authed non-owner:** published rows only.
- **Owner:** read all own; insert/update within {private, published}; removed rows
  read-and-delete only. `slug` must be unique per user (`unique (user_id, slug)`).
  `body_md` is Markdown. Editing a published post no longer demotes it
  (`0005_self_publish.sql:69-70` — the 0002 review-pullback era ended).

### 8. `public.lists` (curated free-text lists) + `public.list_items`

`lists` final: `0002_ugc.sql:62-71` + status check/default from `0005_self_publish.sql:93-96`:

```sql
create table if not exists public.lists (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users (id) on delete cascade,
  title       text not null,
  description text,
  status      text not null default 'pending'        -- superseded by 0005
                check (status in ('pending', 'published', 'rejected')),
  reviewed_at timestamptz,
  created_at  timestamptz not null default now()
);
```

```sql
alter table public.lists
  add constraint lists_status_check
  check (status in ('private', 'published', 'removed'));
alter table public.lists alter column status set default 'private';
```

Indexes `0002_ugc.sql:223,225`:

```sql
create index if not exists lists_status_created_idx        on public.lists (status, created_at desc);
create index if not exists list_items_list_idx             on public.list_items (list_id, position);
```

`lists` final policies — select+delete from 0002 (`0002_ugc.sql:75-76,88-89`), insert+update
from 0005 (`0005_self_publish.sql:99-105`):

```sql
create policy "lists_select_own_or_published" on public.lists
  for select using (auth.uid() = user_id or status = 'published');

create policy "lists_delete_own" on public.lists
  for delete using (auth.uid() = user_id);

create policy "lists_insert_own" on public.lists
  for insert with check (auth.uid() = user_id and status in ('private', 'published'));

create policy "lists_update_own" on public.lists
  for update using (auth.uid() = user_id and status <> 'removed')
  with check (auth.uid() = user_id and status in ('private', 'published'));
```

`list_items` — `0002_ugc.sql:91-100`. Items are free text, **not** playable content_refs
(that distinction from playlists is by design, `0002_ugc.sql:59-60`):

```sql
create table if not exists public.list_items (
  id        uuid primary key default gen_random_uuid(),
  list_id   uuid not null references public.lists (id) on delete cascade,
  item_type text not null default 'other'
              check (item_type in ('record', 'artist', 'label', 'show', 'other')),
  title     text not null,
  note      text,
  url       text,
  position  integer not null default 0
);
```

`list_items` policies (derived access, `0002_ugc.sql:105-131`):

```sql
create policy "list_items_select" on public.list_items
  for select using (
    exists (
      select 1 from public.lists l
      where l.id = list_id and (l.user_id = auth.uid() or l.status = 'published')
    )
  );

create policy "list_items_insert" on public.list_items
  for insert with check (
    exists (select 1 from public.lists l where l.id = list_id and l.user_id = auth.uid())
  );

create policy "list_items_update" on public.list_items
  for update using (
    exists (select 1 from public.lists l where l.id = list_id and l.user_id = auth.uid())
  ) with check (
    exists (select 1 from public.lists l where l.id = list_id and l.user_id = auth.uid())
  );

create policy "list_items_delete" on public.list_items
  for delete using (
    exists (select 1 from public.lists l where l.id = list_id and l.user_id = auth.uid())
  );
```

- **Anonymous / authed non-owner:** items of published lists only.
- **Owner:** full CRUD on items of own lists — including items of a `removed` list
  (deliberate; harmless because no public surface shows them, `0005_self_publish.sql:132-135`).

### 9. `public.photo_albums` + `public.photos`

`photo_albums` final: `0002_ugc.sql:138-148` + status check/default from
`0005_self_publish.sql:112-115`:

```sql
create table if not exists public.photo_albums (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users (id) on delete cascade,
  title       text not null,
  venue       text,
  event_date  date,
  description text,
  status      text not null default 'pending'        -- superseded by 0005
                check (status in ('pending', 'published', 'rejected')),
  reviewed_at timestamptz,
  created_at  timestamptz not null default now()
);
```

```sql
alter table public.photo_albums
  add constraint photo_albums_status_check
  check (status in ('private', 'published', 'removed'));
alter table public.photo_albums alter column status set default 'private';
```

Indexes `0002_ugc.sql:224,226`:

```sql
create index if not exists photo_albums_status_created_idx on public.photo_albums (status, created_at desc);
create index if not exists photos_album_idx                on public.photos (album_id, position);
```

`photo_albums` final policies — select+delete from 0002 (`0002_ugc.sql:153-154,166-167`),
insert+update from 0005 (`0005_self_publish.sql:118-124`):

```sql
create policy "albums_select_own_or_published" on public.photo_albums
  for select using (auth.uid() = user_id or status = 'published');

create policy "albums_delete_own" on public.photo_albums
  for delete using (auth.uid() = user_id);

create policy "albums_insert_own" on public.photo_albums
  for insert with check (auth.uid() = user_id and status in ('private', 'published'));

create policy "albums_update_own" on public.photo_albums
  for update using (auth.uid() = user_id and status <> 'removed')
  with check (auth.uid() = user_id and status in ('private', 'published'));
```

`photos` — `0002_ugc.sql:169-175`. No status of their own; visibility follows the album
(`0002_ugc.sql:136`):

```sql
create table if not exists public.photos (
  id       uuid primary key default gen_random_uuid(),
  album_id uuid not null references public.photo_albums (id) on delete cascade,
  r2_key   text not null,
  caption  text,
  position integer not null default 0
);
```

`photos` policies (`0002_ugc.sql:179-208`) — note the R2 prefix on insert AND update:

```sql
create policy "photos_select" on public.photos
  for select using (
    exists (
      select 1 from public.photo_albums a
      where a.id = album_id and (a.user_id = auth.uid() or a.status = 'published')
    )
  );

create policy "photos_insert" on public.photos
  for insert with check (
    exists (select 1 from public.photo_albums a where a.id = album_id and a.user_id = auth.uid())
    and r2_key like 'user/' || auth.uid()::text || '/%'
  );

create policy "photos_update" on public.photos
  for update using (
    exists (select 1 from public.photo_albums a where a.id = album_id and a.user_id = auth.uid())
  ) with check (
    exists (select 1 from public.photo_albums a where a.id = album_id and a.user_id = auth.uid())
    and r2_key like 'user/' || auth.uid()::text || '/%'
  );

create policy "photos_delete" on public.photos
  for delete using (
    exists (select 1 from public.photo_albums a where a.id = album_id and a.user_id = auth.uid())
  );
```

- **Anonymous / authed non-owner:** photos of published albums only.
- **Owner:** full CRUD on photos of own albums; `r2_key` must be under own prefix.
- Web upload pattern worth copying: insert the album `private`, add photos, flip to
  `published` after the last photo lands — no half-albums on the public shelf.

### 10. `public.playlists` + `public.playlist_items`

These predate the UGC moderation story and were never touched after 0001: visibility is a
plain `is_public` boolean, no status vocabulary, no review, no `removed`.

`playlists` — `0001_init.sql:159-166`:

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

Policies `0001_init.sql:170-183`:

```sql
create policy "playlists_select_own_or_public" on public.playlists
  for select using (auth.uid() = user_id or is_public);

create policy "playlists_insert_own" on public.playlists
  for insert with check (auth.uid() = user_id);

create policy "playlists_update_own" on public.playlists
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "playlists_delete_own" on public.playlists
  for delete using (auth.uid() = user_id);
```

`playlist_items` — `0001_init.sql:185-191`. Items ARE playable `content_ref`s
(§Conventions), unlike `list_items`:

```sql
create table if not exists public.playlist_items (
  id          uuid primary key default gen_random_uuid(),
  playlist_id uuid not null references public.playlists (id) on delete cascade,
  content_ref text not null,
  position    integer not null default 0,
  added_at    timestamptz not null default now()
);
```

Policies `0001_init.sql:197-223`:

```sql
create policy "playlist_items_select" on public.playlist_items
  for select using (
    exists (
      select 1 from public.playlists p
      where p.id = playlist_id and (p.user_id = auth.uid() or p.is_public)
    )
  );

create policy "playlist_items_insert" on public.playlist_items
  for insert with check (
    exists (select 1 from public.playlists p where p.id = playlist_id and p.user_id = auth.uid())
  );

create policy "playlist_items_update" on public.playlist_items
  for update using (
    exists (select 1 from public.playlists p where p.id = playlist_id and p.user_id = auth.uid())
  ) with check (
    exists (select 1 from public.playlists p where p.id = playlist_id and p.user_id = auth.uid())
  );

create policy "playlist_items_delete" on public.playlist_items
  for delete using (
    exists (select 1 from public.playlists p where p.id = playlist_id and p.user_id = auth.uid())
  );
```

- **Anonymous / authed non-owner:** public playlists and their items, read-only.
- **Owner:** full CRUD on own playlists and their items; flips `is_public` freely
  (no moderation gate on playlists).

### 11. `public.wall_comments` (profile comment wall — live-immediately)

Definition `0004_wall.sql:9-18`:

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
```

Index `0004_wall.sql:67-68`:

```sql
create index if not exists wall_comments_profile_idx
  on public.wall_comments (profile_id, created_at desc);
```

Policies `0004_wall.sql:26-63` — note there is deliberately **no user UPDATE policy**
(`0004_wall.sql:65`: `-- No user update policy: takedowns happen through the service-role client.`):

```sql
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

create policy "wall_delete_owner_or_author" on public.wall_comments
  for delete using (auth.uid() in (profile_id, author_id));
```

- **Anonymous:** published comments on public walls only (the `auth.uid() in (…)` branch
  is null-false; the `is_public` subquery branch carries anon reads).
- **Authed non-owner (= any author or visitor):** read published comments on public walls,
  plus their own published comments anywhere; **insert** only as themselves
  (`author_id = auth.uid()`), only `status='published'` (comments go live immediately —
  no review queue), only onto walls whose `profile_details.is_public` is true, and only if
  **neither party blocks the other** (both directions checked); **delete** their own
  comments on anyone's wall.
- **Wall owner:** additionally reads published comments on their own wall even if their
  profile is private, and **deletes any comment on their wall** (owner-delete).
- **Nobody (user-side) can update** — takedown (`status='removed'`) is service-role only,
  and a removed wall comment disappears from every user-side read, author included
  (contrast with UGC tables, §Conventions).
- `body` must be 1–1000 characters (DB CHECK) — validate client-side too.

### 12. `public.messages` (lightweight DMs)

Definition `0001_init.sql:251-258`:

```sql
create table if not exists public.messages (
  id           uuid primary key default gen_random_uuid(),
  sender_id    uuid not null references auth.users (id) on delete cascade,
  recipient_id uuid not null references auth.users (id) on delete cascade,
  body         text not null,
  created_at   timestamptz not null default now(),
  read_at      timestamptz
);
```

Policies `0001_init.sql:262-283`:

```sql
create policy "messages_select_participant" on public.messages
  for select using (auth.uid() in (sender_id, recipient_id));

create policy "messages_insert_sender" on public.messages
  for insert with check (
    auth.uid() = sender_id
    and not exists (
      select 1 from public.blocks b
      where b.blocker_id = recipient_id and b.blocked_id = sender_id
    )
    and not exists (
      select 1 from public.blocks b
      where b.blocker_id = sender_id and b.blocked_id = recipient_id
    )
  );

create policy "messages_update_recipient" on public.messages
  for update using (auth.uid() = recipient_id) with check (auth.uid() = recipient_id);
```

- **Anonymous:** nothing.
- **Participants (sender or recipient):** read the message.
- **Sender:** insert only as self, blocked in *both* directions by `blocks` rows.
  **A sender cannot mark their own sent message read, edit it, or delete it.**
- **Recipient:** update (in practice: set `read_at`).
- **No delete policy at all** — DMs are permanent user-side. Threads are derived
  client-side by the (sender, recipient) pair (`0001_init.sql:249`).

### 13. `public.blocks`

Definition `0001_init.sql:228-233`:

```sql
create table if not exists public.blocks (
  blocker_id uuid not null references auth.users (id) on delete cascade,
  blocked_id uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id)
);
```

Policies `0001_init.sql:237-246`:

```sql
create policy "blocks_select_own" on public.blocks
  for select using (auth.uid() = blocker_id);

create policy "blocks_insert_own" on public.blocks
  for insert with check (auth.uid() = blocker_id);

create policy "blocks_delete_own" on public.blocks
  for delete using (auth.uid() = blocker_id);
```

- **Anonymous / authed non-owner:** nothing — **the blocked party cannot discover they are
  blocked** by reading this table. They only observe `42501` on message/wall-comment
  inserts. The iOS app must show a generic failure, not "you are blocked".
- **Blocker:** sees, creates, deletes own block rows. No update policy (nothing to update).
- Composite PK `(blocker_id, blocked_id)` — no surrogate id column. Blocking gates
  `messages` inserts and `wall_comments` inserts in both directions (see those tables).

### 14. `public.reports` (user flags → curator moderation queue)

Definition `0001_init.sql:290-298`, with the final `content_type` check from
`0004_wall.sql:74-76`:

```sql
create table if not exists public.reports (
  id           uuid primary key default gen_random_uuid(),
  reporter_id  uuid not null references auth.users (id) on delete cascade,
  content_type text not null check (content_type in ('upload', 'message', 'post', 'playlist')),  -- superseded
  content_ref  text not null,
  reason       text,
  status       text not null default 'open' check (status in ('open', 'reviewed', 'dismissed')),
  created_at   timestamptz not null default now()
);
```

```sql
alter table public.reports
  add constraint reports_content_type_check
  check (content_type in ('upload', 'message', 'post', 'playlist', 'list', 'photo_album', 'wall_comment'));
```

Policies `0001_init.sql:302-307`:

```sql
create policy "reports_insert_own" on public.reports
  for insert with check (auth.uid() = reporter_id);

create policy "reports_select_own" on public.reports
  for select using (auth.uid() = reporter_id);
```

- **Anonymous:** nothing.
- **Authed user:** insert reports as themselves (`content_type` from the 7-value list,
  `content_ref` = the offending row's id as text, optional `reason`); read **only their
  own** reports. **No update, no delete** — a report cannot be withdrawn or edited.
  Status changes (`reviewed`/`dismissed`) and the resulting takedowns happen via the
  curator's service-role client (`0001_init.sql:287-288`).

---

## Storage buckets, grants, other server objects

- **Supabase Storage: not used.** Zero `storage.*` statements across all migrations
  (tool-verified grep). All binary media is Cloudflare R2, keyed by the `r2_key`/
  `cover_r2_key`/`image_url` columns; the only DB-side enforcement is the
  `'user/' || auth.uid()::text || '/%'` LIKE prefix in the policies quoted above. The iOS
  app obtains upload URLs from the web app's API (R2 signing), never from Supabase.
- **Grants: none beyond Supabase defaults.** Zero `grant` statements (tool-verified grep);
  the standard Supabase grants to `anon`/`authenticated` apply and RLS does all row gating.
- **Functions/triggers: exactly one of each** — `public.handle_new_user()` +
  `on_auth_user_created` (§Function + trigger). No `updated_at` maintenance triggers exist
  anywhere; clients own those columns.
- **Indexes (8 named, beyond PKs/uniques):** `user_uploads_status_created_idx`,
  `posts_status_created_idx`, `lists_status_created_idx`, `photo_albums_status_created_idx`
  (`(status, created_at desc)` each), `list_items_list_idx (list_id, position)`,
  `photos_album_idx (album_id, position)`, `connections_user_idx (user_id, position)`,
  `wall_comments_profile_idx (profile_id, created_at desc)`. Read paths should match them:
  filter by status + order by `created_at desc`, or by parent id + `position`.

---

## What the iOS client may rely on / must not attempt

**May rely on:**

1. RLS is the entire authorization layer — the client may issue any query with the anon
   key + user JWT and trust that rows it gets back are rows it is allowed to see. There is
   no server-side API gate between the app and these tables.
2. `profiles` is world-readable; everything privacy-sensitive lives in `profile_details`
   behind `is_public`. A null `profile_details` read means "treat as private".
3. A `profiles` row exists for every user immediately after sign-up (trigger).
   `profile_details` does NOT — upsert it lazily.
4. Published UGC (`status = 'published'`) on `user_uploads` / `posts` / `lists` /
   `photo_albums` is world-readable without auth; so are public playlists+items, public
   profiles' connections, and published wall comments on public walls. That is the complete
   anonymous surface — everything else requires a session.
5. The author always sees ALL their own UGC rows, `removed` included — render removed
   pieces with a takedown badge (web copy: "removed by the curator") and offer Delete only.
6. Self-publish is live: authors freely insert/flip `private` ↔ `published`; no review
   queue, no pending state exists anymore.
7. Wall comments go live immediately on insert (`status='published'` is the only value an
   author can write).
8. Check constraints hold even against the curator: status values outside the documented
   vocabularies cannot exist in any row the app reads.

**Must not attempt (RLS/constraints will refuse — design the UI to reflect, not fight):**

1. **Un-removing a removed piece.** `UPDATE … WHERE id = X` on a `removed` row matches
   zero rows and returns *success with no data* — always `.select()` after a mutation and
   check the row count; surface "this piece was removed and can't be edited". The only
   author action on a removed row is DELETE (allowed, permanent, not an un-remove).
2. Writing `status = 'removed'`, or any legacy value (`draft`, `pending`, `rejected`) —
   insert/update policies allow only `('private', 'published')`; legacy values also fail
   the CHECK constraints.
3. Updating or user-deleting wall comments — there is no user update policy; only delete
   (as author anywhere, or as owner on one's own wall) and only insert-as-published.
4. Setting `r2_key`/`cover_r2_key`/`photos.r2_key` outside `user/<own-uid>/…` — `42501`.
5. Posting a wall comment on a private wall, or where a block exists in either direction —
   `42501`. Show a generic "couldn't post" message; never reveal block state.
6. Sending a DM where a block exists in either direction — `42501`, same generic-error rule.
7. Reading other users' favorites, listen_status, messages, blocks, or reports — these are
   strictly private; don't build UI that assumes cross-user visibility.
8. Marking one's own *sent* messages read, editing, or deleting any message — only the
   recipient may update; no delete policy exists.
9. Withdrawing or editing a report — insert and read-own only.
10. Deleting a `profiles` or `profile_details` row — no delete policies; account deletion
    is an `auth.users` cascade, out of client scope.
11. Counting "own" UGC rows without `.eq('user_id', me)` — the own-or-published select
    policy silently widens unfiltered queries to everyone's published rows.
12. Exceeding app-level limits the DB won't catch: 12 rotation tiles, the 24h/20-piece
    creation brake, wall body 1–1000 chars (this one IS a DB check — validate before send),
    `unique (user_id, name)` on connections and `unique (user_id, slug)` on posts (DB
    uniques — handle `23505` gracefully).
