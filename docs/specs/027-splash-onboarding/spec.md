# 027 — Écran de lancement (splash) et présentation (onboarding)

## Objectif

Donner à chaque app (acheteur, marchand, livreur) une identité dès son ouverture, puis expliquer en
trois écrans, au premier lancement seulement, ce que l'app permet de faire. Le public visé n'utilise
souvent que WhatsApp et Mobile Money ([PRD](../../PRD.md)) : il faut le rassurer avant de lui
demander son e-mail.

## Comportement attendu

**Splash** (maquettes fournies par le porteur du projet le 2026-10-30) :

| App | Fond | Logo |
|---|---|---|
| Acheteur | Imperial Red `#ED1C2F` | Logotype blanc, centré |
| Marchand | Berkeley Blue `#0E2E54` | Logotype Berkeley Blue dans une tuile blanche à coins arrondis, centrée |
| Livreur | Cobalt Blue `#004DA8` | Logotype Cobalt Blue dans une tuile blanche à coins arrondis, centrée |

1. L'utilisateur ouvre l'app : le splash s'affiche immédiatement, avant même que Flutter démarre.
2. Il reste affiché le temps de l'initialisation (lecture de l'état local), sans délai artificiel.
3. Ensuite :
   - au premier lancement, la présentation s'ouvre ;
   - aux lancements suivants, l'écran de connexion s'ouvre directement (pour l'instant, un écran
     provisoire en attendant la fonctionnalité 001).

**Présentation** : trois pages qu'on fait défiler (balayage ou bouton « Suivant »). Chaque page
comporte une illustration, un titre court et une phrase. Un indicateur montre la page en cours, et un
bouton « Passer » en haut permet de sauter la présentation. Sur la dernière page, le bouton devient
« Commencer ». « Passer » comme « Commencer » mènent à l'écran de connexion, et la présentation n'est
plus jamais montrée sur cet appareil.

Contenu proposé (à valider) :

| App | Page 1 | Page 2 | Page 3 |
|---|---|---|---|
| Acheteur | **Les boutiques de Lomé dans votre poche** — Trouvez un produit près de chez vous, avec son prix et sa disponibilité. | **Payez par Flooz ou T-Money** — Votre paiement est confirmé avant que la boutique prépare votre commande. | **Retrait ou livraison, à vous de choisir** — Suivez votre commande étape par étape et remettez votre code à la réception. |
| Marchand | **Votre boutique en ligne** — Créez-la en quelques minutes ; ivia la vérifie avant de la publier. | **Des commandes déjà payées** — Acceptez-les en un geste, l'acheteur a payé par Mobile Money. | **Une remise sans litige** — Le code de l'acheteur confirme chaque remise ; vos relevés sont tenus pour vous. |
| Livreur | **Des missions près de vous** — Recevez des propositions selon votre position et votre véhicule. | **Guidé de la boutique au client** — Itinéraire, récupération, puis code du client pour terminer. | **Disponible quand vous le décidez** — Votre position n'est partagée que lorsque vous êtes en service. |

Les illustrations sont provisoires (pictogrammes) jusqu'à la livraison des illustrations du designer.

## Critères d'acceptation

- [ ] Étant donné une première installation, quand l'utilisateur ouvre l'app, alors le splash de son
      app s'affiche, puis la page 1 de la présentation.
- [ ] Étant donné la présentation ouverte, quand l'utilisateur appuie sur « Suivant » (ou balaie),
      alors la page suivante s'affiche et l'indicateur se met à jour.
- [ ] Étant donné la page 3, alors le bouton principal affiche « Commencer » ; un appui ouvre l'écran
      de connexion.
- [ ] Étant donné n'importe quelle page, quand l'utilisateur appuie sur « Passer », alors l'écran de
      connexion s'ouvre.
- [ ] Étant donné une présentation terminée ou passée, quand l'utilisateur relance l'app, alors
      il arrive sur l'écran de connexion sans revoir la présentation.
- [ ] Étant donné la page 2 ou 3, quand l'utilisateur fait « retour », alors la page précédente
      s'affiche ; sur la page 1, « retour » quitte l'app.
- [ ] Étant donné la police du téléphone agrandie à 200 % ou un écran de 320 dp de large, alors aucun
      texte n'est tronqué ni ne déborde, et aucun mot de titre n'est coupé (les titres sont plafonnés
      à 150 %, le texte courant suit les 200 %).
