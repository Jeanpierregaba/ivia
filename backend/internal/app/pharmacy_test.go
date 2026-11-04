package app_test

import (
	"bytes"
	"net/http"
	"testing"
)

// newPharmacy inscrit une pharmacie au point donné, dépose les trois pièces, la fait valider et
// l'ouvre. Retourne le jeton du titulaire et l'identifiant de la pharmacie.
func newPharmacy(t *testing.T, name string, lat, lng float64) (string, string) {
	t.Helper()
	tok := login(t, uniqueEmail("pharma"))
	completeProfile(t, tok, "Essi")
	p := mustStatus(t, call(t, tok, "POST", "/v1/pharmacy/application", map[string]any{
		"name": name, "license_number": "ORD-TG-0042", "phone": uniquePhone(), "address_text": "Boulevard du 13 janvier",
		"location": map[string]float64{"lat": lat, "lng": lng}, "opening_hours": "Lun-Sam 8h-21h",
	}), http.StatusCreated)
	id := p.str("id")
	// Validation refusée sans les pièces.
	if r := call(t, admin(t), "POST", "/v1/admin/pharmacies/"+id+"/review", map[string]string{"decision": "approve"}); r.code() != "documents_missing" {
		t.Fatalf("validation sans pièces : %d %s", r.Status, r.code())
	}
	for _, kind := range []string{"opening_authorization", "order_registration", "owner_id"} {
		key := uploadPrivatePDF(t, tok, "pharmacy_document")
		mustStatus(t, call(t, tok, "POST", "/v1/pharmacy/me/documents", map[string]string{"kind": kind, "object_key": key}), http.StatusCreated)
	}
	// Avant validation : pas d'accès aux alertes.
	if r := call(t, tok, "GET", "/v1/pharmacy/inbox", nil); r.Status != http.StatusForbidden {
		t.Fatalf("boîte avant validation : %d", r.Status)
	}
	a := mustStatus(t, call(t, admin(t), "POST", "/v1/admin/pharmacies/"+id+"/review", map[string]string{"decision": "approve"}), http.StatusOK)
	if a.str("status") != "approved" {
		t.Fatalf("statut après validation : %s", a.str("status"))
	}
	mustStatus(t, call(t, tok, "PUT", "/v1/pharmacy/me/status", map[string]bool{"is_open": true, "on_duty": false}), http.StatusOK)
	return tok, id
}

// uploadAlertPhoto envoie une photo (ordonnance ou boîte) par URL signée, comme l'app acheteur.
func uploadAlertPhoto(t *testing.T, token string) string {
	t.Helper()
	content := []byte("\xff\xd8\xff photo de test")
	up := mustStatus(t, call(t, token, "POST", "/v1/uploads", map[string]any{
		"purpose": "pharmacy_alert_photo", "content_type": "image/jpeg", "size_bytes": len(content),
	}), http.StatusCreated)
	signed := up.Body["upload"].(map[string]any)
	req, _ := http.NewRequest(http.MethodPut, signed["url"].(string), bytes.NewReader(content))
	req.Header.Set("Content-Type", "image/jpeg")
	res, err := http.DefaultClient.Do(req)
	if err != nil || res.StatusCode != http.StatusOK {
		t.Fatalf("envoi de la photo : %v %v", err, res)
	}
	res.Body.Close()
	return up.str("object_key")
}

func simulateMedicinePayment(t *testing.T, token, paymentID string) {
	t.Helper()
	mustStatus(t, call(t, token, "POST", "/v1/dev/medicine-payments/"+paymentID+"/simulate", map[string]string{"outcome": "succeeded"}), http.StatusOK)
}

func items(r resp) []map[string]any {
	raw, _ := r.Body["items"].([]any)
	out := make([]map[string]any, len(raw))
	for i, v := range raw {
		out[i] = v.(map[string]any)
	}
	return out
}

