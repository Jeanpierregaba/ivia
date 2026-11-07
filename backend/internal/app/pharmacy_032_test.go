package app_test

import (
	"context"
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"testing"
)

// Spec 032 : numéro court d'alerte et quartier du client.
func TestPharmacyAlertNumberAndNeighborhood(t *testing.T) {
	requireApp(t)
	lat, lng := zone()
	ph, _ := newPharmacy(t, "Pharmacie du Numéro", lat, lng)
	b := newBuyer(t, lat, lng)
	hood := fmt.Sprintf("Quartier-%d", seq.Add(1))
	mustStatus(t, call(t, admin(t), "POST", "/v1/admin/neighborhoods", map[string]any{
		"name": hood, "city": "Lomé", "center": map[string]float64{"lat": lat + 0.003, "lng": lng},
	}), http.StatusCreated)

	alert := func(dLat float64) string {
		return mustStatus(t, call(t, b.token, "POST", "/v1/medicine-alerts", map[string]any{
			"items":    []map[string]any{{"name": "Paracétamol 1000 mg", "quantity": 1}},
			"radius_m": 5000, "location": map[string]float64{"lat": lat + dLat, "lng": lng},
		}), http.StatusCreated).str("number")
	}
	n1, n2 := alert(0.002), alert(0.002)
	parse := func(s string) int {
		if !strings.HasPrefix(s, "A-") {
			t.Fatalf("numéro d'alerte : %q", s)
		}
		v, err := strconv.Atoi(strings.TrimPrefix(s, "A-"))
		if err != nil {
			t.Fatalf("numéro d'alerte : %q", s)
		}
		return v
	}
	if parse(n2) != parse(n1)+1 {
		t.Fatalf("numéros non consécutifs : %s puis %s", n1, n2)
	}

	inbox := items(mustStatus(t, call(t, ph, "GET", "/v1/pharmacy/inbox", nil), http.StatusOK))
	if len(inbox) != 2 || inbox[0]["number"] != n2 || inbox[1]["number"] != n1 {
		t.Fatalf("numéros dans la boîte : %v", inbox)
	}
	if inbox[0]["client_neighborhood"] != hood {
		t.Fatalf("quartier du client : %v", inbox[0]["client_neighborhood"])
	}
	for _, forbidden := range []string{"location", "lat", "lng", "buyer_id"} {
		if _, ok := inbox[0][forbidden]; ok {
			t.Fatalf("position du client exposée : %s", forbidden)
		}
	}
	id := inbox[0]["alert_id"].(string)
	d := mustStatus(t, call(t, ph, "GET", "/v1/pharmacy/inbox/"+id, nil), http.StatusOK)
	if d.str("number") != n2 || d.str("client_neighborhood") != hood {
		t.Fatalf("détail : %v", d.Body)
	}
	if a := mustStatus(t, call(t, admin(t), "GET", "/v1/admin/medicine-alerts/"+id, nil), http.StatusOK); a.str("number") != n2 {
		t.Fatalf("numéro au back-office : %v", a.Body["number"])
	}

	// Loin de tout quartier connu : pas de quartier.
	// (dans le rayon de la pharmacie, à plus de 4 km du centre du quartier).
	far := alert(-0.04)
	found := false
	for _, it := range items(call(t, ph, "GET", "/v1/pharmacy/inbox", nil)) {
		if it["number"] == far {
			found = true
			if it["client_neighborhood"] != nil {
				t.Fatalf("quartier trop loin : %v", it["client_neighborhood"])
			}
		}
	}
	if !found {
		t.Fatal("alerte lointaine absente de la boîte")
	}
}

// Spec 032 : arrivée estimée du livreur et forfait remboursé, vus par la pharmacie.
func TestPharmacyReservationCourierEtaAndRefundFee(t *testing.T) {
	requireApp(t)
	d := deliveryAssigned(t, true)
	r := mustStatus(t, call(t, d.pharmacy, "GET", "/v1/pharmacy/reservations/"+d.reservationID, nil), http.StatusOK)
	if num(r.Body["refund_fee_xof"]) != 100 {
		t.Fatalf("forfait remboursé : %v", r.Body["refund_fee_xof"])
	}
	eta := func() any {
		r := mustStatus(t, call(t, d.pharmacy, "GET", "/v1/pharmacy/reservations/"+d.reservationID, nil), http.StatusOK)
		return r.Body["courier"].(map[string]any)["eta_minutes"]
	}
	near := num(eta())
	if near < 1 {
		t.Fatalf("arrivée estimée près de la pharmacie : %v", near)
	}
	mission, _ := mustStatus(t, call(t, d.driver, "GET", "/v1/driver/pharmacy-missions/current", nil), http.StatusOK).Body["mission"].(map[string]any)
	ph := mission["pharmacy"].(map[string]any)["location"].(map[string]any)
	mustStatus(t, call(t, d.driver, "POST", "/v1/driver/location", map[string]any{
		"lat": num(ph["lat"]) + 0.05, "lng": num(ph["lng"]),
	}), http.StatusNoContent)
	if far := num(eta()); far <= near {
		t.Fatalf("arrivée estimée plus loin : %v (près : %v)", far, near)
	}
	// Position trop ancienne : pas d'arrivée estimée.
	if _, err := testDB.Pool.Exec(context.Background(),
		`UPDATE drivers SET last_location_at = now() - interval '1 hour' WHERE user_id = (SELECT driver_id FROM pharmacy_deliveries WHERE id = $1)`,
		d.missionID); err != nil {
		t.Fatal(err)
	}
	if e := eta(); e != nil {
		t.Fatalf("arrivée avec une position ancienne : %v", e)
	}
	// Après la remise : plus d'arrivée estimée, heure de récupération connue.
	mustStatus(t, handover(t, d.pharmacy, d.reservationID, pickupCode(t, d.driver), true), http.StatusOK)
	r = mustStatus(t, call(t, d.pharmacy, "GET", "/v1/pharmacy/reservations/"+d.reservationID, nil), http.StatusOK)
	if r.Body["picked_up_at"] == nil || r.Body["courier"].(map[string]any)["eta_minutes"] != nil {
		t.Fatalf("après la remise : %v", r.Body)
	}
}

