# 0009 — Recherche par vues SQL en lecture seule

- **Statut** : Accepté
- **Date** : 2026-10-30

## Contexte

La recherche de produits croise des données de trois modules : le produit (`catalog`), la
boutique publiée et sa position (`shops`) et la disponibilité (`stock`). La règle 2 d'AGENTS.md
interdit à un module de lire les tables d'un autre ; l'ADR 0004 exclut un moteur de recherche
externe au MVP. Passer par les services (un appel par produit) rendrait la recherche par distance
et le tri par pertinence impossibles à paginer correctement en SQL.

## Options envisagées

- **Appels de services puis filtrage en Go** : respecte la règle, mais il faut charger tout le
  catalogue pour trier et paginer ; inacceptable dès quelques milliers de produits.
- **Table dénormalisée tenue à jour par le module search** (copie alimentée par des tâches de
  fond) : isolation totale, mais copie en retard, double écriture et code de synchronisation.
- **Vues SQL en lecture seule, propriété du module search** (`search_products`, `search_shops`) :
  une seule requête paginée, toujours à jour ; le couplage est déclaré dans une migration et limité
  aux colonnes publiques.

## Décision

Le module `search` lit uniquement les vues `search_products` et `search_shops` (migration
`00016_search_views.sql`). Elles n'exposent que des données publiques : produits actifs des
boutiques publiées, sans propriétaire, téléphone ni adresse. Aucun autre module ne les utilise et
le module search n'écrit nulle part.

## Conséquences

- Une modification des tables `products`, `shops`, `categories`, `product_images` ou
  `stock_levels` qui touche une colonne de ces vues demande de recréer la vue dans la même migration.
- La pertinence combine le plein texte français sans accents (`tsvector` pondéré nom/description)
  et la similarité trigramme (fautes de frappe) ; la distance utilise les index GiST PostGIS.
- Si la recherche devient lente, on passera à une vue matérialisée ou à un moteur externe (nouvel ADR).
