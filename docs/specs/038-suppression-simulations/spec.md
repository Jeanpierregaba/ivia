# 038 — Audit et suppression des simulations (alerte médicament)

<!-- Demandé le 2026-11-13 avant la mise en production. -->

## Constat
Une alerte médicament recevait, environ 8 s après l'envoi, des réponses complètes de pharmacies
(produits, prix, disponibilités), alors qu'aucune vraie pharmacie n'avait répondu.

## Origine (vérifiée dans le code et la base)
1. **App ivia** (`new_alert_screen.dart`, `alert_screen.dart`) : après l'envoi ou la relance d'une
   alerte, un minuteur de 8 s appelait `POST /v1/dev/medicine-alerts/{id}/auto-respond`. Il était
   actif dès que l'option de paiement simulé (`IVIA_DEV_PAYMENT`) était compilée, ce qui est le cas
   de toutes les compilations de l'aperçu.
2. **Serveur** (`app/seed_pharmacy.go`, `pharmacy/dev.go`) : cette route faisait répondre les
   « pharmacies de démonstration » sollicitées, avec des prix calculés (1 500 à 3 500 F).
3. **Données** : `manage seed-demo` créait 11 pharmacies de démonstration (licence `DEMO-…`),
   validées, ouvertes et de garde. Elles étaient sollicitées comme de vraies pharmacies et
   recevaient la majorité des alertes.

Le vrai envoi fonctionnait déjà : la vraie pharmacie « Pharma Test » (à 1,6 km) avait bien été
sollicitée par la dernière alerte. La pharmacie « Test » est à 8,4 km, hors du rayon de 5 km.

## Corrections
- Supprimés : route `auto-respond`, `DevAutoRespond`, `DevSeedPharmacy`, requête
  `DevUpsertPharmacy`, création des pharmacies par `seed-demo`, méthode `devAutoRespond` du
  client API et ses deux appels dans l'app ivia.
- App ivia : « En attente de réponse » tant qu'aucune pharmacie n'a répondu ; message clair quand
  aucune pharmacie n'est joignable dans le rayon.
- Base locale de l'aperçu (sauvegarde CSV faite avant) : 11 pharmacies de démonstration
  suspendues (pas supprimées) ; 21 réponses inventées retirées de 7 alertes jamais payées, qui
  repassent « en recherche » ou « sans réponse ». Les alertes déjà payées en démonstration restent
  dans l'historique.

## Simulations restantes (développement seulement, jamais en production)
- Paiement simulé (`PAYMENT_PROVIDER=fake`, routes `/v1/dev/payments/…` et
  `/v1/dev/medicine-payments/…`) : la configuration refuse `fake` en production ; aucun
  agrégateur Mobile Money n'est encore choisi (ADR 0007).
- Code de connexion lu par l'app (`/v1/dev/otp`) : local et tests seulement.
- Jeu de démonstration (`manage seed-demo`) : boutiques, produits, livreurs et biens de démo,
  jamais lancé en production. Il ne crée plus de pharmacies.

## Tests réels
`TestPharmacyAlertOnlyRealResponses` (3 vraies pharmacies créées par l'API, dont une hors rayon) :
seules les 2 du rayon sont sollicitées et prévenues en direct dans leur app (WebSocket), l'alerte
est dans leur boîte, aucune réponse n'apparaît tant que personne n'a répondu, la route de
simulation n'existe plus, et le client voit exactement la réponse envoyée par la pharmacie (prix
compris). Les tests existants du parcours pharmacie passent aussi.
