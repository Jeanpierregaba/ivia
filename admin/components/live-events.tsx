"use client";

import { Bell, X } from "lucide-react";
import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { useEffect, useRef, useState } from "react";

import { cx } from "./ui";

/** Événement poussé par le serveur (spec 036). */
export type LiveEvent = {
  id: string;
  kind: string;
  title?: string;
  body?: string;
  data: Record<string, string>;
  at: string;
};

/** Nom de l'événement diffusé dans la page (la carte de la flotte l'écoute). */
export const LIVE_EVENT = "ivia:live";

type Toast = LiveEvent & { leaving?: boolean };

// Pages relues dès qu'une commande ou une course change (sans recharger la page).
const LIVE_PAGES = ["/", "/orders", "/ivi-orders", "/refunds", "/deliveries", "/notifications"];

function hrefOf(e: LiveEvent): string {
  if (e.kind.startsWith("platform_order")) return "/ivi-orders";
  if (e.data.order_id) return `/orders/${e.data.order_id}`;
  return "/notifications";
}

/**
 * Événements en direct du back-office : un seul flux pour tout l'onglet, reconnecté seul après
 * une coupure. Notifications en bulles douces ; pages de suivi relues aussitôt ; positions et
 * étapes diffusées à la carte de la flotte.
 */
export function LiveEvents() {
  const router = useRouter();
  const path = usePathname();
  const pathRef = useRef(path);
  const [toasts, setToasts] = useState<Toast[]>([]);
  const [online, setOnline] = useState(true);

  useEffect(() => {
    pathRef.current = path;
  }, [path]);

  useEffect(() => {
    let source: EventSource | null = null;
    let retry: ReturnType<typeof setTimeout> | undefined;
    let refresh: ReturnType<typeof setTimeout> | undefined;
    let attempt = 0;
    let closed = false;

    const scheduleRefresh = () => {
      const p = pathRef.current;
      const live = LIVE_PAGES.some((x) => (x === "/" ? p === "/" : p.startsWith(x)));
      if (!live) return;
      clearTimeout(refresh);
      refresh = setTimeout(() => router.refresh(), 600);
    };

    const connect = () => {
      if (closed) return;
      source = new EventSource("/live");
      source.onopen = () => {
        if (attempt > 0) scheduleRefresh(); // reprise : relire ce qui a pu changer
        attempt = 0;
        setOnline(true);
      };
      source.onmessage = (msg) => {
        let e: LiveEvent;
        try {
          e = JSON.parse(msg.data) as LiveEvent;
        } catch {
          return;
        }
        if (e.kind === "ready") return;
        window.dispatchEvent(new CustomEvent(LIVE_EVENT, { detail: e }));
        if (e.kind === "driver_position") return;
        if (e.title) {
          setToasts((t) => [{ ...e }, ...t.filter((x) => x.id !== e.id)].slice(0, 4));
          setTimeout(() => dismiss(e.id), 7000);
        }
        scheduleRefresh();
      };
      source.onerror = () => {
        source?.close();
        setOnline(false);
        const wait = Math.min(30_000, 1000 * 2 ** Math.min(attempt, 5));
        attempt++;
        retry = setTimeout(connect, wait);
      };
    };

    const dismiss = (id: string) => {
      setToasts((t) => t.map((x) => (x.id === id ? { ...x, leaving: true } : x)));
      setTimeout(() => setToasts((t) => t.filter((x) => x.id !== id)), 400);
    };

    connect();
    return () => {
      closed = true;
      clearTimeout(retry);
      clearTimeout(refresh);
      source?.close();
    };
  }, [router]);

  const close = (id: string) => {
    setToasts((t) => t.map((x) => (x.id === id ? { ...x, leaving: true } : x)));
    setTimeout(() => setToasts((t) => t.filter((x) => x.id !== id)), 400);
  };

  return (
    <>
      <div
        aria-live="polite"
        className="pointer-events-none fixed right-4 top-4 z-[1000] flex w-[min(380px,calc(100vw-2rem))] flex-col gap-2"
      >
        {toasts.map((t) => (
          <div
            key={t.id}
            className={cx(
              "live-toast pointer-events-auto flex items-start gap-3 rounded-[16px] bg-surface p-4 shadow-[0_22px_48px_-20px_rgba(10,26,48,0.45)] ring-1 ring-border",
              t.leaving && "is-leaving",
            )}
          >
            <span className="grid size-9 shrink-0 place-items-center rounded-full bg-primary-soft text-primary">
              <Bell size={17} aria-hidden="true" />
            </span>
            <Link href={hrefOf(t)} onClick={() => close(t.id)} className="min-w-0 flex-1">
              <p className="truncate text-[14px] font-bold">{t.title}</p>
              {t.body && <p className="mt-0.5 text-[13px] leading-[18px] text-text-secondary">{t.body}</p>}
            </Link>
            <button
              type="button"
              onClick={() => close(t.id)}
              aria-label="Fermer"
              className="grid size-7 shrink-0 place-items-center rounded-full text-text-muted hover:bg-background"
            >
              <X size={15} />
            </button>
          </div>
        ))}
      </div>
      {!online && (
        <p className="fixed bottom-4 right-4 z-[1000] rounded-full bg-tertiary px-4 py-2 text-[12px] font-semibold text-white shadow-lg">
          Reconnexion au direct…
        </p>
      )}
    </>
  );
}
