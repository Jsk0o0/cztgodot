class_name MenuQishu
extends RefCounted
## 主菜单「奇术」页 (初始化 0x48260f, 更新 0x48286c, 绘制 0x482fe5; 逆向笔记 re/menu_qishu.md)
##   不用先选人: 所有入队队员的法术 (kind 3) 分组列在一张表里, 每组前一行「------名字------」
##   页签 ACT 9025 (450+35k, 6): 恢复 202 / 辅助 203 / 攻击 201 / 绝技 305; 车芸的 302 木甲修复归恢复页, 306 机关术归辅助页 (要旗标 7)
##   列表板 0083 第 0 帧 (240,73), 消耗框 第 1 帧 (65,73), 说明栏 0081 第 1 帧 (62,478); 每页 14 行, 行高 25
##   技能名 16px x=Lx+40, 组标题 x=Lx+64; 地图上可用 (ObjDATA field_use 1/2) 且消耗够、施术者没倒下 → 调色板 15, 否则调色板 20
##   确认 → 状态 2 选施法对象: 三个状态面板 + 0153 选择框 (全体技能每个面板都框); 施法后留在状态 2, 可以连续施放
##   原版 bug 不照搬: 全体技能也检查灵力; 消耗框按施术者自己的上限换算百分比

const QI_UI := "ui/all_sys/0083_000_主介面奇术/%03d.png"
const ITEM_UI := "ui/all_sys/0081_000_主介面物品/%03d.png"
const TAB := "ui/all_sys/0041_000_奇术分类ICON/%03d.png"
const TAB_SEL := "ui/all_sys/0111_000_奇术分类ICON选/%03d.png"
const ICON3 := "ui/all_sys/0266_000_命灵体/%03d.png"
const FRAME := "ui/all_sys/0153_000_人物介面选择框/000.png"
const PAL20 := Color8(192, 80, 88)
const PAL16 := Color8(229, 69, 16)
## 页签: [分类码, 图标帧, 底栏名称]
const TABS := [[202, 1, "恢复"], [203, 2, "辅助"], [201, 0, "攻击"], [305, 3, "绝技"]]
const ROWS := 14
## 选中页签的跳动轨迹 (跳动对象 0xc70160, 14 帧循环)

var m: MainMenu
var state := 1          # 1 列表 / 2 选施法对象
var tab := 0
var sel := 0            # 全局行号
var top := 0
var target := 0         # 选施法对象: 队员下标
var _tab_t := 0.0


func _init(menu: MainMenu) -> void:
	m = menu
	_reset_list()


## 某队员在当前页签下的技能 (0x462296 / 0x4622f1)
func _skills(mem: int) -> Array:
	var sub: int = TABS[tab][0]
	var out: Array = []
	for s in State.skills_with_xian(mem):   # 奇术页里桓远之带上装备着的仙术 (0x48260f)
		var r := Battle.obj(int(s))
		if int(r.get("kind", 0)) != 3:
			continue
		var sb := int(r.get("sub", 0))
		if mem == 1:
			if sb == 302:
				sb = 202
			elif sb == 306:
				if not State.test_flag(7):
					continue
				sb = 203
		if sb == sub:
			out.append(int(s))
	return out


## 表格行: [队员, 技能号 (0 = 组标题)]
func rows() -> Array:
	var out: Array = []
	for mem in m._members:
		var sk := _skills(mem)
		if sk.is_empty():
			continue
		out.append([mem, 0])
		for s in sk:
			out.append([mem, s])
	return out


func _cost(v: int, mx: int) -> int:
	return Formula.cost_of(v, mx)


## 0x4839be 可否施放 (施术者 c, 技能 r, 目标 t; t = 0 只检查消耗). 返回错误提示, 空串 = 可以
func check(c: int, r: Dictionary, t: int) -> String:
	var cd := State.member(c)
	if t > 0:
		var tc := int(r.get("target_class", 0))
		if (t == 1 and tc & 0x4) or (t != 1 and tc & 0x8):
			return "无法对此对象使用!!"
	var cost: Dictionary = r.get("cost", {})
	if _cost(int(cost.get("mp", 0)), int(cd.mp_max)) > int(cd.mp):
		return "灵力不足,无法使用!!"
	if _cost(int(cost.get("sp", 0)), int(cd.sp_max)) > int(cd.sp):
		return "体力不足,无法使用!!"
	return ""


func usable(c: int, s: int) -> bool:
	var r := Battle.obj(s)
	return int(r.get("field_use", 0)) in [1, 2] and int(State.member(c).hp) > 0 and check(c, r, 0) == ""


