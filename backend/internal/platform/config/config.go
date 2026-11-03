// Package config lit et valide la configuration de l'API depuis les variables d'environnement.
package config

import (
	"crypto/rand"
	"errors"
	"fmt"
	"net/url"
	"os"
	"strconv"
	"strings"
	"time"
)

// Environnements reconnus.
const (
	EnvLocal      = "local"
	EnvTest       = "test"
	EnvStaging    = "staging"
	EnvProduction = "production"
)

// Config regroupe toute la configuration de l'API. Voir .env.example pour la description de chaque variable.
type Config struct {
	Env           string
	Port          string
	DatabaseURL   string
	PublicBaseURL string
	LogLevel      string
	// TrustProxyHeaders : lire l'adresse du client dans X-Forwarded-For (derrière Caddy uniquement).
	TrustProxyHeaders bool

	// AuthSecret sert de clé HMAC pour hacher les codes OTP.
	AuthSecret []byte
	SessionTTL time.Duration

	OTPSender       string // log | smtp | brevo
	SMTPAddr        string
	SMTPFrom        string
	BrevoAPIKey     string
	BrevoSenderMail string
	BrevoSenderName string

	PaymentProvider      string // fake
	PaymentWebhookSecret string

	PushSender         string // log | fcm
	FCMCredentialsFile string

	Storage           string // local | r2
	LocalStorageDir   string
	R2AccountID       string
	R2AccessKeyID     string
	R2SecretAccessKey string
	R2PublicBucket    string
	R2PrivateBucket   string
	R2PublicBaseURL   string

	// RunWorkers : exécuter les tâches de fond River dans ce processus.
	RunWorkers bool

	// GoogleClientIDs : identifiants OAuth (Android, iOS, web) acceptés pour la connexion avec
	// Google, séparés par des virgules dans GOOGLE_CLIENT_IDS. Vide : connexion Google désactivée.
	GoogleClientIDs []string

	// SentryDSN : suivi des erreurs (vide : désactivé). Version : identifiant de la version déployée.
	SentryDSN string
	Version   string
}

// IsProduction indique un environnement où les implémentations factices sont interdites.
func (c Config) IsProduction() bool { return c.Env == EnvProduction || c.Env == EnvStaging }

// DevToolsEnabled indique si les routes de simulation (/v1/dev/...) sont exposées.
func (c Config) DevToolsEnabled() bool { return c.Env == EnvLocal || c.Env == EnvTest }

