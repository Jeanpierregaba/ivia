package app_test

import (
	"bytes"
	"context"
	"net/http"
	"sync"
	"testing"

	"github.com/google/uuid"
)

func ctx() context.Context { return context.Background() }

func stockOf(t *testing.T, s sellerFixture, productID string) int {
	t.Helper()
	r := mustStatus(t, call(t, s.token, "GET", "/v1/seller/products/"+productID, nil), http.StatusOK)
	return int(r.Body["stock_quantity"].(float64))
}

func exec(t *testing.T, sql string, args ...any) {
	t.Helper()
	if _, err := testDB.Pool.Exec(ctx(), sql, args...); err != nil {
		t.Fatalf("%s : %v", sql, err)
	}
}

// Parcours complet en livraison, par HTTP : commande → paiement (webhook) → marchand →
// attribution automatique → récupération → remise par code → relevé marchand.
func TestDeliveryJourney(t *testing.T) {
	requireApp(t)
	s := newSeller(t, 10)
	b := newBuyer(t, s.lat, s.lng)
	d := newDriver(t, s.lat+0.002, s.lng, "motorbike")

	o := mustStatus(t, order(t, b, s.trackedID, 2, "delivery"), http.StatusCreated)
	oid := o.str("id")
	if o.Body["handover_code"] != nil {
		t.Fatal("le code de remise ne doit pas être visible avant le paiement")
	}
	if stockOf(t, s, s.trackedID) != 8 {
		t.Fatal("le stock doit être réservé à la commande")
	}
	pay(t, b, oid)

	seller := mustStatus(t, call(t, s.token, "GET", "/v1/seller/orders/"+oid, nil), http.StatusOK)
	if seller.Body["delivery_address"] != nil || bytes.Contains(seller.Raw, []byte("+228")) {
		t.Fatalf("le marchand ne doit voir ni l'adresse ni le numéro de l'acheteur : %s", seller.Raw)
	}
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
	m := mustStatus(t, call(t, d, "POST", "/v1/driver/offers/"+offerID+"/accept", map[string]any{}), http.StatusOK)
	mid := m.str("id")
	if cust, _ := m.Body["customer"].(map[string]any); cust == nil || cust["phone"] == "" {
		t.Fatal("pendant la mission, le livreur voit le prénom et le numéro de l'acheteur")
	}
	if got := orderStatus(t, b.token, oid); got != "driver_assigned" {
		t.Fatalf("statut %s, attendu driver_assigned", got)
	}
	for _, step := range []string{"arrived-at-shop", "picked-up", "arrived-at-customer"} {
		mustStatus(t, call(t, d, "POST", "/v1/driver/missions/"+mid+"/"+step, map[string]any{}), http.StatusOK)
	}
	code := mustStatus(t, call(t, b.token, "GET", "/v1/orders/"+oid, nil), http.StatusOK).str("handover_code")
	done := mustStatus(t, call(t, d, "POST", "/v1/driver/missions/"+mid+"/deliver", map[string]string{"code": code}), http.StatusOK)
	if done.Body["customer"] != nil {
		t.Fatal("après la remise, le livreur ne voit plus les coordonnées de l'acheteur")
	}
	final := mustStatus(t, call(t, b.token, "GET", "/v1/orders/"+oid, nil), http.StatusOK)
	if final.str("status") != "delivered" || final.Body["handover_code"] != nil {
		t.Fatalf("commande finale : %s", final.Raw)
	}
	if events := final.Body["events"].([]any); len(events) != 8 {
		t.Fatalf("%d événements d'historique, attendu 8", len(events))
	}
	if st := mustStatus(t, call(t, d, "GET", "/v1/driver/me", nil), http.StatusOK).str("status"); st != "available" {
		t.Fatalf("le livreur doit redevenir disponible : %s", st)
	}

	today := final.str("completed_at")[:10]
	st := mustStatus(t, call(t, admin(t), "POST", "/v1/admin/settlements", map[string]string{
		"shop_id": s.shopID, "period_start": today, "period_end": today,
	}), http.StatusCreated)
	// 2 × 5 000 = 10 000 ; commission 10 % = 1 000 ; net 9 000 (frais de livraison à la plateforme).
	if st.Body["gross_xof"].(float64) != 10000 || st.Body["commission_xof"].(float64) != 1000 || st.Body["net_xof"].(float64) != 9000 {
		t.Fatalf("relevé inattendu : %s", st.Raw)
	}
	sid := st.str("id")
	mustStatus(t, call(t, admin(t), "POST", "/v1/admin/settlements/"+sid+"/mark-settled", map[string]string{"settlement_reference": "VIR-1"}), http.StatusOK)
	if r := call(t, admin(t), "POST", "/v1/admin/settlements", map[string]string{"shop_id": s.shopID, "period_start": today, "period_end": today}); r.code() != "nothing_to_settle" {
		t.Fatalf("une commande ne doit être réglée qu'une fois : %s", r.Raw)
	}
	if _, err := testDB.Pool.Exec(ctx(), "UPDATE settlements SET net_xof = 0 WHERE id = $1", sid); err == nil {
		t.Fatal("un relevé réglé doit être figé")
	}
}

