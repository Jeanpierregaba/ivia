# 031 — Plan technique

## Approche

L'app pharmacie garde son routeur, ses fournisseurs Riverpod et le push de Gedeon. On **refait la
présentation écran par écran** d'après les maquettes, sans changer le serveur. Les règles d'accès,
les appels à l'API et les redirections restent celles d'aujourd'hui, et les tests actuels doivent
rester verts à chaque étape.

Avant tout habillage, on découpe `shell.dart` (1 311 lignes) et `application_screen.dart` (970
lignes) en dossiers par fonctionnalité (`lib/features/<fonctionnalité>/`, convention d'AGENTS.md).
Ce découpage est un déplacement sans changement de comportement, dans un commit à part : chaque
écran se refait ensuite dans son propre fichier, avec son test.

Les couleurs des maquettes vont dans `packages/ui`, car les couleurs ne passent que par ce paquet
(AGENTS.md). Les composants propres à la pharmacie restent dans l'app (`lib/common/`). Les écrans
communs (splash, présentation, connexion) reçoivent des options **facultatives** : les trois autres
apps ne changent pas.

## Fichiers touchés

**`packages/ui`**
- `lib/src/pharmacy_colors.dart` (nouveau) : `IviaPharmacyColors`, la palette relevée sur les
  maquettes (vert `#0B7A55`, vert foncé `#075C40`, page `#F3F4F6`, encre `#0A1A30`, texte
  secondaire `#5A6A80`, filets, fonds doux, bleu nuit de F12, rouge foncé de F18…).
- `lib/src/loading_splash.dart` : couleur de fond facultative. F00 a un vert plus foncé que
  `IviaColors.success`.
- `lib/src/onboarding.dart` : bouton retour facultatif (pages 2 et 3). Sans l'option, les autres
  apps restent inchangées.

**`packages/app_core`**
- `app_identity.dart` : trois champs facultatifs :
  - libellé des conditions (« Conditions partenaires ») ;
  - titre du code selon le canal (« Vérifiez vos SMS » ou « Vérifiez WhatsApp ») ;
  - libellé du bouton du code (« Valider »).
- `phone_screens.dart` : utilise ces champs quand ils sont fournis.

**`packages/api_client`**
- `pharmacist.dart` : `updatePharmacyContact(phone, openingHours)` → `PATCH /v1/pharmacy/me`. La
  route existe déjà dans `openapi.yaml`. Elle sert à l'écran Informations d'une pharmacie validée.
  Aucun autre ajout.

**`apps/pharmacy`**
- `lib/main.dart` : route de présentation, `OnboardingStore`, routes `incoming/:id` (F10) et
  `alert/:id` (F11), splash F00.
- `lib/common/` (remplace `features/ui.dart`) :
  - composants `PCard`, `PPill`, `PIcon` et `PButton` repris ;
  - nouveaux composants :
    - `PBackButton` (retour rond blanc) et `PHeader` (titre centré et pastille) ;
    - `PBottomBar` (bouton en pilule fixé en bas) ;
    - `PCountdown` (compte à rebours qui passe à « Terminée ») ;
    - `PCheckRow`, `PSwitchRow`, `PSection`, `PEmpty` (état vide) et `PErrorRetry` ;
  - `hhmm` et les formats.
- `lib/features/launch/` : présentation en 3 pages et ses illustrations, dessinées en widgets
  (pas d'images).
- `lib/features/application/` :
  - `application_flow.dart` : les 5 étapes, la pastille « n sur 5 » et la reprise ;
  - `step_details.dart` (étape 1, fiche et photo de devanture) ;
  - `step_documents.dart` (étape 3, pièces et case de certification) ;
  - `payout_screen.dart` (étape 5, aussi ouvert depuis le relevé) ;
  - `review_screen.dart` (F08, frise et suspension).
  - L'étape 2 utilise le `PlacePickerScreen` commun. L'étape 4 est le planning.
- `lib/features/home/` :
  - `pharmacy_shell.dart` : barre flottante à 4 onglets et relecture toutes les 5 s ;
  - `home_tab.dart` (F09) et `today_stats.dart` (chiffres du jour calculés sur la boîte de
    réception).
- `lib/features/alerts/` :
  - `incoming_alert_screen.dart` (F10) ;
  - `alert_detail_screen.dart` (F11) ;
  - `prescription_viewer.dart` (F12) ;
  - `response_screen.dart` (F13) et `response_sent_screen.dart` (F14) ;
  - `alerts_tab.dart` (F21) et `alert_row.dart` ;
  - `new_alert_watcher.dart` : ouvre F10 pour une alerte nouvelle, qu'elle arrive par le push ou
    par la relecture.
- `lib/features/orders/` :
  - `order_screen.dart` (F15 et F17) ;
  - `handover_screen.dart` (F16) ;
  - `order_done_screen.dart` (remise au client, et F19) ;
  - `cancel_sheet.dart` (F18) ;
  - `orders_tab.dart` et `order_row.dart`.
- `lib/features/planning/planning_screen.dart` (F20) : semaine, gardes, ajout, import de Gedeon et
  heures de nuit.
- `lib/features/earnings/statement_screen.dart` (F22).
- `lib/features/profile/` :
  - `profile_tab.dart` (F23) ;
  - `info_screen.dart` (fiche, ouverte 24 h/24, de garde) ;
  - `documents_screen.dart` ;
  - `alert_sound.dart` (réglage de la sonnerie sur ce téléphone).
- `lib/features/push/push.dart` (déplacé) :
  - deux canaux Android, l'un « forte · répétée » (actuel), l'autre silencieux ;
  - le canal se choisit selon le réglage, lu aussi dans le gestionnaire d'arrière-plan ;
  - `onAlertReceived` reçoit l'identifiant de l'alerte.
- `lib/features/security/secure_screen.dart` et `android/.../MainActivity.kt` : canal
  `ivia/secure_screen` qui pose et retire `FLAG_SECURE` (F12). Sur iOS, rien n'est fait.
- `lib/features/alerts_permission.dart` : reste en place, habillé à la charte.
- Supprimés une fois vides : `features/shell.dart`, `features/application_screen.dart` et
  `features/ui.dart`.
- `test/` : un fichier par fonctionnalité (`launch_test.dart`, `application_test.dart`,
  `home_test.dart`, `alerts_test.dart`, `orders_test.dart`, `planning_test.dart`,
  `profile_test.dart`) et `test/helpers.dart` (serveur factice et données types). `app_test.dart`
  garde les redirections.

## Données

Aucune migration ni changement de schéma. Deux réglages restent sur le téléphone
(`SharedPreferences`) : la présentation vue (`OnboardingStore` existant) et la sonnerie des alertes.

## API / interfaces

Seules des routes existantes sont utilisées. Les manques sont notés pour Gedeon (spec, « Hors
périmètre »), plus un nouveau : **l'opérateur du compte de versement** n'est pas renvoyé par
`GET /v1/pharmacy/me`. F22 et F23 affichent donc le numéro masqué sans le nom de l'opérateur.

Ce qui se calcule dans l'app, sans nouvelle route :
- **Chiffres du jour (F09)** : alertes reçues aujourd'hui (heure de Lomé), répondues et confirmées
  (`unlocked`), sur les 50 dernières alertes de la boîte.
- **Commandes du relevé (F22)** : commandes en livraison terminées (`pharmacy_due_xof`), sur les
  50 dernières réservations.
- **Générique (F13)** : le nom de la ligne de réponse devient le nom du générique proposé. La
  ligne reste rattachée au produit demandé (`alert_item_id`).
- **Ligne de garde (F09)** : la garde du planning en cours, sinon les heures de nuit.

Le code du livreur n'existe pas à la remise (F17) : l'écran indique que le livreur confirme la
récupération dans son app.

## Dépendances

Aucune nouvelle bibliothèque.
- Le blocage de capture passe par un canal de plateforme de quelques lignes dans `MainActivity`,
  plutôt que par un paquet tiers.
- La présentation réutilise `IviaOnboarding` et `OnboardingStore`.
- Zoom, pivot et pages de F12 utilisent `InteractiveViewer` et `Transform.rotate`.

## Sécurité

- **Ordonnance (F12)** :
  - capture bloquée sur Android pendant l'affichage, puis débloquée en quittant l'écran, même en
    cas d'erreur (`dispose`) ;
  - l'image n'est pas mise en cache sur le disque (`Image.network` en mémoire seulement) ;
  - un lien expiré (10 min) relit le détail.
- **Code de remise (F16)** : saisi, envoyé, puis effacé. Il n'est jamais journalisé ni gardé dans
  l'état après la réponse.
- **Pièces du dossier** : même envoi qu'aujourd'hui (URL signée, puis clé d'objet). Aucun fichier
  n'est gardé hors du cache temporaire du sélecteur.
- **Déconnexion** : le push est d'abord retiré (`signOutPharmacy`, inchangé).
- **Client anonyme** : aucun nom ni numéro client n'est affiché avant la confirmation, comme le
  veut l'API.

## Tests

Tests de widgets avec `FakeApiServer`, un fichier par fonctionnalité. Chaque critère d'acceptation
a son test :
- **Lancement** : présentation montrée une fois, connexion sans e-mail, titre du code selon le
  canal (avec un test qui vérifie que l'acheteur n'a pas changé).
- **Dossier** :
  - 5 étapes et pastille ;
  - photo envoyée après la création ;
  - case obligatoire ;
  - bouton d'envoi grisé ;
  - reprise d'un brouillon ;
  - motif des compléments.
- **Accueil** : interrupteur (`PUT status`), chiffres et pastille de la barre.
- **Alertes** :
  - F10 sur un push simulé et sur la relecture ;
  - « Ignorer » envoie `decline` ;
  - total et « n / N » ;
  - corps envoyé ;
  - F14 ;
  - alerte terminée ;
  - compte à rebours à zéro.
- **F12** : appels du canal `ivia/secure_screen` (activer, puis désactiver à la fermeture).
- **Commandes** :
  - préparée ;
  - remise exigeant 4 chiffres et les cases ;
  - code faux ;
  - F17, puis F19 ;
  - feuille F18 et ses motifs ;
  - « Garder » sans appel.
- **Planning, relevé et profil** :
  - ajout de garde et heures de nuit ;
  - solde et compte ;
  - sonnerie mémorisée ;
  - déconnexion qui retire le push en premier.
- **Accessibilité** : chaque écran est rendu en 320 × 640 dp avec la police à 200 %, sans erreur de
  débordement, et les libellés du lecteur d'écran sont vérifiés.

Les parties critiques de `docs/TESTING.md` sont côté serveur et ne changent pas : pas de TDD
imposé ici.

Vérification visuelle :
- chaque écran est comparé à sa maquette sur le simulateur iPhone 17 Pro, avec les données de
  `seed-demo` ;
- l'alerte plein écran, la sonnerie et le blocage de capture se vérifient sur Android quand un
  émulateur est disponible.

## Risques

- **Taille** : 24 écrans. Le découpage en tâches permet de committer et de relire au fil de l'eau.
  Les écrans les plus utilisés (alerte, réponse, remise) passent avant les écrans de réglage.
- **Écrans communs** : toute option ajoutée à la connexion, à la présentation ou au splash est
  facultative. Les suites des trois autres apps doivent rester vertes.
- **Sonnerie par téléphone** : sur Android, on ne change pas le son d'un canal existant. D'où deux
  canaux. Le canal actuel garde son identifiant pour ne pas casser les installations.
- **Relecture toutes les 5 s et F10** : sans push, une alerte n'ouvre F10 qu'une fois (identifiants
  déjà montrés gardés en mémoire), et jamais par-dessus une réponse en cours de saisie.
- **Chiffres du jour sur 50 alertes** : ils peuvent être sous-estimés un jour très chargé. Un
  compteur serveur est noté pour Gedeon.
- **Travail en parallèle de Gedeon** sur `push.dart` et le dossier : on récupère `develop` avant
  chaque tâche qui les touche.
