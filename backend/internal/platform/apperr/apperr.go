// Package apperr définit les erreurs métier renvoyées au client avec un code stable et un message
// en français. Les services les retournent ; la couche HTTP les traduit en réponse JSON.
package apperr

import (
	"errors"
	"net/http"
)

// Error est une erreur affichable au client.
type Error struct {
	Status  int
	Code    string
	Message string
	// Fields détaille les erreurs de validation (champ → message).
	Fields map[string]string
	// RetryAfterSeconds renseigne l'en-tête Retry-After (limitation de débit).
	RetryAfterSeconds int
}

func (e *Error) Error() string { return e.Code + ": " + e.Message }

// As extrait une *Error de la chaîne d'erreurs.
func As(err error) (*Error, bool) {
	var e *Error
	if errors.As(err, &e) {
		return e, true
	}
	return nil, false
}

// IsCode indique si err porte le code donné.
func IsCode(err error, code string) bool {
	e, ok := As(err)
	return ok && e.Code == code
}

func newErr(status int, code, message string) *Error {
	return &Error{Status: status, Code: code, Message: message}
}

// BadRequest : requête invalide.
func BadRequest(code, message string) *Error { return newErr(http.StatusBadRequest, code, message) }

// Unauthorized : authentification absente ou invalide.
func Unauthorized(code, message string) *Error {
	return newErr(http.StatusUnauthorized, code, message)
}

// Forbidden : authentifié mais action interdite (rôle manquant, compte suspendu).
func Forbidden(code, message string) *Error { return newErr(http.StatusForbidden, code, message) }

// NotFound : ressource absente ou appartenant à un autre utilisateur.
func NotFound(code, message string) *Error { return newErr(http.StatusNotFound, code, message) }

// Conflict : état incompatible avec l'action (transition interdite, doublon).
func Conflict(code, message string) *Error { return newErr(http.StatusConflict, code, message) }

// Unprocessable : requête comprise mais refusée par une règle métier.
func Unprocessable(code, message string) *Error {
	return newErr(http.StatusUnprocessableEntity, code, message)
}

// TooManyRequests : limite de débit atteinte.
func TooManyRequests(code, message string, retryAfterSeconds int) *Error {
	e := newErr(http.StatusTooManyRequests, code, message)
	e.RetryAfterSeconds = retryAfterSeconds
	return e
}

// Unavailable : dépendance externe indisponible.
func Unavailable(code, message string) *Error {
	return newErr(http.StatusServiceUnavailable, code, message)
}

// Validation : une ou plusieurs entrées invalides.
func Validation(fields map[string]string) *Error {
	e := newErr(http.StatusBadRequest, "validation_failed", "Certaines informations sont invalides.")
	e.Fields = fields
	return e
}
