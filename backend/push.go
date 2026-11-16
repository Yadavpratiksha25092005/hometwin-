package main

// Push notifications via Firebase Cloud Messaging (HTTP v1 API).
//
// Setup (one-time, in the Firebase console):
//   1. Firebase project -> Project settings -> Service accounts -> "Generate new private key".
//      This downloads a JSON file. Put its contents in the FIREBASE_CREDENTIALS_JSON env var
//      (or save the file somewhere on the server and point GOOGLE_APPLICATION_CREDENTIALS_FILE at it).
//   2. Set FIREBASE_PROJECT_ID to the Firebase project id (same project the Flutter app uses).
// Without these two env vars push sending is silently disabled (logged once at startup);
// everything else in the app keeps working as before.

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"golang.org/x/oauth2"
	"golang.org/x/oauth2/google"
)

type Pusher struct {
	projectID string
	ts        oauth2.TokenSource
}

// newPusher reads FIREBASE_PROJECT_ID + FIREBASE_CREDENTIALS_JSON (or
// GOOGLE_APPLICATION_CREDENTIALS_FILE) from the environment. Returns nil, false when push is not configured.
func newPusher(ctx context.Context) (*Pusher, bool) {
	projectID := os.Getenv("FIREBASE_PROJECT_ID")
	raw := os.Getenv("FIREBASE_CREDENTIALS_JSON")
	if raw == "" {
		if f := os.Getenv("GOOGLE_APPLICATION_CREDENTIALS_FILE"); f != "" {
			b, err := os.ReadFile(f)
			if err != nil {
				log.Println("push: could not read GOOGLE_APPLICATION_CREDENTIALS_FILE:", err)
				return nil, false
			}
			raw = string(b)
		}
	}
	if projectID == "" || raw == "" {
		log.Println("push: FIREBASE_PROJECT_ID / FIREBASE_CREDENTIALS_JSON not set, push notifications are OFF")
		return nil, false
	}
	creds, err := google.CredentialsFromJSON(ctx, []byte(raw), "https://www.googleapis.com/auth/firebase.messaging")
	if err != nil {
		log.Println("push: bad FIREBASE_CREDENTIALS_JSON:", err)
		return nil, false
	}
	return &Pusher{projectID: projectID, ts: creds.TokenSource}, true
}

// send delivers one notification to a single FCM device token.
// It returns ok=false, invalidToken=true when FCM says the token is unregistered/invalid,
// so the caller can delete it from device_tokens.
func (p *Pusher) send(ctx context.Context, token, title, body string, data map[string]string) (ok bool, invalidToken bool) {
	tok, err := p.ts.Token()
	if err != nil {
		log.Println("push: token error:", err)
		return false, false
	}
	msg := map[string]any{
		"message": map[string]any{
			"token": token,
			"notification": map[string]string{
				"title": title,
				"body":  body,
			},
			"data": data,
			"android": map[string]any{
				"priority": "high",
			},
		},
	}
	b, _ := json.Marshal(msg)
	url := fmt.Sprintf("https://fcm.googleapis.com/v1/projects/%s/messages:send", p.projectID)
	req, _ := http.NewRequestWithContext(ctx, "POST", url, bytes.NewReader(b))
	req.Header.Set("Content-Type", "application/json")
	tok.SetAuthHeader(req)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		log.Println("push: send error:", err)
		return false, false
	}
	defer resp.Body.Close()
	respBody, _ := io.ReadAll(resp.Body)
	if resp.StatusCode == 200 {
		return true, false
	}
	s := string(respBody)
	invalid := resp.StatusCode == 404 || strings.Contains(s, "UNREGISTERED")
	log.Printf("push: FCM error %d: %s", resp.StatusCode, s)
	return false, invalid
}

// sendToUser pushes to every device token the user has registered, dropping tokens FCM rejects.
func (p *Pusher) sendToUser(ctx context.Context, db *pgxpool.Pool, uid int64, title, body string, data map[string]string) bool {
	rows, err := db.Query(ctx, `SELECT token FROM device_tokens WHERE user_id=$1`, uid)
	if err != nil {
		return false
	}
	var tokens []string
	for rows.Next() {
		var t string
		if rows.Scan(&t) == nil {
			tokens = append(tokens, t)
		}
	}
	rows.Close()
	delivered := false
	for _, t := range tokens {
		ok, invalid := p.send(ctx, t, title, body, data)
		if ok {
			delivered = true
		}
		if !ok && invalid {
			db.Exec(ctx, `DELETE FROM device_tokens WHERE user_id=$1 AND token=$2`, uid, t)
		}
	}
	return delivered
}

