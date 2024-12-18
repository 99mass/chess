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
	m.userStore.UpdateUserOnlineStatus(username, true, false)

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
		m.userStore.UpdateUserOnlineStatus(username, false, false)

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
			m.broadcastOnlineUsers()
		case "leave_room":
			var leaveRequest struct {
				Username string `json:"username"`
			}
			if err := json.Unmarshal([]byte(message.Content), &leaveRequest); err != nil {
				log.Printf("Error parsing leave room request: %v", err)
				continue
			}

			_, err := m.RemoveUserFromRoom(leaveRequest.Username)
			if err != nil {
				log.Printf("Error removing user from room: %v", err)
				continue
			}

			// Notify all clients about updated online users
			m.broadcastOnlineUsers()

		default:
			log.Printf("Unhandled message type: %s", message.Type)
			m.broadcastOnlineUsers()
		}
	}
}

func (m *OnlineUsersManager) handleInvitation(invitation InvitationMessage) error {
	log.Printf("🚀 Handling Invitation")
    log.Printf("   From: %s", invitation.FromUsername)
    log.Printf("   To: %s", invitation.ToUsername)

	m.mutex.RLock()
	_, fromExists := m.connections[invitation.FromUsername]
	toConn, toExists := m.connections[invitation.ToUsername]
	m.mutex.RUnlock()

	log.Printf("🔌 Connection Status:")
    log.Printf("   From User Connected: %v", fromExists)
    log.Printf("   To User Connected: %v", toExists)

	if invitation.Type == RoomLeave && !fromExists {
		log.Printf("Cannot process room leave: user %s not online", invitation.FromUsername)
		return fmt.Errorf("user not online")
	}

	if invitation.Type != RoomLeave && (!fromExists || !toExists) {
		log.Printf("Invitation error: User not online. From: %v, To: %v", fromExists, toExists)
		return fmt.Errorf("one or both users not online")
	}

	switch invitation.Type {
	case InvitationSend:

		// Envoyer l'invitation au destinataire
		toConn, exists := m.connections[invitation.ToUsername]
		if exists {
			err := toConn.WriteJSON(WebSocketMessage{
				Type:    "invitation",
				Content: string(mustJson(invitation)),
			})
			if err != nil {
				log.Printf("❌ Error Sending Invitation: %v", err)
				return err
			}
			log.Printf("✅ Invitation Sent Successfully to %s", invitation.ToUsername)
		} else {
			log.Printf("❌ Recipient %s not connected", invitation.ToUsername)
		}

	case InvitationAccept:

		// Générer un ID de room
		if invitation.RoomID == "" {
			invitation.RoomID = GenerateUniqueID()
		}

		m.roomManager.CreateRoom(invitation)

		// Retrouver la room
		room, exists := m.roomManager.GetRoom(invitation.RoomID)
		if !exists {
			return fmt.Errorf("room not found")
		}

		// Mettre à jour le statut des joueurs
		m.userStore.UpdateUserRoomStatus(invitation.FromUsername, true)
		m.userStore.UpdateUserRoomStatus(invitation.ToUsername, true)

		// Update room status
		room.Status = RoomStatusInGame

		// Initialiser l'état du jeu de base
		room.PositionFEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
		room.IsWhitesTurn = true
		room.IsGameOver = false
		room.WhitesTime = "60"
		room.BlacksTime = "60"

		startMessage := WebSocketMessage{
			Type: "game_start",
			Content: string(mustJson(map[string]interface{}{
				"gameId":            invitation.RoomID,
				"gameCreatorUid":    room.GameCreatorUID,
				"userId":            invitation.ToUserID,
				"opponentUsername":  invitation.ToUsername,
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

		// Envoyer le message de démarrage aux deux joueurs
		fromConn, fromExists := m.connections[invitation.FromUsername]
		toConn, toExists := m.connections[invitation.ToUsername]

		if fromExists {
			err := fromConn.WriteJSON(startMessage)
			if err != nil {
				log.Printf("Error sending game start to from user: %v", err)
			}
		}

		if toExists {
			err := toConn.WriteJSON(startMessage)
			if err != nil {
				log.Printf("Error sending game start to to user: %v", err)
			}
		}
	case InvitationReject:
		log.Printf("Invitation Reject - FromUsername: %s, ToUsername: %s",
			invitation.FromUsername,
			invitation.ToUsername)

		// Vérifier les connexions
		fromConn, fromExists := m.connections[invitation.ToUsername]
		_, toExists := m.connections[invitation.FromUsername]

		log.Printf("Connection status - From: %v, To: %v", fromExists, toExists)

		// Notifier l'expéditeur du rejet (celui qui a reçu l'invitation)
		if fromExists {
			err := fromConn.WriteJSON(WebSocketMessage{
				Type:    "invitation_rejected",
				Content: string(mustJson(invitation)),
			})
			if err != nil {
				log.Printf("Error sending rejection notification: %v", err)
			}
		} else {
			log.Printf("Cannot send rejection - Target user not connected")
		}

	case InvitationCancel:

		// Notifier le destinataire de l'annulation
		err := toConn.WriteJSON(WebSocketMessage{
			Type:    "invitation_canceled",
			Content: string(mustJson(invitation)),
		})
		if err != nil {
			log.Printf("Error sending cancellation notification: %v", err)
		}
	case RoomLeave:
		log.Printf("RoomLeave: Processing room leave for %s", invitation.FromUsername)

		// Retrieve the room
		room, exists := m.roomManager.GetRoom(invitation.RoomID)
		if !exists {
			log.Printf("Room %s not found during leave", invitation.RoomID)
			return fmt.Errorf("room not found")
		}

		// Notify the other player about room closure
		m.notifyRoomClosure(invitation)

		// Remove the room
		m.roomManager.RemoveRoom(invitation.RoomID)
		m.userStore.UpdateUserRoomStatus(invitation.FromUsername, false)

		// If the other player is still in the room, update their status too
		otherUsername, found := room.GetOtherPlayer(invitation.FromUsername)
		if found {
			m.userStore.UpdateUserRoomStatus(otherUsername, false)
		}
		m.userStore.UpdateUserRoomStatus(invitation.FromUsername, false)
		m.userStore.UpdateUserRoomStatus(invitation.ToUsername, false)
		
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

func (m *OnlineUsersManager) notifyRoomClosure(invitation InvitationMessage) {
	// Try to find the room first
	room, exists := m.roomManager.GetRoom(invitation.RoomID)
	if !exists {
		log.Printf("Room %s not found when trying to notify closure", invitation.RoomID)
		return
	}

	// Find the other player's username
	otherUsername, found := room.GetOtherPlayer(invitation.FromUsername)
	if !found {
		log.Printf("Could not find other player in room %s", invitation.RoomID)
		return
	}

	// Check if the other player is connected
	conn, exists := m.connections[otherUsername]
	if !exists {
		log.Printf("Other player %s not connected", otherUsername)
		return
	}

	// Prepare and send the closure message
	closureMessage := WebSocketMessage{
		Type: "room_closed",
		Content: string(mustJson(map[string]string{
			"room_id":      invitation.RoomID,
			"fromUsername": invitation.FromUsername,
		})),
	}

	err := conn.WriteJSON(closureMessage)
	if err != nil {
		log.Printf("Error sending room closure message to %s: %v", otherUsername, err)
	}
}

func (m *OnlineUsersManager) broadcastOnlineUsers() {
	m.mutex.RLock()
	defer m.mutex.RUnlock()

	// Préparer la liste des utilisateurs en ligne
	onlineUsers := make([]OnlineUser, 0)

	// Récupérer toutes les rooms actives
	activeRooms := m.roomManager.GetActiveRooms()

	// Créer un ensemble des utilisateurs en room
	usersInRooms := make(map[string]bool)
	for _, room := range activeRooms {
		usersInRooms[room.WhitePlayer.Username] = true
		usersInRooms[room.BlackPlayer.Username] = true
	}

	// Parcourir les connexions
	for username := range m.connections {
		user, err := m.userStore.GetUser(username)
		if err == nil {
			// N'ajouter que les utilisateurs qui ne sont pas dans une room
			if _, inRoom := usersInRooms[username]; !inRoom {
				onlineUsers = append(onlineUsers, OnlineUser{
					ID:       user.ID,
					Username: user.UserName,
					IsInRoom: false,
				})
			}
		}
	}

	// Préparer le message
	message := WebSocketMessage{
		Type:    "online_users",
		Content: string(mustJson(onlineUsers)),
	}

	// Envoyer à tous les clients connectés
	for _, conn := range m.connections {
		err := conn.WriteJSON(message)
		if err != nil {
			log.Printf("Error broadcasting to client: %v", err)
		}
	}

	// Log pour le débogage
	log.Printf("Broadcasting %d online users (not in room)", len(onlineUsers))
	log.Printf("Online users: %+v", onlineUsers)
}

// Méthode similaire pour getCurrentOnlineUsers
func (m *OnlineUsersManager) getCurrentOnlineUsers() []OnlineUser {
	m.mutex.RLock()
	defer m.mutex.RUnlock()

	// Récupérer toutes les rooms actives
	activeRooms := m.roomManager.GetActiveRooms()

	// Créer un ensemble des utilisateurs en room
	usersInRooms := make(map[string]bool)
	for _, room := range activeRooms {
		usersInRooms[room.WhitePlayer.Username] = true
		usersInRooms[room.BlackPlayer.Username] = true
	}

	onlineUsers := make([]OnlineUser, 0)
	for username := range m.connections {
		user, err := m.userStore.GetUser(username)
		if err == nil {
			// N'ajouter que les utilisateurs qui ne sont pas dans une room
			if _, inRoom := usersInRooms[username]; !inRoom {
				onlineUsers = append(onlineUsers, OnlineUser{
					ID:       user.ID,
					Username: user.UserName,
					IsInRoom: false,
				})
			}
		}
	}
	return onlineUsers
}

// Utilitaire pour convertir en JSON sans erreur
func mustJson(v interface{}) []byte {
	data, _ := json.Marshal(v)
	return data
}
