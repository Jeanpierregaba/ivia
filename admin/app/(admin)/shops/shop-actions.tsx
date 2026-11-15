import { ActionForm } from "@/components/action-form";
import type { Schemas } from "@/lib/api";
import { reviewShop } from "./actions";

/** Pièces sans lesquelles l'API refuse la publication (`merchant_documents_missing`). */
export const REQUIRED_MERCHANT_DOCUMENTS: Schemas["MerchantDocument"]["kind"][] = ["id_card"];

export function missingMerchantDocuments(shop: Schemas["Shop"]): Schemas["MerchantDocument"]["kind"][] {
  const kinds = new Set(shop.merchant_documents.map((d) => d.kind));
  return REQUIRED_MERCHANT_DOCUMENTS.filter((k) => !kinds.has(k));
}

/** Décisions possibles selon le statut : publier, refuser, suspendre, rétablir. */
export function ShopActions({ shop }: { shop: Schemas["Shop"] }) {
  const hidden = (decision: string) => ({ id: shop.id, decision });
  const incomplete = missingMerchantDocuments(shop).length > 0;
  return (
    <div className="flex flex-wrap gap-2">
      {(shop.status === "pending_review" || shop.status === "rejected") && !incomplete && (
        <ActionForm
          action={reviewShop}
          label="Publier"
          hidden={hidden("approve")}
          confirm={{
            title: `Publier « ${shop.name} » ?`,
            body: "Après vérification de la pièce d'identité du marchand, la boutique devient visible des acheteurs et peut vendre.",
          }}
        />
      )}
      {shop.status === "pending_review" && (
        <ActionForm
          action={reviewShop}
          label="Refuser"
          variant="outline"
          hidden={hidden("reject")}
          confirm={{ title: `Refuser « ${shop.name} » ?`, body: "Le motif est communiqué au marchand." }}
          reason={{ label: "Motif du refus", required: true }}
        />
      )}
      {shop.status === "published" && (
        <ActionForm
          action={reviewShop}
          label="Suspendre"
          variant="danger"
          hidden={hidden("suspend")}
          confirm={{
            title: `Suspendre « ${shop.name} » ?`,
            body: "La boutique disparaît des recherches et le marchand perd l'accès aux commandes dès maintenant.",
          }}
          reason={{ label: "Motif de la suspension", required: true }}
        />
      )}
      {shop.status === "suspended" && (
        <ActionForm
          action={reviewShop}
          label="Rétablir"
          variant="outline"
          hidden={hidden("reinstate")}
          confirm={{
            title: `Rétablir « ${shop.name} » ?`,
            body: "La boutique redevient visible des acheteurs.",
          }}
        />
      )}
    </div>
  );
}
