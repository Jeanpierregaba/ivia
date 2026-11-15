package app_test

import (
	"net/http"
	"strings"
	"testing"
)

// Le délai de réponse du marchand (15 min) est vérifié à l'acceptation et au refus, sans attendre
// la tâche de fond : une réponse en retard annule la commande et rembourse l'acheteur.
func TestSellerAnswerAfterDeadlineIsRefused(t *testing.T) {
	requireApp(t)
	s := newSeller(t, 10)
	b := newBuyer(t, s.lat, s.lng)

	for _, action := range []string{"accept", "reject"} {
		oid := mustStatus(t, order(t, b, s.untrackedID, 1, "pickup"), http.StatusCreated).str("id")
		pay(t, b, oid)
		// Délai dépassé, tâche de fond pas encore passée.
		exec(t, "UPDATE orders SET seller_deadline_at = now() - interval '1 second' WHERE id = $1", oid)

		r := call(t, s.token, "POST", "/v1/seller/orders/"+oid+"/"+action, map[string]any{})
		if r.Status != http.StatusConflict || r.code() != "seller_deadline_passed" {
			t.Fatalf("%s après le délai : %d %s", action, r.Status, r.code())
		}
		if st := orderStatus(t, b.token, oid); st != "cancelled" {
			t.Fatalf("%s après le délai : commande %s, attendue annulée", action, st)
		}
		got := mustStatus(t, call(t, s.token, "GET", "/v1/seller/orders/"+oid, nil), http.StatusOK)
		if reason, _ := got.Body["cancel_reason"].(string); !strings.Contains(reason, "pas répondu à temps") {
			t.Fatalf("%s après le délai : motif %q", action, reason)
		}
	}

	// Avant le délai, l'acceptation passe.
	oid := mustStatus(t, order(t, b, s.untrackedID, 1, "pickup"), http.StatusCreated).str("id")
	pay(t, b, oid)
	mustStatus(t, call(t, s.token, "POST", "/v1/seller/orders/"+oid+"/accept", map[string]any{}), http.StatusOK)
}

// Le motif de refus est limité à 200 caractères, comme dans l'app marchand.
func TestSellerRejectReasonIsBounded(t *testing.T) {
	requireApp(t)
	s := newSeller(t, 10)
	b := newBuyer(t, s.lat, s.lng)
	oid := mustStatus(t, order(t, b, s.untrackedID, 1, "pickup"), http.StatusCreated).str("id")
	pay(t, b, oid)

	r := call(t, s.token, "POST", "/v1/seller/orders/"+oid+"/reject", map[string]any{"reason": strings.Repeat("é", 201)})
	if r.code() != "validation_failed" {
		t.Fatalf("motif de 201 caractères : %d %s", r.Status, r.code())
	}
	if st := orderStatus(t, b.token, oid); st != "awaiting_seller" {
		t.Fatalf("motif refusé : la commande ne doit pas changer (%s)", st)
	}
	got := mustStatus(t, call(t, s.token, "POST", "/v1/seller/orders/"+oid+"/reject",
		map[string]any{"reason": strings.Repeat("é", 200)}), http.StatusOK)
	if got.str("status") != "cancelled" {
		t.Fatalf("motif de 200 caractères : %s", got.str("status"))
	}
}

// Le paramètre group renvoie tout un onglet, même une commande en cours ancienne.
func TestOrderListsFilterByTabGroup(t *testing.T) {
	requireApp(t)
	s := newSeller(t, 10)
	b := newBuyer(t, s.lat, s.lng)

	fresh := mustStatus(t, order(t, b, s.untrackedID, 1, "pickup"), http.StatusCreated).str("id")
	pay(t, b, fresh)
	active := mustStatus(t, order(t, b, s.untrackedID, 1, "pickup"), http.StatusCreated).str("id")
	pay(t, b, active)
	mustStatus(t, call(t, s.token, "POST", "/v1/seller/orders/"+active+"/accept", map[string]any{}), http.StatusOK)
	done := mustStatus(t, order(t, b, s.untrackedID, 1, "pickup"), http.StatusCreated).str("id")
	pay(t, b, done)
	mustStatus(t, call(t, s.token, "POST", "/v1/seller/orders/"+done+"/reject", map[string]any{}), http.StatusOK)
	unpaid := mustStatus(t, order(t, b, s.untrackedID, 1, "pickup"), http.StatusCreated).str("id")

	ids := func(token, path string) []string {
		t.Helper()
		var out []string
		for _, it := range mustStatus(t, call(t, token, "GET", path, nil), http.StatusOK).Body["items"].([]any) {
			out = append(out, it.(map[string]any)["id"].(string))
		}
		return out
	}
	expect := func(what string, got []string, want ...string) {
		t.Helper()
		if strings.Join(got, ",") != strings.Join(want, ",") {
			t.Errorf("%s : %v, attendu %v", what, got, want)
		}
	}
	expect("marchand, nouvelles", ids(s.token, "/v1/seller/orders?group=new"), fresh)
	expect("marchand, en cours", ids(s.token, "/v1/seller/orders?group=active"), active)
	expect("marchand, terminées", ids(s.token, "/v1/seller/orders?group=done"), done)
	expect("acheteur, en cours", ids(b.token, "/v1/orders?group=active"), unpaid, active, fresh)
	expect("acheteur, terminées", ids(b.token, "/v1/orders?group=done"), done)
	if r := call(t, s.token, "GET", "/v1/seller/orders?group=archived", nil); r.code() != "validation_failed" {
		t.Fatalf("groupe inconnu : %d %s", r.Status, r.code())
	}
}
