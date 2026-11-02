# 009 — Commande en retrait et suivi

## Objectif

Permettre à l'acheteur de passer commande du panier pour un **retrait en boutique**, puis de
suivre sa commande jusqu'au retrait, avec son **code de remise** ([PRD](../../PRD.md), parcours 2 :
« le marchand accepte et prépare → « prête pour retrait » → l'acheteur se présente avec son code →
« retirée » »). Suite directe de [008](../008-panier/spec.md), dont « Commander » annonçait la
commande.

Maquettes du 2026-11-02 (commande, commandes, suivi) : elles guident l'écran sans le figer. Le
paiement (écrans « Paiement » et « Validez le paiement sur votre téléphone ») est la
[010](../../../TASKS.md) ; la livraison (adresse, véhicule, livreur) la 020 ; l'annulation et le
rafraîchissement par notification la 013 et la 012.

## Comportement attendu

**1. Écran Commande** (depuis « Commander » du panier)
- Deux cartes de mode : **Livraison** (« Un livreur ivia vous apporte la commande »), visible mais
  désactivée avec « Bientôt » ; **Retrait** (« Gratuit, en boutique à Tokoin »), choisie.
- La boutique : nom, adresse, quartier ; « Vous retirez la commande ici, avec votre code. »
- Le récapitulatif calculé par le serveur : lignes (quantité × nom, montant), « Produits »,
  « Total ».
- « Vos produits sont réservés 15 minutes, le temps de payer. » (délai lu sur le serveur).
- Bouton **« Payer 10 500 F »** : crée la commande (stock réservé, panier vidé) puis ouvre son suivi.
  Le paiement lui-même arrive avec la 010 : le suivi le propose (voir 3).

**2. Onglet Commandes** (barre du bas)
- Onglets **« En cours · 2 »** et **« Terminées »**.
- Une ligne par commande : logo de la boutique, nom, « #1042 · Retrait · 3 articles » (en cours)
  ou « #1018 · 24 oct. » (terminée), total, pastille de statut (libellés et couleurs de
  [DESIGN](../../DESIGN.md#libellés-des-statuts), avec une icône).
- Sous les commandes en cours, « Récemment » : les 3 dernières commandes terminées.
- Vide : « Aucune commande en cours. » et « Découvrir les produits » ; « Aucune commande
  terminée. »
- Un appui ouvre le suivi. Tirer vers le bas actualise.

**3. Suivi d'une commande** (« Commande #1042 »)
- **En-tête de couleur** selon l'étape :
  - en attente de paiement : « À payer avant 14:32 », « Sinon la commande est annulée et vos
    produits libérés. », bouton « Payer 10 500 F » (annonce « Le paiement arrive bientôt. »
    jusqu'à la 010) ;
  - payée : « En attente de la boutique », « Acceptée », « En préparation », puis « Prête à
    retirer » avec l'adresse de la boutique ;
  - **code de remise** en très grand (4 cases), dès que le serveur le donne (commande payée, pas
    encore retirée) : « Donnez-le à la boutique uniquement au retrait de vos produits. » ;
  - terminée : « Retirée », ou « Paiement expiré », « Annulée » (avec la raison), « Remboursée »
    (couleur neutre).
- La boutique (logo, nom, adresse) : un appui ouvre sa fiche.
- **Frise des statuts** horodatés (heure de Lomé) : « Commande passée », « Paiement reçu »,
  « Acceptée par Chez Afi », « En préparation », « Prête à retirer », « Retirée » ; les étapes à
  venir en gris ; une fin anormale (expirée, annulée, remboursée) clôt la frise.
- Les articles (quantité × nom, montant) et le total.
- Une commande en cours se met à jour seule : relue toutes les 20 s pendant que son suivi est
  affiché, et au retour dans l'app ; tirer vers le bas actualise.

## Critères d'acceptation

- [ ] Étant donné un panier commandable, quand l'acheteur ouvre « Commander », alors le
      récapitulatif du serveur (`POST /v1/orders/quote`, retrait) s'affiche avec le total, et
      « Livraison » est désactivée avec « Bientôt ».
- [ ] Étant donné le récapitulatif, quand l'acheteur appuie sur « Payer », alors une seule
      commande est créée (`POST /v1/orders`, retrait, identifiant de requête unique réutilisé en
      cas de nouvel essai), le panier est vide et le suivi de la commande s'ouvre.
- [ ] Étant donné un refus du serveur à la commande (stock, produit retiré, boutique fermée,
      panier vide), alors son message s'affiche et « Revenir au panier » relit le panier.
- [ ] Étant donné des commandes en cours et terminées, alors l'onglet Commandes les sépare, avec
      le nombre en cours, le statut lisible et le total ; « Récemment » montre les 3 dernières
      terminées.
- [ ] Étant donné une commande en attente de paiement, alors le suivi affiche l'heure limite et
      « Payer », sans code de remise.
- [ ] Étant donné une commande payée non retirée, alors le suivi affiche le code de remise en 4
      cases, lu chiffre par chiffre par le lecteur d'écran.
- [ ] Étant donné une commande en cours affichée, quand son statut change sur le serveur, alors
      le suivi le montre en moins de 20 s ; une commande terminée n'est plus relue.
- [ ] Étant donné la frise, alors chaque étape passée a son heure, les étapes à venir sont en
      gris, et une commande annulée affiche « Annulée » et sa raison.

## Cas limites et erreurs

- **Double appui sur « Payer »**, ou réponse perdue puis nouvel essai : le même identifiant de
  requête est renvoyé, le serveur rend la même commande (jamais deux commandes).
- **Panier modifié ailleurs** (autre téléphone) entre le panier et « Commander » : le
  récapitulatif est celui du serveur ; « Payer » commande ce que le serveur a, et le panier de
  l'app est relu après.
- **Trop de commandes en peu de temps** (`rate_limited`) : message du serveur.
- **Profil incomplet** (`profile_incomplete`, rare : le profil est exigé à la connexion) : message
  du serveur.
- **Réseau coupé** : au récapitulatif, message et « Réessayer » ; à « Payer », message, et le
  nouvel appui renvoie la même requête ; au suivi, la dernière version reste affichée.
- **Commande d'un autre compte** (lien, autre compte sur le téléphone) : 404, « Cette commande
  n'est plus disponible. » ; la liste est relue au changement de compte.
- **Délai de paiement dépassé** pendant que le suivi est ouvert : la relecture affiche « Paiement
  expiré », et continue 10 minutes après l'heure limite (un paiement arrivé en retard reprend la
  commande).
- **Retour pendant « Payer »** : bloqué jusqu'à la réponse ; si l'écran est quitté après une
  coupure, le panier est relu (la commande a pu être créée et le panier vidé).
- **Relecture** : jamais en arrière-plan ni sous un autre écran ; au retour dans l'app, la commande
  est relue aussitôt, quel que soit son statut. Une réponse plus ancienne que la version affichée
  est ignorée.
- **Police à 200 %, écran de 320 dp** : rien n'est masqué ; le code reste sur une ligne.

## Hors périmètre

- Paiement Flooz / T-Money et écran d'attente : 010.
- Livraison (adresse, véhicule, frais, livreur, « Arrivée vers ») : 020 et suivantes.
- Annulation par l'acheteur : 013 ; notifications push : 012.
- Profil, adresses (maquette « Profil ») : 002.

## Questions ouvertes

<!-- Vide = prêt pour le plan. -->
