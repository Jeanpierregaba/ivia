package app_test

import (
	"bytes"
	"fmt"
	"net/http"
	"sync"
	"testing"

	"github.com/google/uuid"
)

// readyPickup crée une commande en retrait payée et prête, et retourne son code de remise.
func readyPickup(t *testing.T) (sellerFixture, buyerFixture, string, string) {
	t.Helper()
	s := newSeller(t, 5)
	b := newBuyer(t, s.lat, s.lng)
	oid := mustStatus(t, order(t, b, s.untrackedID, 1, "pickup"), http.StatusCreated).str("id")
	pay(t, b, oid)
	for _, step := range []string{"accept", "preparing", "ready"} {
		mustStatus(t, call(t, s.token, "POST", "/v1/seller/orders/"+oid+"/"+step, map[string]any{}), http.StatusOK)
	}
	code := mustStatus(t, call(t, b.token, "GET", "/v1/orders/"+oid, nil), http.StatusOK).str("handover_code")
	return s, b, oid, code
}

// Des centaines d'essais simultanés ne comparent jamais plus de 5 codes.
func TestHandoverCodeBruteForceInParallel(t *testing.T) {
	requireApp(t)
	s, b, oid, code := readyPickup(t)

	var wg sync.WaitGroup
	for i := range 200 {
		guess := fmt.Sprintf("%04d", i)
		if guess == code {
			continue
		}
		wg.Go(func() {
			call(t, s.token, "POST", "/v1/seller/orders/"+oid+"/handover", map[string]string{"code": guess})
		})
	}
	wg.Wait()

	var attempts int
	if err := testDB.Pool.QueryRow(ctx(), "SELECT handover_attempts FROM orders WHERE id = $1", oid).Scan(&attempts); err != nil {
		t.Fatal(err)
	}
	if attempts != 5 {
		t.Fatalf("%d essais comptés, attendu 5 au maximum", attempts)
	}
	if r := call(t, s.token, "POST", "/v1/seller/orders/"+oid+"/handover", map[string]string{"code": code}); r.code() != "handover_locked" {
		t.Fatalf("après 5 essais, le bon code doit être refusé : %s", r.Raw)
	}
	if orderStatus(t, b.token, oid) != "ready_for_pickup" {
		t.Fatal("la commande ne doit pas être remise")
	}
}

// Le marchand injoignable : l'admin confirme le retour, le livreur est libéré, la commande part en remboursement.
func TestAdminConfirmsReturn(t *testing.T) {
	requireApp(t)
	s := newSeller(t, 5)
	b := newBuyer(t, s.lat, s.lng)
	d := newDriver(t, s.lat+0.001, s.lng, "motorbike")
	oid := mustStatus(t, order(t, b, s.trackedID, 1, "delivery"), http.StatusCreated).str("id")
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
	exec(t, "UPDATE deliveries SET arrived_customer_at = now() - interval '11 minutes' WHERE id = $1", uuid.MustParse(mid))
	mustStatus(t, call(t, d, "POST", "/v1/driver/missions/"+mid+"/fail", map[string]any{"call_attempts": 2}), http.StatusOK)

	if r := call(t, s.token, "POST", "/v1/admin/orders/"+oid+"/confirm-return", map[string]string{"reason": "x"}); r.Status != http.StatusForbidden {
		t.Fatalf("route réservée aux admins : %d", r.Status)
	}
	if r := call(t, admin(t), "POST", "/v1/admin/orders/"+oid+"/confirm-return", map[string]string{}); r.code() != "validation_failed" {
		t.Fatalf("motif obligatoire : %s", r.Raw)
	}
	r := mustStatus(t, call(t, admin(t), "POST", "/v1/admin/orders/"+oid+"/confirm-return", map[string]string{"reason": "Colis vu en boutique"}), http.StatusOK)
	if r.str("status") != "returned_to_shop" || r.Body["refund_due_xof"].(float64) != 5000 {
		t.Fatalf("retour confirmé par l'admin : %s", r.Raw)
	}
	eventually(t, "livreur libéré", func() bool { return call(t, d, "GET", "/v1/driver/me", nil).str("status") == "available" })
	queue := mustStatus(t, call(t, admin(t), "GET", "/v1/admin/refund-queue?limit=100", nil), http.StatusOK)
	if !bytes.Contains(queue.Raw, []byte(oid)) {
		t.Fatal("la commande doit être dans la file de remboursement")
	}
	audit := mustStatus(t, call(t, admin(t), "GET", "/v1/admin/audit-log?target_type=order&target_id="+oid, nil), http.StatusOK)
	if !bytes.Contains(audit.Raw, []byte("order.confirm_return")) {
		t.Fatal("l'action doit être journalisée")
	}
}

