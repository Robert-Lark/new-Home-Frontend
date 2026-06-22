import type { SupabaseClient, User } from '@supabase/supabase-js';

/**
 * Report handler for UGC detail pages. The hosting page reads the POST body
 * once and dispatches on the form's `action` field (reports vs the owner's
 * visibility toggle), then hands the parsed form here. Inserts under RLS —
 * users only ever see their own reports; the owner reads the queue with the
 * service-role key in /admin/moderation.
 */
export async function handleReport(
  form: FormData,
  locals: { user: User | null; supabase: SupabaseClient },
  contentType: 'upload' | 'post' | 'list' | 'photo_album',
  contentRef: string,
): Promise<{ ok: boolean; message: string }> {
  const user = locals.user;
  if (!user) return { ok: false, message: 'Sign in to report content.' };

  const reason = String(form.get('reason') ?? '').trim().slice(0, 1000);
  if (!reason) return { ok: false, message: 'Say briefly what the problem is.' };

  const { error } = await locals.supabase.from('reports').insert({
    reporter_id: user.id,
    content_type: contentType,
    content_ref: contentRef,
    reason,
  });
  if (error) return { ok: false, message: 'Could not file the report — try again.' };
  return { ok: true, message: 'Reported — the curator will take a look.' };
}

/**
 * Owner visibility toggle on the same pages: flip a piece between private
 * and published. RLS enforces ownership and blocks removed rows (a takedown
 * can't be edited around), but the explicit user_id filter keeps the query
 * honest. Returns an error message, or null on success (caller redirects —
 * PRG).
 */
export async function setVisibility(
  locals: { user: User | null; supabase: SupabaseClient },
  table: 'user_uploads' | 'posts' | 'lists' | 'photo_albums',
  id: string,
  form: FormData,
): Promise<string | null> {
  const user = locals.user;
  if (!user) return 'Sign in first.';
  const next = form.get('visibility') === 'published' ? 'published' : 'private';
  const { error } = await locals.supabase
    .from(table)
    .update({ status: next })
    .eq('id', id)
    .eq('user_id', user.id);
  return error ? 'Could not change visibility — try again.' : null;
}