// Retrait en boutique : code de remise, 5 essais au maximum, déblocage par l'admin.
func TestPickupHandoverCodeLock(t *testing.T) {
	requireApp(t)
	s := newSeller(t, 5)
	b := newBuyer(t, s.lat, s.lng)
	oid := mustStatus(t, order(t, b, s.untrackedID, 1, "pickup"), http.StatusCreated).str("id")
	pay(t, b, oid)
	for _, step := range []string{"accept", "preparing", "ready"} {
		mustStatus(t, call(t, s.token, "POST", "/v1/seller/orders/"+oid+"/"+step, map[string]any{}), http.StatusOK)
	}
	code := mustStatus(t, call(t, b.token, "GET", "/v1/orders/"+oid, nil), http.StatusOK).str("handover_code")
	wrong := "0000"
	if code == wrong {
		wrong = "1111"
	}
	for i := 1; i <= 5; i++ {
		r := call(t, s.token, "POST", "/v1/seller/orders/"+oid+"/handover", map[string]string{"code": wrong})
		want := "handover_code_invalid"
		if i == 5 {
			want = "handover_locked"
		}
		if r.code() != want {
			t.Fatalf("essai %d : %s, attendu %s", i, r.code(), want)
		}
	}
	if r := call(t, s.token, "POST", "/v1/seller/orders/"+oid+"/handover", map[string]string{"code": code}); r.code() != "handover_locked" {
		t.Fatalf("après 5 essais, même le bon code est refusé : %s", r.Raw)
	}
	mustStatus(t, call(t, admin(t), "POST", "/v1/admin/orders/"+oid+"/unlock-handover", map[string]string{"reason": "Identité vérifiée"}), http.StatusOK)
	r := mustStatus(t, call(t, s.token, "POST", "/v1/seller/orders/"+oid+"/handover", map[string]string{"code": code}), http.StatusOK)
	if r.str("status") != "completed" {
		t.Fatalf("statut %s, attendu completed", r.str("status"))
	}
}

// N commandes simultanées sur le dernier article : une seule réussit ; l'expiration rend le stock.
func TestLastItemOnlyOneOrderWins(t *testing.T) {
	requireApp(t)
	s := newSeller(t, 1)
	const n = 6
	buyers := make([]buyerFixture, n)
	for i := range buyers {
		buyers[i] = newBuyer(t, s.lat, s.lng)
		mustStatus(t, call(t, buyers[i].token, "PUT", "/v1/cart/items", map[string]any{"product_id": s.trackedID, "quantity": 1}), http.StatusOK)
	}
	var mu sync.Mutex
	var created []string
	var wg sync.WaitGroup
	for _, b := range buyers {
		wg.Go(func() {
			r := call(t, b.token, "POST", "/v1/orders", map[string]any{"fulfillment": "pickup"})
			if r.Status == http.StatusCreated {
				mu.Lock()
				created = append(created, r.str("id"))
				mu.Unlock()
			} else if r.code() != "insufficient_stock" {
				t.Errorf("refus inattendu : %s", r.Raw)
			}
		})
	}
	wg.Wait()
	if len(created) != 1 {
		t.Fatalf("%d commandes créées sur le dernier article, attendu 1", len(created))
	}
	if q := stockOf(t, s, s.trackedID); q != 0 {
		t.Fatalf("stock %d, attendu 0", q)
	}

	// Délai de paiement dépassé : la commande expire et le stock est rendu.
	id := uuid.MustParse(created[0])
	exec(t, "UPDATE orders SET payment_deadline_at = now() - interval '1 second' WHERE id = $1", id)
	if err := testApp.Orders.ExpirePayment(ctx(), id); err != nil {
		t.Fatal(err)
	}
	if q := stockOf(t, s, s.trackedID); q != 1 {
		t.Fatalf("stock %d après expiration, attendu 1", q)
	}
}