// ---------- reminder scheduler ----------
//
// Mirrors the frontend's local-notification offsets (notifications.dart) so a push arrives
// even when the app is closed: tasks at 1 day before + on the due date; warranties at
// 30 / 7 / 0 days before expiry. A sent_notifications row keyed by (user_id, reminder_key)
// stops the same reminder being pushed twice.

// negative = overdue: 1, 3 and 7 days after the due date
var taskOffsets = []int{1, 0, -1, -3, -7}
var warrantyOffsets = []int{30, 7, 0}

func ensureSentTable(ctx context.Context, db *pgxpool.Pool) {
	db.Exec(ctx, `CREATE TABLE IF NOT EXISTS sent_notifications (
		user_id BIGINT NOT NULL, reminder_key TEXT NOT NULL, sent_at TIMESTAMPTZ DEFAULT now(),
		PRIMARY KEY (user_id, reminder_key))`)
}

type dueItem struct {
	uid        int64
	kind       string // "task" | "warranty"
	id         int64
	title      string
	offsetDays int
}

// collectDue finds every task/warranty, for every user, that is exactly `offset` days away
// from its due/expiry date today, for each configured offset.
func collectDue(ctx context.Context, db *pgxpool.Pool) []dueItem {
	var out []dueItem
	rows, err := db.Query(ctx, `SELECT user_id, id, title, (due_date - CURRENT_DATE) AS d FROM tasks WHERE due_date IS NOT NULL`)
	if err == nil {
		for rows.Next() {
			var uid, id int64
			var title string
			var d int
			if rows.Scan(&uid, &id, &title, &d) == nil {
				for _, o := range taskOffsets {
					if d == o {
						out = append(out, dueItem{uid, "task", id, title, o})
					}
				}
			}
		}
		rows.Close()
	}
	rows, err = db.Query(ctx, `SELECT w.user_id, w.id, COALESCE(a.name, w.provider, 'Warranty'), (w.expiry_date - CURRENT_DATE) AS d
		FROM warranties w LEFT JOIN assets a ON a.id=w.asset_id WHERE w.expiry_date IS NOT NULL`)
	if err == nil {
		for rows.Next() {
			var uid, id int64
			var title string
			var d int
			if rows.Scan(&uid, &id, &title, &d) == nil {
				for _, o := range warrantyOffsets {
					if d == o {
						out = append(out, dueItem{uid, "warranty", id, title, o})
					}
				}
			}
		}
		rows.Close()
	}
	return out
}

func (it dueItem) key() string { return fmt.Sprintf("%s:%d:%d", it.kind, it.id, it.offsetDays) }

func (it dueItem) notification() (title, body string) {
	if it.kind == "task" {
		if it.offsetDays == 0 {
			return "Maintenance reminder", fmt.Sprintf("%s is due today", it.title)
		}
		if it.offsetDays < 0 {
			return "Maintenance overdue", fmt.Sprintf("%s is overdue by %d day(s)", it.title, -it.offsetDays)
		}
		return "Maintenance reminder", fmt.Sprintf("%s is due tomorrow", it.title)
	}
	if it.offsetDays == 0 {
		return "Warranty reminder", fmt.Sprintf("%s warranty expires today", it.title)
	}
	return "Warranty reminder", fmt.Sprintf("%s warranty expires in %d days", it.title, it.offsetDays)
}

// runPushScheduler checks for due reminders once now and then once every hour, forever.
// Safe to call even when push is not configured (it just logs and returns).
func runPushScheduler(ctx context.Context, db *pgxpool.Pool) {
	pusher, ok := newPusher(ctx)
	if !ok {
		return
	}
	sharedPusher.Store(pusher) // lets login/device-token handlers send the welcome push
	ensureSentTable(ctx, db)
	log.Println("push: scheduler started (project", pusher.projectID+")")

	tick := func() {
		for _, it := range collectDue(ctx, db) {
			var exists int
			db.QueryRow(ctx, `SELECT 1 FROM sent_notifications WHERE user_id=$1 AND reminder_key=$2`, it.uid, it.key()).Scan(&exists)
			if exists == 1 {
				continue
			}
			title, body := it.notification()
			if pusher.sendToUser(ctx, db, it.uid, title, body, map[string]string{"kind": it.kind, "id": fmt.Sprint(it.id)}) {
				db.Exec(ctx, `INSERT INTO sent_notifications(user_id, reminder_key) VALUES($1,$2) ON CONFLICT DO NOTHING`, it.uid, it.key())
			}
		}
	}

	var once sync.Once
	once.Do(tick)
	t := time.NewTicker(time.Hour)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-t.C:
			tick()
		}
	}
}