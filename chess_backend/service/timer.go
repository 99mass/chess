package service

import (
	"fmt"
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
	roomID       string
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
		roomID:       room.RoomID,
	}
}

func (ct *ChessTimer) Start() {
	ct.mutex.Lock()
	if ct.isRunning {
		ct.mutex.Unlock()
		return
	}

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

			// Vérifier si la room existe toujours
			if ct.room == nil {
				ct.mutex.Unlock()
				return
			}

			ct.room.mutex.RLock()
			isWhitesTurn := ct.room.IsWhitesTurn
			isGameOver := ct.room.IsGameOver
			ct.room.mutex.RUnlock()

			// Ne pas décrémenter si la partie est terminée
			if isGameOver {
				ct.mutex.Unlock()
				continue
			}

			timeoutOccurred := false
			var winner string

			if isWhitesTurn {
				if ct.whiteSeconds <= 0 {
					timeoutOccurred = true
					winner = "black"
				} else {
					ct.whiteSeconds--
				}
			} else {
				if ct.blackSeconds <= 0 {
					timeoutOccurred = true
					winner = "white"
				} else {
					ct.blackSeconds--
				}
			}
			ct.mutex.Unlock()

			// Broadcast seulement si le timer est toujours actif
			if ct.isRunning {
				ct.broadcastTimeUpdate()
			}

			if timeoutOccurred {
				ct.handleTimeOut(winner)
				return
			}

		case <-ct.stopChan:
			if ct.ticker != nil {
				ct.ticker.Stop()
			}
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
	// S'assurer que le timer est arrêté
	ct.Stop()

	ct.room.mutex.Lock()
	roomID := ct.room.RoomID
	whiteUsername := ct.room.WhitePlayer.Username
	blackUsername := ct.room.BlackPlayer.Username

	// Marquer la partie comme terminée
	ct.room.IsGameOver = true

	if winner == "white" {
		ct.room.WinnerID = ct.room.WhitePlayer.ID
	} else {
		ct.room.WinnerID = ct.room.BlackPlayer.ID
	}

	// Copier les connexions nécessaires
	connections := make(map[string]*SafeConn)
	for username, conn := range ct.room.Connections {
		connections[username] = conn
	}
	ct.room.mutex.Unlock()

	// Envoyer le message de fin de partie
	gameOver := map[string]interface{}{
		"gameId":    roomID,
		"winner":    winner,
		"reason":    "timeout",
		"whiteTime": formatTime(ct.whiteSeconds),
		"blackTime": formatTime(ct.blackSeconds),
		"winnerId":  ct.room.WinnerID,
	}

	// Envoyer aux deux joueurs
	for _, conn := range connections {
		conn.WriteJSON(WebSocketMessage{
			Type:    "game_over",
			Content: string(mustJson(gameOver)),
		})
	}

	// Nettoyer la room après un court délai
	go func() {
		time.Sleep(200 * time.Millisecond)
		if ct.room.onlineManager != nil {
			// Nettoyer uniquement les joueurs de cette room
			ct.room.onlineManager.cleanupPlayerFromPublicQueue(whiteUsername)
			ct.room.onlineManager.cleanupPlayerFromPublicQueue(blackUsername)

			// Mettre à jour le statut des joueurs
			ct.room.onlineManager.userStore.UpdateUserRoomStatus(whiteUsername, false)
			ct.room.onlineManager.userStore.UpdateUserRoomStatus(blackUsername, false)

			// Supprimer uniquement cette room
			ct.room.onlineManager.roomManager.RemoveSpecificRoom(roomID)
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
	defer ct.mutex.RUnlock()

	// Vérifier si la room existe toujours
	if ct.room == nil {
		return
	}

	ct.room.mutex.RLock()
	isWhitesTurn := ct.room.IsWhitesTurn
	roomID := ct.room.RoomID
	ct.room.mutex.RUnlock()

	update := TimerUpdate{
		RoomID:       roomID,
		WhiteTime:    ct.whiteSeconds,
		BlackTime:    ct.blackSeconds,
		IsWhitesTurn: isWhitesTurn,
	}

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
