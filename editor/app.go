package main

import (
	"context"
	"crypto/rand"
	"crypto/rsa"
	"crypto/x509"
	"encoding/json"
	"encoding/pem"
	"errors"
	"fmt"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"sync"

	"czt/podtool/pod"
	"editor/internal/gamedata"
	"editor/internal/project"

	"github.com/wailsapp/wails/v2/pkg/runtime"
)

// 编辑器设置 (~/.config/czt-editor/config.json)
type Config struct {
	GameRoot string `json:"gameRoot"` // 复刻工程根目录 (含 godot/、extracted/)
	Godot    string `json:"godot"`    // Godot 可执行文件
}

type App struct {
	ctx     context.Context
	cfg     Config
	mu      sync.Mutex
	store   *gamedata.Store
	projDir string // 当前工程目录 (/project/ 预览自定义模型用)
}

func NewApp() *App { return &App{} }

func configPath() string {
	home, _ := os.UserHomeDir()
	return filepath.Join(home, ".config", "czt-editor", "config.json")
}

func authorKeyPath() string {
	if p := os.Getenv("CZT_AUTHOR_KEY"); p != "" { // 测试用, 不碰真正的作者密钥
		return p
	}
	home, _ := os.UserHomeDir()
	return filepath.Join(home, ".config", "czt-pod", "author.pem") // 和 tools/podtool 共用
}

func (a *App) startup(ctx context.Context) {
	a.ctx = ctx
	if b, err := os.ReadFile(configPath()); err == nil {
		json.Unmarshal(b, &a.cfg)
	}
	if a.cfg.Godot == "" {
		a.cfg.Godot = "/Applications/Godot-stable.app/Contents/MacOS/Godot"
	}
	if !isGameRoot(a.cfg.GameRoot) {
		a.cfg.GameRoot = findGameRoot()
	}
}

// findGameRoot: 不用玩家选 —— 从编辑器程序所在位置、当前目录往上找复刻工程 (含 godot/project.godot,
// 且按游戏的规则能找到提取数据)。.app 用 open 启动时当前目录是 /, 所以先看程序自己的位置
func findGameRoot() string {
	var starts []string
	if exe, err := os.Executable(); err == nil {
		if r, err := filepath.EvalSymlinks(exe); err == nil {
			exe = r
		}
		starts = append(starts, filepath.Dir(exe))
	}
	if wd, err := os.Getwd(); err == nil {
		starts = append(starts, wd)
	}
	for _, s := range starts {
		for d, i := s, 0; i < 10; d, i = filepath.Dir(d), i+1 {
			if isGameRoot(d) {
				return d
			}
			if filepath.Dir(d) == d {
				break
			}
		}
	}
	return ""
}

func isGameRoot(dir string) bool {
	if dir == "" {
		return false
	}
	if _, err := os.Stat(filepath.Join(dir, "godot", "project.godot")); err != nil {
		return false
	}
	_, err := os.Stat(filepath.Join(extractedDir(dir), "game", "maps.json"))
	return err == nil
}

// extractedDir: 提取数据的位置, 规则同游戏 (godot/scripts/game.gd _load_paths):
// 用户设置 user://settings.cfg > 工程里的 godot/local_paths.cfg > 默认 <工程>/extracted
func extractedDir(root string) string {
	dir := filepath.Join(root, "extracted")
	if v := cfgValue(filepath.Join(root, "godot", "local_paths.cfg"), "paths", "extracted_dir"); v != "" {
		dir = v
	}
	if v := cfgValue(godotUserSettings(root), "paths", "extracted_dir"); v != "" {
		dir = v
	}
	return dir
}

// godotUserSettings: 游戏的 user://settings.cfg (Godot 默认用户目录 = app_userdata/<config/name>)
func godotUserSettings(root string) string {
	name := cfgValue(filepath.Join(root, "godot", "project.godot"), "application", "config/name")
	if name == "" {
		return ""
	}
	home, _ := os.UserHomeDir()
	return filepath.Join(home, "Library", "Application Support", "Godot", "app_userdata", name, "settings.cfg")
}

