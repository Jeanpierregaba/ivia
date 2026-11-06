# DESIGN — Interface et expérience

Charte fournie par le porteur du projet (logo, couleurs, typographie, formes). Les éléments marqués
**(proposé)** ne viennent pas de la charte : ils comblent un manque et sont à valider par le designer.

## Intention

- **Simple** : un acheteur qui n'utilise que WhatsApp et Mobile Money doit réussir son premier achat
  sans aide. Une action principale par écran.
- **Rassurant** : on manipule de l'argent. Montants, statuts et prochaines étapes toujours visibles,
  jamais d'état ambigu (« Paiement en cours de vérification » plutôt qu'un écran blanc).
- **Rapide** : écrans légers, utilisables en 3G sur un Android d'entrée de gamme.

Références : Gozem (super-app de Lomé, codage par service), Wave (clarté des montants et des
confirmations), Glovo (suivi de commande par étapes).

## Logo

Fichiers : [`brand/logo-horizontal.png`](brand/logo-horizontal.png) (1200 × 600) et
[`brand/logo-carre.png`](brand/logo-carre.png) (1024 × 1024, base de l'icône des apps).
À fournir par le designer : versions SVG (rouge, blanc, Berkeley Blue, Cobalt Blue) et premier plan
de l'icône adaptative Android. En attendant, les logotypes de `mobile/packages/ui/assets/brand/` et
les images de splash des apps sont tirés de `logo-carre.png` : à remplacer par ses exports.

- Logotype `ivia`, toujours en minuscules, en Parkinsans Bold (700), lettres non modifiées.
- Versions autorisées : blanc sur Imperial Red (principale) · Imperial Red sur fond blanc ou clair ·
  blanc sur Berkeley Blue · Berkeley Blue sur fond clair (secondaire) · Berkeley Blue ou Cobalt Blue
  dans une tuile blanche à coins arrondis (rayon ≈ 21 % du côté), sur fond de la même couleur
  (splash des apps marchand et livreur).
- Zone de protection : la hauteur du point du « i », sur les quatre côtés. Taille minimale : 24 px de haut.
- Interdits : déformer, ajouter contour ou ombre, changer de police, passer en majuscules, logo rouge
  sur fond rouge ou bleu cobalt.

## Design system

- **Apps Flutter** : Material 3 avec un thème construit depuis les tokens ci-dessous, défini une
  seule fois dans `mobile/packages/ui` (`ThemeData`, `ColorScheme`, `TextTheme`) et partagé par les
  3 apps. Les écrans n'écrivent jamais une couleur, une taille de police ou un rayon en dur.
- **Back-office Next.js** : shadcn/ui (sur Tailwind 4), tokens déclarés dans le bloc `@theme` de
  `admin/app/globals.css`.
- **Règle** : on n'invente pas de composant si Material 3 ou shadcn/ui en fournit un équivalent ; on
  le thème. Les composants propres à ivia (tuile de mosaïque, carte produit, frise de suivi, code de
  remise, compte à rebours) vivent dans `packages/ui` et sont listés ici quand ils sont créés.
- **Dans le code** : `mobile/packages/ui/lib/src/` — `tokens.dart` (`IviaColors`,
  `IviaSpacing`, `IviaRadius`, `IviaShadows`), `typography.dart` (`IviaTextStyles`), `theme.dart`
  (`IviaTheme.light()`), `brand.dart` (`IviaLogo`, `IviaAppBrand` : couleurs de chaque app),
  `onboarding.dart` (`IviaOnboarding`, `OnboardingArtboard`), `components.dart` (`IviaLogoTile`,
  `IviaBackButton`, `IviaFieldLabel`, `IviaInfoCard`, `IviaPill`, `IviaImagePlaceholder`),
  `code_input.dart` (`IviaCodeInput`), `loading_splash.dart` (`IviaLoadingSplash`, logotype ou
  tuile), `step_list.dart` (`IviaStepList`), `illustration.dart` (`IllustrationCard`, `Tilted`,
  `MosaicTile`, `CheckPill` : briques des illustrations), `amount_row.dart` (`IviaAmountRow` :
  « libellé … montant », montant sous le libellé si ce dernier garde moins de 40 % de la
  largeur), `countdown.dart` (`IviaCountdown` :
  « 12:40 » relu chaque seconde sur l'heure du serveur, warning puis error sous 3 min, « Délai
  dépassé », lu à la minute près), `navigation.dart` (`IviaBottomNav`, pastille d'onglet
  `IviaNavItem.badge` en Cornell, « 9+ » au-delà de 9, lue « Commandes, 2 nouvelles »). Champs
  communs de connexion et de formulaire (`TogoPhoneField`, `ConsentCheckbox`), libellés des
  commandes (`statusLabel`, `statusPill`) et messages en bas d'écran (`showMessage`) :
  `mobile/packages/app_core`.
  Le test `contrast_test.dart` vérifie les
  ratios du tableau « Contrastes » : à mettre à jour avec ce fichier si une couleur change.
- Pas de mode sombre au MVP. Les tokens sont nommés par rôle (`surface`, `text-muted`…) et non par
  couleur, pour pouvoir l'ajouter sans toucher aux écrans.

## Tokens

### Couleurs de marque

| Token | Nom | Hex | Rôle |
|---|---|---|---|
| `primary` | Imperial Red | `#ED1C2F` | Logo, action principale (bouton plein), éléments actifs |
| `primary-strong` | Cornell Red | `#AA0E1B` | État appuyé, texte rouge sur fond clair |
| `secondary` | Cobalt Blue | `#004DA8` | Liens, informations, app livreur |
| `tertiary` | Berkeley Blue | `#0E2E54` | Fonds sombres, en-têtes foncés, app marchand |

### Neutres

| Token | Hex | Rôle |
|---|---|---|
| `surface` | `#FFFFFF` | Cartes, feuilles, champs |
| `background` | `#F3F4F6` | Fond d'écran |
| `background-alt` | `#F6F7F9` | Zones secondaires |
| `border` | `#E3E6EB` | Séparateurs et contours décoratifs |
| `border-input` **(proposé)** | `#7F8C9E` | Contour des champs et cases à cocher (contraste 3:1 exigé) |
| `text` | `#0A1A30` | Texte principal |
| `text-secondary` | `#3A4A60` | Paragraphes |
| `text-muted` | `#5A6A80` | Légendes, métadonnées |

### Couleurs d'état (proposé)

| Token | Hex | Usage |
|---|---|---|
| `success` | `#1E7A4C` | Paiement réussi, commande livrée ou retirée |
| `warning` | `#B45309` | Paiement en attente, délai bientôt écoulé |
| `error` | `#AA0E1B` (Cornell Red) | Erreurs, échec, annulation |
| `info` | `#004DA8` (Cobalt Blue) | Information neutre |

Le rouge étant la couleur de marque, une erreur n'est **jamais** signalée par la couleur seule :
toujours une icône et un texte.

Teintes pâles **(proposé)** : `primary-soft` `#FDE8EA` et `secondary-soft` `#E5EEF8`, fonds des
éléments sélectionnés (puce de filtre, indicateur de la barre de navigation) avec texte foncé.
Textes rouges : Cornell Red (boutons texte, onglet actif, libellé d'un champ actif).
Pastilles de statut : `success-soft` `#EDF7F1` (texte `success`) et `warning-soft` `#FEF5EC`
(texte `warning`), en plus des deux teintes ci-dessus (`error` sur `primary-soft`, `info` sur
`secondary-soft`) ; contraste ≥ 4,5 vérifié par `contrast_test.dart`.

### Couleur de chaque app

Fixée par les maquettes de splash du 2026-10-30 (`IviaAppBrand` dans `packages/ui`). Elle remplace
l'ancien codage par famille de services (Cornell pour la livraison, Cobalt et Berkeley réservés à
la mobilité et à la santé) : **à confirmer avec le designer**.

| App | Couleur | Splash |
|---|---|---|
| Acheteur | Imperial `#ED1C2F` | Logotype blanc sur fond Imperial |
| Marchand | Berkeley `#0E2E54` | Tuile blanche, logotype Berkeley, sur fond Berkeley |
| Livreur | Cobalt `#004DA8` | Tuile blanche, logotype Cobalt, sur fond Cobalt |

La couleur de l'app sert au splash, aux pictogrammes, aux indicateurs et aux en-têtes de section.

Couleurs d'action par app (maquettes marchand du 2026-10-31, choix à confirmer avec le designer),
portées par le thème (`IviaTheme.light(brand)`, `IviaAppBrand.of(context)`) :

| App | Action (boutons, champ actif, case) | Liens | Partie colorée des titres |
|---|---|---|---|
| Acheteur | Imperial | Cornell | Imperial |
| Marchand | Berkeley | Berkeley | Cobalt |
| Livreur | Cobalt | Cobalt | Cobalt |

Exception tirée des maquettes livreur : le choix sélectionné d'un sélecteur segmenté (Moto /
Voiture) est en Berkeley.

