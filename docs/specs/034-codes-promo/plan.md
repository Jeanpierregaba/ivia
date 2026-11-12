# 034 — Plan technique

## Modèle de données (migration 00043)
- `promo_codes` (module `coupons`) : `id`, `code` (majuscules, unique), `shop_id` (NULL : coupon
  de bienvenue de la plateforme), `funded_by` (`shop` | `ivia`), `kind` (`percent` | `fixed`),
  `value`, `max_discount_xof`, `min_order_xof`, `starts_at`, `ends_at`, `max_uses`,
  `max_uses_per_user`, `visibility` (`public` | `private`), `reserved_for` (compte, coupon de
  bienvenue), `status` (`active` | `suspended` | `ended`), `uses_count`, `created_by`, horodatages.
  Contrainte `uses_count <= max_uses`.
- `promo_redemptions` : `code_id`, `order_id` (unique), `user_id`, `discount_xof`, `status`
  (`reserved` | `used` | `released`). Index partiel pour compter les utilisations par client.
- `coupon_settings` (une ligne) : coupon de bienvenue activé, montant, minimum, validité en jours.
- `orders` : `promo_code_id`, `discount_xof` (0 par défaut), `discount_funded_by` ; la contrainte
  `total_xof = subtotal_xof + delivery_fee_xof` devient `… - discount_xof` (migration additive :
  ancienne contrainte retirée, nouvelle posée, valeurs existantes inchangées car `discount_xof = 0`).

## Module `coupons` (backend/internal/coupons)
- `Quote(ctx, user, code, shopID, subtotal)` : vérifie le code et calcule la réduction (aucune
  écriture). Codes d'erreur : `promo_not_found`, `promo_not_started`, `promo_expired`,
  `promo_suspended`, `promo_exhausted`, `promo_already_used`, `promo_min_not_reached`,
  `promo_not_applicable`.
- `Reserve(ctx, tx, …)` dans la transaction de création de commande : `UPDATE promo_codes SET
  uses_count = uses_count + 1 WHERE id = $1 AND (max_uses IS NULL OR uses_count < max_uses)` puis
  insertion de la réservation ; refus si 0 ligne (concurrence garantie par la base).
- `Confirm(ctx, orderID)` au paiement réussi ; `Release(ctx, orderID)` à l'expiration ou à
  l'annulation avant paiement (décrémente `uses_count`).
- Coupon de bienvenue créé à la création d'un compte (crochet de `users`), si activé.
- Limite des essais ratés : 10 par heure et par compte (`ratelimit`).

## Module `orders`
- `checkout.go` : champ `promo_code` facultatif ; réduction appliquée aux produits ; commission
  calculée sur `subtotal - discount` pour un code de boutique, sur `subtotal` pour un coupon
  d'ivia ; total minimum 100 F.
- Transitions : `Confirm` au passage à payé, `Release` à l'expiration et à l'annulation avant
  paiement (dans la même transaction que le changement de statut).

## Module `settlements`
- Le net du marchand retire la réduction d'un code de boutique ; un coupon d'ivia ne change rien
  pour lui. Indicateur « réductions offertes par ivia » au back-office.

## API (openapi.yaml)
- Acheteur : `POST /v1/promo-codes/check` (aperçu), `promo_code` dans `POST /v1/orders`,
  `GET /v1/me/coupons`.
- Marchand : `GET|POST /v1/seller/shops/{id}/promo-codes`, `PATCH …/{code_id}` (dates, limites,
  visibilité ; valeur figée après une utilisation), `POST …/{code_id}/suspend|resume|end`.
- Admin : `GET /v1/admin/promo-codes` (tous), `POST /v1/admin/promo-codes` (boutique IVI),
  `POST /v1/admin/promo-codes/{id}/suspend|resume`, `GET|PUT /v1/admin/coupon-settings`.

## Apps
- ivia : champ « Code promo » à l'écran Commande (aperçu, retrait), ligne de réduction dans le
  récapitulatif, le suivi et le reçu ; Profil › « Mes coupons ».
- Ivia Business : « Codes promo » de la boutique (liste, création, suspension).
- Back-office : « Codes promo » (liste, création pour IVI, suspension), réglages du coupon de
  bienvenue.

## Tests (parties critiques, écrits avant le code)
- Calcul de la réduction (pourcentage, plafond, montant fixe, minimum, 100 F à payer).
- Concurrence : deux commandes simultanées sur un code à une utilisation restante.
- Commission et relevé : code de boutique et coupon d'ivia.
- Réservation libérée à l'expiration et à l'annulation, gardée au remboursement.
- Accès : codes d'une autre boutique introuvables (404).
