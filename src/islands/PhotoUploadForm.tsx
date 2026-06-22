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
  const [visibility, setVisibility] = useState<'published' | 'private'>('published');
  const [status, setStatus] = useState<Status>('idle');
  const [doneCount, setDoneCount] = useState(0);
  const [progress, setProgress] = useState(0);
  const [msg, setMsg] = useState('');
  const [savedId, setSavedId] = useState<string | null>(null);

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

    // Album row first, ALWAYS private, then photos attach one by one; only a
    // complete album flips to the chosen visibility. A mid-batch failure
    // keeps what already made it — visible to the author alone, never a
    // half-album on the community shelf.
    const { data: album, error: albumError } = await supabase
      .from('photo_albums')
      .insert({
        user_id: uid,
        title: title.trim(),
        venue: venue.trim() || null,
        event_date: eventDate || null,
        description: description.trim() || null,
        status: 'private',
      })
      .select('id')
      .single();
    if (albumError || !album) return fail(`Couldn't create the album: ${albumError?.message ?? 'unknown error'}.`);
    setSavedId(album.id);

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
        `${err instanceof Error ? err.message : 'Upload failed.'} ${completed} of ${files.length} photos made it — the album is saved, private, on your account.`,
      );
    }
    if (visibility === 'published') {
      const { error } = await supabase
        .from('photo_albums')
        .update({ status: 'published' })
        .eq('id', album.id);
      if (error)
        return fail('The photos are all up, but publishing failed — flip the album public from its page.');
    }
    setStatus('done');
  };

  if (status === 'done') {
    const href = savedId ? `/photos/${savedId}` : '/dashboard';
    return (
      <div class="ugc-success">
        <p class="ugc-success-t">{visibility === 'published' ? "It's live." : 'Saved — private.'}</p>
        <p class="ugc-success-s">
          {visibility === 'published' ? (
            <>
              <strong>{title}</strong> ({files.length} photo{files.length === 1 ? '' : 's'}) is on the
              community shelf now — <a href={href}>have a look</a>. You can make it private again from
              its page.
            </>
          ) : (
            <>
              <strong>{title}</strong> ({files.length} photo{files.length === 1 ? '' : 's'}) is up,
              visible only to you. Publish it any time from <a href={href}>its page</a> or your{' '}
              <a href="/dashboard">account</a>.
            </>
          )}
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

      <fieldset class="ugc-vis" disabled={busy}>
        <legend class="ugc-label">Visibility</legend>
        <label>
          <input
            type="radio"
            name="visibility"
            value="published"
            checked={visibility === 'published'}
            onChange={() => setVisibility('published')}
          />
          <span><b>Public</b> — on the community shelf and your profile once every photo is up.</span>
        </label>
        <label>
          <input
            type="radio"
            name="visibility"
            value="private"
            checked={visibility === 'private'}
            onChange={() => setVisibility('private')}
          />
          <span><b>Private</b> — only you can see it. Flip it later from the album's page.</span>
        </label>
      </fieldset>

      {busy && (
        <div class="ugc-progress" role="progressbar" aria-valuenow={Math.round(progress * 100)} aria-valuemin={0} aria-valuemax={100}>
          <i style={`width:${Math.round(progress * 100)}%`}></i>
          <span class="mono">
            {doneCount + 1}/{files.length} · {Math.round(progress * 100)}%
          </span>
        </div>
      )}

      <button class="ugc-submit" type="submit" disabled={busy}>
        {busy ? `Uploading ${doneCount + 1} of ${files.length}…` : 'Upload the album'}
      </button>
      {status === 'error' && <p class="ugc-error">{msg}</p>}
    </form>
  );
}
