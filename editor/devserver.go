//go:build devserver

// 开发用: 不开窗口, 用 HTTP 提供和桌面版同一套 App 接口, 方便用浏览器 (含无窗口 Chrome) 检查界面。
//
//	go build -tags devserver -ldflags=-linkmode=external -o /tmp/editor-dev . && DEV_DIR=<工程目录> /tmp/editor-dev
//	→ http://127.0.0.1:34115/?open=1&select=npc:1
//
// 选目录的对话框在这里换成环境变量 DEV_DIR。
package main

import (
	"context"
	"encoding/json"
	"io"
	"log"
	"net/http"
	"os"
	"reflect"
	"strings"
)

const mockJS = `
const q = new URLSearchParams(location.search)
window.__devAutoOpen = q.get("open") === "1"
window.__devSelect = q.get("select") || ""
window.go = { main: { App: new Proxy({}, { get: (_, name) => (...args) =>
  fetch("/api/" + name, { method: "POST", body: JSON.stringify(args) })
    .then((r) => r.json()).then((j) => (j.error ? Promise.reject(j.error) : j.result)) }) } }
window.runtime = new Proxy({}, { get: () => () => {} })
`

func main() {
	app := NewApp()
	app.startup(context.Background())
	devDir := os.Getenv("DEV_DIR")
	dist := http.FileServer(http.Dir("frontend/dist"))
	mux := http.NewServeMux()
	mux.Handle("/gamedata/", app.assetHandler())
	mux.Handle("/project/", app.assetHandler())
	mux.HandleFunc("/mock.js", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/javascript")
		io.WriteString(w, mockJS)
	})
	mux.HandleFunc("/api/", func(w http.ResponseWriter, r *http.Request) {
		name := strings.TrimPrefix(r.URL.Path, "/api/")
		log.Println("api", name)
		w.Header().Set("Content-Type", "application/json")
		if name == "ChooseDirectory" || name == "ChooseGameRoot" {
			json.NewEncoder(w).Encode(map[string]any{"result": devDir})
			return
		}
		if name == "ChooseGLB" {
			json.NewEncoder(w).Encode(map[string]any{"result": os.Getenv("DEV_GLB")})
			return
		}
		m := reflect.ValueOf(app).MethodByName(name)
		if !m.IsValid() {
			json.NewEncoder(w).Encode(map[string]any{"error": "没有接口 " + name})
			return
		}
		var raw []json.RawMessage
		json.NewDecoder(r.Body).Decode(&raw)
		args := make([]reflect.Value, m.Type().NumIn())
		for i := range args {
			v := reflect.New(m.Type().In(i))
			if i < len(raw) {
				json.Unmarshal(raw[i], v.Interface())
			}
			args[i] = v.Elem()
		}
		out := m.Call(args)
		res := map[string]any{}
		errType := reflect.TypeOf((*error)(nil)).Elem()
		for i, o := range out {
			if m.Type().Out(i) == errType {
				if !o.IsNil() {
					res["error"] = o.Interface().(error).Error()
				}
				continue
			}
			res["result"] = o.Interface()
		}
		json.NewEncoder(w).Encode(res)
	})
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/" {
			b, _ := os.ReadFile("frontend/dist/index.html")
			io.WriteString(w, strings.Replace(string(b), "<head>", `<head><script src="/mock.js"></script>`, 1))
			return
		}
		dist.ServeHTTP(w, r)
	})
	log.Println("http://127.0.0.1:34115")
	log.Fatal(http.ListenAndServe("127.0.0.1:34115", mux))
}
