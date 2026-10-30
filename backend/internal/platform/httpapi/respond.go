package httpapi

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"mime"
	"net/http"
	"strconv"

	"ivia/backend/internal/platform/apperr"
)

type errorBody struct {
	Error errorPayload `json:"error"`
}

type errorPayload struct {
	Code    string            `json:"code"`
	Message string            `json:"message"`
	Fields  map[string]string `json:"fields,omitempty"`
}

// WriteJSON écrit body en JSON avec le statut donné.
func WriteJSON(w http.ResponseWriter, status int, body any) {
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Cache-Control", "no-store")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(body)
}

// OK écrit body en JSON avec le statut 200.
func OK(w http.ResponseWriter, body any) error {
	WriteJSON(w, http.StatusOK, body)
	return nil
}

// Created écrit body en JSON avec le statut 201.
func Created(w http.ResponseWriter, body any) error {
	WriteJSON(w, http.StatusCreated, body)
	return nil
}

// NoContent répond 204 sans corps.
func NoContent(w http.ResponseWriter) error {
	w.WriteHeader(http.StatusNoContent)
	return nil
}

// List est l'enveloppe des réponses paginées.
type List[T any] struct {
	Items      []T  `json:"items"`
	NextOffset *int `json:"next_offset"`
}

// NewList construit une page : fetched contient au plus page.Limit+1 éléments, le dernier servant
// seulement à savoir s'il existe une page suivante.
func NewList[T any](fetched []T, page Page) List[T] {
	l := List[T]{Items: fetched}
	if l.Items == nil {
		l.Items = []T{}
	}
	if len(fetched) > page.Limit {
		l.Items = fetched[:page.Limit]
		next := page.Offset + page.Limit
		l.NextOffset = &next
	}
	return l
}

// WriteError traduit une erreur en réponse JSON. Les erreurs inattendues sont journalisées et
// renvoyées comme une erreur 500 générique, sans détail interne.
func WriteError(w http.ResponseWriter, r *http.Request, logger *slog.Logger, err error) {
	if e, ok := apperr.As(err); ok {
		if e.RetryAfterSeconds > 0 {
			w.Header().Set("Retry-After", strconv.Itoa(e.RetryAfterSeconds))
		}
		WriteJSON(w, e.Status, errorBody{Error: errorPayload{Code: e.Code, Message: e.Message, Fields: e.Fields}})
		return
	}
	var maxBytes *http.MaxBytesError
	if errors.As(err, &maxBytes) {
		WriteJSON(w, http.StatusRequestEntityTooLarge, errorBody{Error: errorPayload{
			Code: "body_too_large", Message: "La requête est trop volumineuse.",
		}})
		return
	}
	if errors.Is(err, context.Canceled) && r.Context().Err() != nil {
		// Le client a abandonné la requête : rien à lui répondre.
		return
	}
	logger.Error("erreur interne", "request_id", RequestID(r.Context()), "path", r.URL.Path, "err", err)
	writeInternalError(w, r)
}

func writeInternalError(w http.ResponseWriter, _ *http.Request) {
	WriteJSON(w, http.StatusInternalServerError, errorBody{Error: errorPayload{
		Code:    "internal_error",
		Message: "Une erreur inattendue est survenue. Réessayez dans un instant.",
	}})
}

// Decode lit un corps JSON dans dst : un seul objet, aucun champ inconnu.
func Decode(r *http.Request, dst any) error {
	if ct := r.Header.Get("Content-Type"); ct != "" {
		mt, _, err := mime.ParseMediaType(ct)
		if err != nil || mt != "application/json" {
			return apperr.BadRequest("unsupported_media_type", "Le corps de la requête doit être du JSON.")
		}
	}
	dec := json.NewDecoder(r.Body)
	dec.DisallowUnknownFields()
	if err := dec.Decode(dst); err != nil {
		var maxBytes *http.MaxBytesError
		var typeErr *json.UnmarshalTypeError
		switch {
		case errors.As(err, &maxBytes):
			return err
		case errors.Is(err, io.EOF):
			return apperr.BadRequest("invalid_json", "Le corps de la requête est vide.")
		case errors.As(err, &typeErr) && typeErr.Field != "":
			return apperr.Validation(map[string]string{typeErr.Field: "Type de valeur invalide."})
		default:
			return apperr.BadRequest("invalid_json", fmt.Sprintf("JSON invalide : %s.", jsonErrorHint(err)))
		}
	}
	if dec.More() {
		return apperr.BadRequest("invalid_json", "Le corps doit contenir un seul objet JSON.")
	}
	return nil
}

func jsonErrorHint(err error) string {
	var syntaxErr *json.SyntaxError
	if errors.As(err, &syntaxErr) {
		return "syntaxe incorrecte"
	}
	// json : unknown field "x"
	return err.Error()
}
