# 004 — Plan technique

## Approche

**1. Mettre en commun la connexion avant de la dupliquer.** L'état de session, le parcours e-mail →
code, les écrans de connexion, `AsyncButton`, `LegalText`, le stockage « présentation vue » et le
nettoyage après réinstallation sont aujourd'hui dans `apps/buyer`. Ils passent dans un nouveau
paquet du workspace, **`packages/app_core`**, qui dépend de `api_client`, `ui`, Riverpod et
go_router. Chaque app ne fournit plus que :
- sa configuration (`AppIdentity` : marque, textes de l'écran e-mail, de l'encart du code, slogan) ;
- ses écrans propres ;
- sa table de redirection.

L'app acheteur est migrée sans changement visible : ses 60 tests doivent rester verts. Ce paquet
s'ajoute à ceux de l'[ADR 0002](../../decisions/0002-trois-apps-flutter-workspace.md) ; ce choix est
noté dans ARCHITECTURE (pas de nouvel ADR, car il ne change pas la décision).

**2. Thème par app.** `IviaAppBrand` gagne :
- `action` : boutons, champ actif, indicateur. Imperial pour l'acheteur, Berkeley pour le marchand ;
- `link` : texte cliquable. Cornell pour l'acheteur, Berkeley pour le marchand ;
- `highlight` : partie colorée des titres. Imperial pour l'acheteur, Cobalt pour le marchand.

`IviaTheme.light(brand)` en dérive le `ColorScheme`. L'app livreur garde la valeur actuelle en
attendant ses maquettes. Les contrastes sont vérifiés dans `contrast_test.dart` :
- blanc sur Berkeley : 13,7 ;
- Cobalt sur `#F3F4F6` : environ 6,8.

