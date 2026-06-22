-- Quiet Cast — self-publish: visibility is the author's choice.
-- Run after 0004_wall.sql in the Supabase dashboard → SQL Editor.
--
-- The review queue dies. Users pick public/private when they post and can
-- flip it later; that flag alone decides whether a piece appears on
-- /community, in site news, and on the public profile. The status vocabulary
-- becomes private/published/removed on all four UGC tables — posts' 'draft'
-- folds into 'private' (same RLS reality: only the author sees it), and
-- 'published' keeps its meaning everywhere it's read.
--
-- Moderation goes post-hoc, wall-style (0004): reports stay, and a takedown
-- is the curator's service-role client setting status = 'removed' (stamp
-- reviewed_at while at it). Users can never write 'removed', and a removed
-- row drops out of their updatable set entirely — so a takedown can't be
-- undone or edited around. Unlike wall comments, removed rows STAY VISIBLE
-- to their author (the select policies don't change): their own work
-- shouldn't silently vanish from their dashboard, they just can't touch it.
-- Deleting a removed row remains allowed (same as wall comments) — that
-- removes the content outright, which is not an un-remove.
--
-- DEPLOY COUPLING — run this together with the front-end deploy that
-- retires the queue UI. Old code against this schema breaks two paths:
--   · /contribute/post sends status='pending' → now RLS-rejected;
--   · the report "Take down" buttons write status='rejected' → now
--     constraint-rejected (check constraints bind the service role too).
-- The other flows survive the gap: mix/photo/list inserts omit status and
-- inherit the new 'private' default.
--
-- Existing rows: EVERYTHING non-published goes private — pending, rejected,
-- and posts' drafts all land in 'private' (owner's call, 2026-06-12). No
-- backlog appears on /community at migration time; authors republish on
-- their own terms once the visibility toggle ships.
--
-- The MAX_PENDING_PER_USER abuse brake (counted 'pending' rows) goes moot;
-- its replacement — refuse new pieces when 20 were created in the trailing
-- 24h — is app-level like its predecessor, so no schema here.

-- ---------------------------------------------------------------------------
-- user_uploads
-- ---------------------------------------------------------------------------
alter table public.user_uploads drop constraint if exists user_uploads_status_check;
update public.user_uploads set status = 'private' where status in ('pending', 'rejected');
alter table public.user_uploads
  add constraint user_uploads_status_check
  check (status in ('private', 'published', 'removed'));
alter table public.user_uploads alter column status set default 'private';

drop policy if exists "uploads_insert_own" on public.user_uploads;
create policy "uploads_insert_own" on public.user_uploads
  for insert with check (
    auth.uid() = user_id
    and status in ('private', 'published')
    and r2_key like 'user/' || auth.uid()::text || '/%'
    and (cover_r2_key is null or cover_r2_key like 'user/' || auth.uid()::text || '/%')
  );

drop policy if exists "uploads_update_own" on public.user_uploads;
create policy "uploads_update_own" on public.user_uploads
  for update using (auth.uid() = user_id and status <> 'removed')
  with check (
    auth.uid() = user_id
    and status in ('private', 'published')
    and r2_key like 'user/' || auth.uid()::text || '/%'
    and (cover_r2_key is null or cover_r2_key like 'user/' || auth.uid()::text || '/%')
  );

-- ---------------------------------------------------------------------------
-- posts — 'draft' and the queue states all fold into 'private'.
-- Editing a published post no longer drags it back through review (the 0002
-- posts_update_own with-check did that deliberately; that era ends here).
-- ---------------------------------------------------------------------------
alter table public.posts drop constraint if exists posts_status_check;
update public.posts set status = 'private' where status in ('draft', 'pending', 'rejected');
alter table public.posts
  add constraint posts_status_check
  check (status in ('private', 'published', 'removed'));
alter table public.posts alter column status set default 'private';

drop policy if exists "posts_insert_own" on public.posts;
create policy "posts_insert_own" on public.posts
  for insert with check (auth.uid() = user_id and status in ('private', 'published'));

drop policy if exists "posts_update_own" on public.posts;
create policy "posts_update_own" on public.posts
  for update using (auth.uid() = user_id and status <> 'removed')
  with check (auth.uid() = user_id and status in ('private', 'published'));

-- ---------------------------------------------------------------------------
-- lists
-- ---------------------------------------------------------------------------
alter table public.lists drop constraint if exists lists_status_check;
update public.lists set status = 'private' where status in ('pending', 'rejected');
alter table public.lists
  add constraint lists_status_check
  check (status in ('private', 'published', 'removed'));
alter table public.lists alter column status set default 'private';

drop policy if exists "lists_insert_own" on public.lists;
create policy "lists_insert_own" on public.lists
  for insert with check (auth.uid() = user_id and status in ('private', 'published'));

drop policy if exists "lists_update_own" on public.lists;
create policy "lists_update_own" on public.lists
  for update using (auth.uid() = user_id and status <> 'removed')
  with check (auth.uid() = user_id and status in ('private', 'published'));

-- ---------------------------------------------------------------------------
-- photo_albums
-- ---------------------------------------------------------------------------
alter table public.photo_albums drop constraint if exists photo_albums_status_check;
update public.photo_albums set status = 'private' where status in ('pending', 'rejected');
alter table public.photo_albums
  add constraint photo_albums_status_check
  check (status in ('private', 'published', 'removed'));
alter table public.photo_albums alter column status set default 'private';

drop policy if exists "albums_insert_own" on public.photo_albums;
create policy "albums_insert_own" on public.photo_albums
  for insert with check (auth.uid() = user_id and status in ('private', 'published'));

drop policy if exists "albums_update_own" on public.photo_albums;
create policy "albums_update_own" on public.photo_albums
  for update using (auth.uid() = user_id and status <> 'removed')
  with check (auth.uid() = user_id and status in ('private', 'published'));

-- ---------------------------------------------------------------------------
-- Unchanged, deliberately:
--   · select policies (own-or-published) — removed rows stay author-visible,
--     private means exactly what own-or-published already gives;
--   · delete policies — authors may delete anything of theirs, removed
--     included (deletion is not un-removal);
--   · list_items / photos child policies — derived access already follows
--     the parent's status for the public and ownership for the author. An
--     author can still edit children of a removed parent; harmless, since
--     no surface but their own shows them;
--   · reviewed_at columns — now the takedown timestamp;
--   · the (status, created_at) indexes — same published-only read paths;
--   · wall_comments, reports — the 0004 moderation model is untouched.
-- ---------------------------------------------------------------------------
