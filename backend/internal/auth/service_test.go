package auth_test

import (
	"context"
	"fmt"
	"io"
	"log/slog"
	"os"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"ivia/backend/internal/admin"
	"ivia/backend/internal/auth"
	"ivia/backend/internal/geo"
	"ivia/backend/internal/platform/apperr"
	"ivia/backend/internal/platform/database"
	"ivia/backend/internal/platform/identity"
	"ivia/backend/internal/platform/testdb"
	"ivia/backend/internal/users"
)

var testDB *database.DB

func TestMain(m *testing.M) { os.Exit(testdb.Main(m, &testDB)) }

var seq atomic.Int64

func uniqueEmail() string {
	return fmt.Sprintf("u%d-%d@example.tg", time.Now().UnixNano(), seq.Add(1))
}

func newService(t *testing.T) (*auth.Service, *auth.LogSender, *users.Service) {
	t.Helper()
	db := testdb.Require(t, testDB)
	logger := slog.New(slog.NewTextHandler(io.Discard, nil))
	adm := admin.NewService(db)
	userSvc := users.NewService(db, geo.NewService(db, adm), adm)
	sender := &auth.LogSender{Logger: logger}
	svc := auth.NewService(db, userSvc, sender, logger, auth.Options{
		Secret: []byte("0123456789abcdef0123456789abcdef"), SessionTTL: 24 * time.Hour,
	})
	return svc, sender, userSvc
}

func requestCode(t *testing.T, svc *auth.Service, sender *auth.LogSender, email string) string {
	t.Helper()
	if _, err := svc.RequestOTP(context.Background(), auth.ChannelEmail, email, "1.2.3.4"); err != nil {
		t.Fatalf("RequestOTP : %v", err)
	}
	code, ok := sender.LastCode(strings.TrimSpace(email))
	if !ok || len(code) != 6 {
		t.Fatalf("code non envoyé : %q", code)
	}
	return code
}

func wrongCode(code string) string {
	if code == "000000" {
		return "111111"
	}
	return "000000"
}

func assertCode(t *testing.T, err error, code string) {
	t.Helper()
	if !apperr.IsCode(err, code) {
		t.Fatalf("erreur %v, attendu le code %q", err, code)
	}
}

func TestNewUserSignsInAndGetsBuyerRole(t *testing.T) {
	svc, sender, _ := newService(t)
	ctx := context.Background()
	email := uniqueEmail()

	code := requestCode(t, svc, sender, "  "+email+"  ")
	sess, err := svc.Verify(ctx, auth.ChannelEmail, email, code, "test", "1.2.3.4")
	if err != nil {
		t.Fatalf("Verify : %v", err)
	}
	if !sess.IsNewUser || sess.Token == "" || *sess.User.Email != email {
		t.Fatalf("session inattendue : %+v", sess)
	}
	if len(sess.User.Roles) != 1 || sess.User.Roles[0] != identity.RoleBuyer {
		t.Fatalf("rôles : %v, attendu [buyer]", sess.User.Roles)
	}

	p, err := svc.Authenticate(ctx, sess.Token)
	if err != nil || p.UserID != sess.User.ID {
		t.Fatalf("Authenticate : %+v %v", p, err)
	}

	// Seconde connexion : même compte, pas de nouveau compte.
	time.Sleep(10 * time.Millisecond)
	_, _ = testDB.Pool.Exec(ctx, "UPDATE otp_codes SET created_at = created_at - interval '2 minutes' WHERE recipient = $1", email)
	code = requestCode(t, svc, sender, email)
	sess2, err := svc.Verify(ctx, auth.ChannelEmail, email, code, "test", "1.2.3.4")
	if err != nil || sess2.IsNewUser || sess2.User.ID != sess.User.ID {
		t.Fatalf("seconde connexion : %+v %v", sess2, err)
	}
}

func TestCodeIsSingleUse(t *testing.T) {
	svc, sender, _ := newService(t)
	ctx := context.Background()
	email := uniqueEmail()
	code := requestCode(t, svc, sender, email)

	if _, err := svc.Verify(ctx, auth.ChannelEmail, email, code, "", "1.2.3.4"); err != nil {
		t.Fatal(err)
	}
	_, err := svc.Verify(ctx, auth.ChannelEmail, email, code, "", "1.2.3.4")
	assertCode(t, err, "otp_invalid")
}

func TestConcurrentVerifyOnlyOneSucceeds(t *testing.T) {
	svc, sender, _ := newService(t)
	email := uniqueEmail()
	code := requestCode(t, svc, sender, email)

	var ok atomic.Int32
	var wg sync.WaitGroup
	for range 5 {
		wg.Go(func() {
			if _, err := svc.Verify(context.Background(), auth.ChannelEmail, email, code, "", "1.2.3.4"); err == nil {
				ok.Add(1)
			}
		})
	}
	wg.Wait()
	if ok.Load() != 1 {
		t.Fatalf("%d connexions réussies avec le même code, attendu 1", ok.Load())
	}
}

func TestCodeExpires(t *testing.T) {
	svc, sender, _ := newService(t)
	ctx := context.Background()
	email := uniqueEmail()
	code := requestCode(t, svc, sender, email)

	if _, err := testDB.Pool.Exec(ctx, "UPDATE otp_codes SET expires_at = now() - interval '1 second' WHERE recipient = $1", email); err != nil {
		t.Fatal(err)
	}
	_, err := svc.Verify(ctx, auth.ChannelEmail, email, code, "", "1.2.3.4")
	assertCode(t, err, "otp_expired")
}

