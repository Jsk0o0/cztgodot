package project

import (
	"bytes"
	"encoding/json"
	"fmt"
	"math"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// M1 示例 (令狐国东城送盘缠的老伯) 用积木重做一遍; 环境变量 EDITOR_M1_OUT 给了目录就把工程存到那里,
// 供游戏端 make test-mod-m1 用同一个验收测试跑「编辑器生成的 mod」
func m1() *Project {
	return &Project{
		Manifest: Manifest{ID: "kp.cheyun-gold", Name: "车芸的盘缠（测试）", Version: "0.1.0", Author: "kp",
			Description: "在令狐国东城新增一位老伯。车芸与他交谈后可获得 9999 金，只能领取一次。"},
		NPCs:  []NPC{{Local: 1, Map: 12201, Name: "送盘缠的老伯", Act: 114, Pos: [3]float64{24300, 1501, 15450}, Talk: true, Event: 1}},
		Flags: []Flag{{Local: 1, Name: "已领盘缠"}},
		Events: []Event{{Local: 1, Name: "送盘缠", Blocks: []Block{
			{Type: "if_flag", Flag: 1,
				Then: []Block{{Type: "say", Speaker: "npc:1", Text: "钱已经给过你啦，路上小心。"}},
				Else: []Block{
					{Type: "say", Speaker: "npc:1", Text: "姑娘辛苦了，这点盘缠拿去吧！"},
					{Type: "say", Speaker: "player", Text: "多谢老伯！"},
					{Type: "money", Amount: 9999},
					{Type: "flag", Flag: 1, On: true},
				}},
		}}},
	}
}

func TestM1(t *testing.T) {
	p := m1()
	if is := p.Validate(); len(is) > 0 {
		t.Fatalf("校验不通过: %+v", is)
	}
	code, err := Compile(p.Events[0], p)
	if err != nil {
		t.Fatal(err)
	}
	// 跳转目标必须是某条指令的位置
	pos := map[float64]bool{}
	for _, ins := range code {
		pos[float64(ins[0].(int))] = true
	}
	for _, ins := range code {
		if op := ins[1].(string); op == "if_flag_goto" || op == "goto" {
			if tgt := ins[len(ins)-1].(int); !pos[float64(tgt)] {
				t.Fatalf("%v 跳到不存在的位置 %d", ins, tgt)
			}
		}
	}
	dir := os.Getenv("EDITOR_M1_OUT")
	if dir == "" {
		dir = t.TempDir()
	} else {
		os.RemoveAll(dir)
	}
	p.Dir = dir
	if err := p.Save(); err != nil {
		t.Fatal(err)
	}
	q, err := Open(dir)
	if err != nil {
		t.Fatal(err)
	}
	if len(q.NPCs) != 1 || len(q.Events) != 1 || q.Manifest.ID != p.Manifest.ID {
		t.Fatalf("存了再读不一致: %+v", q)
	}
	var mp map[string][]map[string]any
	b, _ := os.ReadFile(filepath.Join(dir, "maps", "12201.json"))
	if json.Unmarshal(b, &mp) != nil || mp["npcs"][0]["id"] != "@npc:1" || mp["npcs"][0]["event"] != "@event:1" {
		t.Fatalf("maps/12201.json 不对: %s", b)
	}
}

func TestValidate(t *testing.T) {
	p := m1()
	p.Manifest.ID = "Bad ID"
	p.NPCs[0].Event = 9
	p.Events[0].Blocks = append(p.Events[0].Blocks, Block{Type: "flag", Flag: 7, On: true})
	is := p.Validate()
	if len(is) < 3 || is[0].Level != "error" {
		t.Fatalf("应该报 3 个错误: %+v", is)
	}
}

func TestTextEscape(t *testing.T) {
	if got := cleanText("100%\n第二行"); got != "100％%N第二行" {
		t.Fatalf("got %q", got)
	}
}

func TestImportModel(t *testing.T) {
	src := os.Getenv("TEST_GLB")
	if src == "" {
		t.Skip("TEST_GLB 未设置 (tools/make_test_glb.py 生成)")
	}
	p := m1()
	p.Dir = t.TempDir()
	if err := p.Save(); err != nil {
		t.Fatal(err)
	}
	m, info, err := p.ImportModel(src)
	if err != nil {
		t.Fatal(err)
	}
	if m.Idle != "idle" || m.Walk != "walk" || len(info.Anims) != 2 || info.Triangles != 24 {
		t.Fatalf("导入结果不对: %+v %+v", m, info)
	}
	p.Models = append(p.Models, *m)
	p.NPCs[0].Model = m.Local
	if is := p.Validate(); len(is) > 0 {
		t.Fatalf("校验: %+v", is)
	}
	if err := p.Save(); err != nil {
		t.Fatal(err)
	}
	b, _ := os.ReadFile(filepath.Join(p.Dir, "models.json"))
	var mj map[string]map[string]any
	json.Unmarshal(b, &mj)
	poses := mj["1"]["poses"].(map[string]any)
	if poses["0"].(map[string]any)["ticks"].(float64) != 70 || poses["4"].(map[string]any)["clip"] != "walk" {
		t.Fatalf("models.json 不对: %s", b)
	}
	mp, _ := os.ReadFile(filepath.Join(p.Dir, "maps", "12201.json"))
	if !bytes.Contains(mp, []byte(`"@model:1"`)) {
		t.Fatalf("NPC 没用上自定义模型: %s", mp)
	}
	// 删掉模型再保存: models/ 里的文件也清掉
	p.Models, p.NPCs[0].Model = nil, 0
	p.Save()
	if fileExists(filepath.Join(p.Dir, m.File)) {
		t.Fatal("没引用的模型文件没删掉")
	}
	// 坏文件
	bad := filepath.Join(t.TempDir(), "bad.glb")
	os.WriteFile(bad, []byte("not a glb file at all"), 0o644)
	if _, _, err := p.ImportModel(bad); err == nil {
		t.Fatal("坏文件应该报错")
	}
}

func TestImportPicksWalkOverRun(t *testing.T) {
	src := os.Getenv("TEST_ANIM_GLB")
	if src == "" {
		t.Skip("TEST_ANIM_GLB 没设")
	}
	p := &Project{Dir: t.TempDir()}
	m, _, err := p.ImportModel(src)
	if err != nil {
		t.Fatal(err)
	}
	if m.Idle != "mon280_stand01" || m.Walk != "mon280_walk" {
		t.Fatalf("idle=%s walk=%s", m.Idle, m.Walk)
	}
}

func TestReplaceModelKeepsIdentity(t *testing.T) {
	static, anim := os.Getenv("TEST_STATIC_GLB"), os.Getenv("TEST_ANIM_GLB")
	if static == "" || anim == "" {
		t.Skip("TEST_STATIC_GLB / TEST_ANIM_GLB 没设")
	}
	p := &Project{Dir: t.TempDir()}
	m, _, err := p.ImportModel(static)
	if err != nil {
		t.Fatal(err)
	}
	m.Scale, m.Name = 0.1, "青蛙"
	p.Models = append(p.Models, *m)
	r, _, err := p.ReplaceModel(m.Local, anim)
	if err != nil {
		t.Fatal(err)
	}
	if r.Local != m.Local || r.Scale != 0.1 || r.Name != "青蛙" || len(r.Anims) != 16 || r.Walk != "mon280_walk" || r.File == m.File {
		t.Fatalf("换文件后: %+v", r)
	}
	if fileExists(filepath.Join(p.Dir, m.File)) {
		t.Fatal("旧文件没删")
	}
}

func TestGroundY(t *testing.T) {
	anim, static := os.Getenv("TEST_ANIM440"), os.Getenv("TEST_STATIC440")
	if anim == "" || static == "" {
		t.Skip("TEST_ANIM440 / TEST_STATIC440 没设")
	}
	for _, c := range []struct {
		file, idle string
		want       float64
	}{{anim, "", -0.485}, {anim, "mon440_stand01", -0.485}, {static, "", -0.001}} {
		data, _ := os.ReadFile(c.file)
		g, err := GroundY(data, c.idle)
		if err != nil || math.Abs(g-c.want) > 0.002 {
			t.Errorf("%s %s: %.4f %v, want %.3f", filepath.Base(c.file), c.idle, g, err, c.want)
		}
	}
}

func TestModItemsCompileAndSave(t *testing.T) {
	p := &Project{Dir: t.TempDir(), Manifest: Manifest{ID: "kp.t", Name: "t", Version: "0.1.0"},
		Items: []Item{{Local: 1, Base: 3001, Name: "熊掌蜜饯", Desc: "d", Price: 80, FX1: []int{10050, 0, 0, 0, 0, 0}}},
		Events: []Event{{Local: 1, Name: "e", Blocks: []Block{
			{Type: "item", ModItem: 1, Count: 2},
			{Type: "shop", Goods: []Goods{{ModItem: 1}, {Item: 3001}}},
		}}}}
	code, err := Compile(p.Events[0], p)
	if err != nil {
		t.Fatal(err)
	}
	s := fmt.Sprint(code)
	for _, want := range []string{"give_item @item:1 2", "open_shop [@item:1 3001]", "熊掌蜜饯"} {
		if !strings.Contains(s, want) {
			t.Errorf("编译结果里没有 %q: %s", want, s)
		}
	}
	if err := p.Save(); err != nil {
		t.Fatal(err)
	}
	b, _ := os.ReadFile(filepath.Join(p.Dir, "items.json"))
	if !strings.Contains(string(b), `"base": 3001`) || !strings.Contains(string(b), `"fx1"`) || strings.Contains(string(b), `"fx2"`) {
		t.Errorf("items.json 不对: %s", b)
	}
	for _, is := range p.Validate() {
		if is.Level == "error" {
			t.Errorf("校验错误: %+v", is)
		}
	}
}

// 模拟执行编译结果里的旗标跳转, 检查「如果任务」三种状态走对分支
func runFlags(code [][]any, flags map[string]bool, items map[string]int) []string {
	at := map[int]int{}
	for i, ins := range code {
		at[ins[0].(int)] = i
	}
	var said []string
	for i := 0; i < len(code); {
		ins := code[i]
		op := ins[1].(string)
		jump := func(t any) { i = at[t.(int)] }
		switch op {
		case "if_flag_goto":
			if flags[fmt.Sprint(ins[2])] {
				jump(ins[3])
				continue
			}
		case "if_item_goto":
			if items[fmt.Sprint(ins[2])] >= ins[3].(int) {
				jump(ins[4])
				continue
			}
		case "goto":
			jump(ins[2])
			continue
		case "set_flag":
			flags[fmt.Sprint(ins[2])] = true
		case "text":
			said = append(said, fmt.Sprint(ins[len(ins)-1]))
		case "end":
			return said
		}
		i++
	}
	return said
}

func TestQuestBlocks(t *testing.T) {
	p := &Project{Quests: []Quest{{Local: 1, Title: "熊掌柜的委托"}}}
	ev := Event{Blocks: []Block{{Type: "if_quest", Quest: 1, State: "active",
		Then: []Block{{Type: "if_item", Item: 3001, Count: 3,
			Then: []Block{{Type: "say", Speaker: "player", Text: "交草药"}, {Type: "quest", Quest: 1, Step: "done"}},
			Else: []Block{{Type: "say", Speaker: "player", Text: "还差草药"}}}},
		Else: []Block{{Type: "if_quest", Quest: 1, State: "done",
			Then: []Block{{Type: "say", Speaker: "player", Text: "谢谢"}},
			Else: []Block{{Type: "say", Speaker: "player", Text: "接任务"}, {Type: "quest", Quest: 1, Step: "accept"}}}}}}}
	code, err := Compile(ev, p)
	if err != nil {
		t.Fatal(err)
	}
	acc, done := flagRef(901), flagRef(951)
	flags := map[string]bool{}
	got := runFlags(code, flags, map[string]int{})
	if strings.Join(got, "|") != "接任务|%C00%S00任务更新" || !flags[acc] {
		t.Fatalf("没接: %v %v", got, flags)
	}
	if got := runFlags(code, flags, map[string]int{"3001": 1}); got[0] != "还差草药" {
		t.Fatalf("进行中缺草药: %v", got)
	}
	if got := runFlags(code, flags, map[string]int{"3001": 3}); got[0] != "交草药" || !flags[done] {
		t.Fatalf("交任务: %v %v", got, flags)
	}
	if got := runFlags(code, flags, map[string]int{}); got[0] != "谢谢" {
		t.Fatalf("已完成: %v", got)
	}
	flags["38"] = true // 设定关掉「任务更新」提示
	if got := runFlags(code, map[string]bool{"38": true}, nil); strings.Contains(strings.Join(got, "|"), "任务更新") {
		t.Fatalf("关了提示还弹: %v", got)
	}
}

func TestModMonstersBattlesSave(t *testing.T) {
	p := &Project{Dir: t.TempDir(), Manifest: Manifest{ID: "kp.t", Name: "t", Version: "0.1.0"},
		Items:    []Item{{Local: 1, Base: 3001, Name: "熊胆", Price: 10}},
		Monsters: []Monster{{Local: 1, Base: 1017, Name: "山贼熊", Level: 12, HP: 600, Atk: 360, Exp: 120, Money: 150, DropRate: 100, DropModItem: 1}},
		Battles:  []Battle{{Local: 1, Name: "山贼熊拦路", Base: 74, Enemies: []Enemy{{At: 0, ModMonster: 1}, {At: 1, Monster: 1034}}}},
		Events:   []Event{{Local: 1, Name: "e", Blocks: []Block{{Type: "battle", Battle: 1}}}}}
	code, err := Compile(p.Events[0], p)
	if err != nil {
		t.Fatal(err)
	}
	if s := fmt.Sprint(code); !strings.Contains(s, "start_battle @battle:1") {
		t.Errorf("编译结果里没有开战: %s", s)
	}
	if err := p.Save(); err != nil {
		t.Fatal(err)
	}
	var mon map[string]map[string]any
	b, _ := os.ReadFile(filepath.Join(p.Dir, "monsters.json"))
	json.Unmarshal(b, &mon)
	if m := mon["1"]; m == nil || m["base"] != float64(1017) || fmt.Sprint(m["drop"]) != "[100 @item:1]" || m["exp"] != float64(120) {
		t.Errorf("monsters.json 不对: %s", b)
	}
	b, _ = os.ReadFile(filepath.Join(p.Dir, "battles.json"))
	if !strings.Contains(string(b), `"monster": "@monster:1"`) || !strings.Contains(string(b), `"monster": 1034`) || !strings.Contains(string(b), `"base": 74`) {
		t.Errorf("battles.json 不对: %s", b)
	}
	for _, is := range p.Validate() {
		if is.Level == "error" {
			t.Errorf("校验错误: %+v", is)
		}
	}
	// 引用不存在的怪物 / 战斗、同一站位两个敌人 → 报错
	p.Battles[0].Enemies = append(p.Battles[0].Enemies, Enemy{At: 1, ModMonster: 9})
	p.Events[0].Blocks = append(p.Events[0].Blocks, Block{Type: "battle", Battle: 5})
	n := 0
	for _, is := range p.Validate() {
		if is.Level == "error" {
			n++
		}
	}
	if n != 3 {
		t.Errorf("应该有 3 个错误, 实际 %d: %+v", n, p.Validate())
	}
}

func TestMonsterBattleModel(t *testing.T) {
	p := &Project{Dir: t.TempDir(), Manifest: Manifest{ID: "kp.t", Name: "t", Version: "0.1.0"},
		Models:   []Model{{Local: 1, Name: "m", File: "models/m.glb", Scale: 1, Anims: []Anim{{Name: "stand"}, {Name: "atk"}}}},
		Monsters: []Monster{{Local: 1, Base: 1017, Name: "飞天熊", Level: 1, HP: 1, Model: 1, Poses: map[string]string{"14": "stand", "17": "atk", "25": ""}}}}
	for _, is := range p.Validate() {
		if is.Level == "error" && strings.Contains(is.Where, "怪物") {
			t.Errorf("校验错误: %+v", is)
		}
	}
	if err := p.saveMonsters(); err != nil {
		t.Fatal(err)
	}
	b, _ := os.ReadFile(filepath.Join(p.Dir, "monsters.json"))
	var mon map[string]map[string]any
	json.Unmarshal(b, &mon)
	if mon["1"]["model"] != "@model:1" || fmt.Sprint(mon["1"]["poses"]) != "map[14:stand 17:atk]" {
		t.Errorf("monsters.json 不对: %s", b)
	}
	// 动画名不存在 / 没有待机 → 报错
	p.Monsters[0].Poses = map[string]string{"17": "nope"}
	n := 0
	for _, is := range p.Validate() {
		if is.Level == "error" && strings.Contains(is.Where, "怪物") {
			n++
		}
	}
	if n != 2 {
		t.Errorf("应有 2 个错误, 实际 %d", n)
	}
}

func TestVarsAndEncounters(t *testing.T) {
	p := &Project{Dir: t.TempDir(), Manifest: Manifest{ID: "kp.t", Name: "t", Version: "0.1.0"},
		Vars:       []Var{{Local: 1, Name: "打倒山贼熊"}},
		Monsters:   []Monster{{Local: 1, Base: 1017, Name: "山贼熊", Level: 1, HP: 1, Counter: 1}},
		Battles:    []Battle{{Local: 1, Name: "b", Base: 74, Enemies: []Enemy{{At: 0, ModMonster: 1}}}},
		Encounters: []Encounter{{Map: 12001, Battle: 1, Weight: 5}},
		Events: []Event{{Local: 1, Name: "e", Blocks: []Block{
			{Type: "if_var", Var: 1, Cmp: "ge", Value: 3, Then: []Block{{Type: "var", Var: 1, Op: "set", Value: 0}}, Else: []Block{{Type: "var", Var: 1, Op: "add", Value: 1}}},
		}}}}
	code, err := Compile(p.Events[0], p)
	if err != nil {
		t.Fatal(err)
	}
	s := fmt.Sprint(code)
	for _, want := range []string{"if_actor_var_ge_goto @npc:0 1 3", "set_actor_var @npc:0 1 0", "add_actor_var @npc:0 1 1"} {
		if !strings.Contains(s, want) {
			t.Errorf("编译结果里没有 %q: %s", want, s)
		}
	}
	for _, is := range p.Validate() {
		if is.Level == "error" {
			t.Errorf("校验错误: %+v", is)
		}
	}
	if err := p.Save(); err != nil {
		t.Fatal(err)
	}
	b, _ := os.ReadFile(filepath.Join(p.Dir, "maps", "12001.json"))
	if !strings.Contains(string(b), `"battle": "@battle:1"`) || !strings.Contains(string(b), `"weight": 5`) || !strings.Contains(string(b), `"npcs": []`) {
		t.Errorf("maps/12001.json 不对: %s", b)
	}
	b, _ = os.ReadFile(filepath.Join(p.Dir, "monsters.json"))
	if !strings.Contains(string(b), `"counter": 1`) {
		t.Errorf("monsters.json 没有 counter: %s", b)
	}
}

// 原版全部事件过一遍结构检查 (位置不重复、跳转目标都在): 规则对原版数据不能有误报
func TestCheckCodeOnOriginalEvents(t *testing.T) {
	dir := "../../../extracted"
	var ops map[string]struct {
		Name     string `json:"name"`
		Operands string `json:"operands"`
	}
	b, err := os.ReadFile(dir + "/scripts/opcodes.json")
	if err != nil {
		t.Skip("没有游戏数据")
	}
	json.Unmarshal(b, &ops)
	m := map[string]string{}
	for _, o := range ops {
		m[o.Name] = o.Operands
	}
	SetJumpOperands(m)
	files, _ := filepath.Glob(dir + "/game/events/*.json")
	n, jumps := 0, 0
	for _, f := range files {
		var ef struct {
			Codes map[string][][]any `json:"codes"`
		}
		b, _ := os.ReadFile(f)
		json.Unmarshal(b, &ef)
		for k, code := range ef.Codes {
			n++
			for _, ins := range code {
				jumps += len(JumpTargets(ins))
			}
			if msgs := checkCode(code); len(msgs) > 0 {
				t.Errorf("%s 代码 %s: %v", filepath.Base(f), k, msgs[:1])
			}
		}
	}
	if n < 1000 || jumps < 5000 {
		t.Errorf("事件 %d 段、跳转 %d 个, 太少了", n, jumps)
	}
	t.Logf("检查了 %d 段事件代码, %d 个跳转", n, jumps)
}

func TestCharsNewGameSkillsSave(t *testing.T) {
	name := "小芸"
	money := 5000
	power := 5000
	p := &Project{Dir: t.TempDir(), Manifest: Manifest{ID: "kp.t", Name: "t", Version: "0.1.0"},
		Skills:     []ModSkill{{Local: 1, Base: 6401, Name: "恨心诀·改", Power: 4600, Cost: map[string]int{"sp": 30}}},
		SkillEdits: []SkillEdit{{ID: 6701, Power: &power}},
		Characters: []CharEdit{{ID: 1, Name: &name, Stats: map[string]int{"level": 5, "hp": 999},
			Growth: []GrowthRow{{Lv: 6, Inc: [12]int{44}, Learn: SkillRef{ModSkill: 1}}}, MapAct: ptr(110)}},
		NewGame: &NewGameEdit{Money: &money, Party: []int{1, 2}, Skills: map[string][]SkillRef{"2": {{Skill: 6401}, {ModSkill: 1}}}}}
	for _, is := range p.Validate() {
		if is.Level == "error" {
			t.Errorf("校验错误: %+v", is)
		}
	}
	if err := p.Save(); err != nil {
		t.Fatal(err)
	}
	read := func(f string) map[string]any {
		var m map[string]any
		b, _ := os.ReadFile(filepath.Join(p.Dir, f))
		json.Unmarshal(b, &m)
		return m
	}
	ch := read("characters.json")["1"].(map[string]any)
	if ch["name"] != "小芸" || ch["level"] != float64(5) || ch["map_act"] != float64(110) || fmt.Sprint(ch["growth"]) != "[[6 44 0 0 0 0 0 0 0 0 0 0 0 @skill:1]]" {
		t.Errorf("characters.json 不对: %v", ch)
	}
	ng := read("newgame.json")
	if ng["money"] != float64(5000) || fmt.Sprint(ng["party"]) != "[1 2]" || fmt.Sprint(ng["skills"]) != "map[2:[6401 @skill:1]]" {
		t.Errorf("newgame.json 不对: %v", ng)
	}
	sk := read("skills.json")
	if fmt.Sprint(sk["1"]) != "map[base:6401 cost:map[sp:30] desc: name:恨心诀·改 power:4600]" || fmt.Sprint(sk["6701"]) != "map[power:5000]" {
		t.Errorf("skills.json 不对: %v", sk)
	}
	// 引用不存在的技能 → 报错
	p.Characters[0].Growth[0].Learn = SkillRef{ModSkill: 9}
	n := 0
	for _, is := range p.Validate() {
		if is.Level == "error" {
			n++
		}
	}
	if n != 1 {
		t.Errorf("应有 1 个错误, 实际 %d", n)
	}
}

func ptr(v int) *int { return &v }
