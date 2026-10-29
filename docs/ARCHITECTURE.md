# ARCHITECTURE

<!--
À REMPLIR après docs/PRD.md. Définit COMMENT le projet est construit techniquement.
Version détaillée : le résumé indispensable (stack, règles non négociables) va dans AGENTS.md.
Chaque choix important a son ADR dans docs/decisions/ — ici, on résume et on fait un lien.
-->

## Stack technique
<!-- Langage(s), framework(s), base de données, hébergement — avec versions.
Vérifier les versions actuelles (doc officielle / Context7), pas celles dont le modèle se souvient. -->

## Modèles de données
<!-- Entités principales, champs clés et relations. Un schéma texte ou Mermaid suffit. -->

## Architecture générale
<!-- Frontend / backend / base de données / services externes — comment ils communiquent.
Un diagramme Mermaid est bienvenu. -->

## Authentification et autorisations
<!-- Qui peut faire quoi. Où le contrôle d'accès est appliqué (middleware, RLS, policies…). -->

## Intégrations externes
<!-- APIs tierces et services (paiement, email, stockage, IA…). Pour chacun : usage, clé requise, coût, limite. -->

## Environnements et déploiement
<!-- local / preview / production : où ça tourne, comment on déploie, comment on revient en arrière,
où vivent les secrets de chaque environnement. -->

## Observabilité
<!-- Logs, suivi d'erreurs (ex : Sentry), métriques. Comment on sait qu'un truc casse en production. -->

## Choix techniques
<!-- Liste des ADR avec une ligne de résumé chacun. Ex :
- [ADR-0001](decisions/0001-choix-de-la-stack.md) — Stack : Next.js + Postgres (Supabase) -->

## Points d'attention
<!-- Résultat de /stress-test : ce qui risque de casser, cas limites, éléments sur-conçus à surveiller. -->
