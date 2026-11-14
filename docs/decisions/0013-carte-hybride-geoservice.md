# 0013 — Carte hybride et GeoService

- **Statut** : Proposé
- **Date** : 2026-11-06

## Contexte

`architecture-feat-map.md` définit la couche cartographique d'Ivia. Les apps appelaient directement les tuiles publiques d'OpenStreetMap, ce que sa politique d'usage interdit en production, et aucun itinéraire réel n'était calculé. Un fournisseur unique serait soit trop cher (Google pour tout), soit moins bon (OSM pour la recherche de lieux à Lomé).

## Décision

Chaque fournisseur sert là où il a le meilleur rapport qualité/coût, derrière le module `internal/mapping` :

- Affichage : Google Maps SDK, gratuit sur mobile.
- Itinéraires, matrices, recalage de trace : OSRM auto-hébergé.
- Géocodage inverse : Nominatim auto-hébergé, avec cache.
- Recherche : lieux personnels, puis base Ivia, puis Google Places (New) en secours, par le serveur seulement.
- Positions temps réel : Redis GEO, reçues par WebSocket.

Les apps n'appellent jamais de routage ni de géocodage directement. Les fournisseurs se choisissent par variables d'environnement, et rien d'externe n'est appelé sans configuration explicite. Si OSRM tombe : estimation à vol d'oiseau × 1,3, jamais de bascule automatique vers Google Routes. Les traces GPS sont des données personnelles, purgées après 180 jours.

## Conséquences

- Redis devient un service de plus à héberger, alors que l'ADR 0005 l'avait écarté pour les tâches de fond. Il ne sert ici qu'au temps réel et au cache, et reste facultatif : sans `REDIS_URL`, un équivalent en mémoire convient à un seul serveur.
- OSRM et Nominatim demandent 8 Go de RAM sur le VPS (ADR 0008) et ne doivent pas être exposés publiquement.
- Le suivi WebSocket diffuse en mémoire : il faudra un bus (Redis Pub/Sub) si l'API passe à plusieurs serveurs.
- Coût Google à plafonner dans la console, et conditions de stockage des données Places à vérifier avant la production.
