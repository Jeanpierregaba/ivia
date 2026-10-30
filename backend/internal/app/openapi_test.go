package app_test

import (
	"bufio"
	"os"
	"regexp"
	"strings"
	"testing"

	"ivia/backend/internal/platform/docs"
)

// Le contrat OpenAPI doit décrire chaque route enregistrée, et seulement celles-là.
func TestOpenAPICoversAllRoutes(t *testing.T) {
	a := requireApp(t)
	f, err := os.Open("../../api/openapi.yaml")
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()

	pathRe := regexp.MustCompile(`^  "?(/[^":]*)"?:$`)
	methodRe := regexp.MustCompile(`^    (get|post|put|patch|delete):$`)
	documented := map[string]bool{}
	var current string
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		line := sc.Text()
		if m := pathRe.FindStringSubmatch(line); m != nil {
			current = m[1]
		} else if m := methodRe.FindStringSubmatch(line); m != nil && current != "" {
			documented[strings.ToUpper(m[1])+" "+current] = true
		}
	}

	registered := map[string]bool{"GET /health": true, "GET /ready": true}
	for _, p := range a.Routes {
		if p == docs.PageRoute || p == docs.SpecRoute {
			continue // la documentation sert le contrat, elle n'en fait pas partie
		}
		if strings.Contains(p, " ") { // les routes sans méthode (/dev/storage/) servent des fichiers
			registered[p] = true
		}
	}
	for r := range registered {
		if !documented[r] {
			t.Errorf("route absente de api/openapi.yaml : %s", r)
		}
	}
	for d := range documented {
		if !registered[d] {
			t.Errorf("route décrite dans api/openapi.yaml mais absente du code : %s", d)
		}
	}
}
