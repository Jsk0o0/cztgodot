// Package gamedata 读取复刻工程导出的游戏数据 (extracted/game/*.json、collision/*.bin), 只读。
// 编辑器只引用玩家本机由原版提取出的数据, 自己不带任何原版素材。
package gamedata

import (
	"encoding/binary"
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"sync"
)

type rawMap struct {
	Name   string    `json:"name"`
	Title  string    `json:"title"`
	Scene  string    `json:"scene"`
	Wld    string    `json:"wld"`
	Offset []float64 `json:"offset"`
	Boxes  []rawBox  `json:"boxes"`
	Npcs   []rawNpc  `json:"npcs"`
	Enc    bool      `json:"encounters"`
	Zones  []struct {
		Group        int       `json:"group"`
		Min          []float64 `json:"min"`
		Max          []float64 `json:"max"`
		Battlefields []int     `json:"battlefields"`
	} `json:"zones"`
}

type rawBox struct {
	Event int       `json:"event"`
	Pos   []float64 `json:"pos"`
	Min   []float64 `json:"min"`
	Max   []float64 `json:"max"`
}

type rawNpc struct {
	Actor  int       `json:"actor"`
	Act    int       `json:"act"`
	Pos    []float64 `json:"pos"`
	Facing float64   `json:"facing"`
	Event  int       `json:"event"`
	Flags  int       `json:"flags"`
}

// MapInfo 地图列表项
type MapInfo struct {
	ID    int    `json:"id"`
	Name  string `json:"name"`  // 「12201_城镇_令狐国东城」
	Title string `json:"title"` // 画面左上角显示的地名
	Kind  string `json:"kind"`  // 城镇 / 户外 / 室内 / 迷宫 / 地图 / 剧情
}

// Npc 原版 NPC (地图上显示参考用)
type Npc struct {
	Actor  int        `json:"actor"`
	Name   string     `json:"name"`
	Act    int        `json:"act"`
	Pos    [3]float64 `json:"pos"`
	Facing float64    `json:"facing"`
	Event  int        `json:"event"` // 对话 / 调查事件 (0 = 没有)
}

// Box 原版事件框
type Box struct {
	Event int        `json:"event"`
	Min   [3]float64 `json:"min"`
	Max   [3]float64 `json:"max"`
}

// MapDetail 打开地图时给前端的数据
type MapDetail struct {
	MapInfo
	Scene  string     `json:"scene"`  // 相对 extracted 的 GLB 路径, 前端经 /gamedata/ 读取
	Offset [3]float64 `json:"offset"` // 场景 GLB 坐标 = (游戏坐标 + offset) × 0.01
	Npcs   []Npc      `json:"npcs"`
	Boxes  []Box      `json:"boxes"`
	// 遇敌区域 (原版 0x404f17: 主角在区域 x/z 范围内按概率组遇敌, 从战场列表里随机挑, 重复 = 权重); 没有遇敌的地图为空
	Zones []Zone `json:"zones"`
}

type Zone struct {
	Min     [2]float64 `json:"min"` // x, z
	Max     [2]float64 `json:"max"`
	Battles []int      `json:"battles"`
	Names   []string   `json:"names"` // 每个战场的敌人 (例「强盗×3」), 同 battles 顺序
}

// Model 可选的 NPC 模型 (原版 ACT, 只引用编号)
type Model struct {
	Act   int    `json:"act"`
	Label string `json:"label"` // 用这个模型的一个原版角色名, 方便辨认
	Glb   string `json:"glb"`   // 预览用, 相对 extracted
}

type Store struct {
	Extracted    string
	maps         map[string]rawMap
	people       map[string]string
	items        map[string]string
	gameItems    []Item
	rawBattle    *rawBattle
	evIndex      *eventsIndex
	snapIx       *snapIndex
	npcEvents    map[int]bool
	flagTests    map[int]map[int]bool // 旗标 → 判断它的事件 (共用代码的都算), 分类「影响剧情」用
	storyEv      map[int]bool         // 影响剧情的事件 (storyEvents)
	codeOf       map[int]string       // 事件号 → 文件:代码键 (共用代码的事件同一个键)
	evFiles      map[string]*eventFile
	chapters     []Chapter
	opcodes      map[string]Opcode
	monsters     []Monster
	battlefields []Battlefield
	coll         map[string]*collision
	mu           sync.Mutex
}

