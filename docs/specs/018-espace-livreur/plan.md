# 018 — Plan technique

## Approche

Même structure que l'app marchand ([004](../004-espace-marchand/plan.md)), sans changement de
backend : `PUT /v1/driver/application`, `POST /v1/driver/application/documents`,
`GET /v1/driver/me` et `POST /v1/uploads` (`driver_document`, compartiment privé) existent.

**Marque** : `IviaAppBrand.driver` passe en Cobalt pour l'action, les liens et la partie colorée des
titres (maquettes). `CheckPill` accepte un fond sombre (« Mission terminée »).

**État du livreur** : `DriverDossier` (`AsyncNotifier`, même schéma que `SellerShop`) lit
`GET /v1/driver/me` à chaque connexion. Une réponse 404 (`driver_not_found`) signifie qu'il n'y a
pas de dossier. Aucun nouvel essai automatique ; une actualisation qui échoue garde l'écran affiché.

| Session / dossier | Écran |
|---|---|
| démarrage, ou dossier en chargement | splash |
| déconnecté | présentation ou connexion |
| aucun dossier (profil complet ou non) | « Devenez livreur ivia » (champs du profil si incomplet) |
| `review_status = pending_review` | « En cours de vérification », « Voir mon dossier » |
| `rejected` | motif, « Corriger mon dossier » (formulaire) |
| `status = suspended` | motif |
| validé (`offline` / `available` / `busy`) | accueil provisoire |

**Envoi du dossier**, avec un double appui ignoré :
0. Profil incomplet : `PATCH /v1/me` (prénom, nom, téléphone, `accept_privacy_policy`), puis
   `profileUpdated`.
1. Chaque document qui n'a pas encore de clé est préparé (`POST /v1/uploads`), puis envoyé sur
   l'URL signée sans jeton. La clé obtenue est gardée : un nouvel essai ne renvoie pas les fichiers
   déjà envoyés.
2. `PUT /v1/driver/application` (véhicule, immatriculation).
3. Une requête `POST …/documents` par document, et seulement pour les documents pas encore
   transmis.
4. Le dossier renvoyé met à jour l'état, et l'écran de vérification s'ouvre.

**Photos des documents** : `PhotoPicker`, partagé avec le marchand, passe dans `app_core` et accepte
une source (appareil photo ou galerie) et une taille. Les documents sont redimensionnés à 2048 px
pour rester lisibles, en JPEG sans métadonnées. Le choix de la source se fait par une feuille
« Prendre une photo / Choisir une photo ».

## Fichiers touchés

- **`ui`** :
  - `brand.dart` : couleurs du livreur ;
  - `illustration.dart` : `CheckPill` sombre ;
  - tests et contrastes (Cobalt sur fond et sur blanc pour les liens).
- **`app_core`** : `photo_picker.dart`, déplacé depuis le marchand et paramétré ; tests.
- **`api_client`** : modèles `DriverDossier` et `DriverDocument`, plus `driverMe`, `applyAsDriver`,
  `addDriverDocument` ; 404 traduit en « aucun dossier » ; réponses types dans `testing.dart` ;
  tests.
- **`apps/seller`** : il importe le `PhotoPicker` d'`app_core`, sans autre changement.
- **`apps/driver`** :
  - `app/` : identité, `driver_dossier.dart`, routeur ;
  - `features/` : splash, présentation et illustrations, `dossier/` (formulaire, ligne de document,
    feuille de source, vérification, récapitulatif, refus et suspension), accueil provisoire ;
  - `main.dart` ;
  - natif : permissions appareil photo et photos (Info.plist), HTTP local en debug, permission
    INTERNET en release ;
  - tests.
- **Docs** : DESIGN.md (couleurs du livreur, écrans), TASKS.md.

## Données

Aucune migration. Sur le téléphone, seules les clés des fichiers déjà envoyés sont gardées en
mémoire, le temps de l'écran.

## Dépendances

Aucune nouvelle : `image_picker` et `flutter_image_compress`, déjà vérifiés pour 004, passent dans
`app_core`.

## Sécurité

- Les documents vont dans le compartiment **privé**, par URL signée, sans jeton. L'app ne les
  affiche plus après l'envoi : l'API ne donne leur lien qu'aux admins.
- Les métadonnées (position GPS) sont retirées avant l'envoi.
- Les permissions d'appareil photo et de photos ne sont demandées qu'au choix de la source.
- Aucune localisation au MVP de cette fonctionnalité (019).

## Tests

- **`api_client`** : candidature, document, dossier, 404 traduit en « aucun dossier ».
- **Livreur** :
  - routeur, pour chaque état ;
  - parcours complets contre le faux serveur :
    - présentation, connexion, profil incomplet ;
    - dossier complet (ordre des appels, aucun jeton vers le stockage) ;
    - échec d'un document puis nouvel essai, sans renvoyer les documents déjà envoyés ;
    - double appui, immatriculation invalide ;
    - refus puis correction, suspension, dossier validé, serveur injoignable ;
  - police à 200 % sur 320 dp, mots des titres.
- **Manuel** : simulateur iPhone 17 Pro contre l'API locale, avec validation par l'admin par
  `curl`.

## Risques

- **Dossier envoyé en partie** (documents) : le serveur l'accepte ; l'app l'indique et permet de
  compléter le dossier.
- **Couleur d'action Cobalt** : elle déroge à la règle « action Imperial dans les trois apps »,
  comme pour le marchand ; à confirmer par le designer.
