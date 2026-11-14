import type { NextConfig } from "next";

// Sortie autonome : image Docker légère, hébergée sur le même VPS que l'API (ADR 0003).
const nextConfig: NextConfig = {
  output: "standalone",
  poweredByHeader: false,
  // Images publicitaires et photos de produits envoyées par les Server Actions (5 Mo chacune).
  experimental: { serverActions: { bodySizeLimit: "24mb" } },
  async headers() {
    return [
      {
        source: "/:path*",
        headers: [
          { key: "X-Frame-Options", value: "DENY" },
          { key: "X-Content-Type-Options", value: "nosniff" },
          // Origine seule (jamais le chemin) : Google Maps vérifie que la clé vient du back-office.
          { key: "Referrer-Policy", value: "strict-origin" },
        ],
      },
    ];
  },
};

export default nextConfig;
