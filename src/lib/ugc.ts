import { PUBLIC_CDN_URL } from 'astro:env/client';
import type { SupabaseClient } from '@supabase/supabase-js';

/**
 * Shared user-generated-content rules: upload caps, the safe markdown subset
 * for posts, and small display helpers. Imported by islands too, so keep this
 * module dependency-free (the zod presign schema lives in /api/uploads/sign).
 * Caps are enforced server-side in /api/uploads/sign — the island checks are
 * UX only.
 */

/** Plan default (to confirm with owner): mixes ≤ 250MB, mp3/m4a. */
export const MIX_MAX_BYTES = 250 * 1024 * 1024;
/** Covers + concert photos ≤ 10MB, JPG/PNG/WebP. */
export const IMAGE_MAX_BYTES = 10 * 1024 * 1024;
/** Max photos per album upload. */
export const ALBUM_MAX_PHOTOS = 24;
/** Abuse brake: refuse new pieces once this many were created in the trailing 24h. */
export const MAX_CREATED_PER_DAY = 20;

export const AUDIO_TYPES: Record<string, string> = {
  'audio/mpeg': 'mp3',
  'audio/mp4': 'm4a',
  'audio/x-m4a': 'm4a',
};

export const IMAGE_TYPES: Record<string, string> = {
  'image/jpeg': 'jpg',
  'image/png': 'png',
  'image/webp': 'webp',
};

/** Public read URL for an R2 object (zero-egress custom domain). */
export function cdnUrl(key: string): string {
  return `${PUBLIC_CDN_URL.replace(/\/$/, '')}/${key}`;
}

export const LIST_ITEM_TYPES = ['record', 'artist', 'label', 'show', 'other'] as const;
export type ListItemType = (typeof LIST_ITEM_TYPES)[number];

/* ---------------------------------------------------------------------------
 * Markdown — a deliberately tiny, view-source-friendly subset.
 * Input is HTML-escaped FIRST, then formatted, so there is no raw-HTML XSS
 * surface and no sanitizer dependency. Supported: # / ## headings, **bold**,
 * *italic*, [text](https://…) links, "- " lists, "> " blockquotes, paragraphs.
 * ------------------------------------------------------------------------- */

function escapeHtml(s: string): string {
  return s
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function inline(s: string): string {
  return s
    .replace(/\[([^\]]+)\]\((https?:\/\/[^\s)]+)\)/g, (_, text: string, href: string) => {
      return `<a href="${href}" rel="nofollow noopener ugc" target="_blank">${text}</a>`;
    })
    .replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>')
    .replace(/\*([^*]+)\*/g, '<em>$1</em>');
}

/** Render the markdown subset to HTML. Safe for set:html. */
export function renderMarkdown(md: string): string {
  const blocks = escapeHtml(md.replace(/\r\n/g, '\n')).split(/\n{2,}/);
  const html: string[] = [];

  for (const block of blocks) {
    const lines = block.split('\n').filter((l) => l.trim() !== '');
    if (lines.length === 0) continue;

    if (lines.every((l) => l.startsWith('- '))) {
      html.push(`<ul>${lines.map((l) => `<li>${inline(l.slice(2).trim())}</li>`).join('')}</ul>`);
    } else if (lines.every((l) => l.startsWith('&gt;'))) {
      const quoted = lines.map((l) => inline(l.replace(/^&gt;\s?/, '').trim())).join('<br>');
      html.push(`<blockquote>${quoted}</blockquote>`);
    } else if (lines.length === 1 && lines[0]?.startsWith('## ')) {
      html.push(`<h3>${inline(lines[0].slice(3).trim())}</h3>`);
    } else if (lines.length === 1 && lines[0]?.startsWith('# ')) {
      html.push(`<h2>${inline(lines[0].slice(2).trim())}</h2>`);
    } else {
      html.push(`<p>${lines.map(inline).join('<br>')}</p>`);
    }
  }
  return html.join('\n');
}

/* ---------------------------------------------------------------------------
 * Display helpers
 * ------------------------------------------------------------------------- */

/**
 * Author display names for a set of user ids. Separate query because the UGC
 * tables FK auth.users (not exposed to PostgREST), so resource embedding
 * can't join profiles directly.
 */
export async function displayNames(
  supabase: SupabaseClient,
  userIds: string[],
): Promise<Map<string, string>> {
  const ids = [...new Set(userIds)];
  const names = new Map<string, string>();
  if (ids.length === 0) return names;
  const { data } = await supabase.from('profiles').select('id, display_name').in('id', ids);
  for (const row of data ?? []) {
    if (row.display_name) names.set(row.id, row.display_name);
  }
  return names;
}

/**
 * Which of these users have a public profile (one batched query) — used to
 * decide whether a "by <name>" byline links to /u/<id> or stays plain text.
 * RLS on profile_details lets anonymous readers see is_public rows, and the
 * empty-set fallback keeps bylines plain until the 0003 migration runs.
 */
export async function publicProfileIds(
  supabase: SupabaseClient,
  userIds: string[],
): Promise<Set<string>> {
  const ids = [...new Set(userIds)];
  if (ids.length === 0) return new Set();
  try {
    const { data, error } = await supabase
      .from('profile_details')
      .select('id')
      .in('id', ids)
      .eq('is_public', true);
    if (error || !data) return new Set();
    return new Set(data.map((r) => r.id));
  } catch {
    return new Set();
  }
}

/** "1:24:06" / "54:02" — duration label from stored seconds. */
export function durationLabel(seconds: number | null | undefined): string | undefined {
  if (!seconds || !Number.isFinite(seconds) || seconds <= 0) return undefined;
  const h = Math.floor(seconds / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  const s = Math.floor(seconds % 60);
  const ss = String(s).padStart(2, '0');
  return h > 0 ? `${h}:${String(m).padStart(2, '0')}:${ss}` : `${m}:${ss}`;
}

/** "11 June 2026" — consistent date stamp for UGC bylines. */
export function ugcDate(iso: string | null | undefined): string {
  if (!iso) return '';
  return new Intl.DateTimeFormat('en', { day: 'numeric', month: 'long', year: 'numeric' }).format(
    new Date(iso),
  );
}