// Open 读 <extracted>/game 下的数据
func Open(extracted string) (*Store, error) {
	s := &Store{Extracted: extracted, coll: map[string]*collision{}}
	if err := readJSON(filepath.Join(extracted, "game", "maps.json"), &s.maps); err != nil {
		return nil, fmt.Errorf("读不到地图数据: %w", err)
	}
	var names struct {
		People map[string]string `json:"people"`
		Items  map[string]string `json:"items"`
	}
	if err := readJSON(filepath.Join(extracted, "game", "names.json"), &names); err != nil {
		return nil, fmt.Errorf("读不到人名表: %w", err)
	}
	s.people, s.items = names.People, names.Items
	return s, nil
}

func readJSON(p string, v any) error {
	b, err := os.ReadFile(p)
	if err != nil {
		return err
	}
	return json.Unmarshal(b, v)
}

func kindOf(name string) string {
	parts := strings.Split(name, "_")
	if len(parts) >= 3 {
		return parts[1]
	}
	return ""
}

func (s *Store) Maps() []MapInfo {
	out := make([]MapInfo, 0, len(s.maps))
	for k, m := range s.maps {
		id, _ := strconv.Atoi(k)
		out = append(out, MapInfo{ID: id, Name: m.Name, Title: m.Title, Kind: kindOf(m.Name)})
	}
	sort.Slice(out, func(i, j int) bool { return out[i].ID < out[j].ID })
	return out
}

func v3(a []float64) [3]float64 {
	var r [3]float64
	copy(r[:], a)
	return r
}

func (s *Store) Map(id int) (*MapDetail, error) {
	m, ok := s.maps[strconv.Itoa(id)]
	if !ok {
		return nil, fmt.Errorf("没有地图 %d", id)
	}
	d := &MapDetail{MapInfo: MapInfo{ID: id, Name: m.Name, Title: m.Title, Kind: kindOf(m.Name)}, Scene: m.Scene, Offset: v3(m.Offset)}
	for _, n := range m.Npcs {
		if n.Actor == 0 || n.Actor >= 0xff00 || (n.Act >= 12000 && n.Act < 15000) {
			continue
		}
		d.Npcs = append(d.Npcs, Npc{Actor: n.Actor, Name: s.people[strconv.Itoa(n.Actor)], Act: n.Act, Pos: v3(n.Pos), Facing: n.Facing, Event: n.Event})
	}
	for _, b := range m.Boxes {
		p := v3(b.Pos)
		mn, mx := v3(b.Min), v3(b.Max)
		d.Boxes = append(d.Boxes, Box{Event: b.Event,
			Min: [3]float64{p[0] + mn[0], p[1] + mn[1], p[2] + mn[2]}, Max: [3]float64{p[0] + mx[0], p[1] + mx[1], p[2] + mx[2]}})
	}
	if m.Enc {
		b, _ := s.battleData()
		for _, z := range m.Zones {
			if len(z.Min) < 3 || len(z.Max) < 3 {
				continue
			}
			zz := Zone{Min: [2]float64{z.Min[0], z.Min[2]}, Max: [2]float64{z.Max[0], z.Max[2]}, Battles: z.Battlefields}
			for _, bf := range z.Battlefields {
				zz.Names = append(zz.Names, battleLabel(b, bf))
			}
			d.Zones = append(d.Zones, zz)
		}
	}
	return d, nil
}

func (s *Store) battleData() (*rawBattle, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.battle()
}

// battleLabel: 战场的敌人, 同名合并 (例「强盗×3」)
func battleLabel(b *rawBattle, id int) string {
	if b == nil {
		return fmt.Sprint(id)
	}
	f, ok := b.Battlefields[strconv.Itoa(id)]
	if !ok {
		return fmt.Sprint(id)
	}
	var order []string
	cnt := map[string]int{}
	for _, e := range f.Enemies {
		n := b.Objs[strconv.Itoa(e.ID)].Name
		if cnt[n] == 0 {
			order = append(order, n)
		}
		cnt[n]++
	}
	parts := []string{}
	for _, n := range order {
		if cnt[n] > 1 {
			parts = append(parts, fmt.Sprintf("%s×%d", n, cnt[n]))
		} else {
			parts = append(parts, n)
		}
	}
	return strings.Join(parts, "、")
}

