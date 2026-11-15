// Package adminperm définit les rôles des comptes admin (spec 039) et les sections du back-office
// que chacun peut utiliser. Le super admin peut tout faire ; les autres ne voient que leur domaine.
// Le contrôle est fait par le routeur à chaque requête admin (/v1/admin/<section>/...).
package adminperm

import (
	"slices"
	"strings"
)

// Rôles des comptes admin.
const (
	SuperAdmin = "super_admin"
	Operations = "operations"
	Network    = "network"
	Health     = "health"
	Marketing  = "marketing"
	Finance    = "finance"
	Map        = "map"
	Support    = "support"
)

// Role décrit un rôle pour le back-office.
type Role struct {
	Code        string `json:"code"`
	Label       string `json:"label"`
	Description string `json:"description"`
}

// Roles : rôles proposés à la création d'un compte admin, dans l'ordre d'affichage.
var Roles = []Role{
	{SuperAdmin, "Super admin", "Tout le back-office, comptes admin et journal de toutes les actions."},
	{Operations, "Opérations", "Commandes, commandes IVI, livraisons, carte de la flotte, remboursements, avis."},
	{Network, "Réseau", "Boutiques, Ivia Business, livreurs et leurs réglages, immobilier."},
	{Health, "Santé", "Pharmacies, alertes et paiements santé, médicaments, réglages santé."},
	{Marketing, "Marketing", "Publicité, produits IVI, codes promo, avis."},
	{Finance, "Finances", "Paiements, remboursements, relevés des marchands, exports."},
	{Map, "Carte", "Lieux, zones et tarifs, coûts de la carte."},
	{Support, "Support client", "Consultation des commandes, comptes, boutiques, livreurs ; avis et signalements."},
}

// Valid indique si le code est un rôle admin connu.
func Valid(code string) bool {
	return slices.ContainsFunc(Roles, func(r Role) bool { return r.Code == code })
}

// Label donne le libellé d'un rôle.
func Label(code string) string {
	for _, r := range Roles {
		if r.Code == code {
			return r.Label
		}
	}
	return code
}

// common : sections ouvertes à tous les admins (tableau de bord, direct, profil admin).
var common = []string{"overview", "metrics", "stream", "me"}

// grants : sections de chaque rôle ; « GET:section » = consultation seulement.
var grants = map[string][]string{
	Operations: {
		"orders", "refund-queue", "platform-orders", "payments", "refunds", "deliveries", "delivery-alerts",
		"fleet", "driver-incidents", "GET:drivers", "GET:shops", "ratings", "app-feedback", "rating-scores",
	},
	Network: {
		"shops", "shop-categories", "business", "drivers", "driver-settings", "driver-incidents", "properties",
		"fleet", "categories", "neighborhoods", "ratings", "rating-scores",
	},
	Health: {
		"pharmacies", "pharmacy", "pharmacy-duty-shifts", "medicines", "medicine-alerts", "medicine-payments",
	},
	Marketing: {
		"promo", "products", "promo-codes", "coupon-settings", "categories", "GET:shops", "ratings",
		"app-feedback", "rating-scores",
	},
	Finance: {
		"payments", "refunds", "refund-queue", "settlements", "deliveries", "medicine-payments",
		"GET:orders", "GET:promo-codes", "GET:shops",
	},
	Map: {"places", "zones", "geo", "neighborhoods", "fleet"},
	Support: {
		"GET:orders", "GET:users", "GET:shops", "GET:drivers", "GET:pharmacies", "GET:refund-queue",
		"ratings", "app-feedback", "rating-scores", "driver-incidents",
	},
}

// Section extrait la section d'un chemin /v1/admin/<section>/... ("" hors back-office).
func Section(path string) string {
	rest, ok := strings.CutPrefix(path, "/v1/admin/")
	if !ok {
		return ""
	}
	section, _, _ := strings.Cut(rest, "/")
	return section
}

// Allowed dit si un rôle admin peut faire la requête (méthode, chemin).
func Allowed(role, method, path string) bool {
	if role == SuperAdmin {
		return true
	}
	s := Section(path)
	if s == "" || slices.Contains(common, s) {
		return true
	}
	for _, g := range grants[role] {
		if g == s || (method == "GET" && g == "GET:"+s) {
			return true
		}
	}
	return false
}

// Sections liste les sections d'un rôle (« * » pour le super admin), pour le menu du back-office.
func Sections(role string) []string {
	if role == SuperAdmin {
		return []string{"*"}
	}
	out := slices.Clone(common)
	for _, g := range grants[role] {
		out = append(out, strings.TrimPrefix(g, "GET:"))
	}
	return out
}
