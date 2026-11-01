class_name MenuJiguan
extends RefCounted
## 主菜单「机关」页 = 车芸的「木甲研發」技术树 (初始化 0x48ad3f, 逻辑 0x48aeee, 绘制 0x48bb4c; 逆向笔记 re/menu_jiguan.md)
##   25 个技术节点 (圆点) 花木甲技术点数点亮; 27 块三角板 = 机关成果 (法术 6001–6033), 三个顶点都点亮就自动授予:
##   招式 → 车芸 (战斗中是云狐) 学会; 306 被动 (加速 / 巧动 / 奋力 …) → 永久套用到车芸身上。不消耗金属木材, 没有确认框
##   页签 ACT 9028 (500+35k, 6): 0 树 / 1 「木甲列表」(只读, 已出现的成果及消耗)
##   第一次打开且旗标 130 置位: 点数 += 1..车芸等级的累计获得点数, 木甲术 6024–6027 登记为 1 级, 清旗标 130

const UI := "ui/all_sys/0262_000_主介面机关列表/%03d.png"
const TAB := "ui/all_sys/0043_000_机关分类/%03d.png"
const GLOW := "ui/all_magic/0013_木甲升级点数_蓝/%03d.png"
const QI_UI := "ui/all_sys/0083_000_主介面奇术/%03d.png"
const ITEM_UI := "ui/all_sys/0081_000_主介面物品/%03d.png"
const ICON3 := "ui/all_sys/0266_000_命灵体/%03d.png"
const PAL19 := Color8(166, 124, 82)
const PAL21 := Color8(91, 110, 70)
## 9018 动作 qq → 0262 帧
const QQ_FRAME := {0: 0, 1: 7, 2: 8, 3: 9, 4: 1, 5: 2, 6: 3, 7: 4, 8: 5, 9: 6, 10: 10, 11: 11, 12: 12, 13: 13, 14: 14}
## 类别 → 升级的木甲术 (0x48e034): 1 卸甲 2 瘫痪 3 拆解
const CAT_MECH := {1: 6026, 2: 6027, 3: 6025}

## 节点 (0x48d473 建表): id → [x, y (24×24 圆点左上角), 价格]
const NODES := {1: [157, 154, 600], 2: [270, 154, 300], 3: [383, 154, 600], 4: [99, 212, 300], 5: [213, 212, 100], 6: [327, 212, 100], 7: [441, 212, 300], 8: [41, 269, 600], 9: [156, 269, 100], 10: [270, 269, 0], 11: [384, 269, 100], 12: [498, 269, 600], 13: [99, 327, 300], 14: [213, 327, 100], 15: [327, 327, 100], 16: [441, 327, 300], 17: [156, 385, 600], 18: [270, 385, 300], 19: [384, 385, 600], 20: [99, 443, 1000], 21: [213, 443, 1000], 22: [556, 212, 1000], 23: [558, 326, 1000], 24: [99, 97, 1000], 25: [215, 97, 1000]}
## 机关板 (0x48cc2e 建表), 板号 = 下标: [前置节点, x, y (板图左上角), 法术号, 授予 (1 学会 / 0 被动套用), 类别, kind, 形状 (0 ▽ 1 △ 2 ◁), 列表排序号]
const MECHS := [
	[[1, 4, 5], 123, 178, 6031, 0, 1, 1, 1, 14],
	[[1, 5, 2], 180, 171, 6006, 1, 1, 1, 0, 20],
	[[2, 5, 6], 237, 178, 6018, 1, 1, 2, 1, 19],
	[[2, 6, 3], 294, 171, 6019, 1, 1, 1, 0, 21],
	[[3, 6, 7], 351, 178, 6010, 1, 2, 1, 1, 12],
	[[4, 8, 9], 66, 236, 6022, 1, 1, 1, 1, 15],
	[[4, 9, 5], 123, 229, 6021, 1, 1, 2, 0, 13],
	[[5, 9, 10], 180, 236, 6028, 0, 1, 2, 1, 6],
	[[5, 10, 6], 237, 229, 6001, 1, 1, 2, 0, 1],
	[[6, 10, 11], 294, 236, 6029, 0, 2, 2, 1, 2],
	[[6, 11, 7], 351, 229, 6005, 1, 2, 2, 0, 10],
	[[7, 11, 12], 408, 236, 6032, 0, 2, 1, 1, 11],
	[[8, 13, 9], 66, 287, 6017, 1, 3, 1, 0, 24],
	[[9, 13, 14], 123, 294, 6016, 1, 3, 2, 1, 22],
	[[9, 14, 10], 180, 287, 6003, 1, 3, 2, 0, 5],
	[[10, 14, 15], 237, 294, 6030, 0, 3, 2, 1, 4],
	[[10, 15, 11], 294, 287, 6002, 1, 2, 2, 0, 3],
	[[11, 15, 16], 351, 294, 6014, 1, 2, 2, 1, 16],
	[[11, 16, 12], 408, 287, 6007, 1, 2, 1, 0, 17],
	[[13, 17, 14], 123, 345, 6008, 1, 3, 1, 0, 23],
	[[14, 17, 18], 180, 352, 6033, 0, 3, 1, 1, 8],
	[[14, 18, 15], 237, 345, 6004, 1, 3, 2, 0, 7],
	[[15, 18, 19], 294, 352, 6009, 1, 3, 1, 1, 9],
	[[15, 19, 16], 351, 345, 6015, 1, 2, 1, 0, 18],
	[[1, 24, 25], 123, 113, 6023, 1, 4, 3, 0, 25],
	[[12, 22, 23], 522, 236, 6011, 1, 4, 3, 2, 27],
	[[17, 20, 21], 123, 410, 6012, 1, 4, 3, 1, 26]]