// cfgValue: 读 Godot ConfigFile (ini 风格) 里 [section] key="字符串" 的值
func cfgValue(path, section, key string) string {
	b, err := os.ReadFile(path)
	if err != nil {
		return ""
	}
	cur := ""
	for _, line := range strings.Split(string(b), "\n") {
		line = strings.TrimSpace(line)
		if strings.HasPrefix(line, "[") && strings.HasSuffix(line, "]") {
			cur = line[1 : len(line)-1]
			continue
		}
		if cur != section {
			continue
		}
		if k, v, ok := strings.Cut(line, "="); ok && strings.TrimSpace(k) == key {
			v = strings.TrimSpace(v)
			if uq, err := strconv.Unquote(v); err == nil {
				return uq
			}
			return strings.Trim(v, "\"")
		}
	}
	return ""
}

func (a *App) saveConfig() error {
	b, _ := json.MarshalIndent(a.cfg, "", "  ")
	os.MkdirAll(filepath.Dir(configPath()), 0o700)
	return os.WriteFile(configPath(), b, 0o600)
}

func (a *App) data() (*gamedata.Store, error) {
	a.mu.Lock()
	defer a.mu.Unlock()
	if a.store != nil {
		return a.store, nil
	}
	if !isGameRoot(a.cfg.GameRoot) {
		return nil, errors.New("还没有找到游戏数据，请先选择复刻工程目录")
	}
	s, err := gamedata.Open(extractedDir(a.cfg.GameRoot))
	if err != nil {
		return nil, err
	}
	a.store = s
	if ops, err := s.Opcodes(); err == nil { // 校验方案里的指令要知道哪些参数是跳转
		m := map[string]string{}
		for name, o := range ops {
			m[name] = o.Operands
		}
		project.SetJumpOperands(m)
	}
	return s, nil
}

// ---------------- 状态 / 设置 ----------------

type Status struct {
	GameRoot  string `json:"gameRoot"`
	DataOK    bool   `json:"dataOk"`
	Error     string `json:"error"`
	Godot     string `json:"godot"`
	GodotOK   bool   `json:"godotOk"`
	AuthorKey bool   `json:"authorKey"`
}

func (a *App) GetStatus() Status {
	st := Status{GameRoot: a.cfg.GameRoot, Godot: a.cfg.Godot}
	if _, err := a.data(); err != nil {
		st.Error = err.Error()
	} else {
		st.DataOK = true
	}
	if _, err := os.Stat(a.cfg.Godot); err == nil {
		st.GodotOK = true
	}
	if _, err := os.Stat(authorKeyPath()); err == nil {
		st.AuthorKey = true
	}
	return st
}

// ChooseGameRoot: 选复刻工程目录 (取消返回空字符串)
func (a *App) ChooseGameRoot() (string, error) {
	dir, err := runtime.OpenDirectoryDialog(a.ctx, runtime.OpenDialogOptions{Title: "选择复刻工程目录（含 godot 和 extracted）"})
	if err != nil || dir == "" {
		return "", err
	}
	if !isGameRoot(dir) {
		return "", errors.New("这个目录里没有 godot/project.godot 和 extracted/game/maps.json")
	}
	a.mu.Lock()
	a.cfg.GameRoot, a.store = dir, nil
	a.mu.Unlock()
	return dir, a.saveConfig()
}

// ---------------- 游戏数据 ----------------

func (a *App) ListMaps() ([]gamedata.MapInfo, error) {
	s, err := a.data()
	if err != nil {
		return nil, err
	}
	return s.Maps(), nil
}

func (a *App) GetMap(id int) (*gamedata.MapDetail, error) {
	s, err := a.data()
	if err != nil {
		return nil, err
	}
	return s.Map(id)
}

func (a *App) ListModels() ([]gamedata.Model, error) {
	s, err := a.data()
	if err != nil {
		return nil, err
	}
	return s.Models(), nil
}

type Floor struct {
	Y  float64 `json:"y"`
	OK bool    `json:"ok"`
}

// FloorAt: 点击位置贴到碰撞地面上 (同游戏规则, 在 yHint ± 300 内找最近的一层)
func (a *App) FloorAt(mapID int, x, z, yHint float64) Floor {
	s, err := a.data()
	if err != nil {
		return Floor{}
	}
	y, ok := s.FloorAt(mapID, x, z, yHint, 300)
	return Floor{y, ok}
}

// ListItems: 原版物品 (新建 mod 物品时选复制哪个)
func (a *App) ListItems() ([]gamedata.Item, error) {
	s, err := a.data()
	if err != nil {
		return nil, err
	}
	return s.Items()
}

