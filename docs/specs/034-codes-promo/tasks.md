# 034 — Tâches

<!-- Ordonnées. Chaque tâche est petite, testable et committable seule. Cochée dès qu'elle est faite et commitée. -->

**Serveur**
- [ ] 1. Migration 00043 (`promo_codes`, `promo_redemptions`, `coupon_settings`, colonnes de
      `orders`, contrainte du total), `sqlc generate`.
- [ ] 2. Tests du calcul de la réduction (pourcentage, plafond, fixe, minimum, 100 F à payer),
      écrits avant le code.
- [ ] 3. Module `coupons` : calcul, aperçu (`POST /v1/promo-codes/check`), limite des essais ratés.
- [ ] 4. Tests de concurrence et de cycle de vie (réservation, confirmation, libération), avant le
      code.
- [ ] 5. Commande : code à la création, commission, réservation, confirmation au paiement,
      libération à l'expiration et à l'annulation.
- [ ] 6. Relevés des marchands et indicateur des réductions offertes par ivia, avec tests.
- [ ] 7. Codes du marchand : routes, contrôle de propriété (404), tests.
- [ ] 8. Back-office : codes IVI, liste de tous les codes, suspension journalisée, réglages du
      coupon de bienvenue ; création du coupon à l'inscription.
- [ ] 9. `GET /v1/me/coupons` ; `openapi.yaml`, `TestOpenAPICoversAllRoutes`, `govulncheck`.

**Applications**
- [ ] 10. `api_client` : modèles et routes, avec tests.
- [ ] 11. ivia : champ « Code promo » à l'écran Commande, réduction dans le récapitulatif, le
      suivi et le reçu.
- [ ] 12. ivia : Profil › « Mes coupons ».
- [ ] 13. Ivia Business : « Codes promo » (liste, création, suspension).
- [ ] 14. Back-office : pages « Codes promo » et réglages du coupon de bienvenue.

**Vérification**
- [ ] 15. Vérification sur l'aperçu web avec l'API locale.
- [ ] Vérifier tous les critères d'acceptation de spec.md
- [ ] Relecture par le sous-agent reviewer
