package main

import (
	"context"
	"encoding/json"
	"net/http"
	"strings"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"golang.org/x/crypto/bcrypt"
)

type App struct {
	db     *pgxpool.Pool
	secret []byte
}

type ctxKey struct{}

func writeJSON(w http.ResponseWriter, code int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	json.NewEncoder(w).Encode(v)
}

func writeErr(w http.ResponseWriter, code int, msg string) {
	writeJSON(w, code, map[string]string{"error": msg})
}

func (a *App) token(uid int64) (string, error) {
	return jwt.NewWithClaims(jwt.SigningMethodHS256, jwt.MapClaims{
		"sub": uid, "exp": time.Now().Add(30 * 24 * time.Hour).Unix(),
	}).SignedString(a.secret)
}

func (a *App) register(w http.ResponseWriter, r *http.Request) {
	var b struct{ Name, Email, Password, Phone string }
	if json.NewDecoder(r.Body).Decode(&b) != nil || b.Email == "" || len(b.Password) < 6 {
		writeErr(w, 400, "name, email and password (min 6 chars) required")
		return
	}
	hash, _ := bcrypt.GenerateFromPassword([]byte(b.Password), bcrypt.DefaultCost)
	var id int64
	err := a.db.QueryRow(r.Context(),
		`INSERT INTO users(name,email,password_hash,phone) VALUES($1,lower($2),$3,NULLIF($4,'')) RETURNING id`,
		b.Name, b.Email, string(hash), b.Phone).Scan(&id)
	if err != nil {
		writeErr(w, 409, "email already registered")
		return
	}
	t, _ := a.token(id)
	writeJSON(w, 201, map[string]any{"token": t, "user": map[string]any{"id": id, "name": b.Name, "email": b.Email}})
}

func (a *App) login(w http.ResponseWriter, r *http.Request) {
	var b struct{ Email, Password string }
	json.NewDecoder(r.Body).Decode(&b)
	var id int64
	var name, hash string
	err := a.db.QueryRow(r.Context(), `SELECT id,name,password_hash FROM users WHERE email=lower($1)`, b.Email).Scan(&id, &name, &hash)
	if err != nil || bcrypt.CompareHashAndPassword([]byte(hash), []byte(b.Password)) != nil {
		writeErr(w, 401, "invalid credentials")
		return
	}
	t, _ := a.token(id)
	writeJSON(w, 200, map[string]any{"token": t, "user": map[string]any{"id": id, "name": name, "email": b.Email}})
}

func (a *App) protect(next func(http.ResponseWriter, *http.Request, int64)) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		s := strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer ")
		tok, err := jwt.Parse(s, func(t *jwt.Token) (any, error) { return a.secret, nil },
			jwt.WithValidMethods([]string{"HS256"}))
		if err != nil || !tok.Valid {
			writeErr(w, 401, "unauthorized")
			return
		}
		claims, _ := tok.Claims.(jwt.MapClaims)
		sub, _ := claims["sub"].(float64)
		next(w, r.WithContext(context.WithValue(r.Context(), ctxKey{}, int64(sub))), int64(sub))
	}
}