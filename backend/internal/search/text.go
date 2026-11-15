package search

import (
	"strings"
	"unicode"
)

// maxQueryWords borne la requête plein texte construite à partir du texte de l'app.
const maxQueryWords = 8

// prefixQuery construit la requête « début de mot » de la recherche pendant la frappe : tous les
// mots, le dernier en préfixe (« robe pag » → « robe & pag:* »). Seuls les lettres et chiffres
// sont gardés, ce qui exclut toute syntaxe de to_tsquery venue de l'app ; les mots d'une lettre
// (« l' », « d' ») sont ignorés. nil : rien à chercher.
func prefixQuery(q string) *string {
	words := strings.FieldsFunc(q, func(r rune) bool { return !unicode.IsLetter(r) && !unicode.IsDigit(r) })
	kept := words[:0]
	for _, w := range words {
		if len([]rune(w)) > 1 || unicode.IsDigit([]rune(w)[0]) {
			kept = append(kept, strings.ToLower(w))
		}
	}
	if len(kept) == 0 {
		return nil
	}
	if len(kept) > maxQueryWords {
		kept = kept[len(kept)-maxQueryWords:]
	}
	out := strings.Join(kept, " & ") + ":*"
	return &out
}

var likeEscaper = strings.NewReplacer(`\`, `\`, `%`, `\%`, `_`, `\_`)

// likeText échappe les jokers de LIKE (ESCAPE '\') : le texte de l'app est cherché tel quel.
func likeText(q *string) *string {
	if q == nil {
		return nil
	}
	out := likeEscaper.Replace(*q)
	return &out
}