// Webhook : signature invalide refusée, montant différent refusé, webhook rejoué traité une fois.
func TestPaymentWebhookSecurity(t *testing.T) {
	requireApp(t)
	s := newSeller(t, 5)
	b := newBuyer(t, s.lat, s.lng)
	oid := mustStatus(t, order(t, b, s.untrackedID, 1, "pickup"), http.StatusCreated).str("id")
	p := mustStatus(t, call(t, b.token, "POST", "/v1/orders/"+oid+"/payments", map[string]string{"operator": "tmoney", "phone": "70000001"}), http.StatusCreated)
	pid := p.str("id")
	ref := mustStatus(t, call(t, admin(t), "GET", "/v1/admin/payments/"+pid, nil), http.StatusOK).str("reference")

	post := func(h http.Header, body []byte) int {
		req, _ := http.NewRequest("POST", server.URL+"/v1/webhooks/payments/fake", bytes.NewReader(body))
		for k, v := range h {
			req.Header[k] = v
		}
		res, err := http.DefaultClient.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		res.Body.Close()
		return res.StatusCode
	}

	// 1. Signature falsifiée.
	h, body, _ := testApp.FakePayment.SignedWebhook(map[string]any{"event_id": "evt-x", "reference": ref, "status": "succeeded", "amount_xof": 5000, "currency": "XOF"})
	h.Set("X-Fake-Signature", "00"+h.Get("X-Fake-Signature")[2:])
	if code := post(h, body); code != http.StatusUnauthorized {
		t.Fatalf("signature invalide : statut %d, attendu 401", code)
	}
	// Une app ne peut pas non plus déclarer un paiement réussi : aucune route ne le permet.
	if orderStatus(t, b.token, oid) != "pending_payment" {
		t.Fatal("une signature invalide ne doit rien changer")
	}

	// 2. Montant différent du montant attendu.
	h, body, _ = testApp.FakePayment.SignedWebhook(map[string]any{"event_id": "evt-low", "reference": ref, "status": "succeeded", "amount_xof": 100, "currency": "XOF"})
	if code := post(h, body); code != http.StatusOK {
		t.Fatalf("webhook signé : statut %d", code)
	}
	eventually(t, "alerte montant incohérent", func() bool {
		var n int
		_ = testDB.Pool.QueryRow(ctx(), "SELECT count(*) FROM notifications WHERE kind = 'payment_amount_mismatch' AND data->>'payment_id' = $1", pid).Scan(&n)
		return n > 0
	})
	if orderStatus(t, b.token, oid) != "pending_payment" {
		t.Fatal("un montant différent ne doit pas valider la commande")
	}

	// 3. Bon webhook envoyé deux fois : un seul traitement.
	h, body, _ = testApp.FakePayment.Simulate(ref, "succeeded", -1)
	if post(h, body) != http.StatusOK || post(h, body) != http.StatusOK {
		t.Fatal("le webhook valide doit être accepté (y compris rejoué)")
	}
	eventually(t, "commande payée", func() bool { return orderStatus(t, b.token, oid) == "awaiting_seller" })
	var paidEvents, rows int
	_ = testDB.Pool.QueryRow(ctx(), "SELECT count(*) FROM order_status_events WHERE order_id = $1 AND to_status = 'awaiting_seller'", oid).Scan(&paidEvents)
	_ = testDB.Pool.QueryRow(ctx(), "SELECT count(*) FROM payment_events WHERE reference = $1 AND source = 'webhook'", ref).Scan(&rows)
	if paidEvents != 1 || rows != 2 {
		t.Fatalf("transitions payées : %d (attendu 1) ; événements enregistrés : %d (attendu 2 : montant faux + bon)", paidEvents, rows)
	}
}

