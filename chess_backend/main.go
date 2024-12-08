package main

import (
	service "chess_backend/service"
	"log"
	"net/http"
	"os"

	"github.com/gorilla/mux"
	// "github.com/gorilla/websocket"
)

// const (
// 	ColorWhite = "white"
// 	ColorBlack = "black"
// )

// type ChessRoom struct {
// 	ID      string
// 	Clients map[string]*ChessClient
// }
// type ChessClient struct {
// 	ID                  string
// 	Color               string
// 	RoomID              string
// 	ActiveConn          *websocket.Conn
// 	ChanNotifyWhenReady chan bool
// }

// var upgrader = websocket.Upgrader{
// 	CheckOrigin: func(r *http.Request) bool {
// 		return true
// 	},
// }

// func main() {
// 	var (
// 		router = mux.NewRouter()
// 		port   = getenv("PORT", "8080")
// 	)

// 	router.HandleFunc("/rooms", http.NotFound)
// 	router.HandleFunc("/rooms/{client_id}", http.NotFound)
// 	http.Handle("/", router)
// 	log.Printf("running chess server on port :%s...", port)
// 	if err := http.ListenAndServe(":"+port, nil); err != nil {
// 		log.Println(err)
// 	}
// }

func main() {
	router := mux.NewRouter()

	// Routes pour la gestion des utilisateurs
	router.HandleFunc("/user", service.CreateUserHandler).Methods("POST")
	router.HandleFunc("/user", service.GetUserHandler).Methods("GET")

	port := getenv("PORT", "8080")
	log.Printf("Running user management server on port :%s...", port)

	if err := http.ListenAndServe(":"+port, router); err != nil {
		log.Println(err)
	}
}

func getenv(key, fallback string) string {
	value := os.Getenv(key)
	if value == "" {
		return fallback
	}
	return value
}
