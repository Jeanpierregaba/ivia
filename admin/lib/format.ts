// Formats d'affichage (docs/DESIGN.md, « Ton et microcopie ») : heure de Lomé, FCFA sans décimales.

const LOME = "Africa/Lome";

const money = new Intl.NumberFormat("fr-FR", { maximumFractionDigits: 0 });

/** 12500 → « 12 500 FCFA » (espace fine insécable entre les milliers). */
export function formatXOF(amount: number): string {
  return `${money.format(amount)} FCFA`;
}

const dateTime = new Intl.DateTimeFormat("fr-FR", {
  timeZone: LOME,
  day: "numeric",
  month: "short",
  year: "numeric",
  hour: "2-digit",
  minute: "2-digit",
});

/** Date et heure à Lomé ; tiret si absente. */
export function formatDateTime(iso: string | null | undefined): string {
  if (!iso) return "—";
  return dateTime.format(new Date(iso));
}

/** Date du jour à Lomé au format AAAA-MM-JJ (périodes des rapports). */
export function lomeDate(d: Date): string {
  return new Intl.DateTimeFormat("en-CA", { timeZone: LOME }).format(d);
}

/** +22890123456 → « +228 90 12 34 56 ». */
export function formatPhone(phone: string | null | undefined): string {
  if (!phone) return "—";
  const m = /^\+228(\d{2})(\d{2})(\d{2})(\d{2})$/.exec(phone);
  return m ? `+228 ${m[1]} ${m[2]} ${m[3]} ${m[4]}` : phone;
}

export type Tone = "success" | "warning" | "info" | "error" | "muted";

/** Libellés des statuts de commande (docs/DESIGN.md, « Libellés des statuts »). */
export const ORDER_STATUS: Record<string, { label: string; tone: Tone }> = {
  pending_payment: { label: "En attente de paiement", tone: "warning" },
  expired: { label: "Paiement expiré", tone: "muted" },
  awaiting_seller: { label: "En attente de la boutique", tone: "warning" },
  accepted: { label: "Acceptée par la boutique", tone: "info" },
  preparing: { label: "En préparation", tone: "info" },
  ready_for_pickup: { label: "Prête à retirer", tone: "success" },
  completed: { label: "Retirée", tone: "success" },
  awaiting_driver: { label: "Recherche d'un livreur", tone: "info" },
  driver_assigned: { label: "Livreur en route vers la boutique", tone: "info" },
  picked_up: { label: "En cours de livraison", tone: "info" },
  delivered: { label: "Livrée", tone: "success" },
  delivery_failed: { label: "Livraison échouée", tone: "error" },
  returned_to_shop: { label: "Retournée à la boutique", tone: "muted" },
  cancelled: { label: "Annulée", tone: "error" },
  refunded: { label: "Remboursée", tone: "muted" },
};

export const SHOP_STATUS: Record<string, { label: string; tone: Tone }> = {
  pending_review: { label: "À valider", tone: "warning" },
  published: { label: "Publiée", tone: "success" },
  rejected: { label: "Refusée", tone: "error" },
  suspended: { label: "Suspendue", tone: "error" },
};

export const DRIVER_STATUS: Record<string, { label: string; tone: Tone }> = {
  pending_review: { label: "À valider", tone: "warning" },
  rejected: { label: "Refusé", tone: "error" },
  suspended: { label: "Suspendu", tone: "error" },
  offline: { label: "Hors ligne", tone: "muted" },
  available: { label: "Disponible", tone: "success" },
  busy: { label: "En mission", tone: "info" },
};

export const DOCUMENT_KIND: Record<string, string> = {
  id_card: "Pièce d'identité",
  driving_license: "Permis de conduire",
  vehicle_registration: "Carte grise",
  photo: "Photo",
  other: "Autre document",
};

export const VEHICLE: Record<string, string> = { motorbike: "Moto", car: "Voiture" };

export function statusOf(map: Record<string, { label: string; tone: Tone }>, code: string) {
  return map[code] ?? { label: code, tone: "muted" as Tone };
}

/** Statuts de paiement (ADR 0004). */
export const PAYMENT_STATUS: Record<string, { label: string; tone: Tone }> = {
  pending: { label: "En attente", tone: "warning" },
  succeeded: { label: "Reçu", tone: "success" },
  failed: { label: "Échoué", tone: "error" },
  expired: { label: "Expiré", tone: "muted" },
  refund_pending: { label: "Remboursement en cours", tone: "warning" },
  refunded: { label: "Remboursé", tone: "info" },
};

/** Libellés des actions du journal d'audit (identifiant technique affiché si inconnu). */
export const AUDIT_ACTION: Record<string, string> = {
  "shop.approve": "Boutique publiée",
  "shop.reject": "Boutique refusée",
  "shop.suspend": "Boutique suspendue",
  "shop.reinstate": "Boutique rétablie",
  "driver.approve": "Livreur validé",
  "driver.reject": "Livreur refusé",
  "driver.suspend": "Livreur suspendu",
  "driver.reinstate": "Livreur rétabli",
  "order.cancel": "Commande annulée",
  "order.confirm_return": "Retour en boutique confirmé",
  "order.unassign_driver": "Livreur retiré",
  "order.unlock_handover": "Code de remise débloqué",
  "payment.refund_requested": "Remboursement demandé",
  "settings.update": "Paramètres modifiés",
  "settlement.create": "Reversement créé",
  "settlement.delete": "Reversement supprimé",
  "settlement.mark_settled": "Reversement effectué",
  "category.create": "Catégorie de produits créée",
  "category.update": "Catégorie de produits modifiée",
  "shop_category.create": "Catégorie de boutiques créée",
  "shop_category.update": "Catégorie de boutiques modifiée",
  "neighborhood.create": "Quartier créé",
  "neighborhood.update": "Quartier modifié",
  "user.grant_admin": "Droits admin accordés",
  "user.revoke_admin": "Droits admin retirés",
};