**3. Backend : catégories de boutique** (module `shops`, car `catalog` dépend déjà de `shops`) :
- migration `00019` : table `shop_categories` (id, nom unique, position, active), liste de départ
  (Alimentation, Mode et beauté, Maison, Électronique et téléphonie, Santé et bien-être, Services,
  Autre) et colonne `shops.category_id` (nullable : les boutiques existantes n'en ont pas) ;
- route `GET /v1/shop-categories`, publique, pour les catégories actives ;
- `ShopInput.category_id` : obligatoire à la création (`validation_failed` sinon), modifiable
  ensuite ; `Shop` expose `category_id` et `category_name` ;
- `openapi.yaml` dans le même commit, avec des tests Go.

**4. Carte** (choix d'`architecture-feat-map.md` : Google Maps SDK pour l'affichage) :
- `google_maps_flutter`, épingle déplaçable et bouton « Ma position » (`geolocator`, permission
  « pendant l'utilisation »).
- Clés restreintes : Android par paquet + SHA-1, iOS par bundle. Elles sont lues au build et ne
  sont jamais committées :
  - Android : `MAPS_API_KEY` dans `android/local.properties` ;
  - iOS : `Maps.xcconfig` ignoré par git.
  La carte n'est activée qu'avec `--dart-define=GOOGLE_MAPS=true`. Sinon, un aperçu sans fond de
  carte est affiché (épingle, coordonnées, « Ma position »), car le SDK iOS plante sans clé.
- Aucun appel de géocodage depuis l'app (règle d'or du document) ; l'adresse est saisie.

**5. Logo** : `image_picker` (galerie ; plus grand côté borné à 1024 px), puis
`flutter_image_compress` (réencodage JPEG sans métadonnées EXIF ni GPS) — `PhotoPicker`
d'`app_core`, partagé avec le livreur, puis `POST /v1/uploads` (`shop_logo`), puis `PUT`
sur l'URL signée (dio, sans jeton), puis `logo_key` dans `POST /v1/shops`.

**6. Navigation du marchand** : `SellerSession` combine la session (`app_core`) et
`GET /v1/seller/shops` :

| État | Écran |
|---|---|
| démarrage | splash |
| déconnecté | présentation ou connexion |
| connecté, aucune boutique | « Créez votre boutique » |
| boutique `pending_review` | « En cours de validation » |
| boutique `rejected` / `suspended` | information avec le motif |
| boutique `published` | accueil provisoire |

Le consentement est demandé par la case du formulaire boutique : `PATCH /v1/me`
`accept_privacy_policy` est envoyé juste avant `POST /v1/shops`. Le prénom n'est pas demandé.
L'état « profil incomplet » n'envoie donc pas le marchand vers « Faisons connaissance ».

## Fichiers touchés

- **Backend** :
  - `db/migrations/00019_shop_categories.sql` ;
  - `internal/shops/` : queries, service, handler, store généré ;
  - `api/openapi.yaml` ;
  - `internal/app/` : tests et données de démonstration (catégorie de la boutique de démo).
- **`packages/app_core`** (nouveau) : `auth_controller.dart`, `login_flow.dart`, `email_screen.dart`,
  `code_screen.dart`, `profile_screen.dart` (pour l'acheteur), `offline_screen.dart`,
  `onboarding_store.dart`, `first_launch.dart`, `async_button.dart`, `legal_text.dart`,
  `button_progress.dart`, `phone_format.dart`, `app_identity.dart`, plus leurs tests (repris de
  l'acheteur).
- **`packages/ui`** : `IviaAppBrand` (couleurs d'action), `IviaTheme.light(brand)`,
  `IviaLoadingSplash` (variante tuile et sous-titre), `IviaStepList` (étapes de validation),
  `IviaSelectField` (liste déroulante au style des champs).
- **`packages/api_client`** : catégories de boutique, quartiers, boutiques (création, liste),
  envoi de fichier (URL signée).
- **`apps/buyer`** : imports vers `app_core`, plus rien d'autre.
- **`apps/seller`** : `main.dart`, routeur, `seller_session.dart`, illustrations, présentation,
  `shop_form_screen.dart`, `shop_location_field.dart`, `shop_logo_field.dart`,
  `shop_pending_screen.dart`, `shop_blocked_screen.dart`, accueil et produits provisoires ;
  permissions de localisation, photos et appareil photo (Info.plist, manifeste) ; clés Maps ;
  tests.
- **Docs** : DESIGN.md (couleurs par app, nouveaux composants, écrans marchand), ARCHITECTURE.md
  (paquet `app_core`, catégories de boutique), AGENTS.md (clés Google Maps en local), `.gitignore`.

## Données

Migration `00019` **non destructive** : nouvelle table et colonne nullable.

## API / interfaces

- Nouvelle route : `GET /v1/shop-categories`.
- Changements : `ShopInput.category_id`, `Shop.category_id` et `Shop.category_name`.
- Routes déjà en place, utilisées par l'app : `POST /v1/shops`, `GET /v1/seller/shops`,
  `GET /v1/neighborhoods`, `POST /v1/uploads`, `PATCH /v1/me`.

## Dépendances

Vérifiées sur pub.dev le 2026-10-31. La documentation à jour sera consultée via Context7 au moment
de coder.

| Paquet | Version | Pourquoi |
|---|---|---|
| `google_maps_flutter` | ^2.19.0 | carte (stack prévue, `architecture-feat-map.md`) |
| `geolocator` | ^14.1.2 | « Ma position » |
| `image_picker` | ^1.2.4 | choix du logo |
| `flutter_image_compress` | ^2.5.1 | redimensionnement et suppression des métadonnées (PRD, SECURITY) |

## Sécurité

- **Clés Google Maps** : restreintes aux apps, hors du dépôt. C'est la seule clé embarquée permise
  par RULES.
- **Logo** : métadonnées supprimées ; type et taille imposés par l'URL signée ; clé de fichier
  choisie par le serveur.
- **Localisation** : demandée seulement au tap sur « Ma position », avec un texte d'explication
  (Info.plist, Play Console). Elle n'est jamais envoyée ailleurs que dans la boutique.
- **Consentement** : daté par le serveur avant la création de la boutique.

## Tests

- **Go** :
  - catégories (liste, inactives exclues) ;
  - création sans catégorie ou avec une catégorie inconnue refusée ;
  - `category_name` renvoyé ;
  - contrat OpenAPI.
- **`app_core`** : les tests de connexion de l'acheteur, déplacés et paramétrés.
- **`ui`** : thème par app (couleur des boutons, du champ actif, des liens), splash tuile, liste
  d'étapes, contrastes.
- **Marchand** :
  - parcours complets contre le faux serveur : présentation, connexion, création de la boutique
    (avec et sans logo, refus de localisation, erreurs par champ, réseau, double appui), écran
    en attente puis publiée, refus ;
  - police à 200 % sur 320 dp.
- **Manuel** : simulateur iPhone 17 Pro contre l'API locale (sans clé Maps : aperçu), et
  validation de la boutique par l'admin avec `curl`.

## Risques

- **Refactorisation de l'acheteur** dans `app_core` : risque de régression, couvert par ses 60 tests.
- **Clés Google Maps** à créer par le porteur du projet (compte Google Cloud). Sans elles,
  l'aperçu sans carte reste en place.
- **Catégorie obligatoire côté serveur** : l'app livreur n'est pas concernée ; les scripts et tests
  qui créent des boutiques sont mis à jour.
- **Action en Berkeley** : elle déroge à la règle de DESIGN.md (« action principale Imperial dans
  les trois apps »), choix du 2026-10-31 à faire confirmer par le designer.
