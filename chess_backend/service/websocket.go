package service

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"

	"github.com/gorilla/websocket"
)

// Configuration du WebSocket upgrader
var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool {
		return true // À personnaliser selon vos besoins de sécurité
	},
}

// Créer un nouveau gestionnaire de connexions
func NewOnlineUsersManager(userStore *UserStore) *OnlineUsersManager {
	return &OnlineUsersManager{
		connections: make(map[string]*websocket.Conn),
		userStore:   userStore,
		roomManager: NewRoomManager(),
	}
}

// Gérer la connexion WebSocket
func (m *OnlineUsersManager) HandleConnection(w http.ResponseWriter, r *http.Request) {
	// Récupérer le nom d'utilisateur
	username := r.URL.Query().Get("username")
	if username == "" {
		http.Error(w, "Username is required", http.StatusBadRequest)
		return
	}

	// Vérifier si l'utilisateur existe
	_, err := m.userStore.GetUser(username)
	if err != nil {
		http.Error(w, "User not found", http.StatusUnauthorized)
		return
	}

	// Établir la connexion WebSocket
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Printf("WebSocket upgrade error: %v", err)
		return
	}

	// Ajouter la connexion
	m.mutex.Lock()
	m.connections[username] = conn
	m.mutex.Unlock()

	// Mettre à jour le statut en ligne
	m.userStore.UpdateUserOnlineStatus(username, true,false)

	// Notifier tous les clients de la nouvelle connexion
	m.broadcastOnlineUsers()

	// Gestion de la connexion
	go m.handleClientConnection(username, conn)
}

// Gérer les messages du client
func (m *OnlineUsersManager) handleClientConnection(username string, conn *websocket.Conn) {
	defer func() {
		// Nettoyer à la déconnexion
		m.mutex.Lock()
		delete(m.connections, username)
		m.mutex.Unlock()

		// Mettre à jour le statut hors ligne
		m.userStore.UpdateUserOnlineStatus(username, false,false)

		// Notifier les autres clients
		m.broadcastOnlineUsers()

		conn.Close()
	}()

	for {
		var message WebSocketMessage
		err := conn.ReadJSON(&message)
		if err != nil {
			log.Printf("WebSocket read error for %s: %v", username, err)
			break
		}

		switch message.Type {
		case "request_online_users":
			// Explicitly send online users to the requesting client
			onlineUsers := m.getCurrentOnlineUsers()
			conn.WriteJSON(WebSocketMessage{
				Type:    "online_users",
				Content: string(mustJson(onlineUsers)),
			})
		case "invitation_send", "invitation_accept", "invitation_reject", "invitation_cancel", "room_leave":
			var invitation InvitationMessage
			if err := json.Unmarshal([]byte(message.Content), &invitation); err != nil {
				log.Printf("Error parsing invitation: %v", err)
				continue
			}

			if err := m.handleInvitation(invitation); err != nil {
				log.Printf("Failed to process invitation: %v", err)
			}
		

		default:
			log.Printf("Unhandled message type: %s", message.Type)
		}
	}
}

