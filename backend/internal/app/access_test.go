package app_test

import (
	"net/http"
	"strconv"
	"testing"
)

func ftoa(f float64) string { return strconv.FormatFloat(f, 'f', 6, 64) }

// Chaque route vérifie le rôle (403) et la propriété de la ressource (404 sur celle d'autrui).
func TestAccessControl(t *testing.T) {
	requireApp(t)
	s1, s2 := newSeller(t, 5), newSeller(t, 5)
	b1, b2 := newBuyer(t, s1.lat, s1.lng), newBuyer(t, s1.lat, s1.lng)
	oid := mustStatus(t, order(t, b1, s1.untrackedID, 1, "pickup"), http.StatusCreated).str("id")
	pay(t, b1, oid)

	cases := []struct {
		name, token, method, path string
		status                    int
	}{
		{"anonyme", "", "GET", "/v1/orders", http.StatusUnauthorized},
		{"commande d'un autre acheteur", b2.token, "GET", "/v1/orders/" + oid, http.StatusNotFound},
		{"annulation d'une commande d'autrui", b2.token, "POST", "/v1/orders/" + oid + "/cancel", http.StatusNotFound},
		{"paiement sur la commande d'autrui", b2.token, "POST", "/v1/orders/" + oid + "/payments", http.StatusBadRequest},
		{"commande d'une autre boutique", s2.token, "GET", "/v1/seller/orders/" + oid, http.StatusNotFound},
		{"acceptation par un autre marchand", s2.token, "POST", "/v1/seller/orders/" + oid + "/accept", http.StatusNotFound},
		{"produit d'un autre marchand", s2.token, "PATCH", "/v1/seller/products/" + s1.trackedID, http.StatusNotFound},
		{"acheteur sur une route marchand", b1.token, "GET", "/v1/seller/orders", http.StatusForbidden},
		{"marchand sur une route admin", s1.token, "GET", "/v1/admin/orders", http.StatusForbidden},
		{"acheteur sur une route livreur", b1.token, "GET", "/v1/driver/offers/current", http.StatusForbidden},
		{"identifiant mal formé", b1.token, "GET", "/v1/orders/pas-un-uuid", http.StatusNotFound},
	}
	for _, c := range cases {
		var body any
		if c.method != "GET" {
			body = map[string]any{}
		}
		if r := call(t, c.token, c.method, c.path, body); r.Status != c.status {
			t.Errorf("%s : statut %d, attendu %d (%s)", c.name, r.Status, c.status, r.Raw)
		}
	}
	// Produit d'autrui avec un corps valide : introuvable.
	r := call(t, s2.token, "PATCH", "/v1/seller/products/"+s1.trackedID, map[string]any{
		"category_id": category(t), "name": "Piraté", "price_xof": 1, "parcel_size": "small",
	})
	if r.Status != http.StatusNotFound {
		t.Errorf("modification du produit d'autrui : %d, attendu 404", r.Status)
	}
	// Paiement sur la commande d'autrui avec un corps valide : introuvable.
	r = call(t, b2.token, "POST", "/v1/orders/"+oid+"/payments", map[string]string{"operator": "flooz", "phone": "90000003"})
	if r.Status != http.StatusNotFound {
		t.Errorf("paiement de la commande d'autrui : %d, attendu 404", r.Status)
	}

	// Une boutique suspendue perd l'accès aux actions marchand dès la requête suivante.
	mustStatus(t, call(t, admin(t), "POST", "/v1/admin/shops/"+s1.shopID+"/suspend", map[string]string{"reason": "Contrôle"}), http.StatusOK)
	if r := call(t, s1.token, "POST", "/v1/seller/orders/"+oid+"/accept", map[string]any{}); r.code() != "shop_suspended" {
		t.Errorf("boutique suspendue : %s", r.Raw)
	}
	if r := call(t, "", "GET", "/v1/shops/"+s1.shopID, nil); r.Status != http.StatusNotFound {
		t.Errorf("une boutique suspendue n'est plus visible : %d", r.Status)
	}

	// Les rôles driver et admin ne s'obtiennent jamais par l'inscription.
	me := mustStatus(t, call(t, b2.token, "GET", "/v1/me", nil), http.StatusOK)
	if roles := me.Body["roles"].([]any); len(roles) != 1 || roles[0] != "buyer" {
		t.Errorf("rôles d'un nouvel inscrit : %v", roles)
	}
	if r := call(t, b2.token, "POST", "/v1/admin/users/"+me.str("id")+"/grant-admin", map[string]any{}); r.Status != http.StatusForbidden {
		t.Errorf("auto-attribution du rôle admin : %d", r.Status)
	}
}