func TestPharmacyAlertDeliveryFlow(t *testing.T) {
	requireApp(t)
	lat, lng := zone()
	ph1, ph1ID := newPharmacy(t, "Pharmacie du Grand Marché", lat, lng)
	ph2, _ := newPharmacy(t, "Pharmacie de la Lagune", lat+0.01, lng)
	b := newBuyer(t, lat, lng)

	alert := mustStatus(t, call(t, b.token, "POST", "/v1/medicine-alerts", map[string]any{
		"kind": "name", "medicine_name": "Paracétamol 1 g", "quantity": 2,
		"location": map[string]float64{"lat": lat + 0.002, "lng": lng},
	}), http.StatusCreated)
	alertID := alert.str("id")
	if alert.str("status") != "searching" || alert.Body["pharmacies_notified"].(float64) != 2 {
		t.Fatalf("alerte : %v", alert.Body)
	}

	// La pharmacie voit l'alerte, jamais le client.
	inbox := items(mustStatus(t, call(t, ph1, "GET", "/v1/pharmacy/inbox", nil), http.StatusOK))
	if len(inbox) != 1 || inbox[0]["alert_id"] != alertID || inbox[0]["medicine_name"] != "Paracétamol 1 g" {
		t.Fatalf("boîte de la pharmacie : %v", inbox)
	}
	for _, forbidden := range []string{"buyer_id", "location", "buyer_first_name"} {
		if _, ok := inbox[0][forbidden]; ok {
			t.Fatalf("donnée du client exposée à la pharmacie : %s", forbidden)
		}
	}
	mustStatus(t, call(t, ph1, "POST", "/v1/pharmacy/inbox/"+alertID+"/respond", map[string]any{
		"product_name": "Doliprane 1000 mg", "unit_price_xof": 1500, "quantity_available": 10, "note": "Boîte de 8",
	}), http.StatusOK)
	mustStatus(t, call(t, ph2, "POST", "/v1/pharmacy/inbox/"+alertID+"/decline", nil), http.StatusOK)

	// Avant déblocage : réponse visible, pharmacie masquée.
	a := mustStatus(t, call(t, b.token, "GET", "/v1/medicine-alerts/"+alertID, nil), http.StatusOK)
	responses := a.Body["responses"].([]any)
	first := responses[0].(map[string]any)
	if len(responses) != 1 || first["pharmacy"] != nil || first["label"] != "Pharmacie 1" || first["note"] != "" {
		t.Fatalf("réponse non masquée : %v", first)
	}
	if first["delivery_allowed"] != true || first["unit_price_xof"].(float64) != 1500 {
		t.Fatalf("réponse : %v", first)
	}
	responseID := first["id"].(string)
	if r := call(t, b.token, "POST", "/v1/medicine-alerts/"+alertID+"/reservations", map[string]any{"response_id": responseID, "fulfillment": "pickup"}); r.code() != "unlock_required" {
		t.Fatalf("réservation sans déblocage : %d %s", r.Status, r.code())
	}

	// Déblocage forfaitaire (100 F), validé par le prestataire.
	u := mustStatus(t, call(t, b.token, "POST", "/v1/medicine-alerts/"+alertID+"/unlock", map[string]string{"operator": "tmoney", "phone": uniquePhone()}), http.StatusOK)
	pay := u.Body["payment"].(map[string]any)
	if pay["amount_xof"].(float64) != 100 || pay["status"] != "pending" {
		t.Fatalf("paiement du déblocage : %v", pay)
	}
	simulateMedicinePayment(t, b.token, pay["id"].(string))
	eventually(t, "alerte débloquée", func() bool {
		return call(t, b.token, "GET", "/v1/medicine-alerts/"+alertID, nil).Body["unlocked"] == true
	})
	a = mustStatus(t, call(t, b.token, "GET", "/v1/medicine-alerts/"+alertID, nil), http.StatusOK)
	contact := a.Body["responses"].([]any)[0].(map[string]any)["pharmacy"].(map[string]any)
	if contact["name"] != "Pharmacie du Grand Marché" || contact["id"] != ph1ID {
		t.Fatalf("pharmacie après déblocage : %v", contact)
	}

	// Livraison : frais calculés, paiement dans l'app.
	res := mustStatus(t, call(t, b.token, "POST", "/v1/medicine-alerts/"+alertID+"/reservations", map[string]any{
		"response_id": responseID, "fulfillment": "delivery", "address_id": b.addressID,
	}), http.StatusCreated)
	resID := res.str("id")
	fee := res.Body["delivery_fee_xof"].(float64)
	if res.str("status") != "awaiting_payment" || res.Body["items_xof"].(float64) != 3000 || fee <= 0 ||
		res.Body["total_xof"].(float64) != 3000+fee || res.str("handover_code") != "" {
		t.Fatalf("réservation : %v", res.Body)
	}
	if r := call(t, b.token, "POST", "/v1/medicine-alerts/"+alertID+"/reservations", map[string]any{"response_id": responseID, "fulfillment": "pickup"}); r.code() != "reservation_exists" {
		t.Fatalf("seconde réservation : %d %s", r.Status, r.code())
	}

	driver := newDriver(t, lat+0.001, lng, "motorbike")
	p := mustStatus(t, call(t, b.token, "POST", "/v1/medicine-reservations/"+resID+"/pay", map[string]string{"operator": "flooz", "phone": uniquePhone()}), http.StatusOK)
	if p.Body["amount_xof"].(float64) != 3000+fee {
		t.Fatalf("montant payé : %v", p.Body)
	}
	simulateMedicinePayment(t, b.token, p.str("id"))

	var offerID string
	eventually(t, "proposition de course", func() bool {
		o, _ := call(t, driver, "GET", "/v1/driver/pharmacy-offers/current", nil).Body["offer"].(map[string]any)
		if o != nil {
			offerID = o["id"].(string)
		}
		return offerID != ""
	})
	m := mustStatus(t, call(t, driver, "POST", "/v1/driver/pharmacy-offers/"+offerID+"/accept", nil), http.StatusOK)
	missionID := m.str("id")
	if m.str("status") != "assigned" || m.Body["client"] == nil {
		t.Fatalf("course : %v", m.Body)
	}
	if av := mustStatus(t, call(t, driver, "GET", "/v1/driver/me", nil), http.StatusOK).str("availability"); av != "busy" {
		t.Fatalf("livreur pendant la course : %s", av)
	}
	r := mustStatus(t, call(t, b.token, "GET", "/v1/medicine-reservations/"+resID, nil), http.StatusOK)
	code := r.str("handover_code")
	if r.str("status") != "courier_assigned" || r.Body["courier"] == nil || len(code) != 6 {
		t.Fatalf("réservation avec livreur : %v", r.Body)
	}
	// Remise impossible avant la récupération ou avec un mauvais code.
	if x := call(t, driver, "POST", "/v1/driver/pharmacy-missions/"+missionID+"/delivered", map[string]string{"code": code}); x.code() != "invalid_transition" {
		t.Fatalf("remise avant récupération : %d %s", x.Status, x.code())
	}
	mustStatus(t, call(t, driver, "POST", "/v1/driver/pharmacy-missions/"+missionID+"/picked-up", nil), http.StatusOK)
	wrong := "000000"
	if code == wrong {
		wrong = "111111"
	}
	mustStatus(t, call(t, driver, "POST", "/v1/driver/pharmacy-missions/"+missionID+"/delivered", map[string]string{"code": wrong}), http.StatusBadRequest)
	done := mustStatus(t, call(t, driver, "POST", "/v1/driver/pharmacy-missions/"+missionID+"/delivered", map[string]string{"code": code}), http.StatusOK)
	if done.str("status") != "delivered" || done.Body["client"] != nil {
		t.Fatalf("course terminée : %v", done.Body)
	}
	if av := mustStatus(t, call(t, driver, "GET", "/v1/driver/me", nil), http.StatusOK).str("availability"); av != "available" {
		t.Fatalf("livreur après la course : %s", av)
	}
	if s := mustStatus(t, call(t, b.token, "GET", "/v1/medicine-alerts/"+alertID, nil), http.StatusOK).str("status"); s != "fulfilled" {
		t.Fatalf("alerte après livraison : %s", s)
	}

	// La pharmacie est créditée du médicament moins la commission, puis reversée par l'admin.
	e := mustStatus(t, call(t, ph1, "GET", "/v1/pharmacy/earnings", nil), http.StatusOK)
	due := e.Body["balance_xof"].(float64)
	if due <= 0 || due >= 3000 || e.Body["delivered_count"].(float64) != 1 {
		t.Fatalf("solde de la pharmacie : %v", e.Body)
	}
	if x := call(t, admin(t), "POST", "/v1/admin/pharmacies/"+ph1ID+"/payouts", map[string]any{"amount_xof": due + 1, "reference": "TMONEY-1"}); x.code() != "amount_exceeds_balance" {
		t.Fatalf("reversement trop élevé : %d %s", x.Status, x.code())
	}
	e = mustStatus(t, call(t, admin(t), "POST", "/v1/admin/pharmacies/"+ph1ID+"/payouts", map[string]any{"amount_xof": due, "reference": "TMONEY-1"}), http.StatusCreated)
	if e.Body["balance_xof"].(float64) != 0 {
		t.Fatalf("solde après reversement : %v", e.Body)
	}
}

