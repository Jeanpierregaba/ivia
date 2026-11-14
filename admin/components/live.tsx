"use client";

import { ChevronDown } from "lucide-react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useRef, useState, useTransition } from "react";

import { cx } from "./ui";

const time = new Intl.DateTimeFormat("fr-FR", {
  timeZone: "Africa/Lome",
  hour: "2-digit",
  minute: "2-digit",
  second: "2-digit",
});

/**
 * Données en direct : relit la page (Server Components) toutes les `seconds` secondes tant que
 * l'onglet est visible, et au retour sur l'onglet. Affiche l'heure de la dernière mise à jour.
 */
export function LiveRefresh({ seconds = 30, generatedAt }: { seconds?: number; generatedAt: string }) {
  const router = useRouter();
  const [refreshing, start] = useTransition();

  useEffect(() => {
    const tick = () => {
      if (document.visibilityState === "visible") start(() => router.refresh());
    };
    const id = setInterval(tick, seconds * 1000);
    document.addEventListener("visibilitychange", tick);
    return () => {
      clearInterval(id);
      document.removeEventListener("visibilitychange", tick);
    };
  }, [router, seconds]);

  return (
    <span className="inline-flex items-center gap-2" aria-live="polite">
      <span
        aria-hidden="true"
        className={cx("size-2 rounded-full bg-success", refreshing ? "opacity-40" : "animate-live")}
      />
      données en direct · à jour à {time.format(new Date(generatedAt))}
    </span>
  );
}

const group = new Intl.NumberFormat("fr-FR", { maximumFractionDigits: 0 });

const formats = {
  int: (n: number) => group.format(n),
  xof: (n: number) => `${group.format(n)} F`,
};

/** Nombre qui défile jusqu'à sa nouvelle valeur quand les données changent. */
export function AnimatedNumber({ value, kind = "int" }: { value: number; kind?: keyof typeof formats }) {
  const format = formats[kind];
  const [shown, setShown] = useState(value);
  const from = useRef(value);

  useEffect(() => {
    const start = from.current;
    if (start === value) return;
    const t0 = performance.now();
    let raf = 0;
    const step = (t: number) => {
      const p = Math.min(1, (t - t0) / 700);
      const eased = 1 - Math.pow(1 - p, 3);
      setShown(Math.round(start + (value - start) * eased));
      if (p < 1) raf = requestAnimationFrame(step);
      else from.current = value;
    };
    raf = requestAnimationFrame(step);
    return () => cancelAnimationFrame(raf);
  }, [value]);

  return <span className="tabular-nums">{format(shown)}</span>;
}

/** Menu « Aujourd'hui ▾ » : la période est dans l'URL (partageable). */
export function PeriodMenu({
  current,
  options,
}: {
  current: string;
  options: { value: string; label: string; href: string }[];
}) {
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLDivElement>(null);
  useEffect(() => {
    const close = (e: MouseEvent) => {
      if (!ref.current?.contains(e.target as Node)) setOpen(false);
    };
    document.addEventListener("mousedown", close);
    return () => document.removeEventListener("mousedown", close);
  }, []);
  const label = options.find((o) => o.value === current)?.label ?? options[0]?.label ?? "";
  return (
    <div ref={ref} className="relative">
      <button
        type="button"
        onClick={() => setOpen((o) => !o)}
        aria-expanded={open}
        aria-haspopup="menu"
        className="flex h-[54px] items-center gap-2 rounded-[14px] bg-surface px-5 text-[14px] font-bold hover:bg-white/70"
      >
        {label}
        <ChevronDown
          size={17}
          aria-hidden="true"
          className={cx("transition-transform", open && "rotate-180")}
        />
      </button>
      {open && (
        <div
          role="menu"
          className="animate-rise absolute right-0 z-50 mt-2 w-56 overflow-hidden rounded-[14px] bg-surface py-1.5 shadow-[0_12px_32px_rgba(14,46,84,0.18)]"
        >
          {options.map((o) => (
            <Link
              key={o.value}
              role="menuitem"
              href={o.href}
              onClick={() => setOpen(false)}
              className={cx(
                "block px-4 py-2.5 text-[14px] hover:bg-background",
                o.value === current && "font-bold text-primary",
              )}
            >
              {o.label}
            </Link>
          ))}
        </div>
      )}
    </div>
  );
}