// Models: 原版 NPC 用过的人物模型 (ACT < 12000, 有导出文件), 标签取第一个用它的角色名
func (s *Store) Models() []Model {
	seen := map[int]Model{}
	ids := make([]string, 0, len(s.maps))
	for k := range s.maps {
		ids = append(ids, k)
	}
	sort.Strings(ids)
	for _, k := range ids {
		for _, n := range s.maps[k].Npcs {
			if n.Act <= 0 || n.Act >= 12000 {
				continue
			}
			if _, ok := seen[n.Act]; ok {
				continue
			}
			glb := fmt.Sprintf("game/actors/act_%d_g0.glb", n.Act)
			if _, err := os.Stat(filepath.Join(s.Extracted, glb)); err != nil {
				continue
			}
			label := s.people[strconv.Itoa(n.Actor)]
			if label == "" {
				label = "无名"
			}
			seen[n.Act] = Model{Act: n.Act, Label: label, Glb: glb}
		}
	}
	out := make([]Model, 0, len(seen))
	for _, m := range seen {
		out = append(out, m)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Act < out[j].Act })
	return out
}

func (s *Store) ItemName(id int) string { return s.items[strconv.Itoa(id)] }

// Item: 原版物品 (battle.json objs 里分类 201–211 的记录), mod 物品复制它
type Item struct {
	ID    int    `json:"id"`
	Name  string `json:"name"`
	Sub   int    `json:"sub"`
	Cat   string `json:"cat"`
	Price int    `json:"price"`
	Desc  string `json:"desc"`
	Icon  string `json:"icon"` // extracted 下的相对路径 (ui/all_item/…png)
	FX1   []int  `json:"fx1"`
	FX2   []int  `json:"fx2"`
}

// 分类码 → 名称 (同游戏 main_menu ITEM_TABS)
var itemCats = map[int]string{201: "攻击", 202: "恢复", 203: "辅助", 204: "武器", 205: "防具", 206: "饰品", 207: "法宝",
	208: "鞋", 209: "素材", 210: "剧情", 211: "剧情"}

// Items: 原版物品列表 (按编号), 第一次用时读 battle.json
func (s *Store) Items() ([]Item, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.gameItems != nil {
		return s.gameItems, nil
	}
	var b struct {
		Objs map[string]struct {
			Name  string `json:"name"`
			Sub   int    `json:"sub"`
			Price int    `json:"price"`
			Desc  string `json:"desc"`
			Icon  string `json:"icon"`
			FX1   []int  `json:"fx1"`
			FX2   []int  `json:"fx2"`
		} `json:"objs"`
	}
	if err := readJSON(filepath.Join(s.Extracted, "game", "battle.json"), &b); err != nil {
		return nil, fmt.Errorf("读不到物品数据: %w", err)
	}
	out := []Item{}
	for k, o := range b.Objs {
		cat, ok := itemCats[o.Sub]
		if !ok || o.Name == "" {
			continue
		}
		id, _ := strconv.Atoi(k)
		out = append(out, Item{ID: id, Name: o.Name, Sub: o.Sub, Cat: cat, Price: o.Price, Desc: o.Desc, Icon: o.Icon, FX1: o.FX1, FX2: o.FX2})
	}
	sort.Slice(out, func(i, j int) bool { return out[i].ID < out[j].ID })
	s.gameItems = out
	return out, nil
}
func (s *Store) PersonName(id int) string { return s.people[strconv.Itoa(id)] }

// ---------------- 地面 (同游戏 field.floor_at) ----------------

type collision struct {
	tris [][9]float64
}

func (s *Store) loadColl(wld string) (*collision, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if c, ok := s.coll[wld]; ok {
		return c, nil
	}
	b, err := os.ReadFile(filepath.Join(s.Extracted, "game", "collision", wld+".bin"))
	if err != nil {
		return nil, err
	}
	if len(b) < 8 {
		return nil, errors.New("碰撞数据损坏")
	}
	nt := int(binary.LittleEndian.Uint32(b[0:]))
	if len(b) < 8+nt*36 {
		return nil, errors.New("碰撞数据损坏")
	}
	c := &collision{tris: make([][9]float64, nt)}
	for i := 0; i < nt; i++ {
		for j := 0; j < 9; j++ {
			c.tris[i][j] = float64(math.Float32frombits(binary.LittleEndian.Uint32(b[8+i*36+j*4:])))
		}
	}
	s.coll[wld] = c
	return c, nil
}