func TestPharmacyPrescriptionIsPickupOnly(t *testing.T) {
	requireApp(t)
	lat, lng := zone()
	ph, _ := newPharmacy(t, "Pharmacie Bon Secours", lat, lng)
	b := newBuyer(t, lat, lng)

	// Photo obligatoire pour une ordonnance.
	if r := call(t, b.token, "POST", "/v1/medicine-alerts", map[string]any{
		"kind": "prescription", "location": map[string]float64{"lat": lat, "lng": lng},
	}); r.Status != http.StatusBadRequest {
		t.Fatalf("ordonnance sans photo : %d", r.Status)
	}
	alert := mustStatus(t, call(t, b.token, "POST", "/v1/medicine-alerts", map[string]any{
		"kind": "prescription", "photo_key": uploadAlertPhoto(t, b.token), "address_id": b.addressID,
	}), http.StatusCreated)
	alertID := alert.str("id")

	item := mustStatus(t, call(t, ph, "GET", "/v1/pharmacy/inbox/"+alertID, nil), http.StatusOK)
	if item.str("photo_url") == "" || item.Body["has_photo"] != true {
		t.Fatalf("photo de l'ordonnance pour la pharmacie : %v", item.Body)
	}
	mustStatus(t, call(t, ph, "POST", "/v1/pharmacy/inbox/"+alertID+"/respond", map[string]any{
		"product_name": "Amoxicilline 500 mg", "unit_price_xof": 2500, "quantity_available": 3, "prescription_required": true,
	}), http.StatusOK)
	a := mustStatus(t, call(t, b.token, "GET", "/v1/medicine-alerts/"+alertID, nil), http.StatusOK)
	first := a.Body["responses"].([]any)[0].(map[string]any)
	if first["delivery_allowed"] != false {
		t.Fatalf("livraison proposée sur ordonnance : %v", first)
	}
	u := mustStatus(t, call(t, b.token, "POST", "/v1/medicine-alerts/"+alertID+"/unlock", map[string]string{"operator": "flooz", "phone": uniquePhone()}), http.StatusOK)
	simulateMedicinePayment(t, b.token, u.Body["payment"].(map[string]any)["id"].(string))
	eventually(t, "alerte débloquée", func() bool {
		return call(t, b.token, "GET", "/v1/medicine-alerts/"+alertID, nil).Body["unlocked"] == true
	})

	responseID := first["id"].(string)
	if r := call(t, b.token, "POST", "/v1/medicine-alerts/"+alertID+"/reservations", map[string]any{
		"response_id": responseID, "fulfillment": "delivery", "address_id": b.addressID,
	}); r.code() != "prescription_pickup_only" {
		t.Fatalf("livraison sur ordonnance : %d %s", r.Status, r.code())
	}
	res := mustStatus(t, call(t, b.token, "POST", "/v1/medicine-alerts/"+alertID+"/reservations", map[string]any{
		"response_id": responseID, "fulfillment": "pickup",
	}), http.StatusCreated)
	code := res.str("handover_code")
	if res.str("status") != "reserved" || len(code) != 6 || res.Body["pay_in_app"] != false || res.Body["delivery_fee_xof"].(float64) != 0 {
		t.Fatalf("retrait : %v", res.Body)
	}
	// La pharmacie voit le prénom du client, jamais son code.
	pr := mustStatus(t, call(t, ph, "GET", "/v1/pharmacy/reservations/"+res.str("id"), nil), http.StatusOK)
	if pr.str("buyer_first_name") != "Kossi" || pr.str("handover_code") != "" {
		t.Fatalf("réservation vue par la pharmacie : %v", pr.Body)
	}
	mustStatus(t, call(t, ph, "POST", "/v1/pharmacy/reservations/"+res.str("id")+"/complete", map[string]string{"code": code}), http.StatusOK)
	if s := mustStatus(t, call(t, b.token, "GET", "/v1/medicine-reservations/"+res.str("id"), nil), http.StatusOK).str("status"); s != "completed" {
		t.Fatalf("retrait terminé : %s", s)
	}
	if e := mustStatus(t, call(t, ph, "GET", "/v1/pharmacy/earnings", nil), http.StatusOK); e.Body["pickup_count"].(float64) != 1 || e.Body["due_xof"].(float64) != 0 {
		t.Fatalf("retrait payé sur place, rien à reverser : %v", e.Body)
	}
}

