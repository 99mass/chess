package service

import (
	"fmt"
	"log"
	"sync"
	"time"
)

type ChessTimer struct {
	room         *ChessGameRoom
	ticker       *time.Ticker
	stopChan     chan struct{}
	mutex        sync.RWMutex
	isRunning    bool
	whiteSeconds int
	blackSeconds int
}

type TimerUpdate struct {
	RoomID       string `json:"roomId"`
	WhiteTime    int    `json:"whiteTime"`
	BlackTime    int    `json:"blackTime"`
	IsWhitesTurn bool   `json:"isWhitesTurn"`
}

func NewChessTimer(room *ChessGameRoom, initialTimeMinutes int) *ChessTimer {
	return &ChessTimer{
		room:         room,
		stopChan:     make(chan struct{}),
		whiteSeconds: initialTimeMinutes * 60,
		blackSeconds: initialTimeMinutes * 60,
	}
}

func (ct *ChessTimer) Start() {
	ct.mutex.Lock()
	if ct.isRunning {
		ct.mutex.Unlock()
		return
	}

	// S'assurer que IsWhitesTurn est à true au démarrage
	ct.room.mutex.Lock()
	ct.room.IsWhitesTurn = true
	ct.room.mutex.Unlock()

	ct.isRunning = true
	ct.ticker = time.NewTicker(1 * time.Second)
	ct.mutex.Unlock()

	// Envoyer l'état initial immédiatement
	ct.broadcastTimeUpdate()

	go ct.runTimer()
}

func (ct *ChessTimer) runTimer() {
	for {
		select {
		case <-ct.ticker.C:
			ct.mutex.Lock()
			ct.room.mutex.RLock()
			isWhitesTurn := ct.room.IsWhitesTurn
			ct.room.mutex.RUnlock()

			timeoutOccurred := false
			var winner string

			// Si c'est le tour des blancs, on décrémente le temps des blancs
			if isWhitesTurn {
				if ct.whiteSeconds <= 0 {
					timeoutOccurred = true
					winner = "black"
				} else {
					ct.whiteSeconds--
					ct.room.WhitesTime = formatTime(ct.whiteSeconds)
				}
			} else {
				if ct.blackSeconds <= 0 {
					timeoutOccurred = true
					winner = "white"
				} else {
					ct.blackSeconds--
					ct.room.BlacksTime = formatTime(ct.blackSeconds)
				}
			}
			ct.mutex.Unlock()

			ct.broadcastTimeUpdate()

			if timeoutOccurred {
				go ct.handleTimeOut(winner)
				return
			}

		case <-ct.stopChan:
			ct.ticker.Stop()
			return
		}
	}
}


func (ct *ChessTimer) SwitchTurn() {
	ct.mutex.Lock()
	defer ct.mutex.Unlock()

	if !ct.isRunning {
		return
	}

	// Changer le tour dans le timer et dans la room de manière atomique
	ct.room.mutex.Lock()
	ct.room.IsWhitesTurn = !ct.room.IsWhitesTurn
	ct.room.mutex.Unlock()

	// Créer une copie locale des valeurs nécessaires
	update := TimerUpdate{
		RoomID:       ct.room.RoomID,
		WhiteTime:    ct.whiteSeconds,
		BlackTime:    ct.blackSeconds,
		IsWhitesTurn: !ct.room.IsWhitesTurn,
	}

	// Broadcaster de manière asynchrone
	go func() {
		message := WebSocketMessage{
			Type:    "time_update",
			Content: string(mustJson(update)),
		}
		ct.room.BroadcastMessage(message)
	}()
}

func (ct *ChessTimer) handleTimeOut(winner string) {
	// Stop the timer first
	ct.Stop()

	// Lock the room for state updates
	ct.room.mutex.Lock()
	ct.room.IsGameOver = true
	ct.room.Status = RoomStatusFinished

	if winner == "white" {
		ct.room.WinnerID = ct.room.WhitePlayer.ID
	} else {
		ct.room.WinnerID = ct.room.BlackPlayer.ID
	}

	// Store usernames and room info before unlocking
	whiteUsername := ct.room.WhitePlayer.Username
	blackUsername := ct.room.BlackPlayer.Username
	roomID := ct.room.RoomID

	// Capture current connections before unlocking
	connections := make(map[string]*SafeConn)
	for username, conn := range ct.room.Connections {
		connections[username] = conn
	}
	ct.room.mutex.Unlock()

	// Create the game over message
	gameOver := map[string]interface{}{
		"gameId":     roomID,
		"winner":     winner,
		"reason":     "timeout",
		"whiteTime":  formatTime(ct.whiteSeconds),
		"blackTime":  formatTime(ct.blackSeconds),
		"winnerId":   ct.room.WinnerID,
		"isGameOver": true,
		"status":     string(RoomStatusFinished),
	}

	gameOverMsg := WebSocketMessage{
		Type:    "game_over",
		Content: string(mustJson(gameOver)),
	}

	// Send the message to all connections
	for _, conn := range connections {
		if err := conn.WriteJSON(gameOverMsg); err != nil {
			log.Printf("Error sending timeout message: %v", err)
		}
	}

	// Clean up the specific room after a short delay
	go func() {
		time.Sleep(200 * time.Millisecond)

		if ct.room.onlineManager != nil {
			// Remove only this room's players from public queue
			ct.room.onlineManager.cleanupPlayerFromPublicQueue(whiteUsername)
			ct.room.onlineManager.cleanupPlayerFromPublicQueue(blackUsername)

			// Update only these players' room status
			ct.room.onlineManager.userStore.UpdateUserRoomStatus(whiteUsername, false)
			ct.room.onlineManager.userStore.UpdateUserRoomStatus(blackUsername, false)

			// Remove only this room
			ct.room.onlineManager.roomManager.RemoveRoom(roomID)

			// Clear only this room's connections
			ct.room.mutex.Lock()
			ct.room.Connections = make(map[string]*SafeConn)
			ct.room.mutex.Unlock()

			// Broadcast updated online users
			go ct.room.onlineManager.broadcastOnlineUsers()
		}
	}()
}

func (ct *ChessTimer) Stop() {
	ct.mutex.Lock()
	defer ct.mutex.Unlock()

	if ct.isRunning {
		close(ct.stopChan)
		ct.ticker.Stop()
		ct.isRunning = false
	}
}

func (ct *ChessTimer) broadcastTimeUpdate() {
	ct.mutex.RLock()
	ct.room.mutex.RLock()
	update := TimerUpdate{
		RoomID:       ct.room.RoomID,
		WhiteTime:    ct.whiteSeconds,
		BlackTime:    ct.blackSeconds,
		IsWhitesTurn: ct.room.IsWhitesTurn,
	}
	ct.room.mutex.RUnlock()
	ct.mutex.RUnlock()

	message := WebSocketMessage{
		Type:    "time_update",
		Content: string(mustJson(update)),
	}

	ct.room.BroadcastMessage(message)
}

// Fonction utilitaire pour formater le temps en string "MM:SS"
func formatTime(seconds int) string {
	minutes := seconds / 60
	remainingSeconds := seconds % 60
	return fmt.Sprintf("%02d:%02d", minutes, remainingSeconds)
}