// FloorAt: 在 (x, z) 处、高度 yHint ± span 内找碰撞地面, 返回最接近 yHint 的那层 (游戏坐标)
func (s *Store) FloorAt(mapID int, x, z, yHint, span float64) (float64, bool) {
	m, ok := s.maps[strconv.Itoa(mapID)]
	if !ok {
		return 0, false
	}
	c, err := s.loadColl(m.Wld)
	if err != nil {
		return 0, false
	}
	best, found := 0.0, false
	for _, t := range c.tris {
		y, hit := vertical(t, x, z)
		if !hit || y > yHint+span || y < yHint-span {
			continue
		}
		if !found || math.Abs(y-yHint) < math.Abs(best-yHint) {
			best, found = y, true
		}
	}
	return best, found
}

// 竖直线和三角形 (XZ 投影里重心坐标) 的交点高度
func vertical(t [9]float64, x, z float64) (float64, bool) {
	ax, ay, az := t[0], t[1], t[2]
	bx, by, bz := t[3], t[4], t[5]
	cx, cy, cz := t[6], t[7], t[8]
	d := (bz-cz)*(ax-cx) + (cx-bx)*(az-cz)
	if math.Abs(d) < 1e-9 {
		return 0, false
	}
	u := ((bz-cz)*(x-cx) + (cx-bx)*(z-cz)) / d
	v := ((cz-az)*(x-cx) + (ax-cx)*(z-cz)) / d
	w := 1 - u - v
	if u < -1e-6 || v < -1e-6 || w < -1e-6 {
		return 0, false
	}
	return u*ay + v*by + w*cy, true
}

// ---------------- 怪物 / 战场 (M8) ----------------

// Monster: 原版怪物 (battle.json objs 分类 110–120、在某个战场里当过敌人), mod 怪物复制它
type Monster struct {
	ID    int           `json:"id"`
	Name  string        `json:"name"`
	Race  string        `json:"race"` // 图鉴种族 (records.bestiary), 没有图鉴条目的为空
	Desc  string        `json:"desc"`
	Level int           `json:"level"`
	HP    int           `json:"hp"`
	MP    int           `json:"mp"`
	SP    int           `json:"sp"`
	Atk   int           `json:"atk"`
	Def   int           `json:"def"`
	Spd   int           `json:"spd"`
	Matk  int           `json:"matk"`
	Mdef  int           `json:"mdef"`
	Hit   int           `json:"hit"`
	Eva   int           `json:"eva"`
	Mhit  int           `json:"mhit"`
	Meva  int           `json:"meva"`
	Exp   int           `json:"exp"`
	Money int           `json:"money"`
	Drop  [2]int        `json:"drop"`  // [几率 %, 物品]
	Boss  bool          `json:"boss"`  // 分类 120 (首领)
	Glb   string        `json:"glb"`   // 预览模型, 相对 extracted
	Poses []MonsterPose `json:"poses"` // 战斗里会用到的动作 (自定义战斗模型要给它们配动画)
	Scale float64       `json:"scale"` // 待机动作 80 的 ACT 缩放 (xform 第 1 列, 同游戏 field_actor._apply_xform), 预览按它放大
}

// MonsterPose: 怪物在战斗里会播的一个动作 (来源 ACT 的帧数 / 循环; 用途 = 固定动作或普攻 / 技能的 ATK 脚本点名)
type MonsterPose struct {
	Q     int      `json:"q"`
	Ticks int      `json:"ticks"` // 帧数 (35 帧 / 秒)
	Loop  bool     `json:"loop"`
	Hits  int      `json:"hits"` // 命中记号数 (d / e)
	Uses  []string `json:"uses"`
}

