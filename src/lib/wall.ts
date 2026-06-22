import type { SupabaseClient, User } from '@supabase/supabase-js';
import { safeRows } from './profile';
import { displayNames, publicProfileIds } from './ugc';

/**
 * Comment wall data + the shared POST dispatcher for the two profile surfaces
 * (/dashboard and /u/[id]). Same plain-SSR shape as lib/report.ts: the page
 * parses the form once, hands it here, and renders the outcome — no islands.
 * Comments are live immediately; RLS enforces who may post (public walls,
 * neither party blocked) and who may delete (wall owner: any; author: own).
 * Reported comments reach /admin/moderation, where the service-role client
 * takes them down (status → 'removed').
 */

export interface WallComment {
  id: string;
  author_id: string;
  body: string;
  created_at: string;
}

/** Display shape: a comment plus its resolved author byline. */
export interface WallEntry extends WallComment {
  author_name: string;
  /** /u/<id> when the author's own profile is public, else null. */
  author_href: string | null;
}

export interface WallActionResult {
  ok: boolean;
  message: string;
}

export async function getWallComments(
  supabase: SupabaseClient,
  profileId: string,
  limit = 30,
): Promise<WallComment[]> {
  return safeRows<WallComment>(
    supabase
      .from('wall_comments')
      .select('id, author_id, body, created_at')
      .eq('profile_id', profileId)
      .eq('status', 'published')
      .order('created_at', { ascending: false })
      .limit(limit),
  );
}

/** Attach author names and (when public) profile links to wall comments. */
export async function resolveWallEntries(
  supabase: SupabaseClient,
  comments: WallComment[],
): Promise<WallEntry[]> {
  const authorIds = comments.map((c) => c.author_id);
  const [names, publicIds] = await Promise.all([
    displayNames(supabase, authorIds),
    publicProfileIds(supabase, authorIds),
  ]);
  return comments.map((c) => ({
    ...c,
    author_name: names.get(c.author_id) ?? 'a listener',
    author_href: publicIds.has(c.author_id) ? `/u/${c.author_id}` : null,
  }));
}

/**
 * Handle a wall form POST (post / delete / report). Returns null when the
 * form isn't a wall action, so the hosting page can run its other handlers
 * (the dashboard shares its POST route with the grid forms). On ok results
 * the page should redirect (PRG); failures render inline like report.ts.
 */
export async function handleWallAction(
  form: FormData,
  user: User | null,
  supabase: SupabaseClient,
  profileId: string,
): Promise<WallActionResult | null> {
  const action = form.get('action');
  if (action !== 'wall-post' && action !== 'wall-delete' && action !== 'wall-report') return null;
  if (!user) return { ok: false, message: 'Sign in to write on the wall.' };

  if (action === 'wall-post') {
    const body = String(form.get('body') ?? '').trim().slice(0, 1000);
    if (!body) return { ok: false, message: 'Say something first.' };
    const { error } = await supabase.from('wall_comments').insert({
      profile_id: profileId,
      author_id: user.id,
      body,
    });
    if (error)
      return {
        ok: false,
        // 42501 = RLS refused the insert (private wall or a block), anything
        // else is most likely the table not existing yet.
        message:
          error.code === '42501'
            ? "This wall isn't open to you."
            : 'Could not post — has the 0004 migration run?',
      };
    return { ok: true, message: 'Posted.' };
  }

  const id = String(form.get('id') ?? '');
  if (!id) return { ok: false, message: 'Unrecognized wall action.' };

  if (action === 'wall-delete') {
    // RLS scopes the delete: the wall owner may remove any row on their wall,
    // an author their own — anyone else just matches zero rows.
    const { error } = await supabase.from('wall_comments').delete().eq('id', id);
    if (error) return { ok: false, message: 'Could not remove the note — try again.' };
    return { ok: true, message: 'Removed.' };
  }

  const reason = String(form.get('reason') ?? '').trim().slice(0, 1000);
  if (!reason) return { ok: false, message: 'Say briefly what the problem is.' };
  const { error } = await supabase.from('reports').insert({
    reporter_id: user.id,
    content_type: 'wall_comment',
    content_ref: id,
    reason,
  });
  if (error) return { ok: false, message: 'Could not file the report — try again.' };
  return { ok: true, message: 'Reported — the curator will take a look.' };
}
