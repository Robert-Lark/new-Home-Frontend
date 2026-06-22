-- Quiet Cast — initial schema for private user data.
-- Run once in the Supabase dashboard → SQL Editor.
-- Every table has Row-Level Security: a user may read/write ONLY their own
-- rows. Published uploads/posts are world-readable. Profiles are world-readable
-- (so author display names can render on public content).

-- ---------------------------------------------------------------------------
-- profiles (1:1 with auth.users)
-- ---------------------------------------------------------------------------
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

-- Auto-create a profile row when a new auth user signs up.
-- SECURITY DEFINER + empty search_path is the Supabase-recommended safe pattern.
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

-- ---------------------------------------------------------------------------
-- favorites
-- content_ref = Sanity doc id (public content) or a user_uploads id.
-- ---------------------------------------------------------------------------
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

-- ---------------------------------------------------------------------------
-- listen_status
-- ---------------------------------------------------------------------------
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

-- ---------------------------------------------------------------------------
-- user_uploads (metadata only — the audio bytes live in R2)
-- ---------------------------------------------------------------------------
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
  status       text not null default 'pending'
                 check (status in ('pending', 'published', 'rejected')),
  reviewed_at  timestamptz,
  created_at   timestamptz not null default now()
);
alter table public.user_uploads enable row level security;

drop policy if exists "uploads_select_own_or_published" on public.user_uploads;
create policy "uploads_select_own_or_published" on public.user_uploads
  for select using (auth.uid() = user_id or status = 'published');

drop policy if exists "uploads_insert_own" on public.user_uploads;
create policy "uploads_insert_own" on public.user_uploads
  for insert with check (auth.uid() = user_id);

