package app_test

import (
	"context"
	"net/http"
	"testing"
)

// Spec 032, ADR 0014 : la pharmacie valide la remise au livreur avec son code de retrait et
// confirme qu'il l'a payée en espèces. Le livreur ne se déclare plus « récupéré » seul.

type assignedDelivery struct {
	pharmacy, pharmacyID string
	buyer                string
	driver               string
	reservationID        string
	missionID            string
	itemsXOF             float64
}

// deliveryAssigned mène une alerte jusqu'à la livraison payée, livreur en route vers la
// pharmacie (si paid) ; sinon, livreur trouvé, paiement du client attendu.
func deliveryAssigned(t *testing.T, paid bool) assignedDelivery {
	t.Helper()
	lat, lng := zone()
	ph, phID := newPharmacy(t, "Pharmacie de la Remise", lat, lng)
	b := newBuyer(t, lat, lng)
	alert := mustStatus(t, call(t, b.token, "POST", "/v1/medicine-alerts", map[string]any{
		"items":    []map[string]any{{"name": "Paracétamol 1000 mg", "quantity": 2}},
		"radius_m": 5000, "location": map[string]float64{"lat": lat + 0.002, "lng": lng},
	}), http.StatusCreated)
	alertID := alert.str("id")
	itemID := list(alert.Body["items"])[0]["id"]
	mustStatus(t, call(t, ph, "POST", "/v1/pharmacy/inbox/"+alertID+"/respond", map[string]any{
		"lines": []map[string]any{{"alert_item_id": itemID, "available": true, "unit_price_xof": 1500}},
	}), http.StatusOK)
	responseID := list(mustStatus(t, call(t, b.token, "GET", "/v1/medicine-alerts/"+alertID, nil), http.StatusOK).Body["responses"])[0]["id"].(string)
	_, resID := unlockResponse(t, b.token, alertID, responseID)
	driver := newDriver(t, lat+0.001, lng, "motorbike")
	mustStatus(t, call(t, b.token, "POST", "/v1/medicine-reservations/"+resID+"/delivery", map[string]string{"address_id": b.addressID}), http.StatusOK)
	missionID := acceptCourier(t, driver)
	if paid {
		p := mustStatus(t, call(t, b.token, "POST", "/v1/medicine-reservations/"+resID+"/pay", map[string]string{"operator": "flooz", "phone": uniquePhone()}), http.StatusOK)
		simulateMedicinePayment(t, b.token, p.str("id"))
		eventually(t, "livraison payée", func() bool {
			return call(t, b.token, "GET", "/v1/medicine-reservations/"+resID, nil).str("status") == "courier_assigned"
		})
	}
	return assignedDelivery{
		pharmacy: ph, pharmacyID: phID, buyer: b.token, driver: driver,
		reservationID: resID, missionID: missionID, itemsXOF: 3000,
	}
}

// pickupCode lit le code de retrait dans la mission en cours du livreur.
func pickupCode(t *testing.T, driver string) string {
	t.Helper()
	m, _ := mustStatus(t, call(t, driver, "GET", "/v1/driver/pharmacy-missions/current", nil), http.StatusOK).Body["mission"].(map[string]any)
	if m == nil {
		t.Fatal("pas de mission en cours")
	}
	code, _ := m["pickup_code"].(string)
	return code
}

func wrongCode(code string) string {
	if code == "0000" {
		return "1111"
	}
	return "0000"
}

func handover(t *testing.T, token, resID, code string, cash bool) resp {
	t.Helper()
	return call(t, token, "POST", "/v1/pharmacy/reservations/"+resID+"/courier-handover", map[string]any{
		"code": code, "cash_paid": cash,
	})
}

