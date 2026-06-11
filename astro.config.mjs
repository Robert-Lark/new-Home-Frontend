// @ts-check
import { defineConfig, envField } from 'astro/config';
import cloudflare from '@astrojs/cloudflare';
import preact from '@astrojs/preact';

// HTML-first: static by default. Auth/upload routes opt into SSR per-page
// with `export const prerender = false`. We do NOT set output:'server'.
// https://docs.astro.build/en/guides/integrations-guide/cloudflare/
export default defineConfig({
  site: 'https://quietcast.art',
  // Astro 6's adapter uses @cloudflare/vite-plugin and auto-reads wrangler.toml,
  // so local binding access (R2, KV) works in `astro dev` with no extra config.
  adapter: cloudflare({
    // Prerender our static pages in Node instead of the default workerd
    // runtime — they're plain HTML with no Cloudflare-runtime APIs at build
    // time, so Node is the simpler, faster prerender path.
    prerenderEnvironment: 'node',
  }),
  integrations: [
    // Preact powers the interactive islands ONLY (audio player, favorites,
    // upload form, post editor). Everything else ships zero JS.
    preact(),
  ],
  // Pre-bundle every client dep that Vite cannot see in its initial scan.
  // Astro injects these imports at runtime (island hydration, ClientRouter),
  // so without `include` they are only discovered on the first browser visit,
  // which forces a mid-session re-optimization: the deps cache is rewritten
  // under a new hash and any page already loaded 404s on its island modules.
  vite: {
    optimizeDeps: {
      include: [
        '@supabase/ssr',
        '@supabase/supabase-js',
        // ClientRouter's client module (Base.astro) — injected, never scanned.
        'astro/virtual-modules/transitions.js',
        // Dev-only preact graph behind the islands' client-dev entrypoint.
        // @astrojs/preact pre-bundles the production entries but not these,
        // so whether they land in the initial scan is a race.
        'preact/debug',
        'preact/devtools',
        'preact/jsx-dev-runtime',
      ],
    },
    environments: {
      ssr: {
        optimizeDeps: {
          // Same problem in the workerd SSR environment (deps_ssr): these two
          // are discovered on the first render, which reloads the program and
          // aborts in-flight responses mid-stream.
          include: ['@astrojs/cloudflare/entrypoints/server', '@astrojs/preact/server.js'],
        },
      },
    },
  },
  // Astro 5 typed env — validated at build, satisfies the "Zod at the env
  // boundary" guardrail natively. Import from 'astro:env/client' (public,
  // inlined into the browser bundle) or 'astro:env/server' (secret/server).
  env: {
    schema: {
      // --- Supabase (auth + private user data) ---
      PUBLIC_SUPABASE_URL: envField.string({ context: 'client', access: 'public' }),
      PUBLIC_SUPABASE_ANON_KEY: envField.string({ context: 'client', access: 'public' }),
      SUPABASE_SERVICE_ROLE_KEY: envField.string({ context: 'server', access: 'secret', optional: true }),
      // One-owner site: moderation routes are gated on this email (locked
      // decision — a profiles.role column only if multi-moderator is needed).
      ADMIN_EMAIL: envField.string({ context: 'server', access: 'secret', optional: true }),

      // --- Sanity (public editorial CMS, project vcfngr79) ---
      PUBLIC_SANITY_PROJECT_ID: envField.string({ context: 'client', access: 'public', default: 'vcfngr79' }),
      PUBLIC_SANITY_DATASET: envField.string({ context: 'client', access: 'public', default: 'production' }),
      SANITY_API_TOKEN: envField.string({ context: 'server', access: 'secret', optional: true }),

      // --- R2 (audio — served via cdn.quietcast.art, zero egress) ---
      // S3-API creds are only needed for server-side presigned uploads (Phase 6)
      // and the bulk-upload tooling (Phase 3). Reads go through the CDN URL.
      PUBLIC_CDN_URL: envField.string({ context: 'client', access: 'public', default: 'https://cdn.quietcast.art' }),
      R2_ACCOUNT_ID: envField.string({ context: 'server', access: 'secret', optional: true }),
      R2_ACCESS_KEY_ID: envField.string({ context: 'server', access: 'secret', optional: true }),
      R2_SECRET_ACCESS_KEY: envField.string({ context: 'server', access: 'secret', optional: true }),
      R2_BUCKET: envField.string({ context: 'server', access: 'public', default: 'quietcast-audio' }),
    },
  },
});
