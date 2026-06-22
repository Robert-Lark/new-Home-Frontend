# Quiet Cast iOS contract — Auth, Settings, Account Deletion

Source of truth: the Astro web app at `front-end-astro/` (commit state of 2026-06-12).
Every fact below carries a `file:line` citation into that repo. The iOS app talks to the
SAME Supabase project and the same tables — nothing here is iOS-specific infrastructure.

---

## 1. Backend identity

| Item | Value | Source |
| --- | --- | --- |
| Supabase project URL | `https://zzftxvxgnkuowipeylen.supabase.co` | `.env:` `PUBLIC_SUPABASE_URL` (also `.env.example`) |
| Publishable (anon) key | `sb_publishable_7KYvjvCf_JN9r_jFuIGJWA_LAQmLgRh` | `.env:` `PUBLIC_SUPABASE_ANON_KEY` — browser-safe by design (`src/lib/supabase.ts:5-8`) |
| Service-role key env name | `SUPABASE_SERVICE_ROLE_KEY` (server-only secret, `sb_secret_…` format) | `astro.config.mjs:63`, `.env.example` ("secret" key) |
| Admin identity | `ADMIN_EMAIL` env var; admin = the one user whose email matches | `src/lib/supabase-admin.ts:14-18`, `astro.config.mjs:66` |
| R2 public CDN | `https://cdn.quietcast.art` (`PUBLIC_CDN_URL`, default in `astro.config.mjs:76`) | `src/lib/ugc.ts:34-36` |
| supabase-js version (web) | `@supabase/supabase-js ^2.45.0`, `@supabase/ssr ^0.6.0` | `package.json` |

The anon key is shipped in the web browser bundle (`src/lib/supabase.ts:3,22`), so embedding
it in the iOS binary is equivalent exposure. RLS is the security boundary, not key secrecy.

---

## 2. How the web app constructs its three Supabase clients

### 2.1 Browser client (islands) — `src/lib/supabase.ts:20-23`

```ts
let _browser: SupabaseClient | null = null;
export function createSupabaseBrowserClient(): SupabaseClient {
  return (_browser ??= createBrowserClient(PUBLIC_SUPABASE_URL, PUBLIC_SUPABASE_ANON_KEY));
}
```

Memoized singleton; anon key; RLS scopes everything (`src/lib/supabase.ts:5-13`).

### 2.2 Per-request SSR client (cookie sessions) — `src/lib/supabase-server.ts:12-28`

```ts
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
```

Sessions on the web live in **cookies** (set by `@supabase/ssr`). iOS will NOT use cookies —
the supabase-swift SDK stores the JWT access token + refresh token in its own keychain-backed
session store. Same `auth.users` rows, same JWTs, different transport.

### 2.3 Admin (service-role) client — `src/lib/supabase-admin.ts:14-25` (verbatim, full)

```ts
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
```

Imports: `SUPABASE_SERVICE_ROLE_KEY, ADMIN_EMAIL` from `'astro:env/server'`;
`PUBLIC_SUPABASE_URL` from `'astro:env/client'` (`src/lib/supabase-admin.ts:2-3`).
The service-role client bypasses RLS and is created only inside gated request handlers
(`src/lib/supabase-admin.ts:9-11`). **The iOS app must never embed this key** — account
deletion goes through a server endpoint (section 6).

---

## 3. Auth flow

### 3.1 Web flow today: email magic link

`src/pages/login.astro:7` redirects already-signed-in users to `/dashboard`
(`if (Astro.locals.user) return Astro.redirect('/dashboard');`). The form island sends the
link — `src/islands/LoginForm.tsx:17-24`:

```ts
const supabase = createSupabaseBrowserClient();
const { error } = await supabase.auth.signInWithOtp({
  email,
  options: {
    shouldCreateUser: true,
    emailRedirectTo: `${window.location.origin}/auth/confirm`,
  },
});
```

- `shouldCreateUser: true` — login and signup are the same flow; a new email creates an
  account (`src/islands/LoginForm.tsx:21`, copy at `login.astro:27`).
- Redirect target is `/auth/confirm` on the requesting origin (`LoginForm.tsx:22`).

### 3.2 The confirm endpoint — `src/pages/auth/confirm.ts:18-53`

`GET /auth/confirm` handles both Supabase email-link variants (`confirm.ts:6-17` explains):

