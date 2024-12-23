package service

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strings"
)

func NewUserStore() *UserStore {
	return &UserStore{
		Users: make(map[string]UserProfile),
	}
}

func (us *UserStore) Load() error {
	filename := filepath.Join("users", "users.json")

	// Check file existence outside the mutex
	if _, err := os.Stat(filename); os.IsNotExist(err) {
		// If file doesn't exist, save initial empty store
		return us.Save()
	}

	us.mutex.Lock()
	defer us.mutex.Unlock()

	data, err := os.ReadFile(filename)
	if err != nil {
		return err
	}

	return json.Unmarshal(data, us)
}

func (us *UserStore) Save() error {
	os.MkdirAll("users", os.ModePerm)

	filename := filepath.Join("users", "users.json")
	data, err := json.MarshalIndent(us, "", "  ")
	if err != nil {
		return err
	}

	return os.WriteFile(filename, data, 0644)
}

func (us *UserStore) CreateUser(user UserProfile) error {
	us.mutex.Lock()
	defer us.mutex.Unlock()

	if _, exists := us.Users[user.UserName]; exists {
		return fmt.Errorf("username already exists")
	}

	us.Users[user.UserName] = user
	return us.Save()
}

func (us *UserStore) GetUser(username string) (*UserProfile, error) {
	us.mutex.RLock()
	defer us.mutex.RUnlock()

	user, exists := us.Users[username]
	if !exists {
		return nil, fmt.Errorf("user not found")
	}

	return &user, nil
}

func (us *UserStore) UpdateUserOnlineStatus(username string, isOnline bool,isInRoom bool) error {
	us.mutex.Lock()
	defer us.mutex.Unlock()

	user, exists := us.Users[username]
	if !exists {
		return fmt.Errorf("user not found")
	}

	user.IsOnline = isOnline
	user.IsInRoom=isInRoom
	us.Users[username] = user

	return us.Save()
}

func CreateUserHandler(userStore *UserStore) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {

		var user UserProfile
		err := json.NewDecoder(r.Body).Decode(&user)
		if err != nil {
			log.Printf("Decode error: %v", err)
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}

		user.UserName = strings.TrimSpace(user.UserName)
		if user.UserName == "" {
			log.Println("Empty username")
			http.Error(w, "Username cannot be empty", http.StatusBadRequest)
			return
		}

		// Générer un ID unique
		user.ID = GenerateUniqueID()

		log.Printf("Creating user: %+v", user)

		if err := userStore.CreateUser(user); err != nil {
			log.Printf("Create user error: %v", err)
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}

		// Répondre avec le profil utilisateur
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(user)
	}
}

func GetUserHandler(userStore *UserStore) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		username := r.URL.Query().Get("username")
		user, err := userStore.GetUser(username)
		if err != nil {
			http.Error(w, err.Error(), http.StatusNotFound)
			return
		}

		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(user)
	}
}

func SetupUserStore() *UserStore {
	userStore := NewUserStore()
	if err := userStore.Load(); err != nil {
		panic(err)
	}
	return userStore
}