// Spec 032, ADR 0014 : dossier sans compte de versement, photo de la devanture.
func TestPharmacySubmitWithoutPayoutAndStorefront(t *testing.T) {
	requireApp(t)
	lat, lng := zone()
	tok := login(t, uniqueEmail("pharma"))
	completeProfile(t, tok, "Afi")
	mustStatus(t, call(t, tok, "POST", "/v1/pharmacy/application", map[string]any{
		"name": "Pharmacie Sans Compte", "license_number": "ORD-TG-0099", "phone": uniquePhone(), "email": uniqueEmail("officine"),
		"address_text": "Rue du Commerce", "location": map[string]float64{"lat": lat, "lng": lng},
	}), http.StatusCreated)
	if me := mustStatus(t, call(t, tok, "GET", "/v1/pharmacy/me", nil), http.StatusOK); me.Body["storefront_url"] != nil {
		t.Fatalf("devanture avant envoi : %v", me.Body["storefront_url"])
	}
	for _, kind := range []string{"opening_authorization", "owner_id", "storefront_photo"} {
		key := uploadPrivatePDF(t, tok, "pharmacy_document")
		mustStatus(t, call(t, tok, "POST", "/v1/pharmacy/me/documents", map[string]string{"kind": kind, "object_key": key}), http.StatusCreated)
	}
	me := mustStatus(t, call(t, tok, "GET", "/v1/pharmacy/me", nil), http.StatusOK)
	if u, _ := me.Body["storefront_url"].(string); u == "" {
		t.Fatalf("lien de la devanture : %v", me.Body["storefront_url"])
	}
	// Aucun compte de versement : l'envoi passe.
	if s := mustStatus(t, call(t, tok, "POST", "/v1/pharmacy/me/submit", nil), http.StatusOK).str("review_status"); s != "pending_review" {
		t.Fatalf("dossier envoyé sans compte : %s", s)
	}
}

// Spec 032 : encaissements (retrait au comptoir, livraison payée par le livreur) et chiffres du jour.
func TestPharmacyCashReceiptsAndToday(t *testing.T) {
	requireApp(t)
	d := deliveryAssigned(t, true)
	if x := call(t, d.pharmacy, "GET", "/v1/pharmacy/cash-receipts?days=0", nil); x.Status != http.StatusBadRequest {
		t.Fatalf("période invalide : %d", x.Status)
	}
	empty := mustStatus(t, call(t, d.pharmacy, "GET", "/v1/pharmacy/cash-receipts", nil), http.StatusOK)
	if len(list(empty.Body["days"])) != 0 || num(empty.Body["today_total_xof"]) != 0 {
		t.Fatalf("encaissements avant la remise : %v", empty.Body)
	}
	mustStatus(t, handover(t, d.pharmacy, d.reservationID, pickupCode(t, d.driver), true), http.StatusOK)

	c := mustStatus(t, call(t, d.pharmacy, "GET", "/v1/pharmacy/cash-receipts", nil), http.StatusOK)
	days := list(c.Body["days"])
	if len(days) != 1 || num(days[0]["total_xof"]) != d.itemsXOF || num(c.Body["today_total_xof"]) != d.itemsXOF || num(c.Body["week_total_xof"]) != d.itemsXOF {
		t.Fatalf("encaissements : %v", c.Body)
	}
	receipt := list(days[0]["receipts"])[0]
	if receipt["kind"] != "delivery" || receipt["reservation_id"] != d.reservationID || receipt["number"] == "" {
		t.Fatalf("encaissement de la livraison : %v", receipt)
	}

	today := mustStatus(t, call(t, d.pharmacy, "GET", "/v1/pharmacy/today", nil), http.StatusOK)
	if num(today.Body["received"]) != 1 || num(today.Body["responded"]) != 1 || num(today.Body["confirmed"]) != 1 {
		t.Fatalf("chiffres du jour : %v", today.Body)
	}
}
