# 010 — Plan technique

## Approche

- **Routes existantes** (module `payments`, testées) :
  - `POST /v1/orders/{id}/payments` `{operator, phone}` → `Payment` (`pending`) ; s'il y a déjà une
    demande en attente pour la commande, le serveur la rend telle quelle ;
  - `GET /v1/orders/{id}/payments` (plus récentes d'abord) et `GET /v1/payments/{id}` ;
  - `POST /v1/dev/payments/{id}/simulate` `{outcome}` (faux prestataire, local et tests).
- **Nouveau côté serveur** (relu par Gedeon, sans migration) :
  - `POST /v1/payments/{id}/cancel` (rôle `buyer`) : `SetPaymentStatus` conditionnel
    `pending → failed`, raison « Annulé par l'acheteur. ». Idempotent : une demande déjà
    `failed` ou `expired` est rendue telle quelle ; `succeeded`, `refund_pending`, `refunded` ⇒
    409 `payment_not_cancellable` ; demande d'autrui ⇒ 404 `payment_not_found` (règle 3).
    L'index unique `payments_one_pending_per_order` est libéré : une nouvelle demande est possible.
    Le prestataire n'est pas prévenu (l'interface n'a pas d'annulation) : une validation tardive
    arrive par webhook et `applySuccess` l'applique déjà depuis `failed` (doublon ⇒ file
    existante de remboursement).
  - `Initiate` : limiteur en mémoire (`ratelimit.New(10, time.Hour)`, clé acheteur), compté
    seulement à la création d'une nouvelle demande, après le contrôle de la commande et de la
    demande en attente ; 429 `rate_limited`.
- **Parcours de l'app** :
  - écran Commande : « Payer » crée la commande (inchangé), puis `go(suivi)` + `push(paiement)` :
    le retour depuis Paiement mène au suivi ;
  - suivi, « Payer » : `GET /v1/orders/{id}/payments` ; une demande `pending` ⇒ écran d'attente,
    sinon écran Paiement ;
  - Paiement → `POST …/payments` → `pushReplacement` de l'écran d'attente ;
  - attente : `GET /v1/payments/{id}` toutes les 3 s (premier plan, route courante, comme le
    suivi de la 009), arrêt sur un statut final ou 10 min après l'heure limite ; `succeeded` ⇒
    retour au suivi (relu) avec message ; `failed` ⇒ état d'échec dans l'écran.
- **Numéro** : celui du profil de la session (`+228XXXXXXXX` → « 96 45 12 78 »), contrôlé comme le
  serveur (8 chiffres, 7 ou 9 en tête). Le numéro affiché à l'attente est `phone_masked` du
  serveur, mis en forme « +228 96 •• •• 78 ».
- **Temps restant** : `paymentDeadlineAt` de la commande, barre = restant / (`paymentDeadlineAt`
  − `createdAt`), minuteur d'une seconde.
- **Simulation locale** : `devPaymentsProvider` = `!kReleaseMode &&
  bool.fromEnvironment('IVIA_DEV_PAYMENT')`, comme `IVIA_DEV_OTP`.

## Fichiers touchés

**`backend/`**
- `internal/payments/service.go` : `Cancel(ctx, buyerID, paymentID)`, limiteur dans `Initiate`.
- `internal/payments/handler.go` : route `POST /v1/payments/{id}/cancel`.
- `internal/payments/queries.sql` : aucune requête nouvelle (`GetPayment`, `SetPaymentStatus`
  suffisent).
- `internal/app/payments_test.go` (créé) : annulation (en attente, déjà échouée, réussie, autrui,
  nouvelle demande après annulation, validation tardive après annulation), limite des demandes.
- `api/openapi.yaml` : la route ; `admin/lib/api-types.ts` régénéré (`pnpm gen:api`).

**`mobile/packages/api_client`**
- `models.dart` : `Payment` (`id`, `orderId`, `status` : `PaymentStatus` avec `unknown`,
  `amountXof`, `operator` : `PaymentOperator`, `phoneMasked`, `failureReason`, dates).
