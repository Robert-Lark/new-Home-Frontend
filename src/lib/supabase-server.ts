import { createServerClient, parseCookieHeader, type CookieMethodsServer } from '@supabase/ssr';
import { PUBLIC_SUPABASE_URL, PUBLIC_SUPABASE_ANON_KEY } from 'astro:env/client';
import type { AstroCookies, AstroCookieSetOptions } from 'astro';

/**
 * Per-request Supabase client bound to Astro's cookies, for SSR / auth-gated
 * routes. Uses the publishable (anon) key — RLS scopes every read/write to the
 * authenticated user. The service-role key is never used in the request path.
 *
 * Cookie adapter uses the current getAll/setAll API (@supabase/ssr ≥0.5).
 */
export function createSupabaseServerClient(ctx: { request: Request; cookies: AstroCookies }) {
  const cookies: CookieMethodsServer = {
    getAll() {
      return parseCookieHeader(ctx.request.headers.get('Cookie') ?? '').map((c) => ({
        name: c.name,
        value: c.value ?? '',
      }));
    },
    setAll(cookiesToSet) {
      cookiesToSet.forEach(({ name, value, options }) => {
        ctx.cookies.set(name, value, options as AstroCookieSetOptions);
      });
    },
  };

  return createServerClient(PUBLIC_SUPABASE_URL, PUBLIC_SUPABASE_ANON_KEY, { cookies });
}
