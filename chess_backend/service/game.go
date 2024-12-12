package service

import (
	"sync"
	"time"

	"github.com/gorilla/websocket"
)

// New type for Chess Game Room
type ChessGameRoom struct {
	RoomID       string                 `json:"room_id"`
	WhitePlayer  OnlineUser             `json:"white_player"`
	BlackPlayer  OnlineUser             `json:"black_player"`
	CreatedAt    time.Time              `json:"created_at"`
	Connections  map[string]*websocket.Conn `json:"-"`
	mutex        sync.RWMutex
	GameState    map[string]interface{} `json:"game_state,omitempty"`
	Status       RoomStatus             `json:"status"`
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

	room.Connections[username] = conn
}

// Remove a connection from a room
func (room *ChessGameRoom) RemoveConnection(username string) {
	room.mutex.Lock()
	defer room.mutex.Unlock()

	delete(room.Connections, username)
}

// Broadcast message to all players in the room
func (room *ChessGameRoom) BroadcastMessage(message WebSocketMessage) {
	room.mutex.RLock()
	defer room.mutex.RUnlock()

	for _, conn := range room.Connections {
		conn.WriteJSON(message)
	}
}