### Contrastes (WCAG 2.2, calculés)

| Combinaison | Ratio | Usage permis |
|---|---|---|
| Blanc sur Imperial Red | 4,37 | Boutons (16 px, 700) et titres ; jamais de texte courant |
| Imperial Red sur blanc / sur `#F3F4F6` | 4,37 / 3,97 | Icônes, titres ≥ 24 px ; **jamais** de texte courant ni de prix |
| Cornell Red sur `#F3F4F6` | 6,84 | Texte rouge courant, messages d'erreur |
| Blanc sur Cornell, Cobalt, Berkeley | 7,5 à 13,7 | Libre |
| `text-muted` sur `#F3F4F6` | 5,01 | Légendes |
| `border` sur blanc | 1,25 | Décoratif seulement, jamais seul contour d'un champ |
| Couleur de l'app sur blanc ou sur son fond pâle (`primary-soft`, `secondary-soft`) | ≥ 3 | Pictogrammes et indicateurs (3:1 exigé pour les éléments graphiques) |

Interdit : texte rouge sur fond bleu, texte bleu sur fond rouge.

### Typographie

Police unique : **Parkinsans** (Google Fonts, graisses 300 à 800). Elle est **embarquée** dans
`packages/ui` (fichiers `.ttf` en assets, pas de téléchargement au lancement : 3G et hors ligne) et
chargée par `next/font/google` dans le back-office.

