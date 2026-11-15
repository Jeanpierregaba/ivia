# 040 — Refonte d'Ivia Business (lot 1)

<!-- Demandé le 2026-11-14 ; spec écrite avec le code. Maquettes : B00 à B25 (charte d'origine) et
     la maquette « Products / Create Product / Add Media » fournie par Gedeon. -->

## Objectif
Une app marchand nettement plus agréable et plus rapide à utiliser, dans la charte d'origine
d'Ivia Business (bleu nuit, cartes blanches très arrondies, rouge réservé à l'urgence), avec une
réponse visible à chaque geste. Le parcours de base ne change pas : boutique → produits →
commandes → remise → relevés.

## Ce qui change
- **Barre du bas** en pilule flottante : Accueil, Commandes, **+**, Produits, Profil. L'onglet actif
  s'étire avec son nom. Le **+** ouvre « Créer et gérer » : nouveau produit (ou plat), code promo,
  commandes à accepter, revenus.
- **Accueil** (maquette B10) : en-tête bleu nuit (boutique, en ligne, quartier, ventes du jour,
  commandes). Les commandes payées s'**acceptent ou se refusent sur place**. Tuiles En
  préparation, Prêtes, Stock bas. Les commandes en cours avancent d'un geste (« Préparer »,
  « Prête ? »). Une rangée « À réapprovisionner » montre les produits à 3 en stock ou moins.
- **Produits** : grand titre, recherche, filtre par catégorie (sous-catégories comprises, côté
  serveur), affichage en liste ou en grille, puces En vente, Brouillons et Retirés avec leurs
  compteurs. Chaque ligne a une pastille d'état et un point de stock (vert, ambre, rouge).
  Gestes :
  - glisser vers la droite pour retirer ou remettre en vente ;
  - glisser vers la gauche pour ajuster le stock ;
  - appui long pour la sélection multiple (retrait ou mise en vente groupés) ;
  - squelettes animés pendant le chargement.
- **Nouveau produit** sur une seule page : Photos, Informations, Statut (En vente ou Brouillon),
  Prix et catégorie (« + Ajouter »), Livraison et stock. Une jauge « x sur 5 » suit la saisie et
  un aperçu acheteur s'ouvre à tout moment. La barre fixe propose Annuler et Publier (ou
  Enregistrer). Les erreurs sont toutes signalées d'un coup et la page défile jusqu'à la
  première.
- **Ajouter des photos** : la **Bibliothèque** reprend les photos déjà envoyées par la boutique,
  sans les renvoyer. **Importer** utilise l'appareil photo ou la galerie. La sélection est
  numérotée (la 1re photo est la principale), avec 5 photos au plus et « Tout désélectionner ».
  Dans le formulaire, les photos se réordonnent par appui long et glisser.

## Serveur
- `GET /v1/seller/shops/{id}/media` : photos des produits de la boutique, sans doublon, la plus
  récente d'abord (120 au plus). Seules les photos envoyées par le marchand sont renvoyées : une
  photo d'admin ne peut pas être reprise. Boutique d'autrui : 404.
- `GET /v1/seller/shops/{id}/products?category_id=` : filtre par catégorie (avec ses
  sous-catégories).
- Aucune migration.

## Tests
- `internal/app/seller_media_test.go` :
  - bibliothèque sans doublon ;
  - réutilisation d'une photo ;
  - photo d'autrui refusée ;
  - boutique d'autrui refusée ;
  - filtre par catégorie.
- App Business : 158 tests, dont :
  - une page complète ;
  - validations ;
  - brouillon puis reprise ;
  - bibliothèque ;
  - filtre par catégorie ;
  - sélection multiple ;
  - glissement vers le stock ;
  - grille ;
  - menu « + » ;
  - « Accepter » sur l'Accueil ;
  - police à 200 % sur 320 dp.

## Reste (lot 1 bis)
- Écran Commandes et détail d'une commande dans la même charte.
- Écran « Modifier » d'un produit sur le modèle de « Nouveau produit ».
- Lecture d'un code-barres pour retrouver un produit (champ code-barres à ajouter côté serveur).
