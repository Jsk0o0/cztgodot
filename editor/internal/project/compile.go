package project

import (
	"fmt"
	"strings"
)

// Compile: 事件积木 → 游戏事件脚本 [[位置, 指令, 参数...], ...]
// 写法照原版路人对话 (例 talks2 事件 2016): script_begin / set_flag 8080 / reset_move_speed / set_pose 1 0 开头,
// 每句 set_caption + window_color + text + wait_text, 结尾 clear_flag 8080 / script_end / end。
// 位置只要求递增且不重复 (跳转用), 这里每条指令占 4。
func Compile(e Event, p *Project) ([][]any, error) {
	c := &compiler{p: p}
	c.emit("script_begin")
	c.emit("set_flag", 8080)
	c.emit("reset_move_speed")
	c.emit("set_pose", 1, 0)
	if err := c.blocks(e.Blocks); err != nil {
		return nil, err
	}
	c.finish()
	// 回填跳转目标
	for _, fx := range c.fixups {
		ins := c.code[fx.idx]
		ins[len(ins)-1] = c.labels[fx.label]
	}
	return c.code, nil
}

type fixup struct {
	idx   int
	label int
}

type compiler struct {
	p      *Project
	code   [][]any
	pos    int
	labels map[int]int
	fixups []fixup
	nlabel int
}

func (c *compiler) emit(op string, args ...any) {
	ins := append([]any{c.pos, op}, args...)
	c.code = append(c.code, ins)
	c.pos += 4
}

func (c *compiler) newLabel() int {
	c.nlabel++
	return c.nlabel
}

func (c *compiler) mark(l int) {
	if c.labels == nil {
		c.labels = map[int]int{}
	}
	c.labels[l] = c.pos
}

// 跳转指令: 最后一个参数是目标位置, 先占位, Compile 结尾回填
func (c *compiler) jump(op string, l int, args ...any) {
	c.emit(op, append(args, 0)...)
	c.fixups = append(c.fixups, fixup{len(c.code) - 1, l})
}

func (c *compiler) finish() {
	c.emit("clear_flag", 8080)
	c.emit("script_end")
	c.emit("end")
}

// 对话文字: % 是控制码前缀, 用户输入里的换成全角; 换行写成 %N
func cleanText(s string) string {
	s = strings.ReplaceAll(s, "%", "％")
	s = strings.ReplaceAll(s, "\r\n", "\n")
	return strings.ReplaceAll(s, "\n", "%N")
}

func speakerID(s string) (any, error) {
	switch {
	case s == "player" || s == "":
		return 1, nil
	case strings.HasPrefix(s, "npc:"):
		var n int
		if _, err := fmt.Sscanf(s, "npc:%d", &n); err != nil {
			return nil, fmt.Errorf("说话人 %q 不对", s)
		}
		return fmt.Sprintf("@npc:%d", n), nil
	case strings.HasPrefix(s, "actor:"):
		var n int
		if _, err := fmt.Sscanf(s, "actor:%d", &n); err != nil {
			return nil, fmt.Errorf("说话人 %q 不对", s)
		}
		return n, nil
	}
	return nil, fmt.Errorf("说话人 %q 不对", s)
}

func flagRef(n int) string { return fmt.Sprintf("@flag:%d", n) }

// branch: 条件已跳到 lThen / lElse 之后, 生成两个分支
func (c *compiler) branch(b Block, lThen, lElse, lEnd int) error {
	c.mark(lThen)
	if err := c.blocks(b.Then); err != nil {
		return err
	}
	c.jump("goto", lEnd)
	c.mark(lElse)
	if err := c.blocks(b.Else); err != nil {
		return err
	}
	c.mark(lEnd)
	return nil
}

func (c *compiler) quest(n int) Quest {
	if c.p != nil {
		for _, q := range c.p.Quests {
			if q.Local == n {
				return q
			}
		}
	}
	return Quest{Local: n}
}

// questUpdate: 原版「任务更新」提示 (逐条同事件 539 @8887–8955: 旗标 38 = 设定里关掉任务更新提示 → 跳过)
func (c *compiler) questUpdate() {
	l := c.newLabel()
	c.jump("if_flag_goto", l, 38)
	c.emit("play_sound", 527)
	c.emit("window_color", 150, 10, 10, 10)
	c.emit("text_char_spacing", 2)
	c.emit("text_line_spacing", 5)
	c.emit("text", 65281, 0, 320, 240, 320, 240, 0, 0, 1, 16384, "%C00%S00任务更新")
	c.emit("wait_text", 65281)
	c.mark(l)
	c.emit("nop")
}

// itemRef: 本 mod 物品写 "@item:N" (游戏加载时换成实际编号), 原版物品直接写编号
func (c *compiler) itemRef(item, modItem int) any {
	if modItem > 0 {
		return fmt.Sprintf("@item:%d", modItem)
	}
	return item
}

func (c *compiler) modItemName(n int) string {
	if c.p != nil {
		for _, it := range c.p.Items {
			if it.Local == n {
				return it.Name
			}
		}
	}
	return fmt.Sprintf("物品 %d", n)
}

// notice: 系统提示框 (同原版「得到【…】」: 音效 527, 角色 0xff01, 居中 (320, 240), 字速 %S00 一次显示;
// 颜色 / 字速码都写两位, 否则后面紧跟的数字会被当成参数; %C09 高亮色)
func (c *compiler) notice(text string) {
	c.emit("play_sound", 527)
	c.emit("window_color", 150, 10, 10, 10)
	c.emit("text", 65281, 0, 320, 240, 320, 240, 0, 0, 1, 16384, "%C00%S00"+text)
	c.emit("wait_text", 65281)
}