// ListChapters: 原版剧情线路 (只读浏览): 有剧情快照时按真实游玩顺序排
func (a *App) ListChapters() ([]gamedata.Chapter, error) {
	s, err := a.data()
	if err != nil {
		return nil, err
	}
	return s.StoryLine()
}

// GetSnapshot: 事件开始前那一刻在场的角色 (没有快照返回 null)
func (a *App) GetSnapshot(eid int) (*gamedata.Snapshot, error) {
	s, err := a.data()
	if err != nil {
		return nil, err
	}
	return s.Snapshot(eid)
}

// PlayEvent: 播放预览 —— 从剧情快照 (事件开始前那一刻) 启动游戏播这个事件; 传了方案就连方案一起加载 (看改过的效果)
func (a *App) PlayEvent(eid int, p *project.Project) error {
	s, err := a.data()
	if err != nil {
		return err
	}
	snap, from := s.SnapshotFor(eid) // 没触发到的事件借同一张地图的快照
	if snap == "" {
		return fmt.Errorf("事件 #%d 所在的地图还没有剧情快照（自动通关没去过），暂时不能播放预览", eid)
	}
	if _, err := os.Stat(a.cfg.Godot); err != nil {
		return fmt.Errorf("找不到 Godot：%s", a.cfg.Godot)
	}
	args := []string{"--path", filepath.Join(a.cfg.GameRoot, "godot"), "res://scenes/field.tscn", "--", "--snapshot=" + snap, fmt.Sprintf("--event=%d", eid)}
	if from != 0 {
		args = append(args, "--preview-talk") // 借来的快照: 是 NPC 对话事件就先站到那个 NPC 旁边再按原版对话流程开始
	}
	if p != nil && p.Dir != "" {
		if is := p.Validate(); hasErrors(is) {
			return fmt.Errorf("方案还有 %d 个错误，先修好再预览", countErr(is))
		}
		if err := p.Save(); err != nil {
			return err
		}
		args = append(args, "--mod="+p.Dir)
	}
	cmd := exec.Command(a.cfg.Godot, args...)
	cmd.Dir = filepath.Join(a.cfg.GameRoot, "godot")
	return cmd.Start()
}

// GetEvent: 原版事件的指令和概要 (只读浏览)
func (a *App) GetEvent(id int) (*gamedata.EventInfo, error) {
	s, err := a.data()
	if err != nil {
		return nil, err
	}
	return s.Event(id)
}

// GetNames: 角色 / 物品 / 战场的名字 (显示指令参数用)
func (a *App) GetNames() (gamedata.Names, error) {
	s, err := a.data()
	if err != nil {
		return gamedata.Names{}, err
	}
	return s.Names(), nil
}

// ListOpcodes: 事件指令表 (助记符 → 操作数类型 / 说明)
func (a *App) ListOpcodes() (map[string]gamedata.Opcode, error) {
	s, err := a.data()
	if err != nil {
		return nil, err
	}
	return s.Opcodes()
}

// GetMembers: 三名队员的原版数据和原版开局 (改队员 / 开局时参考)
func (a *App) GetMembers() (map[string]any, error) {
	s, err := a.data()
	if err != nil {
		return nil, err
	}
	ms, ng, err := s.Members()
	if err != nil {
		return nil, err
	}
	return map[string]any{"members": ms, "newGame": ng}, nil
}

// ListSkills: 原版技能 (复制成新技能 / 改原版技能)
func (a *App) ListSkills() ([]gamedata.Skill, error) {
	s, err := a.data()
	if err != nil {
		return nil, err
	}
	return s.Skills()
}

// ListMonsters: 原版怪物 (新建 mod 怪物时选复制哪只; 战斗站位选怪物)
func (a *App) ListMonsters() ([]gamedata.Monster, error) {
	s, err := a.data()
	if err != nil {
		return nil, err
	}
	return s.Monsters()
}

// ListBattlefields: 原版普通战场 (新建 mod 战斗时选底子)
func (a *App) ListBattlefields() ([]gamedata.Battlefield, error) {
	s, err := a.data()
	if err != nil {
		return nil, err
	}
	return s.Battlefields()
}

func (a *App) ItemName(id int) string {
	if s, err := a.data(); err == nil {
		return s.ItemName(id)
	}
	return ""
}

// ---------------- 工程 ----------------

func (a *App) ChooseDirectory(title string) (string, error) {
	return runtime.OpenDirectoryDialog(a.ctx, runtime.OpenDialogOptions{Title: title, CanCreateDirectories: true})
}

