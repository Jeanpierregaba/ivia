# 033 — Plan technique

<!-- Le COMMENT. Validé par l'utilisateur avant de découper en tâches. -->

## Approche

On suit la méthode de l'app pharmacie (spec 031) :
- **couleurs de la charte Ivia Driver** dans `packages/ui` (`driver_colors.dart`) ;
- **composants propres à l'app** dans `apps/driver/lib/common/ui.dart` :
  - `D` : couleurs et mesures ;
  - `DText` : styles de texte ;
  - `DCard`, `DSlide` (glissière), `DBottomNav` (barre claire), `DCodeBoxes`, `DStepList`, `DPill`,
    `DSheet` (volet du bas sur la carte) ;
- **un dossier par écran** dans `lib/features/`, en remplaçant les écrans actuels (`work_screens.dart`,
  1 044 lignes, est découpé).

La logique existante est gardée et seulement complétée, car elle est déjà testée :
- état du travail (`work_state.dart`) : disponibilité, envoi de la position, propositions, mission,
  relecture ;
- appels API (`driver_work.dart`) ;
- règle des écrans (`router.dart`).

La connexion reste celle de `app_core` (`PhoneScreen`, `PhoneCodeScreen`), réglée par
`AppIdentity` de l'app : badge « Driver », titre « Espace livreur », note du code. C'est déjà le
cas pour les autres apps.

**Côté serveur, un seul ajout** : les zones de travail dans `GET /v1/driver/options`, pour envoyer
le dossier (décision de la spec).

## Fichiers touchés

**Nom de l'app**
- `apps/driver/android/app/src/main/AndroidManifest.xml` (`android:label`) ;
- `apps/driver/ios/Runner/Info.plist` (`CFBundleDisplayName`, `CFBundleName`) ;
- `apps/driver/lib/main.dart` (`title`), et `identity.dart` (badge « Driver ») ;
- `apps/driver/flutter_native_splash.yaml`, puis `dart run flutter_native_splash:create`
  (fichiers Android et iOS régénérés) ;
- `mobile/README.md`, `tools/preview/demarrer.ps1` ;
- tests (`app_test.dart` : titre attendu).

Les identifiants techniques ne changent pas (`applicationId`, bundle iOS, paquet `ivia_driver`).

**Charte et composants**
- `packages/ui/lib/src/driver_colors.dart` (nouveau) et son export : couleurs lues sur les
  maquettes :
  - bleu `#004DA8` (= `cobaltBlue`) ;
  - encre `#0B1A30` et cartes sombres ;
  - fond de page `#F2F3F5` ;
  - gris des textes, rouge des alertes, vert « Payée » ;
- `apps/driver/lib/common/ui.dart` (nouveau) : composants listés dans l'approche ;
- `apps/driver/lib/common/formats.dart` (nouveau) : `F` sans espace (« 1 200 F »), heures de Lomé
  (`hh:mm` en UTC), distances (« 4,2 km », « 800 m »).

**Écrans** (`apps/driver/lib/features/`)

