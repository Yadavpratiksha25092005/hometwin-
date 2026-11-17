package main

import (
	"encoding/json"
	"io"
	"net/http"
	"os"
	"strings"

	"golang.org/x/crypto/bcrypt"
)

// DEMO ONLY: the OTP for "Forgot password" is a fixed code (default 123456).
// Set the RESET_OTP env var to change it, or RESET_OTP=off to switch password reset off.
// Replace this with a real emailed one-time code before real users use the app.
func resetOTP() string {
	if v := os.Getenv("RESET_OTP"); v != "" {
		return v
	}
	return "123456"
}

// POST /api/auth/reset-password  {"email": "...", "otp": "...", "password": "new password"}
func (a *App) resetPassword(w http.ResponseWriter, r *http.Request) {
	otp := resetOTP()
	if otp == "off" {
		writeErr(w, 503, "password reset is switched off on this server")
		return
	}
	var b struct {
		Email    string `json:"email"`
		OTP      string `json:"otp"`
		Password string `json:"password"`
	}
	if json.NewDecoder(io.LimitReader(r.Body, 1<<16)).Decode(&b) != nil || strings.TrimSpace(b.Email) == "" {
		writeErr(w, 400, "email, otp and new password required")
		return
	}
	if b.OTP != otp {
		writeErr(w, 400, "wrong OTP")
		return
	}
	if len(b.Password) < 6 {
		writeErr(w, 400, "password (min 6 chars) required")
		return
	}
	hash, _ := bcrypt.GenerateFromPassword([]byte(b.Password), bcrypt.DefaultCost)
	tag, err := a.db.Exec(r.Context(), `UPDATE users SET password_hash=$1 WHERE email=lower($2)`, string(hash), strings.TrimSpace(b.Email))
	if err != nil {
		writeErr(w, 500, "could not reset password")
		return
	}
	if tag.RowsAffected() == 0 {
		writeErr(w, 404, "no account found with this email")
		return
	}
	writeJSON(w, 200, map[string]any{"ok": true})
}
