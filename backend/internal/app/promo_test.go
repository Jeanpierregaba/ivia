package app_test

import (
	"bytes"
	"fmt"
	"net/http"
	"testing"
	"time"
)

// uploadImage envoie une image PNG par URL signée pour l'usage donné et retourne la clé.
func uploadImage(t *testing.T, token, purpose string) string {
	t.Helper()
	content := []byte("\x89PNG\r\n\x1a\nimage de test")
	up := mustStatus(t, call(t, token, "POST", "/v1/uploads", map[string]any{
		"purpose": purpose, "content_type": "image/png", "size_bytes": len(content),
	}), http.StatusCreated)
	signed := up.Body["upload"].(map[string]any)
	req, _ := http.NewRequest(http.MethodPut, signed["url"].(string), bytes.NewReader(content))
	req.Header.Set("Content-Type", "image/png")
	res, err := http.DefaultClient.Do(req)
	if err != nil || res.StatusCode != http.StatusOK {
		t.Fatalf("envoi de l'image : %v %v", err, res)
	}
	res.Body.Close()
	return up.str("object_key")
}

func TestProductPromotionAppliesToCartAndCheckout(t *testing.T) {
	requireApp(t)
	s := newSeller(t, 10)
	b := newBuyer(t, s.lat, s.lng)
	adm := admin(t)
	path := "/v1/admin/products/" + s.untrackedID + "/marketing"

	// Validation : promotion au moins égale au prix, badge inconnu, rang hors bornes.
	for _, body := range []map[string]any{
		{"promo_price_xof": 5000},
		{"badges": []string{"gratuit"}},
		{"featured_rank": 0},
	} {
		if r := call(t, adm, "PUT", path, body); r.Status != http.StatusBadRequest {
			t.Fatalf("%v accepté : %d %s", body, r.Status, r.Raw)
		}
	}
	// Le marchand n'y a pas accès.
	if r := call(t, s.token, "PUT", path, map[string]any{"featured_rank": 1}); r.Status != http.StatusForbidden {
		t.Fatalf("marchand : %d", r.Status)
	}

	p := mustStatus(t, call(t, adm, "PUT", path, map[string]any{
		"promo_price_xof": 3500, "badges": []string{"promotion", "featured", "promotion"},
		"featured_rank": 1, "features": []string{"Eau minérale naturelle", " ", "Faiblement minéralisée"},
	}), http.StatusOK)
	if p.Body["effective_price_xof"].(float64) != 3500 || p.Body["promo_active"] != true ||
		len(p.Body["badges"].([]any)) != 2 || len(p.Body["features"].([]any)) != 2 {
		t.Fatalf("promotion : %s", p.Raw)
	}

	// Mis en avant : premier des produits mis en avant et en tête de la recherche par défaut.
	feat := mustStatus(t, call(t, "", "GET", "/v1/products/featured", nil), http.StatusOK).Body["items"].([]any)
	if len(feat) == 0 {
		t.Fatal("aucun produit mis en avant")
	}
	hits := mustStatus(t, call(t, "", "GET", fmt.Sprintf("/v1/search/products?shop_id=%s", s.shopID), nil), http.StatusOK).Body["items"].([]any)
	first := hits[0].(map[string]any)
	if first["id"] != s.untrackedID || first["effective_price_xof"].(float64) != 3500 {
		t.Fatalf("recherche : %v", first)
	}

	// Le panier et la commande facturent le prix promotionnel.
	mustStatus(t, call(t, b.token, "PUT", "/v1/cart/items", map[string]any{"product_id": s.untrackedID, "quantity": 2}), http.StatusOK)
	cart := mustStatus(t, call(t, b.token, "GET", "/v1/cart", nil), http.StatusOK)
	line := cart.Body["items"].([]any)[0].(map[string]any)
	if line["unit_price_xof"].(float64) != 3500 || line["line_total_xof"].(float64) != 7000 {
		t.Fatalf("panier : %s", cart.Raw)
	}
	o := order(t, b, s.untrackedID, 2, "pickup")
	if o.Body["subtotal_xof"].(float64) != 7000 {
		t.Fatalf("commande : %s", o.Raw)
	}

	// Promotion à venir : prix normal.
	start := time.Now().Add(48 * time.Hour).UTC().Format(time.RFC3339)
	p = mustStatus(t, call(t, adm, "PUT", path, map[string]any{"promo_price_xof": 3000, "promo_starts_at": start}), http.StatusOK)
	if p.Body["effective_price_xof"].(float64) != 5000 || p.Body["promo_active"] != false || p.Body["featured_rank"] != nil {
		t.Fatalf("promotion à venir : %s", p.Raw)
	}
	// Prix normal abaissé sous la promotion : refusé par la base (contrainte), message clair.
	cur := mustStatus(t, call(t, adm, "GET", "/v1/admin/products/"+s.untrackedID, nil), http.StatusOK)
	r := call(t, adm, "PATCH", "/v1/admin/products/"+s.untrackedID, map[string]any{
		"category_id": cur.str("category_id"), "name": cur.str("name"), "price_xof": 2500, "parcel_size": cur.str("parcel_size"),
	})
	if r.Status != http.StatusBadRequest {
		t.Fatalf("prix sous la promotion : %d %s", r.Status, r.Raw)
	}
}

