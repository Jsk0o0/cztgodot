package gamedata

// 剧情快照 (extracted/story/snapshots/<事件号>.json, 游戏 --snap-dir 录, 自动通关时打开; 见 godot field._snapshot):
// 每个事件第一次执行前的存档状态 + 所在地图 + 在场角色。编辑器用它: 剧情按真实游玩顺序排、显示当时在场的人物、从这一刻播放预览

import (
	"encoding/json"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
)

// CastMember: 快照那一刻地图上的一个角色
type CastMember struct {
	Actor  int        `json:"actor"`
	Name   string     `json:"name"`
	Act    int        `json:"act"`
	Pose   int        `json:"pose"`
	Pos    [3]float64 `json:"pos"`
	Facing float64    `json:"facing"`
	Event  int        `json:"event"`
	Player bool       `json:"player"`
	Glb    string     `json:"glb"`   // 模型文件 (相对 extracted), 没有导出的为空
	Scale  float64    `json:"scale"` // 这个动作的 ACT 缩放 (xform 第 1 列)
}

// Snapshot: 一个事件的快照概要 (不含存档状态本身)
type Snapshot struct {
	Event       int          `json:"event"`
	Borrowed    int          `json:"borrowed"` // 借用的快照是哪个事件的 (0 = 这个事件自己的)
	Map         int          `json:"map"`
	PlaySeconds float64      `json:"playSeconds"`
	Cast        []CastMember `json:"cast"`
	Cam         *SnapCam     `json:"cam"` // 当时的镜头 (旧快照没有)
}

// SnapCam: 游戏镜头 (orig_camera: 角度 = 俯仰 / 偏航 / 滚转度, 距离 d 游戏单位, 缩放 k → 视野角)
type SnapCam struct {
	Ang [3]float64 `json:"ang"`
	D   float64    `json:"d"`
	K   float64    `json:"k"`
}

type snapFile struct {
	Eid         int          `json:"eid"`
	Map         int          `json:"map"`
	PlaySeconds float64      `json:"play_seconds"`
	Seq         int          `json:"seq"`
	Cast        []CastMember `json:"cast"`
	Cam         *SnapCam     `json:"cam"`
}

func (s *Store) snapDir() string { return filepath.Join(s.Extracted, "story", "snapshots") }

// SnapshotPath: 事件快照文件 (没有返回空)
func (s *Store) SnapshotPath(eid int) string {
	p := filepath.Join(s.snapDir(), strconv.Itoa(eid)+".json")
	if _, err := os.Stat(p); err != nil {
		return ""
	}
	return p
}

// snapOrder: 有快照的事件 → 游玩时间 (排剧情顺序用); 只读文件头, 不解析存档状态
func (s *Store) snapOrder() map[int]float64 {
	out, _ := s.snapOrderStage()
	return out
}

// snapOrderStage: 同 snapOrder, 另给每个事件录快照时是分段自动通关的第几段 (stage, 0 = 没记)
func (s *Store) snapOrderStage() (map[int]float64, map[int]int) {
	out := map[int]float64{}
	stage := map[int]int{}
	files, _ := filepath.Glob(filepath.Join(s.snapDir(), "*.json"))
	for _, f := range files {
		b, err := os.ReadFile(f)
		if err != nil {
			continue
		}
		var h struct {
			Eid         int     `json:"eid"`
			PlaySeconds float64 `json:"play_seconds"`
			Seq         int     `json:"seq"`
			Stage       int     `json:"stage"`
		}
		if json.Unmarshal(b, &h) == nil && h.Eid > 0 {
			out[h.Eid] = h.PlaySeconds + float64(h.Seq)*1e-6
			stage[h.Eid] = h.Stage
		}
	}
	return out, stage
}

// Snapshot: 一个事件的快照 (在场角色带模型文件和动作缩放); 没有自己的就借同一张地图的 (Borrowed = 借来的事件号)
func (s *Store) Snapshot(eid int) (*Snapshot, error) {
	p, from := s.SnapshotFor(eid)
	if p == "" {
		return nil, nil
	}
	b, err := os.ReadFile(p)
	if err != nil {
		return nil, err
	}
	var f snapFile
	if err := json.Unmarshal(b, &f); err != nil {
		return nil, err
	}
	out := &Snapshot{Event: eid, Borrowed: from, Map: f.Map, PlaySeconds: f.PlaySeconds, Cam: f.Cam}
	for _, c := range f.Cast {
		c.Scale = 1
		glb := filepath.Join("game", "actors", "act_"+strconv.Itoa(c.Act)+"_g0.glb")
		if _, err := os.Stat(filepath.Join(s.Extracted, glb)); err == nil {
			c.Glb = filepath.ToSlash(glb)
		}
		var act struct {
			Poses map[string]struct {
				Xform [][]float64 `json:"xform"`
			} `json:"poses"`
		}
		if readJSON(filepath.Join(s.Extracted, "game", "actors", "act_"+strconv.Itoa(c.Act)+".json"), &act) == nil {
			if x := act.Poses[strconv.Itoa(c.Pose)].Xform; len(x) > 0 && len(x[0]) > 1 && x[0][1] > 0 {
				c.Scale = x[0][1]
			}
		}
		out.Cast = append(out.Cast, c)
	}
	return out, nil
}