```ts
if (code) {
  const { error } = await locals.supabase.auth.exchangeCodeForSession(code);
  if (!error) return redirect(next);
  ...
}

if (token_hash && type) {
  const { error } = await locals.supabase.auth.verifyOtp({ type, token_hash });
  if (!error) return redirect(next);
  ...
}

return redirect('/login?error=no-token');
```

- `?code=` → PKCE `exchangeCodeForSession` (same-browser only, code verifier is local) —
  `confirm.ts:10-12,38-43`.
- `?token_hash=&type=` → `verifyOtp({ type, token_hash })` (custom email template path) —
  `confirm.ts:45-50`.
- `next` is sanitized to same-site relative paths only: `rawNext.startsWith('/') &&
  !rawNext.startsWith('//')`, default `/dashboard` (`confirm.ts:19-21`).
- Provider errors (`?error_description=`/`?error=`) forward to `/login?error=…`
  (`confirm.ts:25,34-36`).

### 3.3 Sign-out — `src/pages/auth/signout.ts:5-8` (verbatim, full handler)

```ts
export const POST: APIRoute = async ({ locals, redirect }) => {
  await locals.supabase.auth.signOut();
  return redirect('/');
};
```

### 3.4 Session validation middleware — `src/middleware.ts:12-24` (verbatim)

```ts
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
```

Deliberate choice documented at `middleware.ts:9-10`: `getUser()` (validates the JWT against
the auth server) — never `getSession()` (trusts the cookie blindly). The iOS-facing rule is
the same: any server endpoint must validate tokens with `auth.getUser(jwt)`, not decode-and-trust.

`Astro.locals` typing: `src/env.d.ts:3-8` — `locals.supabase: SupabaseClient`,
`locals.user: User | null`.

### 3.5 iOS flow: email OTP code (same endpoint family, same users)

`signInWithOtp` is one GoTrue endpoint (`POST /auth/v1/otp`); the magic link and the 6-digit
code are two presentations of the same OTP. The iOS app uses supabase-swift:

1. `signInWithOTP(email:, shouldCreateUser: true)` — identical semantics to
   `LoginForm.tsx:18-24` minus `emailRedirectTo` (no redirect needed; the user types the code).
2. `verifyOTP(email:, token: <6-digit code>, type: .email)` — returns a session
   (access + refresh token) for the **same `auth.users` row** the web flow would create.
   The `handle_new_user` trigger (section 4.1) fires identically regardless of client.

**Do `/auth/confirm`, `/auth/signout`, `/login` matter for iOS? No.**
- `/auth/confirm` exists to turn a clicked email link into a browser cookie session
  (`confirm.ts:6-17`). With in-app code entry, `verifyOtp` establishes the session directly
  in the SDK; there is no redirect, no PKCE verifier, no cookie to set.
- `/auth/signout` exists to clear the cookie session; iOS calls the SDK's `signOut()` locally.
- One web-side coupling to know: the web client uses PKCE (`?code=` branch,
  `confirm.ts:38-43`), so links from emails requested **by the web** only work in the
  requesting browser. Irrelevant to iOS code entry.

**Dashboard config caveat (not verifiable from this repo — from training data, unverified):**
the Supabase "Magic Link" email template must contain `{{ .Token }}` for the 6-digit code to
appear in the email; the default template ships only the `{{ .ConfirmationURL }}` link. The
repo's `confirm.ts:7-13` comment ("works with or without custom SMTP… custom template
(token_hash)") implies the template may already be customized — verify in the Supabase
dashboard (Auth → Email Templates) before relying on code entry.

---

## 4. Tables behind auth + settings

### 4.1 `profiles` — world-readable; auto-created on signup

`supabase/migrations/0001_init.sql:10-28` (verbatim):

```sql
create table if not exists public.profiles (
  id           uuid primary key references auth.users (id) on delete cascade,
  display_name text,
  avatar_url   text,
  created_at   timestamptz not null default now()
);
alter table public.profiles enable row level security;

drop policy if exists "profiles_select_all" on public.profiles;
create policy "profiles_select_all" on public.profiles
  for select using (true);

drop policy if exists "profiles_insert_own" on public.profiles;
create policy "profiles_insert_own" on public.profiles
  for insert with check (auth.uid() = id);

drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own" on public.profiles
  for update using (auth.uid() = id) with check (auth.uid() = id);
```

Signup trigger — `0001_init.sql:32-50` (verbatim):

