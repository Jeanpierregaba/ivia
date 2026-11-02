# 010 — Paiement Mobile Money

## Objectif

Permettre à l'acheteur de **payer sa commande par Flooz ou T-Money** depuis l'app, puis d'attendre
la validation sur son téléphone jusqu'à la confirmation du serveur ([PRD](../../PRD.md), parcours 1
et 2 : « paiement Mobile Money → confirmation par le prestataire »). Suite directe de
[009](../009-commande-retrait/spec.md) : son bouton « Payer » crée la commande, la 010 la fait
payer.

Maquettes du 2026-11-02 (« Paiement », « Validez le paiement sur votre téléphone ») : elles guident
l'écran sans le figer. Le paiement n'est réussi que sur notification vérifiée du prestataire
(règle 4) : l'app ne fait qu'afficher ce que le serveur dit.

## Comportement attendu

**1. Écran Paiement** (après « Payer » de l'écran Commande, ou « Payer » du suivi d'une commande en
attente de paiement)
- « Montant à payer » et le total de la commande, en grand (« 10 500 F »).
- **Opérateur** : deux cartes, **Flooz** et **T-Money**, une seule choisie (Flooz par défaut).
- **« Numéro Flooz »** (ou « Numéro T-Money ») : indicatif +228 fixe, 8 chiffres ; pré-rempli
  avec le numéro du profil, modifiable.
- « Paiement sécurisé. Vous validez sur votre téléphone avec votre code secret. » (une
  information, pas une case à cocher : il n'y a rien à accepter).
- Bouton **« Payer 10 500 F »** : envoie la demande au prestataire, puis ouvre l'écran d'attente.
- Retour : au suivi de la commande, qui reste à payer jusqu'à l'heure limite.

**2. Écran « Validez le paiement sur votre téléphone »**
- « Une demande Flooz de 10 500 F a été envoyée au +228 96 •• •• 78. Saisissez votre code secret
  pour confirmer. » (numéro masqué, tel que le serveur le rend).
- **Temps restant** jusqu'à l'heure limite de la commande (« 14:32 », minutes et secondes), barre
  qui se vide ; « Vos produits sont réservés pendant 15 minutes. »
- L'état du paiement est relu toutes les 3 secondes tant que l'écran est affiché.
  - **Réussi** : le suivi de la commande s'ouvre, avec « Paiement reçu. La boutique va confirmer
    votre commande. » et le code de remise.
  - **Refusé** (code faux, solde insuffisant, refus sur le téléphone) : « Le paiement n'a pas
    abouti », la raison donnée par le serveur, **« Réessayer »** (écran Paiement) et « Retour à
    la commande ».
- **« Je n'ai rien reçu »** : une feuille explique quoi vérifier (le numéro, l'opérateur, le
  réseau) et propose **« Renvoyer la demande »** (même opérateur, même numéro) ou **« Changer de
  numéro »** (écran Paiement). Dans les deux cas, la demande en cours est annulée d'abord.