| Dossier | Écrans | Remplace |
|---|---|---|
| `splash/` | D00 | `loading_screen.dart` |
| `onboarding/` | D01 à D03 | `onboarding_screen.dart`, `illustrations.dart` (illustrations redessinées) |
| `dossier/` | D06, D07 | `dossier_form_screen.dart`, `dossier_pending_screen.dart` ; `dossier_summary_screen.dart` et `dossier_blocked_screen.dart` restylés |
| `shell/` | barre du bas | `DriverShell` de `work_screens.dart` |
| `home/` | D08, D09 | onglet Accueil (`home_placeholder_screen.dart` supprimé s'il ne sert plus) |
| `offer/` | D10 | `_OfferCard` |
| `mission/` | D11 à D16 | `MissionView` |
| `missions/` | D17 | `_HistoryTab` |
| `earnings/` | D18 | (nouveau) |
| `profile/` | D19 | `_ProfileTab` |

**Logique**
- `work_state.dart` :
  - heure de passage en ligne (« depuis 1 h 12 », gardée sur le téléphone) ;
  - relecture de la mission pharmacie toutes les 5 s pendant l'attente de la pharmacie (D12) ;
- `earnings/earnings.dart` (nouveau) : gains par jour, semaine et mois depuis l'historique, jours
  de Lomé ;
- `profile/settings.dart` (nouveau) : application de navigation et sonnerie (`shared_preferences`) ;
- `mission/navigation.dart` (nouveau) : ouverture de l'itinéraire dans Google Maps, Waze ou Plans
  (`url_launcher`, liens universels ; repli sur le navigateur) ;
- `mission/eta.dart` (nouveau) : heure d'arrivée estimée, vitesse moyenne selon le véhicule.
  - Vélo 12 km/h, moto 22 km/h, voiture 18 km/h en ville ; distance à vol d'oiseau × 1,3.

**Dossier sur le serveur de Gedeon**
- `packages/api_client` :
  - `driverOptions()` : véhicules, pièces demandées par véhicule, zones ;
  - `saveDriverActivity('delivery', …)` : `PUT /v1/driver/activities/{activity}` ;
  - `setDriverPayout(…)` : `PUT /v1/driver/payout` ;
  - `submitDriverActivity('delivery')` ;
  - `DriverDossier` complété : activités, compte de versement, zone, marque, modèle ;
  - les modèles et routes existants restent pour la compatibilité (`/v1/driver/application`).
- `packages/api_client/lib/testing.dart` : faux serveur complété.

**Sonnerie** (corrigé pendant la tâche 4)
- Ivia Driver n'enregistre aucun jeton push : les propositions arrivent app ouverte (relecture et
  connexion directe au serveur). « Sonnerie des missions » est donc un réglage du téléphone : son
  et vibration du système (`SystemSound`, `HapticFeedback`, sans dépendance) à l'arrivée d'une
  proposition.
- `registerPushToken` accepte `alertSound` (facultatif) pour l'app pharmacie (spec 032).

