package app_test

import (
	"net/http"
	"testing"
)

// L'acheteur abandonne une demande de paiement en attente pour en lancer une autre (010).
func TestPaymentCancel(t *testing.T) {
	requireApp(t)
	s := newSeller(t, 5)
	b, other := newBuyer(t, s.lat, s.lng), newBuyer(t, s.lat, s.lng)
	oid := mustStatus(t, order(t, b, s.untrackedID, 1, "pickup"), http.StatusCreated).str("id")
	start := func(operator, phone string) resp {
		return mustStatus(t, call(t, b.token, "POST", "/v1/orders/"+oid+"/payments", map[string]string{"operator": operator, "phone": phone}), http.StatusCreated)
	}

	p1 := start("flooz", "90123456").str("id")
	// Sans annulation, une nouvelle demande rend celle en attente, même avec un autre numéro.
	if again := start("tmoney", "70123456"); again.str("id") != p1 || again.str("operator") != "flooz" {
		t.Fatalf("la demande en attente doit être rendue telle quelle : %s", again.Raw)
	}

	// Demande d'un autre acheteur : 404, rien ne change.
	r := mustStatus(t, call(t, other.token, "POST", "/v1/payments/"+p1+"/cancel", nil), http.StatusNotFound)
	if r.code() != "payment_not_found" {
		t.Fatalf("code %q, attendu payment_not_found", r.code())
	}
	mustStatus(t, call(t, b.token, "POST", "/v1/payments/not-a-uuid/cancel", nil), http.StatusNotFound)

	// Annulation : échec avec sa raison ; une seconde annulation rend le même état.
	for range 2 {
		r = mustStatus(t, call(t, b.token, "POST", "/v1/payments/"+p1+"/cancel", nil), http.StatusOK)
		if r.str("status") != "failed" || r.str("failure_reason") != "Annulé par l'acheteur." || r.str("id") != p1 {
			t.Fatalf("annulation : %s", r.Raw)
		}
	}
	if orderStatus(t, b.token, oid) != "pending_payment" {
		t.Fatal("annuler la demande ne doit pas toucher à la commande")
	}

	// Une nouvelle demande est possible, avec un autre opérateur et un autre numéro.
	p2 := start("tmoney", "70123456")
	if p2.str("id") == p1 || p2.str("operator") != "tmoney" || p2.str("status") != "pending" {
		t.Fatalf("nouvelle demande attendue : %s", p2.Raw)
	}

	// La demande annulée est validée malgré tout sur le téléphone : le webhook fait foi.
	mustStatus(t, call(t, b.token, "POST", "/v1/dev/payments/"+p1+"/simulate", map[string]string{"outcome": "succeeded"}), http.StatusOK)
	eventually(t, "commande payée par la demande annulée", func() bool { return orderStatus(t, b.token, oid) == "awaiting_seller" })
	if st := mustStatus(t, call(t, b.token, "GET", "/v1/payments/"+p1, nil), http.StatusOK).str("status"); st != "succeeded" {
		t.Fatalf("paiement validé après annulation : statut %q, attendu succeeded", st)
	}

	// Un paiement réussi ne s'annule pas.
	r = mustStatus(t, call(t, b.token, "POST", "/v1/payments/"+p1+"/cancel", nil), http.StatusConflict)
	if r.code() != "payment_not_cancellable" {
		t.Fatalf("code %q, attendu payment_not_cancellable", r.code())
	}
	// L'autre demande, restée en attente, s'annule toujours.
	mustStatus(t, call(t, b.token, "POST", "/v1/payments/"+p2.str("id")+"/cancel", nil), http.StatusOK)
}

// Les demandes de paiement d'un acheteur sont limitées : pas d'envoi en boucle vers un numéro.
func TestPaymentRequestLimit(t *testing.T) {
	requireApp(t)
	s := newSeller(t, 5)
	b := newBuyer(t, s.lat, s.lng)
	oid := mustStatus(t, order(t, b, s.untrackedID, 1, "pickup"), http.StatusCreated).str("id")
	start := func() resp {
		return call(t, b.token, "POST", "/v1/orders/"+oid+"/payments", map[string]string{"operator": "flooz", "phone": "90123456"})
	}

	for range 10 {
		id := mustStatus(t, start(), http.StatusCreated).str("id")
		// Rendre la demande en attente ne compte pas comme une nouvelle demande.
		mustStatus(t, start(), http.StatusCreated)
		mustStatus(t, call(t, b.token, "POST", "/v1/payments/"+id+"/cancel", nil), http.StatusOK)
	}
	r := mustStatus(t, start(), http.StatusTooManyRequests)
	if r.code() != "rate_limited" {
		t.Fatalf("code %q, attendu rate_limited", r.code())
	}
}
