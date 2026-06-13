export const prerender = false;

import type { APIRoute } from 'astro';
import { createClient } from '@supabase/supabase-js';
import { PUBLIC_SUPABASE_URL, PUBLIC_SUPABASE_ANON_KEY } from 'astro:env/client';
import { createSupabaseAdminClient } from '../../../lib/supabase-admin';

/**
 * In-app account deletion for the native iOS app (App Store guideline 5.1.1(v)).
 *
 * Mirrors the web settings delete flow (settings.astro:120-145): one service-role
 * admin.deleteUser() call, relying on `on delete cascade` from auth.users to remove every
 * user-owned row; R2 objects under user/<uid>/ are left for a manual cleanup pass.
 *
 * The only delta from the web flow is auth transport: the iOS SDK holds no @supabase/ssr
 * cookie, so this endpoint takes the Supabase access token in an `Authorization: Bearer`
 * header and VALIDATES it against the auth server with auth.getUser(jwt) — never decode-and-trust
 * (the same rule the middleware documents). RLS is not weakened anywhere; the service-role
 * client is created only after the token check passes.
 */

function json(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

export const POST: APIRoute = async ({ request }) => {
  // 1. Extract + validate the bearer token against the auth server.
  const authHeader = request.headers.get('Authorization') ?? request.headers.get('authorization') ?? '';
  const token = authHeader.toLowerCase().startsWith('bearer ') ? authHeader.slice(7).trim() : '';
  if (!token) return json(401, { error: 'Sign in to delete your account.' });

  const anon = createClient(PUBLIC_SUPABASE_URL, PUBLIC_SUPABASE_ANON_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data, error: authError } = await anon.auth.getUser(token);
  const user = data?.user;
  if (authError || !user) return json(401, { error: 'Your session is invalid — sign in again.' });

  // 2. Require the explicit DELETE confirmation (case-sensitive), same gate as the web.
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return json(400, { error: 'Expected a JSON body.' });
  }
  const confirm = (body as { confirm?: unknown })?.confirm;
  if (confirm !== 'DELETE') {
    return json(400, { error: 'Type DELETE (all caps) to confirm.' });
  }

  // 3. Service-role delete (RLS can't delete auth.users rows). DB cascade does the cleanup.
  let admin: ReturnType<typeof createSupabaseAdminClient>;
  try {
    admin = createSupabaseAdminClient();
  } catch {
    return json(503, { error: 'Deletion is not configured on this deployment — contact the curator.' });
  }

  const { error: deleteError } = await admin.auth.admin.deleteUser(user.id);
  if (deleteError) {
    return json(500, { error: 'Could not delete your account — try again.' });
  }

  return json(200, { ok: true });
};
