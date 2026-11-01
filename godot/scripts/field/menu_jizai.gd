class_name MenuJizai
extends RefCounted
## 主菜单「记载」页 (init 0x483e14, 输入 0x484111, 绘制 0x48512f; 逆向笔记 re/menu_jizai.md)
##   页签 ACT 9026 (430+35k, 6): 0 事 (任务) / 1 人 (怪物图鉴) / 2 物 (道具图鉴); 焦点 −1 = 在页签栏上
##   事: 子页 未完成任务 (旗标 7001+i 置位、7257+i 未置位) / 已完成任务 (7257+i) / 历史相关 (7513+i, 一屏一篇)
##     文字 Mission.GLL 第 7000+i / 7512+i 条; 子页标签 16px 调色板 22 (245+105k, 50); 行 (230, 102+25k), 高亮 (210, 95+25k, 510×30)
##   人: 种族图标 0134 (180+35i, 45); 名单 (568, 102+25k), 高亮 (538, 95+25k, 200×30); 左侧资料按认识度阈值显示, 未知显示「????」
##   物: 分类图标 0106 (220+35i, 45); 生产需求资源 / 技能 / 特殊材料
##   认识度跨存档共享 (Fame, 原版 fame.dat)

const UI := "ui/all_sys/0085_000_主介面记载/%03d.png"
const TAB := "ui/all_sys/0117_000_记载分类ICON/%03d.png"
const TAB_SEL := "ui/all_sys/0118_000_记载分类ICON选/%03d.png"
const RACE := "ui/all_sys/0134_000_种族分类icon/%03d.png"
const RACE_SEL := "ui/all_sys/0135_000_种族分类icon选/%03d.png"
const CAT := "ui/all_sys/0106_000_物品分类icon/%03d.png"
const CAT_SEL := "ui/all_sys/0107_000_物品分类icon选/%03d.png"
const ITEM_UI := "ui/all_sys/0081_000_主介面物品/%03d.png"
const ICON3 := "ui/all_sys/0266_000_命灵体/%03d.png"
const ICON3_PC := Vector2(12, 15)
const PAL14 := Color8(89, 63, 32)
const PAL15 := Color8(117, 76, 36)
const PAL20 := Color8(192, 80, 88)
const PAL22 := Color8(234, 217, 182)
const TAB_FRAME := [1, 0, 2]          # 9026 qq0/1/2 → 0117 帧
const TAB_NAMES := ["事", "人", "物"]
const SUB_NAMES := ["未完成任务", "已完成任务", "历史相关"]
const ROWS := 14

static var _db: Dictionary = {}

var m: MainMenu
var tab := 0
var focus := -1      # −1 页签栏 / 0 任务 / 1 怪物 / 2 道具
var sub := 0         # 事: 子页
var race := 0
var cat := 0
var cur := 0         # 列表光标 (屏幕行)
var top := 0
var _anim_t := 0.0
var _vp: SubViewport
var _view: TextureRect
var _model: FieldActor
var _model_id := 0
var _angle := 2.0
var _spin := false


func _init(menu: MainMenu) -> void:
	m = menu
	if _db.is_empty():
		var p := Game.extracted_dir.path_join("game/records.json")
		if FileAccess.file_exists(p):
			_db = JSON.parse_string(FileAccess.get_file_as_string(p))
	# 每次打开记载页: 1097–1100 设为完全认识 (0x483fb4)
	for id in [1097, 1098, 1099, 1100]:
		Fame.add_monster(id, 100)


func free_fx() -> void:
	if is_instance_valid(_vp):
		_vp.queue_free()
	if is_instance_valid(_view):
		_view.queue_free()


# ---------------- 数据 ----------------

func entries() -> Array:
	match focus if focus >= 0 else tab:
		0:
			if sub == 2:
				return _db.get("history", []).filter(func(h): return State.test_flag(int(h.flag)))
			# 原版任务在前, 创意工坊 mod 的任务接在后面 (同样是 文字 + 接受旗标 + 完成旗标)
			return (_db.get("quests", []) + Mods.quests).filter(func(q):
				return State.test_flag(int(q.flag_done)) if sub == 1 else (State.test_flag(int(q.flag_accept)) and not State.test_flag(int(q.flag_done))))
		1:
			var known := Fame.monsters()
			# 原版图鉴在前, 创意工坊 mod 怪物 (复制原版条目改名字 / 说明 / 数值) 接在后面
			return (_db.get("bestiary", []) + Mods.bestiary).filter(func(b):
				return int(b.race_tab) == race and int(b.get("unique_3f7", 0)) == 0 and int(b.id) != 1097 and known.has(int(b.id)))
		2:
			var got := Fame.items()
			return _db.get("items", []).filter(func(it):
				return int(it.cat_tab) == cat and int(it.get("unique_3f7", 0)) == 0 and got.has(int(it.id)))
	return []


