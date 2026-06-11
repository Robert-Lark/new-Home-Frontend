/** @jsxImportSource preact */
import { useState } from 'preact/hooks';
import { createSupabaseBrowserClient } from '../lib/supabase';
import { uploadToR2 } from '../lib/upload-client';
import { AUDIO_TYPES, IMAGE_TYPES, MIX_MAX_BYTES, IMAGE_MAX_BYTES } from '../lib/ugc';

type Status = 'idle' | 'uploading' | 'saving' | 'done' | 'error';

const mb = (n: number) => Math.floor(n / (1024 * 1024));

/** Best-effort duration probe via an off-DOM <audio> element. */
function probeDuration(file: File): Promise<number | null> {
  return new Promise((resolve) => {
    const url = URL.createObjectURL(file);
    const a = new Audio();
    const done = (v: number | null) => {
      URL.revokeObjectURL(url);
      resolve(v);
    };
    a.onloadedmetadata = () => done(Number.isFinite(a.duration) ? Math.round(a.duration) : null);
    a.onerror = () => done(null);
    a.src = url;
  });
}

export default function MixUploadForm() {
  const [title, setTitle] = useState('');
  const [description, setDescription] = useState('');
  const [tracklist, setTracklist] = useState('');
  const [audio, setAudio] = useState<File | null>(null);
  const [cover, setCover] = useState<File | null>(null);
  const [status, setStatus] = useState<Status>('idle');
  const [progress, setProgress] = useState(0);
  const [msg, setMsg] = useState('');

  const fail = (m: string) => {
    setStatus('error');
    setMsg(m);
  };

  const submit = async (e: Event) => {
    e.preventDefault();
    if (status === 'uploading' || status === 'saving') return;
    if (!title.trim()) return fail('Give your mix a title.');
    if (!audio) return fail('Choose an audio file.');
    if (!AUDIO_TYPES[audio.type]) return fail('Audio must be MP3 or M4A.');
    if (audio.size > MIX_MAX_BYTES) return fail(`Audio is over the ${mb(MIX_MAX_BYTES)}MB limit.`);
    if (cover && !IMAGE_TYPES[cover.type]) return fail('Cover must be JPG, PNG, or WebP.');
    if (cover && cover.size > IMAGE_MAX_BYTES) return fail(`Cover is over the ${mb(IMAGE_MAX_BYTES)}MB limit.`);

    setStatus('uploading');
    setMsg('');
    setProgress(0);
    try {
      const coverObj = cover ? await uploadToR2('cover', cover) : null;
      const audioObj = await uploadToR2('mix', audio, setProgress);

      setStatus('saving');
      const supabase = createSupabaseBrowserClient();
      const { data: session } = await supabase.auth.getSession();
      const uid = session.session?.user?.id;
      if (!uid) return fail('Your session expired — sign in again and retry.');

      const duration = await probeDuration(audio);
      const tracks = tracklist
        .split('\n')
        .map((t) => t.trim())
        .filter(Boolean);

      // Status defaults to 'pending' (RLS rejects anything else).
      const { error } = await supabase.from('user_uploads').insert({
        user_id: uid,
        title: title.trim(),
        description: description.trim() || null,
        tracklist: tracks,
        r2_key: audioObj.key,
        cover_r2_key: coverObj?.key ?? null,
        duration,
        mime: audio.type,
      });
      if (error) return fail(`The file uploaded but saving its details failed: ${error.message}`);
      setStatus('done');
    } catch (err) {
      fail(err instanceof Error ? err.message : 'Upload failed — try again.');
    }
  };

  if (status === 'done') {
    return (
      <div class="ugc-success">
        <p class="ugc-success-t">Submitted for review.</p>
        <p class="ugc-success-s">
          <strong>{title}</strong> is in the moderation queue — it goes public once the curator
          approves it. Track its status from your <a href="/dashboard">account</a>.
        </p>
      </div>
    );
  }

  const busy = status === 'uploading' || status === 'saving';
  return (
    <form class="ugc-form" onSubmit={submit}>
      <label class="ugc-label" for="mix-title">Title</label>
      <input
        id="mix-title"
        class="ugc-input"
        type="text"
        required
        maxLength={120}
        placeholder="Night drive tape no. 4"
        value={title}
        onInput={(e) => setTitle((e.currentTarget as HTMLInputElement).value)}
        disabled={busy}
      />

      <label class="ugc-label" for="mix-desc">Description · optional</label>
      <textarea
        id="mix-desc"
        class="ugc-textarea"
        rows={4}
        maxLength={2000}
        placeholder="Where it was recorded, what it's for, who it's by…"
        value={description}
        onInput={(e) => setDescription((e.currentTarget as HTMLTextAreaElement).value)}
        disabled={busy}
      />

      <label class="ugc-label" for="mix-tracks">Tracklist · optional, one track per line</label>
      <textarea
        id="mix-tracks"
        class="ugc-textarea"
        rows={6}
        placeholder={'Artist — Title\nArtist — Title'}
        value={tracklist}
        onInput={(e) => setTracklist((e.currentTarget as HTMLTextAreaElement).value)}
        disabled={busy}
      />

      <label class="ugc-label" for="mix-audio">
        Audio · MP3 or M4A, up to {mb(MIX_MAX_BYTES)}MB
      </label>
      <input
        id="mix-audio"
        class="ugc-file"
        type="file"
        required
        accept=".mp3,.m4a,audio/mpeg,audio/mp4,audio/x-m4a"
        onChange={(e) => setAudio((e.currentTarget as HTMLInputElement).files?.[0] ?? null)}
        disabled={busy}
      />

      <label class="ugc-label" for="mix-cover">
        Cover art · optional, JPG/PNG/WebP up to {mb(IMAGE_MAX_BYTES)}MB
      </label>
      <input
        id="mix-cover"
        class="ugc-file"
        type="file"
        accept=".jpg,.jpeg,.png,.webp,image/jpeg,image/png,image/webp"
        onChange={(e) => setCover((e.currentTarget as HTMLInputElement).files?.[0] ?? null)}
        disabled={busy}
      />

      {status === 'uploading' && (
        <div class="ugc-progress" role="progressbar" aria-valuenow={Math.round(progress * 100)} aria-valuemin={0} aria-valuemax={100}>
          <i style={`width:${Math.round(progress * 100)}%`}></i>
          <span class="mono">{Math.round(progress * 100)}%</span>
        </div>
      )}

      <button class="ugc-submit" type="submit" disabled={busy}>
        {status === 'uploading' ? 'Uploading…' : status === 'saving' ? 'Saving…' : 'Submit for review'}
      </button>
      {status === 'error' && <p class="ugc-error">{msg}</p>}
    </form>
  );
}
