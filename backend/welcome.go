package main

import (
	"context"
	"sync/atomic"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

// Set by runPushScheduler once Firebase is configured; stays nil when push is off.
var sharedPusher atomic.Pointer[Pusher]

const welcomeTitle = "Welcome to Home Digital Twin"

func welcomeBody(name string) string {
	if name == "" {
		name = "there"
	}
	return "Hi " + name + ", you're signed in. We'll remind you about tasks and warranties here."
}

// welcomeUser pushes the welcome message to all phones registered for the user (used at login).
// No-op when push isn't configured. Runs in the background so login is never slowed down.
func welcomeUser(db *pgxpool.Pool, uid int64, name string) {
	p := sharedPusher.Load()
	if p == nil {
		return
	}
	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
		defer cancel()
		p.sendToUser(ctx, db, uid, welcomeTitle, welcomeBody(name), map[string]string{"kind": "welcome"})
	}()
}

// welcomeToken pushes the welcome message to one freshly registered phone
// (the first login on a phone: its token only reaches the server after login).
func welcomeToken(db *pgxpool.Pool, uid int64, token string) {
	p := sharedPusher.Load()
	if p == nil {
		return
	}
	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
		defer cancel()
		var name string
		db.QueryRow(ctx, `SELECT name FROM users WHERE id=$1`, uid).Scan(&name)
		ok, invalid := p.send(ctx, token, welcomeTitle, welcomeBody(name), map[string]string{"kind": "welcome"})
		if !ok && invalid {
			db.Exec(ctx, `DELETE FROM device_tokens WHERE user_id=$1 AND token=$2`, uid, token)
		}
	}()
}