/// <reference types="google.maps" />

// Moteurs de la carte de la flotte, derrière une même interface : Google Maps (affichage, même clé
// navigateur que les apps), OpenStreetMap avec Leaflet en secours (pas de clé, ou Google qui ne
// charge pas). Les calculs restent côté serveur (ADR 0013).

export type LatLng = { lat: number; lng: number };

export interface MapEngine {
  readonly kind: "google" | "osm";
  /** Ajoute ou met à jour un marqueur HTML (déplacé en douceur). */
  upsert(id: string, at: LatLng, html: string, onClick: () => void): void;
  remove(id: string): void;
  ids(): string[];
  /** Trajet avec son point de départ ; null l'efface. */
  trail(points: LatLng[] | null): void;
  focus(at: LatLng, zoom: number): void;
  destroy(): void;
}

const LOME: LatLng = { lat: 6.1725, lng: 1.2314 };
const TRAIL = "#004da8";
const ORIGIN_HTML = '<div class="fleet-origin">Départ</div>';

function ease(from: LatLng, to: LatLng, apply: (p: LatLng) => void) {
  if (Math.abs(from.lat - to.lat) < 1e-7 && Math.abs(from.lng - to.lng) < 1e-7) return;
  const start = performance.now();
  const step = (t: number) => {
    const k = Math.min(1, (t - start) / 1200);
    const e = 1 - Math.pow(1 - k, 3);
    apply({ lat: from.lat + (to.lat - from.lat) * e, lng: from.lng + (to.lng - from.lng) * e });
    if (k < 1) requestAnimationFrame(step);
  };
  requestAnimationFrame(step);
}

// --- Google Maps -------------------------------------------------------------------------------

let googleLoad: Promise<void> | null = null;

/** Charge l'API JavaScript de Google Maps une fois ; échoue si la clé est refusée ou trop lente. */
function loadGoogle(key: string): Promise<void> {
  if (typeof window !== "undefined" && window.google?.maps?.Map) return Promise.resolve();
  googleLoad ??= new Promise<void>((resolve, reject) => {
    const w = window as unknown as Record<string, unknown>;
    const timer = setTimeout(() => reject(new Error("délai")), 10_000);
    w.__iviaMapsReady = () => {
      clearTimeout(timer);
      resolve();
    };
    w.gm_authFailure = () => reject(new Error("clé refusée"));
    const s = document.createElement("script");
    s.src = `https://maps.googleapis.com/maps/api/js?key=${encodeURIComponent(key)}&v=weekly&language=fr&region=TG&callback=__iviaMapsReady`;
    s.async = true;
    s.onerror = () => reject(new Error("réseau"));
    document.head.appendChild(s);
  }).catch((err: unknown) => {
    googleLoad = null;
    throw err;
  });
  return googleLoad;
}

// Fond doux : moins de points d'intérêt, routes lisibles.
const STYLE: google.maps.MapTypeStyle[] = [
  { featureType: "poi", elementType: "labels", stylers: [{ visibility: "off" }] },
  { featureType: "poi.business", stylers: [{ visibility: "off" }] },
  { featureType: "transit", elementType: "labels.icon", stylers: [{ visibility: "off" }] },
  { featureType: "water", stylers: [{ color: "#cfe3f5" }] },
  { featureType: "landscape", stylers: [{ color: "#f3f4f6" }] },
];

