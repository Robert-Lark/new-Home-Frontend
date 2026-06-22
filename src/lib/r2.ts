import {
  R2_ACCOUNT_ID,
  R2_ACCESS_KEY_ID,
  R2_SECRET_ACCESS_KEY,
  R2_BUCKET,
} from 'astro:env/server';

/**
 * Presigned R2 PUT URLs, hand-rolled SigV4 (query-string flavor) on Web
 * Crypto — no AWS SDK in the bundle for one request shape.
 *
 * Verified against https://developers.cloudflare.com/r2/api/s3/presigned-urls/ :
 * endpoint is `<ACCOUNT_ID>.r2.cloudflarestorage.com` (presigned URLs do NOT
 * work on custom domains — uploads go to the S3 API host, public reads come
 * back via cdn.quietcast.art), region is the literal "auto", UNSIGNED-PAYLOAD
 * is supported, expiry max 7 days. Browser PUTs additionally require CORS
 * rules on the bucket (one-time dashboard step).
 */

const enc = new TextEncoder();

function hex(buf: ArrayBuffer): string {
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

async function sha256Hex(s: string): Promise<string> {
  return hex(await crypto.subtle.digest('SHA-256', enc.encode(s)));
}

async function hmac(key: ArrayBuffer | Uint8Array, s: string): Promise<ArrayBuffer> {
  const k = await crypto.subtle.importKey(
    'raw',
    key as ArrayBuffer,
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  return crypto.subtle.sign('HMAC', k, enc.encode(s));
}

/** RFC 3986 strict encoding (AWS canonical form): also escapes !'()* . */
function rfc3986(s: string): string {
  return encodeURIComponent(s).replace(/[!'()*]/g, (c) => `%${c.charCodeAt(0).toString(16).toUpperCase()}`);
}

/** Encode an object key per segment, keeping the / separators literal. */
function encodeKeyPath(key: string): string {
  return key.split('/').map(rfc3986).join('/');
}

export function r2Configured(): boolean {
  return Boolean(R2_ACCOUNT_ID && R2_ACCESS_KEY_ID && R2_SECRET_ACCESS_KEY);
}

/**
 * Mint a presigned PUT URL for `key`. Only the `host` header is signed, so the
 * browser may send its own Content-Type; the server-side cap enforcement
 * happens before minting, in the /api/uploads/sign route.
 */
export async function presignR2Put(key: string, expiresSeconds = 900): Promise<string> {
  if (!r2Configured()) throw new Error('R2 S3 credentials are not configured');

  const host = `${R2_ACCOUNT_ID}.r2.cloudflarestorage.com`;
  const path = `/${R2_BUCKET}/${encodeKeyPath(key)}`;

  const now = new Date();
  const amzDate = now.toISOString().replace(/[-:]/g, '').replace(/\.\d{3}/, ''); // YYYYMMDDTHHMMSSZ
  const dateStamp = amzDate.slice(0, 8);
  const scope = `${dateStamp}/auto/s3/aws4_request`;

  const params: Array<[string, string]> = [
    ['X-Amz-Algorithm', 'AWS4-HMAC-SHA256'],
    ['X-Amz-Content-Sha256', 'UNSIGNED-PAYLOAD'],
    ['X-Amz-Credential', `${R2_ACCESS_KEY_ID}/${scope}`],
    ['X-Amz-Date', amzDate],
    ['X-Amz-Expires', String(expiresSeconds)],
    ['X-Amz-SignedHeaders', 'host'],
  ];
  const canonicalQuery = params
    .map(([k, v]) => `${rfc3986(k)}=${rfc3986(v)}`)
    .sort()
    .join('&');

  const canonicalRequest = [
    'PUT',
    path,
    canonicalQuery,
    `host:${host}`,
    '',
    'host',
    'UNSIGNED-PAYLOAD',
  ].join('\n');

  const stringToSign = [
    'AWS4-HMAC-SHA256',
    amzDate,
    scope,
    await sha256Hex(canonicalRequest),
  ].join('\n');

  let signingKey = await hmac(enc.encode(`AWS4${R2_SECRET_ACCESS_KEY}`), dateStamp);
  for (const part of ['auto', 's3', 'aws4_request']) signingKey = await hmac(signingKey, part);
  const signature = hex(await hmac(signingKey, stringToSign));

  return `https://${host}${path}?${canonicalQuery}&X-Amz-Signature=${signature}`;
}
