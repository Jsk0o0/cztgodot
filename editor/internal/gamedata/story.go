package gamedata

// 原版剧情浏览 (只读): 章节线路 (extracted/story/data/*.js, tools/story_html.py 生成)、事件指令 (game/events/*.json)、
// 指令表 (scripts/opcodes.json, tools/disasm_script.py 由解释器逆向生成)、事件概要 (scripts/events_index.json)

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
)

// StoryEvent: 章节里的一个事件
type StoryEvent struct {
	ID    int      `json:"id"`
	Map   string   `json:"map"`
	MapID int      `json:"mid"`
	Trig  string   `json:"trig"` // 触发方式 (例「调查」「进入区域」)
	Talk  int      `json:"talk"` // 对白句数
	Acc   []string `json:"acc"`  // 接受的任务 (任务名)
	Comp  []string `json:"comp"` // 完成的任务
	Name  string   `json:"name"` // 触发框 / 调查点的原版名字 (events_index triggers), 可能为空
	First string   `json:"first"`
	// 真实剧情顺序 (剧情快照): Reached = 自动通关触发过, Time = 当时的游玩秒数
	Reached bool `json:"reached"`
	// 分类 (原版数据): story = 推进剧情 (置旗标 / 接受或完成任务 / 切地图 / 开战); talk = NPC 对话不改状态; other = 触发点 / 旁白不改状态
	Kind string  `json:"kind"`
	Time float64 `json:"time"`
}

// Chapter: 一段剧情线路 (序章 … 终章 / 补充 / 地图事件与支线 / 城镇与 NPC 对话)
type Chapter struct {
	Key    string       `json:"key"`
	Group  string       `json:"group"`
	Title  string       `json:"title"`
	Sub    string       `json:"sub"`
	Events []StoryEvent `json:"events"`
	Tasks  []Task       `json:"tasks"` // 有剧情快照时: 按任务分组的剧情 (章节 → 任务 → 事件)
	Side   []Task       `json:"side"`  // 这一章接受的支线任务和相关事件
}

// Opcode: 事件指令 (操作数类型见 tools/disasm_script.py TYPE_DOC: w u16, s i16, d i32, r 跳转, a 角色, m 地图, f 旗标,
// i 物品, b 战场, n 名字号, e 事件, M 曲目, c u8, T 文本, F u16 列表, R 跳转表)
type Opcode struct {
	Code     string `json:"code"`
	Name     string `json:"name"`
	Operands string `json:"operands"`
	Status   string `json:"status"` // C 汇编确认 / P 用途推断
	Note     string `json:"note"`
	Count    int    `json:"count"`
}

// EventInfo: 原版事件 = 指令 + 概要
type EventInfo struct {
	ID       int      `json:"id"`
	File     string   `json:"file"`
	Code     [][]any  `json:"code"`   // [位置, 指令, 参数...]
	Shared   []int    `json:"shared"` // 和这些事件共用同一段代码
	Triggers []string `json:"triggers"`
	Lines    []string `json:"lines"`
	Battles  []string `json:"battles"`
	MapIDs   []int    `json:"maps"` // 会切到的地图
}

type eventsIndex struct {
	Events map[string]struct {
		File     string `json:"file"`
		Shared   []int  `json:"shared_with"`
		Triggers []struct {
			MapID int    `json:"map_id"`
			Map   string `json:"map"`
			Kind  string `json:"kind"`
			Name  string `json:"name"`
		} `json:"triggers"`
		Lines    []string `json:"lines"`
		SetFlags []int    `json:"set_flags"`
		Calls    []int    `json:"call_event"`
		Battles  []struct {
			Name string `json:"name"`
		} `json:"battles"`
		ChangeMap []struct {
			MapID int `json:"map_id"`
		} `json:"change_map"`
		MissionAccept   []int `json:"mission_accept"`
		MissionComplete []int `json:"mission_complete"`
	} `json:"events"`
}

type eventFile struct {
	Events map[string]string  `json:"events"`
	Codes  map[string][][]any `json:"codes"`
}

var (
	reItem = regexp.MustCompile(`%T(\d+)\.`)
	reCode = regexp.MustCompile(`%[SCK]\d*|%[BP]`)
)

