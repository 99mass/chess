package service

import (
	"fmt"
	"log"
	"sync"
	"time"
)

var gameTime = 10

type ChessGameRoom struct {
	RoomID      string               `json:"room_id"`
	WhitePlayer OnlineUser           `json:"white_player"`
	BlackPlayer OnlineUser           `json:"black_player"`
	CreatedAt   time.Time            `json:"created_at"`
	Connections map[string]*SafeConn `json:"-"`
	mutex       sync.RWMutex
	GameState   map[string]interface{} `json:"game_state,omitempty"`
	Status      RoomStatus             `json:"status"`
	RoomOrigin string `json:"room_origin"` 

	GameCreatorUID    string `json:"game_creator_uid"`
	PositionFEN       string `json:"position_fen"`
	WinnerID          string `json:"winner_id,omitempty"`
	WhitesTime        string `json:"whites_time"`
	BlacksTime        string `json:"blacks_time"`
	IsWhitesTurn      bool   `json:"is_whites_turn"`
	IsGameOver        bool   `json:"is_game_over"`
	Moves             []Move `json:"moves"`
	Timer             *ChessTimer
	InvitationTimeout *InvitationTimeout
	onlineManager     *OnlineUsersManager
}


type Move struct {
	From  string `json:"from"`
	To    string `json:"to"`
	Piece string `json:"piece"`
}

type RoomStatus string

const (
	RoomStatusPending  RoomStatus = "pending"
	RoomStatusInGame   RoomStatus = "in_game"
	RoomStatusFinished RoomStatus = "finished"
)

type RoomManager struct {
	rooms         map[string]*ChessGameRoom
	mutex         sync.RWMutex
	onlineManager *OnlineUsersManager
}

const (
	InvitationCancel InvitationMessageType = "invitation_cancel"
	RoomLeave        InvitationMessageType = "room_leave"
)

func NewRoomManager(onlineManager *OnlineUsersManager) *RoomManager {
	return &RoomManager{
		rooms:         make(map[string]*ChessGameRoom),
		onlineManager: onlineManager,
	}
}
func (rm *RoomManager) CreateRoom(invitation InvitationMessage) *ChessGameRoom {
	rm.mutex.Lock()
	defer rm.mutex.Unlock()

	room := &ChessGameRoom{
		RoomID: invitation.RoomID,
		WhitePlayer: OnlineUser{
			ID:       invitation.FromUserID,
			Username: invitation.FromUsername,
		},
		BlackPlayer: OnlineUser{
			ID:       invitation.ToUserID,
			Username: invitation.ToUsername,
		},
		CreatedAt:     time.Now(),
		Connections:   make(map[string]*SafeConn),
		Status:        RoomStatusPending,
		GameState:     make(map[string]interface{}),
		RoomOrigin:    "invitation", // Marquer l'origine
		mutex:         sync.RWMutex{},
		PositionFEN:   "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
		IsWhitesTurn:  true,
		IsGameOver:    false,
		Moves:         []Move{},
		onlineManager: rm.onlineManager,
	}

	// Créer et configurer le timer
	timer := NewChessTimer(room, gameTime)
	room.Timer = timer

	// Stocker la room
	rm.rooms[invitation.RoomID] = room

	// Démarrer le timer de manière asynchrone
	go timer.Start()

	return room
}

func (room *ChessGameRoom) SendMove(moveData struct {
	GameID       string      `json:"gameId"`
	FromUserID   string      `json:"fromUserId"`
	ToUserID     string      `json:"toUserId"`
	ToUsername   string      `json:"toUsername"`
	Move         interface{} `json:"move"`
	FEN          string      `json:"fen"`
	IsWhitesTurn bool        `json:"isWhitesTurn"`
}) error {
	room.mutex.Lock()
	defer room.mutex.Unlock()

	if room.IsWhitesTurn != !moveData.IsWhitesTurn {
		return fmt.Errorf("not your turn")
	}

	// Mettre à jour l'état de la partie
	room.PositionFEN = moveData.FEN
	room.IsWhitesTurn = !moveData.IsWhitesTurn

	// Vérifier et obtenir la connexion du destinataire de manière thread-safe
	targetConn, exists := room.Connections[moveData.ToUsername]
	if !exists {
		// Tenter de récupérer la connexion depuis le manager si elle n'est pas dans la room
		if room.onlineManager != nil {
			room.onlineManager.mutex.RLock()
			if conn, ok := room.onlineManager.connections[moveData.ToUsername]; ok {
				targetConn = conn
				exists = true
				// Mettre à jour la connexion dans la room
				room.Connections[moveData.ToUsername] = conn
			}
			room.onlineManager.mutex.RUnlock()
		}

		if !exists {
			return fmt.Errorf("target player not connected")
		}
	}

	// Préparer le message avec l'ID de la room
	moveMessage := WebSocketMessage{
		Type: "game_move",
		Content: string(mustJson(struct {
			GameID       string      `json:"gameId"`
			FromUserID   string      `json:"fromUserId"`
			ToUserID     string      `json:"toUserId"`
			ToUsername   string      `json:"toUsername"`
			Move         interface{} `json:"move"`
			FEN          string      `json:"fen"`
			IsWhitesTurn bool        `json:"isWhitesTurn"`
			RoomOrigin   string      `json:"roomOrigin"`
		}{
			GameID:       moveData.GameID,
			FromUserID:   moveData.FromUserID,
			ToUserID:     moveData.ToUserID,
			ToUsername:   moveData.ToUsername,
			Move:         moveData.Move,
			FEN:          moveData.FEN,
			IsWhitesTurn: moveData.IsWhitesTurn,
			RoomOrigin:   room.RoomOrigin,
		})),
	}

	// Envoyer le mouvement avec retry et logging
	maxRetries := 3

	for i := 0; i < maxRetries; i++ {
		err := targetConn.WriteJSON(moveMessage)
		if err == nil {
			break
		}

		if i == maxRetries-1 {
			log.Printf("Failed to send move to %s in room %s after %d attempts: %v",
				moveData.ToUsername, room.RoomID, maxRetries, err)
			return fmt.Errorf("failed to send move after %d retries: %v", maxRetries, err)
		}
		time.Sleep(100 * time.Millisecond)
	}

	// Changer le tour dans le timer
	if room.Timer != nil {
		go room.Timer.SwitchTurn()
	}

	return nil
}