- [ ] Le lecteur d'écran annonce « ivia » sur le logo, le titre et le texte de chaque page, et
      « Page n sur 3 » à chaque changement de page.
- [ ] Les couleurs et le texte respectent les contrastes de `docs/DESIGN.md` (bouton principal
      Imperial Red dans les trois apps).

## Cas limites et erreurs

- **Lecture de l'état local impossible** (stockage corrompu) : on montre la présentation. C'est
  sans risque et l'app ne bloque pas.
- **Écriture impossible** : on navigue quand même vers la connexion. La présentation reviendra au
  prochain lancement, ce qui est acceptable.
- **App fermée pendant la présentation** : elle reprend à la page 1 au lancement suivant.
- **Données de l'app effacées ou réinstallation** : la présentation revient (l'état est propre à
  l'appareil, il n'est pas lié au compte).
- **Hors ligne** : splash et présentation n'ont besoin d'aucun réseau.
- **Rotation** : les apps restent en portrait (voir Hors périmètre) ; aucun état ne doit être perdu
  si l'écran est reconstruit.

## Hors périmètre

- L'écran de connexion lui-même : fonctionnalité [001](../001-connexion-otp/spec.md).
- Les demandes de permissions (localisation du livreur, notifications) : elles viendront avec leurs
  fonctionnalités (012, 019), au moment où elles servent.
- Les illustrations définitives, l'icône de lancement des apps et les identifiants
  `com.example.*` : démarches suivies dans `TASKS.md`.
- Le mode paysage et le mode sombre.

## Révision du 2026-10-31 : maquettes de l'app acheteur

Maquettes fournies par le porteur du projet. Elles guident l'écran mais ne le figent pas.

**Splash de chargement (acheteur)** : après le splash natif, un écran Flutter identique (fond Imperial,
logotype blanc à la même place) ajoute le slogan « Tout, près de chez vous. » sous le logo et trois
points animés en bas. Il reste affiché pendant le démarrage (lecture de l'état local et de la session,
voir [001](../001-connexion-otp/spec.md)), **au moins 800 ms** pour que le slogan se lise, et au plus
le temps de la vérification de session (délai réseau de 5 s).

**Nouvelle mise en page de la présentation (les 3 apps)** : fond gris clair, grande illustration
dans une carte aux coins arrondis, indicateur de page aligné à gauche au-dessus du titre, titre aligné
à gauche avec une partie en rouge, texte, bouton principal en pilule. En-tête : logo dans une tuile
rouge sur la page 1, bouton retour rond ensuite ; « Passer » à droite sauf sur la dernière page.

| Page (acheteur) | Illustration | Titre (partie en rouge) | Texte |
|---|---|---|---|
| 1 | Carte Imperial : deux fiches produit inclinées (photo, nom, prix, distance) et la pastille « Autour de moi · Tokoin » | Trouvez ce qu'il vous faut, **tout près.** | Les produits des boutiques de votre quartier, avec le prix et la disponibilité. |
| 2 | Carte Berkeley : « Total à payer 16 500 FCFA », choix Flooz / T-Money, pastille « Paiement reçu » | Payez en confiance avec **Mobile Money.** | Flooz ou T-Money, directement dans l'app. La commande est confirmée dès que le paiement est reçu. |
| 3 | Mosaïque : « Livraison moto ou voiture » (Cobalt), « Retrait en boutique » (blanc), code de remise 4 8 2 7 (Imperial) | Retrait ou **livraison,** vous choisissez. | Suivez chaque étape de votre commande. Votre code à 4 chiffres garantit la remise. |

Les illustrations sont dessinées en Flutter (pas d'images) : les photos de produits et les logos
Flooz / T-Money restent des emplacements hachurés jusqu'à la fourniture des visuels. Les apps
marchand et livreur prennent la nouvelle mise en page avec leur pictogramme dans une carte de leur
couleur, en attendant leurs maquettes.

Critères d'acceptation ajoutés :
- [ ] Étant donné l'app acheteur, au lancement, alors le splash de chargement affiche le slogan et
      les points animés pendant au moins 800 ms, puis l'écran suivant (présentation, connexion,
      profil ou accueil selon la session).
- [ ] Étant donné la page 2 ou 3, quand l'utilisateur appuie sur le bouton retour rond, alors la page
      précédente s'affiche.
- [ ] Les illustrations sont ignorées par le lecteur d'écran (décoratives) ; titres et textes restent
      lus.

## Questions ouvertes

- Contenu des pages marchand et livreur : en attente de leurs maquettes.
