# 011 — Plan technique

## Approche

- **Aucun changement serveur.** Routes existantes et testées (module `orders`, rôle `seller`,
  propriété vérifiée par le service, boutique suspendue ⇒ 403 `shop_suspended`) :
  - `GET /v1/seller/orders?shop_id&status&limit&offset` (plus récentes d'abord, commandes payées
    seulement, `limit` ≤ 100, `next_offset`) et `GET /v1/seller/orders/{id}` → `SellerOrder` ;
  - `POST …/{id}/accept`, `…/reject` `{reason}`, `…/preparing`, `…/ready`, `…/handover` `{code}` →
    `SellerOrder` à jour ; refus d'un changement impossible : 409 `invalid_transition` ;
    remise : 422 `handover_code_invalid` (message avec les essais restants), 409
    `handover_locked`.
  - `SellerOrder` : statut, mode, montants (`subtotal_xof`, `commission_xof`, `net_xof`),
    `buyer_first_name`, `seller_deadline_at`, `paid_at`, `cancel_reason`, `handover_attempts`,
    articles (avec `stock_mode`), `updated_at`. Jamais de numéro ni d'adresse.
- **Une seule liste relue, partagée** : `sellerOrdersProvider` (AsyncNotifier) lit
  `GET /v1/seller/orders?shop_id=<boutique>&limit=100` et répartit dans l'app :
  - Nouvelles : `awaiting_seller`, triées par `seller_deadline_at` croissant ;
  - En cours : `accepted`, `preparing`, `ready_for_pickup`, `awaiting_driver`,
    `driver_assigned`, `picked_up` (et `unknown`) ;
  - Terminées : le reste, plus récentes d'abord, puis « Afficher plus » (`next_offset`).
  Une nouvelle commande ne vit que 15 min : elle est toujours parmi les 100 dernières. Une
  commande en cours plus ancienne que les 100 dernières manquerait : limite notée pour le
  backend (filtre par groupe de statuts), comme pour l'acheteur en 009.
- **Relecture toutes les 30 s** : portée par le cadre des onglets (`SellerShell`, boutique
  publiée) avec un `Timer.periodic` et un `AppLifecycleListener` (arrêt à `onHide`, relecture
  immédiate puis reprise à `onShow`). Le cadre reste monté sur tous les onglets et sous le
  détail : une seule source pour la pastille, l'Accueil et la liste. Erreur pendant une relecture
  automatique : dernières données gardées, sans message.
- **Détail** : `sellerOrderProvider(id)` (famille) lit `GET …/{id}`, relu toutes les 30 s tant
  que le détail est au premier plan, et au retour dans l'app. Chaque action remplace la commande
  dans le détail **et** dans la liste (`sellerOrdersProvider.replace(order)`). Une réponse plus
  ancienne que la version affichée (`updated_at`) ne la remplace pas : une relecture partie avant
  une action ne la défait pas.
- **Compte à rebours** : `IviaCountdown` (nouveau, `packages/ui`) : texte « mm:ss » relu chaque
  seconde à partir d'une heure limite et d'une horloge passée en paramètre ; l'app lui donne
  `client.now()` (heure du serveur estimée, déjà utilisée pour le délai de paiement). Ton
  `warning`, puis `error` sous 3 min ; à 0, rappel `onExpired` : boutons d'acceptation
  désactivés, commande relue.
- **Pastille de l'onglet** : `IviaNavItem.badge` (nouveau, `int?`) : petit rond Imperial avec le
  nombre (« 9+ » au-delà), libellé lu « Commandes, 2 nouvelles ».
- **Libellés partagés** : `statusTone`, `statusIcon`, `fulfillmentLabel`, `articles` passent de
  l'app acheteur à `packages/app_core` (`order_labels.dart`) ; chaque app garde son
  `statusLabel` (côté marchand : « Nouvelle », « Acceptée », « Retirée », « Annulée » ; le reste
  comme DESIGN).
