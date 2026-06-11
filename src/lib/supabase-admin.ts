import { createClient } from '@supabase/supabase-js';
import { SUPABASE_SERVICE_ROLE_KEY, ADMIN_EMAIL } from 'astro:env/server';
import { PUBLIC_SUPABASE_URL } from 'astro:env/client';
import type { User } from '@supabase/supabase-js';

/**
 * Owner/moderation helpers. One-owner site: the admin is whoever matches the
 * ADMIN_EMAIL env var (locked decision — promote to a profiles.role column
 * only if multi-moderator is ever needed). The service-role client bypasses
 * RLS, so it is created ONLY inside isAdmin-gated request handlers and never
 * touches the regular request path.
 */

export function isAdmin(user: User | null): boolean {
  return Boolean(
    user?.email && ADMIN_EMAIL && user.email.toLowerCase() === ADMIN_EMAIL.toLowerCase(),
  );
}

export function createSupabaseAdminClient() {
  if (!SUPABASE_SERVICE_ROLE_KEY) throw new Error('SUPABASE_SERVICE_ROLE_KEY is not configured');
  return createClient(PUBLIC_SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}
