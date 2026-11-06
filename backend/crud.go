package main

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
)

type field struct{ name, cast string }
type resource struct {
	table  string
	fields []field
}

func val(v any) any {
	if v == nil {
		return nil
	}
	if s, ok := v.(string); ok && s == "" {
		return nil
	}
	if f, ok := v.(float64); ok {
		return strconv.FormatFloat(f, 'f', -1, 64) // %v would turn 1000000 into "1e+06"
	}
	switch v.(type) {
	case map[string]any, []any:
		b, _ := json.Marshal(v) // jsonb columns (e.g. scans.meta)
		return string(b)
	}
	return fmt.Sprint(v)
}

func (a *App) mount(mux *http.ServeMux, path string, res resource) {
	mux.HandleFunc("GET "+path, a.protect(res.list(a)))
	mux.HandleFunc("POST "+path, a.protect(res.create(a)))
	mux.HandleFunc("GET "+path+"/{id}", a.protect(res.get(a)))
	mux.HandleFunc("PUT "+path+"/{id}", a.protect(res.update(a)))
	mux.HandleFunc("DELETE "+path+"/{id}", a.protect(res.remove(a)))
}

func raw(w http.ResponseWriter, code int, s string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	w.Write([]byte(s))
}

func (res resource) list(a *App) func(http.ResponseWriter, *http.Request, int64) {
	return func(w http.ResponseWriter, r *http.Request, uid int64) {
		var out string
		q := fmt.Sprintf(`SELECT COALESCE(json_agg(t ORDER BY t.created_at DESC),'[]')::text FROM (SELECT * FROM %s WHERE user_id=$1) t`, res.table)
		if err := a.db.QueryRow(r.Context(), q, uid).Scan(&out); err != nil {
			writeErr(w, 500, err.Error())
			return
		}
		raw(w, 200, out)
	}
}

func (res resource) get(a *App) func(http.ResponseWriter, *http.Request, int64) {
	return func(w http.ResponseWriter, r *http.Request, uid int64) {
		var out string
		q := fmt.Sprintf(`SELECT row_to_json(t)::text FROM %s t WHERE user_id=$1 AND id=$2::text::bigint`, res.table)
		if err := a.db.QueryRow(r.Context(), q, uid, r.PathValue("id")).Scan(&out); err != nil {
			writeErr(w, 404, "not found")
			return
		}
		raw(w, 200, out)
	}
}

func (res resource) create(a *App) func(http.ResponseWriter, *http.Request, int64) {
	return func(w http.ResponseWriter, r *http.Request, uid int64) {
		var body map[string]any
		if json.NewDecoder(r.Body).Decode(&body) != nil {
			writeErr(w, 400, "invalid json")
			return
		}
		cols, phs, args := []string{"user_id"}, []string{"$1"}, []any{uid}
		for i, f := range res.fields {
			cols = append(cols, f.name)
			phs = append(phs, fmt.Sprintf("$%d::text::%s", i+2, f.cast))
			args = append(args, val(body[f.name]))
		}
		q := fmt.Sprintf(`WITH r AS (INSERT INTO %s(%s) VALUES(%s) RETURNING *) SELECT row_to_json(r)::text FROM r`,
			res.table, strings.Join(cols, ","), strings.Join(phs, ","))
		var out string
		if err := a.db.QueryRow(r.Context(), q, args...).Scan(&out); err != nil {
			writeErr(w, 400, err.Error())
			return
		}
		raw(w, 201, out)
	}
}

func (res resource) update(a *App) func(http.ResponseWriter, *http.Request, int64) {
	return func(w http.ResponseWriter, r *http.Request, uid int64) {
		var body map[string]any
		if json.NewDecoder(r.Body).Decode(&body) != nil {
			writeErr(w, 400, "invalid json")
			return
		}
		sets, args := []string{}, []any{uid, r.PathValue("id")}
		for _, f := range res.fields {
			if v, ok := body[f.name]; ok {
				args = append(args, val(v))
				sets = append(sets, fmt.Sprintf("%s=$%d::text::%s", f.name, len(args), f.cast))
			}
		}
		if len(sets) == 0 {
			writeErr(w, 400, "nothing to update")
			return
		}
		q := fmt.Sprintf(`WITH r AS (UPDATE %s SET %s WHERE user_id=$1 AND id=$2::text::bigint RETURNING *) SELECT row_to_json(r)::text FROM r`,
			res.table, strings.Join(sets, ","))
		var out string
		if err := a.db.QueryRow(r.Context(), q, args...).Scan(&out); err != nil {
			writeErr(w, 404, "not found")
			return
		}
		raw(w, 200, out)
	}
}

