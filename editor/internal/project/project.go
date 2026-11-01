// Package project: mod 工程 (= 游戏能直接加载的 mod 文件夹 + 编辑器自己的 editor.json)。
//
// 文件:
//
//	mod.json          清单 (游戏读)
//	editor.json       编辑器的源数据: NPC、事件积木、旗标名 (游戏不读)
//	maps/<地图>.json  由 editor.json 生成 (游戏读)
//	events.json       事件积木编译成的脚本 (游戏读; 格式同 extracted/game/events 的 codes)
//	models.json       自定义模型的动作表 (游戏读), 模型文件在 models/*.glb
//
// 游戏端规则见 godot/scripts/mod_manager.gd: "@npc:N" / "@event:N" / "@flag:N" 符号引用, 指令只能用原版出现过的。
package project

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
)

type Manifest struct {
	ID          string `json:"id"`
	Name        string `json:"name"`
	Version     string `json:"version"`
	Author      string `json:"author"`
	Game        string `json:"game"`
	Description string `json:"description"`
}

type NPC struct {
	Local  int        `json:"local"` // @npc:N
	Map    int        `json:"map"`
	Name   string     `json:"name"`
	Act    int        `json:"act"`   // 原版模型 ACT (Model = 0 时用)
	Model  int        `json:"model"` // 自定义模型 @model:N, 0 = 用原版 Act
	Pose   int        `json:"pose"`
	Pos    [3]float64 `json:"pos"`
	Facing float64    `json:"facing"`
	Talk   bool       `json:"talk"`  // 可对话 (标志 0x2000 | 0x20, 同原版路人)
	Event  int        `json:"event"` // 对话事件 (@event:N), 0 = 无
}

// Block: 事件积木
//
//	say      {speaker: "npc:N" / "player" / "actor:原版角色号", text}
//	notice   {text}                  系统提示框 + 音效 527
//	money    {amount, quiet}         默认之后弹「得到 N 金」提示框 (同原版), quiet = 不弹
//	item     {item / modItem, count, itemName, quiet}  原版物品填 item, 本 mod 物品填 modItem; count < 0 = 拿走;
//	         itemName 由编辑器填 (提示框里显示)
//	shop     {goods: [{item / modItem}]}   开商店 (原版 open_shop), 买卖界面同原版
//	quest    {quest, step: "accept" / "done", quiet}   接受 / 完成任务, 之后弹原版「任务更新」(设定关了提示就不弹)
//	if_quest {quest, state: "none" 没接 / "active" 进行中 / "done" 已完成, then, else}
//	if_item  {item / modItem, count, then, else}   身上有 ≥ count 个 (原版 if_item_goto)
//	var      {var, op: "set" / "add", value}       变量 = / += 值 (原版 set_actor_var / add_actor_var)
//	if_var   {var, cmp: "ge" / "eq", value, then, else}   (原版 if_actor_var_ge_goto / if_actor_var_eq_goto)
//	party    {member: 2 / 3, on}    嬴诗 / 桓远之 入队 (on) / 离队 —— 原版就是设 / 清旗标 2、3 (战斗 / 菜单按它判断谁在队)
//	battle   {battle}                开战 (原版 start_battle): 本 mod 的战斗 @battle:N; 剧情战规则, 输了回标题
//	flag     {flag, on}
//	if_flag  {flag, then, else}
//	end      结束事件
type Block struct {
	Type     string  `json:"type"`
	Speaker  string  `json:"speaker,omitempty"`
	Text     string  `json:"text,omitempty"`
	Amount   int     `json:"amount,omitempty"`
	Item     int     `json:"item,omitempty"`
	ModItem  int     `json:"modItem,omitempty"`
	ItemName string  `json:"itemName,omitempty"`
	Goods    []Goods `json:"goods,omitempty"`
	Count    int     `json:"count,omitempty"`
	Quiet    bool    `json:"quiet,omitempty"`
	Flag     int     `json:"flag,omitempty"`
	On       bool    `json:"on,omitempty"`
	Quest    int     `json:"quest,omitempty"`
	Step     string  `json:"step,omitempty"`
	State    string  `json:"state,omitempty"`
	Battle   int     `json:"battle,omitempty"`
	Member   int     `json:"member,omitempty"`
	Var      int     `json:"var,omitempty"`
	Op       string  `json:"op,omitempty"`  // 变量: set / add
	Cmp      string  `json:"cmp,omitempty"` // 如果变量: ge (≥) / eq (=)
	Value    int     `json:"value,omitempty"`
	Then     []Block `json:"then,omitempty"`
	Else     []Block `json:"else,omitempty"`
}

// Goods: 商店里的一件货 (原版物品 item 或本 mod 物品 modItem, 二选一)
type Goods struct {
	Item    int `json:"item,omitempty"`
	ModItem int `json:"modItem,omitempty"`
}

// Item: 本 mod 的物品 = 复制原版物品 Base (分类、图标、使用演出、范围…照抄), 只改名字 / 说明 / 价格 / 恢复量
// (fx1[0] 生命、fx1[1] 体力、fx2[0] 灵力; 编码同游戏 Formula.amount: ≤10000 定值, 10001–10099 百分比 (10099 = 全满))
type Item struct {
	Local int    `json:"local"` // @item:N (1–255)
	Base  int    `json:"base"`
	Name  string `json:"name"`
	Desc  string `json:"desc"`
	Price int    `json:"price"`
	FX1   []int  `json:"fx1,omitempty"` // 只有恢复类 (分类 202) 才写
	FX2   []int  `json:"fx2,omitempty"`
}

