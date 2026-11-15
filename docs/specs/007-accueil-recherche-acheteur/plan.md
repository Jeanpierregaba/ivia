# 007 — Plan technique

## Approche

- **Aucun changement côté serveur.** Les routes existent et sont testées :
  - `GET /v1/search/products` et `GET /v1/search/shops` : texte, catégorie, prix, quartier,
    rayon, tri, pagination ;
  - `GET /v1/products/{id}` (produit et boutique), `GET /v1/shops/{id}` ;
  - `GET /v1/categories`, `GET /v1/neighborhoods`.
- **Position partagée** : le service de position de l'app marchand passe dans `app_core` pour
  servir aux deux apps. L'acheteur demande une précision approximative (suffisante pour un rayon
  de 1 km, moins intrusive).
- **Zone de recherche** : un état unique (`buyerAreaProvider`) vaut « position du téléphone »,
  « quartier choisi » ou « inconnue ». Chaque recherche le traduit en paramètres (`lat`/`lng` ou
  `neighborhood_id`). Le quartier choisi est gardé dans `shared_preferences` (aucune donnée
  sensible) ; la position n'est jamais stockée.
- **Shell à 4 onglets** comme le marchand (`StatefulShellRoute`), avec le composant
  `IviaBottomNav` déjà dans `ui` : Accueil, Recherche, Commandes, Profil. La recherche est un
  onglet ; l'accueil y envoie sa requête (texte, catégorie, onglet) par un état partagé. Fiche
  boutique et fiche produit s'ouvrent par-dessus la barre.
- **Résultats** : un contrôleur par requête (onglet, texte, filtres, tri), paginé au défilement,
  avec la même garde que le catalogue marchand (une page en retard après un rechargement est
  ignorée).

## Fichiers touchés

**`packages/app_core`**
- `location.dart` (créé, repris de `apps/seller/lib/app/device_services.dart`) :
  `LocationService`, `LocationResult`, `DeviceLocationService` (précision réglable),
  `locationServiceProvider`. `geolocator` passe de l'app marchand à `app_core`.
- `formats.dart` : `formatDistance` (« 350 m », « 1,2 km »).

**`packages/api_client`**
- `models.dart` : `ProductHit`, `ShopHit`, `PublicShop`, `PublicProduct` (produit et boutique),
  `SearchQuery` (paramètres), `Neighborhood` (avec centre).
- `client.dart` : `searchProducts`, `searchShops`, `publicProduct`, `publicShop`.
- `testing.dart` : `FakeSearch` (faux serveur fidèle : filtres, tri, distance, pagination, 429).

**`packages/ui`**
- `IviaChip` (puce de filtre avec flèche, active ou non), `IviaProductCard` (carte de la grille),
  `IviaPhotoCarousel` (photos et points, repris de l'aperçu du catalogue marchand), si leur
  usage dépasse une app ; sinon dans l'app acheteur.

**`apps/buyer`**
- `app/router.dart` : shell (`/home`, `/search`, `/orders`, `/profile`), routes `/shops/:id`
  et `/products/:id` sur le navigateur racine ; `redirectFor` à préfixes. La route actuelle
  `/profile` (« Faisons connaissance ») devient `/welcome` pour libérer le nom.
- `app/buyer_area.dart` : `buyerAreaProvider` (position, quartier, inconnue), mémorisation du
  quartier.
- `features/shell/`, `features/profile/`, `features/orders/` (« Bientôt disponible »).
- `features/home/` : en-tête de position, feuille de choix, sections boutiques et nouveautés.
- `features/search/` : écran de résultats, filtres (feuilles rayon, catégorie, prix, tri),
  contrôleur paginé.
- `features/shop/` et `features/product/` : fiches.
- iOS `Info.plist` : `NSLocationWhenInUseUsageDescription` ; Android :
  `ACCESS_COARSE_LOCATION` seulement.
- Suppression de `features/home/home_placeholder_screen.dart`.

**`apps/seller`** : import de la position depuis `app_core` (comportement inchangé, tests
existants).

**Docs** : `DESIGN.md` (écrans acheteur, puces de filtre), `ARCHITECTURE.md` (position partagée),
`TASKS.md`.

## Données

Aucune migration. Préférence locale `buyer_area` : `n|<id>|<nom>` (quartier choisi) ou
`position` (position du téléphone, jamais ses coordonnées).

## API / interfaces

Paramètres envoyés à `GET /v1/search/products` : `q`, `lat`, `lng`, `radius_m`,
`neighborhood_id`, `category_id`, `shop_id`, `min_price`, `max_price`, `in_stock`, `sort`,
`limit`, `offset`. Boutiques : `q`, `lat`, `lng`, `radius_m`, `neighborhood_id`, `sort`,
`limit`, `offset`. Le nom du quartier d'un résultat vient de `GET /v1/neighborhoods` (chargé une
fois).

## Dépendances

Aucune nouvelle : `geolocator` 14.1.2 (déjà dans le workspace) passe dans `app_core`. Je relirai
sa doc pour la précision approximative (`LocationAccuracy.low` / `medium`) et la permission
Android `ACCESS_COARSE_LOCATION`.

## Sécurité

- Position : demandée seulement à l'accueil, précision approximative, jamais stockée ni
  journalisée ; envoyée uniquement en paramètre de recherche (HTTPS en production).
- Routes publiques sans jeton requis ; le jeton de session est envoyé comme partout (le client
  l'ajoute), sans effet sur la recherche.
- Texte cherché borné à 100 caractères côté app comme côté serveur.

## Tests

- `api_client` : paramètres envoyés (position ou quartier, filtres, tri), lecture des résultats,
  429 traduit en message.
- `app_core` : `formatDistance`.
- App acheteur (faux serveur fidèle) :
  - routeur et barre du bas ;
  - position autorisée, refusée, quartier mémorisé ;
  - accueil (sections, puces, « Voir tout », vides, erreurs) ;
  - résultats (délai de frappe, onglets, chaque filtre et tri, pagination, vide avec « Effacer les
    filtres ») ;
  - fiches boutique et produit (404, photos absentes, « Ajouter ») ;
  - police à 200 % sur 320 dp.
- App marchand : tests existants inchangés après le déplacement de la position.

## Risques

- **Déplacement de la position vers `app_core`** : touche l'app marchand ; ses tests de position
  (formulaire de boutique) doivent passer sans changement.
- **Pas de total de résultats** : la grille ne sait pas combien il reste ; la pagination repose
  sur `next_offset`, comme le catalogue.
- **Recherche d'une boutique par nom côté serveur** (`SearchShops`) : le `LIKE` n'échappe pas
  `%` et `_`. C'est sans risque de sécurité (paramètre sqlc), mais « 100% » trouve trop de
  boutiques. Je le signale à Gedeon plutôt que de modifier le module search ici.
