export const prerender = false;

import type { APIRoute } from 'astro';
import { z } from 'zod';
import { presignR2Put, r2Configured } from '../../../lib/r2';
import {
  AUDIO_TYPES,
  IMAGE_TYPES,
  MIX_MAX_BYTES,
  IMAGE_MAX_BYTES,
  MAX_PENDING_PER_USER,
  cdnUrl,
} from '../../../lib/ugc';

/**
 * Mints a presigned R2 PUT for an authenticated user (locked flow: SSR
 * endpoint authenticates the Supabase session → presigned PUT → the client
 * uploads straight to R2, so audio/image bytes never transit this function or
 * Supabase). The metadata row is inserted afterwards by the client under RLS,
 * which only accepts keys beneath the user/<uid>/ prefix minted here.
 */

const signRequestSchema = z.object({
  kind: z.enum(['mix', 'cover', 'photo']),
  contentType: z.string().min(1),
  size: z.number().int().positive(),
});

function json(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

export const POST: APIRoute = async ({ locals, request }) => {
  const user = locals.user;
  if (!user) return json(401, { error: 'Sign in to upload.' });
  if (!r2Configured()) return json(503, { error: 'Uploads are not configured on this deployment yet.' });

  let raw: unknown;
  try {
    raw = await request.json();
  } catch {
    return json(400, { error: 'Expected a JSON body.' });
  }
  const parsed = signRequestSchema.safeParse(raw);
  if (!parsed.success) return json(400, { error: 'Invalid upload request.' });
  const { kind, contentType, size } = parsed.data;

  const allowed = kind === 'mix' ? AUDIO_TYPES : IMAGE_TYPES;
  const maxBytes = kind === 'mix' ? MIX_MAX_BYTES : IMAGE_MAX_BYTES;
  const ext = allowed[contentType];
  if (!ext) {
    const wanted = kind === 'mix' ? 'MP3 or M4A audio' : 'JPG, PNG, or WebP images';
    return json(415, { error: `That file type isn't supported — use ${wanted}.` });
  }
  if (size > maxBytes) {
    return json(413, { error: `Too large — the limit is ${Math.floor(maxBytes / (1024 * 1024))}MB.` });
  }

  // Abuse brake: pause new submissions while a pile is already awaiting
  // review. RLS scopes these counts to the signed-in user.
  const supabase = locals.supabase;
  const [uploads, albums] = await Promise.all([
    supabase.from('user_uploads').select('id', { count: 'exact', head: true }).eq('status', 'pending'),
    supabase.from('photo_albums').select('id', { count: 'exact', head: true }).eq('status', 'pending'),
  ]);
  const pendingCount = (uploads.count ?? 0) + (albums.count ?? 0);
  if (pendingCount >= MAX_PENDING_PER_USER) {
    return json(429, { error: 'You have submissions awaiting review — please wait for those first.' });
  }

  const key = `user/${user.id}/${kind}/${crypto.randomUUID()}.${ext}`;
  const url = await presignR2Put(key);
  return json(200, { url, key, publicUrl: cdnUrl(key) });
};