**Serveur (seul ajout)**
- `backend/internal/delivery/partner.go` : `Options` renvoie aussi `zones` (id, nom, actives
  seulement). Elles sont lues par le service `mapping` (`Zones`), qui possède la table, et non par
  une requête du module `delivery` (règle 2 d'AGENTS.md). Il est injecté dans `app.go` par un petit
  interface, comme `pharmacy.SetRouter` ;
- `backend/api/openapi.yaml` et `admin/lib/api-types.ts` ;
- test de bout en bout : un livreur lit les zones actives, jamais les inactives.

**Documentation**
- `TASKS.md` :
  - 033 « En cours » ;
  - la tâche 20 de la 032 renvoie à la 033 ;
  - liste « Manques côté serveur (Ivia Driver) » pour Gedeon ;
- `docs/DESIGN.md` : charte Ivia Driver (barre claire, cartes sombres).

## Données

Aucune migration. Réglages du téléphone dans `shared_preferences` :
- application de navigation ;
- sonnerie ;
- heure de passage en ligne.

## API / interfaces

| Route | Usage |
|---|---|
| `GET /v1/driver/options` | Véhicules et pièces (existe) ; **`zones` ajouté**. |
| `PUT /v1/driver/activities/delivery` | Véhicule, plaque, marque, modèle, zone (existe, Gedeon). |
| `PUT /v1/driver/payout` | Compte de versement (existe, Gedeon). |
| `POST /v1/driver/activities/delivery/submit` | Envoi du dossier (existe, Gedeon). |
| `POST /v1/driver/application/documents` | Pièces (existe). |
| `GET /v1/driver/me` | Dossier, véhicule, compte (existe). |
| `PUT /v1/driver/availability`, `POST /v1/driver/location` | En ligne, position (existe). |
| `GET /v1/driver/offers/current`, `GET /v1/driver/pharmacy-offers/current`, accepter, refuser | D10 (existe). |
| Étapes de mission, `deliver`, `fail`, `withdraw` | D11 à D16 (existe). |
| `GET /v1/driver/pharmacy-missions/current` | Code de retrait, montant avancé (032). |
| `GET /v1/driver/missions`, `GET /v1/driver/pharmacy-missions` | D17, D18 : pages de 100 jusqu'à 62 jours en arrière. |
| `PUT /v1/me/devices` | Non utilisé par Ivia Driver (pas de push) ; `alertSound` ajouté au client pour la pharmacie. |

## Dépendances

Aucune nouvelle. Celles déjà présentes suffisent :
- `url_launcher` ;
- `shared_preferences` ;
- `google_maps_flutter` (par `app_core`, carte affichée seulement avec la clé, sinon fond neutre
  comme l'app marchand).

## Sécurité

- Le code de retrait pharmacie n'est ni gardé ni journalisé dans l'app : il est affiché depuis la
  mission en cours, et masqué par le serveur après la remise.
- Le code du client tapé est effacé après un refus.
- Pas de position dans les journaux.
- Le compte de versement est affiché masqué (« +228 90 •• •• 77 »), comme le renvoie le serveur.
- La liste des zones est réservée aux livreurs connectés (rôle `driver` ou dossier en cours),
  comme le reste de `/v1/driver/options`.
- Les liens vers les apps de navigation ne contiennent que les coordonnées de destination.

## Tests

- **Composants** (`test/ui_test.dart`) :
  - la glissière agit seulement au bout ;
  - un glissement incomplet revient au départ ;
  - les cases de code s'affichent ;
  - la barre du bas est claire, avec l'onglet actif.
- **Écrans** (`FakeApiServer`) : un test par écran, avec les critères d'acceptation de la spec.
  - Présentation et « Passer ».
  - Dossier : pièces selon le véhicule, envoi bloqué tant qu'il manque quelque chose.
  - En ligne et hors ligne.
  - Proposition expirée.
  - Retrait : boutique avec cases, pharmacie avec code et attente.
  - Preuve de remise : code et ordonnance.
  - Échec avant 10 min.
  - Gains calculés : jours de Lomé, semaine et mois, variation.
  - Missions par onglet.
  - Profil et sonnerie envoyée.
- **Police à 200 % sur 320 dp** pour chaque écran, avec une marge (test à 220 % sur les écrans à
  montants, vu la CI Linux).
- **Calculs** : tests unitaires des gains par jour (passage de minuit à Lomé, mois) et de l'heure
  d'arrivée estimée.
- **Serveur** : test de bout en bout des zones dans les options.
- **Parties critiques** (`docs/TESTING.md`) : la remise pharmacie et le code client. Leurs tests
  d'écran sont écrits avant le code.
- **Vérification visuelle** sur le simulateur iPhone, avec l'API locale et `seed-demo`, écran par
  écran face aux maquettes.

## Risques

- **Gedeon travaille sur le module `delivery` en même temps** :
  - l'ajout des zones est petit et isolé ;
  - il sera poussé tôt, en commit séparé, pour éviter les conflits ;
  - il le relit.
- **Volume** : 20 écrans. On découpe un écran ou deux par tâche, avec un commit chacune.
- **Gains calculés dans l'app** : limités aux 62 derniers jours de l'historique (assez pour
  « Mois » et sa comparaison). Un vrai calcul serveur viendra avec le règlement des livreurs.
- **Ancien dossier** (`/v1/driver/application`) : les livreurs déjà inscrits gardent leur statut
  (le serveur reprend l'ancien dossier, « legacy »). Le nouvel écran lit les deux formes.
- **Débordements visibles seulement en CI** (polices Linux) : test à 220 % sur les lignes à
  montants.
