import { sanity } from './sanity';
import type { Track } from '../islands/PlayerDock';

/**
 * A Quiet Cast episode. In the current (legacy) Sanity schema these are stored
 * as `interview` docs — each is a mix with audio + cover + tracklist + a Q&A.
 * Phase 3 remodels this into clean `show`/`mixtape`/`interview` types and moves
 * audio to R2; this layer is the single seam where that swap happens.
 */
export interface Episode {
  cat: number;
  catLabel: string; // "QC—013"
  slug: string;
  title: string; // name with the "Quiet Cast NNN:" prefix stripped
  artist: string;
  description: string;
  coverUrl: string | null;
  audioUrl: string | null;
  year: string | null;
  tracklist: string[];
  /** Q&A pairs from the legacy question1..N / answer1..N fields. */
  qa: Array<{ q: string; a: string }>;
}

interface RawEpisode {
  cat: number;
  name: string;
  slug: string | null;
  artist: string | null;
  description: string | null;
  coverUrl: string | null;
  audioUrl: string | null;
  createdAt: string | null;
  tracklist: unknown[] | null;
  qa: Array<{ q: string | null; a: string | null }> | null;
}

// Pull the up-to-20 question/answer pairs the legacy schema spreads across
// flat fields (question1..20 / answer1..20) into a single array.
const QA_PROJECTION = `"qa": [
  ${Array.from({ length: 20 }, (_, i) => `{"q": question${i + 1}, "a": answer${i + 1}}`).join(',\n  ')}
]`;

const EPISODE_PROJECTION = `{
  cat,
  name,
  "slug": slug.current,
  artist,
  description,
  "coverUrl": cover.asset->url,
  "audioUrl": audio.asset->url,
  "createdAt": _createdAt,
  tracklist,
  ${QA_PROJECTION}
}`;

function mapEpisode(r: RawEpisode): Episode {
  const title = (r.name ?? '').replace(/^\s*quiet\s*cast\s*\d+\s*[:\-–]\s*/i, '').trim() || r.name || 'Untitled';
  return {
    cat: r.cat,
    catLabel: `QC—${String(r.cat ?? 0).padStart(3, '0')}`,
    slug: r.slug ?? String(r.cat),
    title,
    artist: r.artist ?? 'Various',
    description: r.description ?? '',
    coverUrl: r.coverUrl,
    audioUrl: r.audioUrl,
    year: r.createdAt ? r.createdAt.slice(0, 4) : null,
    tracklist: (r.tracklist ?? []).filter((t): t is string => typeof t === 'string'),
    qa: (r.qa ?? [])
      .filter((p): p is { q: string; a: string } => Boolean(p?.q && p?.a))
      .map((p) => ({ q: p.q.trim(), a: p.a.trim() })),
  };
}

/** Append Sanity image-CDN transform params (sizing keeps the grid light). */
export function sizedCover(url: string | null, w: number, h: number = w): string | undefined {
  if (!url) return undefined;
  return `${url}?w=${w}&h=${h}&fit=crop&auto=format`;
}

const FILTER = `_type == "interview" && defined(slug.current) && defined(audio.asset)`;

export async function getEpisodes(): Promise<Episode[]> {
  const rows = await sanity.fetch<RawEpisode[]>(`*[${FILTER}] | order(cat desc) ${EPISODE_PROJECTION}`);
  return rows.map(mapEpisode);
}

export async function getEpisode(slug: string): Promise<Episode | null> {
  const row = await sanity.fetch<RawEpisode | null>(
    `*[${FILTER} && slug.current == $slug][0] ${EPISODE_PROJECTION}`,
    { slug },
  );
  return row ? mapEpisode(row) : null;
}

/** Map an episode to the player island's Track shape (small dock cover). */
export function trackOf(e: Episode): Track {
  return {
    id: e.slug,
    title: e.title,
    artist: e.artist,
    cover: sizedCover(e.coverUrl, 160) ?? '',
    src: e.audioUrl ?? '',
    catalog: e.catLabel,
  };
}