## 0x483b15 对目标套用恢复效果; 返回是否有效
func _apply(t: int, r: Dictionary) -> bool:
	var tc := int(r.get("target_class", 0))
	if (t == 1 and tc & 0x4) or (t != 1 and tc & 0x8):
		return false
	var d := State.member(t)
	if int(d.hp) <= 0:
		return false   # 地图上普通治疗不能救倒下的人 (复活状态操作原版只处理解除死亡, 这里倒下 = HP 0, 一并不处理)
	var fx1: Array = r.get("fx1", [0, 0])
	var fx2: Array = r.get("fx2", [0])
	var hp := Formula.amount(int(fx1[0]), int(d.hp_max)) if int(fx1[0]) > 0 else 0
	var sp := Formula.amount(int(fx1[1]), int(d.sp_max)) if fx1.size() > 1 and int(fx1[1]) > 0 else 0
	var mp := Formula.amount(int(fx2[0]), int(d.mp_max)) if int(fx2[0]) > 0 else 0
	var need := (hp > 0 and int(d.hp) < int(d.hp_max)) or (mp > 0 and int(d.mp) < int(d.mp_max)) or (sp > 0 and int(d.sp) < int(d.sp_max))
	if not need:
		return false
	d.hp = mini(int(d.hp) + hp, int(d.hp_max))
	d.mp = mini(int(d.mp) + mp, int(d.mp_max))
	d.sp = mini(int(d.sp) + sp, int(d.sp_max))
	return true


func _cast() -> void:
	var rs := rows()
	var c: int = rs[sel][0]
	var s: int = rs[sel][1]
	var r := Battle.obj(s)
	var t: int = m._members[target]
	var err := check(c, r, 0 if int(r.get("scope", 0)) == 1 else t)
	if err != "":
		Game.play_sound(Game.SFX_UI_ERROR)
		m._say(err)
		return
	var ok := false
	if int(r.get("scope", 0)) == 1:
		for mem in m._members:
			ok = _apply(mem, r) or ok
		if not ok:
			m._say("目前不需要恢复!!")
	else:
		ok = _apply(t, r)
		if not ok:
			m._say("此角色并不需要恢复!!")
	if not ok:
		Game.play_sound(Game.SFX_UI_ERROR)
		return
	var cd := State.member(c)
	var cost: Dictionary = r.get("cost", {})
	cd.mp = int(cd.mp) - _cost(int(cost.get("mp", 0)), int(cd.mp_max))
	cd.sp = int(cd.sp) - _cost(int(cost.get("sp", 0)), int(cd.sp_max))
	Game.play_sound(541)


# ---------------- 绘制 ----------------

func draw(t: float, delta: float) -> void:
	_tab_t += delta
	if state == 2:
		_draw_targets(t)
		return
	for k in 4:
		var icon: int = TABS[k][1]
		if k == tab:
			m._img(TAB_SEL % icon, Vector2(450 + 35 * k, UiAct.bounce(8, int(_tab_t * 35.0))))
		else:
			m._img(TAB % icon, Vector2(450 + 35 * k, 6))
	m._text(TABS[tab][2], Vector2(60, 565), 20, MainMenu.DARK_COL)
	m._text(TABS[tab][2], Vector2(61, 565), 20, MainMenu.DARK_COL)
	var k2 := clampf(t * 3.0, 0.0, 1.0)
	var L := Vector2(lerpf(640, 240, k2), 73)
	var B := Vector2(lerpf(-200, 65, k2), 73)
	var D := Vector2(62, lerpf(600, 478, k2))
	m._img(QI_UI % 0, L)
	m._img(QI_UI % 1, B)
	m._img(ITEM_UI % 1, D)
	var rs := rows()
	m._img(QI_UI % 2, L + Vector2(315, -5))
	if rs.size() > ROWS:
		var th := 266.0 * ROWS / rs.size()
		m._c.draw_rect(Rect2(L.x + 324, L.y + 42 + 266.0 * top / rs.size(), 11, th), Color8(255, 253, 227, 200))
	m._img(ITEM_UI % 3, L + Vector2(320, 19))
	m._img(ITEM_UI % 4, L + Vector2(320, 312))
	if rs.is_empty():
		return
	sel = clampi(sel, 0, rs.size() - 1)
	for i in ROWS:
		var k := top + i
		if k >= rs.size():
			break
		var mem: int = rs[k][0]
		var s: int = rs[k][1]
		var y := L.y + 1 + 25 * i
		if s == 0:
			var nm: String = MainMenu.MEMBER_NAMES.get(mem, "")
			var dash := "-".repeat(12 - nm.length())
			m._text(dash + nm + dash, Vector2(L.x + 64, y), 16)
			continue
		if k == sel:
			m._c.draw_rect(Rect2(L.x, y - 8, 280, 32), Color(1, 1, 1, 0x32 / 255.0))
		var col := MainMenu.TEXT_COL if usable(mem, s) else PAL20
		var name := str(Battle.obj(s).get("name", s))
		m._text(name, Vector2(L.x + 40, y), 16, col)
		m._text(name, Vector2(L.x + 41, y), 16, col)
	# 消耗框 + 说明 (光标在技能行时)
	var cur: Array = rs[sel]
	if int(cur[1]) == 0:
		return
	var r := Battle.obj(int(cur[1]))
	var cd := State.member(int(cur[0]))
	var cost: Dictionary = r.get("cost", {})
	var vals := [_cost(int(cost.get("mp", 0)), int(cd.mp_max)), _cost(int(cost.get("sp", 0)), int(cd.sp_max)), int(cost.get("juji", 0))]
	var icons := [[2, Vector2(38, 5)], [3, Vector2(38, 30)], [9, Vector2(35, 56)]]
	for i in 3:
		m._img(ICON3 % int(icons[i][0]), B + icons[i][1])
		m._text("   %3d" % int(vals[i]), B + Vector2(50, 10 + 25 * i), 16)
		m._text("   %3d" % int(vals[i]), B + Vector2(51, 10 + 25 * i), 16)
	var rows := MainMenu.note_rows(r)
	for i in rows.size():
		m._text(rows[i][0], D + Vector2(12, 3 + 25 * i), 16, rows[i][1])


