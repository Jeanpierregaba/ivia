package app_test

import (
	"net/http"
	"testing"
)

// Boutique gérée par ivia (IVI) : la commande payée arrive au back-office, qui l'accepte, la
// prépare et la remet au client avec son code ; une autre boutique reste hors de portée.
func TestPlatformManagedShopOrders(t *testing.T) {
	requireApp(t)
	adm := admin(t)
	ivi := newSeller(t, 10)
	other := newSeller(t, 10)
	b := newBuyer(t, ivi.lat, ivi.lng)

	sh := mustStatus(t, call(t, adm, "POST", "/v1/admin/shops/"+ivi.shopID+"/platform-managed", map[string]any{"managed": true}), http.StatusOK)
	if sh.Body["managed_by_platform"] != true {
		t.Fatalf("boutique gérée par ivia : %s", sh.Raw)
	}
	oid := mustStatus(t, order(t, b, ivi.untrackedID, 1, "pickup"), http.StatusCreated).str("id")
	pay(t, b, oid)

	list := mustStatus(t, call(t, adm, "GET", "/v1/admin/platform-orders?group=new", nil), http.StatusOK)
	found := false
	for _, it := range list.Body["items"].([]any) {
		found = found || it.(map[string]any)["id"] == oid
	}
	if !found {
		t.Fatalf("commande IVI absente du back-office : %s", list.Raw)
	}
	for _, step := range []string{"accept", "preparing", "ready"} {
		mustStatus(t, call(t, adm, "POST", "/v1/admin/platform-orders/"+oid+"/"+step, map[string]any{}), http.StatusOK)
	}
	code := mustStatus(t, call(t, b.token, "GET", "/v1/orders/"+oid, nil), http.StatusOK).str("handover_code")
	done := mustStatus(t, call(t, adm, "POST", "/v1/admin/platform-orders/"+oid+"/handover", map[string]any{"code": code}), http.StatusOK)
	if done.str("status") != "completed" {
		t.Fatalf("remise : %s", done.Raw)
	}

	// Commande d'une boutique ordinaire : introuvable pour cette page.
	b2 := newBuyer(t, other.lat, other.lng)
	o2 := mustStatus(t, order(t, b2, other.untrackedID, 1, "pickup"), http.StatusCreated).str("id")
	pay(t, b2, o2)
	if r := call(t, adm, "POST", "/v1/admin/platform-orders/"+o2+"/accept", map[string]any{}); r.Status != http.StatusNotFound {
		t.Fatalf("boutique ordinaire : %d %s", r.Status, r.Raw)
	}
	if r := call(t, b.token, "GET", "/v1/admin/platform-orders", nil); r.Status != http.StatusForbidden {
		t.Fatalf("réservé aux admins : %d", r.Status)
	}
}