// Load lit la configuration. getenv vaut os.Getenv en production ; les tests en passent une autre.
func Load(getenv func(string) string) (Config, error) {
	if getenv == nil {
		getenv = os.Getenv
	}
	get := func(key, def string) string {
		if v := strings.TrimSpace(getenv(key)); v != "" {
			return v
		}
		return def
	}

	// Secrets : lus dans <NOM>_FILE (production) ou <NOM> (local), voir secrets.go.
	env := strings.TrimSpace(getenv("APP_ENV"))
	production := env == EnvProduction || env == EnvStaging
	var errs []error
	secrets := make(map[string]string, len(secretKeys))
	unreadable := map[string]bool{} // déjà signalés : pas de second message « non définie »
	for _, k := range secretKeys {
		v, err := readSecret(getenv, k, production)
		if err != nil {
			errs = append(errs, err)
			unreadable[k] = true
		}
		secrets[k] = v
	}

	c := Config{
		// Pas de valeur par défaut : un déploiement qui oublie APP_ENV ne doit jamais démarrer en
		// mode local (routes de simulation ouvertes, implémentations factices acceptées).
		Env:                  get("APP_ENV", ""),
		Port:                 get("PORT", "8080"),
		DatabaseURL:          secrets["DATABASE_URL"],
		LogLevel:             get("LOG_LEVEL", "info"),
		OTPSender:            get("OTP_SENDER", "log"),
		SMTPAddr:             get("SMTP_ADDR", "localhost:1025"),
		SMTPFrom:             get("SMTP_FROM", "ivia <no-reply@ivia.local>"),
		BrevoAPIKey:          secrets["BREVO_API_KEY"],
		BrevoSenderMail:      get("BREVO_SENDER_EMAIL", ""),
		BrevoSenderName:      get("BREVO_SENDER_NAME", "ivia"),
		PaymentProvider:      get("PAYMENT_PROVIDER", "fake"),
		PaymentWebhookSecret: secrets["PAYMENT_WEBHOOK_SECRET"],
		PushSender:           get("PUSH_SENDER", "log"),
		FCMCredentialsFile:   get("FCM_CREDENTIALS_FILE", ""),
		Storage:              get("STORAGE", "local"),
		LocalStorageDir:      get("LOCAL_STORAGE_DIR", "./var/uploads"),
		R2AccountID:          get("R2_ACCOUNT_ID", ""),
		R2AccessKeyID:        secrets["R2_ACCESS_KEY_ID"],
		R2SecretAccessKey:    secrets["R2_SECRET_ACCESS_KEY"],
		R2PublicBucket:       get("R2_PUBLIC_BUCKET", ""),
		R2PrivateBucket:      get("R2_PRIVATE_BUCKET", ""),
		R2PublicBaseURL:      strings.TrimRight(get("R2_PUBLIC_BASE_URL", ""), "/"),
		SentryDSN:            secrets["SENTRY_DSN"],
		Version:              get("APP_VERSION", "dev"),
	}
	c.PublicBaseURL = strings.TrimRight(get("PUBLIC_BASE_URL", "http://localhost:"+c.Port), "/")
	for _, id := range strings.Split(get("GOOGLE_CLIENT_IDS", ""), ",") {
		if id = strings.TrimSpace(id); id != "" {
			c.GoogleClientIDs = append(c.GoogleClientIDs, id)
		}
	}

	switch c.Env {
	case EnvLocal, EnvTest, EnvStaging, EnvProduction:
	case "":
		errs = append(errs, errors.New("APP_ENV non définie : local, test, staging ou production (voir .env.example)"))
	default:
		errs = append(errs, fmt.Errorf("APP_ENV invalide : %q", c.Env))
	}
	if c.DatabaseURL == "" && !unreadable["DATABASE_URL"] {
		errs = append(errs, errors.New("DATABASE_URL non définie (voir .env.example)"))
	}

	var err error
	if c.TrustProxyHeaders, err = parseBool(get("TRUST_PROXY_HEADERS", "false")); err != nil {
		errs = append(errs, fmt.Errorf("TRUST_PROXY_HEADERS : %w", err))
	}
	if c.RunWorkers, err = parseBool(get("RUN_WORKERS", "true")); err != nil {
		errs = append(errs, fmt.Errorf("RUN_WORKERS : %w", err))
	}
	if c.SessionTTL, err = time.ParseDuration(get("SESSION_TTL", "1440h")); err != nil || c.SessionTTL < time.Hour {
		errs = append(errs, errors.New("SESSION_TTL invalide (durée Go, au moins 1h, ex. 1440h)"))
	}

	secret := secrets["AUTH_SECRET"]
	switch {
	case secret == "" && !c.IsProduction():
		// En local, un secret aléatoire suffit : les codes OTP en cours sont perdus au redémarrage.
		c.AuthSecret = make([]byte, 32)
		_, _ = rand.Read(c.AuthSecret)
	case len(secret) < 32:
		errs = append(errs, errors.New("AUTH_SECRET doit faire au moins 32 caractères"))
	default:
		c.AuthSecret = []byte(secret)
	}
	if c.IsProduction() {
		errs = append(errs, c.validateSecretStrength()...)
	}

	errs = append(errs, c.validateIntegrations()...)
	if len(errs) > 0 {
		return Config{}, errors.Join(errs...)
	}
	return c, nil
}

