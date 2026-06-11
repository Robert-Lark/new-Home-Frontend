import { defineMiddleware } from 'astro:middleware';
import { createSupabaseServerClient } from './lib/supabase-server';

/**
 * Attaches a per-request Supabase client and the validated user to
 * Astro.locals for SSR routes. Skipped for prerendered (static) pages — they
 * have no request cookies and must not make build-time auth calls.
 *
 * Uses getUser() (validates the JWT with the auth server), never getSession()
 * (which trusts the cookie blindly) — per Supabase server-side guidance.
 */
export const onRequest = defineMiddleware(async (context, next) => {
  if (context.isPrerendered) return next();

  const supabase = createSupabaseServerClient(context);
  context.locals.supabase = supabase;

  const {
    data: { user },
  } = await supabase.auth.getUser();
  context.locals.user = user;

  return next();
});
