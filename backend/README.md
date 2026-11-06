# Home Digital Twin – Backend (Go + PostgreSQL)

## Run (Docker)
    docker compose up --build

## Run (local)
    go mod tidy
    export DATABASE_URL=postgres://postgres:postgres@localhost:5432/hometwin?sslmode=disable
    export JWT_SECRET=secret
    go run .

Tables auto-create on startup (schema.sql).

## API (Bearer token on all /api/* except auth)
- POST /api/auth/register  {name,email,password}
- POST /api/auth/login     {email,password}
- CRUD: /api/assets, /api/warranties, /api/repairs, /api/documents, /api/scans
- POST /api/upload (multipart "file") -> {url}
- GET  /api/reminders      warranties expiring in 30 days
- GET  /api/export/report  full JSON report
- POST /api/device-token   {token} (for FCM push)
- Files served at /files/<name>

## Production notes
- Uploads go to ./uploads. Swap `upload` in crud.go with AWS S3 SDK for production.
- Push reminders: run a daily cron/goroutine over /reminders query and send via Firebase Admin.
- Set a strong JWT_SECRET and put behind HTTPS.