// firstLine: 事件第一句对白 (读原版事件代码, 控制码同游戏 dialog.gd: %T<物品>. → 物品名, %N 换行, %S %C 去掉)。
// events_index 的 lines 不能用来显示物品: 提取时把「%T5」当成控制码吃掉了 (「%T5506.」铜牌 → 「506.」)
func (s *Store) firstLine(file string, eid int) string {
	name := strings.TrimSuffix(strings.ToLower(file), ".gll") + ".json"
	if s.evFiles == nil {
		s.evFiles = map[string]*eventFile{}
	}
	ef := s.evFiles[name]
	if ef == nil {
		ef = &eventFile{}
		if readJSON(filepath.Join(s.Extracted, "game", "events", name), ef) != nil {
			return ""
		}
		s.evFiles[name] = ef
	}
	for _, ins := range ef.Codes[ef.Events[strconv.Itoa(eid)]] {
		if len(ins) < 3 || ins[1] != "text" {
			continue
		}
		t, _ := ins[len(ins)-1].(string)
		t = reItem.ReplaceAllStringFunc(t, func(m string) string {
			id := reItem.FindStringSubmatch(m)[1]
			if n := s.items[id]; n != "" {
				return n
			}
			return id
		})
		t = reCode.ReplaceAllString(t, "")
		t = strings.TrimSpace(strings.ReplaceAll(t, "%N", ""))
		if t != "" {
			return t
		}
	}
	return ""
}

func readStoryJS(path string, v any) error {
	b, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	s := strings.TrimSpace(string(b))
	i := strings.Index(s, "=")
	if i < 0 {
		return fmt.Errorf("%s 格式不对", filepath.Base(path))
	}
	return json.Unmarshal([]byte(strings.TrimSuffix(s[i+1:], ";")), v)
}

func (s *Store) index() (*eventsIndex, error) {
	if s.evIndex != nil {
		return s.evIndex, nil
	}
	var ix eventsIndex
	if err := readJSON(filepath.Join(s.Extracted, "scripts", "events_index.json"), &ix); err != nil {
		return nil, fmt.Errorf("读不到事件索引: %w", err)
	}
	s.evIndex = &ix
	return &ix, nil
}

// Chapters: 剧情线路 (章节按文件名: ch01…ch11 剧情, 再是 map 地图事件与支线、npc 城镇与 NPC 对话)
func (s *Store) Chapters() ([]Chapter, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.chapters != nil {
		return s.chapters, nil
	}
	ix, err := s.index()
	if err != nil {
		return nil, err
	}
	// 事件接受 / 完成的任务: 按原版数据算 —— 事件置的旗标 (events_index set_flags) 对照任务簿的接受 / 完成旗标
	// (故事页 chNN.js 里的 acc / comp 任务编号对错了, 例: 事件 31 置 7054 = 接受「捡取通行铜牌」, 它写成了第三段的「风爵」)
	acceptOf, doneOf := map[int]string{}, map[int]string{}
	for _, q := range s.quests() {
		mark := "☆"
		if q.Main {
			mark = "★"
		}
		acceptOf[q.Accept], doneOf[q.DoneFl] = mark+q.Title, mark+q.Title
	}
	files, _ := filepath.Glob(filepath.Join(s.Extracted, "story", "data", "*.js"))
	sort.Strings(files)
	var chs, others []Chapter
	for _, f := range files {
		var c Chapter
		if readStoryJS(f, &c) != nil || c.Title == "" || len(c.Events) == 0 {
			continue // battles / codex / missions / meta 是列表或别的格式
		}
		for i := range c.Events {
			e := &c.Events[i]
			e.Acc, e.Comp = nil, nil
			e.Kind = s.eventKind(e.ID)
			if r, ok := ix.Events[strconv.Itoa(e.ID)]; ok {
				for _, f := range r.SetFlags {
					if q, ok := acceptOf[f]; ok {
						e.Acc = append(e.Acc, q)
					}
					if q, ok := doneOf[f]; ok {
						e.Comp = append(e.Comp, q)
					}
				}
				for _, t := range r.Triggers {
					if t.Name != "" {
						e.Name = t.Name
						break
					}
				}
				e.First = s.firstLine(r.File, e.ID)
				if e.First == "" && len(r.Lines) > 0 {
					e.First = r.Lines[0]
				}
			}
		}
		if c.Group == "剧情" {
			chs = append(chs, c)
		} else {
			others = append(others, c)
		}
	}
	s.chapters = append(chs, others...)
	return s.chapters, nil
}