// Paiement arrivé après l'expiration : reprise si le stock est là, sinon annulation et remboursement.
func TestLatePayment(t *testing.T) {
	requireApp(t)
	s := newSeller(t, 1)
	a, other := newBuyer(t, s.lat, s.lng), newBuyer(t, s.lat, s.lng)

	expire := func(oid string) {
		id := uuid.MustParse(oid)
		exec(t, "UPDATE orders SET payment_deadline_at = now() - interval '1 second' WHERE id = $1", id)
		if err := testApp.Orders.ExpirePayment(ctx(), id); err != nil {
			t.Fatal(err)
		}
	}
	reference := func(pid string) string {
		return mustStatus(t, call(t, admin(t), "GET", "/v1/admin/payments/"+pid, nil), http.StatusOK).str("reference")
	}

	// Stock disponible : la commande reprend.
	oid := mustStatus(t, order(t, a, s.trackedID, 1, "pickup"), http.StatusCreated).str("id")
	pid := mustStatus(t, call(t, a.token, "POST", "/v1/orders/"+oid+"/payments", map[string]string{"operator": "flooz", "phone": "90000002"}), http.StatusCreated).str("id")
	expire(oid)
	if orderStatus(t, a.token, oid) != "expired" || stockOf(t, s, s.trackedID) != 1 {
		t.Fatal("expiration : statut expired et stock rendu attendus")
	}
	h, body, _ := testApp.FakePayment.Simulate(reference(pid), "succeeded", -1)
	ev, _ := testApp.FakePayment.ParseWebhook(h, body)
	if err := testApp.Payments.HandleWebhook(ctx(), ev); err != nil {
		t.Fatal(err)
	}
	eventually(t, "reprise après paiement tardif", func() bool { return orderStatus(t, a.token, oid) == "awaiting_seller" })
	if stockOf(t, s, s.trackedID) != 0 {
		t.Fatal("le stock doit être de nouveau réservé")
	}

	// Stock épuisé entre-temps : la commande est annulée et part en remboursement.
	mustStatus(t, call(t, s.token, "PUT", "/v1/seller/products/"+s.trackedID+"/stock", map[string]any{"quantity": 1}), http.StatusOK)
	oid2 := mustStatus(t, order(t, a, s.trackedID, 1, "pickup"), http.StatusCreated).str("id")
	pid2 := mustStatus(t, call(t, a.token, "POST", "/v1/orders/"+oid2+"/payments", map[string]string{"operator": "flooz", "phone": "90000002"}), http.StatusCreated).str("id")
	expire(oid2)
	oid3 := mustStatus(t, order(t, other, s.trackedID, 1, "pickup"), http.StatusCreated).str("id")
	pay(t, other, oid3)
	h, body, _ = testApp.FakePayment.Simulate(reference(pid2), "succeeded", -1)
	ev, _ = testApp.FakePayment.ParseWebhook(h, body)
	if err := testApp.Payments.HandleWebhook(ctx(), ev); err != nil {
		t.Fatal(err)
	}
	eventually(t, "annulation après paiement tardif", func() bool { return orderStatus(t, a.token, oid2) == "cancelled" })
	r := mustStatus(t, call(t, admin(t), "GET", "/v1/admin/orders/"+oid2, nil), http.StatusOK)
	if r.Body["refund_due_xof"].(float64) != 5000 {
		t.Fatalf("remboursement attendu de 5000 : %s", r.Raw)
	}
}

