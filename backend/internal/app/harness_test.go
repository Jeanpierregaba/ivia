package app_test

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"os"
	"sync/atomic"
	"testing"
	"time"

	"ivia/backend/internal/app"
	"ivia/backend/internal/platform/config"
	"ivia/backend/internal/platform/database"
	"ivia/backend/internal/platform/testdb"
)

var (
	testDB  *database.DB
	testApp *app.App
	server  *httptest.Server
	seq     atomic.Int64
)

// TestMain assemble l'application complète (tâches de fond comprises) sur une base dédiée.
func TestMain(m *testing.M) {
	os.Exit(testdb.Main(m, &testDB, func() (func(), error) {
		cfg, err := config.Load(func(k string) string {
			return map[string]string{
				"APP_ENV":           "test",
				"DATABASE_URL":      "unused",
				"LOCAL_STORAGE_DIR": os.TempDir() + "/ivia-test-uploads",
			}[k]
		})
		if err != nil {
			return nil, err
		}
		logger := slog.New(slog.NewTextHandler(io.Discard, nil))
		a, err := app.New(cfg, logger, testDB.Pool, app.Options{PollInterval: 50 * time.Millisecond})
		if err != nil {
			return nil, err
		}
		if err := a.Start(context.Background()); err != nil {
			return nil, err
		}
		testApp = a
		server = httptest.NewServer(a.Handler)
		return func() {
			server.Close()
			ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
			defer cancel()
			_ = a.Stop(ctx)
		}, nil
	}))
}

func requireApp(t *testing.T) *app.App {
	t.Helper()
	testdb.Require(t, testDB)
	return testApp
}

// --- Client HTTP ------------------------------------------------------------------------------

type resp struct {
	Status int
	Body   map[string]any
	Raw    []byte
}

func (r resp) code() string {
	e, _ := r.Body["error"].(map[string]any)
	c, _ := e["code"].(string)
	return c
}

func (r resp) str(key string) string { v, _ := r.Body[key].(string); return v }

func call(t *testing.T, token, method, path string, body any) resp {
	t.Helper()
	var rd io.Reader
	if body != nil {
		b, _ := json.Marshal(body)
		rd = bytes.NewReader(b)
	}
	req, _ := http.NewRequest(method, server.URL+path, rd)
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("%s %s : %v", method, path, err)
	}
	defer res.Body.Close()
	raw, _ := io.ReadAll(res.Body)
	out := resp{Status: res.StatusCode, Raw: raw}
	_ = json.Unmarshal(raw, &out.Body)
	return out
}

func mustStatus(t *testing.T, r resp, status int) resp {
	t.Helper()
	if r.Status != status {
		t.Fatalf("statut %d, attendu %d : %s", r.Status, status, r.Raw)
	}
	return r
}

// eventually attend qu'une condition devienne vraie (tâches de fond).
func eventually(t *testing.T, what string, cond func() bool) {
	t.Helper()
	deadline := time.Now().Add(10 * time.Second)
	for time.Now().Before(deadline) {
		if cond() {
			return
		}
		time.Sleep(50 * time.Millisecond)
	}
	t.Fatalf("délai dépassé : %s", what)
}

// --- Acteurs ----------------------------------------------------------------------------------

func uniqueEmail(prefix string) string {
	return fmt.Sprintf("%s-%d-%d@example.tg", prefix, time.Now().UnixNano(), seq.Add(1))
}

func uniquePhone() string { return fmt.Sprintf("+2289%07d", seq.Add(1)%10_000_000) }

// login connecte un utilisateur par code (lu dans l'implémentation factice de l'envoi).
func login(t *testing.T, email string) string {
	t.Helper()
	mustStatus(t, call(t, "", "POST", "/v1/auth/otp", map[string]string{"recipient": email}), http.StatusAccepted)
	code, ok := testApp.DevOTP.LastCode(email)
	if !ok {
		t.Fatal("code non envoyé")
	}
	r := mustStatus(t, call(t, "", "POST", "/v1/auth/verify", map[string]string{"recipient": email, "code": code}), http.StatusOK)
	return r.str("token")
}

func completeProfile(t *testing.T, token, first string) {
	t.Helper()
	mustStatus(t, call(t, token, "PATCH", "/v1/me", map[string]any{
		"first_name": first, "phone": uniquePhone(), "accept_privacy_policy": true,
	}), http.StatusOK)
}

var adminToken string

func admin(t *testing.T) string {
	t.Helper()
	if adminToken == "" {
		email := uniqueEmail("admin")
		if _, err := testApp.GrantAdmin(context.Background(), email); err != nil {
			t.Fatal(err)
		}
		adminToken = login(t, email)
	}
	return adminToken
}

// zone retourne un point isolé pour un test : les zones sont espacées de plus de 30 km, au-delà
// du rayon de recherche des livreurs, pour que les tests ne se gênent pas.
func zone() (float64, float64) {
	n := seq.Add(1)
	return 5.0 + float64(n%40)*0.4, 0.5 + float64(n/40%10)*0.4
}

type sellerFixture struct {
	token, shopID string
	lat, lng      float64
	trackedID     string // produit à stock suivi (quantité donnée)
	untrackedID   string
	largeID       string // grand colis
}

