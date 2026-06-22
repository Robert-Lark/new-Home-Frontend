/** @jsxImportSource preact */
import { useEffect, useRef, useState, useCallback } from 'preact/hooks';
import { currentUserId } from '../lib/listen';
import {
  fetchFavorites,
  toggleFavorite,
  fetchPlaylists,
  playlistsContaining,
  addToPlaylist,
  removeRefFromPlaylist,
  createPlaylist,
  FAVORITE_EVENT,
  type Playlist,
} from '../lib/library';

/**
 * One island that powers the inline library controls on static pages. Like the
 * player it works by `document`-delegated clicks, so server-rendered buttons on
 * any ClientRouter-swapped page just work with no per-page script:
 *
 *  - `[data-qc-fav-btn][data-qc-ref]`      → one-tap favorite toggle. The island
 *    paints `data-qc-fav="on|off"` on every such button (recolor, mirrors
 *    ListenState) and flips it optimistically on click.
 *  - `[data-qc-playlist-btn][data-qc-ref]` → opens the add-to-playlist popover.
 *
 * Logged-out clicks redirect to /login (favorites/playlists need a session).
 */
export default function LibraryControls() {
  const [open, setOpen] = useState(false);
  const [anchor, setAnchor] = useState<{ x: number; y: number } | null>(null);
  const [activeRef, setActiveRef] = useState<string | null>(null);
  const [playlists, setPlaylists] = useState<Playlist[]>([]);
  const [member, setMember] = useState<Set<string>>(new Set());
  const [loading, setLoading] = useState(false);
  const [newName, setNewName] = useState('');
  const [busy, setBusy] = useState<string | null>(null);
  const triggerRef = useRef<HTMLElement | null>(null);
  // Mirror `open` into a ref so the delegated-listener effect can read the latest
  // value without listing `open` as a dep — otherwise it tears down and re-adds
  // all of its document/window listeners (and refetches favorites) on every
  // popover open/close.
  const openRef = useRef(false);

  const paintFavorites = useCallback(async () => {
    const favs = await fetchFavorites();
    document.querySelectorAll<HTMLElement>('[data-qc-fav-btn][data-qc-ref]').forEach((el) => {
      const ref = el.dataset.qcRef;
      el.dataset.qcFav = ref && favs.has(ref) ? 'on' : 'off';
    });
  }, []);

  const closeMenu = useCallback(() => {
    setOpen(false);
    setActiveRef(null);
    setNewName('');
    triggerRef.current?.focus();
  }, []);

  const openMenu = useCallback(async (btn: HTMLElement) => {
    const ref = btn.dataset.qcRef;
    if (!ref) return;
    if (!(await currentUserId())) {
      window.location.href = '/login';
      return;
    }
    triggerRef.current = btn;
    const rect = btn.getBoundingClientRect();
    setAnchor({ x: rect.right, y: rect.bottom + 6 });
    setActiveRef(ref);
    setOpen(true);
    setLoading(true);
    const [pls, mem] = await Promise.all([fetchPlaylists(), playlistsContaining(ref)]);
    setPlaylists(pls);
    setMember(mem);
    setLoading(false);
  }, []);

  const handleFav = useCallback(async (btn: HTMLElement) => {
    const ref = btn.dataset.qcRef;
    if (!ref) return;
    if (!(await currentUserId())) {
      window.location.href = '/login';
      return;
    }
    await toggleFavorite(ref); // optimistic: emits FAVORITE_EVENT immediately
  }, []);

  useEffect(() => {
    openRef.current = open;
  }, [open]);

  // Delegated clicks + recolor lifecycle. Binds once on mount; re-runs across
  // ClientRouter nav via the astro:page-load listener (matches ListenState).
  useEffect(() => {
    const onClick = (e: MouseEvent) => {
      const t = e.target as HTMLElement | null;
      const fav = t?.closest<HTMLElement>('[data-qc-fav-btn]');
      if (fav) {
        e.preventDefault();
        void handleFav(fav);
        return;
      }
      const pl = t?.closest<HTMLElement>('[data-qc-playlist-btn]');
      if (pl) {
        e.preventDefault();
        void openMenu(pl);
        return;
      }
      // Click outside an open popover closes it.
      if (openRef.current && !t?.closest('.ql-menu')) closeMenu();
    };
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape' && open) closeMenu();
    };
    const onFav = (e: Event) => {
      const d = (e as CustomEvent).detail as { ref: string; favorite: boolean } | undefined;
      if (!d) return;
      document
        .querySelectorAll<HTMLElement>(`[data-qc-fav-btn][data-qc-ref="${CSS.escape(d.ref)}"]`)
        .forEach((el) => {
          el.dataset.qcFav = d.favorite ? 'on' : 'off';
        });
    };
    const onPageLoad = () => void paintFavorites();
    const onScroll = () => openRef.current && closeMenu();

    void paintFavorites();
    document.addEventListener('click', onClick);
    document.addEventListener('keydown', onKey);
    document.addEventListener(FAVORITE_EVENT, onFav);
    document.addEventListener('astro:page-load', onPageLoad);
    window.addEventListener('scroll', onScroll, { passive: true });
    return () => {
      document.removeEventListener('click', onClick);
      document.removeEventListener('keydown', onKey);
      document.removeEventListener(FAVORITE_EVENT, onFav);
      document.removeEventListener('astro:page-load', onPageLoad);
      window.removeEventListener('scroll', onScroll);
    };
  }, [handleFav, openMenu, closeMenu, paintFavorites]);

  const onToggleMembership = useCallback(
    async (pl: Playlist) => {
      if (!activeRef || busy) return;
      setBusy(pl.id);
      const has = member.has(pl.id);
      if (has) await removeRefFromPlaylist(pl.id, activeRef);
      else await addToPlaylist(pl.id, activeRef);
      const next = new Set(member);
      if (has) next.delete(pl.id);
      else next.add(pl.id);
      setMember(next);
      setPlaylists(await fetchPlaylists());
      setBusy(null);
    },
    [activeRef, member, busy],
  );

  const onCreate = useCallback(
    async (e: Event) => {
      e.preventDefault();
      const name = newName.trim();
      if (!name || !activeRef || busy) return;
      setBusy('new');
      const pl = await createPlaylist(name);
      if (pl) {
        await addToPlaylist(pl.id, activeRef);
        setMember(new Set(member).add(pl.id));
        setPlaylists(await fetchPlaylists());
        setNewName('');
      }
      setBusy(null);
    },
    [newName, activeRef, member, busy],
  );

  if (!open || !anchor) return null;

  // Keep the popover on-screen: anchor by its right edge, clamp into the viewport.
  const width = 248;
  const left = Math.max(12, Math.min(anchor.x - width, window.innerWidth - width - 12));
  const top = Math.min(anchor.y, window.innerHeight - 80);

  return (
    <div
      class="ql-menu"
      role="menu"
      aria-label="Add to playlist"
      style={`left:${left}px;top:${top}px;width:${width}px`}
    >
      <div class="ql-menu-h">Add to playlist</div>
      {loading ? (
        <div class="ql-menu-empty">Loading…</div>
      ) : (
        <div class="ql-menu-list">
          {playlists.map((pl) => {
            const checked = member.has(pl.id);
            return (
              <button
                key={pl.id}
                class="ql-menu-row"
                role="menuitemcheckbox"
                aria-checked={checked}
                disabled={busy === pl.id}
                onClick={() => void onToggleMembership(pl)}
              >
                <span class={`ql-check${checked ? ' on' : ''}`} aria-hidden="true">
                  {checked ? '✓' : ''}
                </span>
                <span class="ql-menu-name">{pl.name}</span>
                <span class="ql-menu-n">{pl.count}</span>
              </button>
            );
          })}
          {playlists.length === 0 && <div class="ql-menu-empty">No playlists yet.</div>}
        </div>
      )}
      <form class="ql-menu-new" onSubmit={onCreate}>
        <input
          class="ql-menu-input"
          type="text"
          placeholder="New playlist…"
          value={newName}
          maxLength={80}
          onInput={(e) => setNewName((e.currentTarget as HTMLInputElement).value)}
          aria-label="New playlist name"
        />
        <button class="ql-menu-add" type="submit" disabled={!newName.trim() || busy === 'new'}>
          +
        </button>
      </form>
    </div>
  );
}
