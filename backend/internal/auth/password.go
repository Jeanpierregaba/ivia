package auth

import (
	"crypto/rand"
	"crypto/subtle"
	"encoding/base64"
	"errors"
	"fmt"
	"strings"
	"unicode"
	"unicode/utf8"

	"golang.org/x/crypto/argon2"

	"ivia/backend/internal/platform/apperr"
)

// Hachage des mots de passe : Argon2id, paramètres recommandés par l'OWASP (19 Mio, 2 passes,
// 1 fil), stocké au format PHC ($argon2id$v=19$m=…,t=…,p=…$sel$empreinte) pour pouvoir changer
// les paramètres plus tard sans invalider les mots de passe existants.
const (
	argonMemoryKiB = 19 * 1024
	argonTime      = 2
	argonThreads   = 1
	argonKeyLen    = 32
	argonSaltLen   = 16

	// Hachages simultanés au plus : chacun réserve 19 Mio, le serveur en a 4 Go.
	maxConcurrentHashes = 8

	MinPasswordLength = 10
	MaxPasswordLength = 128
)

type passwordHasher struct {
	slots chan struct{}
	// dummy : empreinte comparée quand le compte n'existe pas, pour un temps de réponse identique.
	dummy string
}

func newPasswordHasher() *passwordHasher {
	h := &passwordHasher{slots: make(chan struct{}, maxConcurrentHashes)}
	h.dummy, _ = h.hash("compte-inexistant-" + rand.Text())
	return h
}

func (h *passwordHasher) hash(password string) (string, error) {
	salt := make([]byte, argonSaltLen)
	if _, err := rand.Read(salt); err != nil {
		return "", fmt.Errorf("sel du mot de passe : %w", err)
	}
	h.slots <- struct{}{}
	key := argon2.IDKey([]byte(password), salt, argonTime, argonMemoryKiB, argonThreads, argonKeyLen)
	<-h.slots
	return fmt.Sprintf("$argon2id$v=%d$m=%d,t=%d,p=%d$%s$%s", argon2.Version, argonMemoryKiB, argonTime, argonThreads,
		base64.RawStdEncoding.EncodeToString(salt), base64.RawStdEncoding.EncodeToString(key)), nil
}

var errBadHash = errors.New("empreinte de mot de passe illisible")

// verify compare en temps constant un mot de passe à une empreinte PHC Argon2id.
func (h *passwordHasher) verify(password, encoded string) (bool, error) {
	parts := strings.Split(encoded, "$")
	if len(parts) != 6 || parts[1] != "argon2id" {
		return false, errBadHash
	}
	var version int
	if _, err := fmt.Sscanf(parts[2], "v=%d", &version); err != nil || version != argon2.Version {
		return false, errBadHash
	}
	var memory, time uint32
	var threads uint8
	if _, err := fmt.Sscanf(parts[3], "m=%d,t=%d,p=%d", &memory, &time, &threads); err != nil {
		return false, errBadHash
	}
	salt, err := base64.RawStdEncoding.DecodeString(parts[4])
	if err != nil {
		return false, errBadHash
	}
	want, err := base64.RawStdEncoding.DecodeString(parts[5])
	if err != nil || len(want) == 0 {
		return false, errBadHash
	}
	h.slots <- struct{}{}
	got := argon2.IDKey([]byte(password), salt, time, memory, threads, uint32(len(want)))
	<-h.slots
	return subtle.ConstantTimeCompare(got, want) == 1, nil
}

// Mots de passe parmi les plus courants (et leurs variantes françaises) : refusés d'emblée.
var commonPasswords = map[string]bool{
	"motdepasse": true, "motdepasse1": true, "motdepasse123": true, "password": true, "password1": true,
	"password123": true, "azertyuiop": true, "azerty1234": true, "qwertyuiop": true, "1234567890": true,
	"0123456789": true, "0987654321": true, "1111111111": true, "aaaaaaaaaa": true, "iloveyou12": true,
	"bonjour123": true, "soleil1234": true, "ivia123456": true, "lome123456": true, "togo123456": true,
}

// checkPassword applique les règles de mot de passe (ADR 0011) : 10 à 128 caractères, différent
// de l'e-mail, absent des mots de passe les plus courants. Pas de règle de composition : la
// longueur protège mieux et se retient plus facilement.
func checkPassword(password, email string) error {
	return checkPasswordField("password", password, email)
}

// checkPasswordField applique ces règles et rapporte l'erreur sur le champ envoyé par l'app.
func checkPasswordField(field, password, email string) error {
	n := utf8.RuneCountInString(password)
	switch {
	case n < MinPasswordLength:
		return apperr.Validation(map[string]string{field: fmt.Sprintf("Le mot de passe doit faire au moins %d caractères.", MinPasswordLength)})
	case n > MaxPasswordLength:
		return apperr.Validation(map[string]string{field: fmt.Sprintf("Le mot de passe fait %d caractères au plus.", MaxPasswordLength)})
	}
	lower := strings.ToLower(password)
	local, _, _ := strings.Cut(strings.ToLower(email), "@")
	// Comparaison sans ponctuation : « kossiagbeko2026 » ressemble à « kossi.agbeko@… ».
	bare, bareLocal := lettersAndDigits(lower), lettersAndDigits(local)
	if commonPasswords[lower] || commonPasswords[bare] || lower == strings.ToLower(email) ||
		(len(bareLocal) >= 4 && strings.Contains(bare, bareLocal) && n < 16) {
		return apperr.Validation(map[string]string{field: "Ce mot de passe est trop facile à deviner. Choisissez-en un autre."})
	}
	return nil
}

func lettersAndDigits(v string) string {
	return strings.Map(func(r rune) rune {
		if unicode.IsLetter(r) || unicode.IsDigit(r) {
			return r
		}
		return -1
	}, v)
}