var categoryID string

func category(t *testing.T) string {
	t.Helper()
	if categoryID == "" {
		r := mustStatus(t, call(t, admin(t), "POST", "/v1/admin/categories", map[string]any{"name": fmt.Sprintf("Catégorie %d", seq.Add(1))}), http.StatusCreated)
		categoryID = r.str("id")
	}
	return categoryID
}

func newSeller(t *testing.T, stock int) sellerFixture {
	t.Helper()
	tok := login(t, uniqueEmail("seller"))
	completeProfile(t, tok, "Afi")
	lat, lng := zone()
	shop := mustStatus(t, call(t, tok, "POST", "/v1/shops", map[string]any{
		"name": "Boutique test", "phone": uniquePhone(), "address_text": "Rue du test",
		"location": map[string]float64{"lat": lat, "lng": lng},
	}), http.StatusCreated)
	shopID := shop.str("id")
	mustStatus(t, call(t, admin(t), "POST", "/v1/admin/shops/"+shopID+"/approve", map[string]any{}), http.StatusOK)
	// Même jeton : le rôle seller, obtenu à la création de la boutique, est relu à chaque requête.
	f := sellerFixture{token: tok, shopID: shopID, lat: lat, lng: lng}
	mk := func(name, size, mode string, qty *int) string {
		body := map[string]any{"category_id": category(t), "name": name, "price_xof": 5000, "parcel_size": size, "stock_mode": mode}
		if qty != nil {
			body["stock_quantity"] = *qty
		}
		return mustStatus(t, call(t, f.token, "POST", "/v1/seller/shops/"+shopID+"/products", body), http.StatusCreated).str("id")
	}
	f.trackedID = mk("Produit suivi", "small", "tracked", &stock)
	f.untrackedID = mk("Produit libre", "medium", "untracked", nil)
	f.largeID = mk("Gros produit", "large", "untracked", nil)
	return f
}

type buyerFixture struct {
	token, addressID string
}

func newBuyer(t *testing.T, lat, lng float64) buyerFixture {
	t.Helper()
	tok := login(t, uniqueEmail("buyer"))
	completeProfile(t, tok, "Kossi")
	addr := mustStatus(t, call(t, tok, "POST", "/v1/me/addresses", map[string]any{
		"label": "Maison", "address_text": "Près du marché",
		"location": map[string]float64{"lat": lat + 0.01, "lng": lng + 0.01},
	}), http.StatusCreated)
	return buyerFixture{token: tok, addressID: addr.str("id")}
}

func newDriver(t *testing.T, lat, lng float64, vehicle string) string {
	t.Helper()
	tok := login(t, uniqueEmail("driver"))
	completeProfile(t, tok, "Yao")
	mustStatus(t, call(t, tok, "PUT", "/v1/driver/application", map[string]string{"vehicle_type": vehicle, "vehicle_plate": "TG-0001"}), http.StatusOK)
	me := mustStatus(t, call(t, tok, "GET", "/v1/me", nil), http.StatusOK)
	mustStatus(t, call(t, admin(t), "POST", "/v1/admin/drivers/"+me.str("id")+"/approve", map[string]any{}), http.StatusOK)
	mustStatus(t, call(t, tok, "PUT", "/v1/driver/availability", map[string]bool{"online": true}), http.StatusOK)
	mustStatus(t, call(t, tok, "POST", "/v1/driver/location", map[string]float64{"lat": lat, "lng": lng}), http.StatusNoContent)
	return tok
}

// order met un produit au panier et crée la commande.
func order(t *testing.T, b buyerFixture, productID string, qty int, fulfillment string) resp {
	t.Helper()
	mustStatus(t, call(t, b.token, "PUT", "/v1/cart/items", map[string]any{"product_id": productID, "quantity": qty, "replace_cart": true}), http.StatusOK)
	body := map[string]any{"fulfillment": fulfillment}
	if fulfillment == "delivery" {
		body["address_id"] = b.addressID
	}
	return call(t, b.token, "POST", "/v1/orders", body)
}

func orderStatus(t *testing.T, token, orderID string) string {
	t.Helper()
	return mustStatus(t, call(t, token, "GET", "/v1/orders/"+orderID, nil), http.StatusOK).str("status")
}

// pay lance le paiement et le fait aboutir par un webhook signé du faux prestataire.
func pay(t *testing.T, b buyerFixture, orderID string) string {
	t.Helper()
	return payFrom(t, b, orderID, "90123456")
}

// payFrom paie depuis un numéro donné (un numéro finissant par 0000 fait échouer les remboursements).
func payFrom(t *testing.T, b buyerFixture, orderID, phone string) string {
	t.Helper()
	p := mustStatus(t, call(t, b.token, "POST", "/v1/orders/"+orderID+"/payments", map[string]string{"operator": "flooz", "phone": phone}), http.StatusCreated)
	mustStatus(t, call(t, b.token, "POST", "/v1/dev/payments/"+p.str("id")+"/simulate", map[string]string{"outcome": "succeeded"}), http.StatusOK)
	eventually(t, "commande payée", func() bool { return orderStatus(t, b.token, orderID) == "awaiting_seller" })
	return p.str("id")
}
