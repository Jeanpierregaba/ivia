package config

import (
	"errors"
	"fmt"
	"io"
	"log/slog"
	"os"
	"runtime"
	"strings"
)

// Secrets : en production, chaque secret est lu dans un fichier (`<NOM>_FILE`, monté par Docker
// Compose dans /run/secrets) plutôt que dans une variable d'environnement, lisible par
// `docker inspect` et par tout processus du conteneur. La variable `<NOM>` reste acceptée en local.

// secretKeys : variables traitées comme secrets (lecture par fichier possible, jamais journalisées).
var secretKeys = []string{
	"DATABASE_URL", "AUTH_SECRET", "BREVO_API_KEY", "PAYMENT_WEBHOOK_SECRET",
	"R2_ACCESS_KEY_ID", "R2_SECRET_ACCESS_KEY", "SENTRY_DSN",
}

// maxSecretBytes borne la taille d'un fichier de secret (une URL de base ou une clé d'API).
const maxSecretBytes = 4 << 10

// readSecret lit <key>_FILE si elle est définie, sinon <key>. Les deux à la fois sont refusées :
// on ne doit pas pouvoir se demander laquelle s'applique.
func readSecret(getenv func(string) string, key string, production bool) (string, error) {
	inline := strings.TrimSpace(getenv(key))
	path := strings.TrimSpace(getenv(key + "_FILE"))
	if path == "" {
		return inline, nil
	}
	if inline != "" {
		return "", fmt.Errorf("%s et %s_FILE sont définies toutes les deux : n'en garder qu'une", key, key)
	}
	f, err := os.Open(path)
	if err != nil {
		return "", fmt.Errorf("%s_FILE : fichier illisible (%s)", key, errorKind(err))
	}
	defer f.Close()
	info, err := f.Stat()
	if err != nil || !info.Mode().IsRegular() {
		return "", fmt.Errorf("%s_FILE : %s n'est pas un fichier", key, path)
	}
	// Droits réservés au propriétaire (400 ou 600) : vérifiable sous Linux, où tourne la production.
	if production && runtime.GOOS != "windows" && info.Mode().Perm()&0o077 != 0 {
		return "", fmt.Errorf("%s_FILE : droits %04o trop ouverts sur %s (attendu 400 ou 600)", key, info.Mode().Perm(), path)
	}
	b, err := io.ReadAll(io.LimitReader(f, maxSecretBytes+1))
	if err != nil {
		return "", fmt.Errorf("%s_FILE : lecture impossible (%s)", key, errorKind(err))
	}
	if len(b) > maxSecretBytes {
		return "", fmt.Errorf("%s_FILE : fichier trop gros pour un secret", key)
	}
	// Fichier vide : secret non configuré (Sentry facultatif, par exemple). Les secrets obligatoires
	// sont exigés ensuite par la validation de Load.
	return strings.TrimSpace(string(b)), nil
}

// errorKind résume une erreur de fichier sans recopier de contenu.
func errorKind(err error) string {
	switch {
	case errors.Is(err, os.ErrNotExist):
		return "absent"
	case errors.Is(err, os.ErrPermission):
		return "accès refusé"
	default:
		return "erreur d'entrée-sortie"
	}
}

// placeholders : fragments trahissant une valeur d'exemple recopiée telle quelle.
var placeholders = []string{"change", "example", "exemple", "xxx", "todo", "secret", "password", "motdepasse", "<", "votre"}

// weakSecret explique pourquoi un secret est trop faible pour la production ("" s'il convient).
func weakSecret(v string, minLen int) string {
	if len(v) < minLen {
		return fmt.Sprintf("%d caractères au moins", minLen)
	}
	lower := strings.ToLower(v)
	for _, p := range placeholders {
		if strings.Contains(lower, p) {
			return "valeur d'exemple, à générer (openssl rand -base64 48)"
		}
	}
	distinct := map[rune]bool{}
	for _, r := range v {
		distinct[r] = true
	}
	if len(distinct) < 12 {
		return "trop peu aléatoire, à générer (openssl rand -base64 48)"
	}
	return ""
}

// redacted remplace un secret dans les journaux et les messages.
func redacted(v string) string {
	if v == "" {
		return ""
	}
	return "[masqué]"
}

// String décrit la configuration sans aucun secret : un `%v` ou un `%+v` accidentel ne fuit rien.
func (c Config) String() string {
	return fmt.Sprintf("Config{Env:%s Port:%s PublicBaseURL:%s OTPSender:%s PaymentProvider:%s PushSender:%s Storage:%s "+
		"DatabaseURL:%s AuthSecret:%s BrevoAPIKey:%s PaymentWebhookSecret:%s R2AccessKeyID:%s R2SecretAccessKey:%s SentryDSN:%s}",
		c.Env, c.Port, c.PublicBaseURL, c.OTPSender, c.PaymentProvider, c.PushSender, c.Storage,
		redacted(c.DatabaseURL), redacted(string(c.AuthSecret)), redacted(c.BrevoAPIKey), redacted(c.PaymentWebhookSecret),
		redacted(c.R2AccessKeyID), redacted(c.R2SecretAccessKey), redacted(c.SentryDSN))
}

// GoString couvre `%#v`.
func (c Config) GoString() string { return c.String() }

// LogValue couvre slog : seuls les réglages sans secret sont journalisés.
func (c Config) LogValue() slog.Value {
	return slog.GroupValue(
		slog.String("env", c.Env), slog.String("port", c.Port), slog.String("public_base_url", c.PublicBaseURL),
		slog.String("otp_sender", c.OTPSender), slog.String("payment_provider", c.PaymentProvider),
		slog.String("push_sender", c.PushSender), slog.String("storage", c.Storage), slog.String("version", c.Version),
	)
}
