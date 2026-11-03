# 011 — Commandes du marchand : acceptation, préparation, remise par code

## Objectif

Permettre au marchand de **recevoir les commandes payées**, de les **accepter ou refuser sous
15 minutes**, de les passer **« en préparation » puis « prête »**, et de **remettre** une commande
à retirer contre le **code de remise** de l'acheteur ([PRD](../../PRD.md), fonctionnalités
marchand : « Réception des commandes payées, acceptation ou refus sous 15 minutes… », « Passage des
commandes à en préparation puis prête ; remise… contrôlée par le code de remise (5 essais au
maximum, puis intervention de l'admin) »).

C'est la moitié marchand du parcours 2 (retrait), dont la moitié acheteur est faite
([009](../009-commande-retrait/spec.md), [010](../010-paiement/spec.md)). Le backend `orders`
existe : seule l'app marchand change. Remplace les écrans provisoires des onglets **Accueil** et
**Commandes**.

Hors 011 : les notifications push (012 : en attendant, l'app relit les commandes), la remise au
livreur et le retour d'un colis non livré (021, 022), les relevés (023).

## Comportement attendu

**1. Arrivée des commandes**
- Tant que l'app est ouverte au premier plan (boutique publiée), les **nouvelles commandes**
  sont relues **toutes les 30 s** (une commande nouvelle qui n'y figure plus est relue seule) ;
  la liste complète est relue au retour dans l'app, à l'ouverture de l'onglet Commandes et en
  tirant vers le bas. Rien n'est relu en arrière-plan.
- L'onglet **Commandes** de la barre du bas porte une **pastille** avec le nombre de nouvelles
  commandes (à accepter) ; rien quand il n'y en a pas. Le lecteur d'écran lit « Commandes,
  2 nouvelles ».

**2. Accueil** (onglet Accueil, remplace l'écran provisoire)
- Logo, nom de la boutique.
- Carte **« 2 nouvelles commandes à accepter »** avec le temps restant de la plus urgente
  (« La première expire dans 12:40 », lu « 13 min ») ; un appui ouvre l'onglet Commandes sur
  « Nouvelles ». Une seule : « 1 nouvelle commande à accepter », « Elle expire dans 12:40 ».
- Carte **« 3 commandes en cours »** (acceptées, en préparation, prêtes) ; un appui ouvre
  « En cours ».
- Rien à faire : « Aucune commande à traiter. Les nouvelles commandes arrivent ici. »
- Bouton « Mes produits » (comme aujourd'hui).

**3. Onglet Commandes**
- Titre « Commandes », onglets **« Nouvelles · 2 »**, **« En cours · 3 »**, **« Terminées »**
  (`IviaSegmentedTabs`).
- Une ligne par commande : « #1042 », prénom de l'acheteur (« Koffi »), « Retrait · 3 articles »
  (ou « Livraison · … »), montant des produits, pastille de statut (icône + libellé, voir
  « Libellés côté marchand »).
- **Nouvelles** : les plus anciennes d'abord (la plus urgente en haut), chacune avec son **compte à
  rebours** (« 12:40 » qui défile, en couleur `warning`, puis `error` sous 3 min).
- **En cours** et **Terminées** : les plus récentes d'abord ; « Terminées » montre aussi l'heure ou
  la date (« Aujourd'hui 14:05 », « 24 oct. »).
- Vide : « Aucune nouvelle commande. », « Aucune commande en cours. », « Aucune commande
  terminée. »
- Tirer vers le bas actualise. Un appui ouvre le détail.

**4. Détail d'une commande** (« Commande #1042 »)
- En-tête : pastille de statut, « Pour Koffi », mode (« Retrait en boutique » ou « Livraison »),
  heure du paiement (heure de Lomé).
- **Nouvelle commande** : compte à rebours en grand (« Il vous reste 12:40 pour répondre ») ;
  sous le délai : « Sans réponse, la commande est annulée et l'acheteur remboursé. »
- Articles : quantité × nom, prix, total de la ligne. Un produit à **stock non suivi** porte
  « Vérifiez que vous l'avez » : accepter vaut confirmation de sa disponibilité.
- Montants : « Produits », « Commission ivia », **« Vous recevez »** (montant net). Jamais le
  numéro ni l'adresse de l'acheteur.
- **Actions selon le statut** (bouton principal pleine largeur en bas) :
  - nouvelle : **« Accepter la commande »** et **« Refuser »** (bouton secondaire) ;
  - acceptée : **« Commencer la préparation »** ;
  - en préparation : **« Commande prête »** ; retrait : « L'acheteur sera prévenu qu'il peut
    venir » ; livraison : « Un livreur sera recherché » ;
  - prête à retirer : **« Saisir le code de l'acheteur »** ;
  - livraison au-delà de « prête » (recherche d'un livreur, livreur en route, en livraison…) :
    statut seul, aucune action (021, 022).
  - terminée : aucune action ; une commande annulée affiche son motif.
- Le détail est relu toutes les 30 s et au retour dans l'app ; tirer vers le bas actualise.

**5. Refus**
- « Refuser » ouvre une feuille **« Pourquoi refusez-vous ? »** : « Produit en rupture »,
  « Boutique fermée », « Impossible de préparer à temps », « Autre » (champ texte, 200 caractères
  au plus, obligatoire si « Autre »).
- « L'acheteur verra ce motif et sera remboursé. » Bouton **« Refuser la commande »**, actif une fois
  un motif choisi (et le texte saisi pour « Autre »).
- Après le refus : la commande passe dans « Terminées », « Annulée » avec le motif.

**6. Remise par code** (retrait)
- « Saisir le code de l'acheteur » ouvre **« Code de remise »** : « Demandez à Koffi son code à
  4 chiffres. », 4 cases (clavier numérique, collage accepté), **« Remettre la commande »**.
- Code juste : « Commande remise. » ; la commande passe en « Retirée » dans « Terminées ».
- Code faux : message du serveur (« Code incorrect. Il reste 3 essai(s). »), cases vidées.
- Après 5 essais faux, ou si le code est déjà bloqué : « Trop d'essais : le code est bloqué.
  Contactez l'équipe ivia. » ; plus de saisie possible (le détail l'indique à la place du bouton).
- Le code n'est jamais gardé ni journalisé par l'app.

**Libellés côté marchand** (le reste comme [DESIGN](../../DESIGN.md#libellés-des-statuts)) :
`awaiting_seller` « Nouvelle » (warning), `accepted` « Acceptée » (info), `completed` « Retirée »
(success), `cancelled` « Annulée » (error).

## Critères d'acceptation

- [x] Étant donné l'app ouverte sur n'importe quel onglet, quand une commande payée arrive, alors
      elle apparaît au plus tard 30 s après dans « Nouvelles » et la pastille de l'onglet
      Commandes passe à 1 ; app en arrière-plan, aucune requête ; au retour, relue aussitôt.
- [x] Étant donné 2 nouvelles commandes et 1 en cours, l'Accueil affiche « 2 nouvelles commandes à
      accepter » avec le temps restant de la plus urgente et « 1 commande en cours » ; un appui
      ouvre l'onglet Commandes sur le bon sous-onglet. Sans commande : « Aucune commande à
      traiter. »
- [x] L'onglet Commandes répartit les commandes : Nouvelles (`awaiting_seller`, plus anciennes
      d'abord), En cours (acceptée à « en cours de livraison »), Terminées (le reste) ; nombres sur
      les onglets ; textes vides.
- [x] Une nouvelle commande affiche un compte à rebours jusqu'à `seller_deadline_at` (liste et
      détail), en `error` sous 3 min ; à 0 : « Délai dépassé », plus d'acceptation possible, et la
      commande est relue.
- [x] « Accepter la commande » envoie `POST /v1/seller/orders/{id}/accept` une seule fois (double
      appui) ; la commande passe dans « En cours » avec « Commencer la préparation ».
- [x] « Commencer la préparation » puis « Commande prête » envoient `preparing` puis `ready` ; une
      commande en retrait finit « Prête à retirer » avec « Saisir le code de l'acheteur » ; une
      commande à livrer finit « Recherche d'un livreur » sans action.
- [x] Refus : motif obligatoire (« Autre » exige un texte de 1 à 200 caractères) ; le motif choisi
      est envoyé dans `reason` ; la commande passe en « Annulée » avec ce motif.
- [x] Remise : code de 4 chiffres envoyé à `handover` ; juste ⇒ « Retirée » ; faux ⇒ message du
      serveur avec les essais restants, cases vidées ; `handover_locked` ⇒ saisie fermée et
      message ; un détail avec `handover_attempts` à 5 n'offre plus la saisie.
- [x] Le détail montre articles, mention « Vérifiez que vous l'avez » sur un produit à stock non
      suivi, produits, commission et « Vous recevez » (net) ; jamais de numéro ni d'adresse.
- [x] Une action refusée parce que la commande a changé (`invalid_transition`, ou 404) affiche le
      message du serveur et relit la commande : l'écran montre son vrai statut.
- [x] Police à 200 % sur 320 dp : listes, détail, feuille de refus et saisie du code sans
      débordement ; lecteur d'écran : statut et compte à rebours lus en texte.

## Cas limites et erreurs

- **Délai dépassé pendant que l'écran est ouvert** : le compte à rebours atteint 0 ⇒ boutons
  d'acceptation désactivés, commande relue ; le serveur l'a annulée (« Le marchand n'a pas répondu
  à temps. ») ou va le faire. Horloge du téléphone décalée : le serveur tranche ; un refus
  `invalid_transition` relit la commande.
- **Acceptation à la dernière seconde** : la requête part, le serveur répond ; s'il a déjà annulé,
  message et commande relue.
- **Acheteur qui annule avant l'acceptation** (013, côté acheteur) : la commande quitte
  « Nouvelles » à la relecture suivante ; une action dessus ⇒ message, commande relue.
- **Réseau coupé** pendant une action : « Pas de connexion. Réessayez. », rien n'est changé à
  l'écran ; un nouvel essai renvoie la même action (le serveur refuse une action déjà faite :
  relecture). Pendant la relecture automatique : l'écran garde les dernières données, sans
  message bloquant.
- **Double appui** sur une action : une seule requête (bouton désactivé pendant l'envoi).
- **Code de remise** : moins de 4 chiffres ⇒ bouton désactivé ; autre chose que des chiffres
  refusé à la saisie ; code collé avec espaces ⇒ chiffres seuls gardés.
- **Boutique suspendue** pendant l'utilisation : le serveur répond 403 `shop_suspended` sur ses
  commandes ⇒ l'app relit la boutique et suit le comportement existant (écran « boutique
  suspendue »).
- **Plusieurs boutiques** : l'app gère une boutique ; la liste est demandée pour cette boutique
  (`shop_id`).
- **Beaucoup de commandes** : « Nouvelles » est toujours complète (filtre `awaiting_seller`) ;
  « Terminées » montre les plus récentes (pagination : voir le plan).
- **Commande d'une autre boutique** (lien forgé, ancienne donnée) : 404 ⇒ « Commande
  introuvable. » et retour à la liste.

## Hors périmètre

- Notifications push et liste des notifications (012) : son ou vibration à l'arrivée d'une
  commande inclus.
- Remise au livreur, confirmation du retour d'un colis (`confirm-return`), informations du livreur
  (`/delivery`) : 021 et 022.
- Annulation par le marchand après acceptation (seul l'admin peut annuler, PRD).
- Relevés et chiffre d'affaires sur l'Accueil (023).
- Impression, export, recherche dans les commandes.

## Questions ouvertes

Aucune (tranchées le 2026-11-02 : relecture toutes les 30 s avec pastille, allégée le 2026-11-03
aux nouvelles commandes après relecture ; étapes communes aux
deux modes, rien après « prête » pour la livraison ; refus avec motifs proposés + « Autre » ;
Accueil avec résumé simple).