func (a *App) NewProject(dir string, m project.Manifest) (*project.Project, error) {
	if dir == "" {
		return nil, errors.New("请选择工程目录")
	}
	p, err := project.New(dir, m)
	if err == nil {
		a.projDir = dir
	}
	return p, err
}

func (a *App) OpenProject(dir string) (*project.Project, error) {
	p, err := project.Open(dir)
	if err == nil {
		a.projDir = dir
	}
	return p, err
}

func (a *App) SaveProject(p project.Project) error {
	if p.Dir == "" {
		return errors.New("工程目录为空")
	}
	a.projDir = p.Dir
	return p.Save()
}

// ChooseGLB: 选要导入的模型文件 (取消返回空字符串)
func (a *App) ChooseGLB() (string, error) {
	return runtime.OpenFileDialog(a.ctx, runtime.OpenDialogOptions{Title: "导入模型（.glb）",
		Filters: []runtime.FileFilter{{DisplayName: "glTF 二进制 (*.glb)", Pattern: "*.glb"}}})
}

type ImportResult struct {
	Model project.Model   `json:"model"`
	Info  project.GLBInfo `json:"info"`
}

// ImportModel: 检查 GLB 后复制进工程的 models/ (要保存工程后才写进 models.json; 没保存就删掉的, 下次保存时清理文件)
func (a *App) ImportModel(p project.Project, src string) (*ImportResult, error) {
	if p.Dir == "" {
		return nil, errors.New("工程目录为空")
	}
	m, info, err := p.ImportModel(src)
	if err != nil {
		return nil, err
	}
	a.projDir = p.Dir
	return &ImportResult{Model: *m, Info: *info}, nil
}

// ReplaceModel: 给已有模型换 .glb 文件 (返回更新后的模型, 前端替换工程里同编号的那个)
func (a *App) ReplaceModel(p project.Project, local int, src string) (*ImportResult, error) {
	if p.Dir == "" {
		return nil, errors.New("工程目录为空")
	}
	m, info, err := p.ReplaceModel(local, src)
	if err != nil {
		return nil, err
	}
	a.projDir = p.Dir
	return &ImportResult{Model: *m, Info: *info}, nil
}

func (a *App) Validate(p project.Project) []project.Issue {
	issues := p.Validate()
	if s, err := a.data(); err == nil {
		if ops, err := s.Opcodes(); err == nil {
			for _, o := range p.Overrides {
				for _, ins := range o.Code {
					if len(ins) > 1 {
						if name, _ := ins[1].(string); ops[name].Name == "" {
							issues = append(issues, project.Issue{Level: "error", Where: fmt.Sprintf("改原版事件 #%d", o.ID), Message: fmt.Sprintf("@%v 的指令「%v」原版里没有", ins[0], ins[1])})
						}
					}
				}
			}
		}
	}
	if issues == nil {
		return []project.Issue{}
	}
	return issues
}

func hasErrors(is []project.Issue) bool {
	for _, i := range is {
		if i.Level == "error" {
			return true
		}
	}
	return false
}

// PlayTest: 保存后用 --mod=工程目录 启动游戏, 直接进指定地图的指定位置 (不等游戏退出)
func (a *App) PlayTest(p project.Project, mapID int, pos [3]float64) error {
	if is := p.Validate(); hasErrors(is) {
		return fmt.Errorf("工程还有 %d 个错误，先修好再试玩", countErr(is))
	}
	if err := p.Save(); err != nil {
		return err
	}
	if _, err := os.Stat(a.cfg.Godot); err != nil {
		return fmt.Errorf("找不到 Godot：%s", a.cfg.Godot)
	}
	cmd := exec.Command(a.cfg.Godot, "--path", filepath.Join(a.cfg.GameRoot, "godot"), "res://scenes/field.tscn", "--",
		"--mod="+p.Dir, fmt.Sprintf("--map=%d", mapID), fmt.Sprintf("--pos=%d,%d,%d", int(pos[0]), int(pos[1]), int(pos[2])))
	cmd.Dir = filepath.Join(a.cfg.GameRoot, "godot")
	return cmd.Start()
}

func countErr(is []project.Issue) int {
	n := 0
	for _, i := range is {
		if i.Level == "error" {
			n++
		}
	}
	return n
}

