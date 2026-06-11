import type { APIRoute } from 'astro';
import type { EmailOtpType } from '@supabase/supabase-js';

export const prerender = false;

/**
 * Magic-link confirmation. Handles BOTH flows so it works with or without
 * custom SMTP:
 *
 *  - Default email template (PKCE): lands here with a `?code=`, exchanged via
 *    exchangeCodeForSession. (Requires same-browser — code verifier is local.)
 *  - Custom template (token_hash): verified with verifyOtp. Immune to the
 *    same-browser/verifier requirement.
 *
 * Forwards the real error to /login so failures are diagnosable instead of a
 * generic "expired".
 */
export const GET: APIRoute = async ({ url, locals, redirect }) => {
  const rawNext = url.searchParams.get('next') ?? '/dashboard';
  // Only same-site relative paths — never honor ?next=https://evil (open redirect).
  const next = rawNext.startsWith('/') && !rawNext.startsWith('//') ? rawNext : '/dashboard';
  const code = url.searchParams.get('code');
  const token_hash = url.searchParams.get('token_hash');
  const type = url.searchParams.get('type') as EmailOtpType | null;
  const provider_error = url.searchParams.get('error_description') ?? url.searchParams.get('error');

  console.log('[auth/confirm]', {
    hasCode: !!code,
    hasTokenHash: !!token_hash,
    type,
    provider_error,
  });

  if (provider_error) {
    return redirect(`/login?error=${encodeURIComponent(provider_error)}`);
  }

  if (code) {
    const { error } = await locals.supabase.auth.exchangeCodeForSession(code);
    if (!error) return redirect(next);
    console.error('[auth/confirm] exchangeCodeForSession failed:', error.message);
    return redirect(`/login?error=${encodeURIComponent(error.message)}`);
  }

  if (token_hash && type) {
    const { error } = await locals.supabase.auth.verifyOtp({ type, token_hash });
    if (!error) return redirect(next);
    console.error('[auth/confirm] verifyOtp failed:', error.message);
    return redirect(`/login?error=${encodeURIComponent(error.message)}`);
  }

  return redirect('/login?error=no-token');
};
