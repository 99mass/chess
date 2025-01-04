package service

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"sync"
	"time"

	"github.com/gorilla/websocket"
)

// Configuration du WebSocket upgrader
var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool {
		return true
	},
}

func NewOnlineUsersManager(userStore *UserStore) *OnlineUsersManager {
	manager := &OnlineUsersManager{
		connections: make(map[string]*SafeConn),
		userStore:   userStore,
		publicQueue: &PublicGameQueue{
			waitingPlayers: make(map[string]*QueuedPlayer),
		},
	}
	
	manager.roomManager = NewRoomManager(manager)
	manager.tempRoomManager = NewTemporaryRoomManager()
	return manager
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
		// Trouver et nettoyer la room si l'utilisateur y était
		var roomID string
		m.roomManager.mutex.RLock()
		for _, room := range m.roomManager.rooms {
			if room.WhitePlayer.Username == username || room.BlackPlayer.Username == username {
				roomID = room.RoomID
				break
			}
		}
		m.roomManager.mutex.RUnlock()

		if roomID != "" {
			// Notifier l'autre joueur et nettoyer la room
			invitation := InvitationMessage{
				Type:         RoomLeave,
				FromUsername: username,
				RoomID:       roomID,
			}
			m.handleInvitation(invitation)
		}

		// Nettoyer la connexion
		m.mutex.Lock()
		delete(m.connections, username)
		m.mutex.Unlock()

		// Mettre à jour le statut hors ligne
		m.userStore.UpdateUserOnlineStatus(username, false, false)
		m.userStore.UpdateUserRoomStatus(username, false)

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

		var wg sync.WaitGroup
		wg.Add(1)

		go func(msg WebSocketMessage) {
			defer wg.Done()

			switch msg.Type {
			case "request_online_users":

				onlineUsers := m.getCurrentOnlineUsers()
				conn.WriteJSON(WebSocketMessage{
					Type:    "online_users",
					Content: string(mustJson(onlineUsers)),
				})

			case "invitation_send", "invitation_accept", "invitation_reject", "invitation_cancel", "room_leave":
				var invitation InvitationMessage
				if err := json.Unmarshal([]byte(msg.Content), &invitation); err != nil {
					log.Printf("Error parsing invitation: %v", err)
					return
				}

				if err := m.handleInvitation(invitation); err != nil {
					log.Printf("Failed to process invitation: %v", err)
				}
				m.broadcastOnlineUsers()

			case "leave_room":
				var leaveRequest struct {
					Username string `json:"username"`
				}
				if err := json.Unmarshal([]byte(msg.Content), &leaveRequest); err != nil {
					log.Printf("Error parsing leave room request: %v", err)
					return
				}

				m.cleanupPlayerFromPublicQueue(username)

				_, err := m.RemoveUserFromRoom(leaveRequest.Username)
				if err != nil {
					log.Printf("Error removing user from room: %v", err)
					return
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

				if err := json.Unmarshal([]byte(msg.Content), &moveData); err != nil {
					log.Printf("Error parsing move data: %v", err)
					return
				}

				// Récupérer la room avec verrou en lecture
				m.roomManager.mutex.RLock()
				room, exists := m.roomManager.rooms[moveData.GameID]
				m.roomManager.mutex.RUnlock()

				if !exists {
					log.Printf("Room not found: %s", moveData.GameID)
					return
				}

				// Envoyer le mouvement avec la nouvelle méthode
				if err := room.SendMove(moveData); err != nil {
					log.Printf("Error sending move: %v", err)
					// Optionnel: notifier le joueur de l'échec
					conn.WriteJSON(WebSocketMessage{
						Type: "move_error",
						Content: string(mustJson(map[string]string{
							"error": err.Error(),
						})),
					})
					return
				}

			case "game_over_checkmate":
				var gameOverData struct {
					GameID   string `json:"gameId"`
					Winner   string `json:"winner"`
					Reason   string `json:"reason"`
					WinnerID string `json:"winnerId"`
				}

				if err := json.Unmarshal([]byte(msg.Content), &gameOverData); err != nil {
					log.Printf("Error parsing game over data: %v", err)
					return
				}

				// Nettoyer la file d'attente publique d'abord
				m.cleanupPlayerFromPublicQueue(username)

				// Récupérer la room avec un verrou
				room, exists := m.roomManager.GetRoom(gameOverData.GameID)
				if !exists {
					log.Printf("Room not found: %s", gameOverData.GameID)
					return
				}

				// Marquer la partie comme terminée
				room.mutex.Lock()
				room.IsGameOver = true
				room.WinnerID = gameOverData.WinnerID
				connections := make(map[string]*SafeConn, len(room.Connections))
				for k, v := range room.Connections {
					connections[k] = v
				}
				room.mutex.Unlock()

				// Arrêter le timer immédiatement
				if room.Timer != nil {
					room.Timer.Stop()
				}

				// Envoyer le message de fin de partie à tous les joueurs
				gameOverMessage := WebSocketMessage{
					Type:    "game_over_checkmate",
					Content: msg.Content,
				}

				for username, conn := range connections {
					if err := conn.WriteJSON(gameOverMessage); err != nil {
						log.Printf("Error sending game over notification to %s: %v", username, err)
					}
				}

				// Nettoyer la room après un délai
				go func() {
					time.Sleep(2 * time.Second)

					// Mettre à jour le statut des joueurs
					for username := range connections {
						m.userStore.UpdateUserRoomStatus(username, false)
					}

					// Supprimer la room
					m.roomManager.RemoveSpecificRoom(gameOverData.GameID)

					// Broadcast la mise à jour
					m.broadcastOnlineUsers()
				}()

			case PublicGameRequest:
				user, err := m.userStore.GetUser(username)
				if err != nil {
					return
				}
				safeConn := NewSafeConn(conn)
				m.handlePublicGameRequest(username, user.ID, safeConn)

			case PublicQueueLeave:
				m.handlePublicQueueLeave(username)

			default:
				log.Printf("Unhandled message type: %s", msg.Type)
				m.broadcastOnlineUsers()
			}

		}(message)

		wg.Wait()
	}
}