func TestAdminManagesPlatformShopProducts(t *testing.T) {
	requireApp(t)
	s := newSeller(t, 1)
	adm := admin(t)

	// Brouillon à prix « à renseigner » (0), avec une photo envoyée par l'admin.
	key := uploadImage(t, adm, "product_image")
	d := mustStatus(t, call(t, adm, "POST", "/v1/admin/shops/"+s.shopID+"/products", map[string]any{
		"category_id": category(t), "name": "Eau minérale IVI 1,5 L", "price_xof": 0, "parcel_size": "medium",
		"stock_mode": "tracked", "stock_quantity": 0, "is_active": false, "image_keys": []string{key},
	}), http.StatusCreated)
	id := d.str("id")
	if d.str("status") != "draft" || len(d.Body["images"].([]any)) != 1 {
		t.Fatalf("brouillon : %s", d.Raw)
	}
	// Mise en vente sans prix : refusée.
	body := map[string]any{"category_id": category(t), "name": "Eau minérale IVI 1,5 L", "price_xof": 0, "parcel_size": "medium", "is_active": true}
	if r := call(t, adm, "PATCH", "/v1/admin/products/"+id, body); r.Status != http.StatusBadRequest {
		t.Fatalf("mise en vente sans prix : %d %s", r.Status, r.Raw)
	}
	body["price_xof"] = 400
	if r := mustStatus(t, call(t, adm, "PATCH", "/v1/admin/products/"+id, body), http.StatusOK); r.str("status") != "active" {
		t.Fatalf("mise en vente : %s", r.Raw)
	}
	if r := mustStatus(t, call(t, adm, "PUT", "/v1/admin/products/"+id+"/stock", map[string]any{"quantity": 120}), http.StatusOK); r.Body["stock_quantity"].(float64) != 120 {
		t.Fatalf("stock : %s", r.Raw)
	}
	list := mustStatus(t, call(t, adm, "GET", "/v1/admin/products?shop_id="+s.shopID+"&q=min%C3%A9rale", nil), http.StatusOK).Body["items"].([]any)
	if len(list) != 1 {
		t.Fatalf("liste admin : %d", len(list))
	}
	// Le marchand ne peut pas signer d'image publicitaire.
	if r := call(t, s.token, "POST", "/v1/uploads", map[string]any{"purpose": "promo_visual", "content_type": "image/png", "size_bytes": 10}); r.Status != http.StatusForbidden {
		t.Fatalf("visuel signé par un marchand : %d", r.Status)
	}
}

