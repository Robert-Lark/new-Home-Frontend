/** @jsxImportSource preact */
import { useEffect, useRef, useState } from 'preact/hooks';

/**
 * The profile rotation (the "top friends" pinboard). One component renders the
 * tiles for both views so the markup exists once:
 *  - /u/[id]: no client directive — pure server HTML, zero JS shipped.
 *  - /dashboard: client:load — the server HTML hydrates into a reorderable
 *    grid (pointer-drag via the ⠿ handle, ◂/▸ move buttons for keyboard).
 *
 * Progressive enhancement contract: every control is a real <form> POSTing to
 * the hosting page's dispatcher, so remove AND reorder work without JS — the
 * ◂/▸ forms carry the full would-be order in a hidden field. Hydration only
 * intercepts them to reorder optimistically and persist via fetch; the server
 * (connections.position, RLS-scoped) stays the source of truth.
 */

export interface RotationTile {
  id: string;
  name: string;
  kind: string;
  image_url: string | null;
  link_url: string | null;
}

interface Props {
  tiles: RotationTile[];
  editable: boolean;
}

/** Off-site tile links open in a new tab; in-app links (listener pins) stay put. */
const offsite = (url: string | null) => Boolean(url && !url.startsWith('/'));

const idsWithSwap = (tiles: RotationTile[], i: number, j: number): string => {
  const ids = tiles.map((t) => t.id);
  if (j >= 0 && j < ids.length) [ids[i], ids[j]] = [ids[j]!, ids[i]!];
  return ids.join(',');
};

