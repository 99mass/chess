package service

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"time"

	"github.com/gorilla/websocket"
)

// Configuration du WebSocket upgrader
var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool {
		return true
	},
}

// Créer un nouveau gestionnaire de connexions
func NewOnlineUsersManager(userStore *UserStore) *OnlineUsersManager {
	return &OnlineUsersManager{
		connections: make(map[string]*SafeConn),
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

	safeConn := NewSafeConn(conn)

	// Ajouter la connexion
	m.mutex.Lock()
	// m.connections[username] = conn
	m.connections[username] = safeConn
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

			// moves
		case "game_move":
			var moveData struct {
				GameID       string      `json:"gameId"`
				FromUserID   string      `json:"fromUserId"`
				ToUserID     string      `json:"toUserId"`
				ToUsername   string      `json:"toUsername"`
				Move         interface{} `json:"move"`
				FEN          string      `json:"fen"`
				IsWhitesTurn bool        `json:"isWhitesTurn"`
			}

			if err := json.Unmarshal([]byte(message.Content), &moveData); err != nil {
				log.Printf("Error parsing move data: %v", err)
				continue
			}

			// Récupérer la room
			room, exists := m.roomManager.GetRoom(moveData.GameID)
			if !exists {
				log.Printf("Room not found: %s", moveData.GameID)
				continue
			}
			if exists {
				room.Timer.SwitchTurn()
			}

			// Mettre à jour l'état du jeu
			room.mutex.Lock()
			room.PositionFEN = moveData.FEN
			room.IsWhitesTurn = moveData.IsWhitesTurn
			room.mutex.Unlock()

			// Envoyer le mouvement à l'autre joueur
			if otherConn, exists := room.Connections[moveData.ToUsername]; exists {
				if err := otherConn.WriteJSON(WebSocketMessage{
					Type:    "game_move",
					Content: message.Content,
				}); err != nil {
					log.Printf("Error sending move to other player: %v", err)
				}
			} else {
				log.Printf("Connection not found for player %s", moveData.ToUsername)
			}
		case "game_over_checkmate":
			var gameOverData struct {
				GameID   string `json:"gameId"`
				Winner   string `json:"winner"`
				WinnerID string `json:"winnerId"`
			}

			if err := json.Unmarshal([]byte(message.Content), &gameOverData); err != nil {
				log.Printf("Error parsing game over data: %v", err)
				continue
			}

			// Récupérer la room
			room, exists := m.roomManager.GetRoom(gameOverData.GameID)
			if !exists {
				log.Printf("Room not found: %s", gameOverData.GameID)
				continue
			}

			room.IsGameOver = true

			gameOverMessage := WebSocketMessage{
				Type:    "game_over_checkmate",
				Content: message.Content,
			}

			// Envoyer aux deux joueurs
			for username, conn := range room.Connections {
				if err := conn.WriteJSON(gameOverMessage); err != nil {
					log.Printf("Error sending game over notification to %s: %v", username, err)
				}
			}

			// Arrêter le timer si nécessaire
			if room.Timer != nil {
				room.Timer.Stop()
			}

			//  Nettoyer la room après un délai 2 secondes
			go func() {
				time.Sleep(2 * time.Second)
				m.roomManager.RemoveRoom(gameOverData.GameID)
				for username := range room.Connections {
					m.userStore.UpdateUserRoomStatus(username, false)
				}
				m.broadcastOnlineUsers()
			}()

		default:
			log.Printf("Unhandled message type: %s", message.Type)
			m.broadcastOnlineUsers()
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

		// Message de base pour les deux joueurs
		baseGameState := map[string]interface{}{
			"gameId":         invitation.RoomID,
			"gameCreatorUid": invitation.ToUserID,
			"positonFen":     room.PositionFEN,
			"winnerId":       "",
			"whitesTime":     room.WhitesTime,
			"blacksTime":     room.BlacksTime,
			"isWhitesTurn":   room.IsWhitesTurn,
			"isGameOver":     room.IsGameOver,
			"moves":          room.Moves,
		}

		// Préparer le message pour le créateur du jeu
		creatorGameState := make(map[string]interface{})
		for k, v := range baseGameState {
			creatorGameState[k] = v
		}
		creatorGameState["userId"] = invitation.FromUserID
		creatorGameState["opponentUsername"] = invitation.ToUsername

		// Préparer le message pour l'invité
		inviteeGameState := make(map[string]interface{})
		for k, v := range baseGameState {
			inviteeGameState[k] = v
		}
		inviteeGameState["userId"] = invitation.ToUserID
		inviteeGameState["opponentUsername"] = invitation.FromUsername

		// Envoyer les messages appropriés aux deux joueurs
		fromConn, fromExists := m.connections[invitation.FromUsername]
		toConn, toExists := m.connections[invitation.ToUsername]

		if fromExists {
			room.AddConnection(invitation.FromUsername, fromConn)
			err := fromConn.WriteJSON(WebSocketMessage{
				Type:    "game_start",
				Content: string(mustJson(creatorGameState)),
			})
			if err != nil {
				log.Printf("Error sending game start to creator: %v", err)
			}
		}

		if toExists {
			room.AddConnection(invitation.ToUsername, toConn)
			err := toConn.WriteJSON(WebSocketMessage{
				Type:    "game_start",
				Content: string(mustJson(inviteeGameState)),
			})
			if err != nil {
				log.Printf("Error sending game start to invitee: %v", err)
			}
		}
	case InvitationReject:

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
			Type:    "invitation_cancel",
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

		// Arrêter le timer avant de fermer la room
		if room.Timer != nil {
			room.Timer.Stop()
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
	connections := make(map[string]*SafeConn)
	for username, conn := range m.connections {
		connections[username] = conn
	}
	m.mutex.RUnlock()

	// Get active rooms with proper locking
	activeRooms := m.roomManager.GetActiveRooms()
	usersInRooms := make(map[string]bool)
	for _, room := range activeRooms {
		usersInRooms[room.WhitePlayer.Username] = true
		usersInRooms[room.BlackPlayer.Username] = true
	}

	onlineUsers := make([]OnlineUser, 0)
	for username := range connections {
		user, err := m.userStore.GetUser(username)
		if err == nil && !usersInRooms[username] {
			onlineUsers = append(onlineUsers, OnlineUser{
				ID:       user.ID,
				Username: user.UserName,
				IsInRoom: false,
			})
		}
	}

	message := WebSocketMessage{
		Type:    "online_users",
		Content: string(mustJson(onlineUsers)),
	}

	for _, conn := range connections {
		if err := conn.WriteJSON(message); err != nil {
			log.Printf("Error broadcasting: %v", err)
		}
	}
}

func (m *OnlineUsersManager) getCurrentOnlineUsers() []OnlineUser {
	m.mutex.RLock()
	connections := make(map[string]*SafeConn)
	for username, conn := range m.connections {
		connections[username] = conn
	}
	m.mutex.RUnlock()

	activeRooms := m.roomManager.GetActiveRooms()
	usersInRooms := make(map[string]bool)
	for _, room := range activeRooms {
		usersInRooms[room.WhitePlayer.Username] = true
		usersInRooms[room.BlackPlayer.Username] = true
	}

	onlineUsers := make([]OnlineUser, 0)
	for username := range connections {
		user, err := m.userStore.GetUser(username)
		if err == nil && !usersInRooms[username] {
			onlineUsers = append(onlineUsers, OnlineUser{
				ID:       user.ID,
				Username: user.UserName,
				IsInRoom: false,
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