func (res resource) remove(a *App) func(http.ResponseWriter, *http.Request, int64) {
	return func(w http.ResponseWriter, r *http.Request, uid int64) {
		q := fmt.Sprintf(`DELETE FROM %s WHERE user_id=$1 AND id=$2::text::bigint`, res.table)
		a.db.Exec(r.Context(), q, uid, r.PathValue("id"))
		w.WriteHeader(204)
	}
}

// POST /api/upload  (multipart, field "file") -> {"url":"/files/xxxx.ext"}
func (a *App) upload(w http.ResponseWriter, r *http.Request, uid int64) {
	r.Body = http.MaxBytesReader(w, r.Body, 50<<20)
	f, hdr, err := r.FormFile("file")
	if err != nil {
		writeErr(w, 400, "file required")
		return
	}
	defer f.Close()
	b := make([]byte, 12)
	rand.Read(b)
	name := hex.EncodeToString(b) + strings.ToLower(filepath.Ext(hdr.Filename))
	dst, err := os.Create(filepath.Join("uploads", name))
	if err != nil {
		writeErr(w, 500, "save failed")
		return
	}
	defer dst.Close()
	io.Copy(dst, f)
	writeJSON(w, 201, map[string]string{"url": "/files/" + name})
}

// Warranties expiring in next 30 days (or already expired in last 7).
func (a *App) reminders(w http.ResponseWriter, r *http.Request, uid int64) {
	var out string
	err := a.db.QueryRow(r.Context(), `SELECT COALESCE(json_agg(x),'[]')::text FROM (
	  SELECT w.id, a.name AS asset, w.provider, w.expiry_date, (w.expiry_date - CURRENT_DATE) AS days_left
	  FROM warranties w LEFT JOIN assets a ON a.id=w.asset_id
	  WHERE w.user_id=$1 AND w.expiry_date BETWEEN CURRENT_DATE-7 AND CURRENT_DATE+30
	  ORDER BY w.expiry_date) x`, uid).Scan(&out)
	if err != nil {
		writeErr(w, 500, err.Error())
		return
	}
	raw(w, 200, out)
}

// Home report as JSON (frontend turns it into PDF / share).
func (a *App) report(w http.ResponseWriter, r *http.Request, uid int64) {
	var out string
	err := a.db.QueryRow(r.Context(), `SELECT json_build_object(
	 'assets',(SELECT COALESCE(json_agg(t),'[]') FROM assets t WHERE user_id=$1),
	 'warranties',(SELECT COALESCE(json_agg(t),'[]') FROM warranties t WHERE user_id=$1),
	 'repairs',(SELECT COALESCE(json_agg(t),'[]') FROM repairs t WHERE user_id=$1),
	 'documents',(SELECT COALESCE(json_agg(t),'[]') FROM documents t WHERE user_id=$1),
	 'tasks',(SELECT COALESCE(json_agg(t),'[]') FROM tasks t WHERE user_id=$1),
	 'generated_at', now())::text`, uid).Scan(&out)
	if err != nil {
		writeErr(w, 500, err.Error())
		return
	}
	raw(w, 200, out)
}

func (a *App) deviceToken(w http.ResponseWriter, r *http.Request, uid int64) {
	var b struct{ Token string }
	json.NewDecoder(r.Body).Decode(&b)
	a.db.Exec(r.Context(), `INSERT INTO device_tokens(user_id,token) VALUES($1,$2) ON CONFLICT DO NOTHING`, uid, b.Token)
	w.WriteHeader(204)
}