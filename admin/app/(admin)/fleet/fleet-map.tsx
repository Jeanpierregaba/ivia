"use client";

import "leaflet/dist/leaflet.css";

import { Bike, Car, Crosshair, Lock, MapPin, Phone, Route, Search } from "lucide-react";
import Link from "next/link";
import { useEffect, useMemo, useRef, useState } from "react";

import { LIVE_EVENT, type LiveEvent } from "@/components/live-events";
import { cx } from "@/components/ui";
import { createEngine, type MapEngine } from "./map-engines";

export type FleetDriver = {
  id: string;
  first_name: string;
  phone: string;
  availability: string;
  vehicle_type: string;
  vehicle_plate: string;
  suspended: boolean;
  lat: number;
  lng: number;
  located_at: string;
  mission_order_id?: string | null;
  mission_status: string;
};
type TrailPoint = { lat: number; lng: number; recorded_at: string };

const REFRESH_MS = 30_000;
const STALE_MS = 10 * 60_000;

const time = new Intl.DateTimeFormat("fr-FR", {
  timeZone: "Africa/Lome",
  hour: "2-digit",
  minute: "2-digit",
});

type Look = { label: string; color: string; ring: string };
function lookOf(d: FleetDriver, now: number): Look {
  if (d.suspended) return { label: "Suspendu", color: "#6b7280", ring: "#d1d5db" };
  const stale = now - new Date(d.located_at).getTime() > STALE_MS;
  if (d.availability === "offline" || stale)
    return { label: "Hors ligne", color: "#94a3b8", ring: "#e2e8f0" };
  if (d.mission_order_id || d.availability === "busy")
    return { label: "En course", color: "#ed1c2f", ring: "#fde8ea" };
  return { label: "Disponible", color: "#1e7a4c", ring: "#e6f2ec" };
}

const MISSION: Record<string, string> = {
  assigned: "course acceptée, vers la boutique",
  at_shop: "à la boutique",
  picked_up: "vers le client",
  at_customer: "chez le client",
  returning: "retour boutique",
};

function ago(iso: string, now: number) {
  const s = Math.max(0, Math.round((now - new Date(iso).getTime()) / 1000));
  if (s < 60) return `il y a ${s} s`;
  if (s < 3600) return `il y a ${Math.round(s / 60)} min`;
  return `à ${time.format(new Date(iso))}`;
}

function markerHtml(d: FleetDriver, look: Look, selected: boolean) {
  const moto = d.vehicle_type !== "car";
  const icon = moto
    ? '<path d="M5 17a3 3 0 1 0 0-6 3 3 0 0 0 0 6Zm14 0a3 3 0 1 0 0-6 3 3 0 0 0 0 6ZM12 17h-2l-2-6h4l3-3h3M15 8l2 3"/>'
    : '<path d="M5 17h14M6 17v2m12-2v2M4 13l2-5h12l2 5v4H4v-4Z"/>';
  const initial = (d.first_name.trim()[0] ?? "?").toUpperCase();
  return `<div class="fleet-pin${selected ? " is-selected" : ""}" style="--c:${look.color};--r:${look.ring}">
    <span class="fleet-pulse"></span>
    <span class="fleet-dot"><svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="white" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">${icon}</svg></span>
    <span class="fleet-name">${initial}</span>
  </div>`;
}

/**
 * Carte en direct de la flotte : positions envoyées par l'app livreur (rafraîchies toutes les
 * 10 s, déplacement animé), filtres, fiche du livreur et trajet récent (point de départ marqué).
 * Les boîtiers GPS des engins (suivi et blocage à distance) viendront compléter cette carte.
 */
