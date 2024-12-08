package service

import (
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"
)

type UserProfile struct {
	ID       string `json:"id"`
	UserName string `json:"username"`
	// Ajoutez d'autres champs si nécessaire
}

func CreateUserHandler(w http.ResponseWriter, r *http.Request) {
	var user UserProfile
	err := json.NewDecoder(r.Body).Decode(&user)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	// Validation basique du nom d'utilisateur
	user.UserName = strings.TrimSpace(user.UserName)
	if user.UserName == "" {
		http.Error(w, "Username cannot be empty", http.StatusBadRequest)
		return
	}

	// Générer un ID unique (vous pouvez utiliser un UUID ou autre méthode)
	user.ID = generateUniqueID()

	// Sauvegarder l'utilisateur dans un fichier JSON
	if err := saveUserToFile(user); err != nil {
		http.Error(w, "Failed to save user", http.StatusInternalServerError)
		return
	}

	// Répondre avec le profil utilisateur
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(user)
}

func GetUserHandler(w http.ResponseWriter, r *http.Request) {
	username := r.URL.Query().Get("username")
	user, err := getUserByUsername(username)
	if err != nil {
		http.Error(w, "User not found", http.StatusNotFound)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(user)
}

func saveUserToFile(user UserProfile) error {
	// Assurez-vous que le dossier existe
	usersDir := "users"
	os.MkdirAll(usersDir, os.ModePerm)

	// Chemin du fichier JSON
	filename := filepath.Join(usersDir, user.UserName+".json")

	// Convertir en JSON
	data, err := json.MarshalIndent(user, "", "  ")
	if err != nil {
		return err
	}

	// Écrire dans le fichier
	return os.WriteFile(filename, data, 0644)
}

func getUserByUsername(username string) (*UserProfile, error) {
	filename := filepath.Join("users", username+".json")

	data, err := os.ReadFile(filename)
	if err != nil {
		return nil, err
	}

	var user UserProfile
	err = json.Unmarshal(data, &user)
	if err != nil {
		return nil, err
	}

	return &user, nil
}

func generateUniqueID() string {
	// Implémentation simple, à remplacer par un UUID ou autre méthode
	return fmt.Sprintf("%d", time.Now().UnixNano())
}
