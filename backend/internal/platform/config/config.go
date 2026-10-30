// Package config lit et valide la configuration de l'API depuis les variables d'environnement.
package config

import (
	"crypto/rand"
	"errors"
	"fmt"
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

	OTPSender       string // log | brevo
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

	c := Config{
		Env:                  get("APP_ENV", EnvLocal),
		Port:                 get("PORT", "8080"),
		DatabaseURL:          get("DATABASE_URL", ""),
		LogLevel:             get("LOG_LEVEL", "info"),
		OTPSender:            get("OTP_SENDER", "log"),
		BrevoAPIKey:          get("BREVO_API_KEY", ""),
		BrevoSenderMail:      get("BREVO_SENDER_EMAIL", ""),
		BrevoSenderName:      get("BREVO_SENDER_NAME", "ivia"),
		PaymentProvider:      get("PAYMENT_PROVIDER", "fake"),
		PaymentWebhookSecret: get("PAYMENT_WEBHOOK_SECRET", ""),
		PushSender:           get("PUSH_SENDER", "log"),
		FCMCredentialsFile:   get("FCM_CREDENTIALS_FILE", ""),
		Storage:              get("STORAGE", "local"),
		LocalStorageDir:      get("LOCAL_STORAGE_DIR", "./var/uploads"),
		R2AccountID:          get("R2_ACCOUNT_ID", ""),
		R2AccessKeyID:        get("R2_ACCESS_KEY_ID", ""),
		R2SecretAccessKey:    get("R2_SECRET_ACCESS_KEY", ""),
		R2PublicBucket:       get("R2_PUBLIC_BUCKET", ""),
		R2PrivateBucket:      get("R2_PRIVATE_BUCKET", ""),
		R2PublicBaseURL:      strings.TrimRight(get("R2_PUBLIC_BASE_URL", ""), "/"),
	}
	c.PublicBaseURL = strings.TrimRight(get("PUBLIC_BASE_URL", "http://localhost:"+c.Port), "/")

	var errs []error
	switch c.Env {
	case EnvLocal, EnvTest, EnvStaging, EnvProduction:
	default:
		errs = append(errs, fmt.Errorf("APP_ENV invalide : %q", c.Env))
	}
	if c.DatabaseURL == "" {
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

	secret := getenv("AUTH_SECRET")
	switch {
	case len(secret) >= 32:
		c.AuthSecret = []byte(secret)
	case secret == "" && !c.IsProduction():
		// En local, un secret aléatoire suffit : les codes OTP en cours sont perdus au redémarrage.
		c.AuthSecret = make([]byte, 32)
		_, _ = rand.Read(c.AuthSecret)
	default:
		errs = append(errs, errors.New("AUTH_SECRET doit faire au moins 32 caractères"))
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
	if c.IsProduction() && len(c.PaymentWebhookSecret) < 16 {
		errs = append(errs, errors.New("PAYMENT_WEBHOOK_SECRET obligatoire hors local (16 caractères au moins)"))
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

func parseBool(s string) (bool, error) {
	b, err := strconv.ParseBool(s)
	if err != nil {
		return false, fmt.Errorf("booléen attendu, reçu %q", s)
	}
	return b, nil
}
