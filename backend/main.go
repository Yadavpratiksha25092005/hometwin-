package main

import (
	"context"
	_ "embed"
	"log"
	"net/http"
	"os"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

//go:embed schema.sql
var schema string

func env(k, d string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return d
}

func cors(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Headers", "Authorization, Content-Type")
		w.Header().Set("Access-Control-Allow-Methods", "GET,POST,PUT,DELETE,OPTIONS")
		if r.Method == http.MethodOptions {
			w.WriteHeader(204)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func main() {
	ctx := context.Background()
	pool, err := pgxpool.New(ctx, env("DATABASE_URL", "postgres://postgres:postgres@localhost:5432/hometwin?sslmode=disable"))
	if err != nil {
		log.Fatal(err)
	}
	// Docker mein DB thodi der se ready hota hai: 30 sec tak retry karo.
	for i := 0; ; i++ {
		if _, err = pool.Exec(ctx, schema); err == nil {
			break
		}
		if i >= 30 {
			log.Fatal("migrate: ", err)
		}
		log.Println("database ka intezaar...", err)
		time.Sleep(time.Second)
	}
	a := &App{db: pool, secret: []byte(env("JWT_SECRET", "change-me"))}
	os.MkdirAll("uploads", 0o755)

	mux := http.NewServeMux()
	mux.HandleFunc("GET /health", func(w http.ResponseWriter, r *http.Request) { w.Write([]byte("ok")) })
	mux.HandleFunc("POST /api/auth/register", a.register)
	mux.HandleFunc("POST /api/auth/login", a.login)
	mux.Handle("GET /files/", http.StripPrefix("/files/", http.FileServer(http.Dir("uploads"))))
	mux.HandleFunc("POST /api/upload", a.protect(a.upload))
	mux.HandleFunc("GET /api/reminders", a.protect(a.reminders))
	mux.HandleFunc("GET /api/export/report", a.protect(a.report))
	mux.HandleFunc("POST /api/device-token", a.protect(a.deviceToken))
	mux.HandleFunc("POST /api/furniture/3d", a.protect(a.furnitureStart))
	mux.HandleFunc("GET /api/furniture/3d/{id}", a.protect(a.furnitureStatus))

	a.mount(mux, "/api/assets", resource{"assets", []field{
		{"name", "text"}, {"category", "text"}, {"room", "text"}, {"brand", "text"}, {"model", "text"},
		{"serial_no", "text"}, {"purchase_date", "date"}, {"price", "numeric"}, {"notes", "text"}, {"photo_url", "text"}}})
	a.mount(mux, "/api/warranties", resource{"warranties", []field{
		{"asset_id", "bigint"}, {"provider", "text"}, {"start_date", "date"}, {"expiry_date", "date"}, {"notes", "text"}}})
	a.mount(mux, "/api/repairs", resource{"repairs", []field{
		{"asset_id", "bigint"}, {"title", "text"}, {"description", "text"}, {"cost", "numeric"},
		{"repair_date", "date"}, {"service_provider", "text"}}})
	a.mount(mux, "/api/documents", resource{"documents", []field{
		{"asset_id", "bigint"}, {"title", "text"}, {"category", "text"}, {"file_url", "text"}}})
	a.mount(mux, "/api/tasks", resource{"tasks", []field{
		{"asset_id", "bigint"}, {"title", "text"}, {"start_date", "date"}, {"due_date", "date"}, {"notes", "text"}}})
	a.mount(mux, "/api/scans", resource{"scans", []field{
		{"name", "text"}, {"model_url", "text"}, {"notes", "text"}, {"meta", "jsonb"}, {"source", "text"}}})

	addr := ":" + env("PORT", "8080")
	log.Println("listening on", addr)
	log.Fatal(http.ListenAndServe(addr, cors(mux)))
}