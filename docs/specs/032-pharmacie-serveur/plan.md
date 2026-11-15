# 032 — Plan technique

## Approche

Trois blocs, dans cet ordre :

1. **Serveur (Go)** :
   - une migration ;
   - les requêtes sqlc et les services des modules `pharmacy`, `users`, `geo`, `delivery` et
     `notifications` ;
   - le contrat `openapi.yaml` et les tests Go par HTTP.
2. **Paiement en espèces** :
   - un ADR ;
   - la remise au livreur par code, côté serveur ;
   - l'app pharmacie (F17, F22, dossier en 4 étapes) et l'app livreur (code de retrait, montant
     avancé).
3. **Petits branchements de l'app pharmacie** sur les nouveaux champs : numéro, quartier, arrivée,
   forfait, devanture, origine des gardes, compteurs, sonnerie sur iPhone, PDF.

Règles respectées :
- Un module n'accède qu'à ses tables. La pharmacie demande le quartier au module `geo` et la
  position du livreur au module `delivery`, par leurs services.
- La migration est relue par Gedeon avant fusion.
- Aucun changement de statut hors des fonctions de transition du module `pharmacy`, qui écrivent
  dans la même transaction.

## Décision structurante → ADR

`docs/decisions/0014-pharmacie-paiement-especes-livreur.md` (statut : accepté le 2026-11-07, par le
porteur du projet). Il dit :
- le livreur paie la pharmacie en espèces au retrait ;
- ivia ne verse plus rien aux pharmacies ;
- le client paie toujours dans l'app ;
- ivia rembourse l'avance au livreur, hors de l'app pour l'instant ;
- la remise se valide par le code du livreur et la case « payé en espèces ».

Il remplace, pour les livraisons de pharmacie, le dû `pharmacy_due_xof` versé plus tard.

## Données (migration `00038_pharmacy_server_gaps.sql`, non destructive)

| Table | Changement | Rôle |
|---|---|---|
| `pharmacy_alerts` | `number bigint NOT NULL UNIQUE`, séquence `pharmacy_alert_number_seq` ; les alertes existantes sont numérotées par date de création | n° « A-n » |
| `pharmacy_duty_shifts` | `source text NOT NULL DEFAULT 'manual' CHECK (source IN ('manual','import','admin'))`, `imported_at timestamptz` | « planning officiel » |
| `pharmacy_deliveries` | `pickup_code text CHECK (pickup_code ~ '^[0-9]{4}$')`, `cash_paid_xof bigint CHECK (cash_paid_xof >= 0)`, `cash_paid_at timestamptz` | remise par code, avance du livreur |
| `device_tokens` (module `users`) | `alert_sound boolean NOT NULL DEFAULT true` | sonnerie coupée sur iPhone |

Notes :
- La migration ne supprime rien. Les colonnes `payout_*` des pharmacies et la table
  `pharmacy_payouts` restent, pour l'historique.
- Retour arrière (`Down`) : suppression des colonnes ajoutées et de la séquence.
- Le code de retrait est tiré au hasard (`crypto/rand`) quand le livreur accepte la course. Il n'est
  envoyé qu'au livreur assigné et n'est jamais journalisé.

## API (`openapi.yaml` et types générés)

**Pharmacie**
- `PharmacyInboxItem` : `number` (« A-12 ») et `client_neighborhood` (nom ou `null`).
- `GET /v1/pharmacy/me` :
  - ajout de `storefront_url`, lien signé de courte durée ;
  - le compte de versement n'est plus exigé à l'envoi : `POST /v1/pharmacy/me/submit` ne vérifie
    que les pièces.
  - `PUT /v1/pharmacy/me/payout` reste, marqué obsolète.
- `PharmacyReservation` :
  - `refund_fee_xof` : forfait remboursé si la pharmacie annule ;
  - `courier.eta_minutes` (ou `null`) ;
  - `picked_up_at` ;
  - `cash_paid_xof`.
- `POST /v1/pharmacy/reservations/{id}/courier-handover` `{code, cash_paid: true}` (nouvelle) :
  - effet : commande « récupérée », livraison « récupérée », avance enregistrée, livreur et client
    prévenus ;
  - erreurs : 422 si `cash_paid` n'est pas vrai, 400 `code` si le code est faux, 429 après 5 essais
    faux en 10 minutes (limiteur `platform/ratelimit` par commande), 409 si la commande n'attend
    pas de remise, 404 pour la commande d'une autre pharmacie.
- `GET /v1/pharmacy/cash-receipts?days=30` (nouvelle) : encaissements groupés par jour à Lomé
  (retraits payés au comptoir, livraisons payées par le livreur), avec un total par jour et un
  total sur 7 jours. L'ancien `GET /v1/pharmacy/earnings` reste pour le back-office.
- `GET /v1/pharmacy/today` (nouvelle) : `{received, responded, confirmed}` du jour à Lomé.
- `DutyShift` : `source` et `imported_at`. L'import (plusieurs gardes en un envoi) est marqué
  `import` ; un ajout seul, `manual`.

**Livreur**
- `CourierMission` : `pickup_code` (seulement tant que la mission est assignée) et
  `cash_advanced_xof`.
- `POST /v1/driver/pharmacy-missions/{id}/picked-up` répond 409 `handover_by_pharmacy`.
  L'app livreur ne l'appelle plus.

**Client**
- `Alert` : ajout de `number`.

