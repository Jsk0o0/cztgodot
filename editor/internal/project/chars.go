package project

// 队员 / 开局 / 技能 (E4 / E5), 游戏端格式见 godot/scripts/mod_manager.gd (characters.json / newgame.json / skills.json)

import (
	"fmt"
	"os"
	"path/filepath"
)

// SkillRef: 原版技能号 skill 或本方案技能 modSkill (二选一)
type SkillRef struct {
	Skill    int `json:"skill,omitempty"`
	ModSkill int `json:"modSkill,omitempty"`
}

func (r SkillRef) out() any {
	if r.ModSkill > 0 {
		return fmt.Sprintf("@skill:%d", r.ModSkill)
	}
	return r.Skill
}

// GrowthRow: 成长表一行 (升到 Lv 级时加的 12 项, 同游戏 State.add_exp) + 这一级学会的技能
type GrowthRow struct {
	Lv    int      `json:"lv"`
	Inc   [12]int  `json:"inc"` // HP MP SP 攻 防 仙攻 仙防 命中 回避 仙命中 仙回避 速度
	Learn SkillRef `json:"learn"`
}

// CharEdit: 改一名队员 (1 车芸 / 2 嬴诗 / 3 桓远之); 没写的项照原版
type CharEdit struct {
	ID       int            `json:"id"`
	Name     *string        `json:"name,omitempty"`
	Desc     *string        `json:"desc,omitempty"`
	Stats    map[string]int `json:"stats,omitempty"`  // level hp mp sp atk def spd matk mdef hit eva mhit meva crit
	Growth   []GrowthRow    `json:"growth,omitempty"` // 整张成长表 (改过才有)
	MapAct   *int           `json:"mapAct,omitempty"` // 车芸在地图上的原版模型
	MapModel int            `json:"mapModel,omitempty"`
}

// NewGameEdit: 改开局; nil / 空 = 照原版
type NewGameEdit struct {
	Money  *int                  `json:"money,omitempty"`
	Items  []ItemRefP            `json:"items,omitempty"`
	Party  []int                 `json:"party,omitempty"`  // 开局在队 (1 一定在)
	Skills map[string][]SkillRef `json:"skills,omitempty"` // 队员 → 开局会的技能
	Equip  map[string][]int      `json:"equip,omitempty"`  // 队员 → 8 格装备 (原版物品)
}

// ItemRefP: 原版物品 item 或本方案物品 modItem
type ItemRefP struct {
	Item    int `json:"item,omitempty"`
	ModItem int `json:"modItem,omitempty"`
}

// ModSkill: 本方案的新技能 = 复制原版技能 Base (演出 / 范围 / 属性照抄), 改名字 / 说明 / 威力 / 消耗 / 恢复量
type ModSkill struct {
	Local int            `json:"local"` // @skill:N
	Base  int            `json:"base"`
	Name  string         `json:"name"`
	Desc  string         `json:"desc"`
	Power int            `json:"power"`
	Cost  map[string]int `json:"cost"` // hp sp mp juji
	FX1   []int          `json:"fx1,omitempty"`
	FX2   []int          `json:"fx2,omitempty"`
}

// SkillEdit: 改原版技能的这几项 (nil = 不改)
type SkillEdit struct {
	ID    int            `json:"id"`
	Name  *string        `json:"name,omitempty"`
	Desc  *string        `json:"desc,omitempty"`
	Power *int           `json:"power,omitempty"`
	Cost  map[string]int `json:"cost,omitempty"`
}

var statKeys = []string{"level", "hp", "mp", "sp", "atk", "def", "spd", "matk", "mdef", "hit", "eva", "mhit", "meva", "crit"}

func (p *Project) saveChars() error {
	path := filepath.Join(p.Dir, "characters.json")
	if len(p.Characters) == 0 {
		os.Remove(path)
		return nil
	}
	out := map[string]any{}
	for _, c := range p.Characters {
		e := map[string]any{}
		if c.Name != nil {
			e["name"] = *c.Name
		}
		if c.Desc != nil {
			e["desc"] = *c.Desc
		}
		for _, k := range statKeys {
			if v, ok := c.Stats[k]; ok {
				e[k] = v
			}
		}
		if len(c.Growth) > 0 {
			rows := []any{}
			for _, r := range c.Growth {
				row := []any{r.Lv}
				for _, x := range r.Inc {
					row = append(row, x)
				}
				rows = append(rows, append(row, r.Learn.out()))
			}
			e["growth"] = rows
		}
		if c.MapModel > 0 {
			e["map_act"] = fmt.Sprintf("@model:%d", c.MapModel)
		} else if c.MapAct != nil {
			e["map_act"] = *c.MapAct
		}
		if len(e) > 0 {
			out[fmt.Sprint(c.ID)] = e
		}
	}
	if len(out) == 0 {
		os.Remove(path)
		return nil
	}
	return writeJSON(path, out)
}

