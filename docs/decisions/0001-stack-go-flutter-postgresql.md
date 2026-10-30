# 0001 — Stack : Go, Flutter et PostgreSQL

- **Statut** : Accepté
- **Date** : 2026-10-30

## Contexte

Il faut une API serveur et une application mobile iOS + Android, avec une base relationnelle.
Le cadrage (PRD, modèle de données) n'est pas encore fait : la stack est posée en amont, sur
demande, pour pouvoir démarrer.

## Options envisagées

- **Backend** : Go avec la bibliothèque standard (routage par motifs de `net/http`, `log/slog`)
  plutôt qu'un framework (Gin, Echo…) — moins de dépendances, suffisant pour une API REST.
- **Mobile** : Flutter — une seule base de code pour iOS et Android.
- **Base de données** : PostgreSQL 18 (dernière version majeure stable).
  - Driver : `pgx/v5` avec `pgxpool`, le driver PostgreSQL Go le plus utilisé et maintenu,
    plutôt que `database/sql` + `lib/pq` (en maintenance seule).
  - En local : Docker Compose (version figée, identique en CI) plutôt qu'une installation
    Homebrew propre à chaque machine.

## Décision

Go (stdlib) + Flutter + PostgreSQL 18 via `pgx/v5`, PostgreSQL lancé par `docker-compose.yml`
en local et en service dans la CI.

## Conséquences

- En local, PostgreSQL utilise l'authentification `trust` sur un port exposé seulement sur
  `127.0.0.1` : aucun mot de passe à stocker. Les autres environnements devront fournir un
  `DATABASE_URL` avec mot de passe et TLS (`sslmode=require` au minimum).
- Docker Desktop doit tourner pour développer le backend.
- L'outil de migrations SQL reste à choisir (voir `TASKS.md`).
- L'API expose `/health` (processus vivant, sans base) et `/ready` (base joignable).
