# 039 — Comptes admin à rôles

<!-- Demandé le 2026-11-13 ; spec écrite avec le code. -->

## Objectif
Plusieurs comptes admin, chacun avec un rôle précis. Le super admin peut tout faire, crée les
autres comptes admin et voit ce que chacun fait. Un compte client, marchand, livreur ou pharmacie
ne devient jamais admin.

## Rôles
| Rôle | Sections |
|---|---|
| Super admin | Tout, dont réglages, comptes, comptes admin et journal des actions |
| Opérations | Commandes, commandes IVI, paiements, remboursements, livraisons, carte de la flotte, signalements, avis |
| Réseau | Boutiques, Ivia Business, livreurs et réglages, immobilier, catégories, quartiers |
| Santé | Pharmacies, alertes et paiements santé, médicaments, réglages santé |
| Marketing | Publicité, produits IVI, codes promo, avis |
| Finances | Paiements, remboursements, relevés, exports ; commandes et codes promo en lecture |
| Carte | Lieux, zones et tarifs, coûts de la carte |
| Support client | Commandes, comptes, boutiques, livreurs, pharmacies en lecture ; avis, signalements |

Tous les admins ont le tableau de bord, le direct et leur sécurité. La table est dans
`internal/platform/adminperm` et le routeur la vérifie à chaque requête `/v1/admin/...`
(`admin_scope` sinon). Le menu du back-office ne montre que les sections du rôle.

## Règles
- Un compte admin est toujours distinct : il est créé par le super admin avec une adresse jamais
  utilisée sur ivia (`email_in_use` sinon). Le nouvel admin choisit son mot de passe avec « Mot de
  passe oublié » et confirme chaque connexion par un code.
- L'ancienne action « Rendre admin » sur un compte existant est supprimée.
- On ne change pas son propre rôle et on ne retire pas son propre accès ; il reste toujours au
  moins un super admin.
- Création, changement de rôle et retrait sont journalisés. Le journal des actions (super admin)
  se filtre par admin et montre son nom et son rôle.
- Migration 00049 : les admins existants deviennent super admins (aucun accès retiré).

## Tests
`internal/platform/adminperm` (table des droits), `internal/app/admin_roles_test.go` (compte
client refusé, accès limité au rôle, changement de rôle, protections, journal, retrait).
