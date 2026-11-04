# 029 — Module pharmacie (alerte médicament)

Diagrammes de flux (BPMN 2.0, à ouvrir dans Camunda Modeler) ; aperçus en PNG à côté.

| Fichier | Contenu |
| --- | --- |
| `alerte-medicament.bpmn` | Alerte du client → réponses des pharmacies → déblocage 100 F → retrait ou livraison ivia |
| `inscription-pharmacie.bpmn` | Inscription de la pharmacie, dépôt des pièces, validation par l'admin |

Backend : module `backend/internal/pharmacy`, migration `00027_pharmacy.sql`, routes décrites dans
`backend/api/openapi.yaml` (tags « Alerte médicament », « Pharmacie », « Livreur », « Admin »).

## Règles retenues

- **Alerte** : trois façons de chercher — photo de l'ordonnance, photo de la boîte, nom saisi.
- **Diffusion** : pharmacies validées par l'admin, ouvertes ou de garde, dans un rayon de 5 km, élargi
  une fois à 10 km au bout de 4 minutes si les réponses manquent (tout de suite si personne n'est
  dans le rayon).
- **Réponses** : la recherche se ferme dès 3 réponses ou au bout de 10 minutes ; réponses classées par
  distance.
- **Déblocage** : les identités restent grisées (nom, adresse, téléphone, position, note) jusqu'au
  paiement forfaitaire de 100 F via l'agrégateur.
- **Sur ordonnance** (alerte par ordonnance, ou produit signalé « sur ordonnance » par la pharmacie) :
  pas de livreur ivia, retrait en pharmacie obligatoire, ordonnance à présenter.
- **Sinon**, le client choisit :
  - retrait en pharmacie : code de retrait à 6 chiffres, paiement sur place ;
  - livraison ivia : médicament et livraison payés dans l'app ; le livreur remet le médicament contre
    le code du client ; la pharmacie est créditée du prix moins la commission ivia.
- **Pharmacie** : inscription dans l'app pharmacie, puis validation par l'admin sur pièces avant de
  recevoir des alertes (rôle `pharmacist`).

Tous les chiffres (forfait, rayons, nombre de réponses, délais, conservation) se règlent dans le
back-office : `GET/PUT /v1/admin/pharmacy/settings`.

## Décisions prises pour les questions ouvertes

Valeurs par défaut retenues pour avancer. Chacune se change dans les réglages ou en une ligne de code.

1. **Remboursement du déblocage** : pas de remboursement automatique ; l'admin rembourse au cas par
   cas (`POST /v1/admin/medicine-payments/{id}/refund`), par exemple si aucune pharmacie n'a pu servir
   le client. Le déblocage n'est possible qu'à partir d'une réponse : on ne paie jamais pour rien. Un
   déblocage payé deux fois est remboursé automatiquement.
2. **Portée des 100 F** : toutes les pharmacies de l'alerte, y compris celles qui répondent après.
3. **Commission et frais de livraison** : même taux de commission et même barème moto que les
   commandes (réglages généraux de la plateforme). Pas de commission sur un retrait payé sur place.
   Livraison refusée au-delà de 20 km.
4. **Durée de réservation** : 2 heures pour un retrait. Une livraison doit être payée dans le délai de
   paiement des commandes.
5. **Pièces exigées** : autorisation d'ouverture, inscription à l'Ordre des pharmaciens, pièce
   d'identité du titulaire. Toutes les trois sont obligatoires pour valider.
6. **Photos d'ordonnance** : supprimées 30 jours après la fin de l'alerte, ou à la suppression du
   compte. Elles restent privées et sont lues par lien de 10 minutes, par les seules pharmacies
   sollicitées et seulement tant que l'alerte est ouverte.

## Cycle de vie

Alerte : `searching` → `answered` (au moins une réponse) ou `no_response` → `unlocked` → `fulfilled`,
ou `cancelled` à tout moment avant la remise.

Réservation :

- retrait : `reserved` → `completed`, ou `expired` / `cancelled` ;
- livraison : `awaiting_payment` → `paid` (recherche d'un livreur) → `courier_assigned` → `picked_up`
  → `completed`, ou `expired` / `cancelled`. Une annulation après paiement est remboursée
  automatiquement.

Si la pharmacie n'a plus le produit, elle annule la réservation. Sa réponse est alors retirée et le
client peut réserver ailleurs dans la même alerte, sans payer un nouveau déblocage.

## Intégration des apps

**App acheteur**

1. Photo : `POST /v1/uploads` avec l'usage `pharmacy_alert_photo`, envoi du fichier, puis
   `POST /v1/medicine-alerts`.
2. Suivi : `GET /v1/medicine-alerts/{id}`, à rafraîchir pendant `searching`. Les notifications sont
   `pharmacy_response` et `pharmacy_alert_closed`.
3. Déblocage : `POST /v1/medicine-alerts/{id}/unlock`, puis suivi du paiement avec
   `GET /v1/medicine-payments/{id}`.
4. Réservation : `POST /v1/medicine-alerts/{id}/reservations`. Pour une livraison, payer ensuite avec
   `POST /v1/medicine-reservations/{id}/pay`.
5. Le code de remise s'affiche dans `GET /v1/medicine-reservations/{id}` (champ `handover_code`).

**App pharmacie**

1. Inscription : `POST /v1/pharmacy/application`, puis chaque pièce avec `POST /v1/uploads` (usage
   `pharmacy_document`) et `POST /v1/pharmacy/me/documents`.
2. Après validation : `PUT /v1/pharmacy/me/status` pour ouvrir la pharmacie ou la déclarer de garde.
3. Alertes reçues : `GET /v1/pharmacy/inbox`, puis `respond` ou `decline`. La notification est
   `pharmacy_alert`, avec l'app `pharmacy`.
4. Réservations : `GET /v1/pharmacy/reservations`. Pour un retrait, saisir le code du client avec
   `POST /v1/pharmacy/reservations/{id}/complete`.
5. Argent : `GET /v1/pharmacy/earnings` (solde et reversements).

**App livreur** : `GET /v1/driver/pharmacy-offers/current` (notification `pharmacy_courier_offer`),
`accept`, puis `picked-up` et `delivered` avec le code du client. Pendant une course pharmacie, le
livreur ne reçoit aucune commande, et inversement.

**Back-office** : dossiers avec `/v1/admin/pharmacies`, alertes avec `/v1/admin/medicine-alerts`,
paiements et remboursements avec `/v1/admin/medicine-payments`, reversements avec
`/v1/admin/pharmacies/{id}/payouts`, indicateurs avec `/v1/admin/pharmacy/overview`.

**En local** : `POST /v1/dev/medicine-payments/{id}/simulate` valide un paiement avec le faux
prestataire, comme `/v1/dev/payments/{id}/simulate` pour les commandes.