func (m *OnlineUsersManager) handleInvitation(invitation InvitationMessage) error {
	m.mutex.RLock()
	_, fromExists := m.connections[invitation.FromUsername]
	toConn, toExists := m.connections[invitation.ToUsername]
	m.mutex.RUnlock()

	if invitation.Type == RoomLeave && !fromExists {
		return fmt.Errorf("user not online")
	}

	if invitation.Type != RoomLeave && (!fromExists || !toExists) {
		return fmt.Errorf("one or both users not online")
	}

	if invitation.Type == RoomLeave {
		m.roomManager.mutex.RLock()
		room, exists := m.roomManager.rooms[invitation.RoomID]
		m.roomManager.mutex.RUnlock()

		if !exists {
			log.Printf("Room %s not found for leave operation", invitation.RoomID)
			return nil // Retourner nil car la room n'existe déjà plus
		}

		// Vérifier si l'utilisateur appartient à cette room
		if room.WhitePlayer.Username != invitation.FromUsername &&
			room.BlackPlayer.Username != invitation.FromUsername {
			return fmt.Errorf("user %s not found in room %s",
				invitation.FromUsername, invitation.RoomID)
		}
	}

	switch invitation.Type {

	case InvitationSend:

		if invitation.RoomID == "" {
			invitation.RoomID = GenerateUniqueID()
		}

		// Créer le timer
		timeout := NewInvitationTimeout(invitation.RoomID, 20*time.Second, func() {
			// Fonction appelée quand le timeout expire
			if tempRoom, exists := m.tempRoomManager.GetTempRoom(invitation.RoomID); exists {

				timeoutMsg := WebSocketMessage{
					Type: "invitation_timeout",
					Content: string(mustJson(InvitationMessage{
						Type:         InvitationCancel,
						FromUserID:   tempRoom.WhitePlayer.ID,
						FromUsername: tempRoom.WhitePlayer.Username,
						ToUserID:     tempRoom.BlackPlayer.ID,
						ToUsername:   tempRoom.BlackPlayer.Username,
						RoomID:       tempRoom.RoomID,
					})),
				}

				// Envoyer le message aux deux joueurs
				if fromConn, exists := m.connections[tempRoom.WhitePlayer.Username]; exists {
					fromConn.WriteJSON(timeoutMsg)
				}
				if toConn, exists := m.connections[tempRoom.BlackPlayer.Username]; exists {
					toConn.WriteJSON(timeoutMsg)
				}

				// Nettoyer la room temporaire
				m.tempRoomManager.RemoveTempRoom(invitation.RoomID)
			}
		})

		// Créer la room temporaire
		m.tempRoomManager.CreateTempRoom(invitation, timeout)
		timeout.Start()

		// Envoyer l'invitation
		if toConn, exists := m.connections[invitation.ToUsername]; exists {
			err := toConn.WriteJSON(WebSocketMessage{
				Type:    "invitation",
				Content: string(mustJson(invitation)),
			})
			if err != nil {
				log.Printf("Error sending invitation: %v", err)
				return err
			}
		}

	case InvitationAccept:
		// Récupérer et nettoyer la room temporaire
		if _, exists := m.tempRoomManager.GetTempRoom(invitation.RoomID); exists {

			m.tempRoomManager.RemoveTempRoom(invitation.RoomID)

			// Créer la nouvelle room de jeu
			gameRoom := m.roomManager.CreateRoom(invitation)

			// Mettre à jour le statut des joueurs
			m.userStore.UpdateUserRoomStatus(invitation.FromUsername, true)
			m.userStore.UpdateUserRoomStatus(invitation.ToUsername, true)

			// Initialiser l'état du jeu
			gameRoom.PositionFEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
			gameRoom.IsWhitesTurn = true
			gameRoom.IsGameOver = false

			// Préparer les états de jeu pour les deux joueurs
			baseGameState := map[string]interface{}{
				"gameId":         invitation.RoomID,
				"gameCreatorUid": invitation.FromUserID,
				"positonFen":     gameRoom.PositionFEN,
				"winnerId":       "",
				"whitesTime":     gameRoom.WhitesTime,
				"blacksTime":     gameRoom.BlacksTime,
				"isWhitesTurn":   gameRoom.IsWhitesTurn,
				"isGameOver":     gameRoom.IsGameOver,
				"moves":          gameRoom.Moves,
			}

			// États spécifiques pour chaque joueur
			creatorGameState := copyAndAddUserInfo(baseGameState, invitation.FromUserID, invitation.ToUsername)
			inviteeGameState := copyAndAddUserInfo(baseGameState, invitation.ToUserID, invitation.FromUsername)

			// Envoyer les messages aux joueurs
			fromConn, fromExists := m.connections[invitation.FromUsername]
			if fromExists {
				gameRoom.AddConnection(invitation.FromUsername, fromConn)
				fromConn.WriteJSON(WebSocketMessage{
					Type:    "game_start",
					Content: string(mustJson(creatorGameState)),
				})
			}

			if toExists {
				gameRoom.AddConnection(invitation.ToUsername, toConn)
				toConn.WriteJSON(WebSocketMessage{
					Type:    "game_start",
					Content: string(mustJson(inviteeGameState)),
				})
			}
		}
	case InvitationReject:

		m.tempRoomManager.RemoveTempRoom(invitation.RoomID)

		fromConn, fromExists := m.connections[invitation.ToUsername]

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
		// Récupérer et nettoyer la room temporaire
		if _, exists := m.tempRoomManager.GetTempRoom(invitation.RoomID); exists {
			// Arrêter le timer et supprimer la room temporaire
			m.tempRoomManager.RemoveTempRoom(invitation.RoomID)

			fromConn, fromExists := m.connections[invitation.ToUsername]
			if fromExists {
				err := fromConn.WriteJSON(WebSocketMessage{
					Type:    "invitation_cancelled",
					Content: string(mustJson(invitation)),
				})
				if err != nil {
					log.Printf("Error sending cancel notification: %v", err)
				}
			}
		}
		return nil

	case RoomLeave:
		// Récupérer la room spécifique
		room, exists := m.roomManager.GetRoom(invitation.RoomID)
		if !exists {
			return nil // La room n'existe déjà plus
		}

		// Arrêter le timer avant tout
		if room.Timer != nil {
			room.Timer.Stop()
		}

		// Notifier l'autre joueur avant de supprimer la room
		otherUsername, found := room.GetOtherPlayer(invitation.FromUsername)
		if found {
			if conn, exists := room.Connections[otherUsername]; exists {
				closeMsg := WebSocketMessage{
					Type: "room_closed",
					Content: string(mustJson(map[string]string{
						"room_id": invitation.RoomID,
						"reason":  "opponent_left",
					})),
				}
				conn.WriteJSON(closeMsg)
			}
		}

		// Mettre à jour les statuts des joueurs
		m.userStore.UpdateUserRoomStatus(invitation.FromUsername, false)
		if found {
			m.userStore.UpdateUserRoomStatus(otherUsername, false)
		}

		// Supprimer uniquement cette room
		m.roomManager.RemoveSpecificRoom(invitation.RoomID)

		// Broadcast la mise à jour des utilisateurs
		m.broadcastOnlineUsers()

	}

	return nil
}

