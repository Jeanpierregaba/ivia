package config

import (
	"bytes"
	"fmt"
	"log/slog"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
)

// Secrets de test générés pour l'occasion : longs, variés, sans motif d'exemple.
const (
	strongAuth    = "q7Rm2Kx9Lp4Vw8Zt1Nc6Bh3Jf5Yd0Gs-Ue_Ai"
	strongWebhook = "W3n8Qz1Lr6Tx9Vk2Mp5Hb7Jc4Fd0Gs-Ya_Ue"
	strongDBURL   = "postgres://ivia:Vq8Lm2Rx7Kp4Zt9Nw1Bc6Hj3@postgres:5432/ivia?sslmode=disable"
)

func writeSecret(t *testing.T, value string, mode os.FileMode) string {
	t.Helper()
	p := filepath.Join(t.TempDir(), "secret")
	if err := os.WriteFile(p, []byte(value+"\n"), mode); err != nil {
		t.Fatal(err)
	}
	if err := os.Chmod(p, mode); err != nil {
		t.Fatal(err)
	}
	return p
}

func TestSecretsAreReadFromFiles(t *testing.T) {
	c, err := Load(env(map[string]string{
		"APP_ENV":            EnvLocal,
		"DATABASE_URL_FILE":  writeSecret(t, strongDBURL, 0o600),
		"AUTH_SECRET_FILE":   writeSecret(t, strongAuth, 0o400),
		"BREVO_API_KEY_FILE": writeSecret(t, "xkeysib-test", 0o600),
	}))
	if err != nil {
		t.Fatal(err)
	}
	if c.DatabaseURL != strongDBURL || string(c.AuthSecret) != strongAuth || c.BrevoAPIKey != "xkeysib-test" {
		t.Fatal("les secrets lus dans les fichiers (espaces et fin de ligne retirés) ne correspondent pas")
	}
}

func TestSecretFileRules(t *testing.T) {
	base := map[string]string{"APP_ENV": EnvLocal}
	cases := map[string]struct {
		vars map[string]string
		want string
	}{
		"variable et fichier à la fois": {map[string]string{"DATABASE_URL": "postgres://x", "DATABASE_URL_FILE": writeSecret(t, "postgres://y", 0o600)}, "toutes les deux"},
		"fichier absent":                {map[string]string{"DATABASE_URL_FILE": filepath.Join(t.TempDir(), "absent")}, "absent"},
		"fichier vide = non configuré":  {map[string]string{"DATABASE_URL_FILE": writeSecret(t, "  ", 0o600)}, "DATABASE_URL non définie"},
		"dossier au lieu d'un fichier":  {map[string]string{"DATABASE_URL_FILE": t.TempDir()}, "n'est pas un fichier"},
	}
	for name, tc := range cases {
		vars := map[string]string{}
		for k, v := range base {
			vars[k] = v
		}
		for k, v := range tc.vars {
			vars[k] = v
		}
		_, err := Load(env(vars))
		if err == nil || !strings.Contains(err.Error(), tc.want) {
			t.Errorf("%s : erreur attendue « %s », obtenu %v", name, tc.want, err)
		}
		if tc.want != "DATABASE_URL non définie" && err != nil && strings.Contains(err.Error(), "DATABASE_URL non définie") {
			t.Errorf("%s : erreur signalée deux fois : %v", name, err)
		}
	}
}

func TestProductionRefusesOpenSecretFiles(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("droits Unix non applicables sous Windows (la production tourne sous Linux)")
	}
	_, err := Load(env(map[string]string{
		"APP_ENV": EnvProduction, "DATABASE_URL_FILE": writeSecret(t, strongDBURL, 0o644),
	}))
	if err == nil || !strings.Contains(err.Error(), "droits 0644 trop ouverts") {
		t.Fatalf("un fichier de secret lisible par tous doit être refusé : %v", err)
	}
}

func TestProductionRefusesWeakSecrets(t *testing.T) {
	for name, tc := range map[string]struct{ key, value, want string }{
		"trop court":             {"AUTH_SECRET", "abc", "au moins 32"},
		"valeur d'exemple":       {"AUTH_SECRET", "change-me-change-me-change-me-change-me", "valeur d'exemple"},
		"peu aléatoire":          {"AUTH_SECRET", strings.Repeat("ab", 20), "trop peu aléatoire"},
		"webhook court":          {"PAYMENT_WEBHOOK_SECRET", "W3n8Qz1Lr6Tx9Vk2", "PAYMENT_WEBHOOK_SECRET trop faible"},
		"base sans mot de passe": {"DATABASE_URL", "postgres://ivia@postgres:5432/ivia", "sans mot de passe"},
		"mot de passe faible":    {"DATABASE_URL", "postgres://ivia:password@postgres:5432/ivia", "mot de passe de DATABASE_URL trop faible"},
	} {
		vars := map[string]string{
			"APP_ENV": EnvStaging, "DATABASE_URL": strongDBURL, "AUTH_SECRET": strongAuth,
			"PAYMENT_WEBHOOK_SECRET": strongWebhook,
		}
		vars[tc.key] = tc.value
		_, err := Load(env(vars))
		if err == nil || !strings.Contains(err.Error(), tc.want) {
			t.Errorf("%s : erreur attendue « %s », obtenu %v", name, tc.want, err)
			continue
		}
		if strings.Contains(err.Error(), tc.value) {
			t.Errorf("%s : le message d'erreur recopie le secret", name)
		}
	}
}

func TestStrongSecretsPassInStaging(t *testing.T) {
	_, err := Load(env(map[string]string{
		"APP_ENV": EnvStaging, "DATABASE_URL": strongDBURL, "AUTH_SECRET": strongAuth,
		"PAYMENT_WEBHOOK_SECRET": strongWebhook,
	}))
	// Restent attendues les erreurs d'intégration (e-mail, stockage), jamais une erreur de secret.
	if err != nil && strings.Contains(err.Error(), "trop faible") {
		t.Fatalf("des secrets solides sont refusés : %v", err)
	}
}

func TestConfigNeverPrintsSecrets(t *testing.T) {
	c := Config{
		Env: EnvProduction, DatabaseURL: strongDBURL, AuthSecret: []byte(strongAuth), BrevoAPIKey: "xkeysib-abc123",
		PaymentWebhookSecret: strongWebhook, R2AccessKeyID: "r2-id-123", R2SecretAccessKey: "r2-secret-456",
		SentryDSN: "https://key@sentry.example/1",
	}
	var logs bytes.Buffer
	slog.New(slog.NewJSONHandler(&logs, nil)).Info("démarrage", "config", c)
	outputs := map[string]string{
		"%v": fmt.Sprintf("%v", c), "%+v": fmt.Sprintf("%+v", c), "%#v": fmt.Sprintf("%#v", c),
		"%s": fmt.Sprintf("%s", c), "slog": logs.String(),
	}
	secrets := []string{"Vq8Lm2Rx7Kp4", strongAuth, "xkeysib-abc123", strongWebhook, "r2-id-123", "r2-secret-456", "key@sentry"}
	for verb, out := range outputs {
		for _, s := range secrets {
			if strings.Contains(out, s) {
				t.Errorf("%s laisse passer un secret : %s", verb, out)
			}
		}
	}
}