// Opcodes: 事件指令表 (按助记符)
func (s *Store) Opcodes() (map[string]Opcode, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.opcodes != nil {
		return s.opcodes, nil
	}
	var raw map[string]Opcode
	if err := readJSON(filepath.Join(s.Extracted, "scripts", "opcodes.json"), &raw); err != nil {
		return nil, fmt.Errorf("读不到指令表: %w", err)
	}
	out := map[string]Opcode{}
	for code, o := range raw {
		o.Code = code
		out[o.Name] = o
	}
	// 导出工具 (tools/export_game.py convert) 加的两个伪指令, 游戏的事件 VM 也认 (event_vm.gd)
	out["end"] = Opcode{Code: "ffff", Name: "end", Note: "事件结束（脚本末尾的 0xFFFF 结束标记）", Status: "C"}
	out["data"] = Opcode{Code: "-", Name: "data", Operands: "r", Note: "原版里没法解析的数据块：执行到这里直接跳到目标", Status: "C"}
	s.opcodes = out
	return out, nil
}

// Event: 原版事件的指令和概要
func (s *Store) Event(id int) (*EventInfo, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	ix, err := s.index()
	if err != nil {
		return nil, err
	}
	r, ok := ix.Events[strconv.Itoa(id)]
	if !ok {
		return nil, fmt.Errorf("没有事件 %d", id)
	}
	name := strings.TrimSuffix(strings.ToLower(r.File), ".gll") + ".json"
	if s.evFiles == nil {
		s.evFiles = map[string]*eventFile{}
	}
	ef := s.evFiles[name]
	if ef == nil {
		ef = &eventFile{}
		if err := readJSON(filepath.Join(s.Extracted, "game", "events", name), ef); err != nil {
			return nil, fmt.Errorf("读不到 %s: %w", name, err)
		}
		s.evFiles[name] = ef
	}
	info := &EventInfo{ID: id, File: r.File, Code: ef.Codes[ef.Events[strconv.Itoa(id)]], Shared: r.Shared, Lines: r.Lines}
	for _, t := range r.Triggers {
		d := t.Map
		if t.Name != "" {
			d += " · " + t.Name
		}
		info.Triggers = append(info.Triggers, d)
	}
	for _, b := range r.Battles {
		info.Battles = append(info.Battles, b.Name)
	}
	for _, c := range r.ChangeMap {
		info.MapIDs = append(info.MapIDs, c.MapID)
	}
	return info, nil
}

// Names: 指令参数显示用的名字表 (角色号 → 人名, 物品号 → 物品名, 战场号 → 战场名)
type Names struct {
	People  map[string]string `json:"people"`
	Items   map[string]string `json:"items"`
	Battles map[string]string `json:"battles"`
}

func (s *Store) Names() Names {
	n := Names{People: s.people, Items: s.items, Battles: map[string]string{}}
	if b, err := s.battleData(); err == nil {
		for k, f := range b.Battlefields {
			n.Battles[k] = f.Name
		}
	}
	return n
}

// eventKind: 事件分类 (原版数据): 改剧情状态的是 story (置旗标 —— 8080「事件进行中」这种临时的不算 —— 接受 / 完成任务、切地图、开战);
// 不改状态的: 挂在地图 NPC 身上的是 talk (路人对话), 其他 (触发框、被别的事件转入、旁白) 是 other
// loadFlagTests: 扫全部事件代码, 记下每个旗标被哪些事件判断 (if_flag_goto / if_not_flag_goto / if_all_flags_goto / if_any_flag_goto;
// 共用一段代码的事件都算), 再算出「影响剧情」的事件集合 storyEv
func (s *Store) loadFlagTests() {
	if s.flagTests != nil {
		return
	}
	s.flagTests = map[int]map[int]bool{}
	s.codeOf = map[int]string{}
	files, _ := filepath.Glob(filepath.Join(s.Extracted, "game", "events", "*.json"))
	for _, fn := range files {
		var ef eventFile
		if readJSON(fn, &ef) != nil {
			continue
		}
		base := filepath.Base(fn)
		users := map[string][]int{}
		for id, ck := range ef.Events {
			if n, err := strconv.Atoi(id); err == nil {
				s.codeOf[n] = base + ":" + ck
				users[ck] = append(users[ck], n)
			}
		}
		for ck, code := range ef.Codes {
			for _, ins := range code {
				if len(ins) < 3 {
					continue
				}
				op, _ := ins[1].(string)
				var fl []any
				switch op {
				case "if_flag_goto", "if_not_flag_goto":
					fl = []any{ins[2]}
				case "if_all_flags_goto", "if_any_flag_goto":
					fl, _ = ins[2].([]any)
				}
				for _, v := range fl {
					if f, ok := v.(float64); ok {
						if s.flagTests[int(f)] == nil {
							s.flagTests[int(f)] = map[int]bool{}
						}
						for _, e := range users[ck] {
							s.flagTests[int(f)][e] = true
						}
					}
				}
			}
		}
	}
	s.storyEv = s.storyEvents()
}