// Monster: 本 mod 的怪物 = 复制原版怪物 Base (模型、普攻、技能、AI、抗性、偷窃物、资源照抄),
// 只改名字 / 说明 / 等级 / 数值 / 经验 / 金钱 / 战后掉落 (掉落表第 0 组: 几率 %, 原版物品 dropItem 或本 mod 物品 dropModItem)
type Monster struct {
	Local       int    `json:"local"` // @monster:N (1–255)
	Base        int    `json:"base"`
	Name        string `json:"name"`
	Desc        string `json:"desc"`
	Level       int    `json:"level"`
	HP          int    `json:"hp"`
	MP          int    `json:"mp"`
	SP          int    `json:"sp"`
	Atk         int    `json:"atk"`
	Def         int    `json:"def"`
	Spd         int    `json:"spd"`
	Matk        int    `json:"matk"`
	Mdef        int    `json:"mdef"`
	Hit         int    `json:"hit"`
	Eva         int    `json:"eva"`
	Mhit        int    `json:"mhit"`
	Meva        int    `json:"meva"`
	Exp         int    `json:"exp"`
	Money       int    `json:"money"`
	DropRate    int    `json:"dropRate"`
	DropItem    int    `json:"dropItem,omitempty"`
	DropModItem int    `json:"dropModItem,omitempty"`
	// 战斗模型 (可选): 本 mod 的自定义模型 @model:N; Poses = 原版动作号 → 模型里的动画名 (没给的用待机 14 的)。
	// 动作的帧数 / 命中时刻 / 音效照抄来源怪物 (游戏端 Mods._battle_model)
	Counter int               `json:"counter,omitempty"` // 被打倒时变量 #Counter +1 (0 = 不计)
	Model   int               `json:"model,omitempty"`
	Poses   map[string]string `json:"poses,omitempty"`
}

// Battle: 本 mod 的战斗 = 复制原版普通战场 Base (场景、镜头、战斗脚本、雾), 敌人换掉;
// 每个敌人占原版战场的一个站位 At (那个位置 / 朝向), 原版怪物 monster 或本 mod 怪物 modMonster
type Battle struct {
	Local   int     `json:"local"` // @battle:N (1–63)
	Name    string  `json:"name"`  // 编辑器里显示
	Base    int     `json:"base"`
	Enemies []Enemy `json:"enemies"`
}

type Enemy struct {
	At         int `json:"at"`
	Monster    int `json:"monster,omitempty"`
	ModMonster int `json:"modMonster,omitempty"`
}

// Quest: 任务 (记载「事」页, 同原版 records.quests): 一行文字 + 接受 / 完成两个旗标。
// 旗标由编辑器自动分配: 接受 @flag:(QuestFlagBase+N), 完成 @flag:(QuestFlagBase+50+N); 作者自己的旗标要 < QuestFlagBase
type Quest struct {
	Local int    `json:"local"` // 1–49
	Title string `json:"title"`
	Main  bool   `json:"main"` // 主线 (★) / 支线 (☆)
}

const QuestFlagBase = 900

func (q Quest) AcceptFlag() int { return QuestFlagBase + q.Local }
func (q Quest) DoneFlag() int   { return QuestFlagBase + 50 + q.Local }
func (q Quest) Text() string {
	if q.Main {
		return "★" + q.Title
	}
	return "☆" + q.Title
}

type Event struct {
	Local  int     `json:"local"`
	Name   string  `json:"name"`
	Blocks []Block `json:"blocks"`
}

// Model: 导入的自定义模型 (GLB)
type Model struct {
	Local     int     `json:"local"` // @model:N (1–63)
	Name      string  `json:"name"`
	File      string  `json:"file"`   // models/xxx.glb
	Scale     float64 `json:"scale"`  // 游戏里 1 = 1 米
	Yaw       float64 `json:"yaw"`    // 朝向修正 (度); glTF 惯例正面朝 +Z, 一般为 0
	Idle      string  `json:"idle"`   // 待机动画 (动作 0)
	Walk      string  `json:"walk"`   // 行走动画 (动作 4), 可空
	Ground    float64 `json:"ground"` // 脚底高度 (模型单位, 见 ground.go); 显示时抬高 -ground 贴地, 保存时重算
	Anims     []Anim  `json:"anims"`
	Triangles int     `json:"triangles"`
	Size      int     `json:"size"`
}

type Flag struct {
	Local int    `json:"local"`
	Name  string `json:"name"`
}

// Var: 本 mod 的变量 (计数器, 0–65535, 跟存档保存) = 游戏里本 mod 0 号角色 (@npc:0) 的角色变量 N
// (原版 add_actor_var / if_actor_var_ge_goto 那组指令, 原版用来记 NPC 对话次数)
type Var struct {
	Local int    `json:"local"` // 1–999
	Name  string `json:"name"`
}

// Override: 方案改过的原版事件 = 整段指令 (格式同游戏事件: [位置, 指令, 参数...], 跳转写目标位置;
// 位置只是标签, 执行按数组顺序, 插入的新指令用没用过的位置号)。游戏端整段替换原版代码 (Mods.override_code)
type Override struct {
	ID   int     `json:"id"`   // 原版事件号
	Name string  `json:"name"` // 编辑器显示 (原版事件的名字)
	Code [][]any `json:"code"`
}