## 键盘导航 (0x48dccf): 节点 → [左, 右, 上, 下]
const NAV := {1: [1, 2, 24, 4], 2: [1, 3, 2, 5], 3: [2, 7, 3, 6], 4: [4, 5, 1, 8], 5: [4, 6, 2, 9], 6: [5, 7, 3, 10], 7: [6, 12, 3, 11], 8: [8, 9, 4, 13], 9: [8, 10, 5, 14], 10: [9, 11, 6, 15], 11: [10, 12, 7, 16], 12: [11, 22, 7, 16], 13: [13, 14, 8, 17], 14: [13, 15, 9, 18], 15: [14, 16, 10, 19], 16: [15, 19, 11, 19], 17: [17, 18, 13, 20], 18: [17, 19, 14, 18], 19: [18, 19, 15, 19], 20: [17, 21, 17, 21], 21: [20, 17, 18, 20], 22: [12, 23, 12, 23], 23: [12, 22, 22, 12], 24: [1, 25, 25, 1], 25: [24, 1, 24, 2]}

var m: MainMenu
var state := 0              # 0 树 (鼠标) / 3 树 (键盘光标) / 1 列表
var cursor := 0             # 光标 / 悬停节点
var hover_mech := -1
var lsel := 0
var ltop := 0
var pops: Array = []        # [{text, t}] 「獲得 X」/「提升至二級」提示
var _flash := {}            # 类别 → [升到的级, 剩余帧]
var _spark := {}            # 正在播的随机闪光 {n, ticks} (同一时间只有一个, [0xc75094])
var _hl_ticks := 0          # 高亮光圈播放器 0xc74e68
var _jg_acc2 := 0.0


func free_fx() -> void:
	if is_instance_valid(_fx):
		_fx.queue_free()


var _fx: Control   # 加法混合层 (光圈 / 闪光原版是黑底加亮贴图)
var _fx_items: Array = []   # [tex, rect, alpha]


func _init(menu: MainMenu) -> void:
	m = menu
	_fx = Control.new()
	_fx.size = Vector2(800, 600)
	_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_fx.material = mat
	_fx.draw.connect(func():
		for it in _fx_items:
			if it[0] is String:   # ["sprite", 帧, 位置]: 0x46a983 画法
				UiAct.draw_sprite(_fx, it[1], it[2])
			else:
				_fx.draw_texture_rect(it[0], it[1], false, Color(1, 1, 1, it[2])))
	m._c.add_child(_fx)
	if State.test_flag(130):
		var g := State.tech_sum(int(State.member(1).lv))
		State.tech += g
		State.tech_total += g
		for s in [6024, 6025, 6026, 6027]:
			State.mech_lv[s] = maxi(int(State.mech_lv.get(s, 0)), 1)
		State.set_flag(130, false)
		if OS.get_cmdline_user_args().has("--trace-events"):
			print("JG init points +%d → %d" % [g, State.tech])
	_recalc(false)


