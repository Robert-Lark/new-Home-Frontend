/** @jsxImportSource preact */
import { useEffect, useRef, useState, useCallback } from 'preact/hooks';
import { recordProgress, fetchProgress, currentUserId } from '../lib/listen';

export interface Track {
  id: string;
  title: string;
  artist: string;
  cover: string;
  /** Absolute audio URL (cdn.quietcast.art/<audioKey>). */
  src: string;
  catalog?: string;
  /** Fallback duration label shown before metadata loads (e.g. "2:04:11"). */
  durationLabel?: string;
}

/** Read a Track off a clicked [data-qc-play] element's dataset. */
function trackFromEl(el: HTMLElement): Track | null {
  const d = el.dataset;
  if (!d.qcSrc || !d.qcId) return null;
  return {
    id: d.qcId,
    title: d.qcTitle ?? 'Untitled',
    artist: d.qcArtist ?? 'Unknown',
    cover: d.qcCover ?? '',
    src: d.qcSrc,
    catalog: d.qcCatalog,
    durationLabel: d.qcDuration,
  };
}

function fmt(seconds: number): string {
  if (!Number.isFinite(seconds) || seconds < 0) return '0:00';
  const h = Math.floor(seconds / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  const s = Math.floor(seconds % 60);
  const ss = String(s).padStart(2, '0');
  return h > 0 ? `${h}:${String(m).padStart(2, '0')}:${ss}` : `${m}:${ss}`;
}

/** How often to persist progress while playing (throttles DB writes). */
const WRITE_EVERY_SECONDS = 20;
/** Only resume if the saved position is past this (avoids tiny jumps). */
const MIN_RESUME_SECONDS = 10;

export default function PlayerDock() {
  const audioRef = useRef<HTMLAudioElement>(null);
  const [track, setTrack] = useState<Track | null>(null);
  const [queue, setQueue] = useState<Track[]>([]);
  const [isPlaying, setIsPlaying] = useState(false);
  const [currentTime, setCurrentTime] = useState(0);
  const [duration, setDuration] = useState(0);
  const [expanded, setExpanded] = useState(false);
  const lastWriteRef = useRef(0);
  const resumeRef = useRef<{ id: string; seconds: number } | null>(null);
  const currentIdRef = useRef<string | null>(null);

  // Resolve the signed-in user once so the first progress write is instant.
  useEffect(() => {
    void currentUserId();
  }, []);

  // Seek to the user's last position for the current track, once metadata is
  // available. Guarded against races when tracks are switched quickly.
  const applyResume = useCallback(() => {
    const a = audioRef.current;
    const r = resumeRef.current;
    if (!a || !r || r.id !== currentIdRef.current) return;
    if (a.readyState < 1 || !Number.isFinite(a.duration)) return;
    if (r.seconds > 0 && r.seconds < a.duration * 0.97) {
      a.currentTime = r.seconds;
      setCurrentTime(r.seconds);
    }
    resumeRef.current = null;
  }, []);

  // Load a track and (optionally) attempt playback.
  const load = useCallback(
    (next: Track, play = true) => {
      setTrack(next);
      setCurrentTime(0);
      setDuration(0);
      lastWriteRef.current = 0;
      resumeRef.current = null;
      currentIdRef.current = next.id;
      // Fetch last position for resume (logged-in only; no-op otherwise).
      void fetchProgress(next.id).then((p) => {
        if (p && p.status === 'playing' && p.progressSeconds > MIN_RESUME_SECONDS) {
          resumeRef.current = { id: next.id, seconds: p.progressSeconds };
          applyResume();
        }
      });
      // The <audio> src is bound below; play after the element picks up the change.
      requestAnimationFrame(() => {
        const a = audioRef.current;
        if (!a) return;
        a.load();
        if (play) {
          const p = a.play();
          if (p) p.then(() => setIsPlaying(true)).catch(() => setIsPlaying(false));
        }
      });
    },
    [applyResume],
  );

  // Delegated play trigger. Lives on `document`, which persists across
  // ClientRouter navigations — so play buttons on any swapped-in page work
  // with no per-page script. An element may carry data-qc-queue (JSON array of
  // tracks) to seed the up-next queue.
  useEffect(() => {
    const onClick = (e: MouseEvent) => {
      const el = (e.target as HTMLElement | null)?.closest<HTMLElement>('[data-qc-play]');
      if (!el) return;
      const next = trackFromEl(el);
      if (!next) return;
      e.preventDefault();
      if (el.dataset.qcQueue) {
        try {
          setQueue(JSON.parse(el.dataset.qcQueue) as Track[]);
        } catch {
          setQueue([]);
        }
      }
      load(next, true);
    };
    document.addEventListener('click', onClick);
    return () => document.removeEventListener('click', onClick);
  }, [load]);

  const toggle = useCallback(() => {
    const a = audioRef.current;
    if (!a || !track) return;
    if (a.paused) {
      const p = a.play();
      if (p) p.then(() => setIsPlaying(true)).catch(() => setIsPlaying(false));
    } else {
      a.pause();
      setIsPlaying(false);
    }
  }, [track]);

  const playAt = useCallback(
    (delta: number) => {
      if (!queue.length || !track) return;
      const i = queue.findIndex((t) => t.id === track.id);
      const nextIndex = i === -1 ? 0 : (i + delta + queue.length) % queue.length;
      const next = queue[nextIndex];
      if (next) load(next, true);
    },
    [queue, track, load],
  );

  const onScrub = useCallback((e: Event) => {
    const a = audioRef.current;
    const v = Number((e.currentTarget as HTMLInputElement).value);
    if (a) a.currentTime = v;
    setCurrentTime(v);
  }, []);

  // Lock body scroll while the expanded now-playing view is open.
  useEffect(() => {
    document.body.style.overflow = expanded ? 'hidden' : '';
    return () => {
      document.body.style.overflow = '';
    };
  }, [expanded]);

  const pct = duration > 0 ? (currentTime / duration) * 100 : 0;
  const remaining = duration > 0 ? duration - currentTime : 0;
  const upNext = (() => {
    if (!queue.length || !track) return [];
    const i = queue.findIndex((t) => t.id === track.id);
    return i === -1 ? queue : [...queue.slice(i + 1), ...queue.slice(0, i)];
  })();

  return (
    <>
      <audio
        ref={audioRef}
        src={track?.src}
        preload="metadata"
        onTimeUpdate={(e) => {
          const a = e.currentTarget as HTMLAudioElement;
          const t = a.currentTime;
          setCurrentTime(t);
          // Throttled progress persistence while actually playing.
          if (track && !a.paused && t - lastWriteRef.current >= WRITE_EVERY_SECONDS) {
            lastWriteRef.current = t;
            void recordProgress(track.id, t, a.duration);
          }
        }}
        onLoadedMetadata={(e) => {
          setDuration((e.currentTarget as HTMLAudioElement).duration);
          applyResume();
        }}
        onPlay={() => setIsPlaying(true)}
        onPause={(e) => {
          setIsPlaying(false);
          // Flush the current position on pause (recordProgress ignores trivial values).
          if (track) void recordProgress(track.id, (e.currentTarget as HTMLAudioElement).currentTime, duration);
        }}
        onEnded={(e) => {
          const a = e.currentTarget as HTMLAudioElement;
          const d = a.duration || duration;
          if (track) void recordProgress(track.id, d, d);
          playAt(1);
        }}
      />

      {/* ---- Compact dock (always visible) ---- */}
      <div class="dock">
        <img class="cover" src={track?.cover || '/images/cryo_01.jpg'} alt="" onClick={() => track && setExpanded(true)} />
        <div class="meta" onClick={() => track && setExpanded(true)} style={track ? 'cursor:pointer' : ''}>
          <span class="t">{track?.title ?? 'Nothing playing'}</span>
          <span class="a">{track?.artist ?? 'Quiet Cast'}</span>
        </div>
        <span class="tnum">{fmt(currentTime)}</span>
        <div class="scrub" aria-hidden="true">
          <i style={`width:${pct}%`}></i>
        </div>
        <span class="tnum">{duration > 0 ? fmt(duration) : (track?.durationLabel ?? '--:--')}</span>
        <button class="play" onClick={toggle} aria-label={isPlaying ? 'Pause' : 'Play'} disabled={!track}>
          {isPlaying ? (
            <svg viewBox="0 0 24 24" fill="currentColor"><path d="M6 5h4v14H6zm8 0h4v14h-4z" /></svg>
          ) : (
            <svg viewBox="0 0 24 24" fill="currentColor"><path d="M8 5v14l11-7z" /></svg>
          )}
        </button>
      </div>

      {/* ---- Expanded now-playing view ---- */}
      {expanded && track && (
        <div class="now-playing" role="dialog" aria-label="Now playing">
          <div class="np-bg" style={track.cover ? `background-image:url('${track.cover}')` : ''}></div>
          <div class="np-wrap">
            <div class="np-stage">
              <div class="np-top">
                <span class="eyebrow">Now playing{track.catalog ? ` · ${track.catalog}` : ''}</span>
                <button class="np-min" onClick={() => setExpanded(false)} aria-label="Minimize player">▾ Minimize</button>
              </div>
              <div class="np-recess"><img src={track.cover} alt={`${track.title} cover`} /></div>
              <div class="np-band">
                <div class="np-t">{track.title}</div>
                <div class="np-s">{track.artist}</div>
              </div>
              <input
                class="np-range"
                type="range"
                min={0}
                max={duration || 0}
                value={currentTime}
                onInput={onScrub}
                aria-label="Seek"
              />
              <div class="np-times">
                <span>{fmt(currentTime)}</span>
                <span>−{fmt(remaining)}</span>
              </div>
              <div class="np-ctrls">
                <button onClick={() => playAt(-1)} aria-label="Previous" disabled={!queue.length}>
                  <svg viewBox="0 0 24 24" fill="currentColor"><path d="M6 6h2v12H6zm3.5 6l8.5 6V6z" /></svg>
                </button>
                <button class="pp" onClick={toggle} aria-label={isPlaying ? 'Pause' : 'Play'}>
                  {isPlaying ? (
                    <svg viewBox="0 0 24 24" fill="currentColor"><path d="M6 5h4v14H6zm8 0h4v14h-4z" /></svg>
                  ) : (
                    <svg viewBox="0 0 24 24" fill="currentColor"><path d="M8 5v14l11-7z" /></svg>
                  )}
                </button>
                <button onClick={() => playAt(1)} aria-label="Next" disabled={!queue.length}>
                  <svg viewBox="0 0 24 24" fill="currentColor"><path d="M16 6h2v12h-2zM6 6l8.5 6L6 18z" /></svg>
                </button>
              </div>
            </div>
            <aside class="np-queue">
              <div class="np-qh">In the queue · {upNext.length}</div>
              {upNext.map((t, i) => (
                <button
                  key={t.id}
                  class={`np-qrow${i === 0 ? ' next' : ''}`}
                  onClick={() => load(t, true)}
                >
                  <img src={t.cover} alt="" />
                  <span class="np-qmeta">
                    <span class="np-qt">{t.title}</span>
                    <span class="np-qa">{t.artist}</span>
                  </span>
                  {t.durationLabel && <span class="np-qn">{t.durationLabel}</span>}
                </button>
              ))}
            </aside>
          </div>
        </div>
      )}
    </>
  );
}
