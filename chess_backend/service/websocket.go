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
	m.userStore.UpdateUserOnlineStatus(username, true)

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
		m.userStore.UpdateUserOnlineStatus(username, false)

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
		case "invitation_send", "invitation_accept", "invitation_reject", "invitation_cancel":
			var invitation InvitationMessage
			if err := json.Unmarshal([]byte(message.Content), &invitation); err != nil {
				log.Printf("Error parsing invitation: %v", err)
				continue
			}

			// Additional security check
			if invitation.FromUsername != username {
				log.Printf("Unauthorized invitation attempt by %s", username)
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

// Modify handleInvitation to create and manage rooms
func (m *OnlineUsersManager) handleInvitation(invitation InvitationMessage) error {
	m.mutex.RLock()
	toConn, exists := m.connections[invitation.ToUsername]
	m.mutex.RUnlock()

	if !exists {
		return fmt.Errorf("user not online")
	}

	switch invitation.Type {
	case InvitationSend:
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
		// Retrieve the room
		room, exists := m.roomManager.GetRoom(invitation.RoomID)
		if !exists {
			return fmt.Errorf("room not found")
		}

		// Update room status
		room.Status = RoomStatusInGame

		// Broadcast to both players that the game is starting
		fromConn, fromExists := m.connections[invitation.FromUsername]
		toConn, toExists := m.connections[invitation.ToUsername]

		if fromExists && toExists {
			startMessage := WebSocketMessage{
				Type: "game_start",
				Content: string(mustJson(map[string]string{
					"room_id":      invitation.RoomID,
					"white_player": invitation.FromUsername,
					"black_player": invitation.ToUsername,
				})),
			}

			fromConn.WriteJSON(startMessage)
			toConn.WriteJSON(startMessage)
		}

	case InvitationReject:
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

// Notify other player when room is closed
func (m *OnlineUsersManager) notifyRoomClosure(invitation InvitationMessage) {
	var otherUsername string
	if invitation.FromUsername == invitation.ToUsername {
		return
	}
	if invitation.FromUsername == invitation.ToUsername {
		otherUsername = invitation.FromUsername
	} else {
		otherUsername = invitation.ToUsername
	}

	conn, exists := m.connections[otherUsername]
	if exists {
		closureMessage := WebSocketMessage{
			Type: "room_closed",
			Content: string(mustJson(map[string]string{
				"room_id": invitation.RoomID,
				"reason":  "player_left",
			})),
		}
		conn.WriteJSON(closureMessage)
	}
}

// exclude players in active rooms
func (m *OnlineUsersManager) broadcastOnlineUsers() {
	m.mutex.RLock()
	defer m.mutex.RUnlock()

	// Prepare the list of online users
	onlineUsers := make([]OnlineUser, 0, len(m.connections))
	for username := range m.connections {
		// Check if user is in an active room
		inActiveRoom := false
		for _, room := range m.roomManager.rooms {
			if room.WhitePlayer.Username == username ||
				room.BlackPlayer.Username == username {
				inActiveRoom = true
				break
			}
		}

		// Only add user if not in an active room
		if !inActiveRoom {
			user, err := m.userStore.GetUser(username)
			if err == nil {
				onlineUsers = append(onlineUsers, OnlineUser{
					ID:       user.ID,
					Username: user.UserName,
				})
			}
		}
	}

	// Prepare the message
	message := WebSocketMessage{
		Type:    "online_users",
		Content: string(mustJson(onlineUsers)),
	}

	// Send to all connected clients
	for _, conn := range m.connections {
		conn.WriteJSON(message)
	}
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
