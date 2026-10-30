// Package validate regroupe la validation des entrées : accumulation des erreurs par champ,
// normalisation des e-mails et numéros togolais, coordonnées.
package validate

import (
	"net/mail"
	"regexp"
	"strings"
	"unicode/utf8"

	"ivia/backend/internal/platform/apperr"
)

// Errors accumule les erreurs par champ.
type Errors map[string]string

// New crée un accumulateur vide.
func New() Errors { return Errors{} }

// Add enregistre une erreur sur un champ (la première gagne).
func (e Errors) Add(field, msg string) {
	if _, ok := e[field]; !ok {
		e[field] = msg
	}
}

// Check enregistre msg sur field si ok est faux.
func (e Errors) Check(ok bool, field, msg string) {
	if !ok {
		e.Add(field, msg)
	}
}

// Text vérifie une chaîne déjà nettoyée : obligatoire si min > 0, longueur en caractères dans [min, max].
func (e Errors) Text(field, value string, min, max int) {
	n := utf8.RuneCountInString(value)
	switch {
	case min > 0 && n == 0:
		e.Add(field, "Champ obligatoire.")
	case n < min:
		e.Add(field, "Trop court.")
	case n > max:
		e.Add(field, "Trop long.")
	}
}

// Err retourne une erreur de validation s'il y a au moins une erreur.
func (e Errors) Err() error {
	if len(e) == 0 {
		return nil
	}
	return apperr.Validation(e)
}

// Clean retire les espaces superflus et les caractères de contrôle d'un texte saisi.
func Clean(s string) string {
	s = strings.Map(func(r rune) rune {
		if r == '\n' || r == '\t' {
			return r
		}
		if r < 0x20 || r == 0x7f {
			return -1
		}
		return r
	}, s)
	return strings.TrimSpace(s)
}

// NormalizeEmail retourne l'adresse en minuscules si elle est valide.
func NormalizeEmail(s string) (string, bool) {
	s = strings.ToLower(strings.TrimSpace(s))
	if len(s) > 254 || strings.ContainsAny(s, " <>") {
		return "", false
	}
	addr, err := mail.ParseAddress(s)
	if err != nil || addr.Address != s || !strings.Contains(s[strings.LastIndexByte(s, '@')+1:], ".") {
		return "", false
	}
	return s, true
}

var nonDigits = regexp.MustCompile(`[^0-9]`)

// NormalizeTogoPhone accepte un numéro mobile togolais (8 chiffres commençant par 7 ou 9, avec ou
// sans indicatif +228 / 00228, espaces et tirets tolérés) et le retourne au format +228XXXXXXXX.
func NormalizeTogoPhone(s string) (string, bool) {
	s = strings.TrimSpace(s)
	if s == "" {
		return "", false
	}
	digits := nonDigits.ReplaceAllString(s, "")
	switch {
	case strings.HasPrefix(digits, "00228"):
		digits = digits[5:]
	case strings.HasPrefix(digits, "228") && len(digits) == 11:
		digits = digits[3:]
	}
	if len(digits) != 8 || (digits[0] != '7' && digits[0] != '9') {
		return "", false
	}
	return "+228" + digits, true
}

// MaskPhone masque un numéro pour l'affichage ou les journaux (+228 90 •• •• 34).
func MaskPhone(p string) string {
	if len(p) < 6 {
		return "••••"
	}
	return p[:6] + "••••" + p[len(p)-2:]
}

// Coordinates vérifie une position (latitude, longitude en degrés).
func (e Errors) Coordinates(prefix string, lat, lng float64) {
	e.Check(lat >= -90 && lat <= 90 && lat != 0, prefix+"lat", "Latitude invalide.")
	e.Check(lng >= -180 && lng <= 180 && lng != 0, prefix+"lng", "Longitude invalide.")
}