export function FleetMap({
  initial,
  generatedAt,
  googleKey,
}: {
  initial: FleetDriver[];
  generatedAt: string;
  googleKey?: string;
}) {
  const box = useRef<HTMLDivElement>(null);
  const engine = useRef<MapEngine | null>(null);
  const [engineKind, setEngineKind] = useState<MapEngine["kind"] | null>(null);
  const [drivers, setDrivers] = useState(initial);
  const [now, setNow] = useState(() => new Date(generatedAt).getTime());
  const [filter, setFilter] = useState<"all" | "available" | "busy" | "offline">("all");
  const [query, setQuery] = useState("");
  const [selected, setSelected] = useState<string | null>(null);
  const [trail, setTrail] = useState<TrailPoint[] | null>(null);
  const [trailHours, setTrailHours] = useState(6);
  const [error, setError] = useState<string | null>(null);
  const driversRef = useRef(drivers);
  const selectedRef = useRef(selected);
  useEffect(() => {
    driversRef.current = drivers;
    selectedRef.current = selected;
  }, [drivers, selected]);

  const refreshFleet = async () => {
    try {
      const res = await fetch("/fleet/data?hours=24", { cache: "no-store" });
      if (!res.ok) throw new Error();
      setDrivers(((await res.json()) as { items: FleetDriver[] }).items);
      setNow(Date.now());
      setError(null);
    } catch {
      setError("Connexion perdue, nouvel essai dans quelques secondes…");
    }
  };

  // Carte créée une fois, côté navigateur : Google Maps, ou OpenStreetMap en secours.
  useEffect(() => {
    let cancelled = false;
    const use = (p: Promise<MapEngine>) =>
      void p.then((e) => {
        if (cancelled) return e.destroy();
        engine.current?.destroy();
        engine.current = e;
        setEngineKind(e.kind);
      });
    if (box.current) use(createEngine(box.current, googleKey, use));
    return () => {
      cancelled = true;
      engine.current?.destroy();
      engine.current = null;
    };
  }, [googleKey]);

  // Positions et étapes poussées par le serveur (flux du back-office, spec 036) : le marqueur
  // avance aussitôt ; une étape ou un statut relit la flotte.
  useEffect(() => {
    let reload: ReturnType<typeof setTimeout> | undefined;
    const onLive = (ev: Event) => {
      const e = (ev as CustomEvent<LiveEvent>).detail;
      if (e.kind === "driver_position") {
        const lat = Number(e.data.lat);
        const lng = Number(e.data.lng);
        if (!Number.isFinite(lat) || !Number.isFinite(lng)) return;
        setDrivers((list) =>
          list.map((d) =>
            d.id === e.data.driver_id
              ? {
                  ...d,
                  lat,
                  lng,
                  located_at: e.at,
                  availability: e.data.status ?? d.availability,
                  mission_order_id: e.data.order_id ?? d.mission_order_id,
                }
              : d,
          ),
        );
        setNow(Date.now());
        // Livreur pas encore sur la carte : relire la flotte.
        if (!driversRef.current.some((d) => d.id === e.data.driver_id)) {
          clearTimeout(reload);
          reload = setTimeout(() => void refreshFleet(), 500);
        }
        if (e.data.driver_id === selectedRef.current) {
          setTrail((t) => (t ? [...t, { lat, lng, recorded_at: e.at }] : t));
        }
        return;
      }
      if (e.kind === "delivery_step" || e.kind === "order_status") {
        clearTimeout(reload);
        reload = setTimeout(() => void refreshFleet(), 400);
      }
    };
    window.addEventListener(LIVE_EVENT, onLive);
    return () => {
      clearTimeout(reload);
      window.removeEventListener(LIVE_EVENT, onLive);
    };
  }, []);

  // Relecture de secours tant que l'onglet est visible.
  useEffect(() => {
    const tick = async () => {
      if (document.visibilityState !== "visible") return;
      try {
        const res = await fetch("/fleet/data?hours=24", { cache: "no-store" });
        if (!res.ok) throw new Error();
        const body = (await res.json()) as { items: FleetDriver[] };
        setDrivers(body.items);
        setNow(Date.now());
        setError(null);
      } catch {
        setError("Connexion perdue, nouvel essai dans quelques secondes…");
      }
    };
    const id = setInterval(tick, REFRESH_MS);
    document.addEventListener("visibilitychange", tick);
    return () => {
      clearInterval(id);
      document.removeEventListener("visibilitychange", tick);
    };
  }, []);

  // Marqueurs : ajoutés, déplacés en douceur, retirés.
  useEffect(() => {
    const e = engine.current;
    if (!e) return;
    const seen = new Set<string>();
    for (const d of drivers) {
      seen.add(d.id);
      e.upsert(d.id, { lat: d.lat, lng: d.lng }, markerHtml(d, lookOf(d, now), d.id === selected), () =>
        setSelected(d.id),
      );
    }
    for (const id of e.ids()) if (!seen.has(id)) e.remove(id);
  }, [drivers, now, selected, engineKind]);

  // Trajet du livreur choisi.
  useEffect(() => {
    if (!selected) return;
    let live = true;
    fetch(`/fleet/data?trail=${selected}&hours=${trailHours}`, { cache: "no-store" })
      .then((res) =>
        res.ok ? (res.json() as Promise<{ items: TrailPoint[] }>) : Promise.reject(new Error()),
      )
      .then((body) => live && setTrail(body.items))
      .catch(() => live && setTrail([]));
    return () => {
      live = false;
    };
  }, [selected, trailHours]);

  useEffect(() => {
    engine.current?.trail(trail);
  }, [trail, engineKind]);

  const focus = (d: FleetDriver) => {
    if (d.id !== selected) setTrail(null);
    setSelected(d.id);
    engine.current?.focus({ lat: d.lat, lng: d.lng }, 16);
  };

  const counts = useMemo(() => {
    const c = { all: drivers.length, available: 0, busy: 0, offline: 0 };
    for (const d of drivers) {
      const l = lookOf(d, now).label;
      if (l === "Disponible") c.available++;
      else if (l === "En course") c.busy++;
      else c.offline++;
    }
    return c;
  }, [drivers, now]);

  const shown = drivers.filter((d) => {
    const l = lookOf(d, now).label;
    if (filter === "available" && l !== "Disponible") return false;
    if (filter === "busy" && l !== "En course") return false;
    if (filter === "offline" && l !== "Hors ligne" && l !== "Suspendu") return false;
    const q = query.trim().toLowerCase();
    return !q || d.first_name.toLowerCase().includes(q) || d.vehicle_plate.toLowerCase().includes(q);
  });
  const current = drivers.find((d) => d.id === selected) ?? null;

  return (
    <div className="grid gap-4 xl:grid-cols-[minmax(0,1fr)_360px]">
      <div className="relative overflow-hidden rounded-field bg-surface shadow-[0_18px_40px_-28px_rgba(14,46,84,0.45)]">
        <div ref={box} className="h-[62vh] min-h-[420px] w-full xl:h-[calc(100vh-220px)]" />
        <div className="pointer-events-none absolute left-4 top-4 z-[500] flex flex-wrap gap-2">
          {(
            [
              ["all", "Tous", "#0e2e54"],
              ["available", "Disponibles", "#1e7a4c"],
              ["busy", "En course", "#ed1c2f"],
              ["offline", "Hors ligne", "#94a3b8"],
            ] as const
          ).map(([v, label, color]) => (
            <button
              key={v}
              type="button"
              onClick={() => setFilter(v)}
              className={cx(
                "pointer-events-auto inline-flex h-9 items-center gap-2 rounded-full px-3.5 text-[13px] font-bold shadow-md backdrop-blur transition-all duration-300 active:scale-95",
                filter === v ? "bg-tertiary text-white" : "bg-white/90 text-text hover:bg-white",
              )}
            >
              <span className="size-2.5 rounded-full" style={{ background: color }} />
              {label}
              <span className="tabular-nums opacity-70">{counts[v]}</span>
            </button>
          ))}
        </div>
        {engineKind && (
          <span className="pointer-events-none absolute bottom-4 left-4 z-[500] rounded-full bg-white/90 px-3 py-1 text-[11px] font-semibold text-text-muted shadow">
            {engineKind === "google" ? "Google Maps" : "OpenStreetMap"}
          </span>
        )}
        {error && (
          <p className="absolute bottom-12 left-4 z-[500] rounded-full bg-primary-soft px-4 py-2 text-[13px] font-semibold text-error shadow">
            {error}
          </p>
        )}
      </div>

      <aside className="flex min-h-0 flex-col gap-4">
        {current ? (
          <section className="animate-rise rounded-field bg-surface p-5">
            <div className="flex items-start justify-between gap-3">
              <div className="min-w-0">
                <p className="text-[17px] font-extrabold">{current.first_name || "Livreur"}</p>
                <p className="mt-0.5 flex items-center gap-1.5 text-[13px] text-text-muted">
                  {current.vehicle_type === "car" ? <Car size={14} /> : <Bike size={14} />}
                  {current.vehicle_type === "car" ? "Voiture" : "Moto"}
                  {current.vehicle_plate && ` · ${current.vehicle_plate}`}
                </p>
              </div>
              <span
                className="shrink-0 rounded-full px-2.5 py-0.5 text-[12px] font-bold"
                style={{ background: lookOf(current, now).ring, color: lookOf(current, now).color }}
              >
                {lookOf(current, now).label}
              </span>
            </div>
            <dl className="mt-4 space-y-2 text-[13px]">
              <div className="flex justify-between gap-3">
                <dt className="text-text-muted">Dernière position</dt>
                <dd className="font-semibold">{ago(current.located_at, now)}</dd>
              </div>
              {current.mission_order_id && (
                <div className="flex justify-between gap-3">
                  <dt className="text-text-muted">Course</dt>
                  <dd className="font-semibold">
                    <Link
                      className="text-secondary hover:underline"
                      href={`/orders/${current.mission_order_id}`}
                    >
                      {MISSION[current.mission_status] ?? "en cours"}
                    </Link>
                  </dd>
                </div>
              )}
            </dl>
            <div className="mt-4 flex flex-wrap items-center gap-2">
              <span className="inline-flex items-center gap-1.5 text-[13px] font-semibold text-text-secondary">
                <Route size={15} /> Trajet
              </span>
              {[1, 6, 24, 72].map((h) => (
                <button
                  key={h}
                  type="button"
                  onClick={() => setTrailHours(h)}
                  className={cx(
                    "h-8 rounded-full px-3 text-[12px] font-bold transition-colors",
                    trailHours === h ? "bg-secondary text-white" : "bg-background hover:bg-secondary-soft",
                  )}
                >
                  {h < 24 ? `${h} h` : `${h / 24} j`}
                </button>
              ))}
            </div>
            <p className="mt-2 text-[12px] text-text-muted">
              {trail === null
                ? "Chargement du trajet…"
                : trail.length < 2
                  ? "Pas de déplacement enregistré sur cette période."
                  : `${trail.length} positions, départ à ${time.format(new Date(trail[0]!.recorded_at))}.`}
            </p>
            <div className="mt-4 grid grid-cols-2 gap-2">
              {current.phone && (
                <a
                  href={`tel:${current.phone}`}
                  className="inline-flex h-10 items-center justify-center gap-2 rounded-full bg-background text-[13px] font-bold hover:bg-secondary-soft"
                >
                  <Phone size={15} /> Appeler
                </a>
              )}
              <Link
                href={`/drivers/${current.id}`}
                className="inline-flex h-10 items-center justify-center gap-2 rounded-full bg-background text-[13px] font-bold hover:bg-secondary-soft"
              >
                <MapPin size={15} /> Fiche
              </Link>
              <button
                type="button"
                disabled
                title="Disponible dès que les boîtiers GPS des engins seront connectés"
                className="col-span-2 inline-flex h-10 cursor-not-allowed items-center justify-center gap-2 rounded-full border border-dashed border-border-input text-[13px] font-bold text-text-muted"
              >
                <Lock size={15} /> Bloquer l&apos;engin · bientôt
              </button>
            </div>
            <button
              type="button"
              onClick={() => {
                setSelected(null);
                setTrail(null);
              }}
              className="mt-3 w-full text-[13px] font-semibold text-text-muted hover:text-text"
            >
              Fermer
            </button>
          </section>
        ) : (
          <section className="rounded-field bg-surface p-5 text-[13px] text-text-secondary">
            Choisissez un livreur sur la carte ou dans la liste pour voir son trajet et sa course.
          </section>
        )}

        <section className="flex min-h-0 flex-1 flex-col rounded-field bg-surface p-4">
          <label className="relative mb-3 block">
            <Search
              size={16}
              className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-text-muted"
            />
            <span className="sr-only">Rechercher un livreur</span>
            <input
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder="Prénom ou plaque…"
              className="h-10 w-full rounded-[12px] bg-background pl-9 pr-3 text-[14px] outline-none focus:shadow-[inset_0_0_0_2px_var(--color-primary)]"
            />
          </label>
          <ul className="-mx-1 max-h-[46vh] space-y-1 overflow-y-auto px-1">
            {shown.length === 0 && (
              <li className="py-6 text-center text-[13px] text-text-muted">Aucun livreur à afficher.</li>
            )}
            {shown.map((d) => {
              const look = lookOf(d, now);
              return (
                <li key={d.id}>
                  <button
                    type="button"
                    onClick={() => focus(d)}
                    className={cx(
                      "flex w-full items-center gap-3 rounded-[12px] px-3 py-2.5 text-left transition-all duration-300 hover:bg-background active:scale-[0.98]",
                      selected === d.id && "bg-secondary-soft",
                    )}
                  >
                    <span
                      className="grid size-9 shrink-0 place-items-center rounded-full text-white"
                      style={{ background: look.color }}
                    >
                      {d.vehicle_type === "car" ? <Car size={16} /> : <Bike size={16} />}
                    </span>
                    <span className="min-w-0 flex-1">
                      <span className="block truncate text-[14px] font-bold">
                        {d.first_name || "Livreur"}
                      </span>
                      <span className="block text-[12px] text-text-muted">
                        {look.label}
                        {d.mission_status && ` · ${MISSION[d.mission_status] ?? ""}`} ·{" "}
                        {ago(d.located_at, now)}
                      </span>
                    </span>
                    <Crosshair size={15} className="shrink-0 text-text-muted" />
                  </button>
                </li>
              );
            })}
          </ul>
        </section>
      </aside>
    </div>
  );
}