func (p *Project) saveNewGame() error {
	path := filepath.Join(p.Dir, "newgame.json")
	ng := p.NewGame
	out := map[string]any{}
	if ng != nil {
		if ng.Money != nil {
			out["money"] = *ng.Money
		}
		if ng.Items != nil {
			items := []any{}
			for _, it := range ng.Items {
				if it.ModItem > 0 {
					items = append(items, fmt.Sprintf("@item:%d", it.ModItem))
				} else {
					items = append(items, it.Item)
				}
			}
			out["items"] = items
		}
		if len(ng.Party) > 0 {
			out["party"] = ng.Party
		}
		if len(ng.Skills) > 0 {
			sk := map[string]any{}
			for m, l := range ng.Skills {
				refs := []any{}
				for _, r := range l {
					refs = append(refs, r.out())
				}
				sk[m] = refs
			}
			out["skills"] = sk
		}
		if len(ng.Equip) > 0 {
			out["equip"] = ng.Equip
		}
	}
	if len(out) == 0 {
		os.Remove(path)
		return nil
	}
	return writeJSON(path, out)
}

func (p *Project) saveSkills() error {
	path := filepath.Join(p.Dir, "skills.json")
	out := map[string]any{}
	for _, s := range p.Skills {
		e := map[string]any{"base": s.Base, "name": s.Name, "desc": s.Desc, "power": s.Power}
		if len(s.Cost) > 0 {
			e["cost"] = s.Cost
		}
		if len(s.FX1) == 6 {
			e["fx1"] = s.FX1
		}
		if len(s.FX2) == 7 {
			e["fx2"] = s.FX2
		}
		out[fmt.Sprint(s.Local)] = e
	}
	for _, s := range p.SkillEdits {
		e := map[string]any{}
		if s.Name != nil {
			e["name"] = *s.Name
		}
		if s.Desc != nil {
			e["desc"] = *s.Desc
		}
		if s.Power != nil {
			e["power"] = *s.Power
		}
		if len(s.Cost) > 0 {
			e["cost"] = s.Cost
		}
		if len(e) > 0 {
			out[fmt.Sprint(s.ID)] = e
		}
	}
	if len(out) == 0 {
		os.Remove(path)
		return nil
	}
	return writeJSON(path, out)
}

// validateChars: 队员 / 开局 / 技能的校验
func (p *Project) validateChars(add func(level, where, msg string)) {
	skills := map[int]bool{}
	for _, s := range p.Skills {
		where := fmt.Sprintf("技能「%s」", s.Name)
		if skills[s.Local] {
			add("error", where, "编号重复")
		}
		skills[s.Local] = true
		if s.Local < 1 || s.Local > 255 {
			add("error", where, "编号要在 1–255 之间")
		}
		if s.Name == "" {
			add("error", where, "名字不能为空")
		}
	}
	checkRef := func(where string, r SkillRef) {
		if r.ModSkill > 0 && !skills[r.ModSkill] {
			add("error", where, fmt.Sprintf("用的技能 #%d 不存在", r.ModSkill))
		}
	}
	names := map[int]string{1: "车芸", 2: "嬴诗", 3: "桓远之"}
	for _, c := range p.Characters {
		where := fmt.Sprintf("队员「%s」", names[c.ID])
		if c.ID < 1 || c.ID > 3 {
			add("error", where, "只能改 1 车芸 / 2 嬴诗 / 3 桓远之")
		}
		if lv, ok := c.Stats["level"]; ok && (lv < 1 || lv > 99) {
			add("error", where, "初始等级要在 1–99 之间")
		}
		for _, r := range c.Growth {
			checkRef(where+fmt.Sprintf("第 %d 级", r.Lv), r.Learn)
		}
		if c.MapModel > 0 {
			ok := false
			for _, m := range p.Models {
				ok = ok || m.Local == c.MapModel
			}
			if !ok {
				add("error", where, fmt.Sprintf("地图模型 #%d 不存在", c.MapModel))
			}
		}
		if (c.MapAct != nil || c.MapModel > 0) && c.ID != 1 {
			add("warning", where, "地图上只有车芸在走，其他队员的地图模型不会用到")
		}
	}
	if p.NewGame != nil {
		for m, l := range p.NewGame.Skills {
			for _, r := range l {
				checkRef(fmt.Sprintf("开局技能（队员 %s）", m), r)
			}
		}
		for _, it := range p.NewGame.Items {
			ok := it.ModItem == 0
			for _, x := range p.Items {
				ok = ok || x.Local == it.ModItem
			}
			if !ok {
				add("error", "开局物品", fmt.Sprintf("用的物品 #%d 不存在", it.ModItem))
			}
		}
	}
}
