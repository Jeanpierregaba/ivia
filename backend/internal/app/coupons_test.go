package app_test

import (
	"fmt"
	"net/http"
	"sync"
	"testing"
)

func uniqueCode(prefix string) string { return fmt.Sprintf("%s%d", prefix, seq.Add(1)) }

// orderCommission lit le taux et la commission enregistrés sur une commande.
func orderCommission(t *testing.T, orderID string) (bp, commission int64) {
	t.Helper()
	if err := testDB.Pool.QueryRow(ctx(), "SELECT commission_rate_bp, commission_xof FROM orders WHERE id = $1", orderID).Scan(&bp, &commission); err != nil {
		t.Fatalf("commission : %v", err)
	}
	return bp, commission
}

// Spec 034 : code d'une boutique, de la création à l'utilisation, avec ses refus.
func TestShopPromoCodeLifecycle(t *testing.T) {
	requireApp(t)
	s := newSeller(t, 10)
	other := newSeller(t, 10)
	b := newBuyer(t, s.lat, s.lng)
	code := uniqueCode("SOLDE")

	c := mustStatus(t, call(t, s.token, "POST", "/v1/seller/shops/"+s.shopID+"/promo-codes", map[string]any{
		"code": " " + code + " ", "kind": "percent", "value": 10, "max_uses": 1, "min_order_xof": 4000,
	}), http.StatusCreated)
	if c.str("code") != code || c.str("state") != "active" {
		t.Fatalf("création : %s", c.Raw)
	}
	codeID := c.str("id")
	// Code déjà pris : refusé.
	if r := call(t, other.token, "POST", "/v1/seller/shops/"+other.shopID+"/promo-codes", map[string]any{
		"code": code, "kind": "fixed", "value": 500,
	}); r.code() != "promo_code_taken" {
		t.Fatalf("code en double : %d %s", r.Status, r.Raw)
	}
	// Boutique d'un autre : 404.
	if r := call(t, other.token, "GET", "/v1/seller/shops/"+s.shopID+"/promo-codes", nil); r.Status != http.StatusNotFound {
		t.Fatalf("liste d'une autre boutique : %d", r.Status)
	}
	if r := call(t, other.token, "POST", "/v1/seller/promo-codes/"+codeID+"/suspend", nil); r.Status != http.StatusNotFound {
		t.Fatalf("code d'une autre boutique : %d", r.Status)
	}

	quote := func(productID, promo string) resp {
		mustStatus(t, call(t, b.token, "PUT", "/v1/cart/items", map[string]any{"product_id": productID, "quantity": 1, "replace_cart": true}), http.StatusOK)
		return call(t, b.token, "POST", "/v1/orders/quote", map[string]any{"fulfillment": "pickup", "promo_code": promo})
	}
	if r := quote(other.untrackedID, code); r.code() != "promo_not_applicable" {
		t.Fatalf("autre boutique : %s", r.Raw)
	}
	if r := quote(s.untrackedID, "inconnu"); r.code() != "promo_not_found" {
		t.Fatalf("code inconnu : %s", r.Raw)
	}
	// 5000 F ≥ 4000 F : 10 %.
	q := mustStatus(t, quote(s.untrackedID, code), http.StatusOK)
	if q.Body["discount_xof"].(float64) != 500 || q.Body["total_xof"].(float64) != 4500 {
		t.Fatalf("aperçu : %s", q.Raw)
	}

	// Commande avec le code, annulée avant paiement : le code est rendu.
	o := mustStatus(t, call(t, b.token, "POST", "/v1/orders", map[string]any{"fulfillment": "pickup", "promo_code": code}), http.StatusCreated)
	if o.Body["discount_xof"].(float64) != 500 || o.Body["total_xof"].(float64) != 4500 || o.str("promo_code") != code {
		t.Fatalf("commande : %s", o.Raw)
	}
	if bp, com := orderCommission(t, o.str("id")); com != (4500*bp+5000)/10000 {
		t.Fatalf("commission sur le montant après réduction : %d", com)
	}
	mustStatus(t, call(t, b.token, "POST", "/v1/orders/"+o.str("id")+"/cancel", map[string]any{}), http.StatusOK)
	var uses int
	if err := testDB.Pool.QueryRow(ctx(), "SELECT uses_count FROM promo_codes WHERE id = $1", codeID).Scan(&uses); err != nil || uses != 0 {
		t.Fatalf("code rendu à l'annulation : %d %v", uses, err)
	}

	// Payée : utilisation confirmée, puis code épuisé pour un autre acheteur.
	mustStatus(t, quote(s.untrackedID, ""), http.StatusOK)
	o2 := mustStatus(t, call(t, b.token, "POST", "/v1/orders", map[string]any{"fulfillment": "pickup", "promo_code": code}), http.StatusCreated)
	pay(t, b, o2.str("id"))
	var status string
	if err := testDB.Pool.QueryRow(ctx(), "SELECT status FROM promo_redemptions WHERE order_id = $1", o2.str("id")).Scan(&status); err != nil || status != "used" {
		t.Fatalf("utilisation confirmée au paiement : %q %v", status, err)
	}
	b2 := newBuyer(t, s.lat, s.lng)
	mustStatus(t, call(t, b2.token, "PUT", "/v1/cart/items", map[string]any{"product_id": s.untrackedID, "quantity": 1}), http.StatusOK)
	if r := call(t, b2.token, "POST", "/v1/orders/quote", map[string]any{"fulfillment": "pickup", "promo_code": code}); r.code() != "promo_exhausted" {
		t.Fatalf("code épuisé : %s", r.Raw)
	}

	// Liste du marchand : une utilisation, 500 F offerts.
	l := mustStatus(t, call(t, s.token, "GET", "/v1/seller/shops/"+s.shopID+"/promo-codes", nil), http.StatusOK)
	it := l.Body["items"].([]any)[0].(map[string]any)
	if it["used_count"].(float64) != 1 || it["discount_given_xof"].(float64) != 500 {
		t.Fatalf("liste du marchand : %s", l.Raw)
	}

	// Suspension par un admin : motif obligatoire ; le marchand ne peut pas la lever.
	adm := admin(t)
	if r := call(t, adm, "POST", "/v1/admin/promo-codes/"+codeID+"/suspend", map[string]any{}); r.Status != http.StatusBadRequest {
		t.Fatalf("motif obligatoire : %d", r.Status)
	}
	mustStatus(t, call(t, adm, "POST", "/v1/admin/promo-codes/"+codeID+"/suspend", map[string]any{"reason": "Abus signalé"}), http.StatusOK)
	if r := call(t, s.token, "POST", "/v1/seller/promo-codes/"+codeID+"/resume", nil); r.Status != http.StatusForbidden {
		t.Fatalf("reprise d'un code suspendu par ivia : %d", r.Status)
	}
}