// Un livreur suspendu perd l'accès immédiatement.
func TestSuspendedDriver(t *testing.T) {
	requireApp(t)
	d := newDriver(t, 1.0, 1.0, "motorbike")
	id := mustStatus(t, call(t, d, "GET", "/v1/me", nil), http.StatusOK).str("id")
	mustStatus(t, call(t, admin(t), "POST", "/v1/admin/drivers/"+id+"/suspend", map[string]string{"reason": "Documents expirés"}), http.StatusOK)
	if r := call(t, d, "GET", "/v1/driver/offers/current", nil); r.code() != "driver_suspended" {
		t.Errorf("livreur suspendu : %s", r.Raw)
	}
	if r := call(t, d, "POST", "/v1/driver/location", map[string]float64{"lat": 1, "lng": 1}); r.code() != "driver_suspended" {
		t.Errorf("position d'un livreur suspendu : %s", r.Raw)
	}
}

// Suppression de compte : refusée avec une commande en cours, puis anonymisation.
func TestAccountDeletion(t *testing.T) {
	requireApp(t)
	s := newSeller(t, 5)
	b := newBuyer(t, s.lat, s.lng)
	oid := mustStatus(t, order(t, b, s.untrackedID, 1, "pickup"), http.StatusCreated).str("id")
	pay(t, b, oid)
	if r := call(t, b.token, "DELETE", "/v1/me", nil); r.code() != "active_orders" {
		t.Fatalf("suppression avec commande en cours : %s", r.Raw)
	}
	for _, step := range []string{"accept", "preparing", "ready"} {
		mustStatus(t, call(t, s.token, "POST", "/v1/seller/orders/"+oid+"/"+step, map[string]any{}), http.StatusOK)
	}
	code := mustStatus(t, call(t, b.token, "GET", "/v1/orders/"+oid, nil), http.StatusOK).str("handover_code")
	mustStatus(t, call(t, s.token, "POST", "/v1/seller/orders/"+oid+"/handover", map[string]string{"code": code}), http.StatusOK)

	id := mustStatus(t, call(t, b.token, "GET", "/v1/me", nil), http.StatusOK).str("id")
	mustStatus(t, call(t, b.token, "DELETE", "/v1/me", nil), http.StatusNoContent)
	if r := call(t, b.token, "GET", "/v1/me", nil); r.Status != http.StatusUnauthorized {
		t.Fatalf("la session doit être révoquée : %d", r.Status)
	}
	var email, phone *string
	var first string
	var addresses, orders int
	_ = testDB.Pool.QueryRow(ctx(), "SELECT email, phone, first_name FROM users WHERE id = $1", id).Scan(&email, &phone, &first)
	_ = testDB.Pool.QueryRow(ctx(), "SELECT count(*) FROM addresses WHERE user_id = $1", id).Scan(&addresses)
	_ = testDB.Pool.QueryRow(ctx(), "SELECT count(*) FROM orders WHERE buyer_id = $1", id).Scan(&orders)
	if email != nil || phone != nil || first != "" || addresses != 0 {
		t.Fatalf("données personnelles non effacées : %v %v %q %d", email, phone, first, addresses)
	}
	if orders != 1 {
		t.Fatal("les commandes sont conservées pour la traçabilité financière")
	}
}

// Recherche : texte avec faute de frappe, prix, rayon ; jamais une boutique non publiée.
func TestSearch(t *testing.T) {
	requireApp(t)
	s := newSeller(t, 5)
	near := "/v1/search/products?lat=" + ftoa(s.lat) + "&lng=" + ftoa(s.lng) + "&radius_m=2000"
	r := mustStatus(t, call(t, "", "GET", near+"&q=prodiut+suivi", nil), http.StatusOK)
	if items := r.Body["items"].([]any); len(items) == 0 || items[0].(map[string]any)["id"] != s.trackedID {
		t.Fatalf("recherche tolérante aux fautes : %s", r.Raw)
	}
	r = mustStatus(t, call(t, "", "GET", near+"&max_price=100", nil), http.StatusOK)
	if len(r.Body["items"].([]any)) != 0 {
		t.Fatal("filtre de prix ignoré")
	}
	if r := call(t, "", "GET", "/v1/search/products?radius_m=1000", nil); r.code() != "validation_failed" {
		t.Fatalf("rayon sans position : %s", r.Raw)
	}
	mustStatus(t, call(t, admin(t), "POST", "/v1/admin/shops/"+s.shopID+"/suspend", map[string]string{"reason": "Test"}), http.StatusOK)
	r = mustStatus(t, call(t, "", "GET", near, nil), http.StatusOK)
	if len(r.Body["items"].([]any)) != 0 {
		t.Fatal("les produits d'une boutique suspendue ne doivent plus apparaître")
	}
}
