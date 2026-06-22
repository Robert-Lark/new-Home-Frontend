/** @jsxImportSource preact */
import { useEffect } from 'preact/hooks';
import { fetchStates, LISTEN_EVENT, type ListenState as LS } from '../lib/listen';

/**
 * Invisible island that recolors any static `[data-qc-ref]` cell on the page by
 * the signed-in user's listen state, writing a `data-qc-state` attribute that
 * page CSS styles. Logged-out visitors leave every cell neutral.
 *
 * Reacts to the player's `qc:listen` events (optimistic, no refetch) and to
 * ClientRouter `astro:page-load` navigations. The cells stay server-rendered
 * and cacheable — this only paints state on top.
 */
export default function ListenState() {
  useEffect(() => {
    let alive = true;

    const paintAll = async (force = false) => {
      const states = await fetchStates(force);
      if (!alive) return;
      document.querySelectorAll<HTMLElement>('[data-qc-ref]').forEach((el) => {
        const ref = el.dataset.qcRef;
        if (ref) el.dataset.qcState = states.get(ref) ?? 'unplayed';
      });
    };

    const onListen = (e: Event) => {
      const d = (e as CustomEvent).detail as { ref: string; state: LS } | undefined;
      if (!d) return;
      document
        .querySelectorAll<HTMLElement>(`[data-qc-ref="${CSS.escape(d.ref)}"]`)
        .forEach((el) => {
          el.dataset.qcState = d.state;
        });
    };

    const onPageLoad = () => void paintAll();

    void paintAll();
    document.addEventListener(LISTEN_EVENT, onListen);
    document.addEventListener('astro:page-load', onPageLoad);
    return () => {
      alive = false;
      document.removeEventListener(LISTEN_EVENT, onListen);
      document.removeEventListener('astro:page-load', onPageLoad);
    };
  }, []);

  return null;
}
