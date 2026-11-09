package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"mime/multipart"
	"net/http"
	"net/textproto"
	"os"
	"strings"
)

// Image -> 3D (.glb) with the Tripo API (v3). Used when MESHY_API_KEY is empty and TRIPO_API_KEY is set.
// Env:
//   TRIPO_API_KEY  key from the Tripo platform (starts with tsk_)
//   TRIPO_BASE     optional, default https://openapi.tripo3d.ai/v3  (China: https://openapi.tripo3d.com/v3)

const tripoModel = "v3.1-20260211"

func tripoBase() string {
	if v := strings.TrimRight(os.Getenv("TRIPO_BASE"), "/"); v != "" {
		return v
	}
	return "https://openapi.tripo3d.ai/v3"
}

type tripoResp struct {
	Code    int             `json:"code"`
	Message string          `json:"message"`
	Data    json.RawMessage `json:"data"`
}

// tripoReq does one authenticated call and returns the decoded envelope.
func tripoReq(ctx context.Context, method, url string, body io.Reader, ctype string) (*tripoResp, error) {
	req, err := http.NewRequestWithContext(ctx, method, url, body)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Authorization", "Bearer "+os.Getenv("TRIPO_API_KEY"))
	if ctype != "" {
		req.Header.Set("Content-Type", ctype)
	}
	resp, err := providerHTTP.Do(req)
	if err != nil {
		return nil, fmt.Errorf("3D service not reachable")
	}
	defer resp.Body.Close()
	b, _ := io.ReadAll(io.LimitReader(resp.Body, 4<<20))
	var out tripoResp
	if err := json.Unmarshal(b, &out); err != nil {
		return nil, fmt.Errorf("3D service error (%d)", resp.StatusCode)
	}
	if resp.StatusCode >= 300 || out.Code != 0 {
		msg := out.Message
		if msg == "" {
			msg = fmt.Sprintf("3D service error (%d)", resp.StatusCode)
		}
		return nil, fmt.Errorf("%s", msg)
	}
	return &out, nil
}

// startTripo uploads the photo, creates the task and stores the job (task_id = "tripo:<id>").
func (a *App) startTripo(w http.ResponseWriter, r *http.Request, uid int64, img []byte, mime string) {
	ctx := r.Context()
	base := tripoBase()

	ext := "jpg"
	if mime == "image/png" {
		ext = "png"
	}
	var buf bytes.Buffer
	mw := multipart.NewWriter(&buf)
	h := make(textproto.MIMEHeader)
	h.Set("Content-Disposition", fmt.Sprintf(`form-data; name="file"; filename="in.%s"`, ext))
	h.Set("Content-Type", mime)
	part, _ := mw.CreatePart(h)
	part.Write(img)
	mw.Close()

	up, err := tripoReq(ctx, "POST", base+"/files", &buf, mw.FormDataContentType())
	if err != nil {
		log.Printf("tripo upload failed: %v", err)
		writeErr(w, 502, err.Error())
		return
	}
	var f struct {
		FileToken string `json:"file_token"`
	}
	json.Unmarshal(up.Data, &f)
	if f.FileToken == "" {
		writeErr(w, 502, "3D service did not accept the image")
		return
	}

	body, _ := json.Marshal(map[string]any{
		"input":   f.FileToken,
		"model":   tripoModel,
		"texture": true,
		"pbr":     false,
	})
	tk, err := tripoReq(ctx, "POST", base+"/generation/image-to-model", bytes.NewReader(body), "application/json")
	if err != nil {
		log.Printf("tripo create failed: %v", err)
		writeErr(w, 502, err.Error())
		return
	}
	var t struct {
		TaskID string `json:"task_id"`
	}
	json.Unmarshal(tk.Data, &t)
	if t.TaskID == "" {
		writeErr(w, 502, "3D service did not start the job")
		return
	}

	var id int64
	if err := a.db.QueryRow(ctx,
		`INSERT INTO furniture_jobs(user_id, task_id) VALUES($1,$2) RETURNING id`, uid, "tripo:"+t.TaskID).Scan(&id); err != nil {
		writeErr(w, 500, err.Error())
		return
	}
	writeJSON(w, 202, map[string]any{"id": id})
}

// tripoTask returns status ("success" | "failed" | "running"), progress, the .glb url and an error text.
func tripoTask(ctx context.Context, taskID string) (string, int, string, string) {
	res, err := tripoReq(ctx, "GET", tripoBase()+"/tasks/"+taskID, nil, "")
	if err != nil {
		return "running", 0, "", "" // temporary problem: the app asks again
	}
	var t struct {
		Status   string `json:"status"`
		Progress int    `json:"progress"`
		Output   struct {
			ModelURL string `json:"model_url"`
			PBRModel string `json:"pbr_model"`
			Model    string `json:"model"`
		} `json:"output"`
	}
	json.Unmarshal(res.Data, &t)
	switch strings.ToLower(t.Status) {
	case "success":
		glb := t.Output.ModelURL
		if glb == "" {
			glb = t.Output.PBRModel
		}
		if glb == "" {
			glb = t.Output.Model
		}
		return "success", 100, glb, ""
	case "failed", "cancelled", "banned", "expired":
		return "failed", t.Progress, "", "3D generation failed. Try a clearer photo of a single piece."
	}
	return "running", t.Progress, "", ""
}