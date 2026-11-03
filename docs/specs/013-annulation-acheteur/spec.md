# 013 — Annulation d'une commande par l'acheteur

## Objectif

Permettre à l'acheteur d'**annuler sa commande tant que la boutique ne l'a pas acceptée**, avec
un remboursement intégral si elle était déjà payée ([PRD](../../PRD.md) : « Annulation par
l'acheteur tant que le marchand n'a pas accepté (remboursement intégral) ; ensuite, seul l'admin
peut annuler »).

Le suivi de commande (statuts, frise, code de remise) est déjà fait
([009](../009-commande-retrait/spec.md)) ; la 013 y ajoute l'annulation et ce qu'elle entraîne
(remboursement annoncé, demande de paiement en cours). Le backend existe
(`POST /v1/orders/{id}/cancel`) : seule l'app acheteur change. Côté marchand, une commande
annulée quitte « Nouvelles » à la relecture suivante ([011](../011-commandes-marchand/spec.md)).

## Comportement attendu

**1. Bouton**
- Sur le suivi d'une commande (« Commande #1042 »), bouton secondaire **« Annuler la
  commande »** sous le contenu, visible seulement tant que l'annulation est possible :
  - **en attente de paiement** (`pending_payment`) ;
  - **payée, en attente de la boutique** (`awaiting_seller`).
- Dès que la boutique accepte (ou que la commande expire, est refusée…), le bouton disparaît
  (à la relecture suivante du suivi, toutes les 20 s).

**2. Confirmation** (feuille)
- « Annuler la commande #1042 ? »
- Non payée : « Vos produits seront libérés. »
- Payée : « Vous serez remboursé de 10 500 F sur votre compte Mobile Money. » (montant total de
  la commande, aucun délai promis).
- Boutons **« Annuler la commande »** (destructif) et **« Garder ma commande »** (ferme la
  feuille, rien n'est envoyé).

**3. Annulation**
- Demande de paiement en cours (l'acheteur doit valider sur son téléphone) : l'app l'annule
  d'abord (`POST /v1/payments/{id}/cancel`), puis annule la commande.
- Réussite : le suivi passe à **« Annulée »** (« Annulée par l'acheteur. ») ; payée :
  « Vous serez remboursé de 10 500 F sur votre compte Mobile Money. » sous le titre, jusqu'au
  remboursement (« Remboursée », déjà fait en 009). Message « Commande annulée. ».
- La commande passe dans « Terminées » de l'onglet Commandes.

**4. Refus**
- La boutique a accepté entre-temps (`cannot_cancel`) : message du serveur (« La boutique a déjà
  accepté cette commande : contactez le support pour l'annuler. »), suivi relu (bouton retiré).
- Le paiement a abouti pendant l'annulation de la demande (`payment_not_cancellable`) : la
  commande est relue ; payée, elle reste annulable et la feuille se rouvre avec le montant
  remboursé (l'acheteur confirme de nouveau).

## Critères d'acceptation

- [ ] Le bouton « Annuler la commande » n'apparaît que pour `pending_payment` et
      `awaiting_seller` ; jamais pour une autre commande (acceptée, prête, terminée…).
- [ ] La feuille affiche « Annuler la commande #N ? » et, selon que la commande est payée ou
      non, le montant remboursé (total) ou « Vos produits seront libérés. ».
- [ ] « Garder ma commande » ferme la feuille sans requête.
- [ ] « Annuler la commande » envoie `POST /v1/orders/{id}/cancel` une seule fois (double appui) ;
      le suivi passe à « Annulée », avec le remboursement annoncé si elle était payée ; la
      commande apparaît dans « Terminées ».
- [ ] Avec une demande de paiement en attente, l'app annule d'abord la demande, puis la
      commande, dans cet ordre.
- [ ] `cannot_cancel` : suivi relu, bouton retiré ; message du serveur, sauf commande expirée :
      « Cette commande a expiré : vos produits sont déjà libérés. ».
- [ ] `payment_not_cancellable` : commande relue ; si elle est payée et toujours annulable, la
      feuille se rouvre avec le montant remboursé, sinon message et bouton retiré.
- [ ] Réseau coupé : « Pas de connexion. Réessayez. », rien ne change ; un nouvel essai
      fonctionne.
- [ ] Police à 200 % sur 320 dp : suivi avec le bouton et feuille sans débordement ; lecteur
      d'écran : bouton et feuille lus.

## Cas limites et erreurs

- **Boutique qui accepte pendant la confirmation** : la feuille est ouverte, l'acheteur confirme
  ⇒ `cannot_cancel` (voir 4).
- **Commande expirée pendant la confirmation** (`pending_payment` → `expired`) : le serveur
  répond `cannot_cancel` avec un message prévu pour une commande acceptée (« La boutique a déjà
  accepté… »), faux ici. L'app relit la commande et, si elle est expirée, affiche « Cette commande
  a expiré : vos produits sont déjà libérés. » (point backend noté pour Gedeon).
- **Paiement arrivé après l'annulation** (l'acheteur valide sur son téléphone malgré tout) : le
  serveur place la commande dans la file de remboursement ; le suivi reste « Annulée » et annonce
  le remboursement dès qu'il voit la commande payée.
- **Double appui** sur « Annuler la commande » : une seule requête (bouton désactivé pendant
  l'envoi).
- **Retour arrière pendant l'envoi** : la requête aboutit quand même ; la liste montre la commande
  annulée.
- **Commande d'un autre compte** : 404, déjà géré par le suivi (« Cette commande n'est plus
  disponible. »).

## Hors périmètre

- Motif d'annulation choisi par l'acheteur (le serveur n'en prend pas).
- Annulation après acceptation (seul l'admin, dans le back-office).
- Délai de remboursement promis (dépend du prestataire, 016).
- Notifications push de l'annulation (012).

## Questions ouvertes

Aucune (tranchées le 2026-11-03 : bouton sur le suivi seulement ; demande de paiement en cours
annulée avant la commande ; montant remboursé sans délai ; feuille de confirmation simple).
