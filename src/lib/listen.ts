import { createSupabaseBrowserClient } from './supabase';
import type { SupabaseClient } from '@supabase/supabase-js';

/**
 * Browser-side listen-tracking. The player island records playback progress
 * here; recolor islands read it to mark catalog cells by per-user state. RLS
 * scopes every read/write to the signed-in user, so the anon key is safe and
 * queries need no explicit user_id filter on selects.
 *
 * `content_ref` is the one cross-feature key for a content item: for Sanity
 * episodes it's the slug (== player Track.id); user uploads will use their
 * upload UUID. favorites/playlists key on the same value.
 */
export type ContentRef = string;

export type ListenState = 'unplayed' | 'in-progress' | 'done';

/** ≥90% played counts as "done" (locked feature rule). */
export const DONE_RATIO = 0.9;
/** Don't persist trivial scrubbing / mis-clicks. */
const MIN_RECORD_SECONDS = 5;

/**
 * Dispatched on `document` after a successful progress write, so on-page
 * recolor islands update optimistically without refetching.
 * detail: { ref: ContentRef, state: ListenState }
 */
export const LISTEN_EVENT = 'qc:listen';

let _client: SupabaseClient | null = null;
function db(): SupabaseClient {
  return (_client ??= createSupabaseBrowserClient());
}

let _userId: string | null | undefined;
/** Signed-in user's id from the cookie session (no network). null when logged out. */
export async function currentUserId(): Promise<string | null> {
  if (_userId !== undefined) return _userId;
  const { data } = await db().auth.getSession();
  _userId = data.session?.user?.id ?? null;
  return _userId;
}

/** Stored row status → display state. Absence of a row = unplayed. */
export function stateFromStatus(status: string | null | undefined): ListenState {
  if (status === 'played') return 'done';
  if (status === 'playing') return 'in-progress';
  return 'unplayed';
}

/** Upsert playback progress for the signed-in user. No-op when logged out. */
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
  if (error) {
    console.warn('[listen] recordProgress failed:', error.message);
    return;
  }
  _statusCache?.set(ref, stateFromStatus(status));
  document.dispatchEvent(
    new CustomEvent(LISTEN_EVENT, { detail: { ref, state: stateFromStatus(status) } }),
  );
}

/** Prior progress for one item, for resume-on-play. null when logged out / none. */
export async function fetchProgress(
  ref: ContentRef,
): Promise<{ progressSeconds: number; status: string } | null> {
  const uid = await currentUserId();
  if (!uid) return null;
  const { data, error } = await db()
    .from('listen_status')
    .select('progress_seconds, status')
    .eq('content_ref', ref)
    .maybeSingle();
  if (error || !data) return null;
  return { progressSeconds: data.progress_seconds ?? 0, status: data.status };
}

let _statusCache: Map<ContentRef, ListenState> | null = null;
/**
 * All of the signed-in user's states, ref → state. Cached for the session
 * (the player keeps it warm on each write); pass force to refetch. Logged out
 * → empty map.
 */
export async function fetchStates(force = false): Promise<Map<ContentRef, ListenState>> {
  if (_statusCache && !force) return _statusCache;
  const uid = await currentUserId();
  if (!uid) return (_statusCache = new Map());
  const { data, error } = await db().from('listen_status').select('content_ref, status');
  const map = new Map<ContentRef, ListenState>();
  if (!error && data) for (const r of data) map.set(r.content_ref, stateFromStatus(r.status));
  return (_statusCache = map);
}

/** Drop in-memory caches if auth changes mid-session. */
export function resetListenCache(): void {
  _userId = undefined;
  _statusCache = null;
}
