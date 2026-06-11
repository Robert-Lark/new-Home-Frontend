/** @jsxImportSource preact */
import { useEffect, useState, useCallback, useMemo } from 'preact/hooks';
import { currentUserId } from '../lib/listen';
import {
  fetchPlaylists,
  createPlaylist,
  renamePlaylist,
  deletePlaylist,
  fetchPlaylistItems,
  removeFromPlaylist,
  reorderPlaylist,
  fetchFavorites,
  toggleFavorite,
  type Playlist,
  type PlaylistItem,
} from '../lib/library';
import type { Track } from './PlayerDock';

/**
 * The /playlists page UI (client:only). Renders the signed-in user's favorites
 * + named playlists, with create / rename / reorder / delete and a "play" that
 * builds a Track[] from current state and hands it to the persistent dock via
 * the `qc:play-queue` event — the dynamic-queue seam.
 *
 * content_ref → Track resolution comes from a server-rendered track index
 * (#qc-track-index, all episodes). Refs that don't resolve (e.g. future
 * uploads not yet in the index) are shown but skipped when building the queue.
 */
function readTrackIndex(): Map<string, Track> {
  const map = new Map<string, Track>();
  try {
    const raw = document.getElementById('qc-track-index')?.textContent;
    if (raw) for (const t of JSON.parse(raw) as Track[]) if (t?.id) map.set(t.id, t);
  } catch {
    /* empty index → titles fall back to the raw ref */
  }
  return map;
}

function playQueue(tracks: Track[], startId?: string): void {
  const first = tracks[0];
  if (!first) return;
  document.dispatchEvent(
    new CustomEvent('qc:play-queue', { detail: { tracks, startId: startId ?? first.id } }),
  );
}