// NpcEdit: 改 / 删原版地图上的 NPC (按角色号); 只写改了的项
type NpcEdit struct {
	Map      int         `json:"map"`
	Actor    int         `json:"actor"`
	Remove   bool        `json:"remove,omitempty"`
	Pos      *[3]float64 `json:"pos,omitempty"`
	Act      *int        `json:"act,omitempty"`
	Model    int         `json:"model,omitempty"` // 换成本 mod 的自定义模型
	Facing   *float64    `json:"facing,omitempty"`
	Event    *int        `json:"event,omitempty"`    // 换成另一个原版事件
	ModEvent int         `json:"modEvent,omitempty"` // 换成本 mod 的事件
	Name     *string     `json:"name,omitempty"`
}

// Encounter: 把本 mod 的战斗加进某张地图原版遇敌区域的战场列表 (重复 = 权重, 同原版); Zones 空 = 全部区域
type Encounter struct {
	Map    int   `json:"map"`
	Battle int   `json:"battle"`
	Weight int   `json:"weight"`
	Zones  []int `json:"zones"`
}

type Project struct {
	Dir        string       `json:"dir"`
	Manifest   Manifest     `json:"manifest"`
	NPCs       []NPC        `json:"npcs"`
	Events     []Event      `json:"events"`
	Flags      []Flag       `json:"flags"`
	Models     []Model      `json:"models"`
	Items      []Item       `json:"items"`
	Quests     []Quest      `json:"quests"`
	Monsters   []Monster    `json:"monsters"`
	Battles    []Battle     `json:"battles"`
	Vars       []Var        `json:"vars"`
	Encounters []Encounter  `json:"encounters"`
	Overrides  []Override   `json:"overrides"`
	NpcEdits   []NpcEdit    `json:"npcEdits"`
	Characters []CharEdit   `json:"characters"`
	NewGame    *NewGameEdit `json:"newGame"`
	Skills     []ModSkill   `json:"skills"`
	SkillEdits []SkillEdit  `json:"skillEdits"`
}

type editorFile struct {
	Format     int          `json:"format"`
	NPCs       []NPC        `json:"npcs"`
	Events     []Event      `json:"events"`
	Flags      []Flag       `json:"flags"`
	Models     []Model      `json:"models"`
	Items      []Item       `json:"items"`
	Quests     []Quest      `json:"quests"`
	Monsters   []Monster    `json:"monsters"`
	Battles    []Battle     `json:"battles"`
	Vars       []Var        `json:"vars"`
	Encounters []Encounter  `json:"encounters"`
	Overrides  []Override   `json:"overrides"`
	NpcEdits   []NpcEdit    `json:"npcEdits"`
	Characters []CharEdit   `json:"characters"`
	NewGame    *NewGameEdit `json:"newGame"`
	Skills     []ModSkill   `json:"skills"`
	SkillEdits []SkillEdit  `json:"skillEdits"`
}

var idRe = regexp.MustCompile(`^[a-z0-9][a-z0-9_-]*\.[a-z0-9][a-z0-9_.-]*$`)

// New: 在空目录 (或不存在的目录) 新建工程
func New(dir string, m Manifest) (*Project, error) {
	if ents, err := os.ReadDir(dir); err == nil && len(ents) > 0 {
		return nil, errors.New("目录不是空的，请选一个空目录")
	}
	if m.Version == "" {
		m.Version = "0.1.0"
	}
	if m.Game == "" {
		m.Game = "0.4"
	}
	p := &Project{Dir: dir, Manifest: m, NPCs: []NPC{}, Events: []Event{}, Flags: []Flag{}, Models: []Model{}, Items: []Item{}, Quests: []Quest{}, Monsters: []Monster{}, Battles: []Battle{}, Vars: []Var{}, Encounters: []Encounter{}, Overrides: []Override{}, NpcEdits: []NpcEdit{}, Characters: []CharEdit{}, Skills: []ModSkill{}, SkillEdits: []SkillEdit{}}
	return p, p.Save()
}

