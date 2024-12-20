package service

import (
	"fmt"
	"log"
	"sync"
	"time"

	"github.com/gorilla/websocket"
)

// New type for Chess Game Room
type ChessGameRoom struct {
	RoomID      string                     `json:"room_id"`
	WhitePlayer OnlineUser                 `json:"white_player"`
	BlackPlayer OnlineUser                 `json:"black_player"`
	CreatedAt   time.Time                  `json:"created_at"`
	Connections map[string]*websocket.Conn `json:"-"`
	mutex       sync.RWMutex
	GameState   map[string]interface{} `json:"game_state,omitempty"`
	Status      RoomStatus             `json:"status"`

	// New fields added from Dart GameModel
	GameCreatorUID    string `json:"game_creator_uid"`
	PositionFEN       string `json:"position_fen"`
	WinnerID          string `json:"winner_id,omitempty"`
	WhitesTime        string `json:"whites_time"`
	BlacksTime        string `json:"blacks_time"`
	WhitesCurrentMove string `json:"whites_current_move"`
	BlacksCurrentMove string `json:"blacks_current_move"`
	BoardState        string `json:"board_state"`
	PlayState         string `json:"play_state"`
	IsWhitesTurn      bool   `json:"is_whites_turn"`
	IsGameOver        bool   `json:"is_game_over"`
	SquareState       int    `json:"square_state"`
	Moves             []Move `json:"moves"`
}

// You'll need to define the Move struct as well
type Move struct {
	From  string `json:"from"`
	To    string `json:"to"`
	Piece string `json:"piece"`
}

// Room status types
type RoomStatus string

const (
	RoomStatusPending  RoomStatus = "pending"
	RoomStatusInGame   RoomStatus = "in_game"
	RoomStatusFinished RoomStatus = "finished"
)

// New type for Room Management
type RoomManager struct {
	rooms map[string]*ChessGameRoom
	mutex sync.RWMutex
}

// Additional invitation message type
const (
	InvitationCancel InvitationMessageType = "invitation_cancel"
	RoomLeave        InvitationMessageType = "room_leave"
)

// Method to create a new Room Manager
func NewRoomManager() *RoomManager {
	return &RoomManager{
		rooms: make(map[string]*ChessGameRoom),
	}
}

// Create a new Chess Game Room
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
		CreatedAt:   time.Now(),
		Connections: make(map[string]*websocket.Conn),
		Status:      RoomStatusPending,
		GameState:   make(map[string]interface{}),

		// Initialize new fields
		GameCreatorUID: invitation.FromUserID,
		PositionFEN:    "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", // Standard starting position
		WhitesTime:     "0",                                                        // Initial time
		BlacksTime:     "0",                                                        // Initial time
		IsWhitesTurn:   true,
		IsGameOver:     false,
		Moves:          []Move{},
	}

	rm.rooms[invitation.RoomID] = room
	return room
}

// Get a room by its ID
func (rm *RoomManager) GetRoom(roomID string) (*ChessGameRoom, bool) {
	rm.mutex.RLock()
	defer rm.mutex.RUnlock()

	room, exists := rm.rooms[roomID]
	return room, exists
}

// Remove a room
func (rm *RoomManager) RemoveRoom(roomID string) {
	rm.mutex.Lock()
	defer rm.mutex.Unlock()

	delete(rm.rooms, roomID)
}

// Add a connection to a room
func (room *ChessGameRoom) AddConnection(username string, conn *websocket.Conn) {
	room.mutex.Lock()
	defer room.mutex.Unlock()
	log.Printf("Adding connection for %s to room %s", username, room.RoomID)
	room.Connections[username] = conn
}

// GetOtherPlayer retourne le joueur opposé à username dans la room.
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
		// Par exemple, vérifier le statut de la room
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

// Broadcast message to all players in the room
func (room *ChessGameRoom) BroadcastMessage(message WebSocketMessage) {
	room.mutex.RLock()
	defer room.mutex.RUnlock()

	for _, conn := range room.Connections {
		conn.WriteJSON(message)
	}
}
