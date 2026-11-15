// Package api embarque le contrat OpenAPI dans le binaire (documentation interactive /docs).
package api

import _ "embed"

// OpenAPI est le contenu de openapi.yaml.
//
//go:embed openapi.yaml
var OpenAPI []byte