func learned(n: int) -> bool:
	return State.jg_nodes.has(n)


func visible(j: int) -> bool:
	return (MECHS[j][0] as Array).any(func(n): return learned(int(n)))


func done(j: int) -> bool:
	return (MECHS[j][0] as Array).all(func(n): return learned(int(n)))


## 0x48dfc8: 板子的帧号
func plate_qq(j: int, flash := false) -> int:
	var pos: int = MECHS[j][7]
	if not done(j):
		return [2, 1, 3][pos]
	if flash:
		return [8, 7, 9][pos]
	if pos == 2 and int(MECHS[j][5]) != 4:
		return 0
	return [5, 4, 6][pos]


## 0x48de98: 能否学习节点 n (不是根节点、没学过、和已出现的板子相连、点数够)
func can_learn(n: int) -> bool:
	if n == 10 or learned(n) or State.tech < int(NODES[n][2]):
		return false
	for j in MECHS.size():
		if (MECHS[j][0] as Array).has(n) and visible(j):
			return true
	return false


func try_learn(n: int, kb: bool) -> void:
	if not can_learn(n):
		Game.play_sound(0x20e)
		return
	State.tech -= int(NODES[n][2])
	State.jg_nodes.append(n)
	if OS.get_cmdline_user_args().has("--trace-events"):
		print("JG learn %d cost %d left %d" % [n, int(NODES[n][2]), State.tech])
	Game.play_sound(0x20a if kb or state == 0 else 0x16)
	_recalc(true)


## 0x48da68: 授予已完成的板子 + 木甲术升级
func _recalc(announce: bool) -> void:
	var k := 0
	for j in MECHS.size():
		if not done(j) or State.jg_granted.has(j):
			continue
		var sid: int = MECHS[j][3]
		if int(MECHS[j][4]) == 1:
			var sk: Array = State.skills.get(1, [])
			if not sk.has(sid):
				sk.append(sid)
				sk.sort()
			State.skills[1] = sk
		else:
			_apply_passive(sid)
		State.jg_granted.append(j)
		if announce:
			pops.append({"text": "获得【%s】" % Battle.obj(sid).get("name", sid), "t": 2.5 + k * 0.2, "k": k})
			k += 1
	# 木甲术升级: 该类别 kind 2 的完成板到 4 块 → 2 级; 完成板到 8 块 → 3 级
	for cat in CAT_MECH:
		var sid2: int = CAT_MECH[cat]
		var n2 := 0
		var n_all := 0
		for j in MECHS.size():
			if int(MECHS[j][5]) == cat and done(j):
				n_all += 1
				if int(MECHS[j][6]) == 2:
					n2 += 1
		var lv := int(State.mech_lv.get(sid2, 1))
		var to := lv
		if lv == 1 and n2 >= 4:
			to = 2
		if to == 2 and n_all >= 8:
			to = 3
		if to != lv:
			State.mech_lv[sid2] = to
			if announce:
				_flash[cat] = [to, 50]


## 被动机关术 (授予方式 0 → 道具使用函数 0x488ffa 套用在车芸身上; 数值取自 magic.json 的效果栏)
## 6028 加速 / 6031 极速: 速度 +10%; 6030 奋力 / 6033 全力: 奋力机率 +10;
## 6029 巧动 / 6032 灵动 (0x488ffa, 逆向确认): 只有物理命中 (档案 +0x5a8) +5、物理回避 (+0x5aa) +5;
##   记录里另外两个 +5 (+0x50 / +0x52) 这个函数不读, 仙命中 / 仙回避不变 (以前四项都加, 是推测)
func _apply_passive(sid: int) -> void:
	var d := State.member(1)
	match sid:
		6028, 6031:
			d.spd = int(round(float(d.spd) * 1.1))
		6030, 6033:
			d.crit = int(d.get("crit", 0)) + 10
		6029, 6032:
			for k in ["hit", "eva"]:
				d[k] = int(d.get(k, 0)) + 5