drop policy if exists "uploads_update_own" on public.user_uploads;
create policy "uploads_update_own" on public.user_uploads
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "uploads_delete_own" on public.user_uploads;
create policy "uploads_delete_own" on public.user_uploads
  for delete using (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- posts (user blog / reviews)
-- ---------------------------------------------------------------------------
create table if not exists public.posts (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references auth.users (id) on delete cascade,
  slug       text not null,
  title      text not null,
  body_md    text,
  status     text not null default 'draft'
               check (status in ('draft', 'published')),
  created_at timestamptz not null default now(),
  unique (user_id, slug)
);
alter table public.posts enable row level security;

drop policy if exists "posts_select_own_or_published" on public.posts;
create policy "posts_select_own_or_published" on public.posts
  for select using (auth.uid() = user_id or status = 'published');

drop policy if exists "posts_insert_own" on public.posts;
create policy "posts_insert_own" on public.posts
  for insert with check (auth.uid() = user_id);

drop policy if exists "posts_update_own" on public.posts;
create policy "posts_update_own" on public.posts
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "posts_delete_own" on public.posts;
create policy "posts_delete_own" on public.posts
  for delete using (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- playlists (named, user-curated) + items
-- ---------------------------------------------------------------------------
create table if not exists public.playlists (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users (id) on delete cascade,
  name        text not null,
  description text,
  is_public   boolean not null default false,
  created_at  timestamptz not null default now()
);
alter table public.playlists enable row level security;

drop policy if exists "playlists_select_own_or_public" on public.playlists;
create policy "playlists_select_own_or_public" on public.playlists
  for select using (auth.uid() = user_id or is_public);

drop policy if exists "playlists_insert_own" on public.playlists;
create policy "playlists_insert_own" on public.playlists
  for insert with check (auth.uid() = user_id);

drop policy if exists "playlists_update_own" on public.playlists;
create policy "playlists_update_own" on public.playlists
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "playlists_delete_own" on public.playlists;
create policy "playlists_delete_own" on public.playlists
  for delete using (auth.uid() = user_id);

create table if not exists public.playlist_items (
  id          uuid primary key default gen_random_uuid(),
  playlist_id uuid not null references public.playlists (id) on delete cascade,
  content_ref text not null,
  position    integer not null default 0,
  added_at    timestamptz not null default now()
);
alter table public.playlist_items enable row level security;

-- Access follows the parent playlist: readable if you own it or it's public;
-- writable only if you own it.
drop policy if exists "playlist_items_select" on public.playlist_items;
create policy "playlist_items_select" on public.playlist_items
  for select using (
    exists (
      select 1 from public.playlists p
      where p.id = playlist_id and (p.user_id = auth.uid() or p.is_public)
    )
  );

drop policy if exists "playlist_items_insert" on public.playlist_items;
create policy "playlist_items_insert" on public.playlist_items
  for insert with check (
    exists (select 1 from public.playlists p where p.id = playlist_id and p.user_id = auth.uid())
  );

drop policy if exists "playlist_items_update" on public.playlist_items;
create policy "playlist_items_update" on public.playlist_items
  for update using (
    exists (select 1 from public.playlists p where p.id = playlist_id and p.user_id = auth.uid())
  ) with check (
    exists (select 1 from public.playlists p where p.id = playlist_id and p.user_id = auth.uid())
  );

drop policy if exists "playlist_items_delete" on public.playlist_items;
create policy "playlist_items_delete" on public.playlist_items
  for delete using (
    exists (select 1 from public.playlists p where p.id = playlist_id and p.user_id = auth.uid())
  );

-- ---------------------------------------------------------------------------
-- blocks (must exist before messages — the send policy references it)
-- ---------------------------------------------------------------------------
create table if not exists public.blocks (
  blocker_id uuid not null references auth.users (id) on delete cascade,
  blocked_id uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id)
);
alter table public.blocks enable row level security;

drop policy if exists "blocks_select_own" on public.blocks;
create policy "blocks_select_own" on public.blocks
  for select using (auth.uid() = blocker_id);

drop policy if exists "blocks_insert_own" on public.blocks;
create policy "blocks_insert_own" on public.blocks
  for insert with check (auth.uid() = blocker_id);

drop policy if exists "blocks_delete_own" on public.blocks;
create policy "blocks_delete_own" on public.blocks
  for delete using (auth.uid() = blocker_id);

-- ---------------------------------------------------------------------------
-- messages (lightweight DMs; threads derived by sender/recipient pair)
-- ---------------------------------------------------------------------------
create table if not exists public.messages (
  id           uuid primary key default gen_random_uuid(),
  sender_id    uuid not null references auth.users (id) on delete cascade,
  recipient_id uuid not null references auth.users (id) on delete cascade,
  body         text not null,
  created_at   timestamptz not null default now(),
  read_at      timestamptz
);
alter table public.messages enable row level security;

drop policy if exists "messages_select_participant" on public.messages;
create policy "messages_select_participant" on public.messages
  for select using (auth.uid() in (sender_id, recipient_id));

-- Send only as yourself, and only if neither party has blocked the other.
drop policy if exists "messages_insert_sender" on public.messages;
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

-- Recipient may mark messages read.
drop policy if exists "messages_update_recipient" on public.messages;
create policy "messages_update_recipient" on public.messages
  for update using (auth.uid() = recipient_id) with check (auth.uid() = recipient_id);

-- ---------------------------------------------------------------------------
-- reports (user-flagged content → owner moderation queue)
-- Owner reads these server-side via the service-role key (bypasses RLS) in an
-- ADMIN_EMAIL-gated route; users only ever see their own reports.
-- ---------------------------------------------------------------------------
create table if not exists public.reports (
  id           uuid primary key default gen_random_uuid(),
  reporter_id  uuid not null references auth.users (id) on delete cascade,
  content_type text not null check (content_type in ('upload', 'message', 'post', 'playlist')),
  content_ref  text not null,
  reason       text,
  status       text not null default 'open' check (status in ('open', 'reviewed', 'dismissed')),
  created_at   timestamptz not null default now()
);
alter table public.reports enable row level security;

drop policy if exists "reports_insert_own" on public.reports;
create policy "reports_insert_own" on public.reports
  for insert with check (auth.uid() = reporter_id);

drop policy if exists "reports_select_own" on public.reports;
create policy "reports_select_own" on public.reports
  for select using (auth.uid() = reporter_id);
