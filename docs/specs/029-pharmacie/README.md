# 029 — Module pharmacie (alerte médicament)

Diagrammes de flux (BPMN 2.0, à ouvrir dans Camunda Modeler) ; aperçus en PNG à côté.

| Fichier | Contenu |
| --- | --- |
| `alerte-medicament.bpmn` | Première version du flux (v1) : alerte → réponses → déblocage → retrait ou livraison. Les règles à jour sont ci-dessous. |
| `inscription-pharmacie.bpmn` | Inscription de la pharmacie, dépôt des pièces, validation par l'admin |

Backend : module `backend/internal/pharmacy`, migrations `00027_pharmacy.sql` (v1) et
`00028_pharmacy_mockups.sql` (v2, alignée sur les maquettes P01 à P14). Routes décrites dans
`backend/api/openapi.yaml` (tags « Alerte médicament », « Pharmacie », « Livreur », « Admin »).

## Règles retenues (v2, maquettes P01 à P14)

- **Alerte** : une liste de produits (choisis dans la base de médicaments ou saisis librement, avec
  forme et quantité) et/ou des photos (ordonnance, boîte). Option « générique accepté » et note.
- **Rayon** : le client choisit parmi les rayons proposés (2, 5 ou 10 km par défaut). Avant de lancer
  l'alerte, l'app affiche le nombre de pharmacies joignables pour chaque rayon. L'élargissement
  automatique est désactivé par défaut : sans réponse, le client relance avec un autre rayon (photos
  et produits repris).
- **Diffusion** : pharmacies validées, ouvertes, de garde (déclarée ou planifiée) ou ouvertes 24 h/24.
- **Réponses** : fenêtre de 20 minutes. La pharmacie répond ligne par ligne (disponible ou non,
  quantité, prix, ordonnance exigée) et peut modifier sa réponse tant qu'elle n'est pas débloquée. Le
  client voit les compteurs « contactées, vues, réponses » et les réponses classées par distance.
- **Déblocage par pharmacie** : chaque pharmacie se débloque séparément, au forfait de 100 F. Le
  déblocage révèle son identité et **met de côté** les produits disponibles pendant 1 heure (réservation
  créée, numéro « M-n », code de remise à 4 chiffres).
- **Aucune commission sur les produits** : le client a déjà payé le forfait de déblocage. La pharmacie
  reçoit le prix complet des produits livrés (réglage `product_commission_bp`, 0 par défaut).
- **Retrait sur place** (par défaut) : le client se rend à la pharmacie, paie sur place et donne son
  code.
- **Livraison ivia** : quand le client choisit « livreur ivia », la recherche démarre tout de suite.
  La course est proposée aux livreurs libres, du plus proche au plus éloigné de la pharmacie. **Le
  client ne paie qu'une fois un livreur trouvé** : produits et livraison, dans l'app. Le livreur ne
  peut récupérer la commande qu'après ce paiement.
- **Sur ordonnance** : la livraison est permise ; le livreur doit confirmer avoir vérifié l'ordonnance
  à la remise (`prescription_checked`), sinon la remise est refusée.
- **Photos** : supprimées 24 heures après la fin de l'alerte, ou à la suppression du compte.
- **Pharmacies de garde** : planning de garde saisi par l'admin, en plus de l'interrupteur « de garde »
  de la pharmacie. La liste publique des pharmacies de garde alimente l'accueil.

Tous les chiffres (forfait, rayons, délais, conservation, commission) se règlent dans le back-office :
`GET/PUT /v1/admin/pharmacy/settings`.

## Décisions prises pour les questions ouvertes

Valeurs par défaut retenues pour avancer. Chacune se change dans les réglages ou en une ligne de code.

1. **Remboursement du déblocage** : automatique si la pharmacie annule (produit plus disponible) ou si
   le déblocage s'avère impossible après paiement. Sinon, l'admin rembourse au cas par cas
   (`POST /v1/admin/medicine-payments/{id}/refund`). On ne paie jamais pour une pharmacie qui n'a pas
   répondu.
2. **Frais de livraison** : barème moto des commandes (réglages généraux). Livraison refusée au-delà
   de 20 km entre la pharmacie et le client. Devis sans engagement avant le choix.
3. **Pas de livreur** : la recherche continue ; les admins sont prévenus après le nombre maximal de
   propositions refusées. Le client peut repasser au retrait à tout moment avant le paiement.