func (rm *RoomManager) GetRoom(roomID string) (*ChessGameRoom, bool) {
	rm.mutex.RLock()
	defer rm.mutex.RUnlock()

	room, exists := rm.rooms[roomID]
	return room, exists
}

func (rm *RoomManager) RemoveRoom(roomID string) {
	rm.mutex.Lock()
	defer rm.mutex.Unlock()

	if room, exists := rm.rooms[roomID]; exists {
		// Arrêter le timer avant de supprimer la room
		if room.Timer != nil {
			room.Timer.Stop()
		}

		// Nettoyer les connexions de la room
		room.mutex.Lock()
		for username := range room.Connections {
			delete(room.Connections, username)
		}
		room.mutex.Unlock()

		delete(rm.rooms, roomID)
	}
}

func (rm *RoomManager) RemoveSpecificRoom(roomID string) {
    rm.mutex.Lock()
    defer rm.mutex.Unlock()

    room, exists := rm.rooms[roomID]
    if !exists {
        return
    }

    // Arrêter le timer de manière sûre
    if room.Timer != nil {
        room.Timer.Stop()
    }

    // Nettoyer les connexions de la room
    room.mutex.Lock()
    for username := range room.Connections {
        delete(room.Connections, username)
    }
    room.mutex.Unlock()

    // Supprimer la room
    delete(rm.rooms, roomID)
}

func (room *ChessGameRoom) AddConnection(username string, conn *SafeConn) {
	room.mutex.Lock()
	defer room.mutex.Unlock()
	room.Connections[username] = conn
}

func (room *ChessGameRoom) GetOtherPlayer(username string) (string, bool) {
	if room.WhitePlayer.Username == username {
		return room.BlackPlayer.Username, true
	} else if room.BlackPlayer.Username == username {
		return room.WhitePlayer.Username, true
	}
	return "", false // Aucun autre joueur trouvé
}

func (rm *RoomManager) GetActiveRooms() []*ChessGameRoom {
	rm.mutex.RLock()
	defer rm.mutex.RUnlock()

	activeRooms := make([]*ChessGameRoom, 0, len(rm.rooms))
	for _, room := range rm.rooms {
		// Vous pouvez ajouter des conditions supplémentaires si nécessaire
		if room.Status == RoomStatusInGame || room.Status == RoomStatusPending {
			activeRooms = append(activeRooms, room)
		}
	}

	return activeRooms
}

// Remove a connection from a room
func (room *ChessGameRoom) RemoveConnection(username string) {
	room.mutex.Lock()
	defer room.mutex.Unlock()

	delete(room.Connections, username)
}

func (m *OnlineUsersManager) RemoveUserFromRoom(username string) ([]OnlineUser, error) {
	// Find the room the user is in
	var roomToRemove *ChessGameRoom
	m.roomManager.mutex.RLock()
	for _, room := range m.roomManager.rooms {
		if room.WhitePlayer.Username == username || room.BlackPlayer.Username == username {
			roomToRemove = room
			break
		}
	}
	m.roomManager.mutex.RUnlock()

	// If no room found, return an error
	if roomToRemove == nil {
		return nil, fmt.Errorf("user %s not in any room", username)
	}

	// Find the other player
	otherUsername, found := roomToRemove.GetOtherPlayer(username)
	if !found {
		return nil, fmt.Errorf("could not find other player in room")
	}

	// Remove the room
	m.roomManager.RemoveRoom(roomToRemove.RoomID)

	// Update user statuses
	m.userStore.UpdateUserRoomStatus(username, false)
	if otherUsername != "" {
		m.userStore.UpdateUserRoomStatus(otherUsername, false)
	}

	// Broadcast and return online users
	return m.getCurrentOnlineUsers(), nil
}

func (room *ChessGameRoom) BroadcastMessage(message WebSocketMessage) {
	room.mutex.RLock()
	connections := make(map[string]*SafeConn)
	for username, conn := range room.Connections {
		connections[username] = conn
	}
	room.mutex.RUnlock()

	for _, conn := range connections {
		if conn != nil {
			go func(c *SafeConn) {
				c.WriteJSON(message)
			}(conn)
		}
	}
}