// StoryLine: 按真实游玩顺序的剧情线路 —— 有快照的事件按游玩时间排, 归到录快照时自动通关跑的那一段 (stage N = 第 N 章;
// 每段跑到下一章任一事件就结束, 所以一段里最后一个快照若是下一章列表里的事件, 它算下一章的开头)。
// 没记段号的旧快照退回按时间: 章节起点 = 那一章编号区间里最早触发的事件。没快照的 (自动通关没走到) 放在各章最后, Reached = false
func (s *Store) StoryLine() ([]Chapter, error) {
	chs, err := s.Chapters()
	if err != nil {
		return nil, err
	}
	order, stageOf := s.snapOrderStage()
	var main []Chapter
	var others []Chapter
	for _, c := range chs {
		if c.Group == "剧情" {
			main = append(main, c)
		} else {
			others = append(others, c)
		}
	}
	// 每章起点时间
	start := make([]float64, len(main))
	for i, c := range main {
		start[i] = -1
		for _, e := range c.Events {
			if t, ok := order[e.ID]; ok && (start[i] < 0 || t < start[i]) {
				start[i] = t
			}
		}
	}
	// 时间 t 属于起点不晚于 t 的最晚一章 (「补充」跨全篇, 不参与定起点, 它的事件按时间归到当时那一章)
	chapterAt := func(t float64) int {
		k, best := 0, -1.0
		for i := range main {
			if main[i].Key != "ch11" && start[i] >= 0 && start[i] <= t && start[i] > best {
				k, best = i, start[i]
			}
		}
		return k
	}
	out := make([]Chapter, len(main))
	for i, c := range main {
		out[i] = Chapter{Key: c.Key, Group: c.Group, Title: c.Title, Sub: c.Sub}
	}
	// 实际经过的事件不管编号在哪个区间 (调查点、拿东西的 5000 以上, 路人对话 2001–5000), 都按游玩时间归到当时那一章
	var reached []StoryEvent
	seenID := map[int]bool{}
	for _, c := range chs {
		for _, e := range c.Events {
			if t, ok := order[e.ID]; ok && !seenID[e.ID] {
				seenID[e.ID] = true
				e.Time, e.Reached = t, true
				reached = append(reached, e)
			}
		}
	}
	sort.Slice(reached, func(i, j int) bool { return reached[i].Time < reached[j].Time })
	// 每段最后一个快照 (段结束的那个事件)
	lastOf := map[int]int{}
	for _, e := range reached {
		if st := stageOf[e.ID]; st > 0 {
			lastOf[st] = e.ID
		}
	}
	inChapter := func(k, id int) bool {
		if k < 0 || k >= len(main) {
			return false
		}
		for _, e := range main[k].Events {
			if e.ID == id {
				return true
			}
		}
		return false
	}
	for _, e := range reached {
		k := chapterAt(e.Time)
		if st := stageOf[e.ID]; st > 0 && st <= len(main) {
			k = st - 1
			if lastOf[st] == e.ID && inChapter(st, e.ID) {
				k = st
			}
		}
		out[k].Events = append(out[k].Events, e)
	}
	// 章节 → 任务 → 剧情: 任务的接受时间 = 第一份置了接受旗标的快照 (排「最后接受的」用)
	qs := s.quests()
	acceptAt := map[string]float64{}
	doneSeen := map[string]bool{}
	for _, e := range reached {
		flags, _ := s.snapFlags(e.ID)
		for _, q := range qs {
			if _, ok := acceptAt[q.Title]; !ok && flags[q.Accept] {
				acceptAt[q.Title] = e.Time
			}
			if flags[q.DoneFl] {
				doneSeen[q.Title] = true
			}
		}
	}
	mapName := func(m int) string {
		if r, ok := s.maps[strconv.Itoa(m)]; ok {
			if r.Title != "" {
				return r.Title
			}
			return r.Name
		}
		return strconv.Itoa(m)
	}
	for i := range out {
		out[i].Tasks = s.groupTasks(out[i].Events, qs, acceptAt, mapName)
		for j := range out[i].Tasks {
			out[i].Tasks[j].Done = doneSeen[out[i].Tasks[j].Title]
		}
		// 支线: 这一章里接受 / 完成的 ☆ 任务, 列出相关的事件
		side := map[string]*Task{}
		var order2 []string
		for _, e := range out[i].Events {
			for _, t := range append(append([]string{}, e.Acc...), e.Comp...) {
				if !strings.HasPrefix(t, "☆") {
					continue
				}
				t = strings.TrimPrefix(t, "☆")
				if side[t] == nil {
					side[t] = &Task{Title: t, Done: doneSeen[t]}
					order2 = append(order2, t)
				}
				side[t].Events = append(side[t].Events, e)
			}
		}
		for _, t := range order2 {
			out[i].Side = append(out[i].Side, *side[t])
		}
	}
	for i, c := range main {
		for _, e := range c.Events {
			if _, ok := order[e.ID]; !ok {
				out[i].Events = append(out[i].Events, e)
			}
		}
	}
	// 地图事件与支线 / 城镇与 NPC 对话: 经过的已经归进各章了, 这里只留没经过的
	for i := range others {
		var evs []StoryEvent
		for _, e := range others[i].Events {
			if _, ok := order[e.ID]; !ok {
				evs = append(evs, e)
			}
		}
		others[i].Events = evs
	}
	return append(out, others...), nil
}