export default function PlaylistManager() {
  const [authed, setAuthed] = useState<boolean | null>(null);
  const [playlists, setPlaylists] = useState<Playlist[]>([]);
  const [favorites, setFavorites] = useState<string[]>([]);
  const [expanded, setExpanded] = useState<string | null>(null);
  const [items, setItems] = useState<PlaylistItem[]>([]);
  const [newName, setNewName] = useState('');
  const [renaming, setRenaming] = useState<{ id: string; value: string } | null>(null);
  const [busy, setBusy] = useState(false);
  const index = useMemo(readTrackIndex, []);

  const label = useCallback(
    (ref: string): { title: string; artist: string } => {
      const t = index.get(ref);
      return t ? { title: t.title, artist: t.artist } : { title: ref, artist: '—' };
    },
    [index],
  );
  const toTracks = useCallback((refs: string[]): Track[] => refs.map((r) => index.get(r)).filter((t): t is Track => Boolean(t)), [index]);

  const refresh = useCallback(async () => {
    const [pls, favs] = await Promise.all([fetchPlaylists(true), fetchFavorites(true)]);
    setPlaylists(pls);
    setFavorites([...favs]);
  }, []);

  useEffect(() => {
    void (async () => {
      const uid = await currentUserId();
      setAuthed(Boolean(uid));
      if (uid) await refresh();
    })();
  }, [refresh]);

  const openPlaylist = useCallback(
    async (id: string) => {
      if (expanded === id) {
        setExpanded(null);
        return;
      }
      setExpanded(id);
      setItems(await fetchPlaylistItems(id, true));
    },
    [expanded],
  );

  const onCreate = useCallback(
    async (e: Event) => {
      e.preventDefault();
      const name = newName.trim();
      if (!name || busy) return;
      setBusy(true);
      await createPlaylist(name);
      setNewName('');
      await refresh();
      setBusy(false);
    },
    [newName, busy, refresh],
  );

  const onRename = useCallback(
    async (e: Event) => {
      e.preventDefault();
      if (!renaming || !renaming.value.trim()) return;
      await renamePlaylist(renaming.id, renaming.value);
      setRenaming(null);
      await refresh();
    },
    [renaming, refresh],
  );

  const onDelete = useCallback(
    async (pl: Playlist) => {
      if (!window.confirm(`Delete playlist "${pl.name}"? This can't be undone.`)) return;
      await deletePlaylist(pl.id);
      if (expanded === pl.id) setExpanded(null);
      await refresh();
    },
    [expanded, refresh],
  );

  const onRemoveItem = useCallback(
    async (playlistId: string, itemId: string) => {
      await removeFromPlaylist(playlistId, itemId);
      setItems((prev) => prev.filter((it) => it.id !== itemId));
      await refresh();
    },
    [refresh],
  );

  const onMove = useCallback(
    async (playlistId: string, idx: number, dir: -1 | 1) => {
      const j = idx + dir;
      if (j < 0 || j >= items.length) return;
      const next = [...items];
      const a = next[idx];
      const b = next[j];
      if (!a || !b) return;
      next[idx] = b;
      next[j] = a;
      setItems(next);
      await reorderPlaylist(playlistId, next.map((it) => it.id));
    },
    [items],
  );

  if (authed === null) return <p class="lib-note">Loading your library…</p>;
  if (!authed) {
    return (
      <p class="lib-note">
        <a class="lib-link" href="/login">
          Sign in
        </a>{' '}
        to build and play your favorites and playlists.
      </p>
    );
  }

  const favTracks = toTracks(favorites);

  return (
    <div class="lib">
      {/* ---- Favorites ---- */}
      <section class="lib-block">
        <div class="section-label" style="padding:0;margin:0 0 18px">
          <span class="eyebrow">Favorites</span>
          <span class="line"></span>
          <span class="eyebrow">{favorites.length}</span>
        </div>
        {favorites.length === 0 ? (
          <p class="lib-empty">Tap the mark on any broadcast to keep it close.</p>
        ) : (
          <>
            <button
              class="lib-play-all"
              disabled={favTracks.length === 0}
              onClick={() => playQueue(favTracks)}
            >
              ▸ Play all · {favTracks.length}
            </button>
            <ul class="lib-items">
              {favorites.map((ref) => {
                const { title, artist } = label(ref);
                return (
                  <li class="lib-item" key={ref}>
                    <button class="lib-item-play" aria-label={`Play ${title}`} onClick={() => playQueue(favTracks, ref)}>
                      ▸
                    </button>
                    <span class="lib-item-meta">
                      <span class="lib-item-t">{title}</span>
                      <span class="lib-item-a">{artist}</span>
                    </span>
                    <button
                      class="lib-item-x"
                      aria-label={`Remove ${title} from favorites`}
                      onClick={async () => {
                        await toggleFavorite(ref);
                        setFavorites((prev) => prev.filter((r) => r !== ref));
                      }}
                    >
                      ✕
                    </button>
                  </li>
                );
              })}
            </ul>
          </>
        )}
      </section>

      {/* ---- Playlists ---- */}
      <section class="lib-block">
        <div class="section-label" style="padding:0;margin:0 0 18px">
          <span class="eyebrow">Playlists</span>
          <span class="line"></span>
          <span class="eyebrow">{playlists.length}</span>
        </div>

        <form class="lib-create" onSubmit={onCreate}>
          <input
            class="lib-create-input"
            type="text"
            placeholder="New playlist name…"
            value={newName}
            maxLength={80}
            onInput={(e) => setNewName((e.currentTarget as HTMLInputElement).value)}
            aria-label="New playlist name"
          />
          <button class="lib-create-btn" type="submit" disabled={!newName.trim() || busy}>
            + New playlist
          </button>
        </form>

        {playlists.length === 0 ? (
          <p class="lib-empty">No playlists yet. Name one above, then add broadcasts from any show.</p>
        ) : (
          <ul class="lib-pls">
            {playlists.map((pl) => {
              const isOpen = expanded === pl.id;
              return (
                <li class="lib-pl" key={pl.id}>
                  <div class="lib-pl-head">
                    {renaming?.id === pl.id ? (
                      <form class="lib-rename" onSubmit={onRename}>
                        <input
                          class="lib-rename-input"
                          type="text"
                          value={renaming.value}
                          maxLength={80}
                          autoFocus
                          onInput={(e) =>
                            setRenaming({ id: pl.id, value: (e.currentTarget as HTMLInputElement).value })
                          }
                          aria-label="Playlist name"
                        />
                        <button class="lib-mini" type="submit">
                          Save
                        </button>
                        <button class="lib-mini" type="button" onClick={() => setRenaming(null)}>
                          Cancel
                        </button>
                      </form>
                    ) : (
                      <button class="lib-pl-name" aria-expanded={isOpen} onClick={() => void openPlaylist(pl.id)}>
                        <span class="lib-pl-caret">{isOpen ? '▾' : '▸'}</span>
                        {pl.name}
                        <span class="lib-pl-n">{pl.count}</span>
                      </button>
                    )}
                    <div class="lib-pl-actions">
                      <button
                        class="lib-mini"
                        disabled={pl.count === 0}
                        onClick={async () => {
                          const its = await fetchPlaylistItems(pl.id, true);
                          playQueue(toTracks(its.map((it) => it.contentRef)));
                        }}
                      >
                        ▸ Play
                      </button>
                      <button class="lib-mini" onClick={() => setRenaming({ id: pl.id, value: pl.name })}>
                        Rename
                      </button>
                      <button class="lib-mini danger" onClick={() => void onDelete(pl)}>
                        Delete
                      </button>
                    </div>
                  </div>

                  {isOpen && (
                    <ul class="lib-items nested">
                      {items.length === 0 ? (
                        <li class="lib-empty">Empty. Add broadcasts with the playlist button on any show.</li>
                      ) : (
                        items.map((it, i) => {
                          const { title, artist } = label(it.contentRef);
                          return (
                            <li class="lib-item" key={it.id}>
                              <span class="lib-reorder">
                                <button aria-label="Move up" disabled={i === 0} onClick={() => void onMove(pl.id, i, -1)}>
                                  ▲
                                </button>
                                <button
                                  aria-label="Move down"
                                  disabled={i === items.length - 1}
                                  onClick={() => void onMove(pl.id, i, 1)}
                                >
                                  ▼
                                </button>
                              </span>
                              <button
                                class="lib-item-play"
                                aria-label={`Play ${title}`}
                                onClick={() => playQueue(toTracks(items.map((x) => x.contentRef)), it.contentRef)}
                              >
                                ▸
                              </button>
                              <span class="lib-item-meta">
                                <span class="lib-item-t">{title}</span>
                                <span class="lib-item-a">{artist}</span>
                              </span>
                              <button
                                class="lib-item-x"
                                aria-label={`Remove ${title}`}
                                onClick={() => void onRemoveItem(pl.id, it.id)}
                              >
                                ✕
                              </button>
                            </li>
                          );
                        })
                      )}
                    </ul>
                  )}
                </li>
              );
            })}
          </ul>
        )}
      </section>
    </div>
  );
}
