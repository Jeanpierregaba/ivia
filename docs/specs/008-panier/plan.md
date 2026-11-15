# 008 — Plan technique

## Approche

- **Aucun changement serveur.** Routes existantes et testées (module `cart`) :
  `GET /v1/cart`, `PUT /v1/cart/items` (`product_id`, `quantity` totale, 0 = retirer,
  `replace_cart`), `DELETE /v1/cart`. Le panier renvoyé est recalculé au prix et au stock du
  moment : `shop`, `items` (avec `issue`), `subtotal_xof`, `orderable`.
- **Un seul état du panier dans l'app** (`cartProvider`, relu à chaque connexion) : le badge,
  la barre de la fiche boutique et l'écran Panier le lisent. Chaque modification renvoie le panier
  complet du serveur, qui remplace l'état : pas de calcul de prix côté app.
- **Ajout** : l'app envoie la quantité totale (déjà au panier + ajoutée). Conflit de boutique
  (`409 cart_shop_conflict`) : feuille « Vider le panier ? », puis le même appel avec
  `replace_cart: true`.
- **Quantités sur l'écran Panier** : une requête à la fois par ligne ; les appuis faits pendant
  l'envoi sont regroupés et la dernière quantité voulue est envoyée ensuite. En cas d'échec, la
  ligne revient à la valeur enregistrée.

## Fichiers touchés

**`packages/api_client`**
- `models.dart` : `Cart`, `CartItem` (dont `issue`), `articleCount`.
- `client.dart` : `cart()`, `setCartItem(productId, quantity, {replaceCart})`, `clearCart()`.
- `testing.dart` : `FakeCart`, branché sur `FakeSearch` (produits, boutiques, stock), fidèle au
  module `cart` : boutique unique et `replace_cart`, `product_unavailable`, `insufficient_stock`,
  99 par ligne, 30 lignes, `issue` et `orderable` recalculés à la lecture.

**`packages/ui`**
- `IviaProductCard` : bouton « + » facultatif (`onAdd`) sur la photo.
- `IviaIconBadgeButton` : icône ronde avec badge (le panier).

**`apps/buyer`**
- `app/cart.dart` : `cartProvider` (lecture, ajout, quantité, vidage, remise à zéro au changement
  de compte), `addToCart(...)` (feuille de conflit, messages).
- `features/cart/cart_screen.dart`, `cart_line.dart`, `cart_button.dart`, `cart_bar.dart`.
- Route `/cart` sur le navigateur racine (au-dessus de la barre du bas).
- Accueil, fiche boutique, fiche produit : icône du panier ; fiche boutique : « + » et barre
  « Voir le panier » ; fiche produit : « Ajouter » branché ; recherche et accueil : « + » des
  cartes.

**Docs** : `DESIGN.md` (panier, badge), `TASKS.md`.

## Données

Aucune migration. Le panier n'est pas gardé sur le téléphone (il est sur le serveur).

## API / interfaces

Voir Approche. Codes d'erreur utilisés : `cart_shop_conflict`, `product_unavailable`,
`product_not_found`, `insufficient_stock`, `cart_full`, `validation_failed` (quantité).

## Dépendances

Aucune.

## Sécurité

- Routes réservées au rôle `buyer`, panier propre au compte (le serveur ne lit que celui du jeton).
- Prix et sous-total viennent toujours du serveur : l'app n'en calcule aucun qui serait envoyé.

## Tests

- `api_client` : modèles, méthodes, `FakeCart` (règles du module `cart`).
- `ui` : « + » des cartes, badge (sémantique, 48 dp, police à 200 %).
- App acheteur :
  - ajout depuis la fiche produit (cumul, message), « + » des cartes et de la fiche boutique ;
  - conflit de boutique (vider et ajouter, annuler) ;
  - écran Panier : quantités (+, −, retrait et « Annuler »), lignes en erreur (« Retirer »,
    « Ajuster »), boutique fermée, « Vider », panier vide, réseau coupé, appuis rapides ;
  - badge et barre « Voir le panier » ;
  - changement de compte ; police à 200 % sur 320 dp.

## Risques

- **Appuis rapides** sur + / − : sans regroupement, des réponses dans le désordre afficheraient une
  quantité ancienne ; couvert par la file d'une requête à la fois par ligne.
- **Panier relu à chaque modification** : une réponse un peu plus lourde, mais toujours juste
  (prix et stock du moment) ; acceptable pour un panier de 30 lignes au plus.
