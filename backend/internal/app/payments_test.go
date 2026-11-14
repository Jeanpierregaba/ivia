package app_test

import (
	"net/http"
	"testing"

	"github.com/google/uuid"
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

	floozPhone, tmoneyPhone := uniquePhone(), "+2287"+uniquePhone()[5:]
	p1 := start("flooz", floozPhone).str("id")
	// Sans annulation, une nouvelle demande rend celle en attente, même avec un autre numéro.
	if again := start("tmoney", tmoneyPhone); again.str("id") != p1 || again.str("operator") != "flooz" {
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
	p2 := start("tmoney", tmoneyPhone)
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
	phone := uniquePhone()
	start := func() resp {
		return call(t, b.token, "POST", "/v1/orders/"+oid+"/payments", map[string]string{"operator": "flooz", "phone": phone})
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

// Plusieurs comptes ne peuvent pas viser un même numéro en boucle.
func TestPaymentRequestLimitPerPhone(t *testing.T) {
	requireApp(t)
	s := newSeller(t, 5)
	phone := uniquePhone()
	for i := range 11 {
		b := newBuyer(t, s.lat, s.lng)
		oid := mustStatus(t, order(t, b, s.untrackedID, 1, "pickup"), http.StatusCreated).str("id")
		r := call(t, b.token, "POST", "/v1/orders/"+oid+"/payments", map[string]string{"operator": "flooz", "phone": phone})
		if i < 10 {
			mustStatus(t, r, http.StatusCreated)
			continue
		}
		if mustStatus(t, r, http.StatusTooManyRequests).code() != "rate_limited" {
			t.Fatalf("code %q, attendu rate_limited", r.code())
		}
		// Le compte n'a rien envoyé : il peut payer depuis un autre numéro.
		mustStatus(t, call(t, b.token, "POST", "/v1/orders/"+oid+"/payments", map[string]string{"operator": "flooz", "phone": uniquePhone()}), http.StatusCreated)
	}
}

// Une demande annulée puis validée sur le téléphone, dont le webhook se perd, est rattrapée par
// la revérification (tâche périodique ou admin) : jamais un compte débité sans commande payée.
func TestPaymentRecheckAfterCancel(t *testing.T) {
	requireApp(t)
	s := newSeller(t, 5)
	b := newBuyer(t, s.lat, s.lng)
	reference := func(pid string) string {
		return mustStatus(t, call(t, admin(t), "GET", "/v1/admin/payments/"+pid, nil), http.StatusOK).str("reference")
	}
	// Demande annulée, validée chez le prestataire, webhook perdu.
	cancelledThenPaid := func() (oid, pid string) {
		oid = mustStatus(t, order(t, b, s.untrackedID, 1, "pickup"), http.StatusCreated).str("id")
		pid = mustStatus(t, call(t, b.token, "POST", "/v1/orders/"+oid+"/payments", map[string]string{"operator": "flooz", "phone": uniquePhone()}), http.StatusCreated).str("id")
		mustStatus(t, call(t, b.token, "POST", "/v1/payments/"+pid+"/cancel", nil), http.StatusOK)
		if _, _, err := testApp.FakePayment.Simulate(reference(pid), "succeeded", -1); err != nil {
			t.Fatal(err)
		}
		return oid, pid
	}

	// Tâche périodique.
	oid, pid := cancelledThenPaid()
	exec(t, "UPDATE payments SET created_at = now() - interval '3 minutes' WHERE id = $1", uuid.MustParse(pid))
	if err := testApp.Payments.Recheck(ctx()); err != nil {
		t.Fatal(err)
	}
	eventually(t, "commande payée par revérification", func() bool { return orderStatus(t, b.token, oid) == "awaiting_seller" })

	// Une demande annulée il y a plus d'une heure n'est plus interrogée.
	oid2, pid2 := cancelledThenPaid()
	exec(t, "UPDATE payments SET created_at = now() - interval '2 hours' WHERE id = $1", uuid.MustParse(pid2))
	if err := testApp.Payments.Recheck(ctx()); err != nil {
		t.Fatal(err)
	}
	if orderStatus(t, b.token, oid2) != "pending_payment" {
		t.Fatal("une demande annulée depuis plus d'une heure ne doit plus être revérifiée par la tâche")
	}

	// L'admin, lui, revérifie toute demande non aboutie.
	mustStatus(t, call(t, admin(t), "POST", "/v1/admin/payments/"+pid2+"/verify", map[string]any{}), http.StatusOK)
	eventually(t, "commande payée par l'admin", func() bool { return orderStatus(t, b.token, oid2) == "awaiting_seller" })

	// Une demande expirée côté ivia s'annule sans changement.
	oid3 := mustStatus(t, order(t, b, s.untrackedID, 1, "pickup"), http.StatusCreated).str("id")
	pid3 := mustStatus(t, call(t, b.token, "POST", "/v1/orders/"+oid3+"/payments", map[string]string{"operator": "flooz", "phone": uniquePhone()}), http.StatusCreated).str("id")
	exec(t, "UPDATE payments SET status = 'expired', failure_reason = 'Aucune confirmation du prestataire.' WHERE id = $1", uuid.MustParse(pid3))
	r := mustStatus(t, call(t, b.token, "POST", "/v1/payments/"+pid3+"/cancel", nil), http.StatusOK)
	if r.str("status") != "expired" || r.str("failure_reason") != "Aucune confirmation du prestataire." {
		t.Fatalf("annulation d'une demande expirée : %s", r.Raw)
	}
}

// La limite est comptée sur les demandes enregistrées (durable) : une heure plus tard, les
// anciennes demandes ne comptent plus.
func TestPaymentRequestLimitSlidesWithTime(t *testing.T) {
	requireApp(t)
	s := newSeller(t, 5)
	b := newBuyer(t, s.lat, s.lng)
	oid := mustStatus(t, order(t, b, s.untrackedID, 1, "pickup"), http.StatusCreated).str("id")
	start := func() resp {
		return call(t, b.token, "POST", "/v1/orders/"+oid+"/payments", map[string]string{"operator": "flooz", "phone": uniquePhone()})
	}
	for range 10 {
		id := mustStatus(t, start(), http.StatusCreated).str("id")
		mustStatus(t, call(t, b.token, "POST", "/v1/payments/"+id+"/cancel", nil), http.StatusOK)
	}
	mustStatus(t, start(), http.StatusTooManyRequests)

	exec(t, "UPDATE payments SET created_at = now() - interval '61 minutes' WHERE order_id = $1", oid)
	mustStatus(t, start(), http.StatusCreated)
}