# ---------------- 绘制 ----------------

func draw(t: float, delta: float) -> void:
	# 页签
	for k in 2:
		var on := (state == 1) == (k == 1)
		if on:
			m._img(TAB % [3, 2][k], Vector2(500 + 35 * k, 6), Color(1, 1, 1, 0.75 + 0.25 * sin(t * 4.0)))
		else:
			m._img(TAB % [1, 0][k], Vector2(500 + 35 * k, 6))
	var title := "木甲列表" if state == 1 else "木甲研发"
	m._text(title, Vector2(60, 565), 20, MainMenu.DARK_COL)
	m._text(title, Vector2(61, 565), 20, MainMenu.DARK_COL)
	_fx_items.clear()
	if state == 1:
		_draw_list(t)
	else:
		_draw_tree(t, delta)
	_fx.queue_redraw()
	# 「獲得 X」提示 (add_txt_msg (224, 166+70k))
	for p in pops:
		p.t -= delta
		var s: String = p.text
		var r := Rect2(224, 166 + 70 * int(p.k), _w(s, 18) + 60, 64)
		Dialog.draw_nine(m._c, m.tex(Dialog.SKIN), r)
		m._text(s, r.position + Vector2(30, 22), 18, Color8(255, 220, 120), Color(0, 0, 0, 0.6))
	pops = pops.filter(func(p): return p.t > 0)


func _w(s: String, size: int) -> float:
	var w := 0.0
	for ch in s:
		w += size * 0.5 if ch.unicode_at(0) < 0x80 else float(size)
	return w


func _draw_tree(t: float, delta: float) -> void:
	m._img(UI % 0, Vector2(10, 47))
	if cursor > 0 and not learned(cursor):
		var s := "所需木甲技术 %3d" % int(NODES[cursor][2])
		m._text(s, Vector2(410, 77), 16)
		m._text(s, Vector2(411, 77), 16)
	# 板子 + 名称 (12px; 已完成调色板 15 加粗, 否则调色板 19)
	var flash_on := false
	for j in MECHS.size():
		if not visible(j):
			continue
		var f: Array = _flash.get(int(MECHS[j][5]), [])
		var fl := f.size() > 0 and int(f[1]) % 4 >= 2 and done(j) and (int(f[0]) == 3 or int(MECHS[j][6]) >= 2)
		var qq := plate_qq(j, fl)
		if qq == 0:
			continue
		var x: float = MECHS[j][1]
		var y: float = MECHS[j][2]
		m._img(UI % int(QQ_FRAME[qq]), Vector2(x, y))
		var name := str(Battle.obj(int(MECHS[j][3])).get("name", ""))
		var blen := name.length() * 2
		var pos: Vector2 = [Vector2(x + blen + 30, y + 10), Vector2(x + blen + 28, y + 20), Vector2(x + blen + 6, y + 38)][int(MECHS[j][7])]
		var col := MainMenu.TEXT_COL if done(j) else PAL19
		m._text(name, pos, 12, col)
		if done(j):
			m._text(name, pos + Vector2(1, 0), 12, col)
	# 闪烁计时 (0x48e263): 到 0 时提示「X 提升至二級 / 三級」, 音效 0x210
	for cat in _flash.keys():
		_flash[cat][1] = int(_flash[cat][1]) - 1
		if int(_flash[cat][1]) <= 0:
			var nm := str(Battle.obj(int(CAT_MECH[cat])).get("name", ""))
			pops.append({"text": "【%s】提升至%s级" % [nm, ["", "", "二", "三"][int(_flash[cat][0])]], "t": 2.5, "k": 0})
			Game.play_sound(0x210)
			_flash.erase(cat)
	# 节点: 已学 / 价格 0 蓝; 100 黄绿 300 橙 600 红 1000 紫
	for n in NODES:
		var p := Vector2(NODES[n][0], NODES[n][1])
		var c: int = NODES[n][2]
		var qq2: int = 10 if learned(n) or c == 0 else int({100: 13, 300: 12, 600: 11, 1000: 14}.get(c, 10))
		m._img(UI % qq2, p)
	# 随机闪光 / 高亮光圈 (0x48bb4c, 逆向确认; 每逻辑帧):
	#   高亮光圈: 节点被选中时用播放器 0xc74e68 播 9018 qq15 (21 帧 × 1 循环), 画在 (x+12, y+12), 从不清零
	#   随机闪光: 没有高亮节点 ([0xc75098] ≠ 1) 且没有闪光在播时, 依次对每个未学节点掷 rand(200) == 20, 命中就在该节点开播
	#     9018 qq17 (OC 透明度 0→255→0, CS 0.234, 加色), 画在 (x+14, y+6); 原版在循环里对每条非高亮记录都推进并画一次
	#     → 每帧约推进 25 个逻辑帧、叠画 25 次; 进入最后一帧时结束
	var steps := 0
	_jg_acc2 += m.get_process_delta_time()
	while _jg_acc2 >= UiAct.TICK_FIELD:
		_jg_acc2 -= UiAct.TICK_FIELD
		steps += 1
	var per := NODES.size() - (1 if cursor > 0 else 0)
	for k in steps:
		if cursor > 0:
			_hl_ticks += 1
		if not _spark.is_empty():
			_spark.ticks = int(_spark.ticks) + per
			if int(UiAct.frame(9018, 17, int(_spark.ticks)).index) >= 20:
				_spark = {}
		elif cursor == 0:
			for n in NODES:
				if not learned(n) and randi() % 200 == 20:
					_spark = {"n": n, "ticks": 0}
					break
	if not _spark.is_empty():
		var sp := Vector2(NODES[_spark.n][0], NODES[_spark.n][1]) + Vector2(14, 6)
		for i in per:
			_fx_items.append(["sprite", UiAct.frame(9018, 17, maxi(int(_spark.ticks) - per + 1 + i, 0)), sp])
	if cursor > 0:
		_fx_items.append(["sprite", UiAct.frame(9018, 15, _hl_ticks), Vector2(NODES[cursor][0], NODES[cursor][1]) + Vector2(12, 12)])
	# 描述: 悬停的板子 (16px, (90,487), 行宽 470, 行高 25)
	if hover_mech >= 0:
		var hr := MainMenu.note_rows(Battle.obj(int(MECHS[hover_mech][3])), 470.0)
		for i in hr.size():
			m._text(hr[i][0], Vector2(90, 487 + 25 * i), 16, hr[i][1])