func (m *OnlineUsersManager) handleInvitation(invitation InvitationMessage) error {
	m.mutex.RLock()
	_, fromExists := m.connections[invitation.FromUsername]
	toConn, toExists := m.connections[invitation.ToUsername]
	m.mutex.RUnlock()

	if invitation.Type == RoomLeave && !fromExists {
        log.Printf("Cannot process room leave: user %s not online", invitation.FromUsername)
        return fmt.Errorf("user not online")
    }

	if !toExists {
		return fmt.Errorf("user not online")
	}

	switch invitation.Type {
	case InvitationSend:

		// Mettre à jour le statut de la room pour les joueurs
		m.userStore.UpdateUserRoomStatus(invitation.FromUsername, true)
		m.userStore.UpdateUserRoomStatus(invitation.ToUsername, false)

		// Generate room ID if not provided
		if invitation.RoomID == "" {
			invitation.RoomID = GenerateUniqueID()
		}

		// Create the room
		m.roomManager.CreateRoom(invitation)

		// Send invitation to the recipient
		err := toConn.WriteJSON(WebSocketMessage{
			Type:    "invitation",
			Content: string(mustJson(invitation)),
		})
		if err != nil {
			log.Printf("Error sending invitation: %v", err)
			return err
		}

	case InvitationAccept:
		// Les deux joueurs sont maintenant dans la room
		m.userStore.UpdateUserRoomStatus(invitation.FromUsername, true)
		m.userStore.UpdateUserRoomStatus(invitation.ToUsername, true)

		// Retrieve the room
		room, exists := m.roomManager.GetRoom(invitation.RoomID)
		if !exists {
			return fmt.Errorf("room not found")
		}

		// Update room status
		room.Status = RoomStatusInGame

		// Initialiser l'état du jeu de base
		room.PositionFEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1" // Position standard des échecs
		room.IsWhitesTurn = true
		room.IsGameOver = false
		room.BoardState = ""
		room.WhitesTime = "60" // 1h par défaut
		room.BlacksTime = "60"
		room.Moves = []Move{} // Liste des mouvements vide au début
		room.GameCreatorUID = invitation.FromUsername
		room.WinnerID = ""
		room.WhitesCurrentMove = ""
		room.BlacksCurrentMove = ""

		// Broadcast to both players that the game is starting
		fromConn, fromExists := m.connections[invitation.FromUsername]
		toConn, toExists := m.connections[invitation.ToUsername]

		if fromExists && toExists {
			startMessage := WebSocketMessage{
				Type: "game_start",
				Content: string(mustJson(map[string]interface{}{
					"gameId":            invitation.RoomID,
					"gameCreatorUid":    invitation.FromUserID,
					"userId":            invitation.ToUserID,
					"opponentUsername": invitation.ToUsername,
					"positonFen":        room.PositionFEN,
					"winnerId":          "", 
					"whitesTime":        room.WhitesTime,
					"blacksTime":        room.BlacksTime,
					"whitsCurrentMove":  "", 
					"blacksCurrentMove": "", 
					"boardState":        room.BoardState,
					"playState":         string(room.Status),
					"isWhitesTurn":      room.IsWhitesTurn,
					"isGameOver":        room.IsGameOver,
					"squareState":       room.SquareState,
					"moves":             room.Moves,
				})),
			}

			fromConn.WriteJSON(startMessage)
			toConn.WriteJSON(startMessage)
		}

	case InvitationReject:
		// Sortir de la room
		m.userStore.UpdateUserRoomStatus(invitation.FromUsername, false)
		m.userStore.UpdateUserRoomStatus(invitation.ToUsername, false)
		// Remove the room
		m.roomManager.RemoveRoom(invitation.RoomID)
		// Notifier l'expéditeur du rejet
		fromConn, fromExists := m.connections[invitation.ToUsername]
		if fromExists {
			rejectionMessage := WebSocketMessage{
				Type:    "invitation_rejected",
				Content: string(mustJson(invitation)),
			}
			fromConn.WriteJSON(rejectionMessage)
		}
	case InvitationCancel:
		// Sortir de la room
		m.userStore.UpdateUserRoomStatus(invitation.FromUsername, false)
		m.userStore.UpdateUserRoomStatus(invitation.ToUsername, false)

		m.roomManager.RemoveRoom(invitation.RoomID)

		// Notifier le destinataire de l'annulation
		toConn, toExists := m.connections[invitation.ToUsername]
		if toExists {
			cancellationMessage := WebSocketMessage{
				Type:    "invitation_cancel",
				Content: string(mustJson(invitation)),
			}
			toConn.WriteJSON(cancellationMessage)
		}

	case RoomLeave:
		log.Printf("RoomLeave: Samba...",)
		// Sortir de la room
		m.userStore.UpdateUserRoomStatus(invitation.FromUsername, false)
		m.userStore.UpdateUserRoomStatus(invitation.ToUsername, false)
		// Handle room leaving
		_, exists := m.roomManager.GetRoom(invitation.RoomID)
		if !exists {
			return fmt.Errorf("room not found")
		}

		// Remove the room
		m.roomManager.RemoveRoom(invitation.RoomID)

		// Notify the other player
		m.notifyRoomClosure(invitation)
	}

	return nil
}

func (us *UserStore) UpdateUserRoomStatus(username string, isInRoom bool) error {
	us.mutex.Lock()
	defer us.mutex.Unlock()

	user, exists := us.Users[username]
	if !exists {
		return fmt.Errorf("user not found")
	}

	user.IsInRoom = isInRoom
	us.Users[username] = user

	return us.Save()
}

// Notify other player when room is closed
func (m *OnlineUsersManager) notifyRoomClosure(invitation InvitationMessage) {

    conn, exists := m.connections[invitation.ToUsername]
    if exists {
        closureMessage := WebSocketMessage{
            Type: "room_closed",
            Content: string(mustJson(map[string]string{
                "room_id":  invitation.RoomID,
                "fromUsername": invitation.FromUsername, 
            })),
        }
        conn.WriteJSON(closureMessage)
    }
}

func (m *OnlineUsersManager) broadcastOnlineUsers() {
	m.mutex.RLock()
	defer m.mutex.RUnlock()

	// Prepare the list of online users
	onlineUsers := make([]OnlineUser, 0, len(m.connections))
	for username := range m.connections {
		user, err := m.userStore.GetUser(username)
		if err == nil {
			onlineUsers = append(onlineUsers, OnlineUser{
				ID:       user.ID,
				Username: user.UserName,
				IsInRoom: user.IsInRoom,
			})
		}
	}

	// Prepare the message
	message := WebSocketMessage{
		Type:    "online_users",
		Content: string(mustJson(onlineUsers)),
	}

	// Send to all connected clients
	for _, conn := range m.connections {
		err := conn.WriteJSON(message)
		if err != nil {
			log.Printf("Error broadcasting to client: %v", err)
		}
	}

	// Log for debugging
	log.Printf("Broadcasting %d online users", len(onlineUsers))
	log.Printf("Online users: %+v", onlineUsers)
}

func (m *OnlineUsersManager) getCurrentOnlineUsers() []OnlineUser {
	m.mutex.RLock()
	defer m.mutex.RUnlock()

	onlineUsers := make([]OnlineUser, 0, len(m.connections))
	for username := range m.connections {
		user, err := m.userStore.GetUser(username)
		if err == nil {
			onlineUsers = append(onlineUsers, OnlineUser{
				ID:       user.ID,
				Username: user.UserName,
				IsInRoom: user.IsInRoom,
			})
		}
	}
	return onlineUsers
}

// Utilitaire pour convertir en JSON sans erreur
func mustJson(v interface{}) []byte {
	data, _ := json.Marshal(v)
	return data
}
