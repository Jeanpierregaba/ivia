# 004 — Espace marchand : lancement, connexion, création de la boutique

## Objectif

Permettre à un commerçant d'ouvrir l'app marchand, de comprendre ce qu'elle apporte, de se connecter
avec le même compte ivia que dans l'app acheteur, puis de créer sa boutique et de suivre sa
validation par l'équipe ivia ([PRD](../../PRD.md), parcours 4 « Ouverture d'une boutique »).

Maquettes du 2026-10-31 : elles guident l'écran mais ne le figent pas. Ce lot reprend pour le
marchand ce que [027](../027-splash-onboarding/spec.md) et [001](../001-connexion-otp/spec.md) font
pour l'acheteur.

## Comportement attendu

**Couleurs de l'app marchand** : action principale (boutons, liens, champ actif, indicateur) en
Berkeley Blue ; partie colorée des titres en Cobalt Blue. L'acheteur garde Imperial Red.

**1. Splash de chargement** : fond Berkeley, logotype dans la tuile blanche à la place exacte du
splash natif, « Marchand » en dessous, puis « Vendez dans votre quartier. », trois points animés,
au moins 800 ms.

**2. Présentation** (premier lancement), en-tête « [logo] Marchand » sur la page 1 :

| Page | Illustration | Titre (partie colorée) | Texte |
|---|---|---|---|
| 1 | Carte Berkeley : fiche de la boutique « Chez Afi · Alimentation · Tokoin · Publiée », trois produits (prix, stock), pastille « Produit ajouté » | Votre boutique en ligne, **sans site web.** | Ajoutez vos produits en photo, avec le prix et le stock. Les acheteurs du quartier vous trouvent. |
| 2 | Carte Berkeley : « Commande payée », compte à rebours, « #1042 · 3 articles · 16 500 F », Refuser / Accepter, pastille « Paiement reçu · Flooz » | Des commandes **déjà payées.** | Le client paie par Mobile Money avant que vous ne prépariez. Vous avez 15 minutes pour accepter. |
| 3 | Mosaïque : « Livraison · Un livreur ivia passe » (Cobalt), « Retrait · Le client vient en boutique » (blanc), « Saisir le code du client » (Berkeley) | La remise, **en toute sécurité.** | Livraison par un livreur ivia ou retrait en boutique : le code à 4 chiffres du client confirme la remise. |

**3. « Espace marchand »** : logo, pastille « Marchand », « Connectez-vous avec votre e-mail. Vous
avez déjà un compte ivia ? Utilisez le même. », puis comme l'acheteur (e-mail, « Recevoir le code »,
WhatsApp « bientôt », mentions légales).

**4. « Vérifiez vos e-mails »** : comme l'acheteur ; l'encart dit « Même compte sur toutes les apps
ivia : utilisez l'e-mail de votre compte acheteur si vous en avez un. »

**5. « Créez votre boutique »** (aucune boutique encore) : logo de la boutique (photo carrée,
facultatif), nom, catégorie (liste), téléphone de la boutique (+228, prérempli avec le numéro du
profil s'il existe), adresse, quartier (liste), position sur la carte (épingle à déplacer, bouton
« Ma position »), case de consentement si le compte ne l'a pas encore donné, bouton « Envoyer pour
validation ». Le retour déconnecte.

**6. « Votre boutique est en cours de validation »** : étapes Compte créé ✓ · Boutique envoyée ✓
(nom · quartier) · Validation par ivia (en cours) · Boutique visible des acheteurs ; bouton
« Préparer mes produits » (écran provisoire jusqu'à 005). L'écran se met à jour à l'ouverture de
l'app et en tirant vers le bas.

**Après validation** (boutique publiée) : accueil provisoire du marchand. Boutique refusée ou
suspendue : écran d'information avec le motif donné par l'admin.

## Critères d'acceptation

- [ ] Étant donné l'app marchand, au lancement, alors le splash de chargement affiche la tuile, « Marchand »
      et le slogan sans saut par rapport au splash natif, au moins 800 ms.
- [ ] Les boutons, liens et champs actifs de l'app marchand sont en Berkeley ; ceux de l'acheteur
      restent en Imperial.
- [ ] Étant donné un compte sans boutique, après connexion, alors « Créez votre boutique » s'ouvre.
- [ ] Étant donné le formulaire rempli (nom, catégorie, téléphone, adresse, position, consentement),
      quand le marchand envoie, alors le consentement puis la boutique sont envoyés au serveur et
      l'écran « en cours de validation » s'ouvre avec le nom et le quartier.
- [ ] Étant donné un logo choisi, alors il est redimensionné (1024 px au plus) et débarrassé de ses
      métadonnées (position GPS comprise) avant l'envoi, puis transmis par URL signée.
- [ ] Étant donné « Ma position », quand le marchand l'autorise, alors l'épingle se place sur sa
      position ; s'il refuse, il peut toujours placer l'épingle à la main.
- [ ] Étant donné une boutique en attente, quand l'app est relancée, alors l'écran de validation
      s'ouvre ; une fois la boutique publiée, l'accueil marchand s'ouvre.
- [ ] Étant donné un compte acheteur existant (même e-mail), alors le marchand retrouve son compte
      (même session, pas de nouvelle inscription) et son téléphone préremplit celui de la boutique.

## Cas limites et erreurs

- **Nom** de 2 à 100 caractères, **adresse** de 1 à 300 : messages sous les champs.
- **Téléphone** non togolais : message (règle du serveur).
- **Position absente** : « Placez votre boutique sur la carte. » ; aucun envoi.
- **Localisation refusée ou désactivée** : message et épingle à la main ; jamais de blocage.
- **Logo trop lourd après compression** (> 5 Mo) ou format non pris en charge : message, la boutique
  peut être envoyée sans logo.
- **Échec de l'envoi du logo** (réseau) : message ; nouvel essai possible.
- **Réseau coupé** à l'envoi : message, rien n'est perdu dans le formulaire.
- **Double appui** sur « Envoyer pour validation » : une seule boutique créée.
- **Carte indisponible** (pas de clé Google Maps en développement) : aperçu sans fond de carte avec
  l'épingle et « Ma position ». Sans carte, un marchand qui refuse la localisation ne peut pas
  placer sa boutique : la carte est donc **exigée en release** (l'app refuse de démarrer sans
  `GOOGLE_MAPS=true`).
- **Police à 200 %, écran de 320 dp** : rien n'est masqué, les écrans défilent.

## Hors périmètre

- Produits et stock (005, 006) : « Préparer mes produits » ouvre un écran provisoire.
- Commandes marchand (011), notifications push de validation (012).
- Plusieurs boutiques par marchand (l'API le permet ; l'app gère la première).
- Géocodage inverse (épingle → adresse) et recherche d'adresse : `GeoService` du backend décrit
  dans `architecture-feat-map.md`, à décider par ADR. L'adresse est saisie à la main.
- Gestion des catégories de boutique dans le back-office (liste de départ fixée par migration).
- App livreur.

## Questions ouvertes

<!-- Vide = prêt pour le plan. -->
