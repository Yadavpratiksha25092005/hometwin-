package main

import (
	"bytes"
	"crypto/rand"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

// Furniture photo -> 3D model (.glb).
//
// The heavy AI work is done by an external image-to-3D service (Meshy). The server only
//   1. accepts the user's furniture photo,
//   2. starts a job at the provider,
//   3. lets the app poll the job, and when it is done downloads the .glb into ./uploads
//      (provider links expire) and returns our own /files/... URL.
//
// Needs env MESHY_API_KEY. Without it the endpoints answer 501 and the app falls back to
// showing the plain photo.
//
// NOTE: check the field names below against the current Meshy docs (https://docs.meshy.ai)
// before going live; provider APIs change.

const meshyURL = "https://api.meshy.ai/openapi/v1/image-to-3d"

var providerHTTP = &http.Client{Timeout: 60 * time.Second}

// POST /api/furniture/3d  (multipart, field "file": jpg/png) -> 202 {"id": 12}
func (a *App) furnitureStart(w http.ResponseWriter, r *http.Request, uid int64) {
	key := os.Getenv("MESHY_API_KEY") // empty -> Tripo (TRIPO_API_KEY)
	r.Body = http.MaxBytesReader(w, r.Body, 80<<20)
	f, hdr, err := r.FormFile("file")
	if err != nil {
		writeErr(w, 400, "file required (photo or video, max 80 MB)")
		return
	}
	defer f.Close()
	img, err := io.ReadAll(f)
	if err != nil || len(img) == 0 {
		writeErr(w, 400, "could not read the file")
		return
	}
	// Video -> take one clear frame with ffmpeg, then continue like a photo.
	ext := strings.ToLower(filepath.Ext(hdr.Filename))
	switch ext {
	case ".mp4", ".mov", ".avi", ".mkv", ".webm", ".3gp", ".m4v":
		frame, ferr := videoFrame(img, ext)
		if ferr != nil {
			writeErr(w, 400, "could not read the video: "+ferr.Error())
			return
		}
		img = frame
	}
	mime := http.DetectContentType(img)
	if mime != "image/jpeg" && mime != "image/png" {
		writeErr(w, 400, "only jpg, png or video files are supported")
		return
	}

	if key == "" {
		if os.Getenv("TRIPO_API_KEY") != "" {
			a.startTripo(w, r, uid, img, mime)
			return
		}
		writeErr(w, 501, "3D generation is not configured on the server (set TRIPO_API_KEY)")
		return
	}
	body, _ := json.Marshal(map[string]any{
		"image_url":        "data:" + mime + ";base64," + base64.StdEncoding.EncodeToString(img),
		"should_texture":   true,
		"enable_pbr":       false,
		"should_remesh":    true,
		"target_polycount": 30000, // keeps the .glb light enough for a phone WebView
	})
	req, _ := http.NewRequestWithContext(r.Context(), "POST", meshyURL, bytes.NewReader(body))
	req.Header.Set("Authorization", "Bearer "+key)
	req.Header.Set("Content-Type", "application/json")
	resp, err := providerHTTP.Do(req)
	if err != nil {
		writeErr(w, 502, "3D service not reachable")
		return
	}
	defer resp.Body.Close()
	var out struct {
		Result  string `json:"result"`
		Message string `json:"message"`
	}
	json.NewDecoder(resp.Body).Decode(&out)
	if resp.StatusCode >= 300 || out.Result == "" {
		msg := out.Message
		if msg == "" {
			msg = fmt.Sprintf("3D service error (%d)", resp.StatusCode)
		}
		writeErr(w, 502, msg)
		return
	}

	var id int64
	err = a.db.QueryRow(r.Context(),
		`INSERT INTO furniture_jobs(user_id, task_id) VALUES($1,$2) RETURNING id`, uid, out.Result).Scan(&id)
	if err != nil {
		writeErr(w, 500, err.Error())
		return
	}
	writeJSON(w, 202, map[string]any{"id": id})
}

// GET /api/furniture/3d/{id} -> {"status":"processing|ready|failed","progress":0-100,"model_url":"/files/x.glb","error":""}
func (a *App) furnitureStatus(w http.ResponseWriter, r *http.Request, uid int64) {
	var taskID, status, modelURL, errMsg string
	var progress int
	err := a.db.QueryRow(r.Context(),
		`SELECT task_id, status, COALESCE(model_url,''), COALESCE(error,''), progress
		   FROM furniture_jobs WHERE user_id=$1 AND id=$2::text::bigint`, uid, r.PathValue("id")).
		Scan(&taskID, &status, &modelURL, &errMsg, &progress)
	if err != nil {
		writeErr(w, 404, "not found")
		return
	}
	reply := func() {
		writeJSON(w, 200, map[string]any{"status": status, "progress": progress, "model_url": modelURL, "error": errMsg})
	}
	if status != "processing" || taskID == "hf" {
		reply()
		return
	}
	if strings.HasPrefix(taskID, "tripo:") {
		st, pr, glb, emsg := tripoTask(r.Context(), strings.TrimPrefix(taskID, "tripo:"))
		switch st {
		case "success":
			file, derr := downloadGLB(glb)
			if derr != nil {
				reply() // try again on the next poll
				return
			}
			status, modelURL, progress = "ready", "/files/"+file, 100
			a.db.Exec(r.Context(), `UPDATE furniture_jobs SET status='ready', model_url=$1, progress=100 WHERE id=$2::text::bigint`,
				modelURL, r.PathValue("id"))
		case "failed":
			status, errMsg = "failed", emsg
			a.db.Exec(r.Context(), `UPDATE furniture_jobs SET status='failed', error=$1 WHERE id=$2::text::bigint`,
				errMsg, r.PathValue("id"))
		default:
			progress = pr
			a.db.Exec(r.Context(), `UPDATE furniture_jobs SET progress=$1 WHERE id=$2::text::bigint`, progress, r.PathValue("id"))
		}
		reply()
		return
	}

	key := os.Getenv("MESHY_API_KEY")
	req, _ := http.NewRequestWithContext(r.Context(), "GET", meshyURL+"/"+taskID, nil)
	req.Header.Set("Authorization", "Bearer "+key)
	resp, err := providerHTTP.Do(req)
	if err != nil {
		reply() // temporary network problem: app simply asks again
		return
	}
	defer resp.Body.Close()
	var t struct {
		Status    string `json:"status"` // PENDING | IN_PROGRESS | SUCCEEDED | FAILED | CANCELED
		Progress  int    `json:"progress"`
		ModelURLs struct {
			GLB string `json:"glb"`
		} `json:"model_urls"`
		TaskError struct {
			Message string `json:"message"`
		} `json:"task_error"`
	}
	json.NewDecoder(resp.Body).Decode(&t)

	switch t.Status {
	case "SUCCEEDED":
		file, derr := downloadGLB(t.ModelURLs.GLB)
		if derr != nil {
			reply() // try again on the next poll
			return
		}
		status, modelURL, progress = "ready", "/files/"+file, 100
		a.db.Exec(r.Context(), `UPDATE furniture_jobs SET status='ready', model_url=$1, progress=100 WHERE id=$2::text::bigint`,
			modelURL, r.PathValue("id"))
	case "FAILED", "CANCELED":
		status = "failed"
		errMsg = t.TaskError.Message
		if errMsg == "" {
			errMsg = "3D generation failed. Try a clearer photo of a single piece."
		}
		a.db.Exec(r.Context(), `UPDATE furniture_jobs SET status='failed', error=$1 WHERE id=$2::text::bigint`,
			errMsg, r.PathValue("id"))
	default:
		progress = t.Progress
		a.db.Exec(r.Context(), `UPDATE furniture_jobs SET progress=$1 WHERE id=$2::text::bigint`, progress, r.PathValue("id"))
	}
	reply()
}

// downloadGLB saves the provider's model into ./uploads and returns the file name.
func downloadGLB(url string) (string, error) {
	if url == "" {
		return "", fmt.Errorf("no model url")
	}
	c := &http.Client{Timeout: 3 * time.Minute}
	resp, err := c.Get(url)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		return "", fmt.Errorf("download failed: %d", resp.StatusCode)
	}
	b := make([]byte, 12)
	rand.Read(b)
	name := "furn_" + hex.EncodeToString(b) + ".glb"
	dst, err := os.Create(filepath.Join("uploads", name))
	if err != nil {
		return "", err
	}
	defer dst.Close()
	if _, err := io.Copy(dst, io.LimitReader(resp.Body, 80<<20)); err != nil {
		return "", err
	}
	return name, nil
}

// videoFrame saves the video to a temp file and grabs one frame (~1s in) as jpg. Needs ffmpeg.
func videoFrame(video []byte, ext string) ([]byte, error) {
	in, err := os.CreateTemp("", "scan_*"+ext)
	if err != nil {
		return nil, err
	}
	defer os.Remove(in.Name())
	if _, err := in.Write(video); err != nil {
		in.Close()
		return nil, err
	}
	in.Close()
	out := in.Name() + ".jpg"
	defer os.Remove(out)
	for _, ss := range []string{"1", "0"} { // very short clips: fall back to first frame
		cmd := exec.Command("ffmpeg", "-y", "-ss", ss, "-i", in.Name(), "-frames:v", "1", "-q:v", "2", out)
		if err := cmd.Run(); err == nil {
			if b, rerr := os.ReadFile(out); rerr == nil && len(b) > 0 {
				return b, nil
			}
		}
	}
	return nil, fmt.Errorf("ffmpeg could not extract a frame")
}