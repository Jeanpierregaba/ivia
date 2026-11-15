# 008 — Panier de l'acheteur

## Objectif

Permettre à l'acheteur de réunir les produits qu'il veut commander dans une boutique, d'en
ajuster les quantités et de voir le sous-total, avant la commande (009)
([PRD](../../PRD.md) : « Panier mono-boutique : ajouter un produit d'une autre boutique propose de
vider le panier »). Suite directe de [007](../007-accueil-recherche-acheteur/spec.md), dont le
bouton « Ajouter » annonçait le panier.

Maquettes du 2026-11-01 (panier, fiche boutique, fiche produit, accueil) : elles guident l'écran
mais ne le figent pas. Le panier est gardé **sur le serveur** (le même sur tous les téléphones de
l'acheteur) ; l'app le relit à l'ouverture et après chaque modification.

## Comportement attendu

**Règle de la boutique unique.** Un panier contient les produits d'une seule boutique. Ajouter un
produit d'une autre boutique ouvre « Vider le panier ? » : « Votre panier contient des produits de
Chez Afi. Le vider pour ajouter celui-ci ? » (Vider et ajouter / Annuler).

**1. Ajouter au panier**
- **Fiche produit** : quantité (− / +) puis « Ajouter · 9 000 F ». La quantité s'ajoute à celle
  déjà dans le panier (2 + 1 = 3), dans la limite du stock et de 99.
- **Ajout rapide « + »** sur les cartes produit (accueil, recherche) et les lignes de la fiche
  boutique : un exemplaire de plus. Pas de « + » sur un produit épuisé.
- Après l'ajout : message « Riz parfumé 5 kg ajouté au panier » avec « Voir le panier ».

**2. Icône du panier** en haut à droite de l'accueil, de la fiche boutique et de la fiche
produit, avec un badge : le **nombre d'articles** (somme des quantités). Un appui ouvre le
panier.

**3. Barre « Voir le panier »** en bas de la fiche boutique quand le panier contient des produits
de cette boutique : « Voir le panier · 3 » (même nombre que l'icône) et le sous-total ; « À
vérifier » à la place du sous-total si une ligne bloque (le sous-total ne la compte pas).

**4. Écran Panier**
- En-tête : retour, « Panier », « Vider » (confirmation « Vider le panier ? »).
- La boutique (logo, nom, quartier) ; un appui ouvre sa fiche.
- Les lignes : photo, nom, prix unitaire, quantité (− / +). « − » à 1 retire la ligne, avec un
  message « … retiré du panier » et « Annuler ».
- Une ligne qui empêche de commander affiche la raison donnée par le serveur en rouge (« Ce
  produit n'est plus disponible. », « Plus que 2 en stock. ») et « Retirer » ; si le stock reste
  suffisant pour une quantité moindre, « Ajuster à 2 ».
- Note : « Un panier contient les produits d'une seule boutique. Ajouter un produit d'une autre
  boutique vous proposera de vider ce panier. »
- En bas : « Sous-total · 3 articles — 10 500 F », « Frais de livraison calculés à l'étape
  suivante. », bouton « Commander ».
- « Commander » : la commande arrive avec la 009 ; le bouton annonce « La commande arrive
  bientôt. ». Il est désactivé, avec la raison, si le panier ne peut pas être commandé : ligne
  indisponible, ou boutique qui ne prend plus de commandes (« Chez Afi ne prend pas de commandes
  pour l'instant. »).
- Panier vide : « Votre panier est vide. » et « Découvrir les produits » (onglet Recherche).
- Tirer vers le bas actualise (prix et stock du moment).

## Critères d'acceptation

- [x] Étant donné une fiche produit et une quantité de 2, quand l'acheteur appuie sur
      « Ajouter », alors `PUT /v1/cart/items` envoie la quantité totale (déjà au panier + 2), le
      badge augmente de 2 et le message propose « Voir le panier ».
- [x] Étant donné un panier d'une autre boutique, quand l'acheteur ajoute un produit, alors
      « Vider le panier ? » s'ouvre ; « Vider et ajouter » renvoie l'ajout avec `replace_cart` et
      le panier ne contient plus que ce produit ; « Annuler » ne change rien.
- [x] Étant donné le « + » d'une carte, alors un exemplaire est ajouté (même règle de boutique).
- [x] Étant donné l'écran Panier, quand l'acheteur change une quantité, alors le serveur
      l'enregistre et le sous-total suit ; « − » à 1 retire la ligne et « Annuler » la remet.
- [x] Étant donné une ligne indisponible ou au-delà du stock, alors sa raison s'affiche,
      « Retirer » ou « Ajuster » la corrige, et « Commander » est désactivé tant qu'elle reste.
- [x] Étant donné une boutique qui ne prend plus de commandes, alors le panier le dit et
      « Commander » est désactivé.
- [x] Étant donné « Vider » confirmé, alors `DELETE /v1/cart` est envoyé et le panier vide
      s'affiche.
- [x] Étant donné un panier de la boutique ouverte, alors la fiche boutique affiche « Voir le
      panier » avec le nombre d'articles et le sous-total.

## Cas limites et erreurs

- **Stock insuffisant à l'ajout** (`insufficient_stock`) : message du serveur (« Seulement 2 en
  stock. »), rien n'est ajouté.
- **Produit devenu indisponible** (`product_unavailable`, 404) : « Ce produit n'est plus
  disponible. »
- **Limite du stock ou de 99** : sur la fiche produit, la quantité s'arrête à ce qui reste
  ajoutable ; tout déjà au panier ⇒ « Tout le stock est au panier » (ou « 99 au plus : déjà au
  panier »), bouton désactivé. Sur l'écran Panier, le stock d'une ligne commandable n'est pas
  connu de l'app : le refus du serveur (« Seulement 2 en stock. ») fait office de limite et la
  quantité revient à la valeur enregistrée. « + » d'une carte à 99 : « 99 exemplaires au plus par
  produit ».
- **« Annuler » après un retrait** : remet la quantité enregistrée avant le retrait, même après
  avoir quitté l'écran Panier ; la ligne revient en fin de liste (le serveur range les lignes par
  date d'ajout).
- **« Vider » pendant un envoi** : les envois en cours finissent d'abord, rien ne part ensuite, et
  le panier ne se modifie pas pendant le vidage : le serveur ne recrée jamais le panier vidé.
- **Messages avec action** (« Voir le panier », « Annuler ») : visibles 6 secondes, sauf avec une
  aide à la navigation (lecteur d'écran), où ils restent jusqu'à l'action ou un glissement.
- **Panier plein** (30 produits différents, `cart_full`) : message du serveur.
- **Réseau coupé** pendant un changement de quantité : message, la quantité revient à la
  valeur enregistrée ; au chargement du panier : message et « Réessayer ».
- **Appuis rapides sur + / −** : une seule requête à la fois par ligne, la dernière quantité
  voulue gagne.
- **Autre compte** sur le même téléphone : le panier affiché est celui du compte connecté
  (relu à chaque connexion).
- **Police à 200 %, écran de 320 dp** : rien n'est masqué.

## Hors périmètre

- Commande (choix retrait ou livraison, adresse, frais) : 009 et 020 ; paiement : 010.
- Panier sans compte (l'acheteur est toujours connecté dans l'app).
- Plusieurs paniers ou listes d'envies.
- Bandeau « commande en cours » de l'accueil (013).

## Questions ouvertes

<!-- Vide = prêt pour le plan. -->