export default function RotationGrid({ tiles, editable }: Props) {
  const [order, setOrder] = useState(tiles);
  const [dragId, setDragId] = useState<string | null>(null);
  const [msg, setMsg] = useState<string | null>(null);
  const [live, setLive] = useState('');
  // Drag handles only exist once hydrated — without JS they'd be dead chrome.
  const [mounted, setMounted] = useState(false);
  useEffect(() => setMounted(true), []);

  const listRef = useRef<HTMLUListElement>(null);
  // Live value for the window-level drag listeners — their closures outlive
  // many renders, and the DOM reorders mid-drag.
  const orderRef = useRef(order);
  orderRef.current = order;
  const dragStart = useRef<RotationTile[] | null>(null);
  const pendingFocus = useRef<{ id: string; dir: -1 | 1 } | null>(null);
  // Serialize saves so rapid moves can't land out of order server-side.
  const saving = useRef<Promise<void>>(Promise.resolve());

  const queueSave = (ids: string[]) => {
    saving.current = saving.current.then(async () => {
      try {
        const fd = new FormData();
        fd.set('action', 'reorder-connections');
        fd.set('order', ids.join(','));
        const res = await fetch('/dashboard', { method: 'POST', body: fd });
        // Success is the PRG redirect; an inline-error page comes back as a
        // plain 200, so `redirected` is the success signal.
        if (!res.ok || !res.redirected) throw new Error('reorder rejected');
        setMsg(null);
      } catch {
        setMsg('Could not save the new order — refresh and try again.');
        setLive('Could not save the new order.');
      }
    });
  };

  const move = (id: string, dir: -1 | 1) => {
    const i = order.findIndex((t) => t.id === id);
    const j = i + dir;
    if (i < 0 || j < 0 || j >= order.length) return;
    const next = [...order];
    [next[i], next[j]] = [next[j]!, next[i]!];
    setOrder(next);
    setLive(`${next[j]!.name} moved to position ${j + 1} of ${next.length}.`);
    pendingFocus.current = { id, dir };
    queueSave(next.map((t) => t.id));
  };

  // Re-rendering can disable the button that was just pressed (tile reached an
  // end of the list) — keep keyboard focus inside the same tile's controls.
  useEffect(() => {
    const pf = pendingFocus.current;
    if (!pf || !listRef.current) return;
    pendingFocus.current = null;
    const btn = (sel: string) => listRef.current!.querySelector<HTMLButtonElement>(sel);
    const same = btn(`[data-mv="${pf.id}|${pf.dir}"]`);
    const other = btn(`[data-mv="${pf.id}|${-pf.dir}"]`);
    (same && !same.disabled ? same : other)?.focus();
  }, [order]);

  /* ---- pointer drag (one code path for mouse + touch) ---- */

  const indexUnderPointer = (x: number, y: number): number => {
    const lis = listRef.current?.querySelectorAll<HTMLElement>('.p-tile');
    if (!lis) return -1;
    let best = -1;
    let bestDist = Infinity;
    lis.forEach((li, i) => {
      const r = li.getBoundingClientRect();
      const d = Math.hypot(x - (r.left + r.width / 2), y - (r.top + r.height / 2));
      if (d < bestDist) {
        bestDist = d;
        best = i;
      }
    });
    return best;
  };

  // The drag listeners live on window: reordering moves the dragged tile in
  // the DOM, and a DOM move releases pointer capture in Chromium — events on
  // the handle itself go silent after the first swap. Window listeners keep
  // receiving the (bubbling) pointer stream for the whole gesture.
  const onGrab = (e: PointerEvent, id: string) => {
    if (e.pointerType === 'mouse' && e.button !== 0) return;
    e.preventDefault();
    (e.currentTarget as HTMLElement).setPointerCapture?.(e.pointerId);
    dragStart.current = orderRef.current;
    setDragId(id);

    const moveEv = (ev: globalThis.PointerEvent) => {
      const cur = orderRef.current;
      const over = indexUnderPointer(ev.clientX, ev.clientY);
      const from = cur.findIndex((t) => t.id === id);
      if (over < 0 || over === from) return;
      const next = [...cur];
      const [moved] = next.splice(from, 1);
      next.splice(over, 0, moved!);
      setOrder(next);
    };
    const finish = (commit: boolean) => {
      window.removeEventListener('pointermove', moveEv);
      window.removeEventListener('pointerup', up);
      window.removeEventListener('pointercancel', cancel);
      window.removeEventListener('keydown', key);
      setDragId(null);
      const before = dragStart.current;
      dragStart.current = null;
      const cur = orderRef.current;
      if (!commit) {
        if (before) setOrder(before);
        setLive('Reorder cancelled.');
        return;
      }
      if (before && before.some((t, i) => t.id !== cur[i]?.id)) {
        const pos = cur.findIndex((t) => t.id === id);
        setLive(`${cur[pos]?.name} moved to position ${pos + 1} of ${cur.length}.`);
        queueSave(cur.map((t) => t.id));
      }
    };
    const up = () => finish(true);
    const cancel = () => finish(false);
    const key = (ev: KeyboardEvent) => {
      if (ev.key === 'Escape') cancel();
    };
    window.addEventListener('pointermove', moveEv);
    window.addEventListener('pointerup', up);
    window.addEventListener('pointercancel', cancel);
    window.addEventListener('keydown', key);
  };

  return (
    <>
      <ul class="p-grid" role="list" ref={listRef}>
        {order.map((t, i) => (
          <li class="p-tile" key={t.id} data-dragging={dragId === t.id || undefined}>
            <a
              class="p-tile-link"
              href={t.link_url ?? undefined}
              target={offsite(t.link_url) ? '_blank' : undefined}
              rel={offsite(t.link_url) ? 'nofollow noopener ugc' : undefined}
            >
              {t.image_url ? (
                <img src={t.image_url} alt="" loading="lazy" />
              ) : (
                <div class="p-tile-fallback" aria-hidden="true">{t.name[0]}</div>
              )}
              <span class="p-tile-n">{t.name}</span>
              <span class="p-chip mono">{t.kind}</span>
            </a>
            {editable && (
              <>
                {mounted && (
                  <button
                    class="p-tile-grab mono"
                    type="button"
                    aria-label={`Drag to reorder ${t.name}`}
                    onPointerDown={(e) => onGrab(e, t.id)}
                  >
                    ⠿
                  </button>
                )}
                <span class="p-tile-mvs">
                  <form
                    method="POST"
                    onSubmit={(e) => {
                      e.preventDefault();
                      move(t.id, -1);
                    }}
                  >
                    <input type="hidden" name="action" value="reorder-connections" />
                    <input type="hidden" name="order" value={idsWithSwap(order, i, i - 1)} />
                    <button
                      class="p-tile-mv mono"
                      type="submit"
                      disabled={i === 0}
                      data-mv={`${t.id}|-1`}
                      aria-label={`Move ${t.name} earlier in the rotation`}
                    >
                      ◂
                    </button>
                  </form>
                  <form
                    method="POST"
                    onSubmit={(e) => {
                      e.preventDefault();
                      move(t.id, 1);
                    }}
                  >
                    <input type="hidden" name="action" value="reorder-connections" />
                    <input type="hidden" name="order" value={idsWithSwap(order, i, i + 1)} />
                    <button
                      class="p-tile-mv mono"
                      type="submit"
                      disabled={i === order.length - 1}
                      data-mv={`${t.id}|1`}
                      aria-label={`Move ${t.name} later in the rotation`}
                    >
                      ▸
                    </button>
                  </form>
                </span>
                <form method="POST">
                  <input type="hidden" name="action" value="remove-connection" />
                  <input type="hidden" name="id" value={t.id} />
                  <button class="p-tile-x mono" type="submit" aria-label={`Unpin ${t.name}`}>
                    ×
                  </button>
                </form>
              </>
            )}
          </li>
        ))}
      </ul>
      {editable && (
        <p class="visually-hidden" aria-live="polite">{live}</p>
      )}
      {msg && <p class="p-grid-msg mono">{msg}</p>}
    </>
  );
}
