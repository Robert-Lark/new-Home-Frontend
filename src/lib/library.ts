import { createSupabaseBrowserClient } from './supabase';
import { currentUserId } from './listen';
import type { SupabaseClient } from '@supabase/supabase-js';
import type { ContentRef } from './listen';

/**
 * Browser-side favorites + named playlists. Mirrors the listen.ts seam: an
 * RLS-scoped anon-key client (so reads/writes need no explicit user_id filter),
 * the shared cookie session for the uid, optimistic local caches, and a
 * `document` event per mutation that on-page islands listen to.
 *
 * `content_ref` is the one cross-feature key: Sanity episode slug today, upload
 * UUID later. favorites, playlists, and listen_status all key on the same value.
 */
export type { ContentRef };

export interface Playlist {
  id: string;
  name: string;
  description: string | null;
  isPublic: boolean;
  createdAt: string;
  /** Item count (from the embedded aggregate); 0 when unknown. */
  count: number;
}

export interface PlaylistItem {
  id: string;
  contentRef: ContentRef;
  position: number;
}

/**
 * Dispatched on `document` after a favorite write.
 * detail: { ref: ContentRef, favorite: boolean }
 */
export const FAVORITE_EVENT = 'qc:favorite';
/**
 * Dispatched on `document` after any playlist mutation, so menus/managers
 * refresh. detail: { action, playlistId?, ref? }
 */
export const PLAYLIST_EVENT = 'qc:playlist';

export type PlaylistAction = 'create' | 'rename' | 'delete' | 'add' | 'remove' | 'reorder';

function db(): SupabaseClient {
  return createSupabaseBrowserClient();
}

function emitFavorite(ref: ContentRef, favorite: boolean): void {
  document.dispatchEvent(new CustomEvent(FAVORITE_EVENT, { detail: { ref, favorite } }));
}
function emitPlaylist(action: PlaylistAction, playlistId?: string, ref?: ContentRef): void {
  document.dispatchEvent(new CustomEvent(PLAYLIST_EVENT, { detail: { action, playlistId, ref } }));
}

// ---------------------------------------------------------------------------
// Favorites
// ---------------------------------------------------------------------------

let _favorites: Set<ContentRef> | null = null;

/** All of the signed-in user's favorited refs. Cached; logged out → empty. */
export async function fetchFavorites(force = false): Promise<Set<ContentRef>> {
  if (_favorites && !force) return _favorites;
  const uid = await currentUserId();
  if (!uid) return (_favorites = new Set());
  const { data, error } = await db().from('favorites').select('content_ref');
  const set = new Set<ContentRef>();
  if (!error && data) for (const r of data) set.add(r.content_ref as ContentRef);
  return (_favorites = set);
}

export async function isFavorite(ref: ContentRef): Promise<boolean> {
  return (await fetchFavorites()).has(ref);
}

/**
 * Flip the favorite state for one ref. Optimistic: updates the cache + emits
 * the event immediately, reverts both if the write fails. Returns the resulting
 * state (the prior state on failure, false when logged out).
 */
export async function toggleFavorite(ref: ContentRef): Promise<boolean> {
  const uid = await currentUserId();
  if (!uid) return false;
  const favs = await fetchFavorites();
  const wasFav = favs.has(ref);
  const next = !wasFav;

  if (next) favs.add(ref);
  else favs.delete(ref);
  emitFavorite(ref, next);

  let error;
  if (next) {
    ({ error } = await db().from('favorites').insert({ user_id: uid, content_ref: ref }));
    // unique(user_id, content_ref): a duplicate just means it's already saved.
    if (error && error.code === '23505') error = null;
  } else {
    ({ error } = await db().from('favorites').delete().eq('content_ref', ref));
  }

  if (error) {
    if (next) favs.delete(ref);
    else favs.add(ref);
    emitFavorite(ref, wasFav);
    console.warn('[library] toggleFavorite failed:', error.message);
    return wasFav;
  }
  return next;
}

// ---------------------------------------------------------------------------
// Playlists
// ---------------------------------------------------------------------------

let _playlists: Playlist[] | null = null;
/** Per-playlist item cache; cleared wholesale on any item mutation. */
const _items = new Map<string, PlaylistItem[]>();

function mapPlaylist(r: {
  id: string;
  name: string;
  description: string | null;
  is_public: boolean;
  created_at: string;
  playlist_items?: Array<{ count: number }> | null;
}): Playlist {
  return {
    id: r.id,
    name: r.name,
    description: r.description,
    isPublic: r.is_public,
    createdAt: r.created_at,
    count: r.playlist_items?.[0]?.count ?? 0,
  };
}

/** The signed-in user's playlists (newest first) with item counts. */
export async function fetchPlaylists(force = false): Promise<Playlist[]> {
  if (_playlists && !force) return _playlists;
  const uid = await currentUserId();
  if (!uid) return (_playlists = []);
  const { data, error } = await db()
    .from('playlists')
    .select('id, name, description, is_public, created_at, playlist_items(count)')
    // RLS allows reading public playlists too; this UI is "my playlists" only.
    .eq('user_id', uid)
    .order('created_at', { ascending: false });
  if (error || !data) return (_playlists = []);
  return (_playlists = data.map(mapPlaylist));
}