func Open(dir string) (*Project, error) {
	p := &Project{Dir: dir}
	b, err := os.ReadFile(filepath.Join(dir, "mod.json"))
	if err != nil {
		return nil, errors.New("这个目录里没有 mod.json，不是 mod 工程")
	}
	if err := json.Unmarshal(b, &p.Manifest); err != nil {
		return nil, fmt.Errorf("mod.json 格式不对: %w", err)
	}
	var ef editorFile
	if b, err := os.ReadFile(filepath.Join(dir, "editor.json")); err == nil {
		if err := json.Unmarshal(b, &ef); err != nil {
			return nil, fmt.Errorf("editor.json 格式不对: %w", err)
		}
	} else {
		return nil, errors.New("没有 editor.json：这个 mod 不是用编辑器做的，暂不支持打开手写的 mod")
	}
	p.NPCs, p.Events, p.Flags, p.Models, p.Items = ef.NPCs, ef.Events, ef.Flags, ef.Models, ef.Items
	if p.Items == nil {
		p.Items = []Item{}
	}
	p.Quests = ef.Quests
	if p.Quests == nil {
		p.Quests = []Quest{}
	}
	p.Monsters, p.Battles = ef.Monsters, ef.Battles
	if p.Monsters == nil {
		p.Monsters = []Monster{}
	}
	if p.Battles == nil {
		p.Battles = []Battle{}
	}
	p.Vars, p.Encounters = ef.Vars, ef.Encounters
	if p.Vars == nil {
		p.Vars = []Var{}
	}
	if p.Encounters == nil {
		p.Encounters = []Encounter{}
	}
	p.Overrides, p.NpcEdits = ef.Overrides, ef.NpcEdits
	if p.Overrides == nil {
		p.Overrides = []Override{}
	}
	if p.NpcEdits == nil {
		p.NpcEdits = []NpcEdit{}
	}
	p.Characters, p.NewGame, p.Skills, p.SkillEdits = ef.Characters, ef.NewGame, ef.Skills, ef.SkillEdits
	if p.Characters == nil {
		p.Characters = []CharEdit{}
	}
	if p.Skills == nil {
		p.Skills = []ModSkill{}
	}
	if p.SkillEdits == nil {
		p.SkillEdits = []SkillEdit{}
	}
	if p.Models == nil {
		p.Models = []Model{}
	}
	if p.NPCs == nil {
		p.NPCs = []NPC{}
	}
	if p.Events == nil {
		p.Events = []Event{}
	}
	if p.Flags == nil {
		p.Flags = []Flag{}
	}
	return p, nil
}

func writeJSON(path string, v any) error {
	b, err := json.MarshalIndent(v, "", "  ")
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	tmp := path + ".tmp"
	if err := os.WriteFile(tmp, b, 0o644); err != nil {
		return err
	}
	return os.Rename(tmp, path) // 先写临时文件再改名, 中途失败不会留下半个文件
}

// Save: 写 mod.json / editor.json, 并生成游戏读的 maps/*.json、events.json (旧的 maps/*.json 先删)
func (p *Project) Save() error {
	// 脚底高度按当前选的待机动画重算 (换了待机动画 / 旧工程没有这个字段)
	for i := range p.Models {
		m := &p.Models[i]
		if data, err := os.ReadFile(filepath.Join(p.Dir, m.File)); err == nil {
			if g, err := GroundY(data, m.Idle); err == nil {
				m.Ground = g
			}
		}
	}
	if err := writeJSON(filepath.Join(p.Dir, "mod.json"), p.Manifest); err != nil {
		return err
	}
	if err := writeJSON(filepath.Join(p.Dir, "editor.json"), editorFile{Format: 1, NPCs: p.NPCs, Events: p.Events, Flags: p.Flags, Models: p.Models, Items: p.Items, Quests: p.Quests, Monsters: p.Monsters, Battles: p.Battles, Vars: p.Vars, Encounters: p.Encounters, Overrides: p.Overrides, NpcEdits: p.NpcEdits, Characters: p.Characters, NewGame: p.NewGame, Skills: p.Skills, SkillEdits: p.SkillEdits}); err != nil {
		return err
	}
	mdir := filepath.Join(p.Dir, "maps")
	old, _ := filepath.Glob(filepath.Join(mdir, "*.json"))
	for _, f := range old {
		os.Remove(f)
	}
	byMap := map[int][]map[string]any{}
	for _, n := range p.NPCs {
		flags := 0
		if n.Talk {
			flags = 0x2020
		}
		var act any = n.Act
		if n.Model > 0 {
			act = fmt.Sprintf("@model:%d", n.Model)
		}
		rec := map[string]any{"id": fmt.Sprintf("@npc:%d", n.Local), "name": n.Name, "act": act, "pose": n.Pose,
			"facing": n.Facing, "pos": []int{int(n.Pos[0]), int(n.Pos[1]), int(n.Pos[2])}, "ai": 0, "flags": flags, "event": 0}
		if n.Event > 0 {
			rec["event"] = fmt.Sprintf("@event:%d", n.Event)
		}
		byMap[n.Map] = append(byMap[n.Map], rec)
	}
	encs := map[int][]map[string]any{}
	for _, e := range p.Encounters {
		zones := e.Zones
		if zones == nil {
			zones = []int{}
		}
		encs[e.Map] = append(encs[e.Map], map[string]any{"battle": fmt.Sprintf("@battle:%d", e.Battle), "weight": e.Weight, "zones": zones})
		if _, ok := byMap[e.Map]; !ok {
			byMap[e.Map] = []map[string]any{}
		}
	}
	edits := map[int][]map[string]any{}
	for _, e := range p.NpcEdits {
		rec := map[string]any{"actor": e.Actor}
		if e.Remove {
			rec["remove"] = true
		} else {
			if e.Pos != nil {
				rec["pos"] = []int{int(e.Pos[0]), int(e.Pos[1]), int(e.Pos[2])}
			}
			if e.Model > 0 {
				rec["act"] = fmt.Sprintf("@model:%d", e.Model)
			} else if e.Act != nil {
				rec["act"] = *e.Act
			}
			if e.Facing != nil {
				rec["facing"] = *e.Facing
			}
			if e.ModEvent > 0 {
				rec["event"] = fmt.Sprintf("@event:%d", e.ModEvent)
			} else if e.Event != nil {
				rec["event"] = *e.Event
			}
			if e.Name != nil {
				rec["name"] = *e.Name
			}
		}
		edits[e.Map] = append(edits[e.Map], rec)
		if _, ok := byMap[e.Map]; !ok {
			byMap[e.Map] = []map[string]any{}
		}
	}
	for mid, list := range byMap {
		out := map[string]any{"npcs": list}
		if len(encs[mid]) > 0 {
			out["encounters"] = encs[mid]
		}
		if len(edits[mid]) > 0 {
			out["npc_edits"] = edits[mid]
		}
		if err := writeJSON(filepath.Join(mdir, fmt.Sprintf("%d.json", mid)), out); err != nil {
			return err
		}
	}
	if err := p.saveItems(); err != nil {
		return err
	}
	if err := p.saveChars(); err != nil {
		return err
	}
	if err := p.saveNewGame(); err != nil {
		return err
	}
	if err := p.saveSkills(); err != nil {
		return err
	}
	if err := p.saveOverrides(); err != nil {
		return err
	}
	if err := p.saveMonsters(); err != nil {
		return err
	}
	if err := p.saveBattles(); err != nil {
		return err
	}
	if err := p.saveQuests(); err != nil {
		return err
	}
	if err := p.saveModels(); err != nil {
		return err
	}
	evs := map[string][][]any{}
	for _, e := range p.Events {
		code, err := Compile(e, p)
		if err != nil {
			return fmt.Errorf("事件「%s」: %w", e.Name, err)
		}
		evs[fmt.Sprint(e.Local)] = code
	}
	return writeJSON(filepath.Join(p.Dir, "events.json"), evs)
}