// Annulation par l'acheteur avant acceptation, file de remboursement, remboursement par l'admin.
func TestCancelAndRefund(t *testing.T) {
	requireApp(t)
	s := newSeller(t, 3)
	b := newBuyer(t, s.lat, s.lng)

	oid := mustStatus(t, order(t, b, s.trackedID, 1, "pickup"), http.StatusCreated).str("id")
	pay(t, b, oid)
	mustStatus(t, call(t, b.token, "POST", "/v1/orders/"+oid+"/cancel", map[string]any{}), http.StatusOK)
	if stockOf(t, s, s.trackedID) != 3 {
		t.Fatal("l'annulation doit rendre le stock")
	}
	queue := mustStatus(t, call(t, admin(t), "GET", "/v1/admin/refund-queue?limit=100", nil), http.StatusOK)
	if !bytes.Contains(queue.Raw, []byte(oid)) {
		t.Fatal("la commande annulée après paiement doit être dans la file de remboursement")
	}
	mustStatus(t, call(t, admin(t), "POST", "/v1/admin/orders/"+oid+"/refund", map[string]string{"reason": "Annulation acheteur"}), http.StatusAccepted)
	if r := call(t, admin(t), "POST", "/v1/admin/orders/"+oid+"/refund", map[string]string{}); r.Status == http.StatusAccepted {
		t.Fatal("un second remboursement ne doit pas être lancé")
	}
	eventually(t, "commande remboursée", func() bool { return orderStatus(t, b.token, oid) == "refunded" })
	var refundID string
	if err := testDB.Pool.QueryRow(ctx(), "SELECT id FROM refunds WHERE order_id = $1 AND status = 'succeeded'", oid).Scan(&refundID); err != nil {
		t.Fatalf("ligne de remboursement : %v", err)
	}
	if _, err := testDB.Pool.Exec(ctx(), "UPDATE refunds SET amount_xof = 1 WHERE id = $1", refundID); err == nil {
		t.Fatal("un remboursement ne doit jamais être modifié")
	}

	// Transfert refusé par l'opérateur : le refus est tracé, la commande reste à rembourser.
	oid3 := mustStatus(t, order(t, b, s.trackedID, 1, "pickup"), http.StatusCreated).str("id")
	payFrom(t, b, oid3, "90000000")
	mustStatus(t, call(t, b.token, "POST", "/v1/orders/"+oid3+"/cancel", map[string]any{}), http.StatusOK)
	mustStatus(t, call(t, admin(t), "POST", "/v1/admin/orders/"+oid3+"/refund", map[string]string{}), http.StatusAccepted)
	eventually(t, "remboursement échoué tracé", func() bool {
		var n int
		_ = testDB.Pool.QueryRow(ctx(), "SELECT count(*) FROM refunds WHERE order_id = $1 AND status = 'failed'", oid3).Scan(&n)
		return n == 1
	})
	if orderStatus(t, b.token, oid3) != "cancelled" {
		t.Fatal("après un transfert refusé, la commande reste annulée et dans la file")
	}
	eventually(t, "paiement de nouveau remboursable", func() bool {
		r := call(t, admin(t), "GET", "/v1/admin/payments?order_id="+oid3, nil)
		return bytes.Contains(r.Raw, []byte(`"status":"succeeded"`))
	})

	// Après acceptation, l'acheteur ne peut plus annuler.
	oid2 := mustStatus(t, order(t, b, s.trackedID, 1, "pickup"), http.StatusCreated).str("id")
	pay(t, b, oid2)
	mustStatus(t, call(t, s.token, "POST", "/v1/seller/orders/"+oid2+"/accept", map[string]any{}), http.StatusOK)
	if r := call(t, b.token, "POST", "/v1/orders/"+oid2+"/cancel", map[string]any{}); r.code() != "cannot_cancel" {
		t.Fatalf("annulation après acceptation : %s", r.Raw)
	}
}

// Le marchand ne répond pas à temps : la commande est annulée et à rembourser.
func TestSellerTimeout(t *testing.T) {
	requireApp(t)
	s := newSeller(t, 3)
	b := newBuyer(t, s.lat, s.lng)
	oid := mustStatus(t, order(t, b, s.untrackedID, 1, "pickup"), http.StatusCreated).str("id")
	pay(t, b, oid)
	id := uuid.MustParse(oid)
	exec(t, "UPDATE orders SET seller_deadline_at = now() - interval '1 second' WHERE id = $1", id)
	if err := testApp.Orders.SellerTimeout(ctx(), id); err != nil {
		t.Fatal(err)
	}
	if orderStatus(t, b.token, oid) != "cancelled" {
		t.Fatal("commande sans réponse du marchand : annulation attendue")
	}
}

