import { createClient } from '@sanity/client';
import { PUBLIC_SANITY_PROJECT_ID, PUBLIC_SANITY_DATASET } from 'astro:env/client';

/**
 * Public, read-only Sanity client for editorial content (interviews, show &
 * mixtape metadata, cover art, tracklists). `useCdn: true` serves cached,
 * published documents — no token, browser-safe.
 *
 * The token-bearing WRITE client (schema migrations, backfilling R2 audioKeys)
 * is server-only and lands in Phase 3 as a separate module so this file stays
 * importable from client islands.
 */
export const sanity = createClient({
  projectId: PUBLIC_SANITY_PROJECT_ID,
  dataset: PUBLIC_SANITY_DATASET,
  apiVersion: '2025-01-01',
  useCdn: true,
  perspective: 'published',
});
