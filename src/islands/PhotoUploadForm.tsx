/** @jsxImportSource preact */
import { useState } from 'preact/hooks';
import { createSupabaseBrowserClient } from '../lib/supabase';
import { uploadToR2 } from '../lib/upload-client';
import { IMAGE_TYPES, IMAGE_MAX_BYTES, ALBUM_MAX_PHOTOS } from '../lib/ugc';

type Status = 'idle' | 'uploading' | 'done' | 'error';

const mb = (n: number) => Math.floor(n / (1024 * 1024));

export default function PhotoUploadForm() {
  const [title, setTitle] = useState('');
  const [venue, setVenue] = useState('');
  const [eventDate, setEventDate] = useState('');
  const [description, setDescription] = useState('');
  const [files, setFiles] = useState<File[]>([]);
  const [status, setStatus] = useState<Status>('idle');
  const [doneCount, setDoneCount] = useState(0);
  const [progress, setProgress] = useState(0);
  const [msg, setMsg] = useState('');

  const fail = (m: string) => {
    setStatus('error');
    setMsg(m);
  };

  const pick = (e: Event) => {
    const list = (e.currentTarget as HTMLInputElement).files;
    setFiles(list ? [...list] : []);
  };

  const submit = async (e: Event) => {
    e.preventDefault();
    if (status === 'uploading') return;
    if (!title.trim()) return fail('Give the album a title.');
    if (files.length === 0) return fail('Choose at least one photo.');
    if (files.length > ALBUM_MAX_PHOTOS) return fail(`Up to ${ALBUM_MAX_PHOTOS} photos per album.`);
    for (const f of files) {
      if (!IMAGE_TYPES[f.type]) return fail(`"${f.name}" isn't a JPG, PNG, or WebP.`);
      if (f.size > IMAGE_MAX_BYTES) return fail(`"${f.name}" is over the ${mb(IMAGE_MAX_BYTES)}MB limit.`);
    }

    setStatus('uploading');
    setMsg('');
    setDoneCount(0);

    const supabase = createSupabaseBrowserClient();
    const { data: session } = await supabase.auth.getSession();
    const uid = session.session?.user?.id;
    if (!uid) return fail('Your session expired — sign in again and retry.');

    // Album row first (status defaults to 'pending'), then photos attach to it
    // one by one so a mid-batch failure keeps what already made it.
    const { data: album, error: albumError } = await supabase
      .from('photo_albums')
      .insert({
        user_id: uid,
        title: title.trim(),
        venue: venue.trim() || null,
        event_date: eventDate || null,
        description: description.trim() || null,
      })
      .select('id')
      .single();
    if (albumError || !album) return fail(`Couldn't create the album: ${albumError?.message ?? 'unknown error'}.`);

    // Local counter: state captured by this closure goes stale across awaits.
    let completed = 0;
    try {
      for (const [i, file] of files.entries()) {
        setProgress(0);
        const obj = await uploadToR2('photo', file, setProgress);
        const { error } = await supabase
          .from('photos')
          .insert({ album_id: album.id, r2_key: obj.key, position: i });
        if (error) throw new Error(`Photo ${i + 1} uploaded but couldn't be saved: ${error.message}`);
        completed = i + 1;
        setDoneCount(completed);
      }
    } catch (err) {
      return fail(
        `${err instanceof Error ? err.message : 'Upload failed.'} ${completed} of ${files.length} photos made it — the album is still in your queue.`,
      );
    }
    setStatus('done');
  };

  if (status === 'done') {
    return (
      <div class="ugc-success">
        <p class="ugc-success-t">Submitted for review.</p>
        <p class="ugc-success-s">
          <strong>{title}</strong> ({files.length} photo{files.length === 1 ? '' : 's'}) is in the
          moderation queue — it goes public once the curator approves it. Track its status from
          your <a href="/dashboard">account</a>.
        </p>
      </div>
    );
  }

  const busy = status === 'uploading';
  return (
    <form class="ugc-form" onSubmit={submit}>
      <label class="ugc-label" for="alb-title">Title</label>
      <input
        id="alb-title"
        class="ugc-input"
        type="text"
        required
        maxLength={120}
        placeholder="Bohren & der Club of Gore, front row"
        value={title}
        onInput={(e) => setTitle((e.currentTarget as HTMLInputElement).value)}
        disabled={busy}
      />

      <div class="ugc-pair">
        <div>
          <label class="ugc-label" for="alb-venue">Venue · optional</label>
          <input
            id="alb-venue"
            class="ugc-input"
            type="text"
            maxLength={120}
            placeholder="The Empty Bottle, Chicago"
            value={venue}
            onInput={(e) => setVenue((e.currentTarget as HTMLInputElement).value)}
            disabled={busy}
          />
        </div>
        <div>
          <label class="ugc-label" for="alb-date">Date · optional</label>
          <input
            id="alb-date"
            class="ugc-input"
            type="date"
            value={eventDate}
            onInput={(e) => setEventDate((e.currentTarget as HTMLInputElement).value)}
            disabled={busy}
          />
        </div>
      </div>

      <label class="ugc-label" for="alb-desc">Notes · optional</label>
      <textarea
        id="alb-desc"
        class="ugc-textarea"
        rows={3}
        maxLength={2000}
        placeholder="Who played, how it sounded, what the room was like…"
        value={description}
        onInput={(e) => setDescription((e.currentTarget as HTMLTextAreaElement).value)}
        disabled={busy}
      />

      <label class="ugc-label" for="alb-photos">
        Photos · up to {ALBUM_MAX_PHOTOS}, JPG/PNG/WebP, {mb(IMAGE_MAX_BYTES)}MB each
      </label>
      <input
        id="alb-photos"
        class="ugc-file"
        type="file"
        required
        multiple
        accept=".jpg,.jpeg,.png,.webp,image/jpeg,image/png,image/webp"
        onChange={pick}
        disabled={busy}
      />
      {files.length > 0 && (
        <p class="ugc-hint mono">
          {files.length} photo{files.length === 1 ? '' : 's'} selected
        </p>
      )}

      {busy && (
        <div class="ugc-progress" role="progressbar" aria-valuenow={Math.round(progress * 100)} aria-valuemin={0} aria-valuemax={100}>
          <i style={`width:${Math.round(progress * 100)}%`}></i>
          <span class="mono">
            {doneCount + 1}/{files.length} · {Math.round(progress * 100)}%
          </span>
        </div>
      )}

      <button class="ugc-submit" type="submit" disabled={busy}>
        {busy ? `Uploading ${doneCount + 1} of ${files.length}…` : 'Submit for review'}
      </button>
      {status === 'error' && <p class="ugc-error">{msg}</p>}
    </form>
  );
}