// ---------------- 没触发到的事件: 借用同一张地图的快照 ----------------

type snapIndex struct {
	files int
	maps  map[int][]snapHead // 地图 → 这张图上的快照 (按游玩时间)
}

type snapHead struct {
	eid    int
	t      float64
	events map[int]bool // 当时在场角色身上的对话事件
	actors map[int]bool
}

func (s *Store) snapIdx() *snapIndex {
	files, _ := filepath.Glob(filepath.Join(s.snapDir(), "*.json"))
	if s.snapIx != nil && s.snapIx.files == len(files) {
		return s.snapIx
	}
	ix := &snapIndex{files: len(files), maps: map[int][]snapHead{}}
	for _, f := range files {
		b, err := os.ReadFile(f)
		if err != nil {
			continue
		}
		var h snapFile
		if json.Unmarshal(b, &h) != nil || h.Eid <= 0 {
			continue
		}
		sh := snapHead{eid: h.Eid, t: h.PlaySeconds + float64(h.Seq)*1e-6, events: map[int]bool{}, actors: map[int]bool{}}
		for _, c := range h.Cast {
			sh.events[c.Event] = true
			sh.actors[c.Actor] = true
		}
		ix.maps[h.Map] = append(ix.maps[h.Map], sh)
	}
	for m := range ix.maps {
		l := ix.maps[m]
		sort.Slice(l, func(i, j int) bool { return l[i].t < l[j].t })
	}
	s.snapIx = ix
	return ix
}

// eventPlaces: 原版数据里这个事件挂在哪: 地图人物表 (NPC 的 event) / 触发框 (box 的 event) / 事件索引的 triggers
func (s *Store) eventPlaces(eid int) (maps []int, actors map[int]bool) {
	actors = map[int]bool{}
	seen := map[int]bool{}
	add := func(m int) {
		if m > 0 && !seen[m] {
			seen[m] = true
			maps = append(maps, m)
		}
	}
	ids := make([]string, 0, len(s.maps))
	for k := range s.maps {
		ids = append(ids, k)
	}
	sort.Strings(ids)
	for _, k := range ids {
		mid, _ := strconv.Atoi(k)
		for _, n := range s.maps[k].Npcs {
			if n.Event == eid {
				add(mid)
				actors[n.Actor] = true
			}
		}
		for _, b := range s.maps[k].Boxes {
			if b.Event == eid {
				add(mid)
			}
		}
	}
	if ix, err := s.index(); err == nil {
		for _, t := range ix.Events[strconv.Itoa(eid)].Triggers {
			add(t.MapID)
		}
	}
	return maps, actors
}

// SnapshotFor: 播放 / 显示这个事件用哪份快照 —— 有它自己的就用; 否则借同一张地图上的:
// 优先「触发它的 NPC 在场」的那一刻 (路人对话), 再退到这张图上最后一份。from = 借用的事件号 (0 = 自己的)
func (s *Store) SnapshotFor(eid int) (path string, from int) {
	if p := s.SnapshotPath(eid); p != "" {
		return p, 0
	}
	s.mu.Lock()
	ix := s.snapIdx()
	s.mu.Unlock()
	maps, actors := s.eventPlaces(eid)
	for _, m := range maps {
		list := ix.maps[m]
		for i := len(list) - 1; i >= 0; i-- {
			h := list[i]
			if h.events[eid] {
				return s.SnapshotPath(h.eid), h.eid
			}
			for a := range actors {
				if h.actors[a] {
					return s.SnapshotPath(h.eid), h.eid
				}
			}
		}
	}
	for _, m := range maps {
		if list := ix.maps[m]; len(list) > 0 {
			h := list[len(list)-1]
			return s.SnapshotPath(h.eid), h.eid
		}
	}
	return "", 0
}

