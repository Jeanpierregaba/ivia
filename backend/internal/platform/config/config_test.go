package config

import (
	"strings"
	"testing"
)

func env(m map[string]string) func(string) string { return func(k string) string { return m[k] } }

func TestAppEnvIsRequired(t *testing.T) {
	_, err := Load(env(map[string]string{"DATABASE_URL": "postgres://x"}))
	if err == nil || !strings.Contains(err.Error(), "APP_ENV non définie") {
		t.Fatalf("sans APP_ENV, le démarrage doit échouer : %v", err)
	}
}

func TestDevToolsOnlyInLocalAndTest(t *testing.T) {
	for env, want := range map[string]bool{EnvLocal: true, EnvTest: true, EnvStaging: false, EnvProduction: false} {
		if got := (Config{Env: env}).DevToolsEnabled(); got != want {
			t.Errorf("DevToolsEnabled(%s) = %v, attendu %v", env, got, want)
		}
	}
}

func TestProductionRefusesFakes(t *testing.T) {
	_, err := Load(env(map[string]string{
		"APP_ENV": EnvProduction, "DATABASE_URL": "postgres://x", "AUTH_SECRET": strings.Repeat("s", 32),
		"PAYMENT_WEBHOOK_SECRET": strings.Repeat("w", 16),
	}))
	if err == nil {
		t.Fatal("la production doit refuser l'envoi de codes dans les journaux, le faux paiement et le stockage local")
	}
	for _, want := range []string{"OTP_SENDER=log", "PAYMENT_PROVIDER=fake", "PUSH_SENDER=log", "STORAGE=local"} {
		if !strings.Contains(err.Error(), want) {
			t.Errorf("erreur attendue sur %s : %v", want, err)
		}
	}
}

func TestLocalDefaults(t *testing.T) {
	c, err := Load(env(map[string]string{"APP_ENV": EnvLocal, "DATABASE_URL": "postgres://x"}))
	if err != nil {
		t.Fatal(err)
	}
	if len(c.AuthSecret) < 32 || c.Port != "8080" {
		t.Fatalf("valeurs par défaut locales : %+v", c)
	}
}
