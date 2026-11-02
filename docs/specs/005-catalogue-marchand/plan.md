# 005 — Plan technique

## Approche

- **Backend : une petite extension du module `catalog`.** L'API produit existe déjà (création,
  modification, stock, photos par URL signée). On ajoute deux choses :
  - deux dates (`published_at`, `withdrawn_at`), qui distinguent le brouillon du produit retiré
    sans toucher à `is_active`. La recherche et le panier lisent toujours `is_active`, donc ils ne
    changent pas ;
  - un filtre par état, une recherche et des compteurs sur la liste du marchand.
- **Mobile : le catalogue dans l'app marchand**, derrière une barre du bas à 4 onglets
  (`StatefulShellRoute` de go_router).
  - Création et reprise d'un brouillon : un seul écran à étapes (1, 2, aperçu). Ses données vivent
    dans un contrôleur commun ; rien n'est envoyé avant « Brouillon » ou « Publier ».
  - Modification d'un produit en vente ou retiré : un écran à part, comme sur la maquette.
- **Photos envoyées à l'enregistrement, pas au choix.** Un produit abandonné ne laisse donc aucun
  fichier. Chaque photo garde sa clé une fois envoyée : un nouvel essai ne la renvoie pas.

## Fichiers touchés

**Backend** (`backend/`)
- `db/migrations/00021_product_publication.sql` (créé) : colonnes, reprise des données
  existantes, contrainte de cohérence.
- `internal/catalog/queries.sql`, `store/` (régénéré) :
  - `CreateProduct` reçoit `is_active` ;
  - `UpdateProduct` gère les dates ;
  - nouvelles requêtes `ListSellerProducts` (état, recherche) et `CountSellerProducts`.
- `internal/catalog/service.go` :
  - `Product` gagne `Status`, `PublishedAt`, `WithdrawnAt` ;
  - `Create` respecte `IsActive` (vrai par défaut) ;
  - `ListForSeller` reçoit un filtre ;
  - nouvelle méthode `CountForSeller`.
- `internal/catalog/handler.go` : paramètres `status` et `q`, route des compteurs.
- `api/openapi.yaml` : schémas `Product`, `ProductInput`, `ProductCounts`, paramètres et nouvelle
  route.