## 列表页 (0x48be89): 已出现的成果, 先已完成后未完成, 同组按排序号
func list_entries() -> Array:
	var out: Array = []
	for j in MECHS.size():
		if visible(j):
			out.append(j)
	out.sort_custom(func(a, b):
		if done(a) != done(b):
			return done(a)
		return int(MECHS[a][8]) < int(MECHS[b][8]))
	return out


func _draw_list(t: float) -> void:
	var k := clampf(t * 3.0, 0.0, 1.0)
	var p1 := Vector2(lerpf(640, 240, k), 73)
	var p2 := Vector2(62, lerpf(600, 478, k))
	var p3 := Vector2(lerpf(-200, 65, k), 73)
	m._img(QI_UI % 0, p1)
	m._img(QI_UI % 1, p3)
	m._img(ITEM_UI % 1, p2)
	m._text("名称", p1 + Vector2(66, 4), 14, PAL19)
	m._text("名称", p1 + Vector2(67, 4), 14, PAL19)
	var es := list_entries()
	if es.size() > 13:
		m._img(ITEM_UI % 2, p1 + Vector2(315, -5))
	if es.is_empty():
		return
	lsel = clampi(lsel, 0, es.size() - 1)
	m._c.draw_rect(Rect2(p1 + Vector2(0, 18 + 25 * (lsel - ltop)), Vector2(280, 32)), Color(1, 1, 1, 0x32 / 255.0))
	for r in range(ltop, mini(ltop + 13, es.size())):
		var j: int = es[r]
		var nm := str(Battle.obj(int(MECHS[j][3])).get("name", ""))
		var col := MainMenu.TEXT_COL if done(j) else PAL21
		var pos := p1 + Vector2(64, 26 + 25 * (r - ltop))
		m._text(nm, pos, 16, col)
		m._text(nm, pos + Vector2(1, 0), 16, col)
	var rec := Battle.obj(int(MECHS[es[lsel]][3]))
	var c: Dictionary = rec.get("cost", {})
	var d := State.member(1)
	var vals := [Formula.cost_of(int(c.get("mp", 0)), int(d.mp_max)), Formula.cost_of(int(c.get("sp", 0)), int(d.sp_max)), int(c.get("juji", 0))]
	var icons := [[2, Vector2(12, 15)], [3, Vector2(12, 15)], [9, Vector2(15, 14)]]
	for i in 3:
		m._img(ICON3 % int(icons[i][0]), p3 + Vector2(50, 20 + 25 * i) - icons[i][1])
		m._text("   %3d" % int(vals[i]), p3 + Vector2(50, 10 + 25 * i), 16)
	var rows := MainMenu.note_rows(rec)
	for i in rows.size():
		m._text(rows[i][0], p2 + Vector2(12, 3 + 25 * i), 16, rows[i][1])


