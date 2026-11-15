package httpapi

import (
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/google/uuid"

	"ivia/backend/internal/platform/apperr"
)

// PathUUID lit un identifiant dans le chemin. Un identifiant mal formé est traité comme une
// ressource absente (404), pour ne rien révéler.
func PathUUID(r *http.Request, name string) (uuid.UUID, error) {
	id, err := uuid.Parse(r.PathValue(name))
	if err != nil {
		return uuid.Nil, apperr.NotFound("not_found", "Ressource introuvable.")
	}
	return id, nil
}

// Page décrit une pagination par décalage.
type Page struct {
	Limit  int
	Offset int
}

// FetchLimit est le nombre de lignes à demander à la base (une de plus pour savoir s'il y a une suite).
func (p Page) FetchLimit() int32 { return int32(p.Limit + 1) }

// Query aide à lire et valider les paramètres de chaîne de requête en accumulant les erreurs.
type Query struct {
	r      *http.Request
	errors map[string]string
}

// NewQuery prépare la lecture des paramètres de r.
func NewQuery(r *http.Request) *Query { return &Query{r: r, errors: map[string]string{}} }

func (q *Query) raw(name string) string { return strings.TrimSpace(q.r.URL.Query().Get(name)) }

func (q *Query) fail(name, msg string) { q.errors[name] = msg }

// String retourne le paramètre (vide s'il est absent), limité à max caractères.
func (q *Query) String(name string, max int) string {
	v := q.raw(name)
	if len([]rune(v)) > max {
		q.fail(name, "Valeur trop longue.")
		return ""
	}
	return v
}

// Enum retourne le paramètre s'il fait partie des valeurs permises, def s'il est absent.
func (q *Query) Enum(name, def string, allowed ...string) string {
	v := q.raw(name)
	if v == "" {
		return def
	}
	for _, a := range allowed {
		if v == a {
			return v
		}
	}
	q.fail(name, "Valeur non reconnue : "+strings.Join(allowed, ", ")+".")
	return def
}

// UUID retourne le paramètre comme identifiant (nil s'il est absent).
func (q *Query) UUID(name string) *uuid.UUID {
	v := q.raw(name)
	if v == "" {
		return nil
	}
	id, err := uuid.Parse(v)
	if err != nil {
		q.fail(name, "Identifiant invalide.")
		return nil
	}
	return &id
}

// Int64 retourne le paramètre entier dans [min, max] (nil s'il est absent).
func (q *Query) Int64(name string, min, max int64) *int64 {
	v := q.raw(name)
	if v == "" {
		return nil
	}
	n, err := strconv.ParseInt(v, 10, 64)
	if err != nil || n < min || n > max {
		q.fail(name, "Nombre entier attendu entre "+strconv.FormatInt(min, 10)+" et "+strconv.FormatInt(max, 10)+".")
		return nil
	}
	return &n
}

// Float retourne le paramètre décimal dans [min, max] (nil s'il est absent). Réservé aux coordonnées.
func (q *Query) Float(name string, min, max float64) *float64 {
	v := q.raw(name)
	if v == "" {
		return nil
	}
	f, err := strconv.ParseFloat(v, 64)
	if err != nil || f < min || f > max {
		q.fail(name, "Valeur numérique hors limites.")
		return nil
	}
	return &f
}

// Date retourne le paramètre au format AAAA-MM-JJ (nil s'il est absent).
func (q *Query) Date(name string) *time.Time {
	v := q.raw(name)
	if v == "" {
		return nil
	}
	d, err := time.Parse(time.DateOnly, v)
	if err != nil {
		q.fail(name, "Date attendue au format AAAA-MM-JJ.")
		return nil
	}
	return &d
}

// Require signale un paramètre obligatoire absent.
func (q *Query) Require(name string) {
	if q.raw(name) == "" {
		if _, already := q.errors[name]; !already {
			q.fail(name, "Paramètre obligatoire.")
		}
	}
}

// Page lit limit (1-100, 20 par défaut) et offset (0-10000).
func (q *Query) Page() Page {
	p := Page{Limit: 20}
	if l := q.Int64("limit", 1, 100); l != nil {
		p.Limit = int(*l)
	}
	if o := q.Int64("offset", 0, 10000); o != nil {
		p.Offset = int(*o)
	}
	return p
}

// Err retourne une erreur de validation si un paramètre était invalide.
func (q *Query) Err() error {
	if len(q.errors) == 0 {
		return nil
	}
	return apperr.Validation(q.errors)
}
