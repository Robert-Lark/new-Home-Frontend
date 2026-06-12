-- Quiet Cast — profile comment wall (the MySpace feature).
-- Run after 0003_profile.sql in the Supabase dashboard → SQL Editor.
--
-- Comments go live immediately (owner's call, 2026-06-12): no review queue.
-- The wall owner deletes anything on their wall, authors delete their own,
-- and reported comments can be taken down (status → 'removed') by the
-- curator's service-role client in /admin/moderation.

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

-- Readable when published AND the wall is visible: your own wall, your own
-- comment, or a public profile (derived-access subquery, same pattern as
-- connections_select in 0003 — the subquery reads profile_details through
-- its own RLS).
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

-- Comment only as yourself, only live, only on public walls, and only when
-- neither party has blocked the other (same shape as messages_insert_sender
-- in 0001).
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

-- The wall owner may delete any comment on their wall; authors their own.
drop policy if exists "wall_delete_owner_or_author" on public.wall_comments;
create policy "wall_delete_owner_or_author" on public.wall_comments
  for delete using (auth.uid() in (profile_id, author_id));

-- No user update policy: takedowns happen through the service-role client.

create index if not exists wall_comments_profile_idx
  on public.wall_comments (profile_id, created_at desc);

-- ---------------------------------------------------------------------------
-- reports — wall comments are reportable.
-- ---------------------------------------------------------------------------
alter table public.reports drop constraint if exists reports_content_type_check;
alter table public.reports
  add constraint reports_content_type_check
  check (content_type in ('upload', 'message', 'post', 'playlist', 'list', 'photo_album', 'wall_comment'));
