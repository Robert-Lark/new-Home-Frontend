# Handoff — Profile picture uploads & R2 / CDN

**Last updated:** 2026-06-22 · **Branch:** `rebuild` · **PR:** [#1](https://github.com/Robert-Lark/new-Home-Frontend/pull/1)

Paused mid-investigation. This is the pickup point for the profile-picture upload feature.

## TL;DR

The upload pipeline **works end-to-end** — file → presigned PUT → R2 → `avatar_url` saved (verified the object lands in the bucket). Pictures **don't display** because the public-read host `cdn.quietcast.art` is **not connected to the R2 bucket**: it currently resolves to Vercel and returns `404 DEPLOYMENT_NOT_FOUND`, so every `<img src={avatar_url}>` (and any R2 audio read) 404s.

**No app code is wrong for this.** What's left is a DNS/infra decision — see [Next steps](#next-steps).

## Current state

| Piece | State | Notes |
|---|---|---|
| Upload gate `r2Configured()` | ✅ passes locally | needs the 3 R2 secrets present **at runtime** |
| Presign + PUT to R2 | ✅ works | hand-rolled SigV4, `src/lib/r2.ts` |
| `avatar_url` persisted | ✅ works | stored **absolute**: `https://cdn.quietcast.art/<key>` |
| Object in bucket | ✅ verified | e.g. `user/<uid>/avatar/<uuid>.jpg` present in `quietcast-audio` |
| Image displays | ❌ broken | `cdn.quietcast.art` → Vercel 404, not R2 |

## Local dev setup (IMPORTANT — gitignored, not in this PR)

The Cloudflare adapter runs the app in workerd locally and **reads server secrets from `.dev.vars`, not `.env`** (startup log: `Using secrets defined in .dev.vars`; also documented in `wrangler.toml`). `astro:env/server` secrets do **not** resolve from `.env` at runtime here.

To run uploads locally, put **your own** R2 S3-API creds in **both** files (both are gitignored — `.env` for build-time/PUBLIC vars, `.dev.vars` for the runtime worker):

```
R2_ACCOUNT_ID=...
R2_ACCESS_KEY_ID=...
R2_SECRET_ACCESS_KEY=...
```

Generate at **Cloudflare → R2 → Manage R2 API Tokens** (Account API token, *Object Read & Write*). `R2_ACCOUNT_ID` is the hex subdomain in the bucket's S3 endpoint. **Restart `npm run dev`** after editing — env is read only at startup.

## The blocker: `cdn.quietcast.art` is not wired to R2

Evidence (re-confirmed 2026-06-22):

- `curl -I https://cdn.quietcast.art/<key>` → `HTTP/2 404`, `server: Vercel`, `x-vercel-error: DEPLOYMENT_NOT_FOUND`
- `dig cdn.quietcast.art` → `64.29.17.65` / `216.198.79.x` (Vercel Anycast)
- `dig NS quietcast.art` → `ns1/ns2.vercel-dns.com` (the whole zone is on Vercel DNS)
- The bucket + app live on **Cloudflare**; the R2 public custom domain was never connected.

`PUBLIC_CDN_URL=https://cdn.quietcast.art` (`.env`) feeds `cdnUrl()` (`src/lib/ugc.ts:34`), whose output is stored absolute in `profiles.avatar_url`. The code is correct — the hostname just doesn't serve the bucket.

### Registrar vs DNS (the `.art` question)

Cloudflare **Registrar** does not sell/transfer `.art` (confirmed against their TLD list) — but that's a separate capability from DNS/R2:

- Any domain whose TLD is on the **Public Suffix List** can use **Cloudflare DNS** without being registered at Cloudflare (`.art` is an ICANN gTLD → eligible).
- R2 custom domains only require the domain be a **zone in the same Cloudflare account** → satisfied by the **free full setup** (nameserver change).
- Keeping DNS on Vercel *and* serving R2 on `cdn.quietcast.art` would need a **partial (CNAME) setup = Business plan** (~$200/mo).

## Next steps

Three options, pick per appetite for DNS work:

**A — Connect `cdn.quietcast.art` to R2 (fixes prod + local).**
1. Add `quietcast.art` to Cloudflare (free), let it import existing DNS records, then switch nameservers Vercel → Cloudflare. Registration stays put at the current registrar.
2. R2 → `quietcast-audio` → Settings → Custom Domains → connect `cdn.quietcast.art` (public).
- The already-uploaded avatar loads with **no re-upload** (object is already in R2). Aligns with the app, which already targets the Cloudflare adapter.
- Tradeoff: Cloudflare becomes authoritative for the whole zone — verify imported records. The apex currently 404s on Vercel, so nothing live is at risk.

**B — Local-only quick view (no DNS change).**
1. R2 → bucket → enable the `pub-*.r2.dev` public URL.
2. Set `PUBLIC_CDN_URL=https://pub-<hash>.r2.dev` in `.env` (+ `.dev.vars`), restart, re-upload.
- Tradeoff: project rule says never use r2.dev in prod (rate-limited); it also bakes r2.dev URLs into stored `avatar_url` rows.

**C — Serve images through the app (keeps DNS on Vercel; code change).**
Add an Astro route that streams objects from the `AUDIO` R2 binding (`wrangler.toml`) and store relative URLs instead of `cdn.quietcast.art`.
- Tradeoff: more code; changes the stored-URL contract; read traffic flows through the worker.

## Key files

| Path | What |
|---|---|
| `src/pages/settings.astro:73-108` | avatar form handler: gate → PUT → save `avatar_url` |
| `src/pages/settings.astro:85-86` | `!r2Configured()` → "Uploads are not configured on this deployment yet." |
| `src/pages/settings.astro:231-232` | `<img src={profile.avatar_url}>` — the broken render |
| `src/lib/r2.ts:51-53` | `r2Configured()` — true only if all 3 secrets set |
| `src/lib/r2.ts:60-106` | `presignR2Put()` SigV4; uses `<account>.r2.cloudflarestorage.com` (default endpoint, not custom domain) |
| `src/lib/ugc.ts:34-35` | `cdnUrl()` → `PUBLIC_CDN_URL + key` |
| `src/pages/api/uploads/sign.ts:39` | same gate for mix/cover/photo direct-to-R2 uploads |
| `astro.config.mjs:77-80` | R2 env fields — secrets are `optional:true`, so unset → `undefined` (no build error) |
| `wrangler.toml` | R2 `AUDIO` binding + note that secrets live in `.dev.vars` / dashboard |

## Useful commands

```bash
# List avatar objects in R2. The aws CLI (Python) needs the corporate CA bundle,
# or TLS fails with "self signed certificate in certificate chain":
set -a; . .env; set +a
AWS_CA_BUNDLE=.certs/ca.pem AWS_ACCESS_KEY_ID="$R2_ACCESS_KEY_ID" \
  AWS_SECRET_ACCESS_KEY="$R2_SECRET_ACCESS_KEY" AWS_DEFAULT_REGION=auto \
  aws s3api list-objects-v2 --endpoint-url "https://$R2_ACCOUNT_ID.r2.cloudflarestorage.com" \
  --bucket "$R2_BUCKET" --prefix user/ --query 'Contents[?contains(Key,`avatar`)].Key'

# Confirm the CDN host state (expect Vercel 404 until option A is done):
curl -sI https://cdn.quietcast.art/ ; dig +short NS quietcast.art
```

## References (Cloudflare docs, fetched 2026-06-13)

- Onboard a domain (DNS works for any PSL TLD; no Cloudflare registration needed): https://developers.cloudflare.com/fundamentals/manage-domains/add-site/
- R2 public buckets / custom domains: https://developers.cloudflare.com/r2/buckets/public-buckets/
- Partial (CNAME) setup requires Business/Enterprise: https://developers.cloudflare.com/dns/zone-setups/partial-setup/
- Registrar TLD list (no `.art`): https://www.cloudflare.com/tld-policies/