- `client.dart` : `startPayment(orderId, operator, phone)`, `orderPayments(orderId)`,
  `payment(id)`, `cancelPayment(id)`, `devSimulatePayment(id, {succeeded})`.
- `testing.dart` : `FakePayments` branché sur `FakeOrders` (demande en attente rendue, annulation,
  simulation qui fait avancer la commande, refus, `rateLimited`, `providerDown`, 404 d'autrui).

**`mobile/packages/app_core`**
- `formats.dart` : `maskedPhone()` (« +228 96 •• •• 78 »), `countdown()` (« 14:32 »).

**`mobile/apps/buyer`**
- `features/payment/`
  - `payment_screen.dart` : montant, opérateurs (`checked` + groupe exclusif pour le lecteur
    d'écran), `TogoPhoneField`, « Payer » ;
  - `payment_wait_screen.dart` : texte, temps restant, relecture, échec, « Je n'ai rien reçu »,
    « Annuler le paiement », boutons de simulation ;
  - `payment_providers.dart` : `paymentProvider(id)` (relecture, `updatedAt` plus ancien ignoré),
    `devPaymentsProvider`.
- `app/router.dart` : `/orders/:id/pay` et `/orders/:id/pay/:paymentId` (navigateur racine).
- `features/checkout/checkout_screen.dart` : ouvre le suivi puis Paiement.
- `features/orders/order_screen.dart` : « Payer » ouvre Paiement ou l'attente.

**Docs** : `DESIGN.md` (Paiement, attente), `TASKS.md`, `AGENTS.md` (`IVIA_DEV_PAYMENT`).

## Données

Aucune migration. Rien de nouveau sur le téléphone (opérateur et numéro ne sont pas gardés).

## API / interfaces

Voir Approche. Codes d'erreur traités par l'app : `order_not_payable`, `order_expired`,
`order_not_found`, `payment_not_found`, `payment_not_cancellable`,
`payment_provider_unavailable`, `rate_limited`, `validation_failed` (numéro).

## Dépendances

Aucune.

## Sécurité

- Le statut affiché vient toujours du serveur ; l'app n'envoie jamais un statut de paiement (la
  simulation locale passe par la route du faux prestataire, absente en staging et production).
- L'annulation ne peut que passer `pending → failed` : elle ne rend jamais un paiement réussi
  annulable ni remboursable par l'acheteur.
- Limite des demandes : empêche d'envoyer des demandes de paiement en boucle vers le numéro d'un
  tiers.
- Le numéro saisi n'est ni journalisé ni gardé sur le téléphone ; l'écran d'attente montre le
  numéro masqué du serveur. Journaux serveur : `payment_id` seulement.

## Tests

- Go (`internal/app`, test avant le code, partie critique) : voir Fichiers touchés.
- `api_client` : modèle `Payment` (tous les statuts, statut inconnu), méthodes, `FakePayments`.
- `app_core` : `maskedPhone`, `countdown`.
- App acheteur :
  - Paiement : montant, Flooz par défaut, numéro du profil, numéro invalide, une seule demande,
    erreurs du serveur, retour au suivi ;
  - attente : texte et temps restant, succès ⇒ suivi avec code, échec ⇒ « Réessayer », « Je n'ai
    rien reçu » (renvoyer, changer de numéro), « Annuler le paiement », annulation qui croise une
    validation, délai dépassé, relecture arrêtée en arrière-plan ;
  - suivi : « Payer » rouvre l'attente d'une demande en cours ;
  - Commande : « Payer » ouvre Paiement au-dessus du suivi ;
  - police à 200 % sur 320 dp.

## Risques

- **Annulation sans prévenir le prestataire** : la demande peut encore être validée sur le
  téléphone. Couvert par le webhook (paiement appliqué) et, si deux demandes aboutissent, par la
  file des doublons à rembourser déjà en place (014). À revoir avec l'API du vrai prestataire
  (016), s'il permet d'annuler.
- **Limiteur en mémoire** : remis à zéro au redémarrage et propre à chaque instance ; suffisant
  avec une seule instance (comme celui des commandes).