# ---------------- 输入 ----------------

## 返回 true = 已处理; false = 交给主菜单 (取消关闭本页)
func key(code: int) -> bool:
	match code:
		KEY_ESCAPE, KEY_CTRL:
			if state == 3:
				state = 0
				cursor = 0
				return true
			return false
		KEY_LEFT, KEY_RIGHT:
			if state == 3:
				_nav(0 if code == KEY_LEFT else 1)
			else:
				state = 1 - state if state != 3 else 1
				Game.play_sound(0x201)
		KEY_UP, KEY_DOWN:
			if state == 3:
				_nav(2 if code == KEY_UP else 3)
			elif state == 1:
				var n := list_entries().size()
				lsel = clampi(lsel + (1 if code == KEY_DOWN else -1), 0, maxi(n - 1, 0))
				ltop = clampi(ltop, lsel - 12, lsel)
				Game.play_sound(0x201)
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			if state == 0:
				state = 3
				cursor = 10
				_recalc(false)
			elif state == 3:
				try_learn(cursor, true)
	return true


func _nav(dir: int) -> void:
	cursor = int(NAV.get(cursor, [cursor, cursor, cursor, cursor])[dir])
	Game.play_sound(0x201)


func mouse(p: Vector2, clicked: bool) -> bool:
	for k in 2:
		if Rect2(500 + 35 * k, 6, 26, 32).has_point(p):
			if clicked:
				state = k
				Game.play_sound(0x201)
			return true
	if state == 1:
		var es := list_entries()
		var p1 := Vector2(240, 73)
		if Rect2(p1.x, p1.y + 26, 300, 25 * 13).has_point(p) and clicked:
			var r := ltop + int((p.y - p1.y - 26) / 25)
			if r < es.size() and r != lsel:
				lsel = r
				Game.play_sound(0x201)
		return clicked
	# 树: 节点 / 板子悬停
	var hn := 0
	for n in NODES:
		if Rect2(Vector2(NODES[n][0], NODES[n][1]), Vector2(24, 24)).has_point(p):
			hn = n
	if hn > 0:
		cursor = hn
		if clicked:
			try_learn(hn, false)
	elif state == 0:
		cursor = 0
	hover_mech = -1
	for j in MECHS.size():
		if not visible(j):
			continue
		var sz := Vector2(41, 90) if int(MECHS[j][7]) == 2 else Vector2(90, 41)
		var r2 := Rect2(Vector2(MECHS[j][1], MECHS[j][2]), sz)
		if r2.has_point(p) and _in_tri(j, p - r2.position, sz):
			hover_mech = j
	return clicked


## 三角板的像素命中 (0x42fb80): 按形状判断点是否在三角形内
func _in_tri(j: int, q: Vector2, sz: Vector2) -> bool:
	match int(MECHS[j][7]):
		0:   # ▽
			return q.y <= sz.y * (1.0 - absf(q.x - sz.x * 0.5) / (sz.x * 0.5))
		1:   # △
			return q.y >= sz.y * absf(q.x - sz.x * 0.5) / (sz.x * 0.5)
		_:   # ◁
			return q.x >= sz.x * absf(q.y - sz.y * 0.5) / (sz.y * 0.5)