// engineFlags: 引擎 (不经事件脚本) 直接判断的旗标 —— godot 复刻里 State.test_flag 的常数: 1–3 队伍、7 / 9 菜单页、18 倒计时、
// 21 战斗音乐、130 机关页、1037、5530 (15 号虽然 166 段代码都置了又清, 但没人判断, 不算)
var engineFlags = map[int]bool{1: true, 2: true, 3: true, 7: true, 9: true, 18: true, 21: true, 130: true, 1037: true, 5530: true}

// storyFlag: 旗标影响剧情 = 引擎直接看, 或被影响剧情的事件 (不是 self 那段代码) 判断
func (s *Store) storyFlag(f, self int, story map[int]bool) bool {
	if engineFlags[f] {
		return true
	}
	for e := range s.flagTests[f] {
		if story[e] && s.codeOf[e] != s.codeOf[self] {
			return true
		}
	}
	return false
}

// storyEvents: 影响剧情的事件 —— 起点: 换地图、开战斗、接受 / 完成主线任务 (★)、置引擎直接看的旗标;
// 然后反复往回扩: 置的旗标被某个影响剧情的事件 (不是自己那段代码) 判断, 或 call_event 调到影响剧情的事件, 也算。
// 只在路人之间互相判断的「说过话」旗标 (例 3301: 2006–2008)、宝箱一族共用的 1060 / 1062 不会被扩进来
func (s *Store) storyEvents() map[int]bool {
	ix, err := s.index()
	if err != nil {
		return map[int]bool{}
	}
	main := map[int]bool{}
	for _, q := range s.quests() {
		if q.Main {
			main[q.Accept] = true
		}
	}
	out := map[int]bool{}
	for id, r := range ix.Events {
		n, _ := strconv.Atoi(id)
		seed := len(r.ChangeMap) > 0 || len(r.Battles) > 0
		for _, m := range append(append([]int{}, r.MissionAccept...), r.MissionComplete...) {
			seed = seed || main[m]
		}
		for _, f := range r.SetFlags {
			seed = seed || engineFlags[f]
		}
		if seed {
			out[n] = true
		}
	}
	for changed := true; changed; {
		changed = false
		for id, r := range ix.Events {
			n, _ := strconv.Atoi(id)
			if out[n] {
				continue
			}
			hit := false
			for _, f := range r.SetFlags {
				hit = hit || s.storyFlag(f, n, out)
			}
			for _, c := range r.Calls {
				hit = hit || out[c]
			}
			if hit {
				out[n] = true
				changed = true
			}
		}
	}
	return out
}

// eventKind: story = 推进剧情 (见 storyEvents; 只换地图、没置影响剧情的旗标的出入口不算, 归 other); side = 接受 / 完成支线任务 (☆);
// talk = 地图上 NPC 身上的其他事件 (路人对话); other = 其他触发点 / 旁白 / 出入口
func (s *Store) eventKind(eid int) string {
	ix, err := s.index()
	if err != nil {
		return "story"
	}
	r := ix.Events[strconv.Itoa(eid)]
	s.loadFlagTests()
	if s.storyEv[eid] {
		onlyMove := len(r.Battles) == 0 && len(r.MissionAccept) == 0 && len(r.MissionComplete) == 0
		for _, f := range r.SetFlags {
			onlyMove = onlyMove && !s.storyFlag(f, eid, s.storyEv)
		}
		if !onlyMove {
			return "story"
		}
	}
	if len(r.MissionAccept) > 0 || len(r.MissionComplete) > 0 {
		return "side"
	}
	if s.npcEvents == nil {
		s.npcEvents = map[int]bool{}
		for _, m := range s.maps {
			for _, n := range m.Npcs {
				// 只算人物: ACT 12000 起是场景 / 地图物件 (宝箱 16002、出入口箭头 16005、门…), 挂在上面的是调查点
				if n.Event > 0 && n.Act < 12000 {
					s.npcEvents[n.Event] = true
				}
			}
		}
	}
	if s.npcEvents[eid] {
		return "talk"
	}
	return "other"
}