func TestFiveAttemptsThenLocked(t *testing.T) {
	svc, sender, _ := newService(t)
	ctx := context.Background()
	email := uniqueEmail()
	code := requestCode(t, svc, sender, email)

	for i := 1; i <= auth.OTPMaxAttempts; i++ {
		_, err := svc.Verify(ctx, auth.ChannelEmail, email, wrongCode(code), "", "1.2.3.4")
		if i < auth.OTPMaxAttempts {
			assertCode(t, err, "otp_invalid")
		} else {
			assertCode(t, err, "otp_too_many_attempts")
		}
	}
	// Même le bon code est refusé après 5 essais.
	_, err := svc.Verify(ctx, auth.ChannelEmail, email, code, "", "1.2.3.4")
	assertCode(t, err, "otp_too_many_attempts")
}

func TestRateLimitPerRecipient(t *testing.T) {
	svc, sender, _ := newService(t)
	ctx := context.Background()
	email := uniqueEmail()
	requestCode(t, svc, sender, email)

	_, err := svc.RequestOTP(ctx, auth.ChannelEmail, email, "1.2.3.4")
	assertCode(t, err, "otp_rate_limited")

	// 10 codes sur 24 h : le 11e est refusé.
	if _, err := testDB.Pool.Exec(ctx, `
		INSERT INTO otp_codes (channel, recipient, code_hash, expires_at, consumed_at, created_at)
		SELECT 'email', $1, '\x00', now(), now(), now() - interval '2 hours'
		FROM generate_series(1, 9)`, email); err != nil {
		t.Fatal(err)
	}
	if _, err := testDB.Pool.Exec(ctx, "UPDATE otp_codes SET created_at = now() - interval '5 minutes' WHERE recipient = $1 AND created_at > now() - interval '1 minute'", email); err != nil {
		t.Fatal(err)
	}
	_, err = svc.RequestOTP(ctx, auth.ChannelEmail, email, "1.2.3.4")
	assertCode(t, err, "otp_daily_limit")
}

func TestNewCodeInvalidatesPrevious(t *testing.T) {
	svc, sender, _ := newService(t)
	ctx := context.Background()
	email := uniqueEmail()
	first := requestCode(t, svc, sender, email)
	_, _ = testDB.Pool.Exec(ctx, "UPDATE otp_codes SET created_at = created_at - interval '2 minutes' WHERE recipient = $1", email)
	second := requestCode(t, svc, sender, email)
	if first == second {
		t.Skip("codes identiques par hasard (1 chance sur un million)")
	}
	_, err := svc.Verify(ctx, auth.ChannelEmail, email, first, "", "1.2.3.4")
	assertCode(t, err, "otp_invalid")
	if _, err := svc.Verify(ctx, auth.ChannelEmail, email, second, "", "1.2.3.4"); err != nil {
		t.Fatalf("le nouveau code doit fonctionner : %v", err)
	}
}

func TestInvalidInputs(t *testing.T) {
	svc, _, _ := newService(t)
	ctx := context.Background()
	_, err := svc.RequestOTP(ctx, auth.ChannelEmail, "pas-un-email", "1.2.3.4")
	assertCode(t, err, "validation_failed")
	_, err = svc.RequestOTP(ctx, auth.ChannelWhatsApp, "+22890123456", "1.2.3.4")
	assertCode(t, err, "otp_channel_unavailable")
	// Un destinataire sans code reçoit la même erreur qu'un mauvais code (pas d'énumération).
	_, err = svc.Verify(ctx, auth.ChannelEmail, uniqueEmail(), "123456", "", "1.2.3.4")
	assertCode(t, err, "otp_invalid")
}

func TestLogoutAndAccountDeletionRevokeSessions(t *testing.T) {
	svc, sender, userSvc := newService(t)
	ctx := context.Background()
	email := uniqueEmail()
	sess, err := svc.Verify(ctx, auth.ChannelEmail, email, requestCode(t, svc, sender, email), "", "1.2.3.4")
	if err != nil {
		t.Fatal(err)
	}
	p, err := svc.Authenticate(ctx, sess.Token)
	if err != nil {
		t.Fatal(err)
	}
	if err := svc.Logout(ctx, p.SessionID); err != nil {
		t.Fatal(err)
	}
	_, err = svc.Authenticate(ctx, sess.Token)
	assertCode(t, err, "invalid_session")

	// Suppression du compte : toutes les sessions tombent.
	_, _ = testDB.Pool.Exec(ctx, "UPDATE otp_codes SET created_at = created_at - interval '2 minutes' WHERE recipient = $1", email)
	sess, err = svc.Verify(ctx, auth.ChannelEmail, email, requestCode(t, svc, sender, email), "", "1.2.3.4")
	if err != nil {
		t.Fatal(err)
	}
	userSvc.AddDeletionHook(svc)
	if err := userSvc.DeleteAccount(ctx, sess.User.ID); err != nil {
		t.Fatal(err)
	}
	_, err = svc.Authenticate(ctx, sess.Token)
	assertCode(t, err, "invalid_session")
}

func TestAuthenticateRejectsGarbage(t *testing.T) {
	svc, _, _ := newService(t)
	for _, tok := range []string{"", "court", "x" + string(make([]byte, 100))} {
		_, err := svc.Authenticate(context.Background(), tok)
		assertCode(t, err, "invalid_session")
	}
}
