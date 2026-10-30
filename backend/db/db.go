// Package db embarque les migrations SQL dans le binaire.
package db

import "embed"

// Migrations contient les fichiers goose de migrations/.
//
//go:embed migrations/*.sql
var Migrations embed.FS
