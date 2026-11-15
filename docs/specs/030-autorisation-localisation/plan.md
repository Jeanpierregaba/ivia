# 030 — Plan technique

Aucun changement côté API ni base. Aucune nouvelle dépendance : `geolocator` (14.x) est déjà dans
`app_core`.

## 1. Service de position (`packages/app_core/lib/src/location.dart`)

La demande au système quitte `current()`. Elle ne se fait plus qu'à travers l'écran, et une lecture
automatique ne peut donc plus ouvrir la fenêtre du système.

```dart
enum LocationAccess { granted, askable, deniedForever }

abstract interface class LocationService {
  Future<LocationAccess> access();   // état de l'autorisation, sans rien demander
  Future<LocationAccess> request();  // fenêtre du système
  Future<LocationResult> current();  // lit la position si elle est autorisée, ne demande jamais
  Future<bool> openSettings();
}
```

- `DeviceLocationService` :
  - `access` ← `Geolocator.checkPermission` ;
  - `request` ← `requestPermission`, et toute exception vaut `askable` ;
  - `current` sans autorisation renvoie `denied` ou `deniedForever` ; le reste est inchangé.
- Les 6 faux services des tests implémentent les deux nouvelles méthodes.

## 2. Écran commun (`packages/app_core/lib/src/location_prompt.dart`)

**Textes et icônes** : `LocationPromptCopy` regroupe le nom de l'espace, l'icône centrale, les 4
icônes autour, le titre en deux parties et le texte. Il est porté par `AppIdentity` (champ
`locationPrompt`), donc chaque app fournit les siens dans son `identity.dart`.

**`LocationPromptScreen(onDone)`**
- Le panneau, le titre et le bouton prennent la couleur de la marque de l'app (`IviaAppBrand`).
- « Autoriser la localisation » :
  - si l'autorisation a été refusée définitivement, le bouton ouvre les réglages ;
  - sinon il appelle `request()` ;
  - il est occupé pendant la demande, puis appelle `onDone`.
- « Refuser » appelle `onDone` directement.

**`LocationPromptStore`**, sur le modèle d'`OnboardingStore` :
- il garde la clé `location_prompt_done` dans `SharedPreferences` ;
- `open(service)` lit cette clé et `access()`, et vaut « fait » si la position est déjà autorisée ;
- si le stockage est illisible, l'écran est montré.

Le provider `locationPromptDoneProvider` expose cet état ; `complete()` l'enregistre.

**`askForLocation(BuildContext, WidgetRef) → Future<bool>`**, pour les fonctionnalités :
- si la position est déjà autorisée, il renvoie `true` sans afficher l'écran ;
- sinon il ouvre l'écran en plein écran, au-dessus de la barre du bas, puis renvoie
  `access() == granted` ;
- le retour système vaut « Refuser ».

## 3. Illustration (`packages/ui/lib/src/location_radar.dart`)

`IviaLocationRadar(center, satellites, color)` :
- 3 cercles concentriques blancs translucides : un trait, un disque à 8 %, un disque à 15 % ;
- une pastille centrale blanche ombrée ;
- 4 pastilles blanches placées comme sur les maquettes (haut gauche, haut droite, bas gauche, bas
  droite) ;
- la taille suit la largeur de l'écran.

`IviaLogo` reçoit une teinte facultative (le logotype blanc, teinté). La tuile blanche affiche ainsi
le logo dans la couleur de chaque app, pharmacie comprise, sans créer de nouvelle image.

Icônes Material :

| App | Pastille centrale | Pastilles autour |
|---|---|---|
| Acheteur | `person_pin_circle` | `storefront`, `local_pharmacy`, `local_taxi`, `restaurant` |
| Marchand | `storefront` | `storefront`, `apartment`, `restaurant`, `construction` |
| Livreur | `two_wheeler` | `storefront`, `home`, `home`, `local_pharmacy` |
| Pharmacie | `local_pharmacy` | `person` ×4 |

