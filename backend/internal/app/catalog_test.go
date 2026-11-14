package app_test

import (
	"context"
	"fmt"
	"net/http"
	"net/url"
	"testing"
	"time"

	"ivia/backend/internal/platform/database"
)

// newProduct crée un produit dans la boutique ; active nil : champ absent (en vente par défaut).
func newProduct(t *testing.T, s sellerFixture, name string, active *bool) resp {
	t.Helper()
	body := map[string]any{
		"category_id": category(t), "name": name, "price_xof": 4500,
		"parcel_size": "medium", "stock_mode": "untracked",
	}
	if active != nil {
		body["is_active"] = *active
	}
	return mustStatus(t, call(t, s.token, "POST", "/v1/seller/shops/"+s.shopID+"/products", body), http.StatusCreated)
}

// setActive publie ou retire un produit (corps complet, comme l'app).
func setActive(t *testing.T, s sellerFixture, id string, active bool) resp {
	t.Helper()
	cur := mustStatus(t, call(t, s.token, "GET", "/v1/seller/products/"+id, nil), http.StatusOK)
	return mustStatus(t, call(t, s.token, "PATCH", "/v1/seller/products/"+id, map[string]any{
		"category_id": cur.str("category_id"), "name": cur.str("name"), "description": cur.str("description"),
		"price_xof": cur.Body["price_xof"], "parcel_size": cur.str("parcel_size"), "is_active": active,
	}), http.StatusOK)
}

func ptr[T any](v T) *T { return &v }

func timeOf(t *testing.T, r resp, key string) *time.Time {
	t.Helper()
	v, ok := r.Body[key].(string)
	if !ok {
		return nil
	}
	ts, err := time.Parse(time.RFC3339Nano, v)
	if err != nil {
		t.Fatalf("%s : %v", key, err)
	}
	return &ts
}

func TestProductPublicationStates(t *testing.T) {
	requireApp(t)
	s := newSeller(t, 5)

	// Sans is_active : en vente, comme avant.
	def := newProduct(t, s, "Par défaut", nil)
	if def.str("status") != "active" || timeOf(t, def, "published_at") == nil || def.Body["withdrawn_at"] != nil {
		t.Fatalf("création par défaut : %s", def.Raw)
	}

	// Brouillon : non visible, sans date.
	d := newProduct(t, s, "Brouillon", ptr(false))
	id := d.str("id")
	if d.str("status") != "draft" || d.Body["published_at"] != nil || d.Body["withdrawn_at"] != nil || d.Body["is_active"] != false {
		t.Fatalf("brouillon : %s", d.Raw)
	}
	if r := call(t, "", "GET", "/v1/products/"+id, nil); r.Status != http.StatusNotFound {
		t.Fatalf("brouillon visible du public : %d", r.Status)
	}
	// Un brouillon modifié reste un brouillon.
	if r := setActive(t, s, id, false); r.str("status") != "draft" || r.Body["withdrawn_at"] != nil {
		t.Fatalf("brouillon modifié : %s", r.Raw)
	}

	// Publication.
	p := setActive(t, s, id, true)
	published := timeOf(t, p, "published_at")
	if p.str("status") != "active" || published == nil || p.Body["withdrawn_at"] != nil {
		t.Fatalf("publication : %s", p.Raw)
	}
	mustStatus(t, call(t, "", "GET", "/v1/products/"+id, nil), http.StatusOK)
	// Modifié en restant en vente : la date de publication ne bouge pas.
	if r := setActive(t, s, id, true); !timeOf(t, r, "published_at").Equal(*published) {
		t.Fatalf("date de publication changée : %s", r.Raw)
	}

	// Retrait.
	w := setActive(t, s, id, false)
	withdrawn := timeOf(t, w, "withdrawn_at")
	if w.str("status") != "withdrawn" || withdrawn == nil || !timeOf(t, w, "published_at").Equal(*published) {
		t.Fatalf("retrait : %s", w.Raw)
	}
	// Modifié en restant retiré : la date de retrait ne bouge pas.
	if r := setActive(t, s, id, false); r.str("status") != "withdrawn" || !timeOf(t, r, "withdrawn_at").Equal(*withdrawn) {
		t.Fatalf("retiré modifié : %s", r.Raw)
	}

	// Remise en vente : nouvelle date de publication, plus de date de retrait.
	again := setActive(t, s, id, true)
	if again.str("status") != "active" || again.Body["withdrawn_at"] != nil || !timeOf(t, again, "published_at").After(*published) {
		t.Fatalf("remise en vente : %s", again.Raw)
	}
}