func TestPharmacyNoResponseAndCancelRefund(t *testing.T) {
	requireApp(t)
	lat, lng := zone()
	ph, _ := newPharmacy(t, "Pharmacie Espoir", lat, lng)
	b := newBuyer(t, lat, lng)
	alert := mustStatus(t, call(t, b.token, "POST", "/v1/medicine-alerts", map[string]any{
		"kind": "box_photo", "medicine_name": "Ventoline", "photo_key": uploadAlertPhoto(t, b.token),
		"location": map[string]float64{"lat": lat, "lng": lng},
	}), http.StatusCreated)
	alertID := alert.str("id")
	// Déblocage inutile tant que personne n'a répondu.
	if r := call(t, b.token, "POST", "/v1/medicine-alerts/"+alertID+"/unlock", map[string]string{"operator": "flooz", "phone": uniquePhone()}); r.code() != "no_response_yet" {
		t.Fatalf("déblocage sans réponse : %d %s", r.Status, r.code())
	}
	mustStatus(t, call(t, ph, "POST", "/v1/pharmacy/inbox/"+alertID+"/respond", map[string]any{
		"product_name": "Ventoline 100 µg", "unit_price_xof": 3200, "quantity_available": 2,
	}), http.StatusOK)
	u := mustStatus(t, call(t, b.token, "POST", "/v1/medicine-alerts/"+alertID+"/unlock", map[string]string{"operator": "flooz", "phone": uniquePhone()}), http.StatusOK)
	simulateMedicinePayment(t, b.token, u.Body["payment"].(map[string]any)["id"].(string))
	eventually(t, "alerte débloquée", func() bool {
		return call(t, b.token, "GET", "/v1/medicine-alerts/"+alertID, nil).Body["unlocked"] == true
	})
	responseID := mustStatus(t, call(t, b.token, "GET", "/v1/medicine-alerts/"+alertID, nil), http.StatusOK).
		Body["responses"].([]any)[0].(map[string]any)["id"].(string)

	// Livraison payée puis annulée par la pharmacie : remboursement automatique.
	res := mustStatus(t, call(t, b.token, "POST", "/v1/medicine-alerts/"+alertID+"/reservations", map[string]any{
		"response_id": responseID, "fulfillment": "delivery", "address_id": b.addressID,
	}), http.StatusCreated)
	p := mustStatus(t, call(t, b.token, "POST", "/v1/medicine-reservations/"+res.str("id")+"/pay", map[string]string{"operator": "flooz", "phone": uniquePhone()}), http.StatusOK)
	simulateMedicinePayment(t, b.token, p.str("id"))
	eventually(t, "réservation payée", func() bool {
		return call(t, b.token, "GET", "/v1/medicine-reservations/"+res.str("id"), nil).str("status") == "paid"
	})
	mustStatus(t, call(t, ph, "POST", "/v1/pharmacy/reservations/"+res.str("id")+"/cancel", map[string]string{"reason": "Rupture de stock"}), http.StatusOK)
	eventually(t, "paiement remboursé", func() bool {
		return call(t, b.token, "GET", "/v1/medicine-payments/"+p.str("id"), nil).str("status") == "refunded"
	})
	a := mustStatus(t, call(t, b.token, "GET", "/v1/medicine-alerts/"+alertID, nil), http.StatusOK)
	if a.Body["responses"].([]any)[0].(map[string]any)["status"] != "withdrawn" {
		t.Fatalf("réponse retirée après rupture : %v", a.Body["responses"])
	}
	mustStatus(t, call(t, b.token, "POST", "/v1/medicine-alerts/"+alertID+"/cancel", nil), http.StatusOK)
}
