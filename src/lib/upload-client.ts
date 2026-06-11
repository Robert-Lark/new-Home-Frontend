/**
 * Browser side of the signed-upload flow (used by the upload islands):
 * ask /api/uploads/sign for a presigned PUT, then send the file straight to
 * R2. XHR rather than fetch so multi-hundred-MB mixes get real progress
 * events.
 */

export interface UploadedObject {
  key: string;
  publicUrl: string;
}

export async function uploadToR2(
  kind: 'mix' | 'cover' | 'photo',
  file: File,
  onProgress?: (fraction: number) => void,
): Promise<UploadedObject> {
  const res = await fetch('/api/uploads/sign', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ kind, contentType: file.type, size: file.size }),
  });
  if (!res.ok) {
    const body = (await res.json().catch(() => null)) as { error?: string } | null;
    throw new Error(body?.error ?? 'Could not start the upload.');
  }
  const { url, key, publicUrl } = (await res.json()) as {
    url: string;
    key: string;
    publicUrl: string;
  };

  await new Promise<void>((resolve, reject) => {
    const xhr = new XMLHttpRequest();
    xhr.open('PUT', url);
    xhr.setRequestHeader('Content-Type', file.type);
    xhr.upload.onprogress = (e) => {
      if (e.lengthComputable && onProgress) onProgress(e.loaded / e.total);
    };
    xhr.onload = () =>
      xhr.status >= 200 && xhr.status < 300
        ? resolve()
        : reject(new Error(`Upload failed (${xhr.status}).`));
    xhr.onerror = () => reject(new Error('Upload failed — check your connection and try again.'));
    xhr.send(file);
  });

  onProgress?.(1);
  return { key, publicUrl };
}
