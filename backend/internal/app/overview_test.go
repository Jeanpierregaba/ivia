package app_test

import (
	"net/http"
	"testing"
)

// Le tableau de bord du back-office tient en un appel et suit l'activité réelle.
func TestAdminOverview(t *testing.T) {
	requireApp(t)
	s := newSeller(t, 10)
	b := newBuyer(t, s.lat, s.lng)

	fresh := mustStatus(t, order(t, b, s.untrackedID, 1, "pickup"), http.StatusCreated).str("id")
	pay(t, b, fresh)
	accepted := mustStatus(t, order(t, b, s.untrackedID, 2, "pickup"), http.StatusCreated).str("id")
	pay(t, b, accepted)
	mustStatus(t, call(t, s.token, "POST", "/v1/seller/orders/"+accepted+"/accept", map[string]any{}), http.StatusOK)
	rejected := mustStatus(t, order(t, b, s.untrackedID, 1, "pickup"), http.StatusCreated).str("id")
	pay(t, b, rejected)
	mustStatus(t, call(t, s.token, "POST", "/v1/seller/orders/"+rejected+"/reject", map[string]any{}), http.StatusOK)

	o := mustStatus(t, call(t, admin(t), "GET", "/v1/admin/overview", nil), http.StatusOK)
	num := func(m map[string]any, k string) float64 { v, _ := m[k].(float64); return v }
	obj := func(k string) map[string]any { return o.Body[k].(map[string]any) }

	if o.str("period") != "today" || len(o.Body["paid_per_day"].([]any)) != 14 {
		t.Fatalf("période ou graphique : %v %d", o.Body["period"], len(o.Body["paid_per_day"].([]any)))
	}
	if num(obj("kpis"), "paid_orders") < 3 {
		t.Fatalf("commandes payées aujourd'hui : %v", obj("kpis"))
	}
	today := o.Body["paid_per_day"].([]any)[13].(map[string]any)
	if num(today, "pickup") < 3 {
		t.Fatalf("retraits payés aujourd'hui : %v", today)
	}
	if num(obj("todo"), "refunds") < 1 || num(obj("todo"), "refunds_xof") <= 0 {
		t.Fatalf("remboursement en attente attendu : %v", obj("todo"))
	}
	active := obj("active_orders")
	if num(active, "to_accept") < 1 || num(active, "all") < 2 {
		t.Fatalf("commandes en cours : %v", active)
	}
	found := map[string]bool{}
	for _, it := range active["items"].([]any) {
		row := it.(map[string]any)
		found[row["id"].(string)] = true
		if row["shop_name"] == "" || row["buyer_name"] == "" || row["reference"] == "" || row["since"] == "" {
			t.Fatalf("ligne incomplète : %v", row)
		}
	}
	if !found[fresh] || !found[accepted] || found[rejected] {
		t.Fatalf("lignes « en cours » : %v", found)
	}
	if num(obj("payments"), "succeeded") < 3 || num(obj("sidebar"), "orders") != num(active, "all") {
		t.Fatalf("paiements ou barre latérale : %v %v", obj("payments"), obj("sidebar"))
	}
	if len(o.Body["audit"].([]any)) == 0 {
		t.Fatal("journal vide (au moins la validation de la boutique de test)")
	}
	line := o.Body["audit"].([]any)[0].(map[string]any)
	if line["admin_name"] == "" || line["admin_initials"] == "" {
		t.Fatalf("ligne du journal : %v", line)
	}

	// Filtre « à accepter » : seules les commandes en attente du marchand.
	g := mustStatus(t, call(t, admin(t), "GET", "/v1/admin/overview?group=to_accept&period=7d", nil), http.StatusOK)
	for _, it := range g.Body["active_orders"].(map[string]any)["items"].([]any) {
		if st := it.(map[string]any)["status"]; st != "awaiting_seller" {
			t.Fatalf("groupe à accepter : statut %v", st)
		}
	}
	if g.str("period") != "7d" {
		t.Fatalf("période : %v", g.Body["period"])
	}
	if r := call(t, admin(t), "GET", "/v1/admin/overview?period=year", nil); r.code() != "validation_failed" {
		t.Fatalf("période inconnue : %d %s", r.Status, r.code())
	}
	// Réservé aux admins vérifiés par code.
	if r := call(t, s.token, "GET", "/v1/admin/overview", nil); r.Status != http.StatusForbidden {
		t.Fatalf("marchand : %d", r.Status)
	}
}
