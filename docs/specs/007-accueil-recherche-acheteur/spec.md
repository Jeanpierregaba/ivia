# 007 — Accueil et recherche de l'acheteur

## Objectif

Permettre à l'acheteur de trouver un produit près de chez lui : accueil, recherche par texte avec
filtres, fiche boutique, fiche produit ([PRD](../../PRD.md), parcours 1 et section « Recherche »).
Maintenant que les marchands publient leurs produits ([005](../005-catalogue-marchand/spec.md)),
c'est ce qui relie l'offre à la demande. Le panier (008) suivra.

Maquettes du 2026-11-01 : elles guident l'écran mais ne le figent pas. Elles couvrent aussi le
panier, la commande, le paiement, le suivi et le profil, traités dans leurs propres
fonctionnalités. Couleurs de l'app acheteur : action en Imperial, textes cliquables en Cornell
(Imperial n'est jamais une couleur de texte courant ni de prix), distances en Cobalt.

## Comportement attendu

**Position de l'acheteur** (« Autour de moi »)
- Au premier accès à l'accueil, l'app demande la position du téléphone (précision approximative
  suffisante).
- Si l'acheteur refuse, ou si la position est indisponible, il choisit son **quartier** dans la
  liste. La recherche filtre alors par quartier et aucune distance ne s'affiche.
- L'en-tête de l'accueil montre « Près de · Ma position » ou « Près de · Tokoin » ; un appui
  ouvre une feuille : « Utiliser ma position » ou la liste des quartiers.
- Le choix est gardé sur le téléphone ; la position, elle, est redemandée à chaque ouverture de
  l'app (jamais envoyée au serveur ailleurs que dans les recherches, arrondie à environ 110 m :
  [ADR 0010](../../decisions/0010-position-arrondie-dans-les-recherches.md)).

**1. Barre du bas** : Accueil · Recherche · Commandes · Profil, même composant que l'app
marchand en Imperial. Le panier sera une icône de l'en-tête, avec la 008.
- Recherche : l'écran de résultats (point 3), champ vide au départ.
- Commandes (009, 013) affiche « Bientôt disponible ».
- Profil : nom, e-mail, « Ouvrir une boutique » (texte d'information sur l'app ivia Marchand au
  MVP), « Se déconnecter ».

**2. Accueil**
- En-tête : position choisie (voir plus haut).
- « Bonjour Awa, **que cherchez-vous ?** » (partie colorée en Imperial).
- Champ « Produit ou boutique… » : un appui ouvre l'onglet Recherche, champ actif.
- Puces de catégories : « Tout » puis les catégories principales ; un appui ouvre l'onglet
  Recherche filtré par cette catégorie.
- « Boutiques autour de vous » : défilement horizontal de cartes (logo ou emplacement vide, nom,
  « Tokoin · 350 m »), les plus proches d'abord ; « Voir tout » ouvre l'onglet Recherche sur
  Boutiques.
- « Nouveautés autour de vous » : grille de produits récents (photo, nom, boutique, distance,
  prix) ; « Voir tout » ouvre l'onglet Recherche sur Produits.
- Tirer vers le bas actualise.

**3. Recherche (onglet)**
- Champ de recherche en haut, recherche envoyée 300 ms après la frappe ; sans texte, les
  produits autour de l'acheteur s'affichent.
