# 0003 — Back-office en Next.js

- **Statut** : Accepté
- **Date** : 2026-10-30

## Contexte

L'équipe ivia doit valider les boutiques et les livreurs, superviser commandes et paiements,
déclencher des remboursements et régler les marchands, depuis un navigateur d'ordinateur.

## Options envisagées

- **Flutter Web** : réutilise le client API et les modèles Dart, mais rendu web moins adapté
  aux écrans de gestion (tableaux, filtres, export).
- **Pages HTML générées par Go + htmx** : rapide, mais une deuxième façon de faire l'interface.
- **Next.js (App Router) + TypeScript** : écosystème riche pour les tableaux de gestion,
  connu de l'équipe — choix de l'équipe.

## Décision

Un back-office Next.js 16 dans `admin/`, qui **n'accède jamais à la base** : son serveur appelle
l'API Go comme les apps mobiles, avec un jeton de session d'un utilisateur `admin`.

## Conséquences

- Une troisième langue dans le dépôt (TypeScript) et sa chaîne d'outils (Node 24 LTS, pnpm).
- Les types TypeScript de l'API sont générés depuis `backend/api/openapi.yaml`.
- Le jeton est stocké dans un cookie `httpOnly` et utilisé uniquement côté serveur Next.js.
- Les règles d'accès restent dans le backend : le back-office ne fait qu'afficher et appeler.
- Hébergé sur le même VPS (sortie `standalone` de Next.js dans une image Docker) : l'offre
  gratuite de Vercel est réservée à un usage non commercial.
