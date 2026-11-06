package main

import (
	"context"
	"encoding/csv"
	"errors"
	"fmt"
	"io"
	"os"
	"strconv"
	"strings"

	"ivia/backend/internal/app"
	"ivia/backend/internal/mapping"
)

// importPlaces charge le CSV de tools/geo/osm_pois.py (relançable : pas de doublon).
func importPlaces(ctx context.Context, a *app.App, path string) error {
	f, err := os.Open(path)
	if err != nil {
		return fmt.Errorf("lecture du fichier : %w", err)
	}
	defer f.Close()
	r := csv.NewReader(f)
	head, err := r.Read()
	if err != nil {
		return fmt.Errorf("en-tête du fichier : %w", err)
	}
	col := map[string]int{}
	for i, h := range head {
		col[h] = i
	}
	for _, need := range []string{"external_id", "name", "category", "lat", "lng", "address", "aliases"} {
		if _, ok := col[need]; !ok {
			return errors.New("colonne manquante : " + need)
		}
	}
	done, skipped := 0, 0
	for {
		row, err := r.Read()
		if errors.Is(err, io.EOF) {
			break
		}
		if err != nil {
			return fmt.Errorf("ligne illisible : %w", err)
		}
		lat, errLat := strconv.ParseFloat(row[col["lat"]], 64)
		lng, errLng := strconv.ParseFloat(row[col["lng"]], 64)
		if errLat != nil || errLng != nil {
			skipped++
			continue
		}
		aliases := []string{}
		if v := row[col["aliases"]]; v != "" {
			aliases = strings.Split(v, ";")
		}
		err = a.Mapping.ImportPlace(ctx, "osm", row[col["external_id"]], mapping.PlaceInput{
			Name: row[col["name"]], Category: row[col["category"]], Address: row[col["address"]], Aliases: aliases,
			Location: mapping.LatLng{Lat: lat, Lng: lng}, IsActive: true,
		})
		if err != nil {
			skipped++
			continue
		}
		done++
	}
	fmt.Printf("%d lieux importés, %d ignorés\n", done, skipped)
	return nil
}