func TestPharmacyCourierHandover(t *testing.T) {
	requireApp(t)
	d := deliveryAssigned(t, true)

	// Le livreur voit son code ; la pharmacie, jamais.
	code := pickupCode(t, d.driver)
	if len(code) != 4 {
		t.Fatalf("code de retrait du livreur : %q", code)
	}
	r := mustStatus(t, call(t, d.pharmacy, "GET", "/v1/pharmacy/reservations/"+d.reservationID, nil), http.StatusOK)
	if _, ok := r.Body["pickup_code"]; ok {
		t.Fatal("code du livreur exposé à la pharmacie")
	}

	// Le livreur ne se déclare plus « récupéré » seul.
	if x := call(t, d.driver, "POST", "/v1/driver/pharmacy-missions/"+d.missionID+"/picked-up", nil); x.Status != http.StatusConflict || x.code() != "handover_by_pharmacy" {
		t.Fatalf("récupération déclarée par le livreur : %d %s", x.Status, x.code())
	}

	// Une autre pharmacie : 404.
	other, _ := newPharmacy(t, "Pharmacie Voisine", 1, 1)
	if x := handover(t, other, d.reservationID, code, true); x.Status != http.StatusNotFound {
		t.Fatalf("remise par une autre pharmacie : %d", x.Status)
	}
	// Paiement en espèces non confirmé : refus, rien ne change.
	if x := handover(t, d.pharmacy, d.reservationID, code, false); x.Status != http.StatusUnprocessableEntity || x.code() != "cash_not_confirmed" {
		t.Fatalf("remise sans paiement confirmé : %d %s", x.Status, x.code())
	}
	// Code faux : refus.
	if x := handover(t, d.pharmacy, d.reservationID, wrongCode(code), true); x.Status != http.StatusBadRequest {
		t.Fatalf("code faux : %d", x.Status)
	}
	if s := call(t, d.buyer, "GET", "/v1/medicine-reservations/"+d.reservationID, nil).str("status"); s != "courier_assigned" {
		t.Fatalf("statut après refus : %s", s)
	}

	// Bon code et espèces : commande récupérée, avance enregistrée.
	ok := mustStatus(t, handover(t, d.pharmacy, d.reservationID, code, true), http.StatusOK)
	if ok.str("status") != "picked_up" || ok.Body["picked_up_at"] == nil || num(ok.Body["cash_paid_xof"]) != d.itemsXOF {
		t.Fatalf("remise validée : %v", ok.Body)
	}
	if s := call(t, d.buyer, "GET", "/v1/medicine-reservations/"+d.reservationID, nil).str("status"); s != "picked_up" {
		t.Fatalf("statut côté client : %s", s)
	}
	m, _ := mustStatus(t, call(t, d.driver, "GET", "/v1/driver/pharmacy-missions/current", nil), http.StatusOK).Body["mission"].(map[string]any)
	if m == nil || m["status"] != "picked_up" || num(m["cash_advanced_xof"]) != d.itemsXOF {
		t.Fatalf("mission du livreur après la remise : %v", m)
	}
	if m["pickup_code"] != nil && m["pickup_code"] != "" {
		t.Fatalf("code encore montré après la remise : %v", m["pickup_code"])
	}

	// Une seule remise.
	if x := handover(t, d.pharmacy, d.reservationID, code, true); x.Status != http.StatusConflict {
		t.Fatalf("seconde remise : %d", x.Status)
	}
}

func TestPharmacyCourierHandoverLimitsAttempts(t *testing.T) {
	requireApp(t)
	d := deliveryAssigned(t, true)
	code := pickupCode(t, d.driver)
	for i := 0; i < 5; i++ {
		if x := handover(t, d.pharmacy, d.reservationID, wrongCode(code), true); x.Status != http.StatusBadRequest {
			t.Fatalf("essai faux %d : %d", i+1, x.Status)
		}
	}
	// Après 5 essais faux : bloqué, même avec le bon code.
	if x := handover(t, d.pharmacy, d.reservationID, code, true); x.Status != http.StatusTooManyRequests {
		t.Fatalf("après 5 essais faux : %d", x.Status)
	}
}

func TestPharmacyCourierHandoverRefusedBeforePayment(t *testing.T) {
	requireApp(t)
	d := deliveryAssigned(t, false)
	code := pickupCode(t, d.driver)
	if x := handover(t, d.pharmacy, d.reservationID, code, true); x.Status != http.StatusConflict || x.code() != "awaiting_payment" {
		t.Fatalf("remise avant le paiement du client : %d %s", x.Status, x.code())
	}
}

func TestPharmacyHandoverRefusedForPickup(t *testing.T) {
	requireApp(t)
	lat, lng := zone()
	ph, _ := newPharmacy(t, "Pharmacie du Comptoir", lat, lng)
	b := newBuyer(t, lat, lng)
	alert := mustStatus(t, call(t, b.token, "POST", "/v1/medicine-alerts", map[string]any{
		"items":    []map[string]any{{"name": "Doliprane 500 mg", "quantity": 1}},
		"radius_m": 5000, "location": map[string]float64{"lat": lat + 0.002, "lng": lng},
	}), http.StatusCreated)
	alertID := alert.str("id")
	mustStatus(t, call(t, ph, "POST", "/v1/pharmacy/inbox/"+alertID+"/respond", map[string]any{
		"lines": []map[string]any{{"alert_item_id": list(alert.Body["items"])[0]["id"], "available": true, "unit_price_xof": 900}},
	}), http.StatusOK)
	responseID := list(call(t, b.token, "GET", "/v1/medicine-alerts/"+alertID, nil).Body["responses"])[0]["id"].(string)
	_, resID := unlockResponse(t, b.token, alertID, responseID)
	if x := handover(t, ph, resID, "1234", true); x.Status != http.StatusConflict {
		t.Fatalf("remise au livreur d'un retrait : %d", x.Status)
	}
}

// Mission acceptée avant le changement (sans code) : le livreur garde l'ancien « Récupéré ».
func TestPharmacyLegacyMissionWithoutCode(t *testing.T) {
	requireApp(t)
	d := deliveryAssigned(t, true)
	if _, err := testDB.Pool.Exec(context.Background(),
		`UPDATE pharmacy_deliveries SET pickup_code = NULL WHERE id = $1`, d.missionID); err != nil {
		t.Fatal(err)
	}
	if c := pickupCode(t, d.driver); c != "" {
		t.Fatalf("code d'une ancienne mission : %q", c)
	}
	mustStatus(t, call(t, d.driver, "POST", "/v1/driver/pharmacy-missions/"+d.missionID+"/picked-up", nil), http.StatusOK)
}
