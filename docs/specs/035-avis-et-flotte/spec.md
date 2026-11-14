# 035 — Avis et carte de la flotte

<!-- Demandé le 2026-11-13 (« ne me demande plus, code ça ») : spec écrite avec le code. -->

## Objectif
- Savoir comment se passent les livraisons : le client (et, s'il le veut, le marchand) note le
  livreur après chaque livraison ; les utilisateurs donnent leur avis sur l'application. Le
  back-office voit tout.
- Voir la flotte en direct au back-office : où sont les livreurs, qui est en course, d'où ils
  viennent (trajet). Première étape avant les boîtiers GPS des engins (suivi et blocage à distance).

## Comportement attendu

### Avis
1. App ivia : sur une commande livrée, une carte « Notez votre livraison » ; la feuille d'avis
   s'ouvre seule la première fois (étoiles, compliments ou problèmes selon la note, commentaire).
2. Après une note de 4 ou 5 étoiles, « Et ivia, vous aimez ? » est demandé une seule fois.
3. Ivia Business : « Noter le livreur » sur une commande livrée (facultatif).
4. Ivia Driver : sa note moyenne et le nombre d'avis dans son profil.
5. Back-office › Avis : livreurs les plus notés (moyenne, nombre, mauvaises notes), note de
   chaque application, liste des notes et des avis.

### Carte de la flotte
1. Back-office › Carte de la flotte : livreurs vus ces 24 dernières heures, couleur selon l'état
   (disponible, en course, hors ligne, suspendu), rafraîchie toutes les 10 s, déplacement animé.
2. Filtres, recherche (prénom, plaque), fiche : dernière position, course en cours, trajet sur
   1 h, 6 h, 1 j ou 3 j avec le point de départ, appel, lien vers le dossier.
3. « Bloquer l'engin » affiché, inactif : il attend les boîtiers GPS (lot suivant).

## Critères d'acceptation
- [x] Une commande non livrée ne peut pas être notée (`rating_not_available`).
- [x] Une note par commande et par rôle (client, marchand) ; seconde note refusée (`already_rated`).
- [x] 1 à 5 étoiles ; étiquettes inconnues ignorées ; commentaire de 500 caractères au plus.
- [x] La commande d'un autre : 404.
- [x] La moyenne du livreur compte les notes du client et du marchand.
- [x] La carte et le trajet sont réservés aux admins (403 pour les autres).
- [x] La carte montre la mission en cours d'un livreur et son trajet récent.

## Hors périmètre
- Boîtiers GPS des engins (position sans l'app, blocage à distance) : il faut choisir le
  fournisseur des boîtiers et son API.
- Note du client par le livreur, note des boutiques.

## Données
Migration 00045 : `delivery_ratings`, `app_feedback`. Positions : `drivers.last_location` et
`driver_positions` (déjà là, gardées 30 jours). Tests : `internal/app/ratings_test.go`.
