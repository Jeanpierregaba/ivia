# 0010 — Position arrondie dans l'URL des recherches

- **Statut** : Accepté
- **Date** : 2026-11-01

## Contexte

La recherche « autour de moi » (spec [007](../specs/007-accueil-recherche-acheteur/spec.md))
envoie la position de l'acheteur au serveur. Le contrat de l'API la place dans l'URL
(`GET /v1/search/products?lat=…&lng=…&radius_m=…`, idem pour les boutiques), alors que
`docs/RULES.md` interdit d'écrire une position dans une URL : les URL complètes peuvent être
journalisées (Caddy les journalise par défaut, des proxys aussi).

## Options envisagées

- **Passer la recherche en `POST` avec la position dans le corps** : la règle est respectée à la
  lettre, mais le contrat, l'OpenAPI, les tests de bout en bout et le cache HTTP éventuel changent,
  pour une recherche qui reste par nature une lecture.
- **Garder l'URL et arrondir la position côté app** à 3 décimales (environ 110 m) : la position
  envoyée ne désigne plus un domicile mais un pâté de maisons, ce qui suffit pour un rayon de
  1 km ou plus ; aucun changement serveur.
- **Garder l'URL sans arrondi** : position précise à quelques mètres dans les journaux ; écarté.

## Décision

- Les apps arrondissent `lat` et `lng` à **3 décimales** avant tout envoi dans une URL de
  recherche (`SearchQuery.toParams`). L'app acheteur ne demande de toute façon qu'une position
  approximative au téléphone (Android `ACCESS_COARSE_LOCATION`, iOS précision réduite).
- C'est une **exception documentée** à la règle « jamais de position dans une URL », limitée aux
  routes `GET /v1/search/*`.
- En production, **Caddy ne journalise pas les paramètres d'URL** (requête journalisée sans sa
  query string) ; l'API ne journalise déjà que le chemin (`r.URL.Path`).

## Conséquences

- Les distances affichées dans les résultats ont une marge d'environ 100 m ; la fiche boutique
  calcule la sienne sur le téléphone, à partir de la position non arrondie, qui ne quitte pas
  l'app.
- Le déploiement (tâche 017, `infra/`) doit configurer le format de journal de Caddy en
  conséquence ; à vérifier par `/audit-securite` avant la mise en production.
- Toute nouvelle route qui recevrait une position (ex. position du livreur, 019) la place dans le
  corps d'une requête, pas dans l'URL.
