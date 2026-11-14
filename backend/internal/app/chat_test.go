package app_test

import (
	"net/http"
	"testing"
)

// Spec 037 : messagerie de la course, client ↔ livreur et livreur ↔ boutique.
func TestChatDuringDelivery(t *testing.T) {
	requireApp(t)
	s := newSeller(t, 10)
	b := newBuyer(t, s.lat, s.lng)
	d := newDriver(t, s.lat+0.002, s.lng, "motorbike")
	other := newBuyer(t, s.lat, s.lng)

	oid := mustStatus(t, order(t, b, s.untrackedID, 1, "delivery"), http.StatusCreated).str("id")
	pay(t, b, oid)
	// Pas encore de livreur : discussion fermée.
	if r := call(t, b.token, "GET", "/v1/orders/"+oid+"/chat", nil); r.code() != "chat_unavailable" {
		t.Fatalf("avant le livreur : %d %s", r.Status, r.Raw)
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
	mid := mustStatus(t, call(t, d, "POST", "/v1/driver/offers/"+offerID+"/accept", map[string]any{}), http.StatusOK).str("id")

	driverWS, dctx := openEvents(t, d, "driver", true)
	buyerWS, bctx := openEvents(t, b.token, "buyer", false)

	// Client → livreur : reçu en direct, puis lu par le livreur.
	m := mustStatus(t, call(t, b.token, "POST", "/v1/orders/"+oid+"/chat", map[string]any{"body": "  Bonjour, je suis au portail bleu  "}), http.StatusCreated)
	if m.str("body") != "Bonjour, je suis au portail bleu" || m.Body["mine"] != true {
		t.Fatalf("message : %s", m.Raw)
	}
	waitEvent(t, driverWS, dctx, "chat_message", func(e liveEvent) bool {
		return e.Data["order_id"] == oid && e.Data["thread"] == "buyer_driver"
	})
	th := mustStatus(t, call(t, d, "GET", "/v1/driver/orders/"+oid+"/chat/client", nil), http.StatusOK)
	msgs := list(th.Body["messages"])
	if len(msgs) != 1 || msgs[0]["mine"] != false || th.Body["can_send"] != true || th.str("other_role") != "buyer" {
		t.Fatalf("fil du livreur : %s", th.Raw)
	}
	waitEvent(t, buyerWS, bctx, "chat_read", nil)
	mustStatus(t, call(t, d, "POST", "/v1/driver/orders/"+oid+"/chat/client", map[string]any{"body": "J'arrive dans 5 minutes"}), http.StatusCreated)
	waitEvent(t, buyerWS, bctx, "chat_message", nil)
	if th := mustStatus(t, call(t, b.token, "GET", "/v1/orders/"+oid+"/chat", nil), http.StatusOK); len(list(th.Body["messages"])) != 2 || th.Body["other_read_at"] == nil {
		t.Fatalf("fil du client : %s", th.Raw)
	}

	// Livreur ↔ boutique : fil séparé, invisible du client.
	mustStatus(t, call(t, d, "POST", "/v1/driver/orders/"+oid+"/chat/shop", map[string]any{"body": "Je suis devant la boutique"}), http.StatusCreated)
	if th := mustStatus(t, call(t, s.token, "GET", "/v1/seller/orders/"+oid+"/chat", nil), http.StatusOK); len(list(th.Body["messages"])) != 1 {
		t.Fatalf("fil de la boutique : %s", th.Raw)
	}
	if th := mustStatus(t, call(t, b.token, "GET", "/v1/orders/"+oid+"/chat", nil), http.StatusOK); len(list(th.Body["messages"])) != 2 {
		t.Fatalf("le client ne voit pas le fil de la boutique : %s", th.Raw)
	}

	// Accès : un autre client, message vide.
	if r := call(t, other.token, "GET", "/v1/orders/"+oid+"/chat", nil); r.Status != http.StatusNotFound {
		t.Fatalf("autre client : %d", r.Status)
	}
	if r := call(t, b.token, "POST", "/v1/orders/"+oid+"/chat", map[string]any{"body": "   "}); r.Status != http.StatusBadRequest {
		t.Fatalf("message vide : %d", r.Status)
	}

	// Course terminée : lecture seule.
	for _, step := range []string{"arrived-at-shop", "picked-up", "arrived-at-customer"} {
		mustStatus(t, call(t, d, "POST", "/v1/driver/missions/"+mid+"/"+step, map[string]any{}), http.StatusOK)
	}
	code := mustStatus(t, call(t, b.token, "GET", "/v1/orders/"+oid, nil), http.StatusOK).str("handover_code")
	mustStatus(t, call(t, d, "POST", "/v1/driver/missions/"+mid+"/deliver", map[string]string{"code": code}), http.StatusOK)
	if th := mustStatus(t, call(t, b.token, "GET", "/v1/orders/"+oid+"/chat", nil), http.StatusOK); th.Body["can_send"] != false {
		t.Fatalf("après la livraison : %s", th.Raw)
	}
	if r := call(t, b.token, "POST", "/v1/orders/"+oid+"/chat", map[string]any{"body": "Merci"}); r.code() != "chat_closed" {
		t.Fatalf("envoi après la livraison : %s", r.Raw)
	}
}
