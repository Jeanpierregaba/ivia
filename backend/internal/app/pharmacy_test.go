package app_test

import (
	"bytes"
	"fmt"
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
		"name": name, "license_number": "ORD-TG-0042", "phone": uniquePhone(), "email": uniqueEmail("officine"), "address_text": "Boulevard du 13 janvier",
		"location": map[string]float64{"lat": lat, "lng": lng}, "opening_hours": "Lun-Sam 8h-21h",
	}), http.StatusCreated)
	id := p.str("id")
	// Validation refusée sans les pièces.
	if r := call(t, admin(t), "POST", "/v1/admin/pharmacies/"+id+"/review", map[string]string{"decision": "approve"}); r.code() != "documents_missing" {
		t.Fatalf("validation sans pièces : %d %s", r.Status, r.code())
	}
	for _, kind := range []string{"opening_authorization", "owner_id", "storefront_photo"} {
		key := uploadPrivatePDF(t, tok, "pharmacy_document")
		mustStatus(t, call(t, tok, "POST", "/v1/pharmacy/me/documents", map[string]string{"kind": kind, "object_key": key}), http.StatusCreated)
	}
	mustStatus(t, call(t, tok, "PUT", "/v1/pharmacy/me/payout", map[string]string{"operator": "flooz", "phone": uniquePhone(), "holder": "Essi Mensah"}), http.StatusOK)
	mustStatus(t, call(t, tok, "POST", "/v1/pharmacy/me/submit", nil), http.StatusOK)
	// Les tests ne dépendent pas de l'heure : pas de restriction de nuit.
	mustStatus(t, call(t, admin(t), "PUT", "/v1/admin/pharmacy/settings", map[string]any{"night_from_hour": 0, "night_to_hour": 0}), http.StatusOK)
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

func list(v any) []map[string]any {
	raw, _ := v.([]any)
	out := make([]map[string]any, len(raw))
	for i, x := range raw {
		out[i] = x.(map[string]any)
	}
	return out
}

func num(v any) float64 { f, _ := v.(float64); return f }

// unlockResponse paie le forfait pour une réponse et attend la mise de côté.
func unlockResponse(t *testing.T, token, alertID, responseID string) (paymentID, reservationID string) {
	t.Helper()
	u := mustStatus(t, call(t, token, "POST", "/v1/medicine-alerts/"+alertID+"/responses/"+responseID+"/unlock",
		map[string]string{"operator": "tmoney", "phone": uniquePhone()}), http.StatusOK)
	pay := u.Body["payment"].(map[string]any)
	if num(pay["amount_xof"]) != 100 || pay["status"] != "pending" {
		t.Fatalf("paiement du déblocage : %v", pay)
	}
	simulateMedicinePayment(t, token, pay["id"].(string))
	eventually(t, "pharmacie débloquée", func() bool {
		for _, r := range list(call(t, token, "GET", "/v1/medicine-alerts/"+alertID, nil).Body["responses"]) {
			if r["id"] == responseID && r["unlocked"] == true && r["reservation_id"] != nil {
				reservationID = r["reservation_id"].(string)
				return true
			}
		}
		return false
	})
	return pay["id"].(string), reservationID
}

// acceptCourier attend la proposition de course du livreur et l'accepte.
func acceptCourier(t *testing.T, driver string) string {
	t.Helper()
	var offerID string
	eventually(t, "proposition de course", func() bool {
		o, _ := call(t, driver, "GET", "/v1/driver/pharmacy-offers/current", nil).Body["offer"].(map[string]any)
		if o != nil {
			offerID = o["id"].(string)
		}
		return offerID != ""
	})
	return mustStatus(t, call(t, driver, "POST", "/v1/driver/pharmacy-offers/"+offerID+"/accept", nil), http.StatusOK).str("id")
}

