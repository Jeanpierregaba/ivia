# 0004 — Monolithe modulaire, sqlc, goose et PostGIS

- **Statut** : Accepté
- **Date** : 2026-10-30

## Contexte

Une quinzaine de domaines fonctionnels, deux développeurs, et des règles qui exigent un SQL
précis : réservation de stock sans survente, un seul livreur actif par commande, recherche par
distance, journal financier.

## Options envisagées

- **Microservices** : isolation forte, mais déploiement et cohérence des données hors de portée
  d'une équipe de deux.
- **Monolithe modulaire** : un binaire, une base, des modules isolés par convention et par revue.
- Accès aux données : **GORM** (le SQL est généré, moins à écrire, mais opaque sur les verrous et
  PostGIS) ou **sqlc** (on écrit le SQL, sqlc génère des fonctions Go typées).
- Migrations : **goose** (SQL, embarquable) ou golang-migrate (équivalent, moins pratique à embarquer).

## Décision

Monolithe modulaire (`backend/internal/<module>/` : handlers → service → store), sqlc pour les
requêtes, goose pour les migrations, PostgreSQL 18 + PostGIS 3.6 et la recherche plein texte de
PostgreSQL.

## Conséquences

- Un module ne lit ni n'écrit les tables d'un autre module : il appelle son service.
- Chaque requête SQL est relue : verrous (`FOR UPDATE`, mises à jour conditionnelles), index.
- Pas de moteur de recherche externe au MVP ; à reconsidérer si la recherche devient lente.
- Les migrations sont versionnées et appliquées au démarrage ; une migration destructive demande
  une confirmation explicite (voir `docs/RULES.md`).
- L'image Docker locale et de CI passe à `postgis/postgis:18-3.6-alpine`.