| Token | Taille / interligne | Graisse | Interlettrage | Material 3 |
|---|---|---|---|---|
| `display` | 34 / 38 | 700 | −2 % | `displayLarge/Medium/Small` |
| `title1` | 28 / 32 | 700 | −2 % | `headlineLarge/Medium` |
| `title2` | 22 / 28 | 700 | −1 % | `titleLarge`, `headlineSmall` (titre de dialogue) |
| `title3` | 17 / 22 | 700 | 0 | `titleMedium` |
| `body` | 15 / 22 | 400 | 0 | `bodyLarge`, `bodyMedium` |
| `body-strong` | 15 / 22 | 600 | 0 | `titleSmall` |
| `caption` | 13 / 18 | 400 | 0 | `bodySmall` ; en 600 : `labelMedium` (puces) |
| `overline` | 12 / 16 | 600, majuscules | +8 % | `labelSmall` |
| `button` | 16 / 20 | 700 | 0 | `labelLarge` |

Chiffres (prix, durées, distances, codes) en 600. Parkinsans n'a pas de chiffres tabulaires : un
compte à rebours place chaque chiffre dans une case de largeur fixe (composant à créer dans `packages/ui`).

### Espacements, rayons, ombres

- Grille de **4 px** ; espacements : 4, 8, 12, 16, 20, 24, 32, 40. Marges latérales : 16 px.
- Rayons : `6` tuiles intérieures de mosaïque · `14` petites cartes et cases du code · `18` champs,
  grandes cartes, barre de navigation, coin extérieur de la mosaïque · `999` pastilles, puces et
  **boutons pleins et à contour** (pilules de 54 dp de haut, maquettes du 2026-10-31 ; bouton
  désactivé : fond `border`, texte `text-muted`).
- Champs : fond blanc, contour fin `border-input` au repos (3:1), Imperial de 2 dp quand le champ est
  actif ; libellé au-dessus du champ (`IviaFieldLabel`), jamais de libellé flottant.