func per_page() -> int:
	return 1 if (focus == 0 and sub == 2) else ROWS


# ---------------- 绘制 ----------------

func draw(t: float, delta: float) -> void:
	_anim_t += delta
	if _spin:
		_angle = fmod(_angle + 0.5 * delta * 35.0, 360.0)
	if focus == 1:   # 手柄 LB +2° / RB −2° (0x4846dc / 0x484724)
		_angle += Pad.turn() * 2.0 * delta * 35.0
	var y_sel: int = UiAct.bounce(8, int(_anim_t * 35.0)) if focus == -1 else 4
	for k in 3:
		if k == tab:
			m._img(TAB_SEL % TAB_FRAME[k], Vector2(430 + 35 * k, y_sel))
		else:
			m._img(TAB % TAB_FRAME[k], Vector2(430 + 35 * k, 6))
	m._text(TAB_NAMES[tab], Vector2(60, 565), 20, PAL14)
	m._text(TAB_NAMES[tab], Vector2(61, 565), 20, PAL14)
	m._img(UI % 1, Vector2(0, 75))
	m._img(UI % 2, Vector2(0, 450))
	if tab != 1 and is_instance_valid(_view):
		_view.visible = false   # 怪物模型只在「人」页显示
	match tab:
		0:
			_draw_quests()
		1:
			_draw_monsters()
		2:
			_draw_items()
	_draw_scroll()


func _bold(s: String, p: Vector2, size: int, col: Color) -> void:
	m._text(s, p, size, col)
	m._text(s, p + Vector2(1, 0), size, col)


## 0x462902: 逐字节扫描, 本行字节数 ×10 > 宽度 就换行; %N 换行; 最多 max_lines 行; 返回行数
func _wrap(s: String, at: Vector2, width: float, max_lines: int, lh: float, col: Color, size := 16) -> int:
	var lines: Array = [""]
	var bytes := 0
	var i := 0
	while i < s.length():
		if s.substr(i, 2) == "%N":
			lines.append("")
			bytes = 0
			i += 2
			continue
		var ch := s[i]
		var b := 1 if ch.unicode_at(0) < 0x80 else 2
		if bytes * 10 > width:
			lines.append("")
			bytes = 0
		lines[-1] += ch
		bytes += b
		i += 1
	for k in mini(lines.size(), max_lines):
		_bold(lines[k], at + Vector2(0, k * lh), size, col)
	return mini(lines.size(), max_lines)


func _draw_quests() -> void:
	m._img(UI % 0, Vector2(0, 100))
	for k in 3:
		var p := Vector2(245 + 105 * k, 50)
		if focus == 0 and k == sub:
			m._text(SUB_NAMES[k], p, 16, PAL22, Color(0, 0, 0))
		else:
			_bold(SUB_NAMES[k], p, 16, PAL22)
	var es := entries()
	if sub == 2:
		if es.size():
			var h: Dictionary = es[clampi(top, 0, es.size() - 1)]
			_wrap(str(h.text), Vector2(10, 102), 780, 14, 25, PAL15)
		return
	if focus == 0 and es.size():
		m._c.draw_rect(Rect2(210, 95 + 25 * cur, 510, 30), Color(1, 1, 1, 0x32 / 255.0))
	var acc := 0.0
	for k in ROWS:
		if top + k >= es.size():
			break
		var q: Dictionary = es[top + k]
		var n := _wrap(str(q.text), Vector2(230, 102 + acc), 410, 10, 25, PAL20 if sub == 1 else PAL15)
		acc += 25 * n