// ---------------- 校验 ----------------

type Issue struct {
	Level   string `json:"level"` // error / warning
	Where   string `json:"where"`
	Message string `json:"message"`
}

func (p *Project) Validate() []Issue {
	var out []Issue
	add := func(lv, where, msg string) { out = append(out, Issue{lv, where, msg}) }
	m := p.Manifest
	if !idRe.MatchString(m.ID) {
		add("error", "mod 信息", "id 要写成「作者.名字」，只用小写字母、数字、- 和 _，例如 kp.cheyun-gold")
	}
	if strings.TrimSpace(m.Name) == "" {
		add("error", "mod 信息", "名称不能为空")
	}
	events := map[int]bool{}
	for _, e := range p.Events {
		events[e.Local] = true
	}
	flags := map[int]bool{}
	for _, f := range p.Flags {
		flags[f.Local] = true
		if f.Local >= QuestFlagBase {
			add("error", fmt.Sprintf("旗标「%s」", f.Name), fmt.Sprintf("编号要小于 %d（%d 以上留给任务）", QuestFlagBase, QuestFlagBase))
		}
	}
	quests := map[int]bool{}
	for _, q := range p.Quests {
		where := fmt.Sprintf("任务「%s」", q.Title)
		if quests[q.Local] {
			add("error", where, "编号重复")
		}
		quests[q.Local] = true
		if q.Local < 1 || q.Local > 49 {
			add("error", where, "编号要在 1–49 之间")
		}
		if strings.TrimSpace(q.Title) == "" {
			add("error", where, "任务名不能为空")
		}
	}
	models := map[int]bool{}
	for _, m := range p.Models {
		where := fmt.Sprintf("模型「%s」", m.Name)
		models[m.Local] = true
		if !fileExists(filepath.Join(p.Dir, m.File)) {
			add("error", where, "模型文件不见了："+m.File)
		}
		if m.Scale <= 0 {
			add("error", where, "缩放要大于 0")
		}
		has := func(n string) bool {
			for _, a := range m.Anims {
				if a.Name == n {
					return true
				}
			}
			return false
		}
		if m.Idle != "" && !has(m.Idle) {
			add("error", where, "待机动画「"+m.Idle+"」在模型里找不到")
		}
		if m.Walk != "" && !has(m.Walk) {
			add("error", where, "行走动画「"+m.Walk+"」在模型里找不到")
		}
	}
	items := map[int]bool{}
	for _, it := range p.Items {
		where := fmt.Sprintf("物品「%s」", it.Name)
		if items[it.Local] {
			add("error", where, "编号重复")
		}
		items[it.Local] = true
		if it.Local < 1 || it.Local > 255 {
			add("error", where, "编号要在 1–255 之间")
		}
		if strings.TrimSpace(it.Name) == "" {
			add("error", where, "名字不能为空")
		}
		if it.Price < 0 {
			add("error", where, "价格不能是负数")
		}
		if it.Price == 0 {
			add("warning", where, "价格是 0，商店里白送、卖掉不给钱")
		}
	}
	vars := map[int]bool{}
	for _, v := range p.Vars {
		where := fmt.Sprintf("变量「%s」", v.Name)
		if vars[v.Local] {
			add("error", where, "编号重复")
		}
		vars[v.Local] = true
		if v.Local < 1 || v.Local > 999 {
			add("error", where, "编号要在 1–999 之间")
		}
	}
	monsters := map[int]bool{}
	for _, m := range p.Monsters {
		where := fmt.Sprintf("怪物「%s」", m.Name)
		if monsters[m.Local] {
			add("error", where, "编号重复")
		}
		monsters[m.Local] = true
		if m.Local < 1 || m.Local > 255 {
			add("error", where, "编号要在 1–255 之间")
		}
		if strings.TrimSpace(m.Name) == "" {
			add("error", where, "名字不能为空")
		}
		if m.Base <= 0 {
			add("error", where, "没选复制哪只原版怪物")
		}
		if m.Level < 1 || m.HP < 1 {
			add("error", where, "等级和生命至少是 1")
		}
		if m.Counter > 0 && !vars[m.Counter] {
			add("error", where, fmt.Sprintf("打倒时计数的变量 #%d 不存在", m.Counter))
		}
		if m.DropModItem > 0 && !items[m.DropModItem] {
			add("error", where, fmt.Sprintf("掉落的物品 #%d 不存在", m.DropModItem))
		}
		if m.Model > 0 {
			var cm *Model
			for i := range p.Models {
				if p.Models[i].Local == m.Model {
					cm = &p.Models[i]
				}
			}
			if cm == nil {
				add("error", where, fmt.Sprintf("战斗模型 #%d 不存在", m.Model))
			} else {
				has := map[string]bool{}
				for _, a := range cm.Anims {
					has[a.Name] = true
				}
				if m.Poses["14"] == "" {
					add("error", where, "用自定义战斗模型时要指定待机动画")
				}
				for q, c := range m.Poses {
					if c != "" && !has[c] {
						add("error", where, fmt.Sprintf("动作 %s 用的动画「%s」在模型里找不到", q, c))
					}
				}
			}
		}
		if m.DropRate > 0 && m.DropItem <= 0 && m.DropModItem <= 0 {
			add("warning", where, "掉落几率不是 0，但没选掉落物品")
		}
	}
	battles := map[int]bool{}
	for _, b := range p.Battles {
		where := fmt.Sprintf("战斗「%s」", b.Name)
		if battles[b.Local] {
			add("error", where, "编号重复")
		}
		battles[b.Local] = true
		if b.Local < 1 || b.Local > 63 {
			add("error", where, "编号要在 1–63 之间")
		}
		if b.Base <= 0 {
			add("error", where, "没选战场")
		}
		if len(b.Enemies) == 0 {
			add("error", where, "没有敌人")
		}
		at := map[int]bool{}
		for _, e := range b.Enemies {
			if at[e.At] {
				add("error", where, fmt.Sprintf("站位 %d 放了两个敌人", e.At+1))
			}
			at[e.At] = true
			if e.Monster <= 0 && e.ModMonster <= 0 {
				add("error", where, fmt.Sprintf("站位 %d 没选怪物", e.At+1))
			}
			if e.ModMonster > 0 && !monsters[e.ModMonster] {
				add("error", where, fmt.Sprintf("用的怪物 #%d 不存在", e.ModMonster))
			}
		}
	}
	p.validateChars(add)
	seenOv := map[int]bool{}
	for _, o := range p.Overrides {
		where := fmt.Sprintf("改原版事件 #%d", o.ID)
		if seenOv[o.ID] {
			add("error", where, "同一个事件改了两份")
		}
		seenOv[o.ID] = true
		for _, msg := range checkCode(o.Code) {
			add("error", where, msg)
		}
	}
	for _, e := range p.NpcEdits {
		where := fmt.Sprintf("地图 %d 的原版角色 %d", e.Map, e.Actor)
		if e.ModEvent > 0 && !events[e.ModEvent] {
			add("error", where, fmt.Sprintf("对话事件 #%d 不存在", e.ModEvent))
		}
		if e.Model > 0 && !models[e.Model] {
			add("error", where, fmt.Sprintf("自定义模型 #%d 不存在", e.Model))
		}
		if e.Remove {
			add("warning", where, "删掉原版 NPC 可能让剧情走不下去（要是剧情需要和它说话）")
		}
	}
	for _, e := range p.Encounters {
		where := fmt.Sprintf("地图 %d 的遇敌", e.Map)
		if !battles[e.Battle] {
			add("error", where, fmt.Sprintf("战斗 #%d 不存在", e.Battle))
		}
		if e.Weight < 1 || e.Weight > 20 {
			add("error", where, "权重要在 1–20 之间")
		}
	}
	npcs := map[int]bool{}
	for _, n := range p.NPCs {
		where := fmt.Sprintf("NPC「%s」", n.Name)
		if npcs[n.Local] {
			add("error", where, "编号重复")
		}
		npcs[n.Local] = true
		if n.Local < 1 || n.Local > 255 {
			add("error", where, "编号要在 1–255 之间")
		}
		if strings.TrimSpace(n.Name) == "" {
			add("warning", where, "没有名字，对话框标题会是空的")
		}
		if n.Talk && n.Event == 0 {
			add("warning", where, "可对话但没有设置对话事件")
		}
		if n.Model > 0 && !models[n.Model] {
			add("error", where, fmt.Sprintf("用的自定义模型 #%d 不存在", n.Model))
		}
		if n.Event > 0 && !events[n.Event] {
			add("error", where, fmt.Sprintf("对话事件 #%d 不存在", n.Event))
		}
	}
	for _, e := range p.Events {
		where := fmt.Sprintf("事件「%s」", e.Name)
		if len(e.Blocks) == 0 {
			add("warning", where, "是空的")
		}
		walk(e.Blocks, func(b Block) {
			switch b.Type {
			case "say", "notice":
				if strings.TrimSpace(b.Text) == "" {
					add("warning", where, "有一条对话没有内容")
				}
				if b.Type == "say" && strings.HasPrefix(b.Speaker, "npc:") {
					var k int
					fmt.Sscanf(b.Speaker, "npc:%d", &k)
					if !npcs[k] {
						add("error", where, fmt.Sprintf("说话的 NPC #%d 不存在", k))
					}
				}
			case "money":
				if b.Amount == 0 {
					add("warning", where, "金钱数量是 0")
				}
			case "item":
				if (b.Item <= 0 && b.ModItem <= 0) || b.Count == 0 {
					add("error", where, "道具或数量没填")
				}
				if b.ModItem > 0 && !items[b.ModItem] {
					add("error", where, fmt.Sprintf("用的物品 #%d 不存在", b.ModItem))
				}
			case "shop":
				if len(b.Goods) == 0 {
					add("error", where, "商店里没有货")
				}
				for _, g := range b.Goods {
					if g.ModItem > 0 && !items[g.ModItem] {
						add("error", where, fmt.Sprintf("商店卖的物品 #%d 不存在", g.ModItem))
					}
					if g.Item <= 0 && g.ModItem <= 0 {
						add("error", where, "商店里有一件货没选物品")
					}
				}
			case "quest", "if_quest":
				if !quests[b.Quest] {
					add("error", where, fmt.Sprintf("任务 #%d 不存在", b.Quest))
				}
			case "if_item":
				if (b.Item <= 0 && b.ModItem <= 0) || b.Count <= 0 {
					add("error", where, "「如果有物品」的物品或数量没填")
				}
				if b.ModItem > 0 && !items[b.ModItem] {
					add("error", where, fmt.Sprintf("用的物品 #%d 不存在", b.ModItem))
				}
			case "party":
				if b.Member != 2 && b.Member != 3 {
					add("error", where, "入队 / 离队只能是嬴诗或桓远之（车芸一直在队）")
				}
			case "var", "if_var":
				if !vars[b.Var] {
					add("error", where, fmt.Sprintf("变量 #%d 不存在", b.Var))
				}
				if b.Value < 0 || b.Value > 65535 {
					add("error", where, "变量的值要在 0–65535 之间")
				}
			case "battle":
				if !battles[b.Battle] {
					add("error", where, fmt.Sprintf("战斗 #%d 不存在", b.Battle))
				}
			case "flag", "if_flag":
				if !flags[b.Flag] {
					add("error", where, fmt.Sprintf("旗标 F%d 不存在", b.Flag))
				}
			}
		})
	}
	sort.SliceStable(out, func(i, j int) bool { return out[i].Level == "error" && out[j].Level != "error" })
	return out
}