// Ressources d'un autre utilisateur : toujours 404, sur chaque route qui prend un identifiant.
func TestOtherUsersResourcesAreNotFound(t *testing.T) {
	requireApp(t)
	s1, s2 := newSeller(t, 5), newSeller(t, 5)
	b1, b2 := newBuyer(t, s1.lat, s1.lng), newBuyer(t, s1.lat, s1.lng)
	d1 := newDriver(t, s1.lat+0.001, s1.lng, "motorbike")
	d2 := newDriver(t, 0.7, 0.7, "motorbike")

	oid := mustStatus(t, order(t, b1, s1.untrackedID, 1, "delivery"), http.StatusCreated).str("id")
	pid := pay(t, b1, oid)
	for _, step := range []string{"accept", "preparing", "ready"} {
		mustStatus(t, call(t, s1.token, "POST", "/v1/seller/orders/"+oid+"/"+step, map[string]any{}), http.StatusOK)
	}
	var offer string
	eventually(t, "proposition", func() bool {
		if off, ok := call(t, d1, "GET", "/v1/driver/offers/current", nil).Body["offer"].(map[string]any); ok {
			offer = off["id"].(string)
		}
		return offer != ""
	})
	mid := mustStatus(t, call(t, d1, "POST", "/v1/driver/offers/"+offer+"/accept", map[string]any{}), http.StatusOK).str("id")
	addr := b1.addressID
	notif := mustStatus(t, call(t, b1.token, "GET", "/v1/notifications?app=buyer", nil), http.StatusOK).Body["items"].([]any)[0].(map[string]any)["id"].(string)

	cases := []struct {
		name, token, method, path string
		body                      any
	}{
		{"adresse d'autrui (modification)", b2.token, "PUT", "/v1/me/addresses/" + addr, map[string]any{"label": "x", "address_text": "x", "location": map[string]float64{"lat": 6.1, "lng": 1.2}}},
		{"adresse d'autrui (suppression)", b2.token, "DELETE", "/v1/me/addresses/" + addr, nil},
		{"notification d'autrui", b2.token, "POST", "/v1/notifications/" + notif + "/read", map[string]any{}},
		{"paiement d'autrui", b2.token, "GET", "/v1/payments/" + pid, nil},
		{"paiements de la commande d'autrui", b2.token, "GET", "/v1/orders/" + oid + "/payments", nil},
		{"livreur de la commande d'autrui", b2.token, "GET", "/v1/orders/" + oid + "/delivery", nil},
		{"simulation du paiement d'autrui", b2.token, "POST", "/v1/dev/payments/" + pid + "/simulate", map[string]string{"outcome": "succeeded"}},
		{"boutique d'autrui", s2.token, "GET", "/v1/seller/shops/" + s1.shopID, nil},
		{"modification de la boutique d'autrui", s2.token, "PATCH", "/v1/seller/shops/" + s1.shopID, map[string]any{"name": "Pirate", "phone": "90000001", "address_text": "x", "location": map[string]float64{"lat": 6.1, "lng": 1.2}}},
		{"produits de la boutique d'autrui", s2.token, "GET", "/v1/seller/shops/" + s1.shopID + "/products", nil},
		{"ajout de produit à la boutique d'autrui", s2.token, "POST", "/v1/seller/shops/" + s1.shopID + "/products", map[string]any{"category_id": category(t), "name": "Pirate", "price_xof": 1, "parcel_size": "small", "stock_mode": "untracked"}},
		{"produit d'autrui", s2.token, "GET", "/v1/seller/products/" + s1.trackedID, nil},
		{"stock d'autrui", s2.token, "PUT", "/v1/seller/products/" + s1.trackedID + "/stock", map[string]any{"quantity": 0}},
		{"journal du stock d'autrui", s2.token, "GET", "/v1/seller/products/" + s1.trackedID + "/stock-movements", nil},
		{"livreur d'une commande d'autrui", s2.token, "GET", "/v1/seller/orders/" + oid + "/delivery", nil},
		{"relevés de la boutique d'autrui", s2.token, "GET", "/v1/seller/shops/" + s1.shopID + "/settlements", nil},
		{"mission d'un autre livreur", d2, "POST", "/v1/driver/missions/" + mid + "/picked-up", map[string]any{}},
		{"remise par un autre livreur", d2, "POST", "/v1/driver/missions/" + mid + "/deliver", map[string]string{"code": "0000"}},
		{"proposition d'un autre livreur", d2, "POST", "/v1/driver/offers/" + offer + "/decline", map[string]any{}},
	}
	for _, c := range cases {
		if r := call(t, c.token, c.method, c.path, c.body); r.Status != http.StatusNotFound {
			t.Errorf("%s : statut %d, attendu 404 (%s)", c.name, r.Status, r.Raw)
		}
	}

	// Une photo envoyée par un autre utilisateur ne peut pas être rattachée à son produit.
	other := mustStatus(t, call(t, s2.token, "POST", "/v1/uploads", map[string]any{"purpose": "product_image", "content_type": "image/jpeg", "size_bytes": 10}), http.StatusCreated)
	r := call(t, s1.token, "PATCH", "/v1/seller/products/"+s1.trackedID, map[string]any{
		"category_id": category(t), "name": "Produit suivi", "price_xof": 5000, "parcel_size": "small",
		"image_keys": []string{other.str("object_key")},
	})
	if r.code() != "validation_failed" {
		t.Errorf("clé de fichier d'autrui : %s", r.Raw)
	}
}

