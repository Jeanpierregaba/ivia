package auth_test

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"

	"ivia/backend/internal/admin"
	"ivia/backend/internal/auth"
	"ivia/backend/internal/geo"
	"ivia/backend/internal/platform/apperr"
	"ivia/backend/internal/platform/testdb"
	"ivia/backend/internal/users"
)

// failingSender simule WhatsApp indisponible (numéro sans WhatsApp, panne de Meta).
type failingSender struct{}

func (failingSender) Send(context.Context, auth.OTPMessage) error { return errors.New("indisponible") }

type adminAlerts struct {
	mu    sync.Mutex
	kinds []string
}

func (a *adminAlerts) NotifyAdmins(_ context.Context, kind, _, _ string, _ map[string]string) error {
	a.mu.Lock()
	defer a.mu.Unlock()
	a.kinds = append(a.kinds, kind)
	return nil
}

func (a *adminAlerts) NotifyUser(context.Context, uuid.UUID, string, string, string, string, map[string]string) error {
	return nil
}

func phoneService(t *testing.T, router auth.ChannelRouter, perHour int) *auth.Service {
	t.Helper()
	db := testdb.Require(t, testDB)
	logger := slog.New(slog.NewTextHandler(io.Discard, nil))
	adm := admin.NewService(db)
	userSvc := users.NewService(db, geo.NewService(db, adm), adm)
	return auth.NewService(db, userSvc, router, logger, auth.Options{
		Secret: []byte("0123456789abcdef0123456789abcdef"), SessionTTL: 24 * time.Hour,
		PhoneChannels: []auth.Channel{auth.ChannelWhatsApp, auth.ChannelSMS}, PhoneCodesPerHour: perHour,
	})
}

func testPhone() string {
	return fmt.Sprintf("+2287%07d", (time.Now().UnixNano()/1000+seq.Add(1))%10_000_000)
}

// WhatsApp en échec : le même code part par SMS, et la réponse indique le canal utilisé.
func TestPhoneCodeFallsBackToSMS(t *testing.T) {
	sms := &auth.LogSender{Logger: slog.New(slog.NewTextHandler(io.Discard, nil))}
	svc := phoneService(t, auth.ChannelRouter{WhatsApp: failingSender{}, SMS: sms}, 100000)
	phone := testPhone()
	out, err := svc.RequestPhoneCode(context.Background(), auth.PhoneCodeInput{Phone: phone, DeviceInfo: auth.DeviceInfo{ID: "appareil-test-1"}}, "1.2.3.4")
	if err != nil {
		t.Fatal(err)
	}
	if out.Channel != auth.ChannelSMS || out.ExpiresInSeconds != 300 {
		t.Fatalf("réponse : %+v", out)
	}
	code, ok := sms.LastCode(phone)
	if !ok {
		t.Fatal("code non envoyé par SMS")
	}
	res, err := svc.VerifyPhone(context.Background(), auth.PhoneVerifyInput{Phone: phone, Code: code, DeviceInfo: auth.DeviceInfo{ID: "appareil-test-1"}}, "test", "1.2.3.4")
	if err != nil || res.Status != "signup_required" {
		t.Fatalf("vérification : %+v %v", res, err)
	}
}

// Aucun canal ne répond : erreur claire, pas de code « envoyé ».
func TestPhoneCodeAllChannelsDown(t *testing.T) {
	svc := phoneService(t, auth.ChannelRouter{WhatsApp: failingSender{}, SMS: failingSender{}}, 100000)
	_, err := svc.RequestPhoneCode(context.Background(), auth.PhoneCodeInput{Phone: testPhone(), DeviceInfo: auth.DeviceInfo{ID: "appareil-test-2"}}, "1.2.3.4")
	if !apperr.IsCode(err, "otp_send_failed") {
		t.Fatalf("erreur : %v", err)
	}
}

