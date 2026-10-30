# SESSION-LOG

<!--
Une entrée par session de travail, la plus récente EN HAUT. Rempli par /fin-de-session.
Objectif : que la session suivante reparte avec le contexte, sans deviner.
Reste bref : les décisions vont dans un ADR (docs/decisions/), on se contente d'y faire un lien.

Format :

### AAAA-MM-JJ — titre court
- Fait :
- Pièges rencontrés :
- Décisions : (liens vers les ADR)
- Prochaine étape :
-->

### 2026-10-30 — Corrections de la revue du backend
- Fait : 4 points importants et 4 mineurs de la revue corrigés, chacun couvert par un test ;
  migration 00017 (effacement des adresses de livraison) ; route admin `confirm-return`.
- Pièges rencontrés : le test d'attaque parallèle sur le code de remise ne prouvait pas la faille
  (compteur déjà plafonné) → test de régression déterministe (lecture périmée), vérifié en échec
  sur l'ancien code.
- Prochaine étape : inchangée (front, prestataire de paiement, déploiement).

### 2026-10-30 — Backend complet du MVP
- Fait : environnement Windows installé (Go 1.27, sqlc 1.31) ; schéma complet et 16 modules
  backend ; assemblage `internal/app` ; `cmd/manage` ; contrat OpenAPI (124 routes) vérifié par un
  test ; tests de bout en bout par HTTP sur PostGIS (parcours livraison et retrait, dernier
  article, webhooks, paiement tardif, remboursements, attribution, échec de livraison, droits,
  suppression de compte) ; parcours complet vérifié à la main sur l'API lancée ; CI enrichie.
- Pièges rencontrés : `core.autocrlf=true` sur Windows convertissait en CRLF (gofmt en échec) →
  `.gitattributes` force LF ; mémoire de la machine saturée → compiler avec `GOFLAGS=-p=2` et
  lancer sqlc avec `GOMAXPROCS=1` ; ports 5432/5433 déjà pris → `POSTGRES_PORT=5434` ; sqlc ne
  déduit pas la nullité dans les vues ni sur `IDENTITY` → `coalesce`/`NOT NULL` explicites ;
  River refuse d'insérer une tâche sans worker → les tests assemblent toute l'application ;
  govulncheck : faille de `crypto/x509` en Go 1.27.2 → passage à 1.27.3.
- Décisions : [ADR 0009](decisions/0009-recherche-vues-lecture-seule.md) (recherche par vues en
  lecture seule) ; stock dans `stock_levels` ; remboursements écrits une fois le résultat connu
  (`refund_pending` sur le paiement) ; transitions ajoutées au diagramme (voir ARCHITECTURE).
- Prochaine étape : front (workspace Flutter, back-office Next.js) sur le contrat OpenAPI ;
  choix du prestataire de paiement (016) ; déploiement (017).

### 2026-10-30 — Cadrage du MVP et squelette backend
- Fait : squelette Go + Flutter + PostgreSQL/PostGIS ; cadrage complet (PRD, ARCHITECTURE,
  stress-test, AGENTS, RULES, SECURITY, TESTING, backlog) ; backend restructuré en modules
  (`internal/<module>`, `internal/platform`), migrations goose appliquées au démarrage
  (extensions PostGIS, pg_trgm, unaccent), contrat `backend/api/openapi.yaml` ; dépôt poussé sur GitHub.
- Pièges rencontrés : depuis PostgreSQL 18, le volume Docker se monte sur `/var/lib/postgresql` ;
  `go test -race` prend environ 2 min sur le Mac Intel (compilation de la bibliothèque standard).
- Décisions : [ADR 0001 à 0008](decisions/) — Next.js pour le back-office (0003),
  prestataire de paiement encore à choisir (0007, « Proposé »). `docs/DESIGN.md` laissé vide :
  charte en cours de conception.
- Prochaine étape : répartition — backend au collaborateur (spec 001, connexion OTP), frontend
  au porteur du projet (workspace Flutter des 3 apps, back-office Next.js). Lancer les démarches
  hors code de `TASKS.md`.