// 战斗固定动作 (同游戏 battle.gd: IDLE_POSE 14, hurt 25 / 防御 24, 倒下 26, VICTORY_POSE 0x23)
var fixedPoses = []struct {
	q     int
	label string
}{{14, "待机"}, {25, "受伤"}, {24, "防御时受伤"}, {26, "倒下"}, {35, "胜利"}}

// BattleSlot: 原版战场里一个敌人的位置
type BattleSlot struct {
	Monster int        `json:"monster"`
	Name    string     `json:"name"`
	Pos     [3]float64 `json:"pos"`
	Facing  float64    `json:"facing"`
}

// Battlefield: 原版普通战场 (战斗脚本只有音乐 / 先手 / 开场演出 / 回合, 同游戏 Mods.is_base_battle)
type Battlefield struct {
	ID      int          `json:"id"`
	Name    string       `json:"name"`
	Scene   string       `json:"scene"`
	Slots   []BattleSlot `json:"slots"`
	Initial int          `json:"initiative"` // set_initiative 参数 (0 = 没写)
}

var battleSimpleOps = map[string]bool{"set_battle_music": true, "play_battle_music": true, "set_initiative": true,
	"start_battle": true, "run_battle_turns": true, "end_script": true, "end": true}

type rawObj struct {
	Name   string `json:"name"`
	Sub    int    `json:"sub"`
	Desc   string `json:"desc"`
	Level  int    `json:"level"`
	HP     int    `json:"hp"`
	MP     int    `json:"mp"`
	SP     int    `json:"sp"`
	Atk    int    `json:"atk"`
	Def    int    `json:"def"`
	Spd    int    `json:"spd"`
	Matk   int    `json:"matk"`
	Mdef   int    `json:"mdef"`
	Hit    int    `json:"hit"`
	Eva    int    `json:"eva"`
	Mhit   int    `json:"mhit"`
	Meva   int    `json:"meva"`
	Reward struct {
		Exp   int `json:"exp"`
		Money int `json:"money"`
	} `json:"reward"`
	Drops  [][2]int `json:"drops"`
	AtkID  int      `json:"atk_id"`
	Skills []int    `json:"skills"`
}

type rawBattle struct {
	Objs         map[string]rawObj `json:"objs"`
	Battlefields map[string]struct {
		Name    string `json:"name"`
		Scene   string `json:"scene"`
		Figtalk int    `json:"figtalk"`
		Enemies []struct {
			ID     int        `json:"id"`
			Pos    [3]float64 `json:"pos"`
			Facing float64    `json:"facing"`
		} `json:"enemies"`
	} `json:"battlefields"`
	Figtalk map[string][][]any `json:"figtalk"`
	Atk     map[string]struct {
		Steps []map[string]any `json:"steps"`
	} `json:"atk"`
}

func (s *Store) battle() (*rawBattle, error) {
	if s.rawBattle != nil {
		return s.rawBattle, nil
	}
	var b rawBattle
	if err := readJSON(filepath.Join(s.Extracted, "game", "battle.json"), &b); err != nil {
		return nil, fmt.Errorf("读不到战斗数据: %w", err)
	}
	s.rawBattle = &b
	return &b, nil
}