func (c Config) validateIntegrations() []error {
	var errs []error
	switch c.OTPSender {
	case "log":
		if c.IsProduction() {
			errs = append(errs, errors.New("OTP_SENDER=log interdit hors local"))
		}
	case "smtp":
		// Boîte de réception locale (Mailpit) : jamais hors local et test.
		if c.IsProduction() {
			errs = append(errs, errors.New("OTP_SENDER=smtp interdit hors local (utiliser brevo)"))
		}
	case "brevo":
		if c.BrevoAPIKey == "" || c.BrevoSenderMail == "" {
			errs = append(errs, errors.New("OTP_SENDER=brevo demande BREVO_API_KEY et BREVO_SENDER_EMAIL"))
		}
	default:
		errs = append(errs, fmt.Errorf("OTP_SENDER inconnu : %q", c.OTPSender))
	}

	switch c.PaymentProvider {
	case "fake":
		if c.Env == EnvProduction {
			errs = append(errs, errors.New("PAYMENT_PROVIDER=fake interdit en production"))
		}
	default:
		errs = append(errs, fmt.Errorf("PAYMENT_PROVIDER inconnu : %q (prestataire à choisir, ADR 0007)", c.PaymentProvider))
	}
	if c.IsProduction() && c.PaymentWebhookSecret == "" {
		errs = append(errs, errors.New("PAYMENT_WEBHOOK_SECRET obligatoire hors local"))
	}

	switch c.PushSender {
	case "log":
		if c.Env == EnvProduction {
			errs = append(errs, errors.New("PUSH_SENDER=log interdit en production"))
		}
	case "fcm":
		if c.FCMCredentialsFile == "" {
			errs = append(errs, errors.New("PUSH_SENDER=fcm demande FCM_CREDENTIALS_FILE"))
		}
	default:
		errs = append(errs, fmt.Errorf("PUSH_SENDER inconnu : %q", c.PushSender))
	}

	switch c.Storage {
	case "local":
		if c.IsProduction() {
			errs = append(errs, errors.New("STORAGE=local interdit hors local"))
		}
	case "r2":
		if c.R2AccountID == "" || c.R2AccessKeyID == "" || c.R2SecretAccessKey == "" ||
			c.R2PublicBucket == "" || c.R2PrivateBucket == "" || c.R2PublicBaseURL == "" {
			errs = append(errs, errors.New("STORAGE=r2 demande toutes les variables R2_*"))
		}
	default:
		errs = append(errs, fmt.Errorf("STORAGE inconnu : %q", c.Storage))
	}
	return errs
}

// validateSecretStrength refuse, hors local, les secrets courts, d'exemple ou peu aléatoires, et
// une base de données sans mot de passe solide. Les messages ne citent jamais la valeur.
func (c Config) validateSecretStrength() []error {
	var errs []error
	check := func(name, v string, minLen int) {
		if v == "" {
			return // l'absence est signalée par la validation de l'intégration concernée
		}
		if why := weakSecret(v, minLen); why != "" {
			errs = append(errs, fmt.Errorf("%s trop faible : %s", name, why))
		}
	}
	check("AUTH_SECRET", string(c.AuthSecret), 32)
	check("PAYMENT_WEBHOOK_SECRET", c.PaymentWebhookSecret, 32)
	check("R2_SECRET_ACCESS_KEY", c.R2SecretAccessKey, 32)
	if c.DatabaseURL != "" {
		u, err := url.Parse(c.DatabaseURL)
		if err != nil {
			errs = append(errs, errors.New("DATABASE_URL illisible"))
		} else if pw, ok := u.User.Password(); !ok {
			errs = append(errs, errors.New("DATABASE_URL sans mot de passe"))
		} else if why := weakSecret(pw, 24); why != "" {
			errs = append(errs, fmt.Errorf("mot de passe de DATABASE_URL trop faible : %s", why))
		}
	}
	return errs
}

func parseBool(s string) (bool, error) {
	b, err := strconv.ParseBool(s)
	if err != nil {
		return false, fmt.Errorf("booléen attendu, reçu %q", s)
	}
	return b, nil
}
