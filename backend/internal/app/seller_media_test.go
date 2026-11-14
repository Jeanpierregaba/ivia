package app_test

import (
	"net/http"
	"testing"
)

// Bibliothèque de photos et filtre par catégorie du catalogue du marchand (refonte Ivia Business).
func TestSellerMediaLibraryAndCategoryFilter(t *testing.T) {
	requireApp(t)
	s := newSeller(t, 3)

	key := uploadImage(t, s.token, "product_image")
	first := mustStatus(t, call(t, s.token, "POST", "/v1/seller/shops/"+s.shopID+"/products", map[string]any{
		"category_id": category(t), "name": "Ventilateur", "price_xof": 22000, "parcel_size": "medium",
		"stock_mode": "untracked", "image_keys": []string{key},
	}), http.StatusCreated)

	lib := mustStatus(t, call(t, s.token, "GET", "/v1/seller/shops/"+s.shopID+"/media", nil), http.StatusOK)
	items, _ := lib.Body["items"].([]any)
	if len(items) != 1 || items[0].(map[string]any)["object_key"] != key || items[0].(map[string]any)["url"] == "" {
		t.Fatalf("bibliothèque : %s", lib.Raw)
	}

	// La photo de la bibliothèque se réutilise dans un autre produit.
	mustStatus(t, call(t, s.token, "POST", "/v1/seller/shops/"+s.shopID+"/products", map[string]any{
		"category_id": category(t), "name": "Ventilateur noir", "price_xof": 23000, "parcel_size": "medium",
		"stock_mode": "untracked", "image_keys": []string{key},
	}), http.StatusCreated)
	lib = mustStatus(t, call(t, s.token, "GET", "/v1/seller/shops/"+s.shopID+"/media", nil), http.StatusOK)
	if items, _ := lib.Body["items"].([]any); len(items) != 1 {
		t.Fatalf("une photo partagée apparaît une seule fois : %s", lib.Raw)
	}

	// Boutique d'autrui : 404.
	other := newSeller(t, 1)
	mustStatus(t, call(t, other.token, "GET", "/v1/seller/shops/"+s.shopID+"/media", nil), http.StatusNotFound)
	// La photo d'autrui ne se reprend pas.
	mustStatus(t, call(t, other.token, "POST", "/v1/seller/shops/"+other.shopID+"/products", map[string]any{
		"category_id": category(t), "name": "Copie", "price_xof": 1000, "parcel_size": "small",
		"stock_mode": "untracked", "image_keys": []string{key},
	}), http.StatusBadRequest)

	// Filtre par catégorie : la catégorie des produits, puis une autre (vide).
	cat := first.str("category_id")
	r := mustStatus(t, call(t, s.token, "GET", "/v1/seller/shops/"+s.shopID+"/products?category_id="+cat, nil), http.StatusOK)
	if items, _ := r.Body["items"].([]any); len(items) != 5 {
		t.Fatalf("filtre catégorie : %d produits, %s", len(items), r.Raw)
	}
	empty := mustStatus(t, call(t, admin(t), "POST", "/v1/admin/categories", map[string]any{"name": "Vide " + uniquePhone()}), http.StatusCreated)
	r = mustStatus(t, call(t, s.token, "GET", "/v1/seller/shops/"+s.shopID+"/products?category_id="+empty.str("id"), nil), http.StatusOK)
	if items, _ := r.Body["items"].([]any); len(items) != 0 {
		t.Fatalf("autre catégorie : %s", r.Raw)
	}
	mustStatus(t, call(t, s.token, "GET", "/v1/seller/shops/"+s.shopID+"/products?category_id=abc", nil), http.StatusBadRequest)
}
