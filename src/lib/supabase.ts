import { createBrowserClient } from '@supabase/ssr';
import type { SupabaseClient } from '@supabase/supabase-js';
import { PUBLIC_SUPABASE_URL, PUBLIC_SUPABASE_ANON_KEY } from 'astro:env/client';

/**
 * Browser Supabase client for interactive islands (favorites, listen-status,
 * playlists, upload form). RLS enforces per-user access, so the
 * publishable/anon key is safe in the bundle.
 *
 * Memoized to a single instance: every browser data module (listen.ts,
 * library.ts, the login form) shares it, which keeps one GoTrueClient /
 * one cookie-session source of truth (multiple instances warn and can race
 * on token refresh).
 *
 * The SSR server client (cookie-based session via @supabase/ssr +
 * Astro.cookies, used for auth-gated routes and signed-upload endpoints)
 * is separate (src/lib/supabase-server.ts) — it needs the per-request Astro
 * context, so it can't be a module singleton like this.
 */
let _browser: SupabaseClient | null = null;
export function createSupabaseBrowserClient(): SupabaseClient {
  return (_browser ??= createBrowserClient(PUBLIC_SUPABASE_URL, PUBLIC_SUPABASE_ANON_KEY));
}
