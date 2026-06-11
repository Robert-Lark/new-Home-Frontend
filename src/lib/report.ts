import type { SupabaseClient, User } from '@supabase/supabase-js';

/**
 * Shared POST handler for the report form on UGC detail pages (the pages'
 * only form, so any POST to them is a report). Inserts under RLS — users only
 * ever see their own reports; the owner reads the queue with the service-role
 * key in /admin/moderation.
 */
export async function handleReport(
  ctx: {
    request: Request;
    locals: { user: User | null; supabase: SupabaseClient };
  },
  contentType: 'upload' | 'post' | 'list' | 'photo_album',
  contentRef: string,
): Promise<{ ok: boolean; message: string } | null> {
  if (ctx.request.method !== 'POST') return null;
  const user = ctx.locals.user;
  if (!user) return { ok: false, message: 'Sign in to report content.' };

  const form = await ctx.request.formData();
  const reason = String(form.get('reason') ?? '').trim().slice(0, 1000);
  if (!reason) return { ok: false, message: 'Say briefly what the problem is.' };

  const { error } = await ctx.locals.supabase.from('reports').insert({
    reporter_id: user.id,
    content_type: contentType,
    content_ref: contentRef,
    reason,
  });
  if (error) return { ok: false, message: 'Could not file the report — try again.' };
  return { ok: true, message: 'Reported — the curator will take a look.' };
}
