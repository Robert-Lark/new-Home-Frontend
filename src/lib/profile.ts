import type { SupabaseClient } from '@supabase/supabase-js';
import type { Track } from '../islands/PlayerDock';
import { trackOf, type Episode } from './content';
import { cdnUrl } from './ugc';
import type { ConnectionKind } from './connections';

/**
 * Shared data layer for the profile pages: the logged-in dashboard and the
 * public /u/<id> view assemble the same shapes from different scopes (own
 * everything vs. published-only — RLS already hides private rows from
 * visitors; the publishedOnly filters here keep drafts out of a user's OWN
 * public preview too).
 */

export interface ProfileRow {
  id: string;
  display_name: string | null;
  avatar_url: string | null;
  created_at: string;
}

export interface ProfileDetails {
  is_public: boolean;
  bio: string | null;
  status_line: string | null;
  profile_song_ref: string | null;
  theme: 'dark' | 'light';
}

export interface Connection {
  id: string;
  kind: ConnectionKind;
  name: string;
  image_url: string | null;
  link_url: string | null;
  position: number;
  created_at: string;
}

/** One row in the "latest activity" feed. */
export interface ActivityEvent {
  /** Short kind tag rendered as the row's eyebrow ("mixtape", "listening"…). */
  kind: string;
  text: string;
  href: string | null;
  at: string;
  /** Own view only: moderation status worth surfacing ("pending", "draft"). */
  note?: string;
}

/** One row in the "meanwhile on Quiet Cast" column. */
export interface NewsItem {
  kind: string;
  title: string;
  href: string;
  at: string;
}

export interface ContentRow {
  id: string;
  title: string;
  status: string;
  created_at: string;
}

export interface UserContent {
  mixes: ContentRow[];
  posts: ContentRow[];
  lists: ContentRow[];
  albums: ContentRow[];
}

// Defensive: tables may not exist until their migration runs, and empty
// results are normal. Either way, degrade to a clean empty state.
export async function safeRows<T>(
  query: PromiseLike<{ data: T[] | null; error: unknown }>,
): Promise<T[]> {
  try {
    const { data, error } = await query;
    return error || !data ? [] : data;
  } catch {
    return [];
  }
}

export async function safeRow<T>(
  query: PromiseLike<{ data: T | null; error: unknown }>,
): Promise<T | null> {
  try {
    const { data, error } = await query;
    return error ? null : data;
  } catch {
    return null;
  }
}

export async function getProfileRow(supabase: SupabaseClient, id: string): Promise<ProfileRow | null> {
  return safeRow<ProfileRow>(
    supabase.from('profiles').select('id, display_name, avatar_url, created_at').eq('id', id).maybeSingle(),
  );
}

/** Null for visitors unless the row exists AND is_public (RLS enforces it). */
export async function getProfileDetails(
  supabase: SupabaseClient,
  id: string,
): Promise<ProfileDetails | null> {
  return safeRow<ProfileDetails>(
    supabase
      .from('profile_details')
      .select('is_public, bio, status_line, profile_song_ref, theme')
      .eq('id', id)
      .maybeSingle(),
  );
}

export async function getConnections(supabase: SupabaseClient, userId: string): Promise<Connection[]> {
  return safeRows<Connection>(
    supabase
      .from('connections')
      .select('id, kind, name, image_url, link_url, position, created_at')
      .eq('user_id', userId)
      .order('position', { ascending: true }),
  );
}

export async function getUserContent(
  supabase: SupabaseClient,
  userId: string,
  publishedOnly: boolean,
): Promise<UserContent> {
  const pull = (table: string) => {
    let q = supabase
      .from(table)
      .select('id, title, status, created_at')
      .eq('user_id', userId)
      .order('created_at', { ascending: false })
      .limit(8);
    if (publishedOnly) q = q.eq('status', 'published');
    return safeRows<ContentRow>(q);
  };
  const [mixes, posts, lists, albums] = await Promise.all([
    pull('user_uploads'),
    pull('posts'),
    pull('lists'),
    pull('photo_albums'),
  ]);
  return { mixes, posts, lists, albums };
}

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * Titles for content_refs that point at community mixes (favorites and listen
 * rows hold either an episode slug or a user_uploads id). Non-uuid refs are
 * dropped before the .in() — Postgres rejects invalid uuid literals outright.
 */
