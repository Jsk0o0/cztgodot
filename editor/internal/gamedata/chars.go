package gamedata

// 队员 / 技能 (E4 / E5): 原版数据给编辑器参考和复制 —— 队员基础属性 (ObjDATA 1/2/3)、成长表 (LEVEL.GLL growth: 每级加的 12 项 + 习得法术)、
// 开局 (new_game.json init)、技能 (ObjDATA kind 3: 分类 201 攻击 / 202 恢复 / 203 辅助 / 302 修复 / 305 绝技 / 306 木甲)

import (
	"fmt"
	"path/filepath"
	"sort"
	"strconv"
)

type Member struct {
	ID     int            `json:"id"`
	Name   string         `json:"name"`
	Desc   string         `json:"desc"`
	Stats  map[string]int `json:"stats"`  // level hp mp sp atk def spd matk mdef hit eva mhit meva crit
	Growth [][]int        `json:"growth"` // [等级, HP, MP, SP, 攻, 防, 仙攻, 仙防, 命中, 回避, 仙命中, 仙回避, 速度, 习得法术]
	Act    int            `json:"act"`    // 地图模型 (新游戏全局角色表; 只有车芸在地图上走)
}

type NewGame struct {
	Money  int              `json:"money"`
	Items  []int            `json:"items"`
	Equip  map[string][]int `json:"equip"`
	Skills map[string][]int `json:"skills"`
}

type Skill struct {
	ID    int            `json:"id"`
	Name  string         `json:"name"`
	Desc  string         `json:"desc"`
	Sub   int            `json:"sub"`
	Cat   string         `json:"cat"`
	Note  string         `json:"note"` // 原版说明 (例「物理全体攻击」)
	Power int            `json:"power"`
	Cost  map[string]int `json:"cost"`
	FX1   []int          `json:"fx1"`
	FX2   []int          `json:"fx2"`
	Owner int            `json:"owner"` // 原版谁会 (开局或成长表里学会; 0 = 敌人 / 没人)
	Copy  bool           `json:"copy"`  // 能当新技能的底子 (攻击 / 恢复 / 辅助 / 绝技)
}

var skillCats = map[int]string{201: "攻击", 202: "恢复", 203: "辅助", 302: "修复", 305: "绝技", 306: "木甲"}

var statKeys = []string{"level", "hp", "mp", "sp", "atk", "def", "spd", "matk", "mdef", "hit", "eva", "mhit", "meva", "crit"}

func (s *Store) newGame() (*NewGame, []map[string]any, error) {
	var ng struct {
		Init   NewGame          `json:"init"`
		Actors []map[string]any `json:"actors"`
	}
	if err := readJSON(filepath.Join(s.Extracted, "game", "new_game.json"), &ng); err != nil {
		return nil, nil, fmt.Errorf("读不到开局数据: %w", err)
	}
	return &ng.Init, ng.Actors, nil
}

// Members: 三名队员的原版数据
func (s *Store) Members() ([]Member, *NewGame, error) {
	var raw struct {
		Objs   map[string]map[string]any `json:"objs"`
		Growth map[string][][]int        `json:"growth"`
	}
	if err := readJSON(filepath.Join(s.Extracted, "game", "battle.json"), &raw); err != nil {
		return nil, nil, err
	}
	ng, actors, err := s.newGame()
	if err != nil {
		return nil, nil, err
	}
	var out []Member
	for _, id := range []int{1, 2, 3} {
		o := raw.Objs[strconv.Itoa(id)]
		m := Member{ID: id, Stats: map[string]int{}, Growth: raw.Growth[strconv.Itoa(id)], Act: id}
		m.Name, _ = o["name"].(string)
		m.Desc, _ = o["desc"].(string)
		for _, k := range statKeys {
			if v, ok := o[k].(float64); ok {
				m.Stats[k] = int(v)
			}
		}
		for _, a := range actors {
			if v, _ := a["actor"].(float64); int(v) == id {
				if act, ok := a["act"].(float64); ok {
					m.Act = int(act)
				}
			}
		}
		out = append(out, m)
	}
	return out, ng, nil
}

// Skills: 原版技能 (队员的在前, 按编号)
func (s *Store) Skills() ([]Skill, error) {
	var raw struct {
		Objs map[string]struct {
			Name  string         `json:"name"`
			Kind  int            `json:"kind"`
			Sub   int            `json:"sub"`
			Desc  string         `json:"desc"`
			Note  string         `json:"note"`
			Power int            `json:"power"`
			Cost  map[string]int `json:"cost"`
			FX1   []int          `json:"fx1"`
			FX2   []int          `json:"fx2"`
		} `json:"objs"`
		Growth map[string][][]int `json:"growth"`
	}
	if err := readJSON(filepath.Join(s.Extracted, "game", "battle.json"), &raw); err != nil {
		return nil, err
	}
	owner := map[int]int{}
	if ng, _, err := s.newGame(); err == nil {
		for k, l := range ng.Skills {
			m, _ := strconv.Atoi(k)
			for _, sid := range l {
				owner[sid] = m
			}
		}
	}
	for k, rows := range raw.Growth {
		m, _ := strconv.Atoi(k)
		for _, r := range rows {
			if len(r) > 13 && r[13] > 0 {
				owner[r[13]] = m
			}
		}
	}
	var out []Skill
	for k, o := range raw.Objs {
		id, _ := strconv.Atoi(k)
		cat, ok := skillCats[o.Sub]
		if o.Kind != 3 || !ok || o.Name == "" {
			continue
		}
		out = append(out, Skill{ID: id, Name: o.Name, Desc: o.Desc, Sub: o.Sub, Cat: cat, Note: o.Note, Power: o.Power, Cost: o.Cost,
			FX1: o.FX1, FX2: o.FX2, Owner: owner[id], Copy: o.Sub == 201 || o.Sub == 202 || o.Sub == 203 || o.Sub == 305})
	}
	sort.Slice(out, func(i, j int) bool {
		if (out[i].Owner == 0) != (out[j].Owner == 0) {
			return out[i].Owner != 0
		}
		return out[i].ID < out[j].ID
	})
	return out, nil
}
