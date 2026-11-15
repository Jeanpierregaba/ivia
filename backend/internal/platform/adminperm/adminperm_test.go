package adminperm

import "testing"

func TestAllowed(t *testing.T) {
	cases := []struct {
		role, method, path string
		want               bool
	}{
		{SuperAdmin, "PATCH", "/v1/admin/settings", true},
		{Operations, "GET", "/v1/admin/orders/123", true},
		{Operations, "POST", "/v1/admin/orders/123/cancel", true},
		{Operations, "GET", "/v1/admin/settings", false},
		{Operations, "GET", "/v1/admin/pharmacies", false},
		{Operations, "GET", "/v1/admin/drivers", true},
		{Operations, "POST", "/v1/admin/drivers/1/approve", false},
		{Health, "GET", "/v1/admin/medicine-alerts", true},
		{Health, "GET", "/v1/admin/overview", true},
		{Support, "POST", "/v1/admin/users/1/mfa/reset", false},
		{Marketing, "GET", "/v1/admin/admins", false},
		{"", "GET", "/v1/admin/orders", false},
		{"", "GET", "/v1/me", true},
	}
	for _, c := range cases {
		if got := Allowed(c.role, c.method, c.path); got != c.want {
			t.Errorf("%s %s %s : %v, attendu %v", c.role, c.method, c.path, got, c.want)
		}
	}
}

func TestRolesValid(t *testing.T) {
	for _, r := range Roles {
		if !Valid(r.Code) || Label(r.Code) == r.Code {
			t.Errorf("rôle %s", r.Code)
		}
	}
	if Valid("admin") {
		t.Fatal("rôle inconnu accepté")
	}
}