// Attribution : véhicule incompatible et position trop ancienne exclus, livreur suivant après un
// refus puis une expiration, alerte de l'admin quand personne ne prend la mission.
func TestAssignmentRules(t *testing.T) {
	requireApp(t)
	s := newSeller(t, 5)
	b := newBuyer(t, s.lat, s.lng)
	car := newDriver(t, s.lat, s.lng, "car")                // le plus proche, mauvais véhicule
	stale := newDriver(t, s.lat+0.0005, s.lng, "motorbike") // proche, position trop ancienne
	near := newDriver(t, s.lat+0.002, s.lng, "motorbike")
	far := newDriver(t, s.lat+0.02, s.lng, "motorbike")
	staleID := mustStatus(t, call(t, stale, "GET", "/v1/me", nil), http.StatusOK).str("id")
	exec(t, "UPDATE drivers SET last_location_at = now() - interval '5 minutes' WHERE user_id = $1", uuid.MustParse(staleID))

	oid := mustStatus(t, order(t, b, s.untrackedID, 1, "delivery"), http.StatusCreated).str("id")
	pay(t, b, oid)
	for _, step := range []string{"accept", "preparing", "ready"} {
		mustStatus(t, call(t, s.token, "POST", "/v1/seller/orders/"+oid+"/"+step, map[string]any{}), http.StatusOK)
	}
	offerOf := func(tok string) string {
		r := call(t, tok, "GET", "/v1/driver/offers/current", nil)
		if off, ok := r.Body["offer"].(map[string]any); ok {
			return off["id"].(string)
		}
		return ""
	}
	var first string
	eventually(t, "proposition au livreur le plus proche compatible", func() bool { first = offerOf(near); return first != "" })
	if offerOf(car) != "" || offerOf(stale) != "" {
		t.Fatal("ni le véhicule incompatible ni la position ancienne ne doivent recevoir la proposition")
	}
	mustStatus(t, call(t, near, "POST", "/v1/driver/offers/"+first+"/decline", map[string]any{}), http.StatusNoContent)

	var second string
	eventually(t, "proposition au livreur suivant", func() bool { second = offerOf(far); return second != "" })
	// Plus personne : on vieillit la recherche pour déclencher l'alerte, puis la proposition expire.
	exec(t, "UPDATE assignment_requests SET started_at = now() - interval '30 minutes' WHERE order_id = $1", uuid.MustParse(oid))
	exec(t, "UPDATE delivery_offers SET expires_at = now() - interval '1 second' WHERE id = $1", uuid.MustParse(second))
	if err := testApp.Delivery.ExpireOffer(ctx(), uuid.MustParse(second)); err != nil {
		t.Fatal(err)
	}
	eventually(t, "alerte admin", func() bool {
		r := call(t, admin(t), "GET", "/v1/admin/delivery-alerts", nil)
		return bytes.Contains(r.Raw, []byte(oid))
	})
	if r := call(t, far, "POST", "/v1/driver/offers/"+second+"/accept", map[string]any{}); r.code() != "offer_expired" {
		t.Fatalf("une proposition expirée ne s'accepte plus : %s", r.Raw)
	}
}