func TestPharmacyAlertDeliveryFlow(t *testing.T) {
	requireApp(t)
	lat, lng := zone()
	ph1, ph1ID := newPharmacy(t, "Pharmacie du Grand Marché", lat, lng)
	ph2, _ := newPharmacy(t, "Pharmacie de la Lagune", lat+0.01, lng)
	b := newBuyer(t, lat, lng)

	// P03 : suggestions de la base des médicaments.
	meds := items(mustStatus(t, call(t, b.token, "GET", "/v1/medicines?q=amoxi", nil), http.StatusOK))
	if len(meds) == 0 || meds[0]["form"] == "" {
		t.Fatalf("suggestions : %v", meds)
	}
	var amoxID string
	for _, m := range meds {
		if m["label"] == "Amoxicilline 500 mg" {
			amoxID = m["id"].(string)
		}
	}
	// P06 : pharmacies de garde jointes par rayon.
	pv := mustStatus(t, call(t, b.token, "GET", "/v1/medicine-alerts/preview?address_id="+b.addressID, nil), http.StatusOK)
	if num(pv.Body["default_radius_m"]) != 5000 || num(pv.Body["unlock_fee_xof"]) != 100 || len(list(pv.Body["radii"])) != 3 {
		t.Fatalf("aperçu : %v", pv.Body)
	}
	// Liste publique des pharmacies de garde (accueil, « De garde maintenant »).
	duty := items(mustStatus(t, call(t, "", "GET", fmt.Sprintf("/v1/pharmacies/on-duty?lat=%f&lng=%f&radius_m=2000", lat, lng), nil), http.StatusOK))
	if len(duty) == 0 || duty[0]["id"] != ph1ID || duty[0]["phone"] == "" {
		t.Fatalf("pharmacies de garde : %v", duty)
	}

	alert := mustStatus(t, call(t, b.token, "POST", "/v1/medicine-alerts", map[string]any{
		"items": []map[string]any{
			{"name": "Paracétamol 1000 mg", "form": "Comprimés", "quantity": 1},
			{"medicine_id": amoxID, "quantity": 2},
		},
		"generic_accepted": true, "radius_m": 5000, "location": map[string]float64{"lat": lat + 0.002, "lng": lng},
	}), http.StatusCreated)
	alertID := alert.str("id")
	stats := alert.Body["stats"].(map[string]any)
	alertItems := list(alert.Body["items"])
	if alert.str("status") != "searching" || num(stats["notified"]) != 2 || len(alertItems) != 2 || alertItems[1]["name"] != "Amoxicilline 500 mg" {
		t.Fatalf("alerte : %v", alert.Body)
	}

	// La pharmacie voit l'alerte (produits), jamais le client ; ouvrir l'alerte la compte « vue ».
	inbox := items(mustStatus(t, call(t, ph1, "GET", "/v1/pharmacy/inbox", nil), http.StatusOK))
	if len(inbox) != 1 || inbox[0]["alert_id"] != alertID || len(list(inbox[0]["items"])) != 2 || inbox[0]["generic_accepted"] != true {
		t.Fatalf("boîte de la pharmacie : %v", inbox)
	}
	for _, forbidden := range []string{"buyer_id", "location", "buyer_first_name"} {
		if _, ok := inbox[0][forbidden]; ok {
			t.Fatalf("donnée du client exposée à la pharmacie : %s", forbidden)
		}
	}
	mustStatus(t, call(t, ph1, "GET", "/v1/pharmacy/inbox/"+alertID, nil), http.StatusOK)
	if s := mustStatus(t, call(t, b.token, "GET", "/v1/medicine-alerts/"+alertID, nil), http.StatusOK).Body["stats"].(map[string]any); num(s["seen"]) != 1 {
		t.Fatalf("pharmacies qui ont vu : %v", s)
	}

	// Réponses ligne par ligne.
	if r := call(t, ph1, "POST", "/v1/pharmacy/inbox/"+alertID+"/respond", map[string]any{
		"lines": []map[string]any{{"alert_item_id": alertItems[0]["id"], "available": false}},
	}); r.Status != http.StatusBadRequest {
		t.Fatalf("réponse sans produit disponible : %d", r.Status)
	}
	mustStatus(t, call(t, ph1, "POST", "/v1/pharmacy/inbox/"+alertID+"/respond", map[string]any{
		"lines": []map[string]any{
			{"alert_item_id": alertItems[0]["id"], "available": true, "unit_price_xof": 1250},
			{"alert_item_id": alertItems[1]["id"], "available": true, "unit_price_xof": 3100},
		},
		"note": "Générique Biogaran",
	}), http.StatusOK)
	mustStatus(t, call(t, ph2, "POST", "/v1/pharmacy/inbox/"+alertID+"/respond", map[string]any{
		"lines": []map[string]any{
			{"alert_item_id": alertItems[0]["id"], "available": true, "unit_price_xof": 1200},
			{"alert_item_id": alertItems[1]["id"], "available": false},
		},
	}), http.StatusOK)

	// P08 : réponses anonymes, classées par distance.
	a := mustStatus(t, call(t, b.token, "GET", "/v1/medicine-alerts/"+alertID, nil), http.StatusOK)
	responses := list(a.Body["responses"])
	first, second := responses[0], responses[1]
	if len(responses) != 2 || first["pharmacy"] != nil || first["label"] != "Pharmacie 1" || first["note"] != "" {
		t.Fatalf("réponse non masquée : %v", first)
	}
	if first["all_available"] != true || num(first["total_xof"]) != 7450 || second["all_available"] != false || num(second["available_count"]) != 1 {
		t.Fatalf("réponses : %v", responses)
	}
	if num(list(first["lines"])[1]["line_total_xof"]) != 6200 {
		t.Fatalf("lignes : %v", first["lines"])
	}

	// P09 : le forfait débloque UNE pharmacie et met ses produits de côté.
	_, resID := unlockResponse(t, b.token, alertID, first["id"].(string))
	a = mustStatus(t, call(t, b.token, "GET", "/v1/medicine-alerts/"+alertID, nil), http.StatusOK)
	responses = list(a.Body["responses"])
	contact := responses[0]["pharmacy"].(map[string]any)
	if contact["name"] != "Pharmacie du Grand Marché" || contact["id"] != ph1ID || responses[1]["pharmacy"] != nil {
		t.Fatalf("déblocage d'une seule pharmacie : %v", responses)
	}
	if r := call(t, b.token, "POST", "/v1/medicine-alerts/"+alertID+"/responses/"+first["id"].(string)+"/unlock", map[string]string{"operator": "tmoney", "phone": uniquePhone()}); r.code() != "already_unlocked" {
		t.Fatalf("second déblocage : %d %s", r.Status, r.code())
	}

	// Débloquer une autre pharmacie se paie à nouveau ; retrait sur place avec le code.
	_, res2ID := unlockResponse(t, b.token, alertID, second["id"].(string))
	r2 := mustStatus(t, call(t, b.token, "GET", "/v1/medicine-reservations/"+res2ID, nil), http.StatusOK)
	if num(r2.Body["items_xof"]) != 1200 || r2.Body["pay_in_app"] != false {
		t.Fatalf("seconde pharmacie : %v", r2.Body)
	}
	mustStatus(t, call(t, ph2, "POST", "/v1/pharmacy/reservations/"+res2ID+"/complete", map[string]string{"code": r2.str("handover_code")}), http.StatusOK)
	if e := mustStatus(t, call(t, ph2, "GET", "/v1/pharmacy/earnings", nil), http.StatusOK); num(e.Body["pickup_count"]) != 1 || num(e.Body["due_xof"]) != 0 {
		t.Fatalf("retrait payé sur place : %v", e.Body)
	}

	// P10 : produits mis de côté, code de retrait à 4 chiffres.
	res := mustStatus(t, call(t, b.token, "GET", "/v1/medicine-reservations/"+resID, nil), http.StatusOK)
	if res.str("status") != "reserved" || len(res.str("handover_code")) != 4 || num(res.Body["items_xof"]) != 7450 ||
		res.Body["expires_at"] == nil || res.str("number") == "" {
		t.Fatalf("mise de côté : %v", res.Body)
	}
	q := mustStatus(t, call(t, b.token, "GET", "/v1/medicine-reservations/"+resID+"/delivery-quote?address_id="+b.addressID, nil), http.StatusOK)
	fee := num(q.Body["delivery_fee_xof"])
	if fee <= 0 || num(q.Body["total_xof"]) != 7450+fee || num(q.Body["eta_minutes"]) <= 0 {
		t.Fatalf("devis de livraison : %v", q.Body)
	}

	// « Livreur ivia » : recherche immédiate, paiement une fois le livreur trouvé.
	driver := newDriver(t, lat+0.001, lng, "motorbike")
	res = mustStatus(t, call(t, b.token, "POST", "/v1/medicine-reservations/"+resID+"/delivery", map[string]string{"address_id": b.addressID}), http.StatusOK)
	if res.str("status") != "courier_search" || num(res.Body["total_xof"]) != 7450+fee || res.str("handover_code") != "" {
		t.Fatalf("recherche du livreur : %v", res.Body)
	}
	if r := call(t, b.token, "POST", "/v1/medicine-reservations/"+resID+"/pay", map[string]string{"operator": "flooz", "phone": uniquePhone()}); r.code() != "courier_not_found_yet" {
		t.Fatalf("paiement avant le livreur : %d %s", r.Status, r.code())
	}
	missionID := acceptCourier(t, driver)
	if s := mustStatus(t, call(t, b.token, "GET", "/v1/medicine-reservations/"+resID, nil), http.StatusOK).str("status"); s != "awaiting_payment" {
		t.Fatalf("après acceptation du livreur : %s", s)
	}
	if av := mustStatus(t, call(t, driver, "GET", "/v1/driver/me", nil), http.StatusOK).str("availability"); av != "busy" {
		t.Fatalf("livreur pendant la course : %s", av)
	}
	if x := call(t, driver, "POST", "/v1/driver/pharmacy-missions/"+missionID+"/picked-up", nil); x.code() != "awaiting_payment" {
		t.Fatalf("récupération avant paiement : %d %s", x.Status, x.code())
	}
	p := mustStatus(t, call(t, b.token, "POST", "/v1/medicine-reservations/"+resID+"/pay", map[string]string{"operator": "flooz", "phone": uniquePhone()}), http.StatusOK)
	if num(p.Body["amount_xof"]) != 7450+fee {
		t.Fatalf("montant payé : %v", p.Body)
	}
	simulateMedicinePayment(t, b.token, p.str("id"))
	eventually(t, "livraison payée", func() bool {
		return call(t, b.token, "GET", "/v1/medicine-reservations/"+resID, nil).str("status") == "courier_assigned"
	})
	mustStatus(t, call(t, ph1, "POST", "/v1/pharmacy/reservations/"+resID+"/prepared", nil), http.StatusOK)

	r := mustStatus(t, call(t, b.token, "GET", "/v1/medicine-reservations/"+resID, nil), http.StatusOK)
	code := r.str("handover_code")
	tl := r.Body["timeline"].(map[string]any)
	if len(code) != 4 || r.Body["courier"] == nil || tl["paid_at"] == nil || tl["prepared_at"] == nil {
		t.Fatalf("suivi de livraison : %v", r.Body)
	}
	mustStatus(t, call(t, driver, "POST", "/v1/driver/pharmacy-missions/"+missionID+"/picked-up", nil), http.StatusOK)
	wrong := "0000"
	if code == wrong {
		wrong = "1111"
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

	// Pas de commission sur les médicaments : la pharmacie reçoit 100 % des produits.
	e := mustStatus(t, call(t, ph1, "GET", "/v1/pharmacy/earnings", nil), http.StatusOK)
	if num(e.Body["balance_xof"]) != 7450 || num(e.Body["delivered_count"]) != 1 {
		t.Fatalf("solde de la pharmacie : %v", e.Body)
	}
	if x := call(t, admin(t), "POST", "/v1/admin/pharmacies/"+ph1ID+"/payouts", map[string]any{"amount_xof": 7451, "reference": "TMONEY-1"}); x.code() != "amount_exceeds_balance" {
		t.Fatalf("reversement trop élevé : %d %s", x.Status, x.code())
	}
	e = mustStatus(t, call(t, admin(t), "POST", "/v1/admin/pharmacies/"+ph1ID+"/payouts", map[string]any{"amount_xof": 7450, "reference": "TMONEY-1"}), http.StatusCreated)
	if num(e.Body["balance_xof"]) != 0 {
		t.Fatalf("solde après reversement : %v", e.Body)
	}
}

func TestPharmacyPrescriptionDeliveryNeedsCheck(t *testing.T) {
	requireApp(t)
	lat, lng := zone()
	ph, _ := newPharmacy(t, "Pharmacie Bon Secours", lat, lng)
	b := newBuyer(t, lat, lng)

	if r := call(t, b.token, "POST", "/v1/medicine-alerts", map[string]any{"location": map[string]float64{"lat": lat, "lng": lng}}); r.Status != http.StatusBadRequest {
		t.Fatalf("alerte vide : %d", r.Status)
	}
	alert := mustStatus(t, call(t, b.token, "POST", "/v1/medicine-alerts", map[string]any{
		"photos":     []map[string]string{{"kind": "prescription", "object_key": uploadAlertPhoto(t, b.token)}},
		"note":       "Le sirop plutôt que les comprimés",
		"address_id": b.addressID,
	}), http.StatusCreated)
	alertID := alert.str("id")
	if alert.str("kind") != "prescription" || len(list(alert.Body["photos"])) != 1 {
		t.Fatalf("alerte par ordonnance : %v", alert.Body)
	}
	item := mustStatus(t, call(t, ph, "GET", "/v1/pharmacy/inbox/"+alertID, nil), http.StatusOK)
	photos := list(item.Body["photos"])
	if len(photos) != 1 || photos[0]["url"] == nil || photos[0]["url"] == "" {
		t.Fatalf("photo de l'ordonnance pour la pharmacie : %v", item.Body)
	}
	// Lecture de l'ordonnance : lignes saisies par le pharmacien.
	mustStatus(t, call(t, ph, "POST", "/v1/pharmacy/inbox/"+alertID+"/respond", map[string]any{
		"lines": []map[string]any{{"name": "Amoxicilline 500 mg", "quantity": 3, "unit_price_xof": 2500, "available": true, "prescription_required": true}},
	}), http.StatusOK)
	responseID := list(mustStatus(t, call(t, b.token, "GET", "/v1/medicine-alerts/"+alertID, nil), http.StatusOK).Body["responses"])[0]["id"].(string)
	_, resID := unlockResponse(t, b.token, alertID, responseID)
	res := mustStatus(t, call(t, b.token, "GET", "/v1/medicine-reservations/"+resID, nil), http.StatusOK)
	if res.Body["prescription_required"] != true || num(res.Body["items_xof"]) != 7500 {
		t.Fatalf("réservation sur ordonnance : %v", res.Body)
	}

	// Livraison possible sur ordonnance : le livreur doit vérifier l'original.
	driver := newDriver(t, lat+0.001, lng, "motorbike")
	mustStatus(t, call(t, b.token, "POST", "/v1/medicine-reservations/"+resID+"/delivery", map[string]string{"address_id": b.addressID}), http.StatusOK)
	missionID := acceptCourier(t, driver)
	m := mustStatus(t, call(t, driver, "GET", "/v1/driver/pharmacy-missions/current", nil), http.StatusOK).Body["mission"].(map[string]any)
	if m["prescription_check_required"] != true {
		t.Fatalf("course sur ordonnance : %v", m)
	}
	p := mustStatus(t, call(t, b.token, "POST", "/v1/medicine-reservations/"+resID+"/pay", map[string]string{"operator": "flooz", "phone": uniquePhone()}), http.StatusOK)
	simulateMedicinePayment(t, b.token, p.str("id"))
	eventually(t, "livraison payée", func() bool {
		return call(t, b.token, "GET", "/v1/medicine-reservations/"+resID, nil).str("status") == "courier_assigned"
	})
	code := mustStatus(t, call(t, b.token, "GET", "/v1/medicine-reservations/"+resID, nil), http.StatusOK).str("handover_code")
	mustStatus(t, call(t, driver, "POST", "/v1/driver/pharmacy-missions/"+missionID+"/picked-up", nil), http.StatusOK)
	if x := call(t, driver, "POST", "/v1/driver/pharmacy-missions/"+missionID+"/delivered", map[string]any{"code": code}); x.code() != "prescription_check_required" {
		t.Fatalf("remise sans vérification de l'ordonnance : %d %s", x.Status, x.code())
	}
	mustStatus(t, call(t, driver, "POST", "/v1/driver/pharmacy-missions/"+missionID+"/delivered", map[string]any{"code": code, "prescription_checked": true}), http.StatusOK)
}

func TestPharmacyPickupRelaunchAndCancelRefund(t *testing.T) {
	requireApp(t)
	lat, lng := zone()
	// Pharmacie à environ 3,3 km : hors du rayon de 2 km, dans celui de 5 km.
	ph, _ := newPharmacy(t, "Pharmacie Espoir", lat+0.03, lng)
	b := newBuyer(t, lat, lng)

	alert := mustStatus(t, call(t, b.token, "POST", "/v1/medicine-alerts", map[string]any{
		"items":    []map[string]any{{"name": "Ventoline 100 µg", "form": "Aérosol"}},
		"photos":   []map[string]string{{"kind": "box", "object_key": uploadAlertPhoto(t, b.token)}},
		"radius_m": 2000, "location": map[string]float64{"lat": lat, "lng": lng},
	}), http.StatusCreated)
	alertID := alert.str("id")
	if num(alert.Body["stats"].(map[string]any)["notified"]) != 0 {
		t.Fatalf("alerte à 2 km : %v", alert.Body["stats"])
	}
	if r := call(t, b.token, "POST", "/v1/medicine-alerts", map[string]any{
		"items": []map[string]any{{"name": "Ventoline"}}, "radius_m": 3000, "location": map[string]float64{"lat": lat, "lng": lng},
	}); r.Status != http.StatusBadRequest {
		t.Fatalf("rayon non proposé : %d", r.Status)
	}
	// Relance à 5 km (après arrêt de la première) : produits et photo repris.
	if r := call(t, b.token, "POST", "/v1/medicine-alerts/"+alertID+"/relaunch", map[string]any{"radius_m": 5000}); r.code() != "alert_not_relaunchable" {
		t.Fatalf("relance d'une alerte en cours : %d %s", r.Status, r.code())
	}
	mustStatus(t, call(t, b.token, "POST", "/v1/medicine-alerts/"+alertID+"/cancel", nil), http.StatusOK)
	re := mustStatus(t, call(t, b.token, "POST", "/v1/medicine-alerts/"+alertID+"/relaunch", map[string]any{"radius_m": 5000}), http.StatusCreated)
	alertID = re.str("id")
	if num(re.Body["stats"].(map[string]any)["notified"]) != 1 || len(list(re.Body["photos"])) != 1 || len(list(re.Body["items"])) != 1 {
		t.Fatalf("alerte relancée : %v", re.Body)
	}
	itemID := list(re.Body["items"])[0]["id"]
	mustStatus(t, call(t, ph, "POST", "/v1/pharmacy/inbox/"+alertID+"/respond", map[string]any{
		"lines": []map[string]any{{"alert_item_id": itemID, "available": true, "unit_price_xof": 3200}},
	}), http.StatusOK)
	responseID := list(mustStatus(t, call(t, b.token, "GET", "/v1/medicine-alerts/"+alertID, nil), http.StatusOK).Body["responses"])[0]["id"].(string)

	// Retrait : la pharmacie saisit le code ; aucun reversement (payé sur place, sans commission).
	unlockPay, resID := unlockResponse(t, b.token, alertID, responseID)
	res := mustStatus(t, call(t, b.token, "GET", "/v1/medicine-reservations/"+resID, nil), http.StatusOK)
	if num(res.Body["walk_minutes"]) <= 0 || res.Body["pay_in_app"] != false {
		t.Fatalf("retrait : %v", res.Body)
	}
	pr := mustStatus(t, call(t, ph, "GET", "/v1/pharmacy/reservations/"+resID, nil), http.StatusOK)
	if pr.str("buyer_first_name") != "Kossi" || pr.str("handover_code") != "" {
		t.Fatalf("réservation vue par la pharmacie : %v", pr.Body)
	}

	// La pharmacie n'a finalement plus le produit : forfait remboursé, réponse retirée.
	mustStatus(t, call(t, ph, "POST", "/v1/pharmacy/reservations/"+resID+"/cancel", map[string]string{"reason": "Rupture de stock"}), http.StatusOK)
	eventually(t, "forfait remboursé", func() bool {
		return call(t, b.token, "GET", "/v1/medicine-payments/"+unlockPay, nil).str("status") == "refunded"
	})
	a := mustStatus(t, call(t, b.token, "GET", "/v1/medicine-alerts/"+alertID, nil), http.StatusOK)
	if list(a.Body["responses"])[0]["status"] != "withdrawn" {
		t.Fatalf("réponse retirée après rupture : %v", a.Body["responses"])
	}
	mustStatus(t, call(t, b.token, "POST", "/v1/medicine-alerts/"+alertID+"/cancel", nil), http.StatusOK)
	if e := mustStatus(t, call(t, ph, "GET", "/v1/pharmacy/earnings", nil), http.StatusOK); num(e.Body["due_xof"]) != 0 {
		t.Fatalf("rien à reverser : %v", e.Body)
	}
}