- Onglets **Produits / Boutiques**.
- Puces de filtres, en défilement horizontal :
  - « Autour de moi · 5 km » (rayon 1, 2, 5, 10 km ou sans limite ; 5 km par défaut, le même que
    l'accueil) avec la position du téléphone, ou le quartier choisi ;
  - catégorie ;
  - prix (minimum et maximum, en FCFA) ;
  - « En stock » (produits seulement).
- « Trier : pertinence » (produits : pertinence, distance, prix croissant, prix décroissant ;
  boutiques : pertinence, distance). « Distance » n'est proposé qu'avec la position du téléphone.
- Produits en grille de deux colonnes : photo, nom, « boutique · distance », prix, « Épuisé » si
  indisponible.
- Boutiques en liste : logo, nom, « quartier · distance », « Commandes suspendues » si la
  boutique n'accepte pas de commandes.
- La suite se charge au défilement.

**4. Fiche boutique**
- En-tête : logo (ou emplacement vide), nom, « adresse, quartier », pastilles « Ouverte » ou
  « Commandes suspendues », distance si la position est connue.
- Champ « Chercher dans la boutique ».
- Liste des produits en vente : photo, nom, « En stock » ou « Épuisé », prix ; un appui ouvre la
  fiche produit.

**5. Fiche produit**
- Photos en défilement avec points, retour par-dessus.
- Nom, prix « 4 500 F ».
- Disponibilité : « En stock » (et « 12 disponibles » pour un stock suivi), « Épuisé », ou
  « Disponible » (stock non suivi).
- Carte de la boutique (logo, nom, « quartier · distance · Ouverte ») qui ouvre sa fiche.
- Description, pastilles catégorie et « Colis moyen · moto » (petit et moyen : moto ; grand :
  voiture).
- En bas : quantité (− / +) et « Ajouter · 4 500 F ». Le panier arrivant avec la 008, le bouton
  affiche « Le panier arrive bientôt. ».

## Critères d'acceptation

- [x] Étant donné la position autorisée, alors l'accueil affiche les boutiques les plus proches
      avec leur distance, et les recherches envoient `lat`, `lng` (et `radius_m` pour « Autour de
      moi »).
- [x] Étant donné la position refusée, alors l'acheteur choisit un quartier ; les recherches
      envoient `neighborhood_id`, aucune distance n'est affichée, et le choix est retrouvé au
      lancement suivant.
- [x] Étant donné une recherche « riz », alors la requête part 300 ms après la dernière frappe
      (une seule requête pour une frappe rapide) et les produits trouvés s'affichent en grille.
- [x] Étant donné les filtres catégorie, prix, « En stock » et le tri, alors chaque choix est
      envoyé au serveur (`category_id`, `min_price`, `max_price`, `in_stock`, `sort`) et la liste
      se recharge.
- [x] Étant donné l'onglet Boutiques, alors la recherche porte sur les boutiques
      (`/v1/search/shops`) et un appui ouvre la fiche boutique.
- [x] Étant donné une fiche boutique, alors ses produits en vente s'affichent, la recherche dans
      la boutique filtre par nom (`shop_id` + `q`), et un appui ouvre la fiche produit.
- [x] Étant donné une fiche produit, alors photos, prix, disponibilité, boutique, description,
      catégorie et taille de colis s'affichent ; « Ajouter » annonce que le panier arrive bientôt.
- [x] La barre du bas montre Accueil, Recherche, Commandes, Profil ; le champ et les puces de
      l'accueil ouvrent l'onglet Recherche ; Profil permet de se déconnecter.

## Cas limites et erreurs

- **Aucun résultat** : « Aucun produit ne correspond à « … ». » avec « Effacer les filtres » si
  des filtres sont actifs ; « Aucune boutique autour de vous pour l'instant. » à l'accueil.
- **Prix minimal supérieur au maximal** : refusé dans la feuille de prix, avant l'envoi.
- **Tri par distance ou « Autour de moi » sans position** : non proposé ; la puce propose de
  choisir le quartier ou d'autoriser la position.
- **Localisation désactivée, refusée ou trop lente** (15 s) : message court, choix du quartier ;
  jamais de blocage de l'accueil.
- **Trop de recherches** (429 du serveur) : « Trop de recherches. Patientez un instant. »
- **Réseau coupé** : message et « Réessayer » à la place de la section ou de la liste concernée ;
  le reste de l'écran reste utilisable.
- **Produit ou boutique devenu indisponible** (retiré, boutique suspendue : 404) : « Ce produit
  n'est plus disponible. » / « Cette boutique n'est plus disponible. », retour possible.
- **Photo absente ou qui ne charge pas** : emplacement hachuré.
- **Police à 200 %, écran de 320 dp** : rien n'est masqué ; la grille passe à une colonne.

## Hors périmètre

- Panier (008), commande (009), paiement (010), suivi et liste des commandes (013), profil
  complet et adresses (002), bandeau « commande en cours » de l'accueil (013).
- Icône et badge du panier dans l'en-tête, « + » d'ajout rapide sur les cartes (008).
- Popularité (« Populaires à Tokoin ») : aucune donnée de ventes au MVP, remplacée par
  « Nouveautés autour de vous ».
- Nombre total de résultats (« 18 produits ») : l'API ne le renvoie pas.
- Catégorie de la boutique sur les cartes et la fiche boutique : non renvoyée par la recherche ni
  par la fiche publique ; à ajouter côté serveur plus tard si utile.
- Photo de couverture des boutiques : seul le logo existe.
- Filtres par catégorie à l'intérieur d'une boutique (les maquettes en montrent) : la recherche
  dans la boutique suffit au MVP.

## Questions ouvertes

<!-- Vide = prêt pour le plan. -->
