-- Quiet Cast — profile pages (old-web "top friends" dashboard).
-- Run after 0002_ugc.sql in the Supabase dashboard → SQL Editor.
--
-- The dashboard becomes a listener profile with a pinboard grid of
-- connections (artists / labels / venues…) and a public view at /u/<id>.
-- `profiles` must stay world-readable (bylines on published content), so
-- everything privacy-sensitive lives here in profile_details, where RLS can
-- enforce the is_public flag row-by-row.

-- ---------------------------------------------------------------------------
-- profile_details (1:1 with auth.users; created lazily by app-level upsert)
-- ---------------------------------------------------------------------------
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

-- ---------------------------------------------------------------------------
-- connections — the profile grid: pinned artists, labels, venues, podcasts,
-- photographers, and (later) other listeners. v1 rows come from a fixed
-- catalog in the front-end; the columns already allow free-form entries.
-- ---------------------------------------------------------------------------
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

-- Visibility follows the owner's privacy flag (derived-access pattern, like
-- playlist_items: the subquery reads profile_details through its own RLS).
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