```sql
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = ''
as $$
begin
  insert into public.profiles (id, display_name)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'display_name', split_part(new.email, '@', 1))
  );
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();
```

iOS implication: after `verifyOTP` succeeds for a brand-new user, a `profiles` row already
exists with `display_name` defaulted to the email local-part. No client-side bootstrap insert
needed for `profiles`.

### 4.2 `profile_details` — privacy-sensitive 1:1 row, created lazily by upsert

`supabase/migrations/0003_profile.sql:13-37` (verbatim):

```sql
create table if not exists public.profile_details (
  id               uuid primary key references auth.users (id) on delete cascade,
  is_public        boolean not null default false,
  bio              text,
  status_line      text,
  -- content_ref of the profile song: an episode slug or a published
  -- user_uploads id (same convention as favorites.content_ref).
  profile_song_ref text,
  -- Stored now, applied when light mode ships.
  theme            text not null default 'dark' check (theme in ('dark', 'light')),
  updated_at       timestamptz not null default now()
);
alter table public.profile_details enable row level security;

drop policy if exists "details_select_public_or_own" on public.profile_details;
create policy "details_select_public_or_own" on public.profile_details
  for select using (is_public or auth.uid() = id);

drop policy if exists "details_insert_own" on public.profile_details;
create policy "details_insert_own" on public.profile_details
  for insert with check (auth.uid() = id);

drop policy if exists "details_update_own" on public.profile_details;
create policy "details_update_own" on public.profile_details
  for update using (auth.uid() = id) with check (auth.uid() = id);
```

The row may not exist for a user until their first settings save — all reads must tolerate
null (web uses `maybeSingle()`, `src/lib/profile.ts:104-115`). TypeScript shape the web uses
(`src/lib/profile.ts:22-28`):

```ts
export interface ProfileDetails {
  is_public: boolean;
  bio: string | null;
  status_line: string | null;
  profile_song_ref: string | null;
  theme: 'dark' | 'light';
}
```

---

## 5. Settings surface (`src/pages/settings.astro`)

SSR page (`settings.astro:2` `export const prerender = false;`), gated at
`settings.astro:16-17`:

```ts
const user = Astro.locals.user;
if (!user) return Astro.redirect('/login');
```

All writes are plain `POST` back to the page with a hidden `action` field
(`settings.astro:10-15`); all use the RLS-scoped `locals.supabase` except account deletion.
The shared upsert helper — `settings.astro:37-42` (verbatim):

```ts
async function upsertDetails(fields: Record<string, unknown>): Promise<boolean> {
  const { error } = await supabase
    .from('profile_details')
    .upsert({ id: user!.id, ...fields, updated_at: new Date().toISOString() });
  return !error;
}
```

### 5.1 `action=save-profile` — `settings.astro:48-72`

Validation (`settings.astro:49-56`):

```ts
const displayName = String(form.get('display_name') ?? '').trim().slice(0, 60);
const statusLine = String(form.get('status_line') ?? '').trim().slice(0, 140);
const bio = String(form.get('bio') ?? '').trim().slice(0, 2000);
const songRef = String(form.get('profile_song_ref') ?? '').trim();
if (!displayName) {
  result = { ok: false, scope: 'profile', message: 'A display name is required.' };
} else if (songRef && !epByRef.has(songRef) && !myMixIds.has(songRef)) {
  result = { ok: false, scope: 'profile', message: 'That profile signal is not available.' };
}
```

| Field | Limit | Written to | Empty → |
| --- | --- | --- | --- |
| display name | trim, max 60, **required** | `profiles.display_name` (UPDATE, `settings.astro:58-61`) | error |
| status line | trim, max 140 | `profile_details.status_line` | `null` |
| bio | trim, max 2000 | `profile_details.bio` | `null` |
| profile song ref | must be a Sanity episode slug OR one of the user's **published** `user_uploads` ids | `profile_details.profile_song_ref` | `null` |

The HTML enforces the same limits client-side (`maxlength="60"` `settings.astro:177`,
`maxlength="140"` `:188`, `maxlength="2000"` `:192`). Server truncates rather than rejects.
`profile_song_ref` validation source set: episode slugs from Sanity (`getEpisodes()`,
`settings.astro:20-21`) plus the user's own `user_uploads` rows with `status = 'published'`
(`settings.astro:25-33`) — published-only because a private mix as profile song would leak
private audio (`settings.astro:23-24`).