- **Actions** : dans l'écran du détail (`_run`) et de la remise (`_submit`) ; les fournisseurs
  sont lus avant l'envoi, pour que le résultat soit reporté dans la liste même si l'écran est
  quitté pendant la requête. Erreurs affichées au-dessus du bouton :
  - réseau : « Pas de connexion. Réessayez. », rien ne change ;
  - `invalid_transition`, `order_not_found` : message du serveur, commande relue (404 : retour à
    la liste avec « Commande introuvable. ») ;
  - `shop_suspended`, `shop_not_found` : `sellerShopProvider.refresh()` (le routeur ouvre l'écran
    « suspendue », comme le catalogue) ;
  - remise : `handover_code_invalid` ⇒ message, cases vidées ; `handover_locked` ⇒ saisie fermée.
  Bouton désactivé pendant l'envoi (`AsyncButton` / état `busy`) : une seule requête.
- **Refus** : feuille modale avec quatre choix (`RadioGroup`) et un champ « Autre » (200
  caractères, `maxLength`) ; le texte envoyé est le libellé du motif, ou le texte saisi.
- **Remise** : écran plein « Code de remise » (`/orders/:id/handover`) avec `IviaCodeInput(length:
  4)` (chiffres seuls, collage nettoyé déjà gérés) ; le code n'est gardé que dans le contrôleur
  du champ, vidé après chaque essai et à la fermeture.

## Fichiers touchés

**`packages/api_client`**
- `lib/src/models.dart` : `SellerOrder` (`fromJson`, `articleCount`, `isHandoverLocked`
  quand `handover_attempts` ≥ 5) ; `OrderItem.stockMode` (`StockMode?`, lu dans `stock_mode`).
- `lib/src/client.dart` : `sellerOrders({shopId, status, offset, limit})` → `Page<SellerOrder>`,
  `sellerOrder(id)`, `acceptOrder(id)`, `rejectOrder(id, reason)`, `startPreparingOrder(id)`,
  `markOrderReady(id)`, `handOverOrder(id, code)`.
- `lib/testing.dart` : `FakeSellerOrders(server)` fidèle au module `orders` côté marchand :
  transitions permises (sinon 409 `invalid_transition` avec le libellé du serveur), délai de
  15 min (`now` réglable ; passé, la commande devient `cancelled` « Le marchand n'a pas répondu à
  temps. » à la lecture suivante), 5 essais de code comptés avant comparaison,
  `handover_locked`, `shop_id` et `status` filtrés, pagination, `failures`, `beforeRequest`,
  `sellerOrderBody(...)` ; requêtes enregistrées pour les tests.
- `test/client_test.dart` : modèles et routes.

**`packages/ui`**
- `lib/src/navigation.dart` : `IviaNavItem.badge`.
- `lib/src/countdown.dart` (nouveau) : `IviaCountdown`.
- tests associés.

**`packages/app_core`**
- `lib/src/order_labels.dart` (nouveau, déplacé de l'app acheteur) : tons, icônes, mode,
  « N articles ».

**App acheteur**
- `lib/features/orders/order_labels.dart` : importe les parties communes (comportement
  inchangé, tests existants verts).

**App marchand**
- `lib/features/orders/` (remplace `orders_placeholder_screen.dart`, supprimé) :
  - `order_labels.dart` : `statusLabel` marchand, groupes Nouvelles / En cours / Terminées ;
  - `orders_providers.dart` : `sellerOrdersProvider`, `sellerOrderProvider(id)` ;
  - `orders_screen.dart` : onglets, lignes, vides, tirer pour actualiser, « Afficher plus » ;
  - `order_screen.dart` : détail, actions selon le statut, relecture ;
  - `reject_sheet.dart` : motifs ;
  - `handover_screen.dart` : saisie du code.
- `lib/features/home/home_screen.dart` (remplace `home_placeholder_screen.dart`) : cartes
  « nouvelles » et « en cours ».
- `lib/features/shell/seller_shell.dart` : relecture toutes les 30 s, pastille.
- `lib/app/router.dart` : `/orders?tab=new|active|done`, `/orders/:id`,
  `/orders/:id/handover`.
- `test/app_test.dart` (ou `test/orders_test.dart`) : parcours et cas limites.

**Docs**
- `docs/DESIGN.md` : Accueil marchand, Commandes, Détail, Refus, Code de remise, libellés
  côté marchand, `IviaCountdown`, pastille d'onglet.
- `TASKS.md` : 011 en cours ; points backend pour Gedeon (longueur maximale du motif de refus,
  filtre par groupe de statuts sur `GET /v1/seller/orders`).

## Données

Aucune : pas de migration, rien de stocké sur le téléphone (ni code de remise, ni commande).

## API / interfaces

Aucune route nouvelle ni modifiée : `openapi.yaml` inchangé.

## Dépendances

Aucune nouvelle bibliothèque (Riverpod, go_router, dio déjà présents ; `RadioGroup` et
`AppLifecycleListener` sont dans Flutter).

## Sécurité

- Contrôle d'accès entièrement côté serveur (rôle `seller`, propriété de la boutique, commandes
  payées seulement) ; l'app n'affiche que ce qu'il renvoie.
