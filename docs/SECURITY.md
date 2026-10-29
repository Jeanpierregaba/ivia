# SECURITY — Sécurité de l'application

<!--
Les applications vibecodées tombent souvent dans les mêmes pièges. Ce fichier liste les points à
vérifier ; /audit-securite les passe en revue. Coche ce qui est en place, adapte à la stack choisie,
supprime ce qui ne s'applique pas (en notant pourquoi).
-->

## Secrets et configuration
- [ ] Aucun secret dans le code ni dans l'historique git (scan : gitleaks ou équivalent).
- [ ] Aucun secret exposé au navigateur (variables `NEXT_PUBLIC_*`, `VITE_*`… ne contiennent que du public).
- [ ] Clés différentes entre développement et production.

## Authentification et accès
- [ ] Le contrôle d'accès est appliqué côté serveur, jamais seulement dans l'interface.
- [ ] Chaque requête vérifie que l'utilisateur a le droit d'accéder à CETTE ressource (pas seulement qu'il est connecté).
- [ ] Si la base est accessible depuis le client (Supabase, Firebase…) : règles RLS / security rules activées sur toutes les tables.
- [ ] Sessions / jetons : expiration, révocation, cookies `HttpOnly` + `Secure` + `SameSite`.

## Entrées et sorties
- [ ] Toutes les entrées sont validées côté serveur (schéma : Zod, Pydantic…).
- [ ] Requêtes paramétrées / ORM, jamais de concaténation SQL.
- [ ] Pas de HTML non échappé (XSS).
- [ ] Upload de fichiers : type, taille et emplacement contrôlés.

## Abus
- [ ] Limitation de débit (rate limiting) sur l'authentification, les formulaires publics et les endpoints coûteux.
- [ ] Protection CSRF si l'authentification passe par cookies.
- [ ] Les messages d'erreur ne révèlent pas d'information interne.

## Dépendances
- [ ] Audit des dépendances dans la CI (`npm audit`, `pip-audit`…).
- [ ] Mises à jour de sécurité automatisées (Dependabot / Renovate).
- [ ] Fichier de lock commité.

## Fonctionnalités IA (si applicable)
- [ ] Le contenu fourni par l'utilisateur ou par des sources externes n'est jamais traité comme des instructions (injection de prompt).
- [ ] Le modèle n'a accès qu'aux outils et données strictement nécessaires.
- [ ] Coût maîtrisé : limites par utilisateur et alertes de dépense.

## Données personnelles
- [ ] Données collectées limitées au nécessaire, durée de conservation définie (RGPD).
- [ ] Suppression de compte et export des données possibles si requis.