The two writes (`settings.astro:58-68`):

```ts
const { error } = await supabase
  .from('profiles')
  .update({ display_name: displayName })
  .eq('id', user.id);
const ok =
  !error &&
  (await upsertDetails({
    status_line: statusLine || null,
    bio: bio || null,
    profile_song_ref: songRef || null,
  }));
```

### 5.2 `action=save-avatar` — `settings.astro:73-108`

Accepted types: `IMAGE_TYPES` = `image/jpeg → jpg`, `image/png → png`, `image/webp → webp`
(`src/lib/ugc.ts:27-31`); max `IMAGE_MAX_BYTES` = `10 * 1024 * 1024` (`ugc.ts:15`).
Key shape and write (`settings.astro:91-103`):

```ts
const key = `user/${user.id}/avatar/${crypto.randomUUID()}.${IMAGE_TYPES[file.type]}`;
const put = await fetch(await presignR2Put(key), {
  method: 'PUT',
  headers: { 'Content-Type': file.type },
  body: await file.arrayBuffer(),
});
...
const { error } = await supabase
  .from('profiles')
  .update({ avatar_url: cdnUrl(key) })
  .eq('id', user.id);
```

`avatar_url` stores the **full CDN URL** (`cdnUrl(key)` = `https://cdn.quietcast.art/<key>`,
`ugc.ts:34-36`), not the bare key. Replaced avatars orphan the old R2 object
(`settings.astro:89-90`). For iOS, the upload path is the presign endpoint (section 7) —
note however that `kind` there is `'mix' | 'cover' | 'photo'` only; the avatar presign
happens inline in settings.astro, so a new endpoint or an extended `kind` enum is needed
for iOS avatar upload.

### 5.3 `action=save-privacy` — `settings.astro:109-113`

```ts
const ok = await upsertDetails({ is_public: form.get('visibility') === 'public' });
```

Single boolean `profile_details.is_public`. Default (no row) is private
(`is_public` default `false`, `0003_profile.sql:15`; UI checks `!details?.is_public` as
private, `settings.astro:250`). Public means `/u/<id>` is visible to anyone; private hides
profile_details, connections, and wall via the RLS in section 4.2.

### 5.4 `action=save-prefs` (theme) — `settings.astro:114-119`

```ts
const theme = form.get('theme') === 'light' ? 'light' : 'dark';
const ok = await upsertDetails({ theme });
```

Anything that isn't exactly `'light'` is coerced to `'dark'`. Stored in
`profile_details.theme` (check constraint `('dark', 'light')`, `0003_profile.sql:22`).

**How theme sync works (web)** — `src/layouts/Base.astro:52-79`, pre-paint inline script
(verbatim):

```html
<script is:inline data-qc-theme-pin data-server-theme={theme ?? ''}>
  (() => {
    const apply = (t) => {
      const theme = t === 'light' ? 'light' : 'dark';
      document.documentElement.setAttribute('data-theme', theme);
      const meta = document.querySelector('meta[name="color-scheme"]');
      if (meta) meta.setAttribute('content', theme);
    };
    const resolve = () => {
      const pin = document.querySelector('script[data-qc-theme-pin]');
      const server = pin?.getAttribute('data-server-theme');
      try {
        if (server === 'light' || server === 'dark') {
          localStorage.setItem('qc-theme', server);
          return server;
        }
        return localStorage.getItem('qc-theme');
      } catch {
        return server || 'dark'; // storage blocked — stay dark
      }
    };
    apply(resolve());
    if (!window.qcThemePinned) {
      window.qcThemePinned = true;
      document.addEventListener('astro:after-swap', () => apply(resolve()));
    }
  })();
</script>
```