async function googleEngine(box: HTMLElement, key: string, onAuthFailure: () => void): Promise<MapEngine> {
  await loadGoogle(key);
  (window as unknown as Record<string, unknown>).gm_authFailure = onAuthFailure;
  const g = google.maps;
  const map = new g.Map(box, {
    center: LOME,
    zoom: 13,
    styles: STYLE,
    disableDefaultUI: true,
    zoomControl: true,
    fullscreenControl: true,
    gestureHandling: "greedy",
    clickableIcons: false,
  });

  /** Marqueur HTML (mêmes pastilles animées que la version OpenStreetMap). */
  class HtmlMarker extends g.OverlayView {
    readonly div = document.createElement("div");
    constructor(
      public pos: LatLng,
      html: string,
      private anchor: [number, number],
      onClick?: () => void,
    ) {
      super();
      this.div.style.position = "absolute";
      this.div.style.cursor = onClick ? "pointer" : "default";
      this.div.innerHTML = html;
      if (onClick) this.div.addEventListener("click", onClick);
      this.setMap(map);
    }
    onAdd() {
      this.getPanes()?.overlayMouseTarget.appendChild(this.div);
    }
    draw() {
      const p = this.getProjection()?.fromLatLngToDivPixel(this.pos);
      if (!p) return;
      this.div.style.left = `${p.x - this.anchor[0]}px`;
      this.div.style.top = `${p.y - this.anchor[1]}px`;
    }
    onRemove() {
      this.div.remove();
    }
    move(to: LatLng) {
      ease(this.pos, to, (p) => {
        this.pos = p;
        this.draw();
      });
    }
  }

  const markers = new Map<string, HtmlMarker>();
  let line: google.maps.Polyline | null = null;
  let origin: HtmlMarker | null = null;

  return {
    kind: "google",
    upsert(id, at, html, onClick) {
      const m = markers.get(id);
      if (!m) {
        markers.set(id, new HtmlMarker(at, html, [22, 22], onClick));
        return;
      }
      if (m.div.innerHTML !== html) m.div.innerHTML = html;
      m.move(at);
    },
    remove(id) {
      markers.get(id)?.setMap(null);
      markers.delete(id);
    },
    ids: () => [...markers.keys()],
    trail(points) {
      line?.setMap(null);
      origin?.setMap(null);
      line = null;
      origin = null;
      if (!points || points.length < 2) return;
      line = new g.Polyline({
        path: points,
        map,
        strokeColor: TRAIL,
        strokeOpacity: 0.9,
        strokeWeight: 5,
        icons: [
          {
            icon: { path: g.SymbolPath.FORWARD_CLOSED_ARROW, scale: 2.6, strokeColor: TRAIL, fillOpacity: 1 },
            offset: "60px",
            repeat: "140px",
          },
        ],
      });
      origin = new HtmlMarker(points[0]!, ORIGIN_HTML, [32, 13]);
      const b = new g.LatLngBounds();
      for (const p of points) b.extend(p);
      map.fitBounds(b, 60);
    },
    focus(at, zoom) {
      map.panTo(at);
      if ((map.getZoom() ?? 0) < zoom) map.setZoom(zoom);
    },
    destroy() {
      for (const m of markers.values()) m.setMap(null);
      markers.clear();
      line?.setMap(null);
      origin?.setMap(null);
    },
  };
}

// --- OpenStreetMap (Leaflet) ---------------------------------------------------------------------

async function osmEngine(box: HTMLElement): Promise<MapEngine> {
  const L = await import("leaflet");
  const map = L.map(box, { zoomControl: false }).setView([LOME.lat, LOME.lng], 13);
  L.tileLayer("https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png", {
    maxZoom: 19,
    subdomains: "abcd",
    attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> &copy; CARTO',
  }).addTo(map);
  L.control.zoom({ position: "bottomright" }).addTo(map);
  const icon = (html: string, size: [number, number]) =>
    L.divIcon({ html, className: "", iconSize: size, iconAnchor: [size[0] / 2, size[1] / 2] });
  const markers = new Map<string, { m: import("leaflet").Marker; html: string }>();
  let line: import("leaflet").Polyline | null = null;
  let origin: import("leaflet").Marker | null = null;

  return {
    kind: "osm",
    upsert(id, at, html, onClick) {
      const cur = markers.get(id);
      if (!cur) {
        const m = L.marker([at.lat, at.lng], { icon: icon(html, [44, 44]), riseOnHover: true })
          .addTo(map)
          .on("click", onClick);
        markers.set(id, { m, html });
        return;
      }
      if (cur.html !== html) {
        cur.m.setIcon(icon(html, [44, 44]));
        cur.html = html;
      }
      ease(cur.m.getLatLng(), at, (p) => cur.m.setLatLng([p.lat, p.lng]));
    },
    remove(id) {
      markers.get(id)?.m.remove();
      markers.delete(id);
    },
    ids: () => [...markers.keys()],
    trail(points) {
      line?.remove();
      origin?.remove();
      line = null;
      origin = null;
      if (!points || points.length < 2) return;
      const pts = points.map((p) => [p.lat, p.lng] as [number, number]);
      line = L.polyline(pts, {
        color: TRAIL,
        weight: 5,
        opacity: 0.85,
        lineCap: "round",
        lineJoin: "round",
      }).addTo(map);
      origin = L.marker(pts[0]!, { icon: icon(ORIGIN_HTML, [64, 26]) }).addTo(map);
      map.flyToBounds(line.getBounds(), { padding: [60, 60], duration: 1.1 });
    },
    focus(at, zoom) {
      map.flyTo([at.lat, at.lng], Math.max(map.getZoom(), zoom), { duration: 1.1 });
    },
    destroy() {
      map.remove();
      markers.clear();
    },
  };
}

/** Google Maps si une clé est donnée et qu'elle fonctionne, sinon OpenStreetMap. */
export async function createEngine(
  box: HTMLElement,
  googleKey: string | undefined,
  onFallback: (engine: Promise<MapEngine>) => void,
): Promise<MapEngine> {
  if (googleKey) {
    try {
      return await googleEngine(box, googleKey, () => {
        // Clé refusée après coup (domaine non autorisé) : bascule sur OpenStreetMap.
        box.innerHTML = "";
        onFallback(osmEngine(box));
      });
    } catch {
      box.innerHTML = "";
    }
  }
  return osmEngine(box);
}