func walk(bs []Block, f func(Block)) {
	for _, b := range bs {
		f(b)
		walk(b.Then, f)
		walk(b.Else, f)
	}
}

// saveOverrides: 写 overrides.json (游戏读, 见 godot/scripts/mod_manager.gd); 没改原版事件就删掉
func (p *Project) saveOverrides() error {
	path := filepath.Join(p.Dir, "overrides.json")
	if len(p.Overrides) == 0 {
		os.Remove(path)
		return nil
	}
	out := map[string]any{}
	for _, o := range p.Overrides {
		out[fmt.Sprint(o.ID)] = o.Code
	}
	return writeJSON(path, out)
}

// saveMonsters: 写 monsters.json (游戏读, 格式见 godot/scripts/mod_manager.gd); 没有怪物就删掉
func (p *Project) saveMonsters() error {
	path := filepath.Join(p.Dir, "monsters.json")
	if len(p.Monsters) == 0 {
		os.Remove(path)
		return nil
	}
	out := map[string]any{}
	for _, m := range p.Monsters {
		var drop any = 0
		if m.DropModItem > 0 {
			drop = fmt.Sprintf("@item:%d", m.DropModItem)
		} else if m.DropItem > 0 {
			drop = m.DropItem
		}
		rate := m.DropRate
		if drop == 0 {
			rate = 0
		}
		e := map[string]any{"base": m.Base, "name": m.Name, "desc": m.Desc, "level": m.Level,
			"hp": m.HP, "mp": m.MP, "sp": m.SP, "atk": m.Atk, "def": m.Def, "spd": m.Spd, "matk": m.Matk, "mdef": m.Mdef,
			"hit": m.Hit, "eva": m.Eva, "mhit": m.Mhit, "meva": m.Meva, "exp": m.Exp, "money": m.Money, "drop": []any{rate, drop}}
		if m.Counter > 0 {
			e["counter"] = m.Counter
		}
		if m.Model > 0 {
			e["model"] = fmt.Sprintf("@model:%d", m.Model)
			poses := map[string]string{}
			for q, c := range m.Poses {
				if c != "" {
					poses[q] = c
				}
			}
			e["poses"] = poses
		}
		out[fmt.Sprint(m.Local)] = e
	}
	return writeJSON(path, out)
}

