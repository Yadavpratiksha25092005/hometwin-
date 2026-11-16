package main

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"strings"
	"time"

	"golang.org/x/crypto/bcrypt"
)

// Web client ID of the Firebase project (client_type 3 in google-services.json).
// The Flutter app passes the same ID as serverClientId, so the ID token's "aud" is this value.
// Override with the GOOGLE_CLIENT_ID env var if it ever changes.
const defaultGoogleClientID = "690646162387-1i02fqiqpfpi30f9rni7tlom0s18c8ra.apps.googleusercontent.com"

func googleClientID() string {
	if v := os.Getenv("GOOGLE_CLIENT_ID"); v != "" {
		return v
	}
	return defaultGoogleClientID
}

// POST /api/auth/google  {"idToken": "..."}
// Verifies the Google ID token, finds the user by email (creates one if new) and returns
// the same {token, user} JSON as /api/auth/login.
func (a *App) googleLogin(w http.ResponseWriter, r *http.Request) {
	var b struct {
		IDToken string `json:"idToken"`
	}
	if json.NewDecoder(io.LimitReader(r.Body, 1<<16)).Decode(&b) != nil || b.IDToken == "" {
		writeErr(w, 400, "idToken required")
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()
	req, _ := http.NewRequestWithContext(ctx, "GET",
		"https://oauth2.googleapis.com/tokeninfo?id_token="+url.QueryEscape(b.IDToken), nil)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		writeErr(w, 502, "could not reach Google to verify the login")
		return
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		writeErr(w, 401, "invalid Google token")
		return
	}

	var t struct {
		Iss           string `json:"iss"`
		Aud           string `json:"aud"`
		Email         string `json:"email"`
		EmailVerified any    `json:"email_verified"`
		Name          string `json:"name"`
	}
	if json.NewDecoder(resp.Body).Decode(&t) != nil {
		writeErr(w, 401, "invalid Google token")
		return
	}
	if t.Aud != googleClientID() {
		writeErr(w, 401, "Google token is for a different app")
		return
	}
	if t.Iss != "accounts.google.com" && t.Iss != "https://accounts.google.com" {
		writeErr(w, 401, "invalid Google token issuer")
		return
	}
	email := strings.ToLower(strings.TrimSpace(t.Email))
	if email == "" || fmt.Sprint(t.EmailVerified) != "true" {
		writeErr(w, 401, "Google account email is not verified")
		return
	}
	name := strings.TrimSpace(t.Name)
	if name == "" {
		name = strings.SplitN(email, "@", 2)[0]
	}

	// New Google users get a random unusable password (password_hash is NOT NULL).
	raw := make([]byte, 32)
	rand.Read(raw)
	hash, _ := bcrypt.GenerateFromPassword([]byte(hex.EncodeToString(raw)), bcrypt.DefaultCost)

	// One statement: create the user, or return the existing one with the same email.
	var id int64
	var dbName string
	err = a.db.QueryRow(r.Context(),
		`INSERT INTO users(name,email,password_hash) VALUES($1,$2,$3)
		 ON CONFLICT (email) DO UPDATE SET email=users.email
		 RETURNING id, name`, name, email, string(hash)).Scan(&id, &dbName)
	if err != nil {
		writeErr(w, 500, "could not sign in")
		return
	}
	welcomeUser(a.db, id, dbName)
	tok, _ := a.token(id)
	writeJSON(w, 200, map[string]any{"token": tok, "user": map[string]any{"id": id, "name": dbName, "email": email}})
}