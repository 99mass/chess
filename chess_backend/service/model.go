package service

import (
	"sync"

	"github.com/gorilla/websocket"
)

type UserProfile struct {
	ID       string `json:"id"`
	UserName string `json:"username"`
	IsOnline bool   `json:"isnOline"`
	IsInRoom   bool   `json:"isInRoom"`
}

type UserStore struct {
	Users map[string]UserProfile `json:"users"`
	mutex sync.RWMutex
}

type OnlineStatusUpdate struct {
	Username string `json:"username"`
	IsOnline bool   `json:"is_online"`
}

// Structure pour représenter un message WebSocket
type WebSocketMessage struct {
	Type    string `json:"type"`
	Content string `json:"content"`
}

// Structure de gestion des connexions WebSocket
type OnlineUsersManager struct {
	mutex       sync.RWMutex
	connections map[string]*websocket.Conn
	userStore   *UserStore
	roomManager *RoomManager
}

type OnlineUser struct {
	ID       string `json:"id"`
	Username string `json:"username"`
	IsInRoom bool   `json:"isInRoom"`
}

// Types de messages pour les invitations
type InvitationMessageType string

const (
	InvitationSend   InvitationMessageType = "invitation_send"
	InvitationAccept InvitationMessageType = "invitation_accept"
	InvitationReject InvitationMessageType = "invitation_reject"
)

// Structure pour les messages d'invitation
type InvitationMessage struct {
	Type         InvitationMessageType `json:"type"`
	FromUserID   string                `json:"from_user_id"`
	FromUsername string                `json:"from_username"`
	ToUserID     string                `json:"to_user_id"`
	ToUsername   string                `json:"to_username"`
	RoomID       string                `json:"room_id,omitempty"`
}
