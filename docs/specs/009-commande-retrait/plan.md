# 009 — Plan technique

## Approche

- **Aucun changement serveur.** Routes existantes et testées (module `orders`) :
  - `POST /v1/orders/quote` `{fulfillment: "pickup"}` → récapitulatif (lignes, sous-total, total,
    `payment_timeout_minutes`) ;
  - `POST /v1/orders` `{fulfillment, client_request_id}` → commande créée en `pending_payment`
    (stock réservé, panier vidé, expiration planifiée) ; idempotente par `client_request_id` ;
  - `GET /v1/orders?limit&offset` (plus récentes d'abord) et `GET /v1/orders/{id}` →
    `BuyerOrder` : statut, totaux, dates, articles, historique (`events`), boutique,
    `handover_code` (donné par le serveur seulement entre le paiement et le retrait).
- **Idempotence de « Payer »** : l'écran Commande tire un identifiant (UUID v4, `Random.secure`)
  à l'ouverture et le renvoie à chaque essai ; il n'en change qu'à une nouvelle ouverture.
- **Commandes en cours / terminées** : séparées dans l'app selon le statut (la route n'a pas de
  filtre) ; une page de 50 commandes, puis « Afficher plus » dans « Terminées ». Statuts en cours
  : `pending_payment`, `awaiting_seller`, `accepted`, `preparing`, `ready_for_pickup` (et ceux de
  la livraison, déjà prévus) ; terminés : `completed`, `delivered`, `expired`, `cancelled`,
  `refunded`, `returned_to_shop`, `delivery_failed`.
- **Suivi** : `orderProvider(id)` relu toutes les 20 s par un minuteur tant que le suivi est
  affiché et la commande en cours, et au retour au premier plan (`AppLifecycleListener`) ;
  arrêté sur un statut terminé. La liste est relue à l'ouverture de l'onglet, au retour d'un
  suivi, au changement de compte et en tirant vers le bas.
- **Frise** : construite à partir de `events` (heure de chaque `to_status`) ; pour un retrait,
  étapes à venir connues (`awaiting_seller` → `accepted` → `preparing` → `ready_for_pickup` →
  `completed`) affichées en gris. Heures en `HH:mm` (Lomé = UTC).

## Fichiers touchés

**`packages/api_client`**
- `models.dart` : `OrderStatus` (codes, `isActive`, `showsHandoverCode`), `Fulfillment`,
  `OrderQuote`, `OrderItem`, `OrderEvent`, `BuyerOrder` (dont `shop`, `handoverCode`,
  `paymentDeadlineAt`, `cancelReason`, `number`).
- `client.dart` : `quoteOrder()`, `createOrder({clientRequestId})`, `myOrders()`, `myOrder(id)`.
- `ids.dart` (créé) : `newRequestId()` (UUID v4 aléatoire, sans dépendance).
- `testing.dart` : `FakeOrders`, branché sur `FakeCart` : récapitulatif, création (réservation du
  stock suivi, panier vidé, idempotence, refus `cart_empty`, `shop_closed`,
  `insufficient_stock`, `product_unavailable`, `rate_limited`), liste paginée, détail, code
  donné selon le statut ; `advance(order, status)` pour faire avancer une commande dans un test.

**`packages/ui`**
- `IviaHandoverCode` : 4 cases blanches sur fond de couleur, chiffres lus un à un.
- `IviaTimeline` : étapes (titre, sous-titre, heure), passées / actuelle / à venir.

**`packages/app_core`**
- `formats.dart` : `timeOfDay` (« 14:32 », heure de Lomé).

**`apps/buyer`**
- `features/checkout/checkout_screen.dart` : modes, boutique, récapitulatif, « Payer ».
- `features/orders/`
  - `order_labels.dart` : libellés, tons et icônes des statuts (DESIGN), titres de la frise ;
  - `orders_providers.dart` : `myOrdersProvider` (relu au changement de compte),
    `orderProvider(id)` ;
  - `orders_screen.dart` (remplace `orders_placeholder_screen.dart`) : onglets, lignes,
    « Récemment » ;
  - `order_screen.dart` : en-tête, code, boutique, frise, articles, relecture toutes les 20 s.
- `app/router.dart` : `/checkout` et `/orders/:id` sur le navigateur racine.
- `features/cart/cart_screen.dart` : « Commander » ouvre `/checkout`.

**Docs** : `DESIGN.md` (écran Commande, Commandes, suivi), `TASKS.md`.

## Données

Aucune migration ; rien de nouveau sur le téléphone (commandes relues sur le serveur).

## API / interfaces

Voir Approche. Codes d'erreur traités : `cart_empty`, `shop_unavailable`, `shop_closed`,
`product_unavailable`, `insufficient_stock`, `profile_incomplete`, `rate_limited`,
`order_not_found` (404).

## Dépendances

Aucune. L'UUID est tiré avec `Random.secure()` (le paquet `uuid` n'est qu'une dépendance
transitive : pas ajouté).

## Sécurité

- Routes réservées au rôle `buyer`, commande d'autrui ⇒ 404 (règle 3) : l'app affiche « plus
  disponible ».
- Le **code de remise** n'est affiché que s'il vient du serveur ; il n'est ni gardé sur le
  téléphone ni écrit dans un journal, une URL ou un message.
- Montants toujours ceux du serveur (récapitulatif et commande), jamais recalculés pour être
  envoyés.

## Tests

- `api_client` : modèles (tous les statuts), méthodes, `FakeOrders` (idempotence, refus,
  réservation, code selon le statut).
- `ui` : code de remise (sémantique, police à 200 %), frise (états).
- App acheteur :
  - Commande : récapitulatif, livraison désactivée, « Payer » (une commande, panier vidé, suivi
    ouvert), double appui, réseau coupé puis nouvel essai (même identifiant), refus du serveur ;
  - Commandes : séparation, nombre, « Récemment », vides, pastilles, ouverture du suivi ;
  - Suivi : en-têtes par statut, code, frise, articles, relecture à 20 s et arrêt sur terminé,
    404 ;
  - changement de compte ; police à 200 % sur 320 dp.

## Risques

- **Commandes non payées** tant que la 010 n'est pas faite : elles expirent après 15 min et
  libèrent le stock (comportement du serveur). En local, le paiement simulé du serveur
  (`POST /v1/dev/payments/{id}/simulate`) permet de vérifier le suivi et le code sur le
  simulateur.
- **Liste sans filtre de statut** : au-delà de 50 commandes, une commande en cours ancienne
  pourrait manquer à « En cours » ; peu probable au MVP, signalé au backend (filtre `status`).
