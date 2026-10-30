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
  `onboarding.dart` (`IviaOnboarding`). Le test `contrast_test.dart` vérifie les
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
L'action principale reste Imperial Red dans les trois apps.

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
- Rayons : `6` tuiles intérieures de mosaïque · `14` boutons et petites cartes · `18` champs,
  grandes cartes, barre de navigation, coin extérieur de la mosaïque · `999` pastilles et puces.
- Ombres : aucune sur les cartes (blanc posé sur `#F3F4F6`). Seule ombre : feuilles non modales
  (les feuilles modales du thème n'en ont pas, le voile les détache),
  `0 -8px 24px rgba(14,46,84,.12)`.
- Mosaïque : tuiles séparées de 8 px, rayon 6 px sauf le coin tourné vers l'extérieur de la grille (18 px).

## Écrans principaux

Maquettes : à venir (lien Figma à ajouter ici). Les statuts affichés suivent
[Libellés des statuts](#libellés-des-statuts).

### Commun aux trois apps
- **Splash** : écran natif (avant le démarrage de Flutter) aux couleurs de l'app, maintenu pendant
  l'initialisation. Sur Android 12 et plus, l'image est réduite pour tenir dans le cercle imposé
  par le système. Détail : [spec 027](specs/027-splash-onboarding/spec.md).
- **Présentation** (premier lancement) : 3 pages, pictogramme dans un disque pâle de la couleur de
  l'app, titre, phrase ; « Passer », indicateur, « Suivant » puis « Commencer ». Pictogrammes
  provisoires en attendant les illustrations.
- **Connexion** : saisie de l'e-mail → saisie du code à 6 chiffres (champ unique, collage accepté,
  « Renvoyer le code » après 60 s). Préparé pour accepter un numéro de téléphone plus tard.
- **Notifications** : liste chronologique, non lues en gras ; un appui ouvre la commande ou la mission.
- **Profil** : informations, déconnexion, **suppression du compte** (confirmation explicite).

### App acheteur (couleur : Imperial)
- **Accueil** : barre de recherche, « Autour de moi », mosaïque des catégories, boutiques proches.
- **Résultats** : liste produits / boutiques ; puces de filtre (catégorie, prix, quartier), tri pertinence / distance.
- **Boutique** : nom, quartier, distance, produits.
- **Produit** : photos, prix, disponibilité, boutique, « Ajouter au panier ».
- **Panier** : une seule boutique ; ajout d'un produit d'une autre boutique ⇒ feuille « Vider le panier ? ».
- **Validation de commande** : retrait ou livraison ; en livraison : adresse, véhicule, frais ; total détaillé.
- **Paiement** : Flooz ou T-Money, numéro, puis écran d'attente « Validez le paiement sur votre
  téléphone » avec le temps restant ; succès confirmé seulement après réponse du serveur.
- **Suivi de commande** : frise des statuts horodatés, **code de remise** en très grand (4 chiffres
  espacés), bouton d'annulation tant que la boutique n'a pas accepté.
- **Mes commandes**, **Adresses** (texte + quartier + point sur la carte).

### App marchand (couleur : Berkeley)
- **Création de boutique** puis écran « En attente de validation ».
- **Commandes** : onglets Nouvelles / En cours / Terminées ; chaque nouvelle commande affiche le
  compte à rebours de 15 min.
- **Détail de commande** : produits, mode de remise, Accepter / Refuser, puis « En préparation »,
  « Prête » ; saisie du code de remise (retrait) ; remise au livreur.
- **Produits** : liste, formulaire (photos, prix, catégorie, taille de colis, stock suivi ou non), activation.

### App livreur (couleur : Cobalt)
- **Inscription livreur** : identité, véhicule, documents, puis « En attente de validation ».
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
