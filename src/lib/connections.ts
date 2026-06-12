/**
 * Curated starter catalog for the profile connections grid. v1: listeners pick
 * from this fixed shortlist; free-form entries and listener-to-listener
 * connections come later (the table columns already allow both).
 *
 * Images live in public/images. Three were fetched from Wikimedia Commons:
 *  - frahm_01.jpg    — "Nils Frahm (Traumzeit Festival 2014)" by Smial, FAL
 *  - cooper_01.jpg   — "Lead shot - Max Cooper (cropped)" by Jonny Wilson, CC BY-SA 4.0
 *  - denovali_01.jpg — Denovali Records logo, public domain
 * The rest are the design-reference images the site already ships.
 */

/** Mirrors the connections.kind check constraint in 0003_profile.sql. */
export const CONNECTION_KINDS = [
  'artist',
  'label',
  'venue',
  'podcast',
  'photographer',
  'listener',
  'other',
] as const;
export type ConnectionKind = (typeof CONNECTION_KINDS)[number];

export interface CatalogEntry {
  /** Stable id used by the add-to-grid form. */
  slug: string;
  name: string;
  kind: ConnectionKind;
  /** Path under public/. */
  image: string;
  url: string;
}

export const CONNECTION_CATALOG: CatalogEntry[] = [
  { slug: 'denovali', name: 'Denovali', kind: 'label', image: '/images/denovali_01.jpg', url: 'https://denovali.com' },
  { slug: 'ant-zen', name: 'Ant-Zen', kind: 'label', image: '/images/antzen_01.jpg', url: 'https://ant-zen.bandcamp.com' },
  { slug: 'nils-frahm', name: 'Nils Frahm', kind: 'artist', image: '/images/frahm_01.jpg', url: 'https://www.nilsfrahm.com' },
  { slug: 'cryo-chamber', name: 'Cryo Chamber', kind: 'label', image: '/images/cryo_01.jpg', url: 'https://cryochamber.bandcamp.com' },
  { slug: 'max-cooper', name: 'Max Cooper', kind: 'artist', image: '/images/cooper_01.jpg', url: 'https://maxcooper.net' },
  { slug: 'edward-burtynsky', name: 'Edward Burtynsky', kind: 'photographer', image: '/images/burtynsky_01.jpg', url: 'https://www.edwardburtynsky.com' },
];

/** Grid cap (MySpace had a Top 8; we allow a 4-wide grid of three rows). */
export const MAX_CONNECTIONS = 12;
