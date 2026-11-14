// Package docs sert la documentation interactive de l'API (Swagger UI) et le contrat OpenAPI.
// Désactivée en production.
package docs

import (
	"net/http"

	"ivia/backend/api"
)

// Routes de la documentation (exclues de la vérification du contrat : elles le servent).
const (
	PageRoute = "GET /docs"
	SpecRoute = "GET /openapi.yaml"
)

const page = `<!doctype html>
<html lang="fr">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>API ivia — documentation</title>
  <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/swagger-ui-dist@5.17.14/swagger-ui.css">
  <style>body{margin:0} .topbar{display:none}</style>
</head>
<body>
  <div id="swagger-ui"></div>
  <script src="https://cdn.jsdelivr.net/npm/swagger-ui-dist@5.17.14/swagger-ui-bundle.js"></script>
  <script>
    window.ui = SwaggerUIBundle({
      url: "/openapi.yaml",
      dom_id: "#swagger-ui",
      deepLinking: true,
      persistAuthorization: true,
      displayRequestDuration: true,
      tryItOutEnabled: true,
      filter: true,
      docExpansion: "none",
      defaultModelsExpandDepth: 0,
      operationsSorter: "alpha",
      tagsSorter: "alpha",
    });
  </script>
</body>
</html>`

// Page sert Swagger UI.
func Page(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	_, _ = w.Write([]byte(page))
}

// Spec sert le contrat OpenAPI.
func Spec(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "application/yaml; charset=utf-8")
	_, _ = w.Write(api.OpenAPI)
}
