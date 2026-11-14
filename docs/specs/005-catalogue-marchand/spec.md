# 005 — Catalogue marchand : produits, photos, publication

## Objectif

Permettre au marchand d'ajouter ses produits (photos, prix, catégorie, description, taille de colis,
stock), de les publier, de les modifier et de les retirer de la vente
([PRD](../../PRD.md), parcours 4 « Ouverture d'une boutique » et section « Boutiques et catalogue »).
Sans produits, rien à chercher (007), à mettre au panier (008) ni à commander (009).

Maquettes du 2026-10-31 : elles guident l'écran mais ne le figent pas. Couleurs de l'app marchand
([004](../004-espace-marchand/spec.md)) : action en Berkeley, accents (coches, « En stock »,
interrupteur) en Cobalt.

## Comportement attendu

**Trois états d'un produit**

| État | Sens | Visible des acheteurs |
|---|---|---|
| Brouillon | Enregistré, jamais publié | Non |
| En vente | Publié | Oui, si la boutique est publiée |
| Retiré | Publié puis retiré par le marchand | Non |

**1. Barre du bas** (boutique publiée) : Accueil · Commandes · Catalogue · Compte.
- Accueil : l'accueil actuel de la boutique.
- Commandes : « Bientôt disponible » (011).
- Compte : nom et e-mail du compte, boutique, « Se déconnecter ».

Boutique en cours de validation : « Préparer mes produits » ouvre le catalogue sans barre du bas,
avec un retour vers l'écran de validation.

**2. Catalogue**
- En-tête : « Catalogue », « [boutique] · N produits » (tous états confondus), bouton « + Produit ».
- Champ « Rechercher un produit » : recherche dans le nom, sans tenir compte des accents ni des
  majuscules.
- Onglets « En vente », « Brouillons », « Retirés », chacun avec son nombre.
- Ligne de produit : photo principale (ou emplacement vide), nom, prix « 4 500 F », puis l'un de :
  - « Catégorie · Stock 12 » ;
  - « Stock non suivi » ;
  - « Épuisé · à réapprovisionner » en rouge (stock suivi à 0).
- Menu « ⋯ » d'une ligne en vente : Modifier, Ajuster le stock (stock suivi), Retirer de la vente.
- Ligne de brouillon : un appui reprend la création à l'étape 1, préremplie.
- Ligne retirée : « Retiré aujourd'hui / le 24 oct. », bouton « Remettre ».
- Plus de produits que l'écran n'en montre : la suite se charge au défilement. Tirer vers le bas
  actualise.

**3. Nouveau produit, étape 1 sur 2**
- Photos : 1 à 5, la première est la principale.
  - « Ajouter » : prendre une photo ou en choisir une.
  - Appui sur une photo : « Mettre en principale » ou « Supprimer ».
- Nom du produit.
- Prix en FCFA, nombre entier.
- Catégorie (liste des catégories de produits actives ; une sous-catégorie s'affiche
  « Parent › Enfant »).
- Description, facultative, 500 caractères au plus, avec compteur.
- « Continuer ».

**4. Étape 2 sur 2 : « Livraison et stock »**
- Taille du colis : Petit / Moyen / Grand, avec l'explication « La taille détermine le véhicule
  envoyé pour la livraison (moto ou voiture). »
- « Suivre le stock » (interrupteur) et « Quantité disponible » (− / nombre saisissable / +).
- Explication du mode non suivi : « Désactivé : vous confirmez la disponibilité à chaque
  commande. »
- Boutons « Brouillon » (enregistre sans publier, retour au catalogue sur l'onglet Brouillons) et
  « Voir l'aperçu ».

**5. Aperçu**
- « Voici votre produit tel que les acheteurs le verront. »
- Carte produit :
  - photos défilantes avec points ;
  - nom et prix ;
  - « [boutique] · [quartier] · En stock / Épuisé » ;
  - pastilles catégorie et « Colis moyen » ;
  - description sur 3 lignes.
- Vérifications : « N photos », « Prix, catégorie et description », « Stock suivi : 12 » ou
  « Stock non suivi ».
- « Publier », et « Modifier » qui revient à l'étape 1.

**6. « Produit publié »** : coche, carte du produit avec la pastille « En vente », puis
« Ajouter un autre produit » et « Retour au catalogue ». Le texte dépend de la boutique :
- publiée : « Il est visible maintenant par les acheteurs autour de [quartier]. » ;
- en cours de validation : « Il sera visible dès que votre boutique sera validée. »

**7. Modifier** (produit en vente ou retiré)
- Carte d'état :
  - en vente : « En vente · Visible par les acheteurs depuis le 12 oct. » ;
  - retiré : « Retiré · Non visible depuis le 24 oct. ».
  - L'interrupteur change l'état, effectif à l'enregistrement.
- Photos (vignettes et « + »), nom, prix, catégorie.
- Lignes qui ouvrent chacune une feuille : « Description · 98 caractères », « Taille du colis ·
  Moyen », « Stock · Suivi · 12 » ou « Non suivi ».
- « Enregistrer les modifications ».
- « Retirer de la vente » (produit en vente) : feuille de confirmation avec le produit et trois
  points :
  - il n'apparaît plus dans la recherche ni la boutique ;
  - les commandes déjà payées restent à préparer ;
  - remise en vente possible à tout moment.
  - Boutons « Retirer de la vente » (rouge) et « Annuler ».

**8. Après un retrait** : retour au catalogue sur « Retirés ». Un message « [produit] retiré de la
vente » offre « Annuler », qui le remet en vente.

**Stock** : la feuille « Stock » d'un produit suivi ajuste la quantité. Le mode (suivi ou non) est
choisi à la création et ne change plus ensuite, brouillon compris : des commandes peuvent réserver
la quantité. La feuille l'explique.

## Critères d'acceptation

- [x] Étant donné une boutique publiée, alors la barre du bas montre Accueil, Commandes, Catalogue,
      Compte ; Compte permet de se déconnecter.
- [x] Étant donné des produits dans les trois états, alors chaque onglet ne liste que les siens et
      affiche le nombre donné par le serveur ; l'en-tête affiche le total.
- [x] Étant donné une recherche « riz », alors l'onglet ne montre que les produits dont le nom
      contient « riz » ou « Riz », accents ignorés (« cafe » trouve « Café ») ; le filtrage est
      fait par le serveur.
- [x] Étant donné les deux étapes remplies, quand le marchand publie depuis l'aperçu, alors les
      photos (redimensionnées à 1600 px au plus, sans métadonnées) sont envoyées par URL signée,
      le produit est créé en vente avec ses photos dans l'ordre, et « Produit publié » s'affiche.
- [x] Étant donné « Brouillon » à l'étape 2, alors le produit est créé non visible, apparaît dans
      « Brouillons », et un appui le rouvre prérempli ; le publier le fait passer « En vente ».
- [x] Étant donné un produit sans photo, alors « Voir l'aperçu » et « Remettre » sont refusés avec
      « Ajoutez au moins une photo. » ; un brouillon sans photo peut être enregistré.
- [x] Étant donné un produit en vente, quand le marchand le retire et confirme, alors il passe dans
      « Retirés » avec la date du jour ; « Annuler » dans le message le remet en vente.
- [x] Étant donné un produit retiré, quand le marchand appuie sur « Remettre », alors il repasse
      « En vente » et « Visible depuis » prend la date du jour.
- [x] Étant donné un produit à stock suivi, quand le marchand ajuste la quantité, alors le serveur
      l'enregistre (journal de stock) et la ligne l'affiche ; à 0, la ligne affiche « Épuisé · à
      réapprovisionner ».
- [x] Étant donné une modification du prix, du nom, de la catégorie ou des photos, quand le marchand
      enregistre, alors le serveur renvoie le produit modifié et le catalogue l'affiche.
- [x] Côté serveur : un produit créé avec `is_active: false` est un brouillon (`status: draft`) ;
      publié, il est `active` avec `published_at` ; désactivé, il est `withdrawn` avec
      `withdrawn_at` ; un brouillon modifié reste un brouillon.
- [x] Côté serveur : la liste du marchand accepte `status` et `q` ; les compteurs par état ne
      comptent que les produits de la boutique demandée ; la boutique d'un autre marchand répond
      404 (liste comme compteurs).

## Cas limites et erreurs

- **Nom** de 2 à 150 caractères, **prix** de 1 à 100 000 000 FCFA, **description** de 500
  caractères au plus, **catégorie** obligatoire : messages sous les champs, l'étape 1 ne se valide
  pas.
- **Prix saisi** avec espaces ou points (« 4 500 », « 4.500 ») : lu comme 4500. Lettres refusées
  par le clavier numérique.
- **Quantité** de 0 à 1 000 000 ; vide = 0.
- **Photo trop lourde** après compression (> 5 Mo) ou illisible : message sur la photo, les autres
  restent.
- **Échec d'envoi d'une photo ou du produit** (réseau) : message, rien n'est perdu ; un nouvel essai
  ne renvoie pas les photos déjà envoyées.
- **Double appui** sur « Publier » ou « Brouillon » : un seul produit créé.
- **Catégorie désactivée** par l'admin entre-temps : le serveur refuse ; message sous « Catégorie »
  pour en choisir une autre.
- **Quitter le formulaire** avec des changements : « Abandonner ce produit ? » (Abandonner /
  Continuer).
- **Liste vide** :
  - « Aucun produit en vente. Ajoutez votre premier produit. » avec un bouton ;
  - « Aucun brouillon. » ;
  - « Aucun produit retiré. » ;
  - recherche sans résultat : « Aucun produit ne correspond à « … ». »
- **Réseau coupé** au chargement du catalogue : message et « Réessayer », sans quitter l'écran.
- **Boutique suspendue** pendant l'utilisation : le serveur refuse ; l'app relit la boutique et
  affiche l'écran « suspendue ».
- **Produit d'un autre marchand** (lien forgé) : 404 du serveur, « Produit introuvable ».
- **Retrait avec des commandes payées en cours** : les commandes restent à préparer (le serveur ne
  les touche pas).
- **Police à 200 %, écran de 320 dp** : rien n'est masqué, les écrans défilent, les noms longs
  passent à la ligne ou sont tronqués avec « … » dans les listes.

## Hors périmètre

- Journal des mouvements de stock (route existante) et alertes de réapprovisionnement : 006.
- Suppression d'un brouillon (aucune route de suppression ; un brouillon reste non visible).
- Changement du mode de stock après la création.
- Photo obligatoire côté serveur : l'app l'exige pour publier, le serveur l'accepte encore sans
  (données de démonstration).
- Commandes (011), accueil marchand définitif, profil complet du compte (002).
- Fiche produit et recherche côté acheteur (007).
- Variantes (taille, couleur), promotions, import en masse.
- Bornes du serveur plus larges que celles de l'app : 6 photos et 5 000 caractères de
  description acceptés par l'API (back-office, appels directs) ; l'app en montre 5 et 500. Un
  produit qui les dépasse s'affiche, mais l'app refuse de l'enregistrer tel quel.
- Création rejouée après une coupure réseau en fin de requête (le serveur a créé le produit, la
  réponse s'est perdue) : un second produit peut être créé au nouvel essai. Une clé
  d'idempotence sur `POST /v1/seller/shops/{id}/products` est à prévoir (voir `TASKS.md`).

## Questions ouvertes

<!-- Vide = prêt pour le plan. -->