// ---------------- 章节 → 任务 → 剧情 ----------------

// Task: 章节下的一个任务 (原版任务簿 records.quests: ★主线 / ☆支线) 和这一步里发生的剧情事件
type Task struct {
	Title  string       `json:"title"` // 去掉 ★☆ 的任务名; 开场 / 任务之间的为空
	Main   bool         `json:"main"`
	Done   bool         `json:"done"` // 自动通关里完成了
	Events []StoryEvent `json:"events"`
}

type quest struct {
	Title          string
	Main           bool
	Accept, DoneFl int
}

func (s *Store) quests() []quest {
	var r struct {
		Quests []struct {
			Text   string `json:"text"`
			Accept int    `json:"flag_accept"`
			Done   int    `json:"flag_done"`
			Main   bool   `json:"main"`
		} `json:"quests"`
	}
	readJSON(filepath.Join(s.Extracted, "game", "records.json"), &r)
	out := make([]quest, 0, len(r.Quests))
	for _, q := range r.Quests {
		t := strings.TrimLeft(q.Text, "★☆")
		out = append(out, quest{Title: t, Main: q.Main, Accept: q.Accept, DoneFl: q.Done})
	}
	return out
}

// snapFlags: 快照那一刻置位的旗标 (判断当时哪个任务在进行) 和所在地图
func (s *Store) snapFlags(eid int) (map[int]bool, int) {
	p := s.SnapshotPath(eid)
	if p == "" {
		return nil, 0
	}
	b, err := os.ReadFile(p)
	if err != nil {
		return nil, 0
	}
	var f struct {
		Map   int `json:"map"`
		State struct {
			Flags []int `json:"flags"`
		} `json:"state"`
	}
	if json.Unmarshal(b, &f) != nil {
		return nil, 0
	}
	set := map[int]bool{}
	for _, x := range f.State.Flags {
		set[x] = true
	}
	return set, f.Map
}

// groupTasks: 一章里触发过的事件 (已按游玩时间排好) 按「当时在进行的主线任务」分组:
// 事件自己接受的主线任务优先 (acc), 否则看快照那一刻的旗标 —— 接受了、还没完成的主线任务里最后接受的那个。
// 地点用快照里的真实地图。新游戏入口 (还没进地图, 地图号 0) 不列
func (s *Store) groupTasks(evs []StoryEvent, qs []quest, acceptAt map[string]float64, mapName func(int) string) []Task {
	ix, _ := s.index()
	var out []Task
	at := map[string]int{}
	for _, e := range evs {
		flags, mid := s.snapFlags(e.ID)
		if flags == nil {
			continue
		}
		r := ix.Events[strconv.Itoa(e.ID)]
		if mid == 0 {
			// 还没进地图就发生的: 只转入别的事件的系统入口 (新游戏的 #1) 不列; 开场演出 (#10) 地点用它切到的地图
			if len(r.ChangeMap) == 0 {
				continue
			}
			mid = r.ChangeMap[0].MapID
		}
		e.MapID, e.Map = mid, mapName(mid)
		// 归到哪个任务: 完成了主线任务 → 那个; 接受了主线任务 → 那个; 否则快照那一刻在进行的主线任务里最后接受的
		cur := ""
		for _, a := range e.Acc {
			if strings.HasPrefix(a, "★") {
				cur = strings.TrimPrefix(a, "★")
			}
		}
		for _, c := range e.Comp {
			if strings.HasPrefix(c, "★") {
				cur = strings.TrimPrefix(c, "★")
			}
		}
		if cur == "" {
			best := -1.0
			for _, q := range qs {
				if q.Main && flags[q.Accept] && !flags[q.DoneFl] && acceptAt[q.Title] > best {
					cur, best = q.Title, acceptAt[q.Title]
				}
			}
		}
		// 同一章里同名任务并成一条 (按第一次出现排): 以前按时间切段, 任务交错进行时 (例 第二段「找寻麦饼需要的五样食材」和
		// 「将五样食材拿给诗姊姊」) 同一个任务拆成好几条, 看不出线路
		if k, ok := at[cur]; ok {
			out[k].Events = append(out[k].Events, e)
		} else {
			at[cur] = len(out)
			out = append(out, Task{Title: cur, Main: cur != "", Events: []StoryEvent{e}})
		}
	}
	return out
}
