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

	ct.isRunning = true
	ct.ticker = time.NewTicker(1 * time.Second)
	ct.mutex.Unlock()

	go ct.runTimer()
}

func (ct *ChessTimer) runTimer() {
	for {
		select {
		case <-ct.ticker.C:
			ct.mutex.Lock()
			if ct.room.IsWhitesTurn {
				ct.whiteSeconds--
				ct.room.WhitesTime = formatTime(ct.whiteSeconds)
				if ct.whiteSeconds <= 0 {
					ct.handleTimeOut("black") // Les noirs gagnent
					ct.mutex.Unlock()
					return
				}
			} else {
				ct.blackSeconds--
				ct.room.BlacksTime = formatTime(ct.blackSeconds)
				if ct.blackSeconds <= 0 {
					ct.handleTimeOut("white") // Les blancs gagnent
					ct.mutex.Unlock()
					return
				}
			}

			ct.broadcastTimeUpdate()
			ct.mutex.Unlock()

		case <-ct.stopChan:
			ct.ticker.Stop()
			return
		}
	}
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

func (ct *ChessTimer) SwitchTurn() {
	ct.mutex.Lock()
	defer ct.mutex.Unlock()

	ct.room.IsWhitesTurn = !ct.room.IsWhitesTurn
	ct.broadcastTimeUpdate()
}

func (ct *ChessTimer) broadcastTimeUpdate() {
	update := TimerUpdate{
		RoomID:       ct.room.RoomID,
		WhiteTime:    ct.whiteSeconds,
		BlackTime:    ct.blackSeconds,
		IsWhitesTurn: ct.room.IsWhitesTurn,
	}

	message := WebSocketMessage{
		Type:    "time_update",
		Content: string(mustJson(update)),
	}

	ct.room.BroadcastMessage(message)
}

func (ct *ChessTimer) handleTimeOut(winner string) {
	ct.Stop()

	// Mettre à jour l'état de la partie
	ct.room.IsGameOver = true
	ct.room.Status = RoomStatusFinished

	if winner == "white" {
		ct.room.WinnerID = ct.room.WhitePlayer.ID
	} else {
		ct.room.WinnerID = ct.room.BlackPlayer.ID
	}

	// Préparer le message de fin de partie
	gameOver := map[string]interface{}{
		"gameId":     ct.room.RoomID,
		"winner":     winner,
		"reason":     "timeout",
		"whiteTime":  formatTime(ct.whiteSeconds),
		"blackTime":  formatTime(ct.blackSeconds),
		"winnerId":   ct.room.WinnerID,
		"isGameOver": true,
		"status":     string(RoomStatusFinished),
	}

	message := WebSocketMessage{
		Type:    "game_over",
		Content: string(mustJson(gameOver)),
	}

	ct.room.BroadcastMessage(message)
}

// Fonction utilitaire pour formater le temps en string "MM:SS"
func formatTime(seconds int) string {
	minutes := seconds / 60
	remainingSeconds := seconds % 60
	return fmt.Sprintf("%02d:%02d", minutes, remainingSeconds)
}
