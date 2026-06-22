/**
 * CSP inline-script hash auditor.
 *
 *   npm run build && node scripts/csp-hashes.mjs
 *
 * Scans the built HTML for every EXECUTABLE inline <script> (the ones CSP
 * `script-src` governs — `type="application/json"` and other data blocks are
 * excluded), computes the union of their sha256 hashes, and diffs it against
 * the CSP_INLINE_SCRIPT_HASHES list in src/layouts/Base.astro.
 *
 * Exits non-zero if the build contains a hash NOT in Base.astro (that hash
 * would be blocked in production — broken hydration). Run it after editing the
 * inline scripts or upgrading astro, then paste the printed list into Base.astro.
 */
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { execSync } from 'node:child_process';

const DIST = 'dist/client';
const BASE = 'src/layouts/Base.astro';

// Executable iff no src and type is empty / module / a JS mimetype.
const EXEC_TYPES = new Set(['', 'module', 'text/javascript', 'application/javascript']);
const isExec = (attrs) => {
  if (/\bsrc=/.test(attrs)) return false;
  const type = (attrs.match(/\btype\s*=\s*["']?([^"'\s>]*)/i)?.[1] || '').toLowerCase();
  return EXEC_TYPES.has(type);
};

let files;
try {
  files = execSync(`find ${DIST} -name "*.html"`, { encoding: 'utf8' }).trim().split('\n').filter(Boolean);
} catch {
  console.error(`No build found at ${DIST}/. Run \`npm run build\` first.`);
  process.exit(2);
}

const re = /<script\b([^>]*)>([\s\S]*?)<\/script>/gi;
const found = new Map(); // hash -> {count, sample}
for (const f of files) {
  const html = readFileSync(f, 'utf8');
  let m;
  while ((m = re.exec(html))) {
    const [, attrs, body] = m;
    if (!isExec(attrs) || body.trim() === '') continue;
    const hash = 'sha256-' + createHash('sha256').update(body, 'utf8').digest('base64');
    const e = found.get(hash) || { count: 0, sample: body.replace(/\s+/g, ' ').trim().slice(0, 60) };
    e.count++;
    found.set(hash, e);
  }
}

const listed = new Set([...readFileSync(BASE, 'utf8').matchAll(/'(sha256-[A-Za-z0-9+/=]+)'/g)].map((m) => m[1]));

console.log(`Built pages scanned: ${files.length}`);
console.log(`\nUnion of executable inline-script hashes (paste into ${BASE}):\n`);
for (const [hash, e] of found) {
  console.log(`  "'${hash}'", // ${listed.has(hash) ? 'ok' : 'NEW'} — ${e.count}/${files.length} pages — ${e.sample}`);
}

const missing = [...found.keys()].filter((h) => !listed.has(h));
const stale = [...listed].filter((h) => !found.has(h));
if (stale.length) console.log(`\nNote: ${stale.length} hash(es) listed in Base.astro no longer appear in the build (harmless, can prune).`);
if (missing.length) {
  console.error(`\n✗ ${missing.length} build hash(es) are MISSING from Base.astro — these would be blocked in production. Update CSP_INLINE_SCRIPT_HASHES.`);
  process.exit(1);
}
console.log(`\n✓ Base.astro CSP covers every executable inline script in the build.`);
