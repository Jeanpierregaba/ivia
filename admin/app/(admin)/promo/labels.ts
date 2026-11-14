// Libellés de la publicité (visuels, emplacements, apps, badges).

export const KINDS: Record<string, { label: string; hint: string }> = {
  banner: { label: "Bannière", hint: "Carrousel d'accueil et listes" },
  modal: { label: "Fenêtre", hint: "S'ouvre pendant la navigation, fermable" },
  interstitial: { label: "Interstitiel", hint: "Page plein écran entre deux écrans" },
  welcome: { label: "Bienvenue", hint: "À l'ouverture de l'app" },
  monthly: { label: "Visuel du mois", hint: "Mis en avant sur sa période" },
  poster: { label: "Affiche", hint: "Visuel libre (événement, annonce)" },
};

export const PLACEMENTS: Record<string, string> = {
  home_hero: "Accueil — carrousel",
  home_feed: "Accueil — fil",
  catalog_feed: "Catalogue et recherche",
  modal: "Fenêtre pendant la navigation",
  interstitial: "Interstitiel plein écran",
  splash: "Ouverture de l'app",
};

export const APPS: Record<string, string> = { buyer: "Acheteur", seller: "Marchand", driver: "Livreur" };

export const BADGES: Record<string, string> = {
  promotion: "Promotion",
  special_offer: "Offre spéciale",
  featured: "Produit vedette",
  best_seller: "Meilleure vente",
};

export const ROTATIONS: Record<string, string> = {
  weighted: "Pondérée (selon le poids de chaque visuel)",
  random: "Aléatoire",
  priority: "Par priorité",
};

/** Valeur d'un champ datetime-local (heure de Lomé = UTC). */
export function localInput(iso: string | null | undefined): string {
  return iso ? iso.slice(0, 16) : "";
}

export function pct(v: number): string {
  return `${v.toLocaleString("fr-FR", { maximumFractionDigits: 1 })} %`;
}