func TestProductPublicationConstraint(t *testing.T) {
	requireApp(t)
	s := newSeller(t, 5)
	id := newProduct(t, s, "Cohérence", nil).str("id")
	// En vente avec une date de retrait : refusé par la base.
	_, err := testDB.Pool.Exec(context.Background(), "UPDATE products SET withdrawn_at = now() WHERE id = $1", id)
	if !database.IsCheckViolation(err, "products_publication_check") {
		t.Fatalf("en vente et retiré : %v", err)
	}
	// Inactif sans date de publication mais avec une date de retrait : refusé.
	_, err = testDB.Pool.Exec(context.Background(),
		"UPDATE products SET is_active = false, published_at = NULL, withdrawn_at = now() WHERE id = $1", id)
	if !database.IsCheckViolation(err, "products_publication_check") {
		t.Fatalf("retiré sans publication : %v", err)
	}
}

func TestSellerProductFilters(t *testing.T) {
	requireApp(t)
	s := newSeller(t, 5) // 3 produits en vente : « Produit suivi », « Produit libre », « Gros produit »
	newProduct(t, s, "Café moulu 250 g", nil)
	newProduct(t, s, "Riz parfumé 5 kg", ptr(false))
	newProduct(t, s, "Remise 100% riz", ptr(false))
	gone := newProduct(t, s, "Ancien riz", nil).str("id")
	setActive(t, s, gone, false)
	older := newProduct(t, s, "Retiré avant", nil).str("id")
	setActive(t, s, older, false)
	setActive(t, s, gone, true)
	setActive(t, s, gone, false) // retiré en dernier : premier de l'onglet

	list := func(query url.Values) []string {
		t.Helper()
		r := mustStatus(t, call(t, s.token, "GET", "/v1/seller/shops/"+s.shopID+"/products?"+query.Encode(), nil), http.StatusOK)
		items, _ := r.Body["items"].([]any)
		names := make([]string, len(items))
		for i, it := range items {
			names[i] = it.(map[string]any)["name"].(string)
		}
		return names
	}
	same := func(what string, got, want []string) {
		t.Helper()
		if len(got) != len(want) {
			t.Fatalf("%s : %v, attendu %v", what, got, want)
		}
		for i := range got {
			if got[i] != want[i] {
				t.Fatalf("%s : %v, attendu %v", what, got, want)
			}
		}
	}

	if got := list(url.Values{}); len(got) != 8 {
		t.Fatalf("sans filtre : %v", got)
	}
	same("en vente", list(url.Values{"status": {"active"}}),
		[]string{"Café moulu 250 g", "Gros produit", "Produit libre", "Produit suivi"})
	same("brouillons", list(url.Values{"status": {"draft"}}), []string{"Remise 100% riz", "Riz parfumé 5 kg"})
	same("retirés, du plus récent", list(url.Values{"status": {"withdrawn"}}), []string{"Ancien riz", "Retiré avant"})

	// Recherche : accents et majuscules ignorés, combinée à l'état.
	same("cafe", list(url.Values{"q": {"CAFE"}}), []string{"Café moulu 250 g"})
	same("riz en brouillon", list(url.Values{"q": {"riz"}, "status": {"draft"}}), []string{"Remise 100% riz", "Riz parfumé 5 kg"})
	// Jokers pris à la lettre.
	same("% littéral", list(url.Values{"q": {"100%"}}), []string{"Remise 100% riz"})
	same("_ littéral", list(url.Values{"q": {"_"}}), []string{})
	same("espaces seuls", list(url.Values{"q": {"   "}, "status": {"draft"}}), []string{"Remise 100% riz", "Riz parfumé 5 kg"})

	// Pagination.
	r := mustStatus(t, call(t, s.token, "GET", "/v1/seller/shops/"+s.shopID+"/products?status=active&limit=3", nil), http.StatusOK)
	if items, _ := r.Body["items"].([]any); len(items) != 3 || r.Body["next_offset"] != float64(3) {
		t.Fatalf("pagination : %s", r.Raw)
	}

	// Paramètres invalides.
	if r := call(t, s.token, "GET", "/v1/seller/shops/"+s.shopID+"/products?status=archived", nil); r.Status != http.StatusBadRequest || !hasField(r, "status") {
		t.Fatalf("état inconnu : %d %s", r.Status, r.Raw)
	}
	long := make([]byte, 101)
	for i := range long {
		long[i] = 'a'
	}
	if r := call(t, s.token, "GET", "/v1/seller/shops/"+s.shopID+"/products?q="+string(long), nil); r.Status != http.StatusBadRequest || !hasField(r, "q") {
		t.Fatalf("recherche trop longue : %d %s", r.Status, r.Raw)
	}

	// Compteurs : tous les états, toute la boutique.
	c := mustStatus(t, call(t, s.token, "GET", "/v1/seller/shops/"+s.shopID+"/product-counts", nil), http.StatusOK)
	if c.Body["active"] != float64(4) || c.Body["draft"] != float64(2) || c.Body["withdrawn"] != float64(2) {
		t.Fatalf("compteurs : %s", c.Raw)
	}
}

