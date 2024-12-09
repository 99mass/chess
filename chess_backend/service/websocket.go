package service

import (
	"encoding/json"
	"log"
	"net/http"
	"sync"

	"github.com/gorilla/websocket"
)

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
}

// Configuration du WebSocket upgrader
var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool {
		return true // À personnaliser selon vos besoins de sécurité
	},
}

// Créer un nouveau gestionnaire de connexions
func NewOnlineUsersManager(userStore *UserStore) *OnlineUsersManager {
	return &OnlineUsersManager{
		connections: make(map[string]*websocket.Conn),
		userStore:   userStore,
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

	// Ajouter la connexion
	m.mutex.Lock()
	m.connections[username] = conn
	m.mutex.Unlock()

	// Mettre à jour le statut en ligne
	m.userStore.UpdateUserOnlineStatus(username, true)

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
		m.userStore.UpdateUserOnlineStatus(username, false)

		// Notifier les autres clients
		m.broadcastOnlineUsers()

		conn.Close()
	}()

	for {
		// Lire les messages
		_, message, err := conn.ReadMessage()
		if err != nil {
			log.Printf("WebSocket read error for %s: %v", username, err)
			break
		}

		// Traiter le message (optionnel)
		log.Printf("Message from %s: %s", username, string(message))
	}
}

// Diffuser la liste des utilisateurs en ligne
func (m *OnlineUsersManager) broadcastOnlineUsers() {
    m.mutex.RLock()
    defer m.mutex.RUnlock()

    // Préparer la liste des utilisateurs en ligne
    onlineUsers := make([]string, 0, len(m.connections))
    for username := range m.connections {
        onlineUsers = append(onlineUsers, username)
    }

    // Préparer le message
    message := WebSocketMessage{
        Type:    "online_users",
        Content: string(mustJson(onlineUsers)), // Convertir en chaîne JSON
    }

    // Envoyer à tous les clients connectés
    for _, conn := range m.connections {
        conn.WriteJSON(message)
    }
}

// Récupérer la liste des utilisateurs en ligne (pour requête HTTP)
func (m *OnlineUsersManager) GetOnlineUsers(w http.ResponseWriter, r *http.Request) {
	m.mutex.RLock()
	defer m.mutex.RUnlock()

	onlineUsers := make([]string, 0, len(m.connections))
	for username := range m.connections {
		onlineUsers = append(onlineUsers, username)
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string][]string{
		"online_users": onlineUsers,
	})
}

// Utilitaire pour convertir en JSON sans erreur
func mustJson(v interface{}) []byte {
	data, _ := json.Marshal(v)
	return data
}