// saveBattles: 写 battles.json (游戏读, 格式见 godot/scripts/mod_manager.gd); 没有战斗就删掉
func (p *Project) saveBattles() error {
	path := filepath.Join(p.Dir, "battles.json")
	if len(p.Battles) == 0 {
		os.Remove(path)
		return nil
	}
	out := map[string]any{}
	for _, b := range p.Battles {
		es := []any{}
		for _, e := range b.Enemies {
			var mon any = e.Monster
			if e.ModMonster > 0 {
				mon = fmt.Sprintf("@monster:%d", e.ModMonster)
			}
			es = append(es, map[string]any{"monster": mon, "at": e.At})
		}
		out[fmt.Sprint(b.Local)] = map[string]any{"base": b.Base, "enemies": es}
	}
	return writeJSON(path, out)
}

// saveQuests: 写 quests.json (游戏读, 格式见 godot/scripts/mod_manager.gd); 没有任务就删掉
func (p *Project) saveQuests() error {
	path := filepath.Join(p.Dir, "quests.json")
	if len(p.Quests) == 0 {
		os.Remove(path)
		return nil
	}
	out := map[string]any{}
	for _, q := range p.Quests {
		out[fmt.Sprint(q.Local)] = map[string]any{"text": q.Text(), "accept": flagRef(q.AcceptFlag()), "done": flagRef(q.DoneFlag())}
	}
	return writeJSON(path, out)
}

