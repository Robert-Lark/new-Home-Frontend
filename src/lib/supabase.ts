import { createBrowserClient } from '@supabase/ssr';
import { PUBLIC_SUPABASE_URL, PUBLIC_SUPABASE_ANON_KEY } from 'astro:env/client';

/**
 * Browser Supabase client for interactive islands (favorites, listen-status,
 * upload form). RLS enforces per-user access, so the publishable/anon key is
 * safe in the bundle.
 *
 * The SSR server client (cookie-based session via @supabase/ssr +
 * Astro.cookies, used for auth-gated routes and signed-upload endpoints)
 * lands in Phase 5 — it needs the per-request Astro context, so it can't be a
 * module singleton like this.
 */
export function createSupabaseBrowserClient() {
  return createBrowserClient(PUBLIC_SUPABASE_URL, PUBLIC_SUPABASE_ANON_KEY);
}