4. **Mise de côté** : 1 heure après le déblocage, quel que soit le mode, tant que rien n'est payé.
5. **Pièces exigées** : autorisation d'ouverture, inscription à l'Ordre des pharmaciens, pièce
   d'identité du titulaire. Toutes les trois sont obligatoires pour valider.
6. **Codes de remise** : 5 essais au plus par quart d'heure et par réservation ou course.

## Cycle de vie

Alerte : `searching` → `answered` (au moins une réponse) ou `no_response` → `unlocked` → `fulfilled`,
ou `cancelled`. Une alerte terminée peut être relancée (nouvelle alerte liée par `relaunched_from`).

Réservation (créée au déblocage) :

- retrait : `reserved` → `completed`, ou `expired` / `cancelled` ;
- livraison : `reserved` → `courier_search` (recherche du livreur) → `awaiting_payment` (livreur
  trouvé, le client paie) → `courier_assigned` → `picked_up` → `completed`, ou `expired` /
  `cancelled`. Une annulation après paiement est remboursée automatiquement. Si le livreur se désiste
  avant le paiement, la recherche reprend (`courier_search`).

Si la pharmacie n'a plus le produit, elle annule : le client est remboursé (forfait compris) et peut
débloquer une autre pharmacie de la même alerte.

## Intégration des apps

**App acheteur**

1. Accueil : `GET /v1/pharmacies/on-duty?lat=&lng=` (public) pour « De garde maintenant ».
2. Préparer l'alerte : `GET /v1/medicines?q=` (autocomplétion), `GET /v1/medicine-alerts/preview`
   (pharmacies par rayon, forfait, délais). Photos : `POST /v1/uploads` avec l'usage
   `pharmacy_alert_photo`.
3. Lancer : `POST /v1/medicine-alerts`. Suivi : `GET /v1/medicine-alerts/{id}`. Notifications :
   `pharmacy_response`, `pharmacy_alert_closed`. Relance : `POST /v1/medicine-alerts/{id}/relaunch`.
4. Débloquer une pharmacie : `POST /v1/medicine-alerts/{id}/responses/{responseId}/unlock`, puis
   suivre le paiement avec `GET /v1/medicine-payments/{id}` (notification `pharmacy_unlocked`). La
   réponse donne `reservation_id`.
5. Retrait : rien à faire, le code s'affiche dans `GET /v1/medicine-reservations/{id}`.
6. Livraison : `GET .../delivery-quote?address_id=`, puis `POST .../delivery` (recherche du livreur).
   Quand le statut passe à `awaiting_payment` (notification `pharmacy_courier_assigned`), payer avec
   `POST .../pay`. `POST .../pickup` revient au retrait.

**App pharmacie**

1. Inscription : `POST /v1/pharmacy/application`, puis chaque pièce avec `POST /v1/uploads` (usage
   `pharmacy_document`) et `POST /v1/pharmacy/me/documents`.
2. Après validation : `PUT /v1/pharmacy/me/status` (ouverte, de garde, 24 h/24) ;
   `GET /v1/pharmacy/me/duty-shifts` pour le planning de garde.
3. Alertes : `GET /v1/pharmacy/inbox`, détail (marque l'alerte vue), puis `respond` (lignes) ou
   `decline`. Notification `pharmacy_alert`.
4. Réservations : `GET /v1/pharmacy/reservations` (notification `pharmacy_reservation`),
   `POST .../prepared`, et pour un retrait `POST .../complete` avec le code du client.
5. Argent : `GET /v1/pharmacy/earnings` (solde et reversements).

**App livreur** : `GET /v1/driver/pharmacy-offers/current` (notification `pharmacy_courier_offer`),
`accept` ; attendre le paiement du client (notification `pharmacy_mission_paid`), puis `picked-up`
et `delivered` avec `{code, prescription_checked}`. Pendant une course pharmacie, le livreur ne reçoit
aucune commande, et inversement.

**Back-office** : dossiers avec `/v1/admin/pharmacies`, planning de garde avec
`/v1/admin/pharmacies/{id}/duty-shifts`, base de médicaments avec `/v1/admin/medicines`, alertes avec
`/v1/admin/medicine-alerts`, paiements et remboursements avec `/v1/admin/medicine-payments`,
reversements avec `/v1/admin/pharmacies/{id}/payouts`, indicateurs avec
`/v1/admin/pharmacy/overview`.

**En local** : `POST /v1/dev/medicine-payments/{id}/simulate` valide un paiement avec le faux
prestataire, comme `/v1/dev/payments/{id}/simulate` pour les commandes.