- **« Annuler le paiement »** : confirmation (« Votre commande reste réservée jusqu'à 14:32. »),
  puis la demande est annulée et le suivi de la commande s'affiche ; « Payer » y reste possible.
- Retour (flèche ou geste) : au suivi, **sans annuler** ; « Payer » du suivi rouvre l'attente de
  la demande en cours.

**3. Serveur : annulation d'une demande** (nouvelle route, module `payments`)
- `POST /v1/payments/{id}/cancel` : l'acheteur abandonne sa demande en attente, qui passe en échec
  (« Annulé par l'acheteur. ») ; il peut alors en lancer une autre (autre numéro, autre opérateur).
- Une demande validée malgré tout sur le téléphone reste appliquée (le webhook fait foi) ; si deux
  demandes aboutissent, la seconde est un doublon remboursé par l'admin, comme aujourd'hui.
- Les demandes de paiement d'un acheteur sont limitées (10 par heure) : on ne peut pas envoyer des
  demandes en boucle vers un numéro.

**4. En local seulement** : avec `--dart-define=IVIA_DEV_PAYMENT=true` dans un build debug,
l'écran d'attente montre « Simuler la validation » et « Simuler un refus » (faux prestataire du
serveur). Jamais en release.

## Critères d'acceptation

- [ ] Étant donné l'écran Commande, quand l'acheteur appuie sur « Payer », alors la commande est
      créée et l'écran Paiement s'ouvre avec son total, Flooz choisi et le numéro du profil ; le
      retour mène au suivi de la commande.
- [ ] Étant donné l'écran Paiement, quand le numéro n'a pas 8 chiffres commençant par 7 ou 9,
      alors « Payer » affiche l'erreur sous le champ et n'envoie rien.
- [ ] Étant donné un numéro valide, quand l'acheteur appuie sur « Payer », alors une seule demande
      est envoyée (`POST /v1/orders/{id}/payments`, opérateur et numéro choisis) et l'écran
      d'attente affiche l'opérateur, le montant, le numéro masqué et le temps restant.
- [ ] Étant donné l'écran d'attente, quand le serveur passe le paiement à « réussi », alors le
      suivi s'ouvre en moins de 3 s avec le code de remise.
- [ ] Étant donné l'écran d'attente, quand le serveur passe le paiement à « échoué », alors la
      raison s'affiche avec « Réessayer », qui rouvre l'écran Paiement.
- [ ] Étant donné une demande en attente, quand l'acheteur choisit « Annuler le paiement » puis
      confirme, alors `POST /v1/payments/{id}/cancel` est appelé et le suivi s'affiche, commande
      toujours à payer.
- [ ] Étant donné « Je n'ai rien reçu », quand l'acheteur choisit « Renvoyer la demande », alors
      la demande en cours est annulée et une nouvelle est envoyée avec le même opérateur et le
      même numéro.
- [ ] Étant donné une commande dont une demande est en attente, quand l'acheteur appuie sur
      « Payer » dans le suivi, alors l'écran d'attente de cette demande s'ouvre (pas de nouvelle
      demande).
- [ ] Serveur : l'annulation d'une demande en attente la passe en échec et permet d'en lancer une
      autre ; annuler une demande réussie rend 409 `payment_not_cancellable` ; la demande d'un
      autre acheteur rend 404 ; une demande annulée puis validée par le prestataire fait avancer la
      commande ; au-delà de 10 demandes par heure, `rate_limited`.

## Cas limites et erreurs

- **Double appui sur « Payer »** : un seul envoi ; le serveur rend de toute façon la demande en
  attente s'il y en a une.
- **Réseau coupé à « Payer »** : message et nouvel essai ; si la première demande était partie, le
  serveur rend celle-ci (l'écran d'attente montre son numéro, celui du serveur).
- **Réseau coupé pendant l'attente** : le temps restant continue, la relecture reprend seule ; rien
  ne passe pour un échec.
- **Délai dépassé pendant l'attente** : « Délai de paiement dépassé. Si vous avez validé, nous
  vérifions votre paiement. » ; la relecture continue 10 minutes (un paiement en retard reprend la
  commande si le stock le permet), puis « Retour à la commande ».
- **Commande plus payable** (`order_not_payable`, `order_expired`) : message du serveur et retour au
  suivi, relu.
- **Prestataire injoignable** (`payment_provider_unavailable`) : message du serveur, « Payer »
  reste disponible.
- **Trop de demandes** (`rate_limited`) : message du serveur.
- **Attente reprise depuis le suivi** : le téléphone ne connaît que le numéro masqué (il ne garde
  pas le numéro complet) ; « Renvoyer la demande » annule alors la demande et ouvre l'écran
  Paiement, opérateur déjà choisi.
- **Annulation qui croise une validation** : le serveur répond que le paiement est déjà confirmé
  (`payment_not_cancellable`) ; l'app ouvre le suivi comme pour un succès.
- **Retour pendant un envoi** (« Payer », annulation) : bloqué jusqu'à la réponse.
- **App en arrière-plan** (l'acheteur valide dans le menu de son opérateur) : la relecture
  s'arrête, puis reprend aussitôt au retour dans l'app.
- **Demande d'un autre compte** (autre compte sur le téléphone) : 404, « Ce paiement n'est plus
  disponible. » et retour au suivi.
- **Police à 200 %, écran de 320 dp** : rien n'est masqué ; le temps restant reste lisible.

## Hors périmètre

- Le vrai prestataire de paiement (016) : la 010 marche avec le faux prestataire du serveur.
- Les instructions propres au prestataire (code USSD à composer…) : affichées quand un vrai
  prestataire sera choisi.
- Annulation de la **commande** par l'acheteur (013) ; notification push du paiement (012).
- Retenir l'opérateur et le numéro du dernier paiement sur le téléphone.

## Questions ouvertes

<!-- Vide = prêt pour le plan. -->
