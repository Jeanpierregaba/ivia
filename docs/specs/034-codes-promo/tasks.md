# 034 — Tâches

<!-- Ordonnées. Chaque tâche est petite, testable et committable seule. Cochée dès qu'elle est faite et commitée. -->

**Serveur**
- [x] 1. Migration 00044 (`promo_codes`, `promo_redemptions`, `coupon_settings`, colonnes de
      `orders`, contrainte du total), `sqlc generate`.
- [x] 2. Tests du calcul de la réduction (pourcentage, plafond, fixe, minimum, 100 F à payer),
      écrits avant le code.
- [x] 3. Module `coupons` : calcul, aperçu (`POST /v1/promo-codes/check`), limite des essais ratés.
- [x] 4. Tests de concurrence et de cycle de vie (réservation, confirmation, libération), avant le
      code.
- [x] 5. Commande : code à la création, commission, réservation, confirmation au paiement,
      libération à l'expiration et à l'annulation.
- [x] 6. Relevés des marchands et indicateur des réductions offertes par ivia, avec tests.
- [x] 7. Codes du marchand : routes, contrôle de propriété (404), tests.
- [x] 8. Back-office : codes IVI, liste de tous les codes, suspension journalisée, réglages du
      coupon de bienvenue ; création du coupon à l'inscription.
- [x] 9. `GET /v1/me/coupons` ; `openapi.yaml`, `TestOpenAPICoversAllRoutes`, `govulncheck`.

**Applications**
- [x] 10. `api_client` : modèles et routes, avec tests.
- [x] 11. ivia : champ « Code promo » à l'écran Commande, réduction dans le récapitulatif, le
      suivi et le reçu.
- [x] 12. ivia : Profil › « Mes coupons ».
- [x] 13. Ivia Business : « Codes promo » (liste, création, suspension).
- [x] 14. Back-office : pages « Codes promo » et réglages du coupon de bienvenue.

**Vérification**
- [x] 15. Vérification sur l'aperçu web avec l'API locale.
- [ ] Vérifier tous les critères d'acceptation de spec.md
- [ ] Relecture par le sous-agent reviewer
