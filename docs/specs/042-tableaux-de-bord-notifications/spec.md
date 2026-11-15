# 042 — Tableaux de bord (Business, Pharmacie) et notifications façon push

<!-- Demandé le 2026-11-14 ; spec écrite avec le code. -->

## Objectif
- Les accueils de Business et de la Pharmacie faisaient « dormants » : ils gagnent un vrai tableau
  de bord, avec statistiques et graphiques interactifs simples à lire.
- Les bandeaux bleus du bas de l'écran disparaissent : chaque confirmation ou erreur devient une
  notification en haut de l'écran, comme une notification du téléphone.

## Notifications
- `IviaNotificationHost` et `IviaMessenger` (paquet `ui`) sont branchés dans
  `IviaResponsiveFrame`, donc dans les quatre apps. Tout `showSnackBar` et tout `showMessage`
  existant devient une bannière qui descend du haut de l'écran :
  - icône dégradée, verte pour un succès, rouge pour un échec (déduit du texte) ;
  - bouton d'action en pilule (« Annuler », « Modifier ») ;
  - fermeture par un glissement vers le haut ou après 4 s (6 s avec une action).
- Aucun écran n'est réécrit, et les messages gardent leur texte.

## Business : « Performances » (Accueil)
- Choix de la période : 7 ou 30 jours.
- 4 chiffres clés avec leur tendance par rapport à la période précédente : chiffre d'affaires,
  commandes, panier moyen, clients.
- Graphiques :
  - ventes par jour, en histogramme interactif (toucher ou glisser fait apparaître une bulle avec
    le jour, le montant et le nombre de commandes) ;
  - heures de pointe ;
  - meilleurs produits, en barres de classement ;
  - part retrait / livraison, en anneau, avec le nombre d'annulations.
- `GET /v1/seller/shops/{id}/stats?days=7|30` : commandes payées, sans les annulées ni les
  remboursées, à l'heure de Lomé.

## Pharmacie : « Votre activité » (Accueil)
- Choix de la période : 7 ou 30 jours.
- 4 chiffres clés : alertes reçues, taux de réponse, temps de réponse moyen (plus bas, c'est
  mieux), ventes terminées.
- Graphiques :
  - alertes par jour (bulle : reçues et répondues) ;
  - anneau des réponses ;
  - heures d'affluence ;
  - médicaments les plus demandés.
- `GET /v1/pharmacy/stats?days=7|30`.

## Rien d'inventé
- Sans donnée, un état vide explique ce qui apparaîtra.
- Si la lecture échoue, la section se retire.

## Tests
- `internal/app/seller_stats_test.go` et `internal/app/pharmacy_stats_test.go`.
- Business : test d'écran du tableau de bord (tendance, bulle d'une barre, 30 jours, anneau).
- Les suites des quatre apps passent avec les nouvelles notifications.
