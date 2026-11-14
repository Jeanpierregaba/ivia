package app_test

import (
	"net/http"
	"testing"
)

// Livraison avec un code de boutique : relevé du marchand réduit, avis du client et du marchand,
// position du livreur sur la carte de la flotte (specs 034 et 035).
func TestDeliveredOrderPromoRatingAndFleet(t *testing.T) {
	requireApp(t)
	s := newSeller(t, 10)
	b := newBuyer(t, s.lat, s.lng)
	d := newDriver(t, s.lat+0.002, s.lng, "motorbike")
	code := uniqueCode("LIVRE")
	mustStatus(t, call(t, s.token, "POST", "/v1/seller/shops/"+s.shopID+"/promo-codes", map[string]any{
		"code": code, "kind": "fixed", "value": 1000,
	}), http.StatusCreated)

	mustStatus(t, call(t, b.token, "PUT", "/v1/cart/items", map[string]any{"product_id": s.trackedID, "quantity": 2, "replace_cart": true}), http.StatusOK)
	o := mustStatus(t, call(t, b.token, "POST", "/v1/orders", map[string]any{
		"fulfillment": "delivery", "address_id": b.addressID, "promo_code": code,
	}), http.StatusCreated)
	oid := o.str("id")

	// Pas encore livrée : rien à noter.
	if r := mustStatus(t, call(t, b.token, "GET", "/v1/orders/"+oid+"/rating", nil), http.StatusOK); r.Body["can_rate"] != false {
		t.Fatalf("note avant livraison : %s", r.Raw)
	}
	if r := call(t, b.token, "POST", "/v1/orders/"+oid+"/rating", map[string]any{"stars": 5}); r.code() != "rating_not_available" {
		t.Fatalf("note avant livraison : %s", r.Raw)
	}

	pay(t, b, oid)
	for _, step := range []string{"accept", "preparing", "ready"} {
		mustStatus(t, call(t, s.token, "POST", "/v1/seller/orders/"+oid+"/"+step, map[string]any{}), http.StatusOK)
	}
	var offerID string
	eventually(t, "proposition au livreur", func() bool {
		r := call(t, d, "GET", "/v1/driver/offers/current", nil)
		if off, ok := r.Body["offer"].(map[string]any); ok {
			offerID, _ = off["id"].(string)
		}
		return offerID != ""
	})
	mid := mustStatus(t, call(t, d, "POST", "/v1/driver/offers/"+offerID+"/accept", map[string]any{}), http.StatusOK).str("id")

	// Position du livreur : visible sur la carte de la flotte avec sa mission, et dans son trajet.
	mustStatus(t, call(t, d, "POST", "/v1/driver/location", map[string]any{"lat": s.lat + 0.001, "lng": s.lng}), http.StatusNoContent)
	fleet := mustStatus(t, call(t, admin(t), "GET", "/v1/admin/fleet?hours=1", nil), http.StatusOK)
	var driverID string
	for _, it := range fleet.Body["items"].([]any) {
		if m := it.(map[string]any); m["mission_order_id"] == oid {
			driverID = m["id"].(string)
		}
	}
	if driverID == "" {
		t.Fatalf("livreur absent de la carte : %s", fleet.Raw)
	}
	trail := mustStatus(t, call(t, admin(t), "GET", "/v1/admin/fleet/"+driverID+"/trail", nil), http.StatusOK)
	if len(trail.Body["items"].([]any)) == 0 {
		t.Fatalf("trajet vide : %s", trail.Raw)
	}
	if r := call(t, b.token, "GET", "/v1/admin/fleet", nil); r.Status != http.StatusForbidden {
		t.Fatalf("carte réservée au back-office : %d", r.Status)
	}

	for _, step := range []string{"arrived-at-shop", "picked-up", "arrived-at-customer"} {
		mustStatus(t, call(t, d, "POST", "/v1/driver/missions/"+mid+"/"+step, map[string]any{}), http.StatusOK)
	}
	hc := mustStatus(t, call(t, b.token, "GET", "/v1/orders/"+oid, nil), http.StatusOK).str("handover_code")
	mustStatus(t, call(t, d, "POST", "/v1/driver/missions/"+mid+"/deliver", map[string]string{"code": hc}), http.StatusOK)

	// Avis du client (une fois), puis du marchand ; un autre client ne voit pas la commande.
	if r := mustStatus(t, call(t, b.token, "GET", "/v1/orders/"+oid+"/rating", nil), http.StatusOK); r.Body["can_rate"] != true {
		t.Fatalf("note après livraison : %s", r.Raw)
	}
	if r := call(t, b.token, "POST", "/v1/orders/"+oid+"/rating", map[string]any{"stars": 6}); r.Status != http.StatusBadRequest {
		t.Fatalf("6 étoiles : %d", r.Status)
	}
	rt := mustStatus(t, call(t, b.token, "POST", "/v1/orders/"+oid+"/rating", map[string]any{
		"stars": 5, "tags": []string{"rapide", "aimable", "inconnu"}, "comment": "Très bien",
	}), http.StatusCreated)
	if tags := rt.Body["tags"].([]any); len(tags) != 2 {
		t.Fatalf("tags inconnus ignorés : %s", rt.Raw)
	}
	if r := call(t, b.token, "POST", "/v1/orders/"+oid+"/rating", map[string]any{"stars": 4}); r.code() != "already_rated" {
		t.Fatalf("seconde note : %s", r.Raw)
	}
	other := newBuyer(t, s.lat, s.lng)
	if r := call(t, other.token, "POST", "/v1/orders/"+oid+"/rating", map[string]any{"stars": 1}); r.Status != http.StatusNotFound {
		t.Fatalf("commande d'un autre : %d", r.Status)
	}
	mustStatus(t, call(t, s.token, "POST", "/v1/seller/orders/"+oid+"/driver-rating", map[string]any{"stars": 3}), http.StatusCreated)
	own := mustStatus(t, call(t, d, "GET", "/v1/driver/rating", nil), http.StatusOK)
	if own.Body["ratings"].(float64) != 2 || own.Body["average"].(float64) != 4 {
		t.Fatalf("moyenne du livreur : %s", own.Raw)
	}
	mustStatus(t, call(t, b.token, "POST", "/v1/me/app-feedback", map[string]any{"app": "buyer", "stars": 5, "comment": "Super appli"}), http.StatusCreated)
	scores := mustStatus(t, call(t, admin(t), "GET", "/v1/admin/rating-scores", nil), http.StatusOK)
	if len(scores.Body["drivers"].([]any)) == 0 || len(scores.Body["apps"].([]any)) == 0 {
		t.Fatalf("moyennes : %s", scores.Raw)
	}

	// Relevé : 2 × 5 000 − 1 000 (code de la boutique) = 9 000 ; commission sur 9 000.
	final := mustStatus(t, call(t, b.token, "GET", "/v1/orders/"+oid, nil), http.StatusOK)
	today := final.str("completed_at")[:10]
	st := mustStatus(t, call(t, admin(t), "POST", "/v1/admin/settlements", map[string]string{
		"shop_id": s.shopID, "period_start": today, "period_end": today,
	}), http.StatusCreated)
	bp, com := orderCommission(t, oid)
	if st.Body["gross_xof"].(float64) != 9000 || int64(st.Body["commission_xof"].(float64)) != com || com != (9000*bp+5000)/10000 {
		t.Fatalf("relevé avec code de boutique : %s", st.Raw)
	}
}
