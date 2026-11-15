import Image from "next/image";

import { cx } from "./ui";

// Logotype ivia : jamais redessiné, images de la charte (mobile/packages/ui/assets/brand).
const RATIO = 678 / 336;

export type LogoColor = "white" | "imperial" | "berkeley" | "cobalt";

export function Logo({
  color,
  height = 28,
  className,
}: {
  color: LogoColor;
  height?: number;
  className?: string;
}) {
  return (
    <Image
      src={`/brand/logo_${color}.png`}
      alt="ivia"
      width={Math.round(height * RATIO)}
      height={height}
      priority
      className={className}
    />
  );
}

/** Logotype blanc dans une tuile de couleur (comme IviaLogoTile des apps). */
export function LogoTile({ size = 40, className }: { size?: number; className?: string }) {
  return (
    <span
      className={cx("inline-grid place-items-center bg-primary", className)}
      style={{ width: size, height: size, borderRadius: size * 0.26 }}
    >
      <Logo color="white" height={Math.round(size * 0.3)} />
    </span>
  );
}