// Commandes simultanées : jamais plus d'utilisations que permis.
func TestPromoCodeConcurrency(t *testing.T) {
	requireApp(t)
	s := newSeller(t, 10)
	code := uniqueCode("UNIQUE")
	mustStatus(t, call(t, s.token, "POST", "/v1/seller/shops/"+s.shopID+"/promo-codes", map[string]any{
		"code": code, "kind": "fixed", "value": 500, "max_uses": 1,
	}), http.StatusCreated)
	buyers := []buyerFixture{newBuyer(t, s.lat, s.lng), newBuyer(t, s.lat, s.lng), newBuyer(t, s.lat, s.lng)}
	for _, b := range buyers {
		mustStatus(t, call(t, b.token, "PUT", "/v1/cart/items", map[string]any{"product_id": s.untrackedID, "quantity": 1}), http.StatusOK)
	}
	var wg sync.WaitGroup
	var mu sync.Mutex
	created := 0
	for _, b := range buyers {
		wg.Add(1)
		go func() {
			defer wg.Done()
			r := call(t, b.token, "POST", "/v1/orders", map[string]any{"fulfillment": "pickup", "promo_code": code})
			if r.Status == http.StatusCreated {
				mu.Lock()
				created++
				mu.Unlock()
			}
		}()
	}
	wg.Wait()
	if created != 1 {
		t.Fatalf("une seule commande avec le code : %d", created)
	}
}

// Coupon de bienvenue : payé par ivia, le marchand reçoit autant que sans coupon.
func TestWelcomeCoupon(t *testing.T) {
	requireApp(t)
	adm := admin(t)
	mustStatus(t, call(t, adm, "PUT", "/v1/admin/coupon-settings", map[string]any{
		"welcome_enabled": true, "welcome_amount_xof": 1000, "welcome_min_order_xof": 0, "welcome_valid_days": 30,
	}), http.StatusOK)
	defer call(t, adm, "PUT", "/v1/admin/coupon-settings", map[string]any{
		"welcome_enabled": false, "welcome_amount_xof": 0, "welcome_min_order_xof": 0, "welcome_valid_days": 30,
	})
	s := newSeller(t, 10)
	b := newBuyer(t, s.lat, s.lng)
	mine := mustStatus(t, call(t, b.token, "GET", "/v1/me/coupons", nil), http.StatusOK)
	var welcome string
	for _, it := range mine.Body["items"].([]any) {
		if m := it.(map[string]any); m["welcome"] == true {
			welcome = m["code"].(string)
		}
	}
	if welcome == "" {
		t.Fatalf("coupon de bienvenue absent : %s", mine.Raw)
	}
	// Un autre compte ne peut pas l'utiliser.
	b2 := newBuyer(t, s.lat, s.lng)
	mustStatus(t, call(t, b2.token, "PUT", "/v1/cart/items", map[string]any{"product_id": s.untrackedID, "quantity": 1}), http.StatusOK)
	if r := call(t, b2.token, "POST", "/v1/orders/quote", map[string]any{"fulfillment": "pickup", "promo_code": welcome}); r.code() != "promo_not_found" {
		t.Fatalf("coupon d'un autre : %s", r.Raw)
	}
	mustStatus(t, call(t, b.token, "PUT", "/v1/cart/items", map[string]any{"product_id": s.untrackedID, "quantity": 1}), http.StatusOK)
	o := mustStatus(t, call(t, b.token, "POST", "/v1/orders", map[string]any{"fulfillment": "pickup", "promo_code": welcome}), http.StatusCreated)
	if o.Body["total_xof"].(float64) != 4000 {
		t.Fatalf("commande : %s", o.Raw)
	}
	if bp, com := orderCommission(t, o.str("id")); com != (5000*bp+5000)/10000 {
		t.Fatalf("commission sur le montant plein (coupon d'ivia) : %d", com)
	}
}
