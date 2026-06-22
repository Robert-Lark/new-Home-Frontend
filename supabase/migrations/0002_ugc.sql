-- Quiet Cast — user-generated content (Phase 6).
-- Run after 0001_init.sql in the Supabase dashboard → SQL Editor.
--
-- Adds the two UGC types 0001 didn't model (curated lists, concert photo
-- albums), brings posts under the same owner-approval gate as uploads, and
-- tightens the 0001 policies so users cannot self-publish or claim R2 keys
-- outside their own prefix. The owner moderates via the service-role key
-- (bypasses RLS) in the ADMIN_EMAIL-gated /admin/moderation route.

-- ---------------------------------------------------------------------------
-- posts — join the moderation flow.
-- 0001 allowed ('draft','published') with users flipping status themselves.
-- Now: draft → pending (user submits) → published/rejected (owner only).
-- ---------------------------------------------------------------------------
alter table public.posts drop constraint if exists posts_status_check;
alter table public.posts
  add constraint posts_status_check
  check (status in ('draft', 'pending', 'published', 'rejected'));
alter table public.posts add column if not exists reviewed_at timestamptz;

-- Users may create/keep rows only in draft or pending — publishing is the
-- owner's move (service role bypasses RLS, so these checks don't bind it).
drop policy if exists "posts_insert_own" on public.posts;
create policy "posts_insert_own" on public.posts
  for insert with check (auth.uid() = user_id and status in ('draft', 'pending'));

-- Editing a published/rejected post pulls it back through review.
drop policy if exists "posts_update_own" on public.posts;
create policy "posts_update_own" on public.posts
  for update using (auth.uid() = user_id)
  with check (auth.uid() = user_id and status in ('draft', 'pending'));

-- ---------------------------------------------------------------------------
-- user_uploads — same self-publish fix + R2 key prefix enforcement.
-- A user's objects live under user/<uid>/…; without the prefix check a
-- metadata row could point at the owner archive or another user's object.
-- ---------------------------------------------------------------------------
drop policy if exists "uploads_insert_own" on public.user_uploads;
create policy "uploads_insert_own" on public.user_uploads
  for insert with check (
    auth.uid() = user_id
    and status = 'pending'
    and r2_key like 'user/' || auth.uid()::text || '/%'
    and (cover_r2_key is null or cover_r2_key like 'user/' || auth.uid()::text || '/%')
  );

drop policy if exists "uploads_update_own" on public.user_uploads;
create policy "uploads_update_own" on public.user_uploads
  for update using (auth.uid() = user_id)
  with check (
    auth.uid() = user_id
    and status = 'pending'
    and r2_key like 'user/' || auth.uid()::text || '/%'
    and (cover_r2_key is null or cover_r2_key like 'user/' || auth.uid()::text || '/%')
  );

-- ---------------------------------------------------------------------------
-- lists (curated: favorite records, labels, artists, shows…) + items
-- Distinct from playlists: playlists queue playable content_refs; list items
-- are free-text entries (often things not on the site at all).
-- ---------------------------------------------------------------------------
create table if not exists public.lists (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users (id) on delete cascade,
  title       text not null,
  description text,
  status      text not null default 'pending'
                check (status in ('pending', 'published', 'rejected')),
  reviewed_at timestamptz,
  created_at  timestamptz not null default now()
);
alter table public.lists enable row level security;

drop policy if exists "lists_select_own_or_published" on public.lists;
create policy "lists_select_own_or_published" on public.lists
  for select using (auth.uid() = user_id or status = 'published');

drop policy if exists "lists_insert_own" on public.lists;
create policy "lists_insert_own" on public.lists
  for insert with check (auth.uid() = user_id and status = 'pending');

drop policy if exists "lists_update_own" on public.lists;
create policy "lists_update_own" on public.lists
  for update using (auth.uid() = user_id)
  with check (auth.uid() = user_id and status = 'pending');

drop policy if exists "lists_delete_own" on public.lists;
create policy "lists_delete_own" on public.lists
  for delete using (auth.uid() = user_id);

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
alter table public.list_items enable row level security;

-- Access follows the parent list (same pattern as playlist_items).
drop policy if exists "list_items_select" on public.list_items;
create policy "list_items_select" on public.list_items
  for select using (
    exists (
      select 1 from public.lists l
      where l.id = list_id and (l.user_id = auth.uid() or l.status = 'published')
    )
  );