## 4. Lancement (4 apps)

- **Route** : chaque routeur ajoute `/location` (`LocationPromptScreen`, dont `onDone` appelle
  `locationPromptDoneProvider.complete()`).
- **Redirection** : après `AuthStarting` (splash), si l'écran n'est pas fait, `/location` est la
  seule route permise ; sinon la table actuelle s'applique (présentation, connexion…). go_router
  relit la règle quand l'état change.
- **Arguments** : `redirectFor` reçoit `locationPromptDone` (acheteur, marchand, livreur), et la
  pharmacie suit la même règle dans sa redirection.
- **`main.dart`** : ouvre `LocationPromptStore` et l'injecte dans le `ProviderScope`.
- **Comptes déjà connectés après la mise à jour** : l'écran s'affiche aussi une fois au lancement
  suivant, sauf si la position est déjà autorisée.

## 5. Fonctionnalités : `askForLocation` avant de lire

| App | Endroit | Fichier | Si refusé |
|---|---|---|---|
| Acheteur | « Utiliser ma position » | `features/home/area_sheet.dart` | message actuel de `locate()` |
| Acheteur | alerte médicament (`alertPosition`) | `features/pharmacy/new_alert_screen.dart` et `reservation_screen.dart`, avant l'appel | — |
| Acheteur | ajout d'une adresse | `features/profile/profile_tab_screen.dart` | — |
| Marchand | « Utiliser ma position » de l'épingle | `features/shop/shop_location_field.dart` | message de refus actuel |
| Livreur | passage en ligne | `features/work/work_screens.dart`, au basculement vers « en ligne » | — |
| Pharmacie | envoi du dossier | `features/application_screen.dart` | — |

- Dans tous les cas, si l'utilisateur refuse, la fonctionnalité continue sans position.
- Les lectures automatiques ne demandent plus rien et passent par `current()` : Accueil acheteur
  (`ensure`), envoi périodique de la position du livreur.

## 6. Plateformes

- **Pharmacie** :
  - iOS : `NSLocationWhenInUseUsageDescription` (« ivia utilise votre position pour recevoir les
    demandes des clients proches de votre officine. ») ;
  - Android : `ACCESS_COARSE_LOCATION` et `ACCESS_FINE_LOCATION`.
- **Livreur** : Android `ACCESS_COARSE_LOCATION` et `ACCESS_FINE_LOCATION` ; le texte iOS existe déjà.

## 7. Tests

- **`app_core`** :
  - le store (première fois, déjà fait, déjà autorisé, stockage illisible) ;
  - l'écran (Refuser ; Autoriser, puis accepté ou refusé ; refus définitif qui ouvre les réglages ;
    double appui) ;
  - `askForLocation` (déjà autorisé : pas d'écran ; retour système vaut refus).
- **`ui`** : rendu de `IviaLocationRadar` et de `IviaLogo` teinté, en grande police.
- **Apps** :
  - `router_test`, pour la place de `/location` dans l'enchaînement ;
  - `app_test` de l'acheteur, du marchand et du livreur : splash, localisation, présentation ;
  - pharmacie : un premier `test/` (splash, localisation, connexion) ;
  - acheteur : « Utiliser ma position » montre l'écran sans autorisation, et ne le montre pas avec ;
    l'Accueil ne le montre pas.
- **Simulateur iPhone 17 Pro** : premier lancement des 4 apps, et une fonctionnalité par app.

## 8. Docs

`DESIGN.md` (écran de localisation, parcours de lancement), `TASKS.md`.

## Point à trancher

**Vert de la pharmacie** : la maquette dit `#0B7A55`, la marque de l'app pharmacie utilise
`IviaColors.success` (`#1E7A4C`). Le plan suit la marque de l'app, pour rester cohérent avec ses
autres écrans. L'aligner sur `#0B7A55` changerait tous les écrans de la pharmacie, ainsi que les
textes et icônes de succès des autres apps.
