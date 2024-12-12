package service

import (
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"log"
	"os"
	"time"
)

func Getenv(key, fallback string) string {
	value := os.Getenv(key)
	if value == "" {
		return fallback
	}
	return value
}

func GenerateUniqueID() string {
	b := make([]byte, 16)
	_, err := rand.Read(b)
	if err != nil {
		return fmt.Sprintf("%d", time.Now().UnixNano())
	}
	return hex.EncodeToString(b)
}

// Optional: Method to log invitation details
func (m *OnlineUsersManager) LogInvitation(invitation InvitationMessage) {
	// Implement logging or persistence of invitations
	log.Printf("Invitation: %s from %s to %s ",
		invitation.Type,
		invitation.FromUsername,
		invitation.ToUsername,
	)
}
