# 027 — Plan technique

## Approche

**Splash natif maintenu pendant l'initialisation.** Le splash est dessiné par le système, avant le
démarrage de Flutter, à partir de ressources générées par `flutter_native_splash` (Android avant
et après la version 12, iOS). Il reste affiché jusqu'à la première image de Flutter : `main()` lit
donc l'état local **avant** `runApp()`. Le paquet ne sert qu'à la génération (`dev_dependencies`) ;
`FlutterNativeSplash.preserve`/`remove` ne deviendraient utiles que pour une initialisation faite
après `runApp()`. On n'a pas de second splash dessiné en Flutter, ni de « saut » visuel.

*Contrainte d'Android 12 et plus* : le système impose une icône centrée dans un masque circulaire de
192 dp de diamètre. L'icône est dimensionnée pour tenir entière dans ce cercle : la tuile blanche du
marchand et du livreur paraît donc un peu plus petite qu'avant Android 12 (154 dp contre 172 dp sur
la maquette ; le logotype de l'acheteur garde presque sa taille : 168 dp contre 174 dp). Ce compromis est accepté plutôt que d'ajouter un second splash en
Flutter.

**Présentation : un composant partagé, le contenu dans chaque app.** Le widget `IviaOnboarding`
(pages, indicateur, Passer / Suivant / Commencer) vit dans `packages/ui`. Chaque app fournit
seulement ses 3 pages et sa couleur d'accent.

**Navigation et état** : on introduit dès maintenant `go_router` et `flutter_riverpod`, prévus par
l'architecture, pour que la fonctionnalité 001 n'ait plus qu'à ajouter la règle « session ouverte ».
Le premier écran (`initialLocation`) est `/onboarding` si la présentation n'a pas été vue, `/login`
sinon. La fonctionnalité 001 remplacera ce choix par une règle `redirect` (session ouverte, liens
profonds). Le drapeau « présentation vue » est stocké dans `shared_preferences` : ce n'est pas
une donnée sensible, et le jeton de session ira, lui, dans le stockage sécurisé (001).

## Fichiers touchés

**`mobile/packages/ui`**
- `assets/brand/` : logotype blanc, Imperial, Berkeley et Cobalt (PNG transparents, un fichier de
  678 × 336 px par couleur, net jusqu'à environ 110 pt de haut en @3x).
- `lib/src/brand.dart` : `IviaLogo` (variante et hauteur, libellé d'accessibilité « ivia ») et
  `IviaAppBrand` (couleur et variante de logo de chaque app : `buyer`, `seller`, `driver`).
- `lib/src/onboarding.dart` : `OnboardingSlide` (pictogramme, titre, texte) et `IviaOnboarding`
  (`PageView`, indicateur, boutons, retour Android vers la page précédente, `onDone`).
- `lib/ivia_ui.dart` : exports. `pubspec.yaml` : déclaration des assets.

**Chaque app `mobile/apps/<buyer|seller|driver>`**
- `flutter_native_splash.yaml` : couleur de fond, image, et réglages d'Android 12.
- `assets/splash/` : images du splash (logo seul, ou tuile + logo), et image dédiée à Android 12.
- `lib/main.dart` : mode portrait, lecture du drapeau, puis `ProviderScope` et `runApp()`.
- `ios/Runner/Info.plist` (iPhone en portrait seulement), `AndroidManifest.xml`
  (`screenOrientation="portrait"`). L'iPad garde le paysage : hors cible au MVP.
- `lib/app/router.dart` : routes `/onboarding` et `/login`, avec la redirection.
- `lib/app/onboarding_store.dart` : lecture et écriture du drapeau (provider Riverpod).
- `lib/features/onboarding/onboarding_screen.dart` : les 3 pages de l'app.
- `lib/features/auth/login_placeholder_screen.dart` : écran provisoire, remplacé par 001.
- Fichiers Android et iOS **générés** par `dart run flutter_native_splash:create` (styles,
  drawables, `LaunchScreen.storyboard`, images) : committés.

**Docs**
- `docs/DESIGN.md` :
  - couleur de chaque app : acheteur Imperial, marchand Berkeley, livreur Cobalt. Cela remplace le
    codage des services, qui réservait Cobalt à la mobilité et Berkeley à la santé, et Cornell au
    livreur ;
  - nouvelles versions du logo (logotype Berkeley ou Cobalt dans une tuile blanche) ;
  - section des composants `IviaLogo` et `IviaOnboarding`.
- `AGENTS.md` : commande de régénération du splash.

**Images** : elles sont tirées de `docs/brand/logo-carre.png` par un script ponctuel, qui n'est pas
committé (logotype extrait puis recoloré), en attendant les SVG du designer. On les remplacera
par ses exports dès qu'ils arrivent.

## Données

Aucune donnée serveur. Côté appareil, une clé `shared_preferences` :
`onboarding_seen` (booléen).

## API / interfaces

Aucun appel à l'API.

## Dépendances

Toutes vérifiées sur pub.dev le 2026-10-30 (elles existent, sont maintenues et compatibles avec
Dart 3.13 et Flutter 3.47) :

| Paquet | Version | Où | Pourquoi |
|---|---|---|---|
| `flutter_native_splash` | ^2.4.8 | `dev_dependencies` de chaque app | génération du splash natif Android et iOS |
| `shared_preferences` | ^2.5.6 | apps | drapeau « présentation vue » |
| `go_router` | ^18.1.2 | apps | navigation (stack prévue) |
| `flutter_riverpod` | ^3.4.3 | apps | état (stack prévue) |
| `shared_preferences_platform_interface` | ^2.4.2 | `dev_dependencies` des apps | simuler un stockage en panne dans les tests |

La documentation à jour de chaque paquet sera consultée via Context7 au moment de coder.

## Sécurité

Aucune donnée personnelle et aucun secret. Le drapeau en clair est sans risque. Aucune permission
n'est demandée.

## Tests

- `packages/ui` : tests de widget d'`IviaOnboarding` (Suivant, Passer, Commencer, indicateur,
  retour vers la page précédente, police à 200 % et largeur de 320 dp sans débordement, libellés
  d'accessibilité) et d'`IviaLogo`. Les nouvelles combinaisons de couleurs entrent dans
  `contrast_test.dart`.
- Chaque app : test de la redirection (drapeau absent ⇒ présentation ; présent ⇒ connexion ;
  terminer ⇒ drapeau écrit puis connexion), avec `SharedPreferences.setMockInitialValues`.
- Manuel : splash sur un émulateur Android 11 et un Android 12 ou plus, puis sur un vrai Android
  d'entrée de gamme.

## Risques

- **Rendu d'Android 12 plus petit que la maquette** : accepté, voir l'approche.
- **Images extraites d'un PNG** et non d'un vecteur : la netteté est suffisante (logotype de 674 px
  de large dans la source), mais elles sont à remplacer par les exports du designer.
- **Changement du codage couleur des services** : à confirmer avec le designer, car Cobalt et
  Berkeley étaient réservés à de futurs services (mobilité, santé).