func TestSellerProductListsOfAnotherShop(t *testing.T) {
	requireApp(t)
	s1, s2 := newSeller(t, 5), newSeller(t, 5)
	for _, path := range []string{
		"/v1/seller/shops/" + s1.shopID + "/products?status=active",
		"/v1/seller/shops/" + s1.shopID + "/product-counts",
	} {
		if r := call(t, s2.token, "GET", path, nil); r.Status != http.StatusNotFound {
			t.Errorf("%s par un autre marchand : %d, attendu 404", path, r.Status)
		}
	}
	// Compteurs d'une boutique : ceux de l'autre ne s'y ajoutent pas.
	newProduct(t, s2, "Brouillon de s2", ptr(false))
	c := mustStatus(t, call(t, s1.token, "GET", "/v1/seller/shops/"+s1.shopID+"/product-counts", nil), http.StatusOK)
	if c.Body["active"] != float64(3) || c.Body["draft"] != float64(0) || c.Body["withdrawn"] != float64(0) {
		t.Fatalf("compteurs de s1 : %s", c.Raw)
	}
	// Acheteur : route marchand interdite.
	b := newBuyer(t, s1.lat, s1.lng)
	if r := call(t, b.token, "GET", "/v1/seller/shops/"+s1.shopID+"/product-counts", nil); r.Status != http.StatusForbidden {
		t.Errorf("acheteur : %d, attendu 403", r.Status)
	}
}

// Catégorie désactivée par l'admin : le produit ne peut plus rester ni revenir en vente sans en
// changer, mais il peut toujours être retiré ou gardé en brouillon.
func TestWithdrawWithInactiveCategory(t *testing.T) {
	requireApp(t)
	s := newSeller(t, 5)
	cat := mustStatus(t, call(t, admin(t), "POST", "/v1/admin/categories", map[string]any{
		"name": fmt.Sprintf("Éphémère %d", seq.Add(1)),
	}), http.StatusCreated).str("id")
	body := func(active bool) map[string]any {
		return map[string]any{
			"category_id": cat, "name": "Jus de bissap", "price_xof": 800,
			"parcel_size": "small", "stock_mode": "untracked", "is_active": active,
		}
	}
	id := mustStatus(t, call(t, s.token, "POST", "/v1/seller/shops/"+s.shopID+"/products", body(true)), http.StatusCreated).str("id")
	mustStatus(t, call(t, admin(t), "PATCH", "/v1/admin/categories/"+cat, map[string]any{
		"name": "Désactivée " + id, "is_active": false,
	}), http.StatusOK)

	// Rester en vente avec la catégorie désactivée : refusé.
	if r := call(t, s.token, "PATCH", "/v1/seller/products/"+id, body(true)); !hasField(r, "category_id") {
		t.Fatalf("en vente, catégorie désactivée : %d %s", r.Status, r.Raw)
	}
	// Retrait : accepté.
	w := mustStatus(t, call(t, s.token, "PATCH", "/v1/seller/products/"+id, body(false)), http.StatusOK)
	if w.str("status") != "withdrawn" {
		t.Fatalf("retrait : %s", w.Raw)
	}
	// Remise en vente sans changer de catégorie : refusée.
	if r := call(t, s.token, "PATCH", "/v1/seller/products/"+id, body(true)); !hasField(r, "category_id") {
		t.Fatalf("remise en vente, catégorie désactivée : %d %s", r.Status, r.Raw)
	}
	// Retiré, autre catégorie inconnue : refusée (catégorie changée).
	other := body(false)
	other["category_id"] = "7d5c1d38-3c1b-4b8f-9a77-1f2e3d4c5b6a"
	if r := call(t, s.token, "PATCH", "/v1/seller/products/"+id, other); !hasField(r, "category_id") {
		t.Fatalf("catégorie changée inconnue : %d %s", r.Status, r.Raw)
	}
}