export async function resolveMixTitles(
  supabase: SupabaseClient,
  refs: string[],
): Promise<Map<string, string>> {
  const ids = [...new Set(refs.filter((r) => UUID_RE.test(r)))];
  if (ids.length === 0) return new Map();
  const rows = await safeRows<{ id: string; title: string }>(
    supabase.from('user_uploads').select('id, title').in('id', ids),
  );
  return new Map(rows.map((r) => [r.id, r.title]));
}

export function buildActivity(opts: {
  content: UserContent;
  episodesByRef: Map<string, Episode>;
  mixTitlesByRef?: Map<string, string>;
  favorites?: Array<{ content_ref: string; created_at: string }>;
  listens?: Array<{ content_ref: string; status: string; updated_at: string }>;
  connections?: Connection[];
  /** Notes received on the comment wall (WallEntry is structurally compatible). */
  wallNotes?: Array<{ author_name: string; created_at: string }>;
  limit?: number;
}): ActivityEvent[] {
  const { content, episodesByRef, mixTitlesByRef } = opts;
  const events: ActivityEvent[] = [];
  const note = (status: string) => (status === 'published' ? undefined : status);

  for (const m of content.mixes)
    events.push({ kind: 'mixtape', text: `Uploaded “${m.title}”`, href: `/mixes/${m.id}`, at: m.created_at, note: note(m.status) });
  for (const p of content.posts)
    events.push({ kind: 'writing', text: `Posted “${p.title}”`, href: `/posts/${p.id}`, at: p.created_at, note: note(p.status) });
  for (const l of content.lists)
    events.push({ kind: 'list', text: `Made the list “${l.title}”`, href: `/lists/${l.id}`, at: l.created_at, note: note(l.status) });
  for (const a of content.albums)
    events.push({ kind: 'photos', text: `Shared “${a.title}”`, href: `/photos/${a.id}`, at: a.created_at, note: note(a.status) });

  const refTitle = (ref: string): { title: string; href: string } | null => {
    const ep = episodesByRef.get(ref);
    if (ep) return { title: ep.title, href: `/show/${ep.slug}` };
    const mix = mixTitlesByRef?.get(ref);
    if (mix) return { title: mix, href: `/mixes/${ref}` };
    return null;
  };

  for (const f of opts.favorites ?? []) {
    const t = refTitle(f.content_ref);
    if (t) events.push({ kind: 'favorite', text: `Favorited “${t.title}”`, href: t.href, at: f.created_at });
  }
  for (const l of opts.listens ?? []) {
    const t = refTitle(l.content_ref);
    if (!t || (l.status !== 'playing' && l.status !== 'played')) continue;
    const verb = l.status === 'playing' ? 'Listening to' : 'Finished';
    events.push({ kind: 'listening', text: `${verb} “${t.title}”`, href: t.href, at: l.updated_at });
  }
  for (const c of opts.connections ?? [])
    events.push({ kind: 'grid', text: `Pinned ${c.name} to the grid`, href: c.link_url, at: c.created_at });
  for (const w of opts.wallNotes ?? [])
    events.push({ kind: 'wall', text: `Got a wall note from ${w.author_name}`, href: '#wall', at: w.created_at });

  events.sort((a, b) => b.at.localeCompare(a.at));
  return events.slice(0, opts.limit ?? 12);
}

/**
 * The "meanwhile on Quiet Cast" column: latest broadcasts plus the latest
 * published community contributions (everyone's, not the profile owner's).
 */
export async function getSiteNews(supabase: SupabaseClient, episodes: Episode[]): Promise<NewsItem[]> {
  const broadcasts: NewsItem[] = episodes.slice(0, 3).map((e) => ({
    kind: 'broadcast',
    title: `${e.catLabel} — ${e.title}`,
    href: `/show/${e.slug}`,
    at: e.airDate ?? '',
  }));

  const pull = (table: string, kind: string, path: string) =>
    safeRows<{ id: string; title: string; created_at: string }>(
      supabase
        .from(table)
        .select('id, title, created_at')
        .eq('status', 'published')
        .order('created_at', { ascending: false })
        .limit(4),
    ).then((rows) => rows.map((r) => ({ kind, title: r.title, href: `${path}/${r.id}`, at: r.created_at })));

  const community = (
    await Promise.all([
      pull('user_uploads', 'mix', '/mixes'),
      pull('posts', 'writing', '/posts'),
      pull('lists', 'list', '/lists'),
      pull('photo_albums', 'photos', '/photos'),
    ])
  )
    .flat()
    .sort((a, b) => b.at.localeCompare(a.at))
    .slice(0, 5);

  return [...broadcasts, ...community];
}

/** Resolve a profile-song content_ref to a playable dock Track. */
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
