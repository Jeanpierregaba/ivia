# 013 — Plan technique

## Approche

- **Aucun changement serveur.** Routes existantes :
  - `POST /v1/orders/{id}/cancel` → `BuyerOrder` annulée (« Annulée par l'acheteur. ») ; permise
    pour `pending_payment` et `awaiting_seller` ; sinon 409 `cannot_cancel` (message prévu pour
    une commande acceptée, renvoyé aussi pour une commande expirée : point backend noté) ;
    payée : remboursement intégral dû (file de remboursement, admin).
  - `GET /v1/orders/{id}/payments` (demandes de la commande) et `POST /v1/payments/{id}/cancel`
    (409 `payment_not_cancellable` si elle a abouti) : déjà dans le client (010).
- **Commande payée ou non** : `BuyerOrder` lit `paid_at` (absent du modèle aujourd'hui). Payée
  ⇒ montant remboursé = `total_xof` (règle du serveur : annulée après paiement, remboursement
  intégral).
- **Annulation** (`OrderController.cancel` dans l'app acheteur) :
  1. lit les demandes de paiement de la commande ; une demande en attente est annulée
     (`cancelPayment`) ;
  2. `payment_not_cancellable` : la commande est relue ; payée et toujours annulable ⇒ la feuille
     se rouvre avec le montant (l'acheteur confirme de nouveau) ; sinon message ;
  3. `cancelOrder` ; la commande rendue remplace celle du suivi et de la liste (`myOrdersProvider`).
  Les fournisseurs sont lus avant l'envoi : le résultat est reporté même si l'écran est quitté.
- **Bouton** sur le suivi (`order_screen.dart`) : `OutlinedButton` « Annuler la commande » en bas
  du contenu, si `status` ∈ {`pending_payment`, `awaiting_seller`} ; désactivé pendant l'envoi.
- **Feuille** `cancel_sheet.dart` : « Annuler la commande #N ? », texte selon payée ou non,
  « Annuler la commande » (style destructif, `IviaColors.error`) et « Garder ma commande ».
- **Refus** `cannot_cancel` : commande relue ; expirée ⇒ « Cette commande a expiré : vos produits
  sont déjà libérés. » ; sinon message du serveur. Réseau : « Pas de connexion. Réessayez. ».
- **Suivi d'une commande annulée et payée** : sous « Annulée » et le motif, « Vous serez remboursé
  de 10 500 F sur votre compte Mobile Money. » (jusqu'à « Remboursée », déjà géré).

## Fichiers touchés

**`packages/api_client`**
- `lib/src/models.dart` : `BuyerOrder.paidAt`.
- `lib/src/client.dart` : `cancelOrder(id)` → `BuyerOrder`.
- `lib/testing.dart` : `FakeOrders` : `POST /v1/orders/{id}/cancel` fidèle (statuts permis,
  `cannot_cancel` avec le message du serveur, événement « Annulée par l'acheteur. », stock suivi
  rendu, commande d'un autre compte ⇒ 404) ; `FakePayments` : paiement abouti sur une commande
  annulée ⇒ `paid_at` posé et événement « Paiement reçu après l'annulation : à rembourser. »
  (comme `RecordLatePayment`, aujourd'hui ignoré par le faux serveur).
- `test/client_test.dart` : modèle, route, faux serveur.

**App acheteur**
- `lib/features/orders/orders_providers.dart` : `OrderController.cancel` (enchaînement
  ci-dessus), report dans la liste.
- `lib/features/orders/cancel_sheet.dart` (nouveau) : feuille de confirmation.
- `lib/features/orders/order_screen.dart` : bouton, refus, remboursement annoncé.
- `test/order_test.dart` : parcours et cas limites.

**Docs**
- `docs/DESIGN.md` : bouton et feuille d'annulation (suivi acheteur).
- `TASKS.md` : 013 en cours puis terminée.

## Données

Aucune (pas de migration ; rien de stocké sur le téléphone).

## API / interfaces

Aucune route nouvelle ni modifiée : `openapi.yaml` inchangé.

## Dépendances

Aucune.

## Sécurité

- Contrôle d'accès côté serveur (commande de l'acheteur seulement, sinon 404).
- Aucun numéro de téléphone ni donnée de paiement affiché, stocké ou journalisé au-delà de ce
  que le suivi montre déjà.
- Le remboursement reste déclenché par l'admin sur paiement vérifié (ADR 0007) : l'app ne fait
  qu'annoncer le montant dû.

## Tests

Pas de partie critique côté app (machine à états et remboursement testés au backend) ; le faux
serveur reproduit les règles d'annulation pour que les tests d'écran ne valident rien
d'impossible.

- `api_client` : `paid_at` lu ; `cancelOrder` (méthode, chemin) ; faux serveur : annulation
  permise / refusée (`cannot_cancel`, y compris commande expirée), stock rendu, paiement tardif
  sur commande annulée.
- App acheteur (faux serveur) : bouton visible ou non selon le statut ; feuille non payée / payée ;
  « Garder ma commande » sans requête ; annulation (suivi, liste, remboursement annoncé) ;
  double appui ; demande de paiement en attente annulée avant la commande (ordre des
  requêtes) ; `payment_not_cancellable` ⇒ feuille rouverte avec le montant ; `cannot_cancel`
  (acceptée, expirée) ; réseau coupé ; police à 200 % sur 320 dp et lecteur d'écran.
- Vérification sur le simulateur iPhone 17 Pro contre l'API locale : commande passée, annulée
  avant paiement ; commande payée (faux prestataire) puis annulée, remboursement annoncé ; la
  commande disparaît des « Nouvelles » de l'app marchand.

## Risques

- **Course avec la boutique** (acceptation pendant la confirmation) : le serveur tranche
  (`cannot_cancel`), l'app relit.
- **Paiement validé sur le téléphone après l'annulation** : le serveur le range dans la file de
  remboursement ; l'app l'annonce dès qu'elle voit `paid_at`.
- **Message serveur faux pour une commande expirée** : contourné dans l'app, point backend noté.