- `internal/app/catalog_test.go` (créé) : tests de bout en bout (états, dates, filtres,
  compteurs, accès d'autrui). `access_test.go` : nouvelle route dans la liste des accès.

**Mobile** (`mobile/`)
- `packages/api_client`
  - `models.dart` : `Product`, `ProductStatus`, `ParcelSize`, `StockMode`, `ProductImage`,
    `ProductInput`, `ProductCounts`, `ProductCategory`, `Page<T>`.
  - `client.dart` : `productCategories`, `sellerProducts`, `productCounts`, `sellerProduct`,
    `createProduct`, `updateProduct`, `setStock`.
  - `testing.dart` : `productBody`, `productCountsBody`, `productCategoriesBody` et routes du faux
    serveur. Le faux serveur garde les produits créés et applique les filtres, comme le vrai.
- `packages/app_core`
  - `formats.dart` (créé) : `formatXof` (« 4 500 F », espace insécable), `parseXof`, `shortDate`
    (« 24 oct. », « aujourd'hui »). Lomé est en UTC toute l'année : pas de fuseau à gérer.
- `packages/ui`
  - `navigation.dart` (créé) : `IviaBottomNav`, barre en pilule ; l'onglet actif est étiqueté.
  - `segmented_tabs.dart` (créé) : `IviaSegmentedTabs`, onglets avec compteur.
  - `form_controls.dart` (créé) :
    - `IviaSearchField` ;
    - `IviaQuantityStepper` (− / saisie / +) ;
    - `IviaChoiceCard` (taille du colis) ;
    - `IviaStatusPill`.
- `apps/seller`
  - `app/router.dart`
    - Shell à 4 branches `/home`, `/orders`, `/catalog`, `/account`.
    - Routes `/catalog/new`, `/catalog/draft/:id`, `/catalog/:id/edit`, `/catalog/published`.
    - `redirectFor` accepte des préfixes. Boutique en validation : `/catalog…` sans barre.
  - `features/shell/seller_shell.dart` (créé) : barre du bas, masquée hors boutique publiée.
  - `features/catalog/` (créé)
    - Contrôleurs :
      - `catalog_controller.dart` : liste paginée par onglet et recherche, recherche
        différée de 300 ms ;
      - `catalog_counts.dart`.
    - Écrans :
      - `catalog_screen.dart` et `product_row.dart` ;
      - `product_editor_controller.dart` : brouillon local, photos, enregistrement ;
      - `product_editor_screen.dart` : étapes 1 et 2 ;
      - `product_preview_screen.dart` et `product_published_screen.dart` ;
      - `product_edit_screen.dart`.
    - Champs du formulaire :
      - `photos_field.dart`, `category_field.dart`, `price_field.dart` ;
      - feuilles `description_sheet.dart`, `parcel_sheet.dart`, `stock_sheet.dart` ;
      - `withdraw_sheet.dart`.
    - `catalog_labels.dart` : textes d'état, de stock, de taille.
  - `features/account/account_screen.dart` et `features/orders/orders_placeholder_screen.dart`
    (créés).
  - `features/home/products_placeholder_screen.dart` (supprimé). « Préparer mes produits » ouvre
    `/catalog`.
- Tests
  - `apps/seller/test/` : `router_test`, `catalog_test`, `product_editor_test`,
    `product_edit_test`.
  - `packages/api_client/test`, `packages/app_core/test` (formats), `packages/ui/test` (nouveaux
    composants).

**Docs** : `DESIGN.md` (écrans du catalogue, barre du bas), `ARCHITECTURE.md` (états d'un
produit), `TASKS.md`.

## Données

Migration `00021_product_publication.sql`, non destructive.

```sql
ALTER TABLE products
  ADD COLUMN published_at timestamptz,  -- dernière mise en vente ; NULL = brouillon
  ADD COLUMN withdrawn_at timestamptz;  -- dernier retrait ; NULL si en vente ou brouillon
-- Existant : un produit actif est « en vente », un inactif est « retiré » (jamais de brouillon avant).
UPDATE products SET published_at = created_at;
UPDATE products SET withdrawn_at = updated_at WHERE NOT is_active;
ALTER TABLE products ADD CONSTRAINT products_publication_check CHECK (
  (is_active AND published_at IS NOT NULL AND withdrawn_at IS NULL)
  OR (NOT is_active AND published_at IS NULL AND withdrawn_at IS NULL)      -- brouillon
  OR (NOT is_active AND published_at IS NOT NULL AND withdrawn_at IS NOT NULL) -- retiré
);
```

Les transitions sont faites par le SQL de `UpdateProduct`, à partir de l'ancien état de la ligne :

| Avant → après | `published_at` | `withdrawn_at` |
|---|---|---|
| brouillon → brouillon | NULL | NULL |
| brouillon ou retiré → en vente | `now()` | NULL |
| en vente → en vente | inchangé | NULL |
| en vente → retiré | inchangé | `now()` |
| retiré → retiré | inchangé | inchangé |

La contrainte rend impossible un état incohérent, même par une requête future mal écrite. État
exposé par l'API (`status`) : `active` si `is_active`, sinon `draft` si `published_at` est NULL,
sinon `withdrawn`.

## API / interfaces

- `GET /v1/seller/shops/{id}/products?status=active|draft|withdrawn&q=…&limit&offset`
  - `status` est facultatif (tous les états) ; une autre valeur répond 400.
  - `q` : 100 caractères au plus. Le nom contient `q`, sans tenir compte des accents ni des
    majuscules (`immutable_unaccent(lower(name)) LIKE …`, index trigramme existant). `%`, `_` et
    `\` sont échappés.
  - Tri : retiré par `withdrawn_at` décroissant, sinon `created_at` décroissant.
- `GET /v1/seller/shops/{id}/product-counts` (créé) → `{"active": 20, "draft": 2, "withdrawn": 3}`.
  Boutique d'autrui : 404 `shop_not_found`.
- `Product` gagne `status`, `published_at`, `withdrawn_at`. `ProductInput.is_active` à la
  création : `false` crée un brouillon ; absent, le produit est en vente comme aujourd'hui.

Autres routes inchangées :
- `PATCH /v1/seller/products/{id}` : `is_active` publie ou retire, `image_keys` ordonne les photos ;
- `PUT /v1/seller/products/{id}/stock` : quantité ;
- `GET /v1/categories` : catégories de produits ;
- `POST /v1/uploads` avec `purpose: product_image`.

## Dépendances

Aucune nouvelle. `StatefulShellRoute.indexedStack` fait partie de go_router 18.1.2, déjà utilisé :
je vérifierai sa doc à jour (Context7) avant de l'écrire.

## Sécurité

- **Contrôle d'accès** : les nouvelles routes passent par `shops.RequireOwned`. La boutique d'un
  autre marchand répond 404 (règle 3) ; un test le vérifie pour la liste filtrée et les compteurs.
- **Requêtes** : `q` et `status` sont des paramètres sqlc, jamais concaténés. `q` est borné à
  100 caractères et ses jokers sont échappés.
- **Photos** : redimensionnées à 1600 px au plus, réencodées en JPEG sans métadonnées EXIF (donc
  sans position GPS) par `PhotoPicker`, puis envoyées par URL signée sans jeton de session.
- **Journaux** : rien de personnel ; aucune donnée de produit n'est journalisée.

## Tests

- **Backend**
  - Les transitions du tableau ci-dessus.
  - La contrainte refuse un état incohérent (UPDATE direct).
  - La création en brouillon, et la création sans `is_active`, qui reste en vente.
  - Filtres `status` et `q` (accents, majuscules, `%` littéral), compteurs, pagination.
  - 404 sur la boutique d'autrui, 400 sur un `status` inconnu.
  - Couverture OpenAPI.
- **Mobile** (faux serveur fidèle)
  - Routeur : shell et préfixes ; en validation, le catalogue est sans barre.
  - Catalogue :
    - onglets et compteurs ;
    - recherche différée envoyée au serveur ;
    - états vides et défilement qui charge la suite ;
    - retrait avec annulation, et « Remettre ».
  - Création :
    - validations, publication complète (photos dans l'ordre, clés réutilisées après un échec) ;
    - brouillon, puis reprise du brouillon ;
    - double appui ;
    - texte « visible dès validation » si la boutique est en attente.
  - Modification : enregistrement, retrait, stock, catégorie refusée par le serveur.
  - Police à 200 % sur 320 dp pour le catalogue et le formulaire.
- Aucune partie de `docs/TESTING.md` « critique » n'est touchée : la réservation de stock reste
  inchangée.

## Risques

- **La migration modifie le module `catalog`, côté Gedeon** : elle doit passer par sa relecture
  (`docs/RULES.md`), et des conflits sont possibles s'il touche ce module en même temps. Je
  l'isole dans un commit backend à part, en tête, pour qu'il puisse la relire seule.
- **Le shell de navigation change la structure du routeur marchand** : les tests du routeur
  existants doivent continuer de passer (écran de validation, refus, hors ligne).
- **Brouillon et mode de stock** : le mode est figé dès l'enregistrement du brouillon. La spec
  l'assume ; l'écran l'explique.