- Ombres : aucune sur les cartes (blanc posé sur `#F3F4F6`), sauf dans les illustrations décoratives
  de la présentation (fiches inclinées). Seule ombre d'interface : feuilles non modales
  (les feuilles modales du thème n'en ont pas, le voile les détache),
  `0 -8px 24px rgba(14,46,84,.12)`, et barre du bas flottante, `0 6px 20px rgba(14,46,84,.10)`.
- Mosaïque : tuiles séparées de 8 px, rayon 6 px sauf le coin tourné vers l'extérieur de la grille (18 px).

## Écrans principaux

Maquettes : à venir (lien Figma à ajouter ici). Les statuts affichés suivent
[Libellés des statuts](#libellés-des-statuts).

### Commun aux trois apps
- **Splash** : écran natif (avant le démarrage de Flutter) aux couleurs de l'app, maintenu pendant
  l'initialisation. Sur Android 12 et plus, l'image est réduite pour tenir dans le cercle imposé
  par le système. Détail : [spec 027](specs/027-splash-onboarding/spec.md).
- **Splash de chargement** (acheteur) : après le splash natif, même fond et logotype au même endroit,
  slogan « Tout, près de chez vous. » 40 dp dessous, trois points animés ; au moins 800 ms.
- **Autorisation de la localisation** ([spec 030](specs/030-autorisation-localisation/spec.md)),
  juste après le splash, au premier lancement : grand panneau de la couleur de l'app (coins
  inférieurs arrondis de 48 dp), tuile blanche du logo teinté et nom de l'espace (« Business »,
  « Livreur », « Pharmacie »), cercles concentriques avec une pastille centrale et quatre pastilles
  blanches ; titre en deux tons, texte, « Autoriser la localisation » (pilule, épingle) et
  « Refuser ». Le même écran s'ouvre par-dessus avant une action qui a besoin de la position.
  Refus définitif : le bouton ouvre les réglages. Composants `IviaLocationPrompt` et
  `IviaLocationRadar` (`packages/ui`).