func _draw_monsters() -> void:
	m._img(UI % 3, Vector2(0, 100))
	m._img(UI % 4, Vector2(548, 100))
	m._img(ITEM_UI % 1, Vector2(62, 478))
	_bold(" [R] 旋转", Vector2(538, 568), 16, PAL15)
	var y_sel: int = 45 + UiAct.bounce(8, int(_anim_t * 35.0)) - 8
	for i in 10:
		if focus != -1 and i == race:
			m._img(RACE_SEL % i, Vector2(180 + 35 * i, y_sel))
		else:
			m._img(RACE % i, Vector2(180 + 35 * i, 45))
	var es := entries()
	for k in ROWS:
		if top + k >= es.size():
			break
		var b: Dictionary = es[top + k]
		_bold(str(b.name) if Fame.known(int(b.id), 10) else "????", Vector2(568, 102 + 25 * k), 16, PAL15)
	if es.is_empty():
		_show_model(0)
		return
	if focus == 1:
		m._c.draw_rect(Rect2(538, 95 + 25 * cur, 200, 30), Color(1, 1, 1, 0x32 / 255.0))
	var e: Dictionary = es[clampi(top + cur, 0, es.size() - 1)]
	var id := int(e.id)
	var th: Dictionary = _db.get("thresholds", {})
	var kn := func(f: String) -> bool: return Fame.known(id, int(th.get(f, 100)))
	_bold(str(e.name) if kn.call("name") else "????", Vector2(20, 100), 16, PAL14)
	_bold("%2d" % int(e.level) if kn.call("level") else "??", Vector2(20, 125), 16, PAL15)
	_bold("级", Vector2(40, 125), 16, PAL14)
	var bars := [["hp", 1, 161, 154, "%d/%-6d"], ["mp", 2, 186, 179, "%d/%-4d"], ["sp", 3, 211, 204, "%d/%-4d"]]
	for bar in bars:
		m._img(ICON3 % int(bar[1]), Vector2(32, bar[2]) - ICON3_PC)
		var v := int(e.get(bar[0], 0))
		_bold(bar[4] % [v, v] if kn.call(bar[0]) else "??/??", Vector2(60, bar[3]), 12, PAL15)
	var stats := [["攻击:", "atk", 15, 228], ["防御:", "def", 15, 253], ["速度:", "spd", 15, 278], ["仙攻:", "matk", 105, 228], ["仙防:", "mdef", 105, 253]]
	for st in stats:
		_bold(st[0], Vector2(st[2], st[3]), 14, PAL14)
		_bold("%-4d" % int(e.get(st[1], 0)) if kn.call(st[1]) else "??", Vector2(int(st[2]) + 45, int(st[3]) + 1), 12, PAL15)
	_bold("属性:", Vector2(105, 128), 14, PAL14)
	_bold(str(e.get("elem", "无")) if kn.call("elem") else "??", Vector2(150, 128), 14, PAL15)
	var craft: Dictionary = e.get("craft", {})
	var ck := ["冶金", "整备", "制药", "神技"]
	for i in 4:
		_bold(ck[i] + ":", Vector2(15, 303 + 25 * i), 14, PAL14)
		_bold("%-4d" % int(craft.get(ck[i], 0)) if kn.call("craft") else "??", Vector2(60, 304 + 25 * i), 12, PAL15)
	if int(e.get("steal_id", 0)) and kn.call("steal"):
		_bold("可偷物品:", Vector2(15, 404), 12, PAL14)
		_bold(str(e.steal), Vector2(80, 403), 14, PAL15)
	if int(e.get("learn_id", 0)) and kn.call("learn"):
		_bold("可学招术:", Vector2(15, 429), 12, PAL14)
		_bold(str(e.learn), Vector2(80, 428), 14, PAL15)
	_wrap(str(e.desc) if kn.call("desc") else "????", Vector2(77, 481), 530, 3, 25, PAL15)
	_show_model(int(e.get("model_act", id)))   # 原版条目 model_act 都等于怪物号; mod 怪物是复制来源的那只


## 怪物 3D 模型 (actobj 0xc72468, 动作 80 待机, 绕 Y 轴转): 画在左侧资料面板右半部
func _show_model(id: int) -> void:
	if _vp == null:
		_vp = SubViewport.new()
		_vp.size = Vector2i(560, 660)
		_vp.transparent_bg = true
		_vp.own_world_3d = true
		_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		m.add_child(_vp)
		var cam := Camera3D.new()
		cam.fov = 33.4
		_vp.add_child(cam)
		cam.position = Vector3(0, 1.0, 4.2)
		cam.look_at(Vector3(0, 0.85, 0))
		var env := WorldEnvironment.new()
		env.environment = Environment.new()
		env.environment.background_mode = Environment.BG_CLEAR_COLOR
		_vp.add_child(env)
		_view = TextureRect.new()
		_view.texture = _vp.get_texture()
		_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_view.stretch_mode = TextureRect.STRETCH_SCALE
		_view.position = Vector2(250, 112)
		_view.size = Vector2(280, 330)
		_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
		m._c.add_child(_view)
	_view.visible = id > 0 and tab == 1
	if id != _model_id:
		_model_id = id
		if is_instance_valid(_model):
			_model.queue_free()
		_model = null
		if id > 0 and (Mods.has_model(id) or FileAccess.file_exists(Game.extracted_dir.path_join("game/actors/act_%d.json" % id))):
			_model = FieldActor.new()
			_vp.add_child(_model)
			_model.setup(m.field, id, id)
			if _model.has_pose(80):
				_model.play(80, true)
			_fit_pending = 6   # 等几帧动画姿势生效后再按包围盒缩放居中
	if is_instance_valid(_model):
		if _fit_pending > 0:
			_fit_pending -= 1
			if _fit_pending == 0:
				_fit()
		_model.rotation_degrees.y = _angle + 180.0


