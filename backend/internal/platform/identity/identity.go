// Package identity transporte l'utilisateur authentifié dans le contexte de la requête.
package identity

import (
	"context"
	"slices"

	"github.com/google/uuid"
)

// Role d'un utilisateur. Un utilisateur peut en cumuler plusieurs.
type Role string

const (
	RoleBuyer  Role = "buyer"
	RoleSeller Role = "seller"
	RoleDriver Role = "driver"
	RoleAdmin  Role = "admin"
)

// Valid indique si le rôle est connu.
func (r Role) Valid() bool {
	switch r {
	case RoleBuyer, RoleSeller, RoleDriver, RoleAdmin:
		return true
	}
	return false
}

// Principal est l'utilisateur authentifié qui fait la requête.
type Principal struct {
	UserID    uuid.UUID
	SessionID uuid.UUID
	Roles     []Role
}

// HasRole indique si l'utilisateur possède au moins un des rôles.
func (p Principal) HasRole(roles ...Role) bool {
	for _, r := range roles {
		if slices.Contains(p.Roles, r) {
			return true
		}
	}
	return false
}

type ctxKey struct{}

// WithPrincipal attache l'utilisateur au contexte.
func WithPrincipal(ctx context.Context, p Principal) context.Context {
	return context.WithValue(ctx, ctxKey{}, p)
}

// FromContext retourne l'utilisateur authentifié, s'il y en a un.
func FromContext(ctx context.Context) (Principal, bool) {
	p, ok := ctx.Value(ctxKey{}).(Principal)
	return p, ok
}

// MustFromContext retourne l'utilisateur authentifié ; à n'utiliser que derrière le middleware d'authentification.
func MustFromContext(ctx context.Context) Principal {
	p, ok := FromContext(ctx)
	if !ok {
		panic("identity: aucun utilisateur dans le contexte (route sans middleware d'authentification)")
	}
	return p
}