// CreateAuthorKey: 生成作者签名密钥 (只在没有时生成, 不覆盖)
func (a *App) CreateAuthorKey() error {
	p := authorKeyPath()
	if _, err := os.Stat(p); err == nil {
		return errors.New("作者密钥已经存在")
	}
	k, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		return err
	}
	os.MkdirAll(filepath.Dir(p), 0o700)
	return os.WriteFile(p, pem.EncodeToMemory(&pem.Block{Type: "RSA PRIVATE KEY", Bytes: x509.MarshalPKCS1PrivateKey(k)}), 0o600)
}

type PackResult struct {
	Path        string `json:"path"`
	Size        int    `json:"size"`
	Files       int    `json:"files"`
	Fingerprint string `json:"fingerprint"`
}

// packBytes: 校验 → 保存 → 打包并自检 (没有作者密钥时返回 NO_AUTHOR_KEY, 前端据此询问生成)
func (a *App) packBytes(p project.Project) ([]byte, *pod.Unpacked, error) {
	if is := p.Validate(); hasErrors(is) {
		return nil, nil, fmt.Errorf("工程还有 %d 个错误，先修好再打包", countErr(is))
	}
	if err := p.Save(); err != nil {
		return nil, nil, err
	}
	kb, err := os.ReadFile(authorKeyPath())
	if err != nil {
		return nil, nil, errors.New("NO_AUTHOR_KEY")
	}
	blk, _ := pem.Decode(kb)
	if blk == nil {
		return nil, nil, errors.New("作者密钥文件损坏")
	}
	key, err := x509.ParsePKCS1PrivateKey(blk.Bytes)
	if err != nil {
		return nil, nil, errors.New("作者密钥文件损坏")
	}
	data, err := pod.Pack(p.Dir, p.Manifest.ID, key)
	if err != nil {
		return nil, nil, err
	}
	u, err := pod.Unpack(data)
	if err != nil {
		return nil, nil, fmt.Errorf("打包后自检失败: %w", err)
	}
	return data, u, nil
}

// PackPod: 打包成 .pod, 写到工程目录旁边 (<目录名>.pod)
func (a *App) PackPod(p project.Project) (*PackResult, error) {
	data, u, err := a.packBytes(p)
	if err != nil {
		return nil, err
	}
	out := strings.TrimRight(p.Dir, string(os.PathSeparator)) + ".pod"
	if err := os.WriteFile(out, data, 0o644); err != nil {
		return nil, err
	}
	return &PackResult{Path: out, Size: len(data), Files: len(u.Files), Fingerprint: u.Fingerprint}, nil
}

func (a *App) RevealInFinder(path string) error {
	return exec.Command("open", "-R", path).Start()
}

// ---------------- 本地游戏数据 (前端 three.js 读场景 / 模型 GLB) ----------------

// assetHandler: /gamedata/<相对 extracted 的路径>, 只允许 scenes/ 和 game/actors/ 下的 .glb / .json
func (a *App) assetHandler() http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if pr, ok := strings.CutPrefix(r.URL.Path, "/project/"); ok {
			// 当前工程里导入的模型 (只读, 只限 models/*.glb)
			pr = filepath.Clean(pr)
			if a.projDir == "" || strings.Contains(pr, "..") || !strings.HasPrefix(pr, "models/") || !strings.HasSuffix(pr, ".glb") {
				http.Error(w, "forbidden", http.StatusForbidden)
				return
			}
			w.Header().Set("Cache-Control", "no-store")
			http.ServeFile(w, r, filepath.Join(a.projDir, pr))
			return
		}
		rel, ok := strings.CutPrefix(r.URL.Path, "/gamedata/")
		if !ok {
			http.NotFound(w, r)
			return
		}
		rel = filepath.Clean(rel)
		okGame := (strings.HasPrefix(rel, "scenes/") || strings.HasPrefix(rel, "game/actors/")) &&
			(strings.HasSuffix(rel, ".glb") || strings.HasSuffix(rel, ".json"))
		okIcon := strings.HasPrefix(rel, "ui/all_item/") && strings.HasSuffix(rel, ".png") // 物品图标
		if strings.Contains(rel, "..") || !(okGame || okIcon) {
			http.Error(w, "forbidden", http.StatusForbidden)
			return
		}
		if !isGameRoot(a.cfg.GameRoot) {
			http.NotFound(w, r)
			return
		}
		http.ServeFile(w, r, filepath.Join(extractedDir(a.cfg.GameRoot), rel))
	})
}