- Code de remise : jamais stocké, journalisé, ni mis dans une URL ; champ vidé après chaque
  essai ; 5 essais imposés par le serveur.
- Aucune donnée de l'acheteur au-delà du prénom (le serveur n'envoie ni numéro ni adresse).
- Motif de refus : texte nettoyé par le serveur (`validate.Clean`), limité à 200 caractères dans
  l'app (pas de limite serveur : point backend).
- Relecture toutes les 30 s seulement au premier plan : pas de trafic en arrière-plan.

## Tests

Pas de partie critique côté app (la machine à états est testée au backend) ; le faux serveur la
reproduit fidèlement pour que les tests d'écran ne puissent pas valider un enchaînement
impossible.

- `api_client` : `SellerOrder.fromJson` (champs, `stock_mode`, dates nulles, statut inconnu) ;
  chaque route (méthode, chemin, corps) ; erreurs traduites.
- `ui` : `IviaCountdown` (défilement, ton sous 3 min, `onExpired` une seule fois, horloge
  injectée), pastille d'onglet (affichage, « 9+ », libellé lu).
- App marchand (faux serveur) :
  - relecture : nouvelle commande visible après 30 s (`tester.pump(30 s)`), pastille ; app en
    arrière-plan ⇒ aucune requête ; au retour, relue ;
  - Accueil : résumé, singulier / pluriel, vide, navigation vers le bon onglet ;
  - liste : répartition, ordres, compteurs, vides, « Afficher plus », tirer pour actualiser ;
  - parcours retrait complet : accepter → préparer → prête → code faux (essais restants) → code
    juste ⇒ « Retirée » ;
  - livraison : prête ⇒ « Recherche d'un livreur », aucune action ;
  - refus : motif obligatoire, « Autre » vide refusé, 200 caractères, `reason` envoyé ;
  - délai : compte à rebours, à 0 boutons désactivés et commande relue ;
  - concurrence : action sur une commande annulée entre-temps ⇒ message et vrai statut ;
    relecture lente partie avant une action ne la défait pas ;
  - réseau coupé, double appui, `handover_locked`, 404, `shop_suspended` ;
  - stock non suivi : mention ; montants ; aucune donnée sensible affichée ;
  - police à 200 % sur 320 dp et lecteur d'écran.
- App acheteur : suite existante inchangée (libellés déplacés).
- Vérification sur le simulateur iPhone 17 Pro contre l'API locale (commande passée avec l'app
  acheteur et le faux paiement, puis traitée dans l'app marchand jusqu'à « Retirée »).

## Risques

- **Délai de 15 min et horloge du téléphone** : compte à rebours sur l'heure estimée du serveur ;
  le serveur tranche toujours, l'app relit sur refus.
- **Liste limitée aux 100 dernières commandes** : suffisant au lancement ; point backend noté.
- **Deux relectures simultanées** (liste et détail) : 2 requêtes toutes les 30 s pendant que le
  détail est ouvert ; acceptable, à revoir avec le push (012) qui permettra d'espacer.
- **Pas de push** : un marchand app fermée ne voit rien ; la 012 couvrira ce cas (spec,
  hors périmètre).
