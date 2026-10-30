# TESTING — Stratégie de validation

Une fonctionnalité est « faite » quand les vérifications ci-dessous passent et que les cas de sa
spec sont couverts. Les commandes exactes sont dans `AGENTS.md`.

## Boucle de retour automatique
- Formatage automatique : hook `PostToolUse` de Claude Code (`.claude/hooks/format.mjs`) —
  `gofmt` (Go), `dart format` (Dart), `prettier` (back-office).
- Lint : `go vet` + `gofmt -l` (Go) ; `flutter analyze` (Dart, règles `flutter_lints`) ;
  `eslint` (Next.js).
- Typecheck : `go build ./...` ; `flutter analyze` ; `tsc --noEmit`.
- Tests unitaires et d'intégration :
  - Go : `go test ./...`. Les tests des stores, de la machine à états, du stock et de
    l'attribution tournent **contre un vrai PostgreSQL + PostGIS** (Docker en local, service en CI) ;
    chaque test travaille dans une transaction annulée ou une base dédiée.
  - Flutter : `flutter test` (logique, providers, widgets) sur chaque app et paquet du workspace.
  - Back-office : Vitest pour la logique.
- Tests end-to-end :
  - Back-office : Playwright sur les parcours admin critiques (valider une boutique, rembourser).
  - API : un test Go qui déroule un parcours complet par HTTP (inscription → commande → paiement
    factice → acceptation → livraison) avec les implémentations factices.
  - Apps mobiles : pas d'E2E automatisé au MVP ; checklist manuelle ci-dessous sur un vrai
    Android d'entrée de gamme.

## Intégration continue
À chaque push et pull request (`.github/workflows/ci.yml`), aucun merge si elle échoue :
- Backend : `gofmt`, `go vet`, `go test -race` avec PostGIS, `go build`, `govulncheck`,
  vérification que `sqlc generate` ne produit aucun écart.
- Mobile : `flutter analyze` et `flutter test` sur tout le workspace.
- Back-office : `pnpm install --frozen-lockfile`, `eslint`, `tsc --noEmit`, tests, `next build`.
- Contrat : le fichier OpenAPI est valide et les types TypeScript générés sont à jour.
- Secrets : gitleaks.

## Ce qui doit être testé pour chaque fonctionnalité
- Cas nominal
- Cas limites (vide, très long, caractères spéciaux et accents, doublons, concurrence)
- Cas d'erreur (réseau, permissions, données invalides)
- **Droits d'accès** : chaque route est testée avec un utilisateur sans le rôle et avec un
  utilisateur qui a le rôle mais pas la ressource (doit renvoyer 404).
Les cas précis de chaque fonctionnalité sont listés dans sa spec (`docs/specs/NNN-nom/spec.md`).

## Fonctionnalités critiques : test écrit AVANT le code
Pour ces parties, le sous-agent `test-writer` écrit d'abord les tests, on vérifie qu'ils échouent,
puis on implémente :
- **OTP et sessions** : expiration, nombre d'essais, usage unique, limitation de débit, révocation.
- **Contrôle d'accès** : rôles et propriété des ressources sur chaque module.
- **Machine à états des commandes** : chaque transition permise, chaque transition interdite
  refusée, historique écrit.
- **Réservation du stock** : N commandes simultanées sur le dernier article ⇒ une seule réussit ;
  libération à l'expiration, l'annulation et le retour en boutique.
- **Webhook de paiement** : signature invalide refusée, montant différent refusé, webhook reçu deux
  fois traité une seule fois, paiement arrivé après expiration.
- **Attribution des livreurs** : deux livreurs qui acceptent en même temps ⇒ un seul gagne ; délai
  de 45 s puis livreur suivant ; alerte après 5 livreurs ou 20 min ; véhicule incompatible exclu ;
  position trop ancienne exclue.
- **Calculs d'argent** : frais de livraison, commission, total, relevé marchand (avec remboursement
  après règlement).
- **Code de remise** : bon code, mauvais code, blocage après 5 essais.
- **Suppression de compte** : données personnelles anonymisées, données financières conservées,
  refus si une commande est en cours.

## Checklist manuelle avant un commit important
- [ ] Parcours complet testé, pas seulement le chemin heureux
- [ ] Entrées invalides / vides
- [ ] Mobile : sur un Android d'entrée de gamme, en 3G simulée et en coupant le réseau en plein parcours
- [ ] App livreur : propositions reçues app en arrière-plan et écran éteint (service actif)
- [ ] Accessibilité : police agrandie du téléphone, contrastes, zones tactiles
- Sans objet — mode sombre : hors MVP.