**Appareils**
- `PUT /v1/me/devices` : ajout de `alert_sound` (facultatif, vrai par défaut).
- Le module `notifications` lit ce choix avec le jeton et envoie la notification iOS sans
  `aps.sound` quand il est faux.

## Fichiers touchés

**Backend**
- `db/migrations/00038_pharmacy_server_gaps.sql`
- `internal/pharmacy` :
  - `queries.sql` et `store/` (régénéré) ;
  - `alerts.go` (numéro, quartier, compteurs du jour) ;
  - `reservations.go` (forfait, arrivée, encaissements, remise par code) ;
  - `courier.go` (code de retrait, refus du « récupéré » seul, avance) ;
  - `dossier.go` (envoi sans compte) ;
  - `duty.go` (origine) ;
  - `pharmacies.go` (lien de la devanture) ;
  - `handler.go`, `service.go` (interfaces `Neighborhoods` et `DriverLocator`).
- `internal/geo` : `NearestNeighborhood(point)`.
- `internal/delivery` : `DriverLocation(userID)`.
- `internal/users` : enregistrement de `alert_sound`, et lecture avec les jetons.
- `internal/notifications/push.go` : son selon l'appareil.
- `internal/app` (assemblage, tests de bout en bout).
- `api/openapi.yaml`.

**Back-office**
- `admin/app/(admin)/pharmacies/[id]/page.tsx` et `actions.ts` :
  - le compte de versement et la saisie d'un versement sont retirés ;
  - l'historique des versements passés reste ;
  - l'avance du livreur est affichée sur les livraisons.
- `lib/api-types.ts` (régénéré).

**Mobile**
- `packages/api_client` : nouveaux champs et routes (`pharmacist.dart`, `driver_work.dart`,
  `pharmacy.dart`, `client.dart`).
- `apps/pharmacy` :
  - dossier en 4 étapes (`application_flow.dart`, `payout_screen.dart` retiré du parcours) ;
  - F17 avec le code et l'encaissement (`order_screen.dart`, nouveau `courier_handover_screen.dart`) ;
  - F22 « Encaissements » (`earnings/statement_screen.dart`) ;
  - numéro, quartier, arrivée, forfait, devanture, gardes importées, compteurs, sonnerie iOS, PDF.
- `apps/driver` : code de retrait affiché, plus de bouton « Récupéré » pour la pharmacie, montant
  avancé (`features/work/work_screens.dart`).
- `apps/buyer` : numéro d'alerte dans le suivi.

## Dépendances

`file_selector` (paquet officiel de l'équipe Flutter, déjà présent par ses implémentations de
plateforme dans le `pubspec.lock`) pour choisir un PDF. Avant de l'ajouter, je vérifie qu'il est
maintenu et je lis sa doc à jour (Context7).

## Sécurité

- **Code de retrait** :
  - aléatoire, 4 chiffres ;
  - comparé en temps constant, comme le code du client ;
  - 5 essais par 10 minutes ;
  - visible seulement par le livreur assigné ;
  - absent des journaux et des réponses à la pharmacie.
- **Quartier du client** : seul le nom du quartier le plus proche, jamais la position (le client
  reste anonyme avant la confirmation).
- **Photo de la devanture** : lien signé de courte durée, stockage privé.
- **Accès** : rôle pharmacien et propriété de la commande à chaque route ; commande d'autrui ⇒
  404.
- **Sonnerie** : préférence d'un appareil, sans donnée personnelle.

## Tests

- **Go**, contre PostGIS, par HTTP dans `internal/app` :
  - numéros consécutifs ;
  - quartier renvoyé, position absente ;
  - remise par code : bon code, code faux, limite d'essais, commande d'autrui, état incorrect,
    case non cochée ;
  - « récupéré » refusé au livreur ;
  - avance enregistrée ;
  - envoi du dossier sans compte ;
  - encaissements par jour ;
  - compteurs du jour en heure de Lomé ;
  - origine des gardes ;
  - lien de la devanture ;
  - `aps` sans son quand `alert_sound` est faux.
- `TestOpenAPICoversAllRoutes`.
- **Remise par code** : partie critique (machine à états, docs/TESTING.md), donc tests écrits
  avant le code.
- **Flutter** :
  - app pharmacie : dossier en 4 étapes, F17 avec le code, F22 Encaissements, nouveaux champs
    affichés, sonnerie sur iPhone, PDF ;
  - app livreur : code affiché, bouton « Récupéré » retiré ;
  - acheteur : numéro d'alerte.
- **Back-office** : `pnpm test`, `typecheck` et `lint`.
- **Simulateur** : pharmacie et livreur, avec l'API locale et `seed-demo`.

## Risques

- **Livreurs déjà en mission** au déploiement : leur mission n'a pas de code. Une mission sans code
  garde l'ancien « Récupéré » côté livreur jusqu'à sa fin. Les tests couvrent ce cas.
- **Versions de l'app livreur** pas encore mises à jour : elles appellent `picked-up` et reçoivent
  le message 409, qui leur demande de faire valider la remise par la pharmacie. À annoncer aux
  livreurs.
- **Avances jamais remboursées** : rien ne règle encore les livreurs dans l'app. L'avance est
  visible au back-office ; une spec de règlement des livreurs doit suivre (`TASKS.md`).
- **Travail parallèle de Gedeon** sur le module `pharmacy` : je récupère `develop` avant chaque
  tâche serveur. La migration lui est soumise avant d'aller plus loin.
