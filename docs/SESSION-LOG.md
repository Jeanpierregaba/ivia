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
