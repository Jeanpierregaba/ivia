package business

import (
	"net/http"

	"github.com/google/uuid"

	"ivia/backend/internal/platform/httpapi"
	"ivia/backend/internal/platform/identity"
)

func who(r *http.Request) identity.Principal { return identity.MustFromContext(r.Context()) }

// Register enregistre les routes de l'app Ivia Business et du back-office.
func (s *Service) Register(rt *httpapi.Router) {
	// withSpace lit {id} puis répond avec le résultat de fn.
	withSpace := func(fn func(r *http.Request, p identity.Principal, id uuid.UUID) (any, error)) httpapi.HandlerFunc {
		return func(w http.ResponseWriter, r *http.Request) error {
			id, err := httpapi.PathUUID(r, "id")
			if err != nil {
				return err
			}
			v, err := fn(r, who(r), id)
			if err != nil {
				return err
			}
			return httpapi.OK(w, v)
		}
	}

	rt.Auth("GET /v1/business/spaces", func(w http.ResponseWriter, r *http.Request) error {
		items, err := s.Spaces(r.Context(), who(r).UserID)
		if err != nil {
			return err
		}
		return httpapi.OK(w, map[string]any{"items": items})
	})
	rt.Auth("POST /v1/business/spaces", func(w http.ResponseWriter, r *http.Request) error {
		var in Input
		if err := httpapi.Decode(r, &in); err != nil {
			return err
		}
		v, err := s.Create(r.Context(), who(r).UserID, in)
		if err != nil {
			return err
		}
		return httpapi.Created(w, v)
	})
	rt.Auth("GET /v1/business/spaces/{id}", withSpace(func(r *http.Request, p identity.Principal, id uuid.UUID) (any, error) {
		return s.Get(r.Context(), p.UserID, id)
	}))
	rt.Auth("PUT /v1/business/spaces/{id}", withSpace(func(r *http.Request, p identity.Principal, id uuid.UUID) (any, error) {
		var in Input
		if err := httpapi.Decode(r, &in); err != nil {
			return nil, err
		}
		return s.Update(r.Context(), p.UserID, id, in)
	}))
	rt.Auth("POST /v1/business/spaces/{id}/documents", withSpace(func(r *http.Request, p identity.Principal, id uuid.UUID) (any, error) {
		var in struct {
			Kind      string `json:"kind"`
			ObjectKey string `json:"object_key"`
		}
		if err := httpapi.Decode(r, &in); err != nil {
			return nil, err
		}
		return s.AddDocument(r.Context(), p.UserID, id, in.Kind, in.ObjectKey)
	}))
	rt.Auth("PUT /v1/business/spaces/{id}/payout", withSpace(func(r *http.Request, p identity.Principal, id uuid.UUID) (any, error) {
		var in PayoutInput
		if err := httpapi.Decode(r, &in); err != nil {
			return nil, err
		}
		return s.SetPayout(r.Context(), p.UserID, id, in)
	}))
	rt.Auth("POST /v1/business/spaces/{id}/submit", withSpace(func(r *http.Request, p identity.Principal, id uuid.UUID) (any, error) {
		return s.Submit(r.Context(), p.UserID, id)
	}))
	rt.Auth("POST /v1/business/spaces/{id}/open", withSpace(func(r *http.Request, p identity.Principal, id uuid.UUID) (any, error) {
		return s.Open(r.Context(), p.UserID, p.SessionID, id)
	}))
	rt.Auth("GET /v1/business/session", func(w http.ResponseWriter, r *http.Request) error {
		p := who(r)
		v, err := s.Opened(r.Context(), p.UserID, p.SessionID)
		if err != nil {
			return err
		}
		return httpapi.OK(w, map[string]any{"space": v})
	})
	rt.Auth("DELETE /v1/business/session", func(w http.ResponseWriter, r *http.Request) error {
		if err := s.Close(r.Context(), who(r).SessionID); err != nil {
			return err
		}
		return httpapi.NoContent(w)
	})

	rt.Auth("GET /v1/business/spaces/{id}/items", withSpace(func(r *http.Request, p identity.Principal, id uuid.UUID) (any, error) {
		items, err := s.Items(r.Context(), p.UserID, id)
		return map[string]any{"items": items}, err
	}))
	rt.Auth("POST /v1/business/spaces/{id}/items", func(w http.ResponseWriter, r *http.Request) error {
		id, err := httpapi.PathUUID(r, "id")
		if err != nil {
			return err
		}
		var in ItemInput
		if err := httpapi.Decode(r, &in); err != nil {
			return err
		}
		v, err := s.AddItem(r.Context(), who(r).UserID, id, in)
		if err != nil {
			return err
		}
		return httpapi.Created(w, v)
	})
	rt.Auth("PUT /v1/business/items/{id}", withSpace(func(r *http.Request, p identity.Principal, id uuid.UUID) (any, error) {
		var in ItemInput
		if err := httpapi.Decode(r, &in); err != nil {
			return nil, err
		}
		return s.UpdateItem(r.Context(), p.UserID, id, in)
	}))
	rt.Auth("PUT /v1/business/spaces/{id}/availability", withSpace(func(r *http.Request, p identity.Principal, id uuid.UUID) (any, error) {
		var in struct {
			Availability []DaySlot `json:"availability"`
		}
		if err := httpapi.Decode(r, &in); err != nil {
			return nil, err
		}
		return s.SetAvailability(r.Context(), p.UserID, id, in.Availability)
	}))
	rt.Auth("DELETE /v1/business/items/{id}", func(w http.ResponseWriter, r *http.Request) error {
		id, err := httpapi.PathUUID(r, "id")
		if err != nil {
			return err
		}
		if err := s.DeleteItem(r.Context(), who(r).UserID, id); err != nil {
			return err
		}
		return httpapi.NoContent(w)
	})

	rt.Auth("GET /v1/business/pin", func(w http.ResponseWriter, r *http.Request) error {
		has, err := s.HasPIN(r.Context(), who(r).UserID)
		if err != nil {
			return err
		}
		return httpapi.OK(w, map[string]bool{"is_set": has})
	})
	rt.Auth("PUT /v1/business/pin", func(w http.ResponseWriter, r *http.Request) error {
		var in struct {
			PIN     string `json:"pin"`
			Current string `json:"current_pin"`
		}
		if err := httpapi.Decode(r, &in); err != nil {
			return err
		}
		if err := s.SetPIN(r.Context(), who(r).UserID, in.PIN, in.Current); err != nil {
			return err
		}
		return httpapi.NoContent(w)
	})

	ad := identity.RoleAdmin
	rt.Roles("GET /v1/admin/business/spaces", func(w http.ResponseWriter, r *http.Request) error {
		q := httpapi.NewQuery(r)
		p := q.Page()
		status := q.Enum("status", "", StatusDraft, StatusPending, StatusNeedsChanges, StatusRejected, StatusApproved, StatusSuspended)
		sector := q.Enum("sector", "", SectorShop, SectorRealEstate, SectorArtisan, SectorRestaurant)
		if err := q.Err(); err != nil {
			return err
		}
		var st, se *string
		if status != "" {
			st = &status
		}
		if sector != "" {
			se = &sector
		}
		items, err := s.AdminList(r.Context(), st, se, p.FetchLimit(), int32(p.Offset))
		if err != nil {
			return err
		}
		return httpapi.OK(w, httpapi.NewList(items, p))
	}, ad)
	rt.Roles("GET /v1/admin/business/spaces/{id}", withSpace(func(r *http.Request, _ identity.Principal, id uuid.UUID) (any, error) {
		return s.AdminGet(r.Context(), id)
	}), ad)
	rt.Roles("POST /v1/admin/business/spaces/{id}/review", withSpace(func(r *http.Request, p identity.Principal, id uuid.UUID) (any, error) {
		var in struct {
			Decision string `json:"decision"`
			Reason   string `json:"reason"`
		}
		if err := httpapi.Decode(r, &in); err != nil {
			return nil, err
		}
		return s.Review(r.Context(), p.UserID, id, in.Decision, in.Reason)
	}), ad)
}
