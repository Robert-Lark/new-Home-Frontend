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
    // Prerender static pages in Node, not workerd. Our pages are plain HTML
    // (no CF-runtime APIs at build time), and the workerd prerenderer collides
    // with the reserved 'ASSETS' binding in a Pages project.
    prerenderEnvironment: 'node',
  }),
  integrations: [
    // Preact powers the interactive islands ONLY (audio player, favorites,
    // upload form, post editor). Everything else ships zero JS.
    preact(),
  ],
  // Pre-bundle Supabase deterministically at startup. These are the first deps
  // pulled into a *client* island; letting Vite optimize them on-demand causes
  // a dep-reoptimization race that breaks island hydration in dev.
  vite: {
    optimizeDeps: {
      include: ['@supabase/ssr', '@supabase/supabase-js'],
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