func copyAndAddUserInfo(baseState map[string]interface{}, userId, opponentUsername string) map[string]interface{} {
	newState := make(map[string]interface{})
	for k, v := range baseState {
		newState[k] = v
	}
	newState["userId"] = userId
	newState["opponentUsername"] = opponentUsername
	return newState
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

func (m *OnlineUsersManager) broadcastOnlineUsers() {
	// Obtenir les connexions actives
	m.mutex.RLock()
	connections := make(map[string]*SafeConn)
	for username, conn := range m.connections {
		connections[username] = conn
	}
	m.mutex.RUnlock()

	// Obtenir la liste filtrée des utilisateurs en ligne
	onlineUsers := m.getCurrentOnlineUsers()

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

	// Obtenir les utilisateurs dans des rooms
	usersInRooms := make(map[string]bool)
	m.roomManager.mutex.RLock()
	for _, room := range m.roomManager.rooms {
		usersInRooms[room.WhitePlayer.Username] = true
		usersInRooms[room.BlackPlayer.Username] = true
	}
	m.roomManager.mutex.RUnlock()

	// Obtenir les utilisateurs dans la file d'attente publique
	m.publicQueue.mutex.RLock()
	usersInPublicQueue := make(map[string]bool)
	for username := range m.publicQueue.waitingPlayers {
		usersInPublicQueue[username] = true
	}
	m.publicQueue.mutex.RUnlock()

	// Ne garder que les utilisateurs qui ne sont ni dans des rooms ni dans la file d'attente
	onlineUsers := make([]OnlineUser, 0)
	for username := range connections {
		// Vérifier si l'utilisateur n'est ni dans une room ni dans la file d'attente
		if !usersInRooms[username] && !usersInPublicQueue[username] {
			user, err := m.userStore.GetUser(username)
			if err == nil {
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
