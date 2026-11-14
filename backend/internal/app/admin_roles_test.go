package app_test

import (
	"net/http"
	"testing"
)

// Spec 039 : comptes admin à rôles. Le super admin crée les comptes admin (adresse dédiée), chaque
// rôle n'accède qu'à ses sections, et le super admin voit les actions de tous.
func TestAdminRoles(t *testing.T) {
	requireApp(t)
	super := admin(t)
	me := mustStatus(t, call(t, super, "GET", "/v1/admin/me", nil), http.StatusOK)
	if me.str("role") != "super_admin" {
		t.Fatalf("premier admin : %s", me.Raw)
	}

	// Un compte client (ou marchand, livreur) ne devient jamais admin.
	b := newBuyer(t, 6.2, 1.2)
	buyerMe := mustStatus(t, call(t, b.token, "GET", "/v1/me", nil), http.StatusOK)
	if r := call(t, super, "POST", "/v1/admin/admins", map[string]any{
		"email": buyerMe.str("email"), "first_name": "Kossi", "last_name": "Client", "role": "operations",
	}); r.code() != "email_in_use" {
		t.Fatalf("compte client rendu admin : %d %s", r.Status, r.Raw)
	}
	if r := call(t, super, "POST", "/v1/admin/users/"+buyerMe.str("id")+"/grant-admin", map[string]any{"reason": "x"}); r.Status != http.StatusNotFound && r.Status != http.StatusMethodNotAllowed {
		t.Fatalf("ancienne route grant-admin encore là : %d", r.Status)
	}

	// Compte « Opérations » : ses sections seulement.
	email := uniqueEmail("ops")
	a := mustStatus(t, call(t, super, "POST", "/v1/admin/admins", map[string]any{
		"email": email, "first_name": "Ama", "last_name": "Opérations", "role": "operations",
	}), http.StatusCreated)
	if a.str("role") != "operations" || a.str("role_label") != "Opérations" {
		t.Fatalf("compte créé : %s", a.Raw)
	}
	ops := login(t, email)
	verifyMFA(t, ops, email)
	opsMe := mustStatus(t, call(t, ops, "GET", "/v1/admin/me", nil), http.StatusOK)
	if opsMe.str("role") != "operations" {
		t.Fatalf("rôle vu par l'admin : %s", opsMe.Raw)
	}
	mustStatus(t, call(t, ops, "GET", "/v1/admin/orders", nil), http.StatusOK)
	mustStatus(t, call(t, ops, "GET", "/v1/admin/overview", nil), http.StatusOK)
	for _, path := range []string{"/v1/admin/settings", "/v1/admin/pharmacies", "/v1/admin/admins", "/v1/admin/audit-log"} {
		if r := call(t, ops, "GET", path, nil); r.code() != "admin_scope" {
			t.Fatalf("%s pour Opérations : %d %s", path, r.Status, r.Raw)
		}
	}
	if r := call(t, ops, "POST", "/v1/admin/admins", map[string]any{
		"email": uniqueEmail("x"), "first_name": "X", "last_name": "Y", "role": "super_admin",
	}); r.Status != http.StatusForbidden {
		t.Fatalf("un admin Opérations crée un admin : %d", r.Status)
	}

	// Changement de rôle, protections, retrait ; tout est au journal du super admin.
	id := a.str("id")
	mustStatus(t, call(t, super, "PUT", "/v1/admin/admins/"+id+"/role", map[string]any{"role": "health"}), http.StatusOK)
	mustStatus(t, call(t, ops, "GET", "/v1/admin/pharmacies", nil), http.StatusOK)
	superID := mustStatus(t, call(t, super, "GET", "/v1/me", nil), http.StatusOK).str("id")
	if r := call(t, super, "PUT", "/v1/admin/admins/"+superID+"/role", map[string]any{"role": "support"}); r.code() != "cannot_change_self" {
		t.Fatalf("changer son propre rôle : %s", r.Raw)
	}
	if r := call(t, super, "POST", "/v1/admin/admins", map[string]any{
		"email": email, "first_name": "Ama", "last_name": "Bis", "role": "map",
	}); r.code() != "admin_exists" {
		t.Fatalf("admin en double : %s", r.Raw)
	}
	logs := mustStatus(t, call(t, super, "GET", "/v1/admin/audit-log?target_id="+id, nil), http.StatusOK)
	if n := len(logs.Body["items"].([]any)); n < 2 {
		t.Fatalf("journal des comptes admin : %s", logs.Raw)
	}
	mustStatus(t, call(t, super, "DELETE", "/v1/admin/admins/"+id, nil), http.StatusNoContent)
	if r := call(t, ops, "GET", "/v1/admin/overview", nil); r.Status != http.StatusForbidden {
		t.Fatalf("accès après retrait : %d", r.Status)
	}
}
