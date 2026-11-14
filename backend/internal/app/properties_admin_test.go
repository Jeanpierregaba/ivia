package app_test

import (
	"bytes"
	"net/http"
	"testing"
)

// uploadPropertyPhoto envoie une photo d'annonce par URL signée, comme le back-office.
func uploadPropertyPhoto(t *testing.T, token string) string {
	t.Helper()
	content := []byte("\xff\xd8\xff photo de test")
	up := mustStatus(t, call(t, token, "POST", "/v1/uploads", map[string]any{
		"purpose": "property_photo", "content_type": "image/jpeg", "size_bytes": len(content),
	}), http.StatusCreated)
	signed := up.Body["upload"].(map[string]any)
	req, _ := http.NewRequest(http.MethodPut, signed["url"].(string), bytes.NewReader(content))
	req.Header.Set("Content-Type", "image/jpeg")
	res, err := http.DefaultClient.Do(req)
	if err != nil || res.StatusCode != http.StatusOK {
		t.Fatalf("envoi de la photo : %v %v", err, res)
	}
	res.Body.Close()
	return up.str("object_key")
}

func TestAdminManagesProperties(t *testing.T) {
	ad := admin(t)
	buyer := login(t, uniqueEmail("immo"))
	key := uploadPropertyPhoto(t, ad)
	input := map[string]any{
		"title": "Villa " + uniquePhone(), "kind": "sale", "property_type": "villa", "price_xof": 45000000,
		"bedrooms": 3, "surface_m2": 300, "neighborhood": "Tokoin", "address_text": "Tokoin Wuiti",
		"lat": 6.15, "lng": 1.21, "description": "Belle villa.", "photo_keys": []string{key},
		"contact_name": "Agence", "contact_phone": "+22890000300", "is_active": true,
	}

	// Réservé aux admins, y compris l'envoi des photos.
	if r := call(t, buyer, "POST", "/v1/admin/properties", input); r.Status != http.StatusForbidden {
		t.Fatalf("création par un client : %d", r.Status)
	}
	if r := call(t, buyer, "POST", "/v1/uploads", map[string]any{"purpose": "property_photo", "content_type": "image/jpeg", "size_bytes": 10}); r.Status != http.StatusForbidden {
		t.Fatalf("envoi par un client : %d", r.Status)
	}

	// Coordonnées inversées et photo jamais reçue : refusées.
	bad := map[string]any{}
	for k, v := range input {
		bad[k] = v
	}
	bad["lat"], bad["lng"] = 1.21, 6.15
	if r := call(t, ad, "POST", "/v1/admin/properties", bad); r.code() != "validation_failed" {
		t.Fatalf("coordonnées inversées : %d %s", r.Status, r.code())
	}
	bad["lat"], bad["lng"] = 6.15, 1.21
	bad["photo_keys"] = []string{"properties/inconnu/photo.jpg"}
	if r := call(t, ad, "POST", "/v1/admin/properties", bad); r.code() != "validation_failed" {
		t.Fatalf("photo inconnue : %d %s", r.Status, r.code())
	}

	// Publiée : visible du public.
	created := mustStatus(t, call(t, ad, "POST", "/v1/admin/properties", input), http.StatusCreated)
	id := created.str("id")
	mustStatus(t, call(t, "", "GET", "/v1/properties/"+id, nil), http.StatusOK)

	// Même titre dans le même quartier : conflit.
	if r := call(t, ad, "POST", "/v1/admin/properties", input); r.Status != http.StatusConflict {
		t.Fatalf("doublon : %d", r.Status)
	}

	// Modification : la photo déjà présente reste permise.
	input["price_xof"] = 40000000
	updated := mustStatus(t, call(t, ad, "PUT", "/v1/admin/properties/"+id, input), http.StatusOK)
	if updated.Body["price_xof"].(float64) != 40000000 {
		t.Fatalf("prix après modification : %v", updated.Body["price_xof"])
	}

	// Retrait : motif obligatoire, puis invisible du public mais toujours au back-office.
	if r := call(t, ad, "PUT", "/v1/admin/properties/"+id+"/active", map[string]any{"is_active": false}); r.Status == http.StatusOK {
		t.Fatal("retrait sans motif accepté")
	}
	mustStatus(t, call(t, ad, "PUT", "/v1/admin/properties/"+id+"/active", map[string]any{"is_active": false, "reason": "Bien vendu"}), http.StatusOK)
	if r := call(t, "", "GET", "/v1/properties/"+id, nil); r.Status != http.StatusNotFound {
		t.Fatalf("annonce retirée, vue publique : %d", r.Status)
	}
	got := mustStatus(t, call(t, ad, "GET", "/v1/admin/properties/"+id, nil), http.StatusOK)
	if got.Body["is_active"].(bool) {
		t.Fatal("annonce toujours active au back-office")
	}

	// Republiée : de nouveau visible.
	mustStatus(t, call(t, ad, "PUT", "/v1/admin/properties/"+id+"/active", map[string]any{"is_active": true}), http.StatusOK)
	mustStatus(t, call(t, "", "GET", "/v1/properties/"+id, nil), http.StatusOK)
}
