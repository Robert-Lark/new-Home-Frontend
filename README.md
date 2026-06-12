# Quiet Cast — front-end (Astro)

HTML-first relaunch of [quietcast.art](https://quietcast.art). Replaces the legacy
Gatsby app in `../front-end/` (kept as salvage reference until cutover).

## Stack

| Concern              | Tech                                                          |
| -------------------- | ------------------------------------------------------------- |
| Framework            | **Astro 5** (static by default; SSR per-route via adapter)    |
| Host                 | **Cloudflare Pages** (`@astrojs/cloudflare`)                  |
| Islands              | **Preact** — audio player, favorites, upload form, post editor |
| Navigation           | Astro `<ClientRouter />` + `transition:persist` (audio survives nav) |
| Audio                | **Cloudflare R2** via `cdn.quietcast.art` (zero egress)       |
| Auth + private data  | **Supabase** (Postgres + Auth, RLS)                           |
| Editorial CMS        | **Sanity** (project `vcfngr79`)                               |
| Video                | YouTube / Vimeo embeds                                        |

Guiding principle: **HTML → CSS → JS, in that order.** No site-wide SPA framework;
interactive islands only where needed.

## Commands

| Command           | Action                                              |
| ----------------- | --------------------------------------------------- |
| `npm install`     | Install deps (corporate proxy: add `--registry=https://registry.npmjs.org/`) |
| `npm run dev`     | Dev server at `localhost:4321`                      |
| `npm run check`   | `astro check` — type + diagnostics                  |
| `npm run build`   | Production build to `./dist`                         |
| `npm run preview` | Serve the built site via `wrangler pages dev`        |

## Environment

Copy `.env.example` → `.env` and fill in. `PUBLIC_*` vars are inlined into the
browser bundle (no secrets there). Env is typed + validated via Astro's
`astro:env` (see `astro.config.mjs`). For deployed previews/prod, set the same
vars as Pages environment variables in the Cloudflare dashboard; for local
binding access (R2) use `.dev.vars`.

## Layout

```
src/
  layouts/Base.astro      shell: head, fonts, nav, ClientRouter, persistent dock
  pages/                  routes (static unless `export const prerender = false`)
  components/             static .astro components
  islands/                Preact interactive islands (hydrated on demand)
  lib/
    sanity.ts             public read client (editorial)
    supabase.ts           browser client factory (RLS-backed islands)
  styles/
    tokens.css            design tokens — source of truth ("Cold Ember / Granite Liturgy")
    global.css            chrome, fog, dock, view transitions
public/images/            reference cover art (temporary; real art comes from Sanity)
studio/                   Sanity Content Studio — schemas + config (see Studio below)
```

## Studio (Sanity CMS)

The editorial CMS lives in `studio/` (folded in from the retired
[new-Home-Backend](https://github.com/Robert-Lark/new-Home-Backend) repo).
Studio schemas and the GROQ projections in `src/lib/content.ts` must change
together — that's why they share a repo.

- Run locally: `cd studio && npm install && npm start` (Sanity v2 studio;
  upgrade to a `sanity.config.ts` studio is planned with the Phase 3
  content remodel)
- Deploy: `cd studio && npx sanity deploy` — manual, independent of the
  Cloudflare build
- Cloudflare Workers Builds should skip studio-only commits: in the
  dashboard under **Settings → Build → Build watch paths**, exclude
  `studio/*` (one-time manual step)

## Design

Direction: **A (Fog Minimal) shell + C calendar ledger for Archive + B industrial
accent texture.** The one law: exactly one warm accent per view. Tokens live in
`src/styles/tokens.css`; full design rationale in the project plan.