var _fit_pending := 0


## 原版相机固定 (距离 1100, 注视 (−190,−30,0)): 模型按原尺寸 (游戏单位 ×0.01 米), 不缩放
func _fit() -> void:
	_model.scale = Vector3.ONE
	_model.position = Vector3.ZERO
	# 用骨骼的当前姿势位置居中 (蒙皮网格的包围盒是静止姿势, 不可靠)
	var pts: Array = []
	for sk in _model.find_children("*", "Skeleton3D", true, false):
		var skel := sk as Skeleton3D
		if not skel.is_visible_in_tree():
			continue
		for b in skel.get_bone_count():
			pts.append(skel.global_transform * skel.get_bone_global_pose(b).origin)
	if pts.is_empty():
		return
	var lo: Vector3 = pts[0]
	var hi: Vector3 = pts[0]
	for q in pts:
		lo = lo.min(q)
		hi = hi.max(q)
	if OS.get_cmdline_user_args().has("--trace-events"):
		print("JZ bones lo=%s hi=%s" % [lo, hi])
	_model.position = Vector3(-(lo.x + hi.x) * 0.5, -lo.y, -(lo.z + hi.z) * 0.5)


func _draw_items() -> void:
	m._img(UI % 3, Vector2(0, 100))
	m._img(UI % 4, Vector2(548, 100))
	m._img(ITEM_UI % 1, Vector2(62, 478))
	var frames: Array = [10, 11, 9, 2, 3, 4, 6, 5, 7]
	var y_sel: int = 45 + UiAct.bounce(8, int(_anim_t * 35.0)) - 8
	for i in 9:
		if focus != -1 and i == cat:
			m._img(CAT_SEL % int(frames[i]), Vector2(220 + 35 * i, y_sel))
		else:
			m._img(CAT % int(frames[i]), Vector2(220 + 35 * i, 45))
	var es := entries()
	for k in ROWS:
		if top + k >= es.size():
			break
		_bold(str(es[top + k].name), Vector2(568, 102 + 25 * k), 16, PAL15)
	if es.is_empty():
		return
	if focus == 2:
		m._c.draw_rect(Rect2(538, 95 + 25 * cur, 200, 30), Color(1, 1, 1, 0x32 / 255.0))
	var e: Dictionary = es[clampi(top + cur, 0, es.size() - 1)]
	var icon := str(Battle.obj(int(e.id)).get("icon", ""))
	if icon != "":
		m._img(icon, Vector2(100, 130))
	_bold(str(e.name), Vector2(290, 128), 16, PAL14)
	_bold("生产需求资源/", Vector2(290, 154), 12, PAL14)
	var res := ["金钱", "金属", "木材", "煤炭"]
	for i in 4:
		_bold(res[i] + ":", Vector2(290, 178 + 25 * i), 14, PAL14)
		_bold("%d" % int(e.get(res[i], 0)), Vector2(335, 179 + 25 * i), 12, PAL15)
	_bold("生产需求技能/", Vector2(290, 279), 12, PAL14)
	var sk := ["冶金", "整备", "制药", "神技"]
	for i in 4:
		_bold(sk[i] + ":", Vector2(290, 303 + 25 * i), 14, PAL14)
		_bold("%d" % int(e.get(sk[i], 0)), Vector2(335, 304 + 25 * i), 12, PAL15)
	var sp: Array = e.get("special", [])
	if sp.size():
		_bold("特殊需求资源/", Vector2(290, 404), 12, PAL14)
		var names := ""
		for s in sp:
			names += str(s.get("name", s) if s is Dictionary else Battle.obj(int(s)).get("name", s)) + " "
		_bold(names, Vector2(290, 429), 12, PAL15)
	_wrap(str(e.desc), Vector2(77, 481), 470, 3, 25, PAL15)