- **Présentation** (premier lancement) : fond gris, grande illustration (plan de 324 × 421 dp mis à
  l'échelle), indicateur puis titre alignés à gauche avec une partie en rouge, texte, bouton en
  pilule ; logo en tuile sur la page 1, bouton retour rond ensuite ; « Passer » sauf sur la dernière
  page. Acheteur : illustrations des maquettes ; marchand et livreur : pictogramme dans une carte de
  leur couleur, en attendant leurs maquettes.
- **Connexion** ([spec 001](specs/001-connexion-otp/spec.md) v2, ADR 0012), commune aux apps :
  numéro (+228, 8 chiffres) ⇒ « Recevoir le code sur WhatsApp » ou « Recevoir par SMS » (« Pas
  de mot de passe : un code à 6 chiffres vous est envoyé à chaque connexion. ») ; mentions
  légales. « Saisissez le code » : 6 chiffres, vérification au 6e, « Modifier le numéro »,
  « Renvoyer le code » après le compte à rebours, SMS en secours. Numéro nouveau : « Faisons
  connaissance » (prénom, nom, consentement). Profil : changer de numéro (code envoyé au nouveau
  numéro), appareils connectés.
- **Notifications** : liste chronologique, non lues en gras ; un appui ouvre la commande ou la mission.
- **Profil** : informations, déconnexion, **suppression du compte** (confirmation explicite).

### App acheteur (couleur : Imperial)
- **Barre du bas** ([spec 007](specs/007-accueil-recherche-acheteur/spec.md)) : Accueil ·
  Recherche · Commandes · Profil, pilule Imperial pour l'onglet actif. Le panier est une icône de
  l'en-tête (008).
- **Accueil** : « Près de · Tokoin ▾ » (position du téléphone ou quartier, feuille de choix),
  « Bonjour Awa, **que cherchez-vous ?** », champ factice qui ouvre l'onglet Recherche, puces de
  catégories, « Boutiques autour de vous » (cartes en défilement horizontal, distance en Cobalt),
  « Nouveautés autour de vous » (grille de cartes produit). « Voir tout » en Cornell.
- **Recherche** : champ, onglets Produits / Boutiques, **puces de filtre** (`IviaChip` : blanches,
  pleines en Berkeley quand elles sont actives, flèche quand elles ouvrent un choix) pour la zone
  (« Autour de moi · 2 km » ou le quartier), la catégorie, le prix, « En stock » ; « Trier :
  pertinence ▾ ». Produits en grille de deux colonnes (une seule avec une police agrandie).
- **Icône du panier** ([spec 008](specs/008-panier/spec.md)) : bouton rond blanc
  (`IviaIconBadgeButton`) en haut à droite de l'accueil, de la boutique et du produit, pastille
  Imperial du nombre d'articles (somme des quantités, « 99+ » au-delà), lue « Panier, 3 articles » ;
  elle suit la police jusqu'à 1,6 fois, pour rester dans le bouton.
- **Ajout rapide** : « + » rond Imperial (`IviaAddButton`, 36 dp visibles, 48 au doigt) sur la photo
  des cartes produit et au bout des lignes de la boutique ; jamais sur un produit épuisé. Message
  « Riz parfumé 5 kg ajouté au panier » avec « Voir le panier ».
- **Boutique** : carte d'en-tête (logo, nom, adresse, pastilles « Ouverte » et distance), recherche
  dans la boutique, liste des produits (« En stock » en Cobalt, « Épuisé » en rouge) ; barre
  « Voir le panier · 3 » et sous-total en bas quand le panier est de cette boutique.
- **Produit** : photos défilantes en haut avec retour par-dessus, nom et prix, disponibilité,
  carte de la boutique, description, pastilles catégorie et « Colis moyen · moto », quantité et
  « Ajouter · 4 500 F » en bas (la quantité s'ajoute à celle du panier, « Déjà 2 dans votre
  panier »).
- **Panier** : une seule boutique ; ajout d'un produit d'une autre boutique ⇒ feuille « Vider le
  panier ? » (« Vider et ajouter » en rouge, « Annuler »). Écran : retour et « Vider », titre, carte
  de la boutique, lignes (photo, nom, prix, quantité sans saisie : « − » devient une corbeille au
  dernier exemplaire et retire la ligne, avec « Annuler »), raison en rouge d'une ligne qui bloque
  (« Plus que 2 en stock. », « Retirer », « Ajuster à 2 »), frais de livraison annoncés, note « une
  seule boutique » ; en bas, sous-total et « Commander » (désactivé si une ligne bloque ou si la
  boutique ne prend plus de commandes). Vide : « Votre panier est vide. » et « Découvrir les
  produits ».
- **Commande** ([spec 009](specs/009-commande-retrait/spec.md)) : deux cartes de mode (« Livraison »
  désactivée avec « Bientôt » jusqu'à la 020, « Retrait » choisi, bordure de la couleur
  d'action), carte « Retrait chez Chez Afi », récapitulatif du serveur (lignes, « Produits ·
  3 articles », « Total »), « Vos produits sont réservés 15 minutes » ; en bas « Payer 10 500 F ».
  En livraison (020) : adresse, véhicule, frais.
- **Paiement** (au-dessus du suivi, après « Payer » de l'écran Commande ou du suivi) : « Montant à
  payer » en grand, cartes **Flooz** / **T-Money** (bouton radio, bordure de la couleur d'action ;
  initiale sur fond neutre, pas de logo d'opérateur), « Numéro Flooz » (`TogoPhoneField`,
  pré-rempli avec le numéro du profil), « Paiement sécurisé… » en information (cadenas, pas de case
  à cocher), en bas « Payer 10 500 F ».
- **Attente** « Validez le paiement sur votre téléphone » : rond qui tourne, « Une demande Flooz de
  10 500 F a été envoyée au +228 96 •• •• 78 » (numéro masqué du serveur), carte « Temps restant
  14:32 » avec barre qui se vide (lue une fois en toutes lettres), « Je n'ai rien reçu » (feuille :
  renvoyer, changer de numéro) et « Annuler le paiement » (confirmation). Succès confirmé
  seulement par le serveur : le suivi s'ouvre avec le code de remise. Échec : croix sur fond
  `primarySoft`, « Le paiement n'a pas abouti », raison du serveur, « Réessayer ».
- **Suivi de commande** (« Commande #1042 ») : en-tête de l'étape en **Cornell** tant que la
  commande est en cours (texte blanc : Imperial n'atteint pas 4,5:1 sous le texte courant), vert
  une fois retirée, blanc pour une fin anormale ; « À payer avant 14:32 » et « Payer » en attente de
  paiement ; **code de remise** en très grand (`IviaHandoverCode` : 4 cases blanches, chiffres
  Cornell, lu chiffre par chiffre) ; carte de la boutique ; frise (`IviaTimeline`) des statuts
  horodatés, étapes à venir en gris ; articles et total (`IviaAmountRow` : montant à droite,
  ou sous le libellé quand la place manque). **Annulation** ([spec 013](specs/013-annulation-acheteur/spec.md)) tant que la
  boutique n'a pas accepté : bouton contour Cornell « Annuler la commande » en bas du suivi ;
  feuille « Annuler la commande #1042 ? » (« Vos produits seront libérés. » ou « Vous serez
  remboursé de 10 500 F sur votre compte Mobile Money. »), « Annuler la commande » plein Cornell,
  « Garder ma commande » ; annulée et payée : le remboursement annoncé sous « Annulée ».
- **Commandes** (onglet) : onglets « En cours · 2 » / « Terminées » (`IviaSegmentedTabs`), lignes
  (logo, boutique, « #1042 · Retrait · 3 articles » ou « #1018 · 24 oct. », total, pastille de
  statut avec icône), « Récemment » sous les commandes en cours (3 dernières terminées).
- **Adresses** (texte + quartier + point sur la carte) : 002.

### App marchand (couleur : Berkeley)
- **Lancement** ([spec 004](specs/004-espace-marchand/spec.md)) : splash de chargement (tuile,
  « Marchand », « Vendez dans votre quartier. ») ; présentation (boutique en ligne, commandes déjà
  payées, remise par code) avec « Marchand » à côté du logo ; « Espace marchand » (même compte que
  l'acheteur).
- **Création de boutique** (« Étape 1 sur 2 ») : logo facultatif, nom, catégorie, téléphone de la
  boutique, adresse, quartier, position (carte Google Maps ou aperçu, « Ma position »),
  consentement si le compte ne l'a pas donné ; puis « En cours de validation » (liste d'étapes,
  actualisation en tirant), refus ou suspension avec le motif.
- **Pièces du marchand** ([spec 028](specs/028-pieces-marchand/spec.md), « Étape 2 sur 2 ») :
  « Vérifions votre identité », ouvert après la création de la boutique si la pièce d'identité
  manque ; lignes de document du dossier livreur (`DocumentPhotoRow`) : « Pièce d'identité »
  (Obligatoire, face avec la photo) et « Registre du commerce (RCCM) » (Facultatif), états
  Ajouter / Ajoutée / Envoyée, appareil photo ou galerie ; « Envoyer mes pièces ». Avec une police
  agrandie, l'état passe sous le libellé. Sur « En cours de validation », étape « Pièce
  d'identité » (À ajouter ou Envoyée) ; sans elle, « Ajouter ma pièce d'identité » en bouton
  principal, « Préparer mes produits » en bouton secondaire.
- **Accueil** ([spec 011](specs/011-commandes-marchand/spec.md)) : tuile, nom de la boutique ;
  carte orangé pâle « 2 nouvelles commandes à accepter » avec « La première expire dans 05:40 »,
  carte blanche « 1 commande en cours » (un appui ouvre le bon onglet) ; sinon « Aucune commande à
  traiter. Les nouvelles commandes arrivent ici. » ; « Mes produits ».
- **Commandes** : nouvelles relues toutes les 30 s app ouverte (liste complète au retour et à
  l'ouverture de l'onglet), pastille sur l'onglet ; onglets
  **Nouvelles / En cours / Terminées** avec leur nombre ; lignes dans une carte blanche
  (« #1042 · Koffi », « Retrait · 3 articles » ou « Aujourd'hui 14:05 » pour une terminée,
  montant des produits, pastille de statut, compte à rebours sur une nouvelle, la plus urgente en
  haut) ; « Afficher plus » dans Terminées.
- **Détail de commande** (« Commande #1042 ») : carte d'en-tête (statut, « Pour Koffi · Retrait en
  boutique », « Payée à 14:00 », « Il vous reste 12:40 pour répondre » et « Sans réponse, la
  commande est annulée et l'acheteur remboursé. ») ; articles, « Stock non suivi : vérifiez que
  vous l'avez » en orangé ; Produits, Commission ivia, **Vous recevez**. En bas, un bouton par
  étape : « Accepter la commande » et « Refuser » (contour), « Commencer la préparation »,
  « Commande prête », « Saisir le code de l'acheteur » ; erreurs au-dessus du bouton (un message en
  bas d'écran le cacherait). Livraison : rien après « prête » (« La suite de la livraison est
  gérée par ivia. »).
- **Refus** : feuille « Pourquoi refusez-vous ? » (« Produit en rupture », « Boutique fermée »,
  « Impossible de préparer à temps », « Autre » avec un texte de 200 caractères au plus),
  « L'acheteur verra ce motif et sera remboursé. », « Refuser la commande ».
- **Code de remise** : « Demandez à Koffi son code à 4 chiffres. », 4 cases (`IviaCodeInput`),
  « Remettre la commande » fixé en bas au-dessus du clavier ; essais restants, puis code bloqué
  (« Contactez l'équipe ivia »).
- **Barre du bas** (boutique publiée) : pilule blanche flottante, Accueil · Commandes · Catalogue ·
  Compte ; l'onglet actif est une pilule Berkeley avec icône et libellé, les autres une icône seule
  (libellé lu par le lecteur d'écran). Boutique en validation : catalogue seul, sans barre.
- **Catalogue** ([spec 005](specs/005-catalogue-marchand/spec.md)) : « Catalogue », « boutique ·
  N produits », « + Produit » ; recherche en pilule ; onglets **En vente / Brouillons / Retirés**
  avec leur nombre (`IviaSegmentedTabs`) ; lignes dans une carte blanche (vignette, nom, prix
  « 4 500 F », « Catégorie · Stock 12 », « Stock non suivi », « Épuisé · à réapprovisionner » en
  rouge), menu « ⋯ » (Modifier, Ajuster le stock, Retirer de la vente), « Remettre » sur les
  retirés. Avec une police agrandie, le prix passe sous le nom.
- **Nouveau produit** : « 1 sur 2 » (photos 1 à 5, la première « Principale » ; nom ; prix en FCFA
  groupé pendant la saisie ; catégorie ; description 500 caractères), « 2 sur 2 · Livraison et
  stock » (taille du colis en cartes, « Suivre le stock », quantité − / + ; « Brouillon » ou
  « Voir l'aperçu »), **Aperçu** (carte telle que l'acheteur la voit, coches Cobalt, « Publier »),
  puis **Produit publié** (coche Cobalt dans un halo pâle).
- **Modifier** : carte d'état avec interrupteur (« En vente · Visible depuis le… », « Retiré · Non
  visible depuis le… »), vignettes, nom, prix, catégorie, lignes Description / Taille du colis /
  Stock qui ouvrent une feuille ; « Retirer de la vente » en rouge, confirmé par une feuille, puis
  message « Annuler ». Interrupteurs et coches en Cobalt (partie colorée de l'app marchand).

### App livreur (couleur : Cobalt)
- **Lancement** ([spec 018](specs/018-espace-livreur/spec.md)) : splash de chargement (tuile,
  « Livreur », « Livrez près de chez vous. ») ; présentation (propositions, étapes guidées, code du
  client) ; « Espace livreur ».
- **Dossier** (« Devenez livreur ivia ») : prénom, nom, téléphone et consentement si le profil est
  incomplet, véhicule (Moto / Voiture), immatriculation, pièce d'identité, permis, carte grise
  (photo prise ou choisie) ; puis « En cours de vérification » (étapes, « Voir mon dossier »),
  refus avec motif et correction, suspension.
- **Accueil** : interrupteur Disponible / Hors ligne bien visible, rappel de la notification permanente.
- **Proposition de mission** : plein écran, boutique, distance, gain indicatif, compte à rebours de
  45 s, Accepter / Refuser.
- **Mission en cours** : étapes (aller en boutique → récupérer → livrer), « Ouvrir l'itinéraire »,
  « Appeler le client », saisie du code, « Déclarer un échec » (actif après 10 min d'attente).
- **Historique des missions**.

### Back-office (bureau)
Barre latérale Berkeley Blue, contenu sur `#F3F4F6`. Tableau de bord, boutiques et livreurs à
valider, commandes, paiements, file de remboursement, relevés marchands, export des livraisons,
paramètres, journal des actions admin. Tableaux filtrables ; toute action sensible (rembourser,
suspendre, régler) demande une confirmation qui rappelle l'objet et le montant.

## États à toujours prévoir

- **Chargement** : squelettes aux dimensions du contenu, pas d'indicateur plein écran au-delà de 1 s.
- **Vide** : phrase qui explique et action suivante (« Aucune commande pour l'instant. Découvrir les boutiques »).
- **Erreur** : message en français tiré du `message` de l'API, et une action (Réessayer, Modifier).
- **Hors ligne** : bandeau discret « Connexion perdue », dernières données affichées, actions
  d'argent désactivées jusqu'au retour du réseau.
- **Succès / confirmation** : confirmation explicite après toute action irréversible ou d'argent.
- **Attente d'un tiers** : paiement, réponse de la boutique, recherche de livreur — toujours un
  texte qui dit qui on attend et combien de temps.

## Libellés des statuts

Codes de la machine à états (`docs/ARCHITECTURE.md`) → texte affiché :

| Code | Libellé | Couleur |
|---|---|---|
| `pending_payment` | En attente de paiement | warning |
| `expired` | Paiement expiré | muted |
| `awaiting_seller` | En attente de la boutique | warning |
| `accepted` | Acceptée par la boutique | info |
| `preparing` | En préparation | info |
| `ready_for_pickup` | Prête à retirer | success |
| `completed` | Retirée | success |
| `awaiting_driver` | Recherche d'un livreur | info |
| `driver_assigned` | Livreur en route vers la boutique | info |
| `picked_up` | En cours de livraison | info |
| `delivered` | Livrée | success |
| `delivery_failed` | Livraison échouée | error |
| `returned_to_shop` | Retournée à la boutique | muted |
| `cancelled` | Annulée | error |
| `refunded` | Remboursée | muted |

Un statut s'affiche toujours avec une icône et son libellé, jamais par sa couleur seule.
Côté marchand : `awaiting_seller` « Nouvelle » et `accepted` « Acceptée » (mêmes couleurs).

États d'un produit (catalogue marchand) : `active` « En vente » (info) · `draft` « Brouillon »
(muted) · `withdrawn` « Retiré » (muted).

## Accessibilité

- Niveau visé : **WCAG 2.2 AA** (écart connu : blanc sur Imperial Red à 4,37, limité aux boutons et titres).
- Zones tactiles d'au moins 48 × 48 dp ; boutons principaux pleine largeur en bas d'écran.
- Taille de texte système respectée : mise en page intacte jusqu'à 130 %, utilisable à 200 %.
- Libellés TalkBack sur toutes les icônes et images ; photos produit avec le nom du produit en texte alternatif.
- Information jamais portée par la couleur seule (statuts, erreurs, champs obligatoires).
- Back-office : navigation complète au clavier, focus visible.

## Responsive

- **Apps** : téléphone en portrait, largeur 360 à 430 dp, minimum supporté 320 dp. Pas de mise
  en page tablette au MVP (contenu centré, 600 dp de large au plus).
- Android d'entrée de gamme : images redimensionnées côté serveur, chargement progressif, listes paginées.
- **Back-office** : bureau d'abord, conçu pour 1280 px et plus, utilisable dès 1024 px ; pas de version mobile.

## Ton et microcopie

- **Vouvoiement**, français simple, phrases courtes. Pas de jargon technique (« webhook »,
  « timeout », « erreur 500 ») à l'écran.
- Boutons à l'infinitif et précis : « Payer 12 500 FCFA », « Accepter la commande », pas « OK » ni « Valider ».
- Montants : `12 500 FCFA` (espace fine insécable entre les milliers, pas de décimales).
- Dates et heures en heure de Lomé : « Aujourd'hui à 14:05 », « Hier à 09:30 », « 12 nov. à 18:00 ».
- Téléphone : `+228 90 12 34 56`.
- Erreurs : dire ce qui s'est passé et quoi faire (« Le paiement n'a pas abouti. Réessayez ou
  choisissez un autre opérateur. »). Ne jamais affirmer ce que le serveur n'a pas confirmé.
- Mots du domaine : boutique, commande, retrait, livraison, livreur, code de remise (voir le
  vocabulaire de `docs/PRD.md`).