// Plafond global atteint : demandes refusées et admins prévenus une seule fois.
func TestPhoneCodeGlobalCap(t *testing.T) {
	logs := &auth.LogSender{Logger: slog.New(slog.NewTextHandler(io.Discard, nil))}
	db := testdb.Require(t, testDB)
	var n int64
	if err := db.Pool.QueryRow(context.Background(), `SELECT count(*) FROM otp_codes WHERE channel = 'phone' AND created_at > now() - interval '1 hour'`).Scan(&n); err != nil {
		t.Fatal(err)
	}
	svc := phoneService(t, auth.ChannelRouter{WhatsApp: logs}, int(n)+1)
	alerts := &adminAlerts{}
	svc.SetNotifier(alerts)
	if _, err := svc.RequestPhoneCode(context.Background(), auth.PhoneCodeInput{Phone: testPhone(), DeviceInfo: auth.DeviceInfo{ID: "appareil-cap-1"}}, "1.2.3.4"); err != nil {
		t.Fatal(err)
	}
	for range 2 {
		_, err := svc.RequestPhoneCode(context.Background(), auth.PhoneCodeInput{Phone: testPhone(), DeviceInfo: auth.DeviceInfo{ID: "appareil-cap-2"}}, "1.2.3.4")
		if !apperr.IsCode(err, "otp_service_busy") {
			t.Fatalf("au-delà du plafond : %v", err)
		}
	}
	if len(alerts.kinds) != 1 || alerts.kinds[0] != "auth_otp_cap" {
		t.Fatalf("alertes : %v", alerts.kinds)
	}
}

// Message WhatsApp : modèle d'authentification, numéro sans « + », jeton en en-tête ; l'erreur
// de Meta ne recopie pas le corps de la réponse (qui peut citer le numéro).
func TestWhatsAppSender(t *testing.T) {
	var got map[string]any
	var auth_ string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		auth_ = r.Header.Get("Authorization")
		if r.URL.Path != "/123456/messages" {
			t.Errorf("chemin : %s", r.URL.Path)
		}
		_ = json.NewDecoder(r.Body).Decode(&got)
		if got["to"] == "22890000001" {
			w.WriteHeader(http.StatusBadRequest)
			_, _ = w.Write([]byte(`{"error":{"code":131026,"type":"OAuthException","message":"+22890000001 n'est pas sur WhatsApp"}}`))
			return
		}
		_, _ = w.Write([]byte(`{"messages":[{"id":"wamid.x"}]}`))
	}))
	defer srv.Close()
	s := &auth.WhatsAppSender{PhoneNumberID: "123456", AccessToken: "jeton-test", Template: "ivia_code", Endpoint: srv.URL}
	if err := s.Send(context.Background(), auth.OTPMessage{Channel: auth.ChannelWhatsApp, Recipient: "+22891234567", Code: "482913", Purpose: auth.PurposePhoneLogin}); err != nil {
		t.Fatal(err)
	}
	tpl := got["template"].(map[string]any)
	if got["to"] != "22891234567" || tpl["name"] != "ivia_code" || auth_ != "Bearer jeton-test" {
		t.Fatalf("requête : %v %s", got, auth_)
	}
	raw, _ := json.Marshal(tpl["components"])
	if string(raw) != `[{"parameters":[{"text":"482913","type":"text"}],"type":"body"},{"index":"0","parameters":[{"text":"482913","type":"text"}],"sub_type":"url","type":"button"}]` {
		t.Fatalf("composants : %s", raw)
	}
	err := s.Send(context.Background(), auth.OTPMessage{Channel: auth.ChannelWhatsApp, Recipient: "+22890000001", Code: "1", Purpose: auth.PurposePhoneLogin})
	if err == nil || !containsAll(err.Error(), "131026") || containsAll(err.Error(), "22890000001") {
		t.Fatalf("erreur : %v", err)
	}
	if err := s.Send(context.Background(), auth.OTPMessage{Channel: auth.ChannelSMS, Recipient: "+22891234567", Code: "1"}); err == nil {
		t.Fatal("canal SMS accepté par l'expéditeur WhatsApp")
	}
}

func containsAll(s string, parts ...string) bool {
	for _, p := range parts {
		if !contains(s, p) {
			return false
		}
	}
	return true
}

func contains(s, sub string) bool {
	for i := 0; i+len(sub) <= len(s); i++ {
		if s[i:i+len(sub)] == sub {
			return true
		}
	}
	return false
}