// Échec de livraison : 10 minutes d'attente et deux appels, retour en boutique, remboursement des produits.
func TestDeliveryFailure(t *testing.T) {
	requireApp(t)
	s := newSeller(t, 5)
	b := newBuyer(t, s.lat, s.lng)
	d := newDriver(t, s.lat+0.001, s.lng, "motorbike")
	o := mustStatus(t, order(t, b, s.trackedID, 1, "delivery"), http.StatusCreated)
	oid := o.str("id")
	pay(t, b, oid)
	for _, step := range []string{"accept", "preparing", "ready"} {
		mustStatus(t, call(t, s.token, "POST", "/v1/seller/orders/"+oid+"/"+step, map[string]any{}), http.StatusOK)
	}
	var offer string
	eventually(t, "proposition", func() bool {
		if off, ok := call(t, d, "GET", "/v1/driver/offers/current", nil).Body["offer"].(map[string]any); ok {
			offer = off["id"].(string)
		}
		return offer != ""
	})
	mid := mustStatus(t, call(t, d, "POST", "/v1/driver/offers/"+offer+"/accept", map[string]any{}), http.StatusOK).str("id")
	for _, step := range []string{"picked-up", "arrived-at-customer"} {
		mustStatus(t, call(t, d, "POST", "/v1/driver/missions/"+mid+"/"+step, map[string]any{}), http.StatusOK)
	}
	if r := call(t, d, "POST", "/v1/driver/missions/"+mid+"/fail", map[string]any{"call_attempts": 2}); r.code() != "wait_required" {
		t.Fatalf("échec déclaré trop tôt : %s", r.Raw)
	}
	exec(t, "UPDATE deliveries SET arrived_customer_at = now() - interval '11 minutes' WHERE id = $1", uuid.MustParse(mid))
	if r := call(t, d, "POST", "/v1/driver/missions/"+mid+"/fail", map[string]any{"call_attempts": 1}); r.code() != "validation_failed" {
		t.Fatalf("un seul appel ne suffit pas : %s", r.Raw)
	}
	mustStatus(t, call(t, d, "POST", "/v1/driver/missions/"+mid+"/fail", map[string]any{"call_attempts": 2}), http.StatusOK)
	if orderStatus(t, b.token, oid) != "delivery_failed" {
		t.Fatal("statut delivery_failed attendu")
	}
	mustStatus(t, call(t, s.token, "POST", "/v1/seller/orders/"+oid+"/confirm-return", map[string]any{}), http.StatusOK)
	eventually(t, "livreur libéré", func() bool {
		return call(t, d, "GET", "/v1/driver/me", nil).str("status") == "available"
	})
	r := mustStatus(t, call(t, admin(t), "GET", "/v1/admin/orders/"+oid, nil), http.StatusOK)
	if r.str("status") != "returned_to_shop" || r.Body["refund_due_xof"].(float64) != 5000 {
		t.Fatalf("retour en boutique : produits remboursés, frais conservés : %s", r.Raw)
	}
	if stockOf(t, s, s.trackedID) != 5 {
		t.Fatal("le colis revenu rend le stock")
	}
}

// Les garanties de concurrence sont portées par la base.
func TestDatabaseGuarantees(t *testing.T) {
	requireApp(t)
	s := newSeller(t, 5)
	b := newBuyer(t, s.lat, s.lng)
	d1 := newDriver(t, 0.5, 0.5, "motorbike")
	d2 := newDriver(t, 0.6, 0.6, "motorbike")
	oid := mustStatus(t, order(t, b, s.untrackedID, 1, "delivery"), http.StatusCreated).str("id")
	id1 := mustStatus(t, call(t, d1, "GET", "/v1/me", nil), http.StatusOK).str("id")
	id2 := mustStatus(t, call(t, d2, "GET", "/v1/me", nil), http.StatusOK).str("id")

	exec(t, "INSERT INTO deliveries (order_id, driver_id, fee_xof) VALUES ($1, $2, 0)", oid, id1)
	if _, err := testDB.Pool.Exec(ctx(), "INSERT INTO deliveries (order_id, driver_id, fee_xof) VALUES ($1, $2, 0)", oid, id2); err == nil {
		t.Fatal("deux livreurs actifs sur une même commande doivent être impossibles")
	}
	oid2 := mustStatus(t, order(t, b, s.untrackedID, 1, "delivery"), http.StatusCreated).str("id")
	if _, err := testDB.Pool.Exec(ctx(), "INSERT INTO deliveries (order_id, driver_id, fee_xof) VALUES ($1, $2, 0)", oid2, id1); err == nil {
		t.Fatal("deux missions actives pour un même livreur doivent être impossibles")
	}
	for _, sql := range []string{
		"UPDATE order_status_events SET reason = 'x'",
		"DELETE FROM order_status_events",
		"DELETE FROM admin_audit_log",
		"UPDATE payment_events SET status = 'x'",
		"UPDATE stock_movements SET delta = 1",
	} {
		if _, err := testDB.Pool.Exec(ctx(), sql); err == nil {
			t.Errorf("table en ajout seul modifiable : %s", sql)
		}
	}
	if _, err := testDB.Pool.Exec(ctx(), "UPDATE stock_levels SET quantity = -1"); err == nil {
		t.Error("un stock négatif doit être impossible")
	}
}