// Le marchand ne voit jamais une commande non payée, même abandonnée par l'acheteur.
func TestSellerNeverSeesUnpaidOrders(t *testing.T) {
	requireApp(t)
	s := newSeller(t, 5)
	b := newBuyer(t, s.lat, s.lng)
	pending := mustStatus(t, order(t, b, s.untrackedID, 1, "pickup"), http.StatusCreated).str("id")
	abandoned := mustStatus(t, order(t, b, s.untrackedID, 1, "pickup"), http.StatusCreated).str("id")
	mustStatus(t, call(t, b.token, "POST", "/v1/orders/"+abandoned+"/cancel", map[string]any{}), http.StatusOK)

	for _, id := range []string{pending, abandoned} {
		if r := call(t, s.token, "GET", "/v1/seller/orders/"+id, nil); r.Status != http.StatusNotFound {
			t.Errorf("commande non payée visible par le marchand : %d", r.Status)
		}
	}
	list := mustStatus(t, call(t, s.token, "GET", "/v1/seller/orders?limit=100", nil), http.StatusOK)
	if bytes.Contains(list.Raw, []byte(pending)) || bytes.Contains(list.Raw, []byte(abandoned)) {
		t.Fatal("la liste du marchand ne doit contenir que des commandes payées")
	}
}

// Un paiement au montant incohérent passe en échec au lieu de rester en attente.
func TestAmountMismatchFailsPayment(t *testing.T) {
	requireApp(t)
	s := newSeller(t, 5)
	b := newBuyer(t, s.lat, s.lng)
	oid := mustStatus(t, order(t, b, s.untrackedID, 1, "pickup"), http.StatusCreated).str("id")
	pid := mustStatus(t, call(t, b.token, "POST", "/v1/orders/"+oid+"/payments", map[string]string{"operator": "flooz", "phone": "90123456"}), http.StatusCreated).str("id")
	mustStatus(t, call(t, b.token, "POST", "/v1/dev/payments/"+pid+"/simulate", map[string]any{"outcome": "succeeded", "amount_xof": 10}), http.StatusOK)
	eventually(t, "paiement en échec", func() bool {
		return call(t, b.token, "GET", "/v1/payments/"+pid, nil).str("status") == "failed"
	})
	if orderStatus(t, b.token, oid) != "pending_payment" {
		t.Fatal("la commande ne doit pas être validée")
	}
}

// La suppression du compte efface l'adresse de livraison copiée dans ses commandes.
func TestAccountDeletionErasesDeliveryAddresses(t *testing.T) {
	requireApp(t)
	s := newSeller(t, 5)
	b := newBuyer(t, s.lat, s.lng)
	oid := mustStatus(t, order(t, b, s.untrackedID, 1, "delivery"), http.StatusCreated).str("id")
	exec(t, "UPDATE orders SET payment_deadline_at = now() - interval '1 second' WHERE id = $1", uuid.MustParse(oid))
	if err := testApp.Orders.ExpirePayment(ctx(), uuid.MustParse(oid)); err != nil {
		t.Fatal(err)
	}
	mustStatus(t, call(t, b.token, "DELETE", "/v1/me", nil), http.StatusNoContent)

	var text, instructions *string
	var hasLocation bool
	var total int64
	if err := testDB.Pool.QueryRow(ctx(),
		"SELECT delivery_address_text, delivery_instructions, delivery_location IS NOT NULL, total_xof FROM orders WHERE id = $1", oid,
	).Scan(&text, &instructions, &hasLocation, &total); err != nil {
		t.Fatal(err)
	}
	if text != nil || instructions != nil || hasLocation {
		t.Fatal("l'adresse de livraison doit être effacée")
	}
	if total == 0 {
		t.Fatal("les montants sont conservés")
	}
}