export async function createPlaylist(name: string, description?: string): Promise<Playlist | null> {
  const uid = await currentUserId();
  const trimmed = name.trim();
  if (!uid || !trimmed) return null;
  const { data, error } = await db()
    .from('playlists')
    .insert({ user_id: uid, name: trimmed, description: description?.trim() || null })
    .select('id, name, description, is_public, created_at')
    .single();
  if (error || !data) {
    console.warn('[library] createPlaylist failed:', error?.message);
    return null;
  }
  const pl = mapPlaylist(data);
  _playlists = _playlists ? [pl, ..._playlists] : [pl];
  emitPlaylist('create', pl.id);
  return pl;
}

export async function renamePlaylist(id: string, name: string): Promise<boolean> {
  const trimmed = name.trim();
  if (!trimmed) return false;
  const { error } = await db().from('playlists').update({ name: trimmed }).eq('id', id);
  if (error) {
    console.warn('[library] renamePlaylist failed:', error.message);
    return false;
  }
  const pl = _playlists?.find((p) => p.id === id);
  if (pl) pl.name = trimmed;
  emitPlaylist('rename', id);
  return true;
}

export async function deletePlaylist(id: string): Promise<boolean> {
  const { error } = await db().from('playlists').delete().eq('id', id);
  if (error) {
    console.warn('[library] deletePlaylist failed:', error.message);
    return false;
  }
  _playlists = _playlists?.filter((p) => p.id !== id) ?? null;
  _items.delete(id);
  emitPlaylist('delete', id);
  return true;
}

/** Ordered items for one playlist (by position, then insertion). Cached. */
export async function fetchPlaylistItems(playlistId: string, force = false): Promise<PlaylistItem[]> {
  const cached = _items.get(playlistId);
  if (cached && !force) return cached;
  const { data, error } = await db()
    .from('playlist_items')
    .select('id, content_ref, position')
    .eq('playlist_id', playlistId)
    .order('position', { ascending: true })
    .order('added_at', { ascending: true });
  if (error || !data) return [];
  const items = data.map((r) => ({ id: r.id, contentRef: r.content_ref as ContentRef, position: r.position }));
  _items.set(playlistId, items);
  return items;
}

/** Append a ref to a playlist (no-op if already present). */
export async function addToPlaylist(playlistId: string, ref: ContentRef): Promise<boolean> {
  const items = await fetchPlaylistItems(playlistId);
  if (items.some((it) => it.contentRef === ref)) return true;
  const position = (items.at(-1)?.position ?? -1) + 1;
  const { data, error } = await db()
    .from('playlist_items')
    .insert({ playlist_id: playlistId, content_ref: ref, position })
    .select('id, content_ref, position')
    .single();
  if (error || !data) {
    console.warn('[library] addToPlaylist failed:', error?.message);
    return false;
  }
  items.push({ id: data.id, contentRef: data.content_ref as ContentRef, position: data.position });
  bumpCount(playlistId, 1);
  emitPlaylist('add', playlistId, ref);
  return true;
}

/** Remove one item from a playlist by its row id. */
export async function removeFromPlaylist(playlistId: string, itemId: string): Promise<boolean> {
  const { error } = await db().from('playlist_items').delete().eq('id', itemId);
  if (error) {
    console.warn('[library] removeFromPlaylist failed:', error.message);
    return false;
  }
  const items = _items.get(playlistId);
  if (items) _items.set(playlistId, items.filter((it) => it.id !== itemId));
  bumpCount(playlistId, -1);
  emitPlaylist('remove', playlistId);
  return true;
}

/** Remove a ref from a playlist by content_ref (looks up the item row). */
export async function removeRefFromPlaylist(playlistId: string, ref: ContentRef): Promise<boolean> {
  const items = await fetchPlaylistItems(playlistId);
  const item = items.find((it) => it.contentRef === ref);
  if (!item) return true;
  return removeFromPlaylist(playlistId, item.id);
}

/** Persist a new order. `orderedItemIds` is the desired item-id sequence. */
export async function reorderPlaylist(playlistId: string, orderedItemIds: string[]): Promise<boolean> {
  const results = await Promise.all(
    orderedItemIds.map((id, i) => db().from('playlist_items').update({ position: i }).eq('id', id)),
  );
  const failed = results.find((r) => r.error);
  if (failed) {
    console.warn('[library] reorderPlaylist failed:', failed.error?.message);
    return false;
  }
  const items = _items.get(playlistId);
  if (items) {
    const byId = new Map(items.map((it) => [it.id, it]));
    _items.set(
      playlistId,
      orderedItemIds
        .map((id, i) => {
          const it = byId.get(id);
          return it ? { ...it, position: i } : null;
        })
        .filter((it): it is PlaylistItem => it !== null),
    );
  }
  emitPlaylist('reorder', playlistId);
  return true;
}

/** Which of the user's playlists already contain `ref` (for menu checkmarks). */
export async function playlistsContaining(ref: ContentRef): Promise<Set<string>> {
  const uid = await currentUserId();
  if (!uid) return new Set();
  const { data, error } = await db()
    .from('playlist_items')
    .select('playlist_id, playlists!inner(user_id)')
    .eq('content_ref', ref)
    .eq('playlists.user_id', uid);
  const set = new Set<string>();
  if (!error && data) for (const r of data) set.add(r.playlist_id as string);
  return set;
}

function bumpCount(playlistId: string, delta: number): void {
  const pl = _playlists?.find((p) => p.id === playlistId);
  if (pl) pl.count = Math.max(0, pl.count + delta);
}

/** Drop in-memory caches if auth changes mid-session. */
export function resetLibraryCache(): void {
  _favorites = null;
  _playlists = null;
  _items.clear();
}
