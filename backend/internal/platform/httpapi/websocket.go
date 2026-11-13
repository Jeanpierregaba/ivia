package httpapi

import (
	"net/http"
	"time"

	"github.com/coder/websocket"
)

// AcceptWebSocket ouvre une connexion WebSocket : sans délai d'écriture ni de lecture du serveur
// (connexion longue), avec le sous-protocole du jeton quand le navigateur l'a proposé.
func AcceptWebSocket(w http.ResponseWriter, r *http.Request) (*websocket.Conn, error) {
	rc := http.NewResponseController(w)
	_ = rc.SetWriteDeadline(time.Time{})
	_ = rc.SetReadDeadline(time.Time{})
	// Origine non vérifiée : l'authentification passe par le jeton (en-tête ou sous-protocole),
	// jamais par un cookie ; une autre page ne peut donc pas détourner la connexion. Les apps web
	// sont servies sur une autre origine que l'API.
	return websocket.Accept(w, r, &websocket.AcceptOptions{Subprotocols: []string{WSProtocol}, InsecureSkipVerify: true})
}
