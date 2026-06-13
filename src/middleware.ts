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

  // Mirror public/_headers (which only covers static routes) onto SSR responses.
  // CSP itself rides on the <meta> in Base.astro, so it's not set here.
  const response = await next();
  response.headers.set('X-Content-Type-Options', 'nosniff');
  response.headers.set('Referrer-Policy', 'strict-origin-when-cross-origin');
  response.headers.set('X-Frame-Options', 'SAMEORIGIN');
  response.headers.set('Strict-Transport-Security', 'max-age=31536000; includeSubDomains');
  return response;
});
