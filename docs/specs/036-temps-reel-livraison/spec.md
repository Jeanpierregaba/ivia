# 036 — Temps réel et parcours de livraison

<!-- Demandé le 2026-11-13 (prompt « Amélioration du suivi en temps réel ») ; spec écrite avec le code. -->

## Constat (avant)
- Les apps relisaient à intervalle fixe : Business toutes les 30 s, le client toutes les 20 s.
  Un paiement reçu apparaissait donc avec jusqu'à 30 s de retard. Dans un navigateur, l'onglet en
  arrière-plan ralentit encore ces relectures.
- Le WebSocket existant (module `mapping`) ne transportait que la position du livreur, et il
  était désactivé dans le navigateur (le jeton ne pouvait pas y passer).
- L'app Livreur oubliait son état « en ligne » au relancement : le serveur continuait à lui
  proposer des courses qu'elle ne lisait plus.

## Solution
- **Événements en direct** : chaque notification (déjà créée à chaque étape d'une commande) et
  chaque signal discret (étape d'une course, statut pour le back-office) est publié **après la
  validation de la transaction** (tâche River) sur un bus en mémoire. Le monolithe tourne sur un
  seul serveur (ADR 0004).
- `GET /v1/ws/events?app=…` : WebSocket des apps. Dans le navigateur, le jeton passe dans le
  sous-protocole `ivia-bearer`, jamais dans l'URL. Ping toutes les 25 s ; à la reconnexion, l'app
  relit tout (événement `reconnected`).
- `GET /v1/admin/stream` : flux SSE du back-office (notifications des admins, étapes des courses,
  statuts des commandes, positions des livreurs), relayé par le serveur Next (`/live`).
- Les relectures régulières restent en secours, espacées quand la connexion tient (Livreur : 4 s
  sans connexion, 20 s avec).

## Parcours du livreur (glissements)
- A. Course acceptée : « Glisser pour démarrer ma course » (`POST /v1/driver/missions/{id}/start`,
  migration 00047 `started_at`). Étape « En route vers la boutique ».
- B. « Glisser à l'arrivée » : inchangé (arrivé à la boutique).
- C. « Glisser pour démarrer ma course vers le client » : colis récupéré, en route vers le client.
- D. Arrivée chez le client, puis remise avec le code : inchangés.
- Navigation : la carte suit la position toutes les 4 s ; l'itinéraire est recalculé dès que le
  livreur s'écarte de plus de 150 m (et chaque minute). Le guidage plein écran dans l'app est
  inchangé (recalcul hors trajet).

## Suivi par tous
- Client et marchand : carte « Livreur » avec les étapes (trouvé, en route vers la boutique,
  arrivé, en route vers le client, arrivé, livrée) et la position en direct sur la carte. Le
  suivi WebSocket est ouvert au marchand de la boutique.
- Back-office : bulles pour chaque notification, pages de suivi relues aussitôt, carte de la flotte
  dont les marqueurs avancent à chaque position reçue.

## Règles gardées
- Une proposition ne va qu'aux livreurs disponibles sans course (index uniques existants).
- Pas de doublon : chaque événement porte un identifiant, et les apps ignorent ceux déjà reçus.
- Positions envoyées toutes les 5 s en mouvement et 15 s à l'arrêt ; refusées hors ligne.

## Tests
`internal/app/realtime_test.go` : WebSocket (en-tête et sous-protocole), paiement → marchand,
boutique prête → livreur, chaque étape → client, marchand et back-office (SSE). App Livreur :
glissement « démarrer ma course ».

## Hors périmètre
- Suivi en arrière-plan sur téléphone au-delà de ce que permet le système (service de premier plan
  Android à ajouter avec les builds natifs).
- Boîtiers GPS des engins.