Semantics: `profile_details.theme` is **authoritative when present**; only `/dashboard` and
`/settings` pass it server-side (`dashboard.astro:235`, `settings.astro:154` —
`theme={details?.theme ?? null}`), and the pin script re-seeds the `qc-theme` localStorage
key from it (`Base.astro:12-16` comment: "Authoritative when present: the pin script
re-seeds localStorage from it"). All other (static) pages read only localStorage. Dark is
the house default (`Base.astro:55,70`).

**iOS rule:** read `profile_details.theme` as the saved preference; write it via the same
upsert shape. A theme changed on iOS propagates to the web the next time the user loads
`/dashboard` or `/settings` (which re-pins localStorage). There is no realtime sync.

### 5.5 Result rendering

Every action sets `result: { ok: boolean; scope: string; message: string }`
(`settings.astro:35`) with scopes `'profile' | 'avatar' | 'privacy' | 'prefs' | 'delete'`;
the page re-reads `profiles` + `profile_details` after writes (`settings.astro:148-151`).
Failure message for missing migration: `'Could not save — has the 0003 migration run?'`
(`settings.astro:71,113,119`).

---

## 6. Account deletion — the template for `POST /api/account/delete`

Current web flow, `settings.astro:120-145` (verbatim):

```ts
} else if (action === 'delete-account') {
    if (String(form.get('confirm') ?? '') !== 'DELETE') {
      result = { ok: false, scope: 'delete', message: 'Type DELETE (all caps) to confirm.' };
    } else {
      try {
        // Service-role: auth.users rows aren't deletable under RLS. Every
        // user table cascades from auth.users; R2 objects under user/<uid>/
        // are left for a manual cleanup pass (no delete helper in r2.ts yet).
        const admin = createSupabaseAdminClient();
        const { error } = await admin.auth.admin.deleteUser(user.id);
        if (error) throw error;
        try {
          await supabase.auth.signOut();
        } catch {
          /* session is already dead — cookies just expire */
        }
        return Astro.redirect('/');
      } catch {
        result = {
          ok: false,
          scope: 'delete',
          message: 'Deletion is not configured on this deployment — contact the curator.',
        };
      }
    }
  }
```

Exact contract:

1. **Confirmation gate:** the literal string `DELETE` (case-sensitive) must be supplied
   (`settings.astro:121`). Error copy: `'Type DELETE (all caps) to confirm.'`
2. **One admin call does all DB cleanup:** `admin.auth.admin.deleteUser(user.id)`
   (`settings.astro:129`). No per-table deletes — every user table has
   `references auth.users (id) on delete cascade`, verified across all migrations:
   - Direct cascades from `auth.users`: `profiles` (`0001:11`), `favorites` (`0001:58`),
     `listen_status` (`0001:74`), `user_uploads` (`0001:93`), `posts` (`0001:129`),
     `playlists` (`0001:161`), `blocks` (both columns, `0001:229-230`), `messages` (both
     columns, `0001:253-254`), `reports` (`0001:292`), `lists` (`0002_ugc.sql:64`),
     `photo_albums` (`0002_ugc.sql:140`), `profile_details` (`0003:14`), `connections`
     (`0003:46`), `wall_comments` (both `profile_id` and `author_id`, `0004_wall.sql:12-13`).
   - Second-level cascades through parents: `playlist_items` → `playlists`
     (`0001:187`), `list_items` → `lists` (`0002:93` `references public.lists (id) on
     delete cascade`), `photos` → `photo_albums` (`0002:174`).
3. **R2 objects are NOT cleaned.** Everything under the `user/<uid>/` prefix (avatar, mix
   audio, covers, photos) is orphaned, by explicit decision (`settings.astro:125-127`
   comment; `r2.ts` has no delete helper — it only exports `r2Configured` and
   `presignR2Put`, `src/lib/r2.ts:51-106`). An iOS-era endpoint may add R2 cleanup, but the
   current contract is: DB only.
4. **Order:** admin delete first; then best-effort `signOut()` whose failure is swallowed
   (the session is already invalid once the user row is gone, `settings.astro:131-135`);
   then redirect `/`.
5. **Failure mode:** any throw (including unconfigured `SUPABASE_SERVICE_ROLE_KEY`, which
   makes `createSupabaseAdminClient()` throw, `supabase-admin.ts:21`) collapses to the
   single message `'Deletion is not configured on this deployment — contact the curator.'`

User-facing description of what deletion removes (`settings.astro:287-290`): "This removes
your profile, favorites, playlists, listening history, rotation, and unpublished
submissions — permanently. Published contributions are removed with them."

For the new `POST /api/account/delete` (iOS-facing) the deltas vs. this template are:
auth must come from a `Authorization: Bearer <access_token>` header instead of cookies
(section 7.3), the `DELETE` confirmation arrives as JSON, and the response is JSON instead
of a redirect. The deletion mechanics (admin client + `deleteUser` + cascade reliance)
stay identical.

---

## 7. Astro API route anatomy (the pattern for any new endpoint)

Reference implementation: `src/pages/api/uploads/sign.ts` — the only existing
`src/pages/api/*` route (directory contains exactly `uploads/sign.ts`).

### 7.1 Shape — `sign.ts:1,29-38`

```ts
export const prerender = false;

import type { APIRoute } from 'astro';
...
function json(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

export const POST: APIRoute = async ({ locals, request }) => {
  const user = locals.user;
  if (!user) return json(401, { error: 'Sign in to upload.' });
```

- `export const prerender = false` is mandatory — the site is static-by-default
  (`astro.config.mjs:6-8`: "We do NOT set output:'server'"); routes opt into SSR per-file.
- Handlers are named HTTP-method exports typed `APIRoute`, destructure `{ locals, request }`.
- Body parsing: `await request.json()` in try/catch → 400 `{ error: 'Expected a JSON body.' }`
  (`sign.ts:41-46`); then a zod `safeParse` (`sign.ts:23-27,47-48`).
- Error body convention: `{ error: string }` with statuses seen in the file: 401, 503, 400,
  415, 413, 429, 200 (`sign.ts:38-79`).

### 7.2 Runtime env access: `astro:env`, NOT `locals.runtime.env`

This project uses Astro 5 typed env exclusively — schema in `astro.config.mjs:58-81`
(`envField.string({ context: 'server', access: 'secret', … })` etc.), imported as
`import { … } from 'astro:env/server'` (e.g. `supabase-admin.ts:2`, `r2.ts:1-6`) or
`'astro:env/client'`. A grep for `runtime` across `src/` returns **zero matches** — no file
uses the `@astrojs/cloudflare` `locals.runtime?.env` pattern. Secrets are set as Worker
env vars/secrets in the Cloudflare dashboard and `.dev.vars` locally; the two `PUBLIC_*`
Supabase vars must exist at **build** time because `astro:env` validates and inlines them
(`wrangler.toml` comment block, "Secrets/bindings…"). Adapter: `@astrojs/cloudflare ^13.7.0`
building a Worker (`wrangler.toml` header comments; `astro.config.mjs:13-18`).

### 7.3 Auth in API routes — and the gap iOS exposes

Today `locals.user` is populated by the middleware **from cookies only**
(`middleware.ts:15-21` → `supabase-server.ts:15` parses the `Cookie` header). An iOS client
has no cookie jar wired to `@supabase/ssr` cookie names, so for any new iOS-facing endpoint
(e.g. `/api/account/delete`) the handler must additionally accept
`Authorization: Bearer <supabase access token>` and validate it server-side — e.g.
`createClient(url, anonKey).auth.getUser(jwt)` — following the same "validate, never trust"
rule the middleware documents (`middleware.ts:9-10`). This is new code; nothing in the repo
reads the Authorization header today (the existing islands authenticate to `/api/uploads/sign`
implicitly via cookies — `MixUploadForm.tsx:62` and `PhotoUploadForm.tsx:50` only call
`auth.getSession()` locally).

---

## 8. Quick iOS implementation checklist

1. Configure supabase-swift with the URL + publishable key from section 1.
2. Login screen: email field → `signInWithOTP(email:, shouldCreateUser: true)` → code field →
   `verifyOTP(email:, token:, type: .email)`. Verify the email template contains
   `{{ .Token }}` (section 3.5 caveat).
3. On first session: `profiles` row already exists (trigger, section 4.1);
   `profile_details` may be absent — treat as `{ is_public: false, theme: 'dark' }` defaults.
4. Settings reads: `profiles.select('id, display_name, avatar_url, created_at')` and
   `profile_details.select('is_public, bio, status_line, profile_song_ref, theme')`, both
   `.eq('id', uid).maybeSingle()`-equivalent (`profile.ts:97-115`).
5. Settings writes: mirror section 5 exactly — `profiles.update({display_name})` and the
   `profile_details` upsert with `id` + `updated_at` (ISO-8601 string) always included.
   Apply the same trims/length caps client-side (60/140/2000).
6. Theme: store/read `profile_details.theme`; no push sync to web (section 5.4).
7. Account deletion: call the (to-be-built) `POST /api/account/delete` with Bearer auth and
   the `DELETE` confirmation; never embed the service-role key (sections 6, 7.3).
8. Ignore `/auth/confirm`, `/auth/signout`, `/login` — cookie-web plumbing only (section 3.5).