func (c *compiler) blocks(bs []Block) error {
	for _, b := range bs {
		switch b.Type {
		case "say":
			who, err := speakerID(b.Speaker)
			if err != nil {
				return err
			}
			c.emit("set_caption", who)
			c.emit("window_color", 150, 10, 10, 10)
			c.emit("text", who, 0, 0, 0, 0, 0, 6, 0, 0, 8192, cleanText(b.Text))
			c.emit("wait_text", who)
		case "notice":
			c.notice(cleanText(b.Text))
		case "money":
			c.emit("add_money", b.Amount)
			if !b.Quiet && b.Amount != 0 {
				if b.Amount > 0 {
					c.notice(fmt.Sprintf("得到【%%C09%d 金%%C00】", b.Amount))
				} else {
					c.notice(fmt.Sprintf("失去【%%C09%d 金%%C00】", -b.Amount))
				}
			}
		case "item":
			ref := c.itemRef(b.Item, b.ModItem)
			if b.Count >= 0 {
				c.emit("give_item", ref, b.Count)
			} else {
				c.emit("take_item", ref, -b.Count)
			}
			if !b.Quiet && b.Count != 0 {
				name := cleanText(b.ItemName)
				if b.ModItem > 0 {
					name = cleanText(c.modItemName(b.ModItem))
				}
				if name == "" {
					name = fmt.Sprintf("道具 %d", b.Item)
				}
				verb, n := "得到", b.Count
				if n < 0 {
					verb, n = "失去", -n
				}
				suffix := ""
				if n > 1 {
					suffix = fmt.Sprintf(" ×%d", n)
				}
				c.notice(fmt.Sprintf("%s【%%C09%s%%C00】%s", verb, name, suffix))
			}
		case "flag":
			if b.On {
				c.emit("set_flag", flagRef(b.Flag))
			} else {
				c.emit("clear_flag", flagRef(b.Flag))
			}
		case "if_flag":
			lThen, lEnd := c.newLabel(), c.newLabel()
			c.jump("if_flag_goto", lThen, flagRef(b.Flag))
			if err := c.blocks(b.Else); err != nil {
				return err
			}
			c.jump("goto", lEnd)
			c.mark(lThen)
			if err := c.blocks(b.Then); err != nil {
				return err
			}
			c.mark(lEnd)
		case "quest":
			q := c.quest(b.Quest)
			c.emit("set_flag", flagRef(q.AcceptFlag()))
			if b.Step == "done" {
				c.emit("set_flag", flagRef(q.DoneFlag()))
			}
			if !b.Quiet {
				c.questUpdate()
			}
		case "if_quest":
			q := c.quest(b.Quest)
			lThen, lElse, lEnd := c.newLabel(), c.newLabel(), c.newLabel()
			switch b.State {
			case "done":
				c.jump("if_flag_goto", lThen, flagRef(q.DoneFlag()))
				c.jump("goto", lElse)
			case "none":
				c.jump("if_flag_goto", lElse, flagRef(q.AcceptFlag()))
				c.jump("goto", lThen)
			default: // active: 接了、没完成
				c.jump("if_flag_goto", lElse, flagRef(q.DoneFlag()))
				c.jump("if_flag_goto", lThen, flagRef(q.AcceptFlag()))
				c.jump("goto", lElse)
			}
			if err := c.branch(b, lThen, lElse, lEnd); err != nil {
				return err
			}
		case "if_item":
			lThen, lElse, lEnd := c.newLabel(), c.newLabel(), c.newLabel()
			c.jump("if_item_goto", lThen, c.itemRef(b.Item, b.ModItem), b.Count)
			c.jump("goto", lElse)
			if err := c.branch(b, lThen, lElse, lEnd); err != nil {
				return err
			}
		case "shop":
			goods := []any{}
			for _, g := range b.Goods {
				goods = append(goods, c.itemRef(g.Item, g.ModItem))
			}
			c.emit("open_shop", goods)
		case "party":
			// 入队 / 离队: 原版剧情就是设 / 清旗标 2 (嬴诗)、3 (桓远之), 例: 事件 610 设 2、3
			if b.On {
				c.emit("set_flag", b.Member)
			} else {
				c.emit("clear_flag", b.Member)
			}
		case "var":
			// 变量 = 本 mod 0 号角色的角色变量 (见 project.go Var)
			if b.Op == "add" {
				c.emit("add_actor_var", "@npc:0", b.Var, b.Value)
			} else {
				c.emit("set_actor_var", "@npc:0", b.Var, b.Value)
			}
		case "if_var":
			lThen, lElse, lEnd := c.newLabel(), c.newLabel(), c.newLabel()
			op := "if_actor_var_ge_goto"
			if b.Cmp == "eq" {
				op = "if_actor_var_eq_goto"
			}
			c.jump(op, lThen, "@npc:0", b.Var, b.Value)
			c.jump("goto", lElse)
			if err := c.branch(b, lThen, lElse, lEnd); err != nil {
				return err
			}
		case "battle":
			// 同原版路人开战 (例 talks2 事件 162973): 对话脚本中间直接 start_battle 战场号, 打完接着往下
			c.emit("start_battle", fmt.Sprintf("@battle:%d", b.Battle))
		case "end":
			c.finish()
		default:
			return fmt.Errorf("不认识的积木 %q", b.Type)
		}
	}
	return nil
}