## 滚动条 (列表控件 0x466a29): 底图 0085 第 5 帧 (760,66), 滑块 (769, 113+偏移, 11×长), 箭头 0081 第 3/4 帧
func _draw_scroll() -> void:
	m._img(UI % 5, Vector2(760, 66))
	var n := entries().size()
	if n == 0:
		return
	var pp := per_page()
	var off := roundf(float(top) / n * 322.0)
	var h := 322.0 if n <= pp else roundf(float(pp) / n * 322.0)
	m._c.draw_rect(Rect2(769, 66 + 47 + off, 11, h), Color8(255, 253, 227, 200))
	m._img(ITEM_UI % 3, Vector2(765, 90))
	m._img(ITEM_UI % 4, Vector2(765, 439))


# ---------------- 输入 ----------------

func _enter() -> void:
	focus = tab
	cur = 0
	top = 0
	_anim_t = 0.0
	Game.play_sound(513)


func _leave() -> void:
	focus = -1
	cur = 0
	top = 0
	_spin = false
	_angle = 2.0
	sub = 0
	Game.play_sound(514)


func _move(d: int) -> void:
	var n := entries().size()
	var pp := per_page()
	if n == 0:
		return
	if d > 0:
		if top + cur + 1 >= n:
			return
		if cur + 1 >= pp:
			top += 1
		else:
			cur += 1
	else:
		if cur > 0:
			cur -= 1
		elif top > 0:
			top -= 1
		else:
			return
	Game.play_sound(513)


func key(code: int) -> bool:
	if focus == -1:
		match code:
			KEY_ESCAPE, KEY_CTRL:
				return false
			KEY_LEFT, KEY_RIGHT:
				tab = (tab + (2 if code == KEY_LEFT else 1)) % 3
				Game.play_sound(513)
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_DOWN:
				_enter()
		return true
	match code:
		KEY_ESCAPE, KEY_CTRL:
			_leave()
		KEY_LEFT, KEY_RIGHT:
			var d := -1 if code == KEY_LEFT else 1
			match focus:
				0:
					sub = (sub + d + 3) % 3
				1:
					if Input.is_key_pressed(KEY_SHIFT) or Input.is_key_pressed(KEY_CTRL):
						_angle += 2.0 * d
						return true
					race = (race + d + 10) % 10
				2:
					cat = (cat + d + 9) % 9
			cur = 0
			top = 0
			Game.play_sound(513)
		KEY_UP:
			_move(-1)
		KEY_DOWN:
			_move(1)
		KEY_PAGEUP, KEY_PAGEDOWN:
			var pp := per_page()
			var n := entries().size()
			top = clampi(top + (pp if code == KEY_PAGEDOWN else -pp), 0, maxi(n - pp, 0))
			Game.play_sound(530)
		KEY_R, Pad.Y:   # 0x484813 / 0x484824
			if focus == 1:
				_spin = not _spin
	return true


func mouse(p: Vector2, clicked: bool) -> bool:
	for k in 3:
		if Rect2(430 + 35 * k, 6, 26, 32).has_point(p):
			if clicked:
				tab = k
				_enter()
			return clicked
	if focus == 0 and sub != 2:
		for k in 3:
			if clicked and Rect2(240 + 105 * k, 48, 80, 16).has_point(p):
				sub = k
				cur = 0
				top = 0
				Game.play_sound(513)
				return true
	if focus == 1 or (tab == 1 and focus == -1):
		for i in 10:
			if clicked and Rect2(180 + 35 * i, 45, 26, 24).has_point(p):
				tab = 1
				focus = 1
				race = i
				cur = 0
				top = 0
				Game.play_sound(513)
				return true
	if focus == 2 or (tab == 2 and focus == -1):
		for i in 9:
			if clicked and Rect2(220 + 35 * i, 45, 26, 24).has_point(p):
				tab = 2
				focus = 2
				cat = i
				cur = 0
				top = 0
				Game.play_sound(513)
				return true
	# 行悬停
	if focus >= 0:
		var x0 := 210.0 if focus == 0 else 538.0
		var w := 510.0 if focus == 0 else 200.0
		var n := entries().size()
		for i in per_page():
			if Rect2(x0, 95 + 25 * i, w, 25).has_point(p) and top + i < n and i != cur:
				cur = i
				Game.play_sound(513)
	return clicked


func fullscreen() -> bool:
	return true