// Monsters: 能当 mod 怪物底子的原版怪物 (按编号)
func (s *Store) Monsters() ([]Monster, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.monsters != nil {
		return s.monsters, nil
	}
	b, err := s.battle()
	if err != nil {
		return nil, err
	}
	var rec struct {
		Bestiary []struct {
			ID   int    `json:"id"`
			Race string `json:"race"`
		} `json:"bestiary"`
	}
	readJSON(filepath.Join(s.Extracted, "game", "records.json"), &rec)
	race := map[int]string{}
	for _, e := range rec.Bestiary {
		race[e.ID] = e.Race
	}
	enemy := map[int]bool{}
	for _, f := range b.Battlefields {
		for _, e := range f.Enemies {
			enemy[e.ID] = true
		}
	}
	out := []Monster{}
	for k, o := range b.Objs {
		id, _ := strconv.Atoi(k)
		if !enemy[id] || o.Sub < 110 || o.Sub > 120 || o.Name == "" {
			continue
		}
		m := Monster{ID: id, Name: o.Name, Race: race[id], Desc: o.Desc, Level: o.Level, HP: o.HP, MP: o.MP, SP: o.SP,
			Atk: o.Atk, Def: o.Def, Spd: o.Spd, Matk: o.Matk, Mdef: o.Mdef, Hit: o.Hit, Eva: o.Eva, Mhit: o.Mhit, Meva: o.Meva,
			Exp: o.Reward.Exp, Money: o.Reward.Money, Boss: o.Sub == 120}
		if len(o.Drops) > 0 {
			m.Drop = o.Drops[0]
		}
		glb := fmt.Sprintf("game/actors/act_%d_g0.glb", id)
		if _, err := os.Stat(filepath.Join(s.Extracted, glb)); err == nil {
			m.Glb = glb
		}
		m.Scale = 1
		var act struct {
			Poses map[string]struct {
				Ticks int         `json:"ticks"`
				Loop  bool        `json:"loop"`
				Marks [][]any     `json:"marks"`
				Xform [][]float64 `json:"xform"`
			} `json:"poses"`
		}
		if readJSON(filepath.Join(s.Extracted, "game", "actors", fmt.Sprintf("act_%d.json", id)), &act) == nil {
			if x := act.Poses["80"].Xform; len(x) > 0 && len(x[0]) > 1 && x[0][1] > 0 {
				m.Scale = x[0][1]
			}
			uses := map[int][]string{}
			add := func(q int, u string) {
				for _, x := range uses[q] {
					if x == u {
						return
					}
				}
				uses[q] = append(uses[q], u)
			}
			for _, f := range fixedPoses {
				add(f.q, f.label)
			}
			atkPoses := func(aid int, label string) {
				for _, st := range b.Atk[strconv.Itoa(aid)].Steps {
					if st["fig"] == true || st["actor"] != nil {
						continue
					}
					if q, ok := st["pose"].(float64); ok {
						if st["t"] == "move" {
							add(int(q), label+"（移动）")
						} else {
							add(int(q), label)
						}
					}
				}
			}
			atkPoses(o.AtkID, "普攻")
			for _, sk := range o.Skills {
				if sk > 0 {
					so := b.Objs[strconv.Itoa(sk)]
					atkPoses(so.AtkID, "技能「"+so.Name+"」")
				}
			}
			for q, u := range uses {
				ap, ok := act.Poses[strconv.Itoa(q)]
				if !ok {
					continue
				}
				hits := 0
				for _, mk := range ap.Marks {
					if len(mk) > 1 && (mk[1] == "d" || mk[1] == "e") {
						hits++
					}
				}
				m.Poses = append(m.Poses, MonsterPose{Q: q, Ticks: ap.Ticks, Loop: ap.Loop, Hits: hits, Uses: u})
			}
			sort.Slice(m.Poses, func(i, j int) bool { return m.Poses[i].Q < m.Poses[j].Q })
		}
		out = append(out, m)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].ID < out[j].ID })
	s.monsters = out
	return out, nil
}

// Battlefields: 能当 mod 战斗底子的原版普通战场 (按编号)
func (s *Store) Battlefields() ([]Battlefield, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.battlefields != nil {
		return s.battlefields, nil
	}
	b, err := s.battle()
	if err != nil {
		return nil, err
	}
	out := []Battlefield{}
	for k, f := range b.Battlefields {
		id, _ := strconv.Atoi(k)
		ft, ok := b.Figtalk[strconv.Itoa(f.Figtalk)]
		if !ok || len(ft) == 0 || len(f.Enemies) == 0 {
			continue
		}
		simple, init := true, 0
		for _, ins := range ft {
			op, _ := ins[1].(string)
			if !battleSimpleOps[op] {
				simple = false
				break
			}
			if op == "set_initiative" && len(ins) > 2 {
				if v, ok := ins[2].(float64); ok {
					init = int(v)
				}
			}
		}
		if !simple {
			continue
		}
		bf := Battlefield{ID: id, Name: f.Name, Scene: f.Scene, Initial: init}
		for _, e := range f.Enemies {
			bf.Slots = append(bf.Slots, BattleSlot{Monster: e.ID, Name: b.Objs[strconv.Itoa(e.ID)].Name, Pos: e.Pos, Facing: e.Facing})
		}
		out = append(out, bf)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].ID < out[j].ID })
	s.battlefields = out
	return out, nil
}
