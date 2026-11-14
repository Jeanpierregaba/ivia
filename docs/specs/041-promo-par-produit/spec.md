# 041 — Codes promo limités à certains produits

<!-- Demandé le 2026-11-14 ; spec écrite avec le code. Complète la spec 034. -->

## Objectif
Un code promo n'est plus forcément valable sur toute la boutique. Le marchand (ou ivia pour la
boutique IVI) choisit à quoi il s'applique :
- **toute la boutique** (comme avant) ;
- **certains produits** (plusieurs produits choisis) ;
- **un seul produit**.

## Règles
- Seuls les produits de la boutique du code peuvent être choisis (100 au plus, sans doublon).
  Un produit d'une autre boutique est refusé à la création (400).
- La réduction ne porte que sur les lignes du panier qui contiennent les produits visés :
  - le pourcentage s'applique à ces lignes seulement ;
  - le montant fixe est plafonné à leur montant.
- Si aucun produit visé n'est dans le panier, le code est refusé (`promo_not_applicable`, « Ce
  code promo ne concerne aucun produit de votre panier. »).
- L'achat minimum se compte toujours sur tout le panier.
- Le reste ne change pas (durée, utilisations, frais à la charge de qui crée le code).

## Données et API
- Migration 00050 `promo_code_products` (additive). Un code sans ligne dans cette table vaut
  pour toute la boutique.
- `product_ids` dans la création (marchand et back-office) ; `scope` (`shop` ou `products`) et
  `products` (`id`, `name`) dans chaque code renvoyé.

## Écrans
- **Ivia Business** :
  - « S'applique à » dans « Nouveau code promo » : Toute la boutique ou Certains produits, avec
    un sélecteur qui permet de chercher et de cocher ;
  - dans le menu de chaque produit, « Code promo pour ce produit » ouvre le formulaire avec ce
    produit déjà choisi ;
  - la carte du code indique sa portée.
- **Back-office** (codes IVI) : même choix ; la liste montre la portée.
- **ivia** : « Mes coupons » indique « Sur <produit> » quand le code est limité.

## Tests
- `internal/app/promo_products_test.go` :
  - réduction limitée aux lignes visées ;
  - code refusé si aucun produit visé n'est dans le panier ;
  - toute la boutique, comme avant ;
  - produit d'autrui refusé.
- App Business : création d'un code depuis la ligne d'un produit.