drop policy if exists "list_items_insert" on public.list_items;
create policy "list_items_insert" on public.list_items
  for insert with check (
    exists (select 1 from public.lists l where l.id = list_id and l.user_id = auth.uid())
  );

drop policy if exists "list_items_update" on public.list_items;
create policy "list_items_update" on public.list_items
  for update using (
    exists (select 1 from public.lists l where l.id = list_id and l.user_id = auth.uid())
  ) with check (
    exists (select 1 from public.lists l where l.id = list_id and l.user_id = auth.uid())
  );

drop policy if exists "list_items_delete" on public.list_items;
create policy "list_items_delete" on public.list_items
  for delete using (
    exists (select 1 from public.lists l where l.id = list_id and l.user_id = auth.uid())
  );

-- ---------------------------------------------------------------------------
-- photo_albums (concert photos) + photos
-- Image bytes live in R2 (same zero-egress path as audio); rows are metadata.
-- Photos carry no status of their own — visibility follows the album.
-- ---------------------------------------------------------------------------
create table if not exists public.photo_albums (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users (id) on delete cascade,
  title       text not null,
  venue       text,
  event_date  date,
  description text,
  status      text not null default 'pending'
                check (status in ('pending', 'published', 'rejected')),
  reviewed_at timestamptz,
  created_at  timestamptz not null default now()
);
alter table public.photo_albums enable row level security;

drop policy if exists "albums_select_own_or_published" on public.photo_albums;
create policy "albums_select_own_or_published" on public.photo_albums
  for select using (auth.uid() = user_id or status = 'published');

drop policy if exists "albums_insert_own" on public.photo_albums;
create policy "albums_insert_own" on public.photo_albums
  for insert with check (auth.uid() = user_id and status = 'pending');

drop policy if exists "albums_update_own" on public.photo_albums;
create policy "albums_update_own" on public.photo_albums
  for update using (auth.uid() = user_id)
  with check (auth.uid() = user_id and status = 'pending');

drop policy if exists "albums_delete_own" on public.photo_albums;
create policy "albums_delete_own" on public.photo_albums
  for delete using (auth.uid() = user_id);

create table if not exists public.photos (
  id       uuid primary key default gen_random_uuid(),
  album_id uuid not null references public.photo_albums (id) on delete cascade,
  r2_key   text not null,
  caption  text,
  position integer not null default 0
);
alter table public.photos enable row level security;

drop policy if exists "photos_select" on public.photos;
create policy "photos_select" on public.photos
  for select using (
    exists (
      select 1 from public.photo_albums a
      where a.id = album_id and (a.user_id = auth.uid() or a.status = 'published')
    )
  );

-- Insert requires owning the album AND the R2 key prefix.
drop policy if exists "photos_insert" on public.photos;
create policy "photos_insert" on public.photos
  for insert with check (
    exists (select 1 from public.photo_albums a where a.id = album_id and a.user_id = auth.uid())
    and r2_key like 'user/' || auth.uid()::text || '/%'
  );

drop policy if exists "photos_update" on public.photos;
create policy "photos_update" on public.photos
  for update using (
    exists (select 1 from public.photo_albums a where a.id = album_id and a.user_id = auth.uid())
  ) with check (
    exists (select 1 from public.photo_albums a where a.id = album_id and a.user_id = auth.uid())
    and r2_key like 'user/' || auth.uid()::text || '/%'
  );

drop policy if exists "photos_delete" on public.photos;
create policy "photos_delete" on public.photos
  for delete using (
    exists (select 1 from public.photo_albums a where a.id = album_id and a.user_id = auth.uid())
  );

-- ---------------------------------------------------------------------------
-- reports — cover the new content types.
-- ---------------------------------------------------------------------------
alter table public.reports drop constraint if exists reports_content_type_check;
alter table public.reports
  add constraint reports_content_type_check
  check (content_type in ('upload', 'message', 'post', 'playlist', 'list', 'photo_album'));

-- ---------------------------------------------------------------------------
-- indexes for the public browse + moderation queries
-- ---------------------------------------------------------------------------
create index if not exists user_uploads_status_created_idx on public.user_uploads (status, created_at desc);
create index if not exists posts_status_created_idx        on public.posts (status, created_at desc);
create index if not exists lists_status_created_idx        on public.lists (status, created_at desc);
create index if not exists photo_albums_status_created_idx on public.photo_albums (status, created_at desc);
create index if not exists list_items_list_idx             on public.list_items (list_id, position);
create index if not exists photos_album_idx                on public.photos (album_id, position);
