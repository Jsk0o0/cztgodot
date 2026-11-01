package gamedata

import (
	"fmt"
	"os"
	"path/filepath"
	"testing"
)

func TestStoryBrowse(t *testing.T) {
	dir := "../../../extracted"
	if _, err := os.Stat(dir + "/story/data/ch01.js"); err != nil {
		t.Skip("没有游戏数据")
	}
	s := &Store{Extracted: dir}
	chs, err := s.Chapters()
	if err != nil {
		t.Fatal(err)
	}
	if len(chs) < 13 || chs[0].Title != "序章　令狐国" || chs[0].Group != "剧情" || len(chs[0].Events) != 76 {
		t.Fatalf("章节不对: %d %q %d", len(chs), chs[0].Title, len(chs[0].Events))
	}
	ev, err := s.Event(607)
	if err != nil {
		t.Fatal(err)
	}
	found := false
	for _, ins := range ev.Code {
		if ins[1] == "start_battle" && ins[2] == float64(131) {
			found = true
		}
	}
	if !found || len(ev.Battles) == 0 {
		t.Errorf("事件 607 应有 start_battle 131: %d 条指令", len(ev.Code))
	}
	ops, err := s.Opcodes()
	if err != nil || ops["text"].Operands == "" || ops["start_battle"].Code != "0051" {
		t.Errorf("指令表不对: %v %+v", err, ops["start_battle"])
	}
}

// 原版全部事件里出现的指令, 指令表里都要有 (编辑器校验「原版里没有这个指令」不能误报)
func TestOpcodesCoverOriginalEvents(t *testing.T) {
	dir := "../../../extracted"
	if _, err := os.Stat(dir + "/scripts/opcodes.json"); err != nil {
		t.Skip("没有游戏数据")
	}
	s := &Store{Extracted: dir}
	ops, err := s.Opcodes()
	if err != nil {
		t.Fatal(err)
	}
	files, _ := filepath.Glob(dir + "/game/events/*.json")
	miss := map[string]int{}
	for _, f := range files {
		var ef eventFile
		if err := readJSON(f, &ef); err != nil {
			t.Fatal(err)
		}
		for _, code := range ef.Codes {
			for _, ins := range code {
				if name, _ := ins[1].(string); ops[name].Name == "" {
					miss[name]++
				}
			}
		}
	}
	if len(miss) > 0 {
		t.Errorf("指令表里没有: %v", miss)
	}
}

// 有剧情快照时: 主线各章里触发过的事件按游玩时间升序排在前面, 没触发的在后; 快照角色带模型文件
func TestStoryLineOrder(t *testing.T) {
	dir := "../../../extracted"
	s := &Store{Extracted: dir}
	if s.SnapshotPath(1) == "" {
		t.Skip("还没有剧情快照")
	}
	chs, err := s.StoryLine()
	if err != nil {
		t.Fatal(err)
	}
	if len(chs[0].Events) == 0 || chs[0].Events[0].ID != 1 || !chs[0].Events[0].Reached {
		t.Fatalf("序章第一个应是新游戏的事件 1: %+v", chs[0].Events[:1])
	}
	for _, c := range chs {
		last, seenUnreached := -1.0, false
		for _, e := range c.Events {
			if !e.Reached {
				seenUnreached = true
				continue
			}
			if seenUnreached || e.Time < last {
				t.Fatalf("%s 顺序不对: #%d", c.Title, e.ID)
			}
			last = e.Time
		}
	}
	// 事件 1 是新游戏入口 (还没进地图, 没有在场角色); 后面的快照要带角色和模型文件
	withCast := false
	for _, c := range chs[0].Events {
		if sn, err := s.Snapshot(c.ID); err == nil && sn != nil && len(sn.Cast) > 0 && sn.Cast[0].Glb != "" {
			withCast = true
			break
		}
	}
	if !withCast {
		t.Fatal("序章没有一个快照带在场角色和模型")
	}
}

// 没触发到的路人对话借快照: 选挂这个事件的 NPC 在场的那一刻 (猪肉大夫 2011, 令狐国东城 12201)
func TestSnapshotForBorrowed(t *testing.T) {
	dir := "../../../extracted"
	s := &Store{Extracted: dir}
	if err := readJSON(dir+"/game/maps.json", &s.maps); err != nil {
		t.Skip("没有游戏数据")
	}
	if s.SnapshotPath(2011) != "" {
		t.Skip("2011 有自己的快照")
	}
	p, from := s.SnapshotFor(2011)
	if p == "" {
		t.Skip("令狐国东城还没有快照")
	}
	sn, err := s.Snapshot(2011)
	if err != nil || sn == nil || from == 0 || sn.Borrowed != from || sn.Map != 12201 {
		t.Fatalf("借用不对: %v %+v", err, sn)
	}
	found := false
	for _, c := range sn.Cast {
		if c.Actor == 2011 {
			found = true
		}
	}
	if !found {
		t.Errorf("借来的快照 (#%d) 里猪肉大夫不在场", from)
	}
}

// 章节 → 任务: 序章第一个任务前是开场 (木工房), 不列新游戏入口 #1; 任务名来自原版任务簿
func TestStoryTasks(t *testing.T) {
	dir := "../../../extracted"
	s := &Store{Extracted: dir}
	readJSON(dir+"/game/maps.json", &s.maps)
	if s.SnapshotPath(31) == "" {
		t.Skip("还没有剧情快照")
	}
	chs, err := s.StoryLine()
	if err != nil {
		t.Fatal(err)
	}
	for _, tk := range chs[0].Tasks {
		names := []string{}
		for _, e := range tk.Events {
			if e.ID == 1 {
				t.Errorf("新游戏入口 #1 不该列出")
			}
			names = append(names, fmt.Sprintf("#%d %s", e.ID, e.Map))
		}
		t.Logf("任务「%s」main=%v: %v", tk.Title, tk.Main, names)
	}
	if len(chs[0].Tasks) < 2 {
		t.Errorf("序章至少要分出开场和一个任务")
	}
}

// 事件分类按原版数据: 旗标被剧情事件判断才算推进剧情; 路人之间互相判断的「说过话」旗标、宝箱共用旗标不算
func TestStoryKinds(t *testing.T) {
	s, err := Open("../../../extracted")
	if err != nil {
		t.Skip("没有游戏数据")
	}
	want := map[int]string{
		10: "story", 31: "story", 5104: "story", 49: "story", // 开场、军官放行、拿铜牌、车氏玉玦
		2004: "side", 2013: "side", // 接受 / 完成支线任务 (☆)
		2006: "talk", 2009: "talk", 2017: "talk", // 路人: 3301 只被 2006–2008 判断
		2001: "other", 173: "other", // 不能出城 / 回不去的阻挡
		7201: "other", 7203: "other", // 出入口: 只置了没人判断的 15
		5232: "other", // 宝箱 (ACT 16002)「距离太远」
	}
	for id, k := range want {
		if got := s.eventKind(id); got != k {
			t.Errorf("事件 %d: 分类 %s, 应为 %s", id, got, k)
		}
	}
}