func _draw_targets(t: float) -> void:
	var rs := rows()
	var r := Battle.obj(int(rs[sel][1]))
	var all := int(r.get("scope", 0)) == 1
	var p := 0.025 + 0.025 * sin(t * 6.0)
	for i in m._members.size():
		var pos: Vector2 = MainMenu.PANEL_POS[i]
		m._draw_panel(m._members[i], pos)
		if all or i == target:
			var fr := m.tex(FRAME)
			if fr:
				# ACT 9019 qq14 的 IS 标签: 256×256 贴图里的 256×136 格子; 0x466459 把格子 (不是整张贴图) 缩放到 170×300
				var sz := Vector2(170, 300) * (1.0 + p)
				var k := fr.get_width() / 256.0   # 高清贴图是 2 倍 (2K) / 4 倍 (4K)
				m._c.draw_texture_rect_region(fr, Rect2(pos + Vector2(85, 150) - sz * 0.5, sz), Rect2(0, 0, 256 * k, 136 * k))


# ---------------- 输入 ----------------

func key(code: int) -> bool:
	var rs := rows()
	if state == 2:
		var n: int = m._members.size()
		match code:
			KEY_ESCAPE, KEY_CTRL:
				state = 1
				Game.play_sound(514)
			KEY_LEFT:
				target = (target + 1) % n
				Game.play_sound(513)
			KEY_RIGHT:
				target = (target + n - 1) % n
				Game.play_sound(513)
			KEY_UP:
				target = 0
				Game.play_sound(513)
			KEY_DOWN:
				target = n - 1
				Game.play_sound(513)
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				_cast()
		return true
	match code:
		KEY_ESCAPE, KEY_CTRL:
			return false
		KEY_LEFT, KEY_RIGHT:
			tab = (tab + (3 if code == KEY_LEFT else 1)) % 4
			_reset_list()
			Game.play_sound(513)
		KEY_UP, KEY_DOWN:
			if rs.size():
				var d := 1 if code == KEY_DOWN else -1
				var ns := clampi(sel + d, 0, rs.size() - 1)
				if int(rs[ns][1]) == 0:   # 跳过组标题
					ns = clampi(ns + d, 0, rs.size() - 1)
					if int(rs[ns][1]) == 0:
						ns = sel
				sel = ns
				top = clampi(top, sel - ROWS + 1, sel)
				Game.play_sound(513)
		KEY_PAGEUP, KEY_PAGEDOWN:
			if rs.size():
				sel = clampi(sel + (ROWS if code == KEY_PAGEDOWN else -ROWS), 0, rs.size() - 1)
				top = clampi(top, sel - ROWS + 1, sel)
				Game.play_sound(530)
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			_confirm()
	return true


func _reset_list() -> void:
	sel = 1 if rows().size() > 1 else 0   # 第 0 行是组标题
	top = 0
	_tab_t = 0.0


func _confirm() -> void:
	var rs := rows()
	if sel < rs.size() and int(rs[sel][1]) != 0 and usable(int(rs[sel][0]), int(rs[sel][1])):
		state = 2
		target = 0
	else:
		Game.play_sound(Game.SFX_UI_ERROR)


func mouse(p: Vector2, clicked: bool) -> bool:
	if state == 2:
		for i in m._members.size():
			var pos: Vector2 = MainMenu.PANEL_POS[i]
			if Rect2(pos + Vector2(0, 20), Vector2(170, 300)).has_point(p):
				if target != i:
					target = i
					Game.play_sound(513)
				if clicked:
					_cast()
				return clicked
		return clicked
	for k in 4:
		if Rect2(450 + 35 * k, 6, 30, 32).has_point(p):
			if clicked and k != tab:
				tab = k
				_reset_list()
				Game.play_sound(513)
			return clicked
	var rs := rows()
	for i in ROWS:
		if Rect2(240, 73 + 25 * i, 280, 25).has_point(p) and top + i < rs.size():
			if top + i != sel and int(rs[top + i][1]) != 0:
				sel = top + i
				Game.play_sound(513)
			if clicked:
				_confirm()
			return clicked
	return clicked


func fullscreen() -> bool:
	return state == 2
