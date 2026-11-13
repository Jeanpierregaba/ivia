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
	return websocket.Accept(w, r, &websocket.AcceptOptions{Subprotocols: []string{WSProtocol}})
}