func TestPromoVisualsFeedEventsAndStats(t *testing.T) {
	requireApp(t)
	s := newSeller(t, 1)
	adm := admin(t)
	key := uploadImage(t, adm, "promo_visual")

	bad := []map[string]any{
		{"kind": "popup", "title": "IVI", "image_key": key, "placements": []string{"modal"}},
		{"kind": "modal", "title": "IVI", "image_key": key, "placements": []string{}},
		{"kind": "modal", "title": "IVI", "image_key": key, "placements": []string{"modal"}, "external_url": "http://exemple.tg"},
		{"kind": "modal", "title": "IVI", "image_key": "promo/autre/x.png", "placements": []string{"modal"}},
	}
	for _, b := range bad {
		if r := call(t, adm, "POST", "/v1/admin/promo/visuals", b); r.Status != http.StatusBadRequest {
			t.Fatalf("%v accepté : %d %s", b, r.Status, r.Raw)
		}
	}
	v := mustStatus(t, call(t, adm, "POST", "/v1/admin/promo/visuals", map[string]any{
		"kind": "modal", "title": "AWU IVI 1,5 L", "subtitle": "Eau minérale naturelle", "image_key": key,
		"product_id": s.untrackedID, "cta_label": "Commander", "external_url": "https://www.eaumineraleivi.com",
		"placements": []string{"modal", "home_hero"}, "priority": 90, "weight": 5,
	}), http.StatusCreated)
	vid := v.str("id")
	if v.Body["live"] != true || v.str("image_url") == "" {
		t.Fatalf("visuel : %s", v.Raw)
	}
	// Visuel programmé : absent du fil.
	future := time.Now().Add(72 * time.Hour).UTC().Format(time.RFC3339)
	later := mustStatus(t, call(t, adm, "POST", "/v1/admin/promo/visuals", map[string]any{
		"kind": "monthly", "title": "Visuel du mois prochain", "image_key": key, "placements": []string{"home_hero"}, "starts_at": future,
	}), http.StatusCreated)

	feed := mustStatus(t, call(t, "", "GET", "/v1/promo/feed?app=buyer", nil), http.StatusOK)
	found, scheduled := false, false
	for _, it := range feed.Body["visuals"].([]any) {
		m := it.(map[string]any)
		if m["id"] == vid {
			found = m["product"] != nil
		}
		if m["id"] == later.str("id") {
			scheduled = true
		}
	}
	if !found || scheduled {
		t.Fatalf("fil : trouvé=%v programmé=%v %s", found, scheduled, feed.Raw)
	}
	if feed.Body["settings"].(map[string]any)["official_url"] != "https://www.eaumineraleivi.com" {
		t.Fatalf("réglages du fil : %s", feed.Raw)
	}
	// Absent du fil livreur (visuel réservé à l'app acheteur).
	for _, it := range mustStatus(t, call(t, "", "GET", "/v1/promo/feed?app=driver", nil), http.StatusOK).Body["visuals"].([]any) {
		if it.(map[string]any)["id"] == vid {
			t.Fatal("visuel acheteur dans le fil livreur")
		}
	}

	// Événements : les invalides sont ignorés, session invalide refusée.
	if r := call(t, "", "POST", "/v1/promo/events", map[string]any{"app": "buyer", "session_id": "x", "events": []any{}}); r.Status != http.StatusBadRequest {
		t.Fatalf("session invalide : %d", r.Status)
	}
	ev := mustStatus(t, call(t, "", "POST", "/v1/promo/events", map[string]any{
		"app": "buyer", "session_id": "test-session-0001",
		"events": []map[string]any{
			{"kind": "impression", "visual_id": vid, "product_id": s.untrackedID, "placement": "modal"},
			{"kind": "impression", "visual_id": vid, "placement": "modal"},
			{"kind": "click_site", "visual_id": vid, "placement": "modal"},
			{"kind": "dismiss", "visual_id": vid},
			{"kind": "hack", "visual_id": vid},
			{"kind": "impression"},
		},
	}), http.StatusOK)
	if ev.Body["recorded"].(float64) != 4 {
		t.Fatalf("événements : %s", ev.Raw)
	}

	st := mustStatus(t, call(t, adm, "GET", "/v1/admin/promo/stats", nil), http.StatusOK)
	var vs map[string]any
	for _, it := range st.Body["visuals"].([]any) {
		if m := it.(map[string]any); m["visual_id"] == vid {
			vs = m
		}
	}
	if vs == nil || vs["impressions"].(float64) != 2 || vs["site_clicks"].(float64) != 1 || vs["dismissals"].(float64) != 1 || vs["ctr_pct"].(float64) != 50 {
		t.Fatalf("statistiques du visuel : %v", vs)
	}

	// Réglages : publicité coupée, fil vide.
	set := mustStatus(t, call(t, adm, "GET", "/v1/admin/promo/settings", nil), http.StatusOK).Body
	set["enabled"] = false
	mustStatus(t, call(t, adm, "PUT", "/v1/admin/promo/settings", set), http.StatusOK)
	if n := len(mustStatus(t, call(t, "", "GET", "/v1/promo/feed", nil), http.StatusOK).Body["visuals"].([]any)); n != 0 {
		t.Fatalf("publicité coupée : %d visuels", n)
	}
	set["enabled"] = true
	set["min_interval_seconds"] = 5
	if r := call(t, adm, "PUT", "/v1/admin/promo/settings", set); r.Status != http.StatusBadRequest {
		t.Fatalf("intervalle trop court accepté : %d", r.Status)
	}
	set["min_interval_seconds"] = 90
	mustStatus(t, call(t, adm, "PUT", "/v1/admin/promo/settings", set), http.StatusOK)

	mustStatus(t, call(t, adm, "DELETE", "/v1/admin/promo/visuals/"+vid, nil), http.StatusNoContent)
	if r := call(t, adm, "GET", "/v1/admin/promo/visuals/"+vid, nil); r.Status != http.StatusNotFound {
		t.Fatalf("visuel supprimé : %d", r.Status)
	}
	mustStatus(t, call(t, adm, "DELETE", "/v1/admin/promo/visuals/"+later.str("id"), nil), http.StatusNoContent)
}
