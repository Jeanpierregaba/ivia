# 0014 — Pharmacie : le livreur paie la pharmacie en espèces au retrait

- **Statut** : Accepté (porteur du projet)
- **Date** : 2026-11-07

## Contexte

Pour une alerte médicament livrée, le client paie dans l'app. Jusqu'ici, le serveur mettait de côté
le dû de la pharmacie (`pharmacy_due_xof`), et l'équipe ivia devait le lui verser plus tard sur un
compte Mobile Money. Ce compte était demandé dans le dossier d'inscription, et le relevé de l'app
pharmacie affichait un solde « à recevoir ».

Sur le terrain, les pharmacies veulent être payées tout de suite, et les livreurs ont de la
liquidité sur eux.

## Décision

- **Le livreur paie la pharmacie en espèces au moment du retrait.** Ivia ne verse plus rien aux
  pharmacies après coup.
- **Le client paie toujours dans l'app**, produits et course.
- **Ivia rembourse au livreur l'argent avancé**, en plus de sa course. Le montant avancé est
  enregistré sur chaque livraison (`cash_paid_xof`, `cash_paid_at`).
- **La remise au livreur se valide à la pharmacie**, avec deux conditions :
  - elle saisit le code à 4 chiffres affiché dans l'app du livreur ;
  - elle coche « Le livreur m'a payé … en espèces ».

  Le livreur ne peut plus se déclarer « récupéré » seul.
- **Le dossier de la pharmacie n'exige plus de compte de versement.** Le relevé devient un
  historique des encaissements : retraits payés au comptoir et livraisons payées par le livreur.

Les retraits au comptoir ne changent pas : le client paie la pharmacie sur place.

## Conséquences

- **Avances non remboursées dans l'app** : il n'existe pas encore de règlement des livreurs. Les
  avances sont visibles au back-office et réglées par l'équipe ivia à part, en attendant une spec
  dédiée.
- **Liquidité des livreurs** : un livreur doit avoir assez d'espèces pour accepter une course de
  pharmacie. Le plafond par course est à surveiller, et pourra devenir une règle d'attribution.
- **Données gardées** : les comptes de versement déjà saisis et l'historique des versements restent
  en base, sans nouvel usage.
- **Anciennes versions de l'app livreur** : elles reçoivent un refus explicite si elles tentent
  encore de valider seules la récupération.
