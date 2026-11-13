package app_test

import (
	"bufio"
	"context"
	"encoding/json"
	"net/http"
	"strings"
	"testing"
	"time"

	"github.com/coder/websocket"
	"github.com/coder/websocket/wsjson"
)

type liveEvent struct {
	Kind string            `json:"kind"`
	Data map[string]string `json:"data"`
}

// openEvents ouvre le WebSocket des événements d'une app. browser : jeton dans le sous-protocole,
// comme un navigateur.
func openEvents(t *testing.T, token, app string, browser bool) (*websocket.Conn, context.Context) {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	t.Cleanup(cancel)
	opts := &websocket.DialOptions{}
	if browser {
		opts.Subprotocols = []string{"ivia-bearer", token}
	} else {
		opts.HTTPHeader = http.Header{"Authorization": {"Bearer " + token}}
	}
	url := "ws" + strings.TrimPrefix(server.URL, "http") + "/v1/ws/events?app=" + app
	conn, _, err := websocket.Dial(ctx, url, opts)
	if err != nil {
		t.Fatalf("connexion temps réel %s : %v", app, err)
	}
	t.Cleanup(func() { conn.CloseNow() })
	var ready liveEvent
	if err := wsjson.Read(ctx, conn, &ready); err != nil || ready.Kind != "ready" {
		t.Fatalf("premier message %s : %v %v", app, ready, err)
	}
	return conn, ctx
}

// waitEvent attend un événement d'un type donné (les autres sont ignorés).
func waitEvent(t *testing.T, conn *websocket.Conn, ctx context.Context, kind string, match func(liveEvent) bool) liveEvent {
	t.Helper()
	c, cancel := context.WithTimeout(ctx, 15*time.Second)
	defer cancel()
	for {
		var e liveEvent
		if err := wsjson.Read(c, conn, &e); err != nil {
			t.Fatalf("événement %s attendu : %v", kind, err)
		}
		if e.Kind == kind && (match == nil || match(e)) {
			return e
		}
	}
}

// Spec 036 : paiement → marchand prévenu en direct ; boutique prête → livreur prévenu ; chaque
// étape de la course poussée au client, au marchand et au back-office.
func TestRealtimeDeliveryEvents(t *testing.T) {
	requireApp(t)
	s := newSeller(t, 10)
	b := newBuyer(t, s.lat, s.lng)
	d := newDriver(t, s.lat+0.002, s.lng, "motorbike")
	adm := admin(t)

	sellerWS, sctx := openEvents(t, s.token, "seller", true)
	buyerWS, bctx := openEvents(t, b.token, "buyer", false)
	driverWS, dctx := openEvents(t, d, "driver", true)
	if r := call(t, "", "GET", "/v1/ws/events?app=seller", nil); r.Status != http.StatusUnauthorized {
		t.Fatalf("sans jeton : %d", r.Status)
	}

	// Flux SSE du back-office.
	req, _ := http.NewRequest("GET", server.URL+"/v1/admin/stream", nil)
	req.Header.Set("Authorization", "Bearer "+adm)
	sctxAdmin, cancelAdmin := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancelAdmin()
	res, err := http.DefaultClient.Do(req.WithContext(sctxAdmin))
	if err != nil || res.StatusCode != http.StatusOK || !strings.HasPrefix(res.Header.Get("Content-Type"), "text/event-stream") {
		t.Fatalf("flux du back-office : %v %v", err, res)
	}
	defer res.Body.Close()
	adminEvents := make(chan liveEvent, 64)
	go func() {
		sc := bufio.NewScanner(res.Body)
		for sc.Scan() {
			if line, ok := strings.CutPrefix(sc.Text(), "data: "); ok {
				var e liveEvent
				if json.Unmarshal([]byte(line), &e) == nil {
					adminEvents <- e
				}
			}
		}
	}()

	oid := mustStatus(t, order(t, b, s.untrackedID, 1, "delivery"), http.StatusCreated).str("id")
	pay(t, b, oid)
	byOrder := func(e liveEvent) bool { return e.Data["order_id"] == oid }
	waitEvent(t, sellerWS, sctx, "order_new", byOrder)

	for _, step := range []string{"accept", "preparing", "ready"} {
		mustStatus(t, call(t, s.token, "POST", "/v1/seller/orders/"+oid+"/"+step, map[string]any{}), http.StatusOK)
	}
	waitEvent(t, buyerWS, bctx, "order_ready", byOrder)
	offer := waitEvent(t, driverWS, dctx, "delivery_offer", nil)
	_ = offer

	var offerID string
	eventually(t, "proposition au livreur", func() bool {
		r := call(t, d, "GET", "/v1/driver/offers/current", nil)
		if off, ok := r.Body["offer"].(map[string]any); ok {
			offerID, _ = off["id"].(string)
		}
		return offerID != ""
	})
	mid := mustStatus(t, call(t, d, "POST", "/v1/driver/offers/"+offerID+"/accept", map[string]any{}), http.StatusOK).str("id")
	waitEvent(t, sellerWS, sctx, "driver_assigned", byOrder)

	// « Démarrer ma course » : étape poussée au client et au marchand ; deuxième appel sans effet.
	m := mustStatus(t, call(t, d, "POST", "/v1/driver/missions/"+mid+"/start", map[string]any{}), http.StatusOK)
	if m.Body["started_at"] == nil {
		t.Fatalf("course démarrée : %s", m.Raw)
	}
	mustStatus(t, call(t, d, "POST", "/v1/driver/missions/"+mid+"/start", map[string]any{}), http.StatusOK)
	step := func(want string) func(liveEvent) bool {
		return func(e liveEvent) bool { return e.Data["order_id"] == oid && e.Data["step"] == want }
	}
	waitEvent(t, buyerWS, bctx, "delivery_step", step("heading_to_shop"))
	waitEvent(t, sellerWS, sctx, "delivery_step", step("heading_to_shop"))
	info := mustStatus(t, call(t, b.token, "GET", "/v1/orders/"+oid+"/delivery", nil), http.StatusOK)
	if dl, _ := info.Body["delivery"].(map[string]any); dl == nil || dl["step"] != "heading_to_shop" {
		t.Fatalf("étape vue par le client : %s", info.Raw)
	}

	mustStatus(t, call(t, d, "POST", "/v1/driver/missions/"+mid+"/arrived-at-shop", map[string]any{}), http.StatusOK)
	waitEvent(t, buyerWS, bctx, "delivery_step", step("at_shop"))
	mustStatus(t, call(t, d, "POST", "/v1/driver/missions/"+mid+"/picked-up", map[string]any{}), http.StatusOK)
	waitEvent(t, sellerWS, sctx, "order_picked_up", byOrder)
	waitEvent(t, buyerWS, bctx, "delivery_step", step("heading_to_customer"))
	if r := call(t, d, "POST", "/v1/driver/missions/"+mid+"/start", map[string]any{}); r.code() != "invalid_mission_step" {
		t.Fatalf("démarrer après le retrait : %s", r.Raw)
	}

	// Le back-office a vu passer les statuts et les étapes.
	deadline := time.After(15 * time.Second)
	seen := map[string]bool{}
	for !(seen["order_status"] && seen["delivery_step"]) {
		select {
		case e := <-adminEvents:
			if e.Data["order_id"] == oid {
				seen[e.Kind] = true
			}
		case <-deadline:
			t.Fatalf("événements du back-office : %v", seen)
		}
	}
}