// saveItems: 写 items.json (游戏读, 格式见 godot/scripts/mod_manager.gd); 没有物品就删掉
func (p *Project) saveItems() error {
	path := filepath.Join(p.Dir, "items.json")
	if len(p.Items) == 0 {
		os.Remove(path)
		return nil
	}
	out := map[string]any{}
	for _, it := range p.Items {
		e := map[string]any{"base": it.Base, "name": it.Name, "desc": it.Desc, "price": it.Price}
		if len(it.FX1) == 6 {
			e["fx1"] = it.FX1
		}
		if len(it.FX2) == 7 {
			e["fx2"] = it.FX2
		}
		out[fmt.Sprint(it.Local)] = e
	}
	return writeJSON(path, out)
}

// saveModels: 写 models.json (动作 0 = 待机, 4 = 行走; 帧数 = 动画秒数 × 35), 删掉 models/ 里没被引用的 .glb
// (导入后没保存就删掉的模型留下的文件)
func (p *Project) saveModels() error {
	used := map[string]bool{}
	out := map[string]any{}
	for _, m := range p.Models {
		used[filepath.Base(m.File)] = true
		poses := map[string]any{}
		for q, clip := range map[string]string{"0": m.Idle, "4": m.Walk} {
			if clip == "" {
				continue
			}
			ticks := 35
			for _, a := range m.Anims {
				if a.Name == clip && a.Seconds > 0 {
					ticks = int(a.Seconds*35 + 0.5)
				}
			}
			poses[q] = map[string]any{"clip": clip, "loop": true, "ticks": ticks}
		}
		out[fmt.Sprint(m.Local)] = map[string]any{"name": m.Name, "file": m.File, "scale": m.Scale, "yaw": m.Yaw, "ground": m.Ground, "poses": poses}
	}
	files, _ := filepath.Glob(filepath.Join(p.Dir, "models", "*.glb"))
	for _, f := range files {
		if !used[filepath.Base(f)] {
			os.Remove(f)
		}
	}
	mj := filepath.Join(p.Dir, "models.json")
	if len(p.Models) == 0 {
		os.Remove(mj)
		return nil
	}
	return writeJSON(mj, out)
}

// checkCode: 事件指令的结构检查 (位置不重复、跳转目标存在); 指令名是否认识由 App 用指令表再查
func checkCode(code [][]any) []string {
	var out []string
	at := map[int]bool{}
	for _, ins := range code {
		if len(ins) < 2 {
			out = append(out, "有一条指令是空的")
			continue
		}
		p, ok := num(ins[0])
		if !ok {
			out = append(out, "指令位置不是数字")
			continue
		}
		if at[p] {
			out = append(out, fmt.Sprintf("位置 %d 重复", p))
		}
		at[p] = true
	}
	for _, ins := range code {
		if len(ins) < 2 {
			continue
		}
		for _, t := range JumpTargets(ins) {
			if !at[t] && !originalQuirk[fmt.Sprintf("%v@%v>%d", ins[1], ins[0], t)] {
				out = append(out, fmt.Sprintf("@%v 的「%v」跳到 @%d，那里没有指令", ins[0], ins[1], t))
			}
		}
	}
	return out
}

// originalQuirk: 原版数据里本来就跳不到指令边界的两处 (全部 1787 段代码 / 11143 个跳转里只有这两个; 复制这两个事件时不报错):
// 事件 2454 @2142 随机跳转的第 4 项指向 @2156 (指令中间); 事件 2103 @1661 if_all_flags_goto 的数据是坏的
var originalQuirk = map[string]bool{"random_goto@2142>2156": true, "if_all_flags_goto@1661>137955037": true}

func num(v any) (int, bool) {
	switch x := v.(type) {
	case float64:
		return int(x), true
	case int:
		return x, true
	}
	return 0, false
}

// SetJumpOperands: App 读到指令表后告诉这里每个指令的操作数类型
func SetJumpOperands(ops map[string]string) {
	for name, operands := range ops {
		jumpOperands[name] = operands
	}
}

var jumpOperands = map[string]string{}

// JumpTargets: 这条指令跳到的位置 (操作数 r = 一个位置, R / P = 位置列表)
func JumpTargets(ins []any) []int {
	op, _ := ins[1].(string)
	types, ok := jumpOperands[op]
	if !ok {
		return nil
	}
	var out []int
	args := ins[2:]
	for i, t := range types {
		if i >= len(args) {
			break
		}
		switch t {
		case 'r':
			if v, ok := num(args[i]); ok {
				out = append(out, v)
			}
		case 'R', 'P':
			if list, ok := args[i].([]any); ok {
				for _, x := range list {
					if v, ok := num(x); ok {
						out = append(out, v)
					}
				}
			}
		}
	}
	return out
}
