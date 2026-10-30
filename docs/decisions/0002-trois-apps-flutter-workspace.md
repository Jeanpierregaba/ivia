# 0002 — Trois apps Flutter dans un pub workspace

- **Statut** : Accepté
- **Date** : 2026-10-30

## Contexte

Le MVP comporte trois applications mobiles (acheteur, marchand, livreur) qui partagent le même
backend, le même compte utilisateur et beaucoup de code : appels API, connexion, modèles, thème.

## Options envisagées

- **Trois apps dans un seul dossier `mobile/` (Dart pub workspace) + paquets partagés** : chaque
  app est publiée séparément et reste légère ; le code commun n'est écrit qu'une fois. Les pub
  workspaces sont intégrés à Dart depuis la 3.6, sans outil supplémentaire.
- **Une seule app qui change selon le rôle** : moins de configuration, mais app plus lourde,
  espace livreur présent dans l'app publique, fiche Play Store confuse.
- **Trois dépôts séparés** : duplication du code commun, versions qui divergent.

## Décision

Un pub workspace `mobile/` avec `apps/buyer`, `apps/seller`, `apps/driver` et les paquets
`packages/api_client` et `packages/ui`.

## Conséquences

- L'app de démonstration actuelle (`mobile/lib`) est remplacée par cette structure.
- Une modification d'un paquet partagé peut casser les trois apps : `flutter analyze` et
  `flutter test` tournent sur tout le workspace en CI.
- Trois fiches Play Store, trois identifiants d'application à choisir.
