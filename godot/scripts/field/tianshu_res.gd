class_name TianshuRes
extends RefCounted
## 天书的居民画面 (逆向笔记 re/menu_tianshu_res.md)
##   居民分页 (分页 2; 输入 0x4b15ae, 绘制 0x4b3ce8 → 0x4b4555 → 0x4b4bc8):
##     清单 = 流放名单 (先, 「流放中」色 20) + 居民链表 (最近加入的在前, 「工作中 / 闲置中」色 23); 一屏 13 行, 行 y = 69+25r
##     清单面板 0081/0 (410,67), 左资料 0143/0 (33,67), 滚动条 0081/2 (725,62); 选中行 → 左边资料 + 3D 模型 + 左下「工作地」
##     子状态: 0 清单 / 1 弹出菜单 0143/2 (300,230)「详细资料 / 驱逐居民」/ 2 详细资料页 / 3「驱逐此居民?」/ 4 拆住房时强制流放
##   驱逐 = 永久删除 (工作中的先移出工房, 音效 0x218), 空出的人口由流放者递补「原位由 X 递补」
##   流放只在拆住房会住不下时发生: 选够人数才真的拆 (0x217), ESC 取消拆除 (流放的人搬回); 离开天书时流放名单里的人永久消失
##   配置居民 (屋舍详情「配置」, 工房 4–7; 输入 0x4b2cf4, 绘制 0x4b6a1d / 0x4b6cd8 / 0x4b7c79):
##     右边「闲置居民清单」0142/0 (560,67): 第 0 行「退出配置」, 行 y = 115+25·sel, 一屏 16 行
##     左边 0145/1 (7,70): 上方技能合计 (57+120j, 88), 有变化时画预览箭头 0146/7 (蓝, 增) / 0146/8 (红, 减) 在 (62+120j,100);
##       中间工作位置 k 在 x∈(7+105k, 87+105k)、y∈(130,350) (画 3D 模型); 下方「工作居民资料 / 闲置居民资料」
##     焦点模式 0 右清单: 确认闲置居民 → 放进第一个空位 (满了 → 模式 2 交换); 选「退出配置」或点左边 → 模式 1 迁出

const LIST := "ui/all_sys/0081_000_主介面物品/%03d.png"
const RESP := "ui/all_sys/0143_天书_居民介面/%03d.png"
const BUILD := "ui/all_sys/0142_天书_建筑介面/%03d.png"
const HOUSEP := "ui/all_sys/0145_天书_屋舍介面/%03d.png"
const COMMON := "ui/all_sys/0144_天书_共用介面/%03d.png"
const ICON := "ui/all_sys/0146_天书_Icon_共用/%03d.png"
const RACE := "ui/all_sys/0134_000_种族分类icon/%03d.png"
const ICON3 := "ui/all_sys/0266_000_命灵体/%03d.png"
const OKBTN := "ui/all_sys/0245_000_买卖介面/%03d.png"
const FRAME := "ui/all_sys/0153_000_人物介面选择框/000.png"
const P14 := Color8(89, 63, 32)
const P15 := Color8(117, 76, 36)
const P16 := Color8(229, 69, 16)
const P17 := Color8(44, 141, 245)
const P19 := Color8(166, 124, 82)
const P20 := Color8(192, 80, 88)
const P21 := Color8(91, 110, 70)
const P22 := Color8(234, 217, 182)
const P23 := Color8(89, 86, 143)
const P24 := Color8(237, 192, 95)
const P25 := Color8(110, 102, 0)
const CRAFT := ["冶金", "整备", "制药", "神技"]
const ROWS := 13
const SLOT_FOOT := [[55, 333, 129], [171, 318, 123], [277, 304, 118], [371, 318, 123], [474, 333, 129]]   # 脚底 x, y, 参考像素高
const CROWS := 16

var ts: MenuTianshu
var m: MainMenu
# 居民分页
var sub := 0
var sel := 1           # 选中行 (1 起, 屏幕行)
var top := 0
var pop := 1           # 弹出菜单焦点 1 详细资料 / 2 驱逐居民
var dlg := 1           # 驱逐确认框焦点 0 确定 / 1 取消
var ex_sel := 1
var ex_need := 0       # 强制流放: 还要流放几个
var ex_house: Dictionary
var expel_flag := false
# 配置画面
var house: Dictionary
var cmode := 0         # 0 右清单 / 1 迁出 / 2 交换
var cslot := 1         # 左边选中位置 (1 起)
var csel := 0          # 右边选中行 (0 = 「退出配置」)
var ctop := 0
var _view: UiModelView     # 居民资料的 3D 模型
var _slots: UiModelView    # 配置画面的工作位置
static var _beasts: Dictionary = {}
static var _races: Array = []


func _init(owner: MenuTianshu) -> void:
	ts = owner
	m = owner.m
	if _beasts.is_empty():
		var p := Game.extracted_dir.path_join("game/records.json")
		if FileAccess.file_exists(p):
			var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(p))
			for b in d.get("bestiary", []):
				_beasts[int(b.id)] = b
			_races = d.get("races", [])


func free_fx() -> void:
	if _view:
		_view.free_all()
	if _slots:
		_slots.free_all()
	_view = null
	_slots = null


func hide_models() -> void:
	if _view:
		_view.set_visible(false)
	if _slots:
		_slots.set_visible(false)


# ---------------- 数据 ----------------

func beast(id: int) -> Dictionary:
	if _beasts.has(id):
		return _beasts[id]
	var o := Battle.obj(id)
	return {"id": id, "name": o.get("name", str(id)), "level": o.get("level", 0), "desc": o.get("desc", ""), "race_tab": 0,
		"hp": o.get("hp", 0), "mp": o.get("mp", 0), "sp": o.get("sp", 0), "atk": o.get("atk", 0), "def": o.get("def", 0),
		"spd": o.get("spd", 0), "matk": o.get("matk", 0), "mdef": o.get("mdef", 0), "elem": "无", "craft": {}}


func craft(id: int, j: int) -> int:
	return int(beast(id).get("craft", {}).get(CRAFT[j], 0))


## 清单行: 流放名单在前, 然后居民链表 → [ID, 是否流放, 居民记录]
func rows() -> Array:
	var out: Array = []
	for id in ts.exiled:
		out.append([int(id), true, null])
	for r in State.ts_residents:
		out.append([int(r.id), false, r])
	return out


func idle() -> Array:
	return State.ts_residents.filter(func(r): return int(r.house) == 0)


func slots_of(h: Dictionary) -> Array:
	return h.get("slots", [])


static func house_skill_of(h: Dictionary, crafts: Callable) -> Array:
	var s := [0, 0, 0, 0]
	for id in h.get("slots", []):
		for j in 4:
			s[j] += int(crafts.call(int(id), j))
	return s


func house_skill(h: Dictionary) -> Array:
	return house_skill_of(h, craft)


## 0x4b10b4: 放进房舍第一个空位
func assign(h: Dictionary, r: Dictionary) -> void:
	var s: Array = h.get("slots", [])
	s.append(int(r.id))
	h.slots = s
	r.house = int(h.seq)


## 0x4b10f7 + 0x4a7fe0: 迁出位置 k (0 起), 后面的往前挪
func unassign(h: Dictionary, k: int) -> bool:
	var s: Array = h.get("slots", [])
	if k < 0 or k >= s.size():
		return false
	var id := int(s[k])
	s.remove_at(k)
	h.slots = s
	for r in State.ts_residents:
		if int(r.id) == id and int(r.house) == int(h.seq):
			r.house = 0
			return true
	return true


func _remove_resident(r: Dictionary) -> void:
	if int(r.house) != 0:
		for h in State.ts_houses:
			if int(h.seq) == int(r.house):
				var k := slots_of(h).find(int(r.id))
				if k >= 0:
					unassign(h, k)
	State.ts_residents.erase(r)


## 0x4b87c3: 流放者回迁 (人口有空位就按顺序搬回)
func return_exiles() -> void:
	var n := 0
	while ts.exiled.size() and ts.capacity() > State.ts_residents.size():
		var id := int(ts.exiled.pop_front())
		State.ts_residents.push_front({"id": id, "house": 0})
		if expel_flag:
			m._say("原位由 %s 递补" % beast(id).name)
			expel_flag = false
		else:
			n += 1
	if n > 0:
		m._say("%d 名流放居民进住" % n)


# ---------------- 通用绘制 ----------------

func _bold(s: String, p: Vector2, size: int, col: Color) -> void:
	m._text(s, p, size, col)
	m._text(s, p + Vector2(1, 0), size, col)


func _outline(s: String, p: Vector2, size: int, col: Color, oc: Color) -> void:
	m._text(s, p, size, col, oc)


func _scroll(n: int, page: int, x: float, y0: float, h: float, top_: int) -> void:
	if n <= 0:
		return
	var yy := y0 if n <= page else y0 + top_ * h / n
	var hh := h if n <= page else h * page / n
	m._c.draw_rect(Rect2(x, yy, 11, hh), Color8(255, 253, 227, 200))


## 选中居民的资料 (0x4b4bc8), o = 左面板原点偏移
func _stats(id: int, o: Vector2, exiled: bool) -> void:
	var b := beast(id)
	_bold(str(b.name), Vector2(63, 80) + o, 16, P15)
	var rt := int(b.get("race_tab", 0))
	m._img(RACE % rt, Vector2(131, 105) + o)
	_bold(str(_races[rt]) if rt < _races.size() else "", Vector2(158, 112) + o, 16, P15)
	_bold("%2d" % int(b.get("level", 0)), Vector2(63, 112) + o, 16, P15)
	_bold("级", Vector2(83, 112) + o, 16, P14)
	_bold("属性:", Vector2(303, 115) + o, 14, P14)
	_bold(str(b.get("elem", "无")), Vector2(343, 115) + o, 14, P15)
	var bars := [["hp", 1, 152, 161], ["mp", 2, 172, 183], ["sp", 3, 192, 205]]
	for e in bars:
		m._img(ICON3 % int(e[1]), Vector2(63, float(e[2])) + o)   # 天书贴图函数 0x4af003 不减 PC 偏移
		_bold("%d" % int(b.get(e[0], 0)), Vector2(103, e[3]) + o, 12, P15)
	var stats := [["攻击:", "atk"], ["防御:", "def"], ["速度:", "spd"], ["仙攻:", "matk"], ["仙防:", "mdef"]]
	for k in 5:
		_bold(stats[k][0], Vector2(63, 247 + 22 * k) + o, 14, P25)
		_bold("%d" % int(b.get(stats[k][1], 0)), Vector2(103, 249 + 22 * k) + o, 12, P15)
	for j in 4:
		_bold(CRAFT[j] + ":", Vector2(63, 380 + 21 * j) + o, 14, P25)
		_bold("%d" % craft(id, j), Vector2(103, 382 + 21 * j) + o, 12, P15)


func _confirm_box(txt: String, focus: int) -> void:
	m._c.draw_rect(Rect2(0, 0, 800, 600), Color(0, 0, 0, 0x50 / 255.0))
	m._img(COMMON % 1, Vector2(310, 250))
	_bold(txt, Vector2(345, 268), 16, P15)
	m._img(OKBTN % (8 if focus == 0 else 9), Vector2(340, 303))
	m._img(OKBTN % (10 if focus == 1 else 11), Vector2(400, 303))


func _model_view() -> UiModelView:
	if _view == null:
		_view = UiModelView.new(m._c, m.field)
	return _view


func _workplace(r: Dictionary) -> String:
	if r == null or int(r.house) == 0:
		return "无"
	for h in State.ts_houses:
		if int(h.seq) == int(r.house):
			return ts.house_name(h) if int(h.type) == 9 else str(MenuTianshu.TYPES[int(h.type)][0])
	return "无"


# ---------------- 居民分页 ----------------

func draw_residents() -> void:
	if _slots:
		_slots.set_visible(false)
	var rs := rows()
	if sub == 2:
		_draw_detail(rs)
		return
	m._img(LIST % 0, Vector2(410, 67))
	m._img(RESP % 0, Vector2(33, 67))
	m._img(LIST % 2, Vector2(725, 62))
	_scroll(rs.size(), ROWS, 734, 110, 264, top)
	m._img(LIST % 3, Vector2(730, 87))
	m._img(LIST % 4, Vector2(730, 379))
	var cur := ex_sel if sub == 4 else sel
	if rs.size() and sub < 4 or (sub == 4 and rs.size()):
		m._c.draw_rect(Rect2(425, 64 + 25 * cur, 280, 25), Color(1, 1, 1, 0x78 / 255.0))
	_bold("居民名称", Vector2(445, 72), 12, P19)
	_bold("状态", Vector2(665, 72), 12, P19)
	_bold("工作地", Vector2(63, 488), 14, P14)
	for r in ROWS:
		var i := top + r
		if i >= rs.size():
			break
		var e: Array = rs[i]
		var y := 69 + 25 * (r + 1)
		var col := P20 if e[1] else P23
		var st := "流放中" if e[1] else ("工作中" if int(e[2].house) != 0 else "闲置中")
		_bold("%-10s" % beast(int(e[0])).name, Vector2(445, y), 16, col)
		_bold(st, Vector2(645, y), 16, col)
	var pick := top + cur - 1
	if pick >= 0 and pick < rs.size():
		var e: Array = rs[pick]
		_stats(int(e[0]), Vector2.ZERO, e[1])
		_bold(_workplace(e[2]) if not e[1] else "无", Vector2(133, 486), 16, P15)
		_model_view().set_visible(true)
		_view.set_models([[int(e[0]), 276, 428, 164]])   # 世界 (5300,1900,1800) ×4 → 脚底 (276,428)
	elif _view:
		_view.set_visible(false)
	match sub:
		1:
			m._c.draw_rect(Rect2(0, 0, 800, 600), Color(0, 0, 0, 0x50 / 255.0))
			m._img(RESP % 2, Vector2(300, 230))
			var items := ["详细资料", "驱逐居民"]
			for k in 2:
				var y := 260 + 40 * k
				if pop == k + 1:
					_outline(items[k], Vector2(355, y), 16, P24, P25)
					m._img(ICON % 6, Vector2(335, y))
					m._img(ICON % 6, Vector2(428, y))
				else:
					_outline(items[k], Vector2(355, y), 16, P22, P23)
		3:
			_confirm_box("驱逐此居民?", dlg)
		4:
			m._img(RESP % 6, Vector2(410, 417))
			_bold("流放居民数目", Vector2(490, 431), 16, P14)
			_bold("%d" % ex_need, Vector2(620, 431), 16, P15)


func _draw_detail(rs: Array) -> void:
	var i := top + sel - 1
	if i < 0 or i >= rs.size():
		sub = 0
		return
	var id := int(rs[i][0])
	m._img(RESP % 3, Vector2(25, 67))
	m._img(RESP % 4, Vector2(470, 67))
	m._img(BUILD % 2, Vector2(107, 464))
	_stats(id, Vector2(-8, 0), rs[i][1])
	_model_view().set_visible(true)
	_view.set_models([[id, 268, 428, 164]])   # 详细资料页 (左面板原点左移 8, 原版常量未核对)
	_bold("招 式", Vector2(495, 81), 16, P19)
	_bold("灵 力", Vector2(610, 81), 16, P19)
	_bold("体 力", Vector2(700, 81), 16, P19)
	var row := 0
	for sk in Battle.obj(id).get("skills", []):
		if int(sk) == 0:
			continue
		var so := Battle.obj(int(sk))
		var c: Dictionary = so.get("cost", {})
		var y := 112 + 25 * row
		_bold("%-10s" % so.get("name", sk), Vector2(492, y), 16, P15)
		_bold("%4d" % int(c.get("mp", 0)), Vector2(605, y), 16, P15)
		_bold("%4d" % int(c.get("sp", 0)), Vector2(695, y), 16, P15)
		row += 1
	var b := beast(id)
	if int(b.get("learn_id", 0)):
		m._img(RESP % 6, Vector2(470, 247))
		_bold("可学招术", Vector2(474, 248), 12, P14)
		var lo := Battle.obj(int(b.learn_id))
		var c: Dictionary = lo.get("cost", {})
		_bold(str(b.learn), Vector2(494, 262), 16, P21)
		_bold("%4d" % int(c.get("mp", 0)), Vector2(605, 262), 16, P15)
		_bold("%4d" % int(c.get("sp", 0)), Vector2(695, 262), 16, P15)
	ts.wrap_text(str(b.get("desc", "")), Vector2(122, 467), 540, 3)


func _move(d: int, cur: int, n: int, page: int) -> Array:
	# 返回 [选中行, 顶行]
	var s := cur + d
	var t := top
	if s < 1:
		t -= 1
		s = 1
		if t < 0:
			t = 0
	elif s > page:
		t = mini(t + 1, maxi(n - page, 0))
		s = page
	if t + s > n:
		s = n - t
	return [s, t]


func key_residents(code: int) -> bool:
	var rs := rows()
	var n := rs.size()
	match sub:
		0:
			match code:
				KEY_ESCAPE, KEY_CTRL:
					top = 0
					Game.play_sound(0x202)
					return false
				KEY_UP, KEY_DOWN:
					if n:
						var r := _move(-1 if code == KEY_UP else 1, sel, n, ROWS)
						sel = r[0]
						top = r[1]
						Game.play_sound(0x201)
				KEY_PAGEUP, KEY_PAGEDOWN:
					if n:
						top = clampi(top + (ROWS if code == KEY_PAGEDOWN else -ROWS), 0, maxi(n - ROWS, 0))
						sel = clampi(sel, 1, mini(ROWS, n - top))
						Game.play_sound(0x212)
				KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
					if n:
						sub = 1
						pop = 1
						Game.play_sound(0x200)
		1:
			match code:
				KEY_ESCAPE, KEY_CTRL:
					sub = 0
					Game.play_sound(0x202)
				KEY_UP, KEY_DOWN:
					pop = clampi(pop + (-1 if code == KEY_UP else 1), 1, 2)
					Game.play_sound(0x201)
				KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
					_pop_ok()
		2:
			match code:
				KEY_ESCAPE, KEY_CTRL:
					sub = 1
					Game.play_sound(0x202)
				KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
					sub = 0
					Game.play_sound(0x200)
		3:
			match code:
				KEY_ESCAPE, KEY_CTRL:
					sub = 1
					Game.play_sound(0x202)
				KEY_LEFT, KEY_RIGHT:
					dlg = 1 - dlg
					Game.play_sound(0x201)
				KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
					if dlg == 0:
						_expel()
					else:
						sub = 1
						Game.play_sound(0x1ff)
		4:
			match code:
				KEY_ESCAPE, KEY_CTRL:
					_cancel_exile()
				KEY_UP, KEY_DOWN:
					if n:
						var r := _move(-1 if code == KEY_UP else 1, ex_sel, n, ROWS)
						ex_sel = r[0]
						top = r[1]
						Game.play_sound(0x201)
				KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
					_exile_pick()
	return true


func mouse_residents(p: Vector2, clicked: bool) -> void:
	var n := rows().size()
	match sub:
		0, 4:
			var vis := mini(ROWS, n - top)
			for r in range(1, vis + 1):
				if p.x > 425 and p.x < 705 and p.y > 64 + 25 * r and p.y < 89 + 25 * r:
					if sub == 0 and r != sel:
						sel = r
						Game.play_sound(0x201)
					elif sub == 4 and r != ex_sel:
						ex_sel = r
						Game.play_sound(0x201)
					if clicked:
						if sub == 0:
							sub = 1
							pop = 1
							Game.play_sound(0x200)
						else:
							_exile_pick()
					return
		1:
			for k in 2:
				if p.x > 335 and p.x < 435 and p.y > 253 + 35 * k and p.y < 283 + 35 * k:
					if pop != k + 1:
						pop = k + 1
						Game.play_sound(0x201)
					if clicked:
						_pop_ok()
					return
		2:
			if clicked:
				sub = 0
				Game.play_sound(0x200)
		3:
			if p.y > 300 and p.y < 326:
				if p.x > 340 and p.x < 384:
					dlg = 0
					if clicked:
						_expel()
				elif p.x > 400 and p.x < 444:
					dlg = 1
					if clicked:
						sub = 1
						Game.play_sound(0x1ff)


func _pop_ok() -> void:
	if pop == 1:
		sub = 2
	else:
		sub = 3
		dlg = 1
	Game.play_sound(0x200)


## 0x4b1f3c: 驱逐 = 永久删除; 流放行则只是从名单里删掉
func _expel() -> void:
	var i := top + sel - 1
	var rs := rows()
	if i < 0 or i >= rs.size():
		sub = 1
		Game.play_sound(0x1ff)
		return
	var e: Array = rs[i]
	if e[1]:
		ts.exiled.remove_at(i)
	else:
		# 0x4b14b8: 驱逐的是道场师范 → 当前修练写回修练记录, 再清空
		for h in State.ts_houses:
			if int(h.seq) == int(e[2].house) and int(h.type) == 10:
				State.dojo_store(State.dojo_cur)
				State.dojo_cur = {"spell": 0, "prog": 0, "need": 0, "done": 0}
		_remove_resident(e[2])
		expel_flag = true
		return_exiles()
		ts._place_models()
	if rs.size() - top <= ROWS:
		top = maxi(top - 1, 0)
	sel = maxi(sel - 1, 1)
	sub = 0
	Game.play_sound(0x218)


## 拆住房会住不下 (0x4a3142 → 0x4b2c69): 切到居民分页选人流放
func start_exile(h: Dictionary, need: int) -> void:
	ex_house = h
	ex_need = need
	ex_sel = 1
	sub = 4
	ts.tab = 2
	ts.focus = 2
	Game.play_sound(0x1fe)
	m._say("请选择要流放的怪物!")


func _exile_pick() -> void:
	var rs := rows()
	var i := top + ex_sel - 1
	if i < 0 or i >= rs.size() or rs[i][1]:
		return
	var r: Dictionary = rs[i][2]
	if ts.exiled.size() >= 255:
		m._say("流放居民过多，请重新做调整!")
		return
	ts.exiled.append(int(r.id))
	_remove_resident(r)
	ex_need -= 1
	var cap := int(MenuTianshu.TYPES[int(ex_house.type)][2])
	if cap == ts.capacity() - State.ts_residents.size():
		ts.remove_house(ex_house)
		return_exiles()
		Game.play_sound(0x217)
		sub = 0
		ts.tab = 0
		ts.focus = 0
	else:
		Game.play_sound(0x200)
	ts._place_models()


func _cancel_exile() -> void:
	sub = 0
	ex_sel = 1
	ts.tab = 3
	ts.focus = 3
	Game.play_sound(0x202)
	return_exiles()
	ts._place_models()


# ---------------- 配置居民 ----------------

func open_config(h: Dictionary) -> void:
	house = h
	cmode = 0
	csel = 0
	ctop = 0
	cslot = 1
	Game.play_sound(0x200)


## 预览 (§1.4): 模式 0 = 房舍 + 候选, 模式 2 = 房舍 + 候选 − 被换下的, 模式 1 = 房舍 − 被迁出的
func _preview() -> Array:
	var cur := house_skill(house)
	var ids := idle()
	var cand := 0
	if cmode != 1 and csel >= 1 and ctop + csel - 1 < ids.size():
		cand = int(ids[ctop + csel - 1].id)
	var out := cur.duplicate()
	var s := slots_of(house)
	for j in 4:
		if cand:
			out[j] += craft(cand, j)
		if cmode >= 1 and cslot - 1 < s.size():
			out[j] -= craft(int(s[cslot - 1]), j)
	return out


func draw_config() -> void:
	if _view:
		_view.set_visible(false)
	var ids := idle()
	var n := ids.size()
	var s := slots_of(house)
	var cap := int(MenuTianshu.TYPES[int(house.type)][2])
	m._img(BUILD % 0, Vector2(560, 67))
	m._img(HOUSEP % 1, Vector2(7, 70))
	m._img(BUILD % 3, Vector2(750, 62))
	if n > 0:
		_scroll(n, CROWS, 759, 110, 385, ctop)
		m._img(LIST % 3, Vector2(755, 87))
		m._img(LIST % 4, Vector2(755, 500))
	_bold("闲置居民清单", Vector2(592, 82), 18, P19)
	if s.size() and csel == 0:
		_outline("退出配置", Vector2(593, 120), 12, P24, P25)
	else:
		_outline("退出配置", Vector2(593, 120), 12, Color.WHITE, P23)
	if (cmode == 0 or cmode == 2) and csel != 0 and (n or s.size()):
		m._c.draw_rect(Rect2(580, 107 + 25 * csel, 160, 25), Color(1, 1, 1, 0x78 / 255.0))
	for i in range(ctop, mini(ctop + CROWS, n)):
		_bold("%-8s" % beast(int(ids[i].id)).name, Vector2(593, 140 + 25 * (i - ctop)), 16, P23)
	# 上方: 房舍技能合计 + 预览
	var cur := house_skill(house)
	var pv := _preview()
	var show := (cmode == 0 and csel != 0 and s.size() < cap and n != 0) or (cmode >= 1 and s.size() > 0)
	for j in 4:
		_bold(CRAFT[j], Vector2(57 + 120 * j, 88), 14, P14)
		_bold("%3d" % int(cur[j]), Vector2(87 + 120 * j, 88), 12, P15)
		if show and int(pv[j]) != int(cur[j]):
			var up := int(pv[j]) > int(cur[j])
			m._img(ICON % (7 if up else 8), Vector2(62 + 120 * j, 100))
			_bold("%3d" % int(pv[j]), Vector2(87 + 120 * j, 110), 12, P17 if up else P16)
	# 中间: 工作位置的 3D 模型
	if _slots == null:
		_slots = UiModelView.new(m._c, m.field)
	_slots.set_visible(true)
	# 工作位 k: 世界 (4450+410k, 2300, 1800/2000/2200/2000/1800) ×3 → 中间最远的弧形 (verify_scene.md §3.4);
	# 焦点模式 0 选中闲置居民时, 再把它画在 (5500,1550,1800) ×3 → 脚底 (327,506)
	var mods: Array = []
	for k in s.size():
		mods.append([int(s[k])] + SLOT_FOOT[k])
	if cmode == 0 and csel >= 1 and ctop + csel - 1 < n:
		mods.append([int(ids[ctop + csel - 1].id), 327, 506, 116])
	_slots.set_models(mods)
	if cmode >= 1 and s.size():
		var fr: Texture2D = m.tex(FRAME)
		if fr:
			var kx := fr.get_width() / 256.0
			m._c.draw_texture_rect_region(fr, Rect2(105 * cslot - 58 - 40, 140, 80, 200), Rect2(0, 0, 256 * kx, 136 * kx))
	# 下方: 居民资料
	var who := 0
	var title := ""
	if cmode >= 1 and cslot - 1 < s.size():
		who = int(s[cslot - 1])
		title = "工作居民资料"
	elif cmode == 0 and csel >= 1 and ctop + csel - 1 < n:
		who = int(ids[ctop + csel - 1].id)
		title = "闲置居民资料"
	if who:
		var b := beast(who)
		m._img(COMMON % 6, Vector2(47, 353))
		m._img(COMMON % 7, Vector2(172, 353))
		_bold(title, Vector2(62, 353 if cmode >= 1 else 355), 16, P15)
		_bold(str(b.name), Vector2(87, 376), 16, P23)
		_bold("%2d" % int(b.get("level", 0)), Vector2(47, 398), 16, P15)
		_bold("级", Vector2(77, 398), 16, P14)
		var rt := int(b.get("race_tab", 0))
		m._img(RACE % rt, Vector2(127, 390))
		_bold(str(_races[rt]) if rt < _races.size() else "", Vector2(157, 398), 16, P15)
		for j in 4:
			var lx := 57 + 60 * (j % 2)
			var ly := 448 + 20 * (j / 2)
			_bold(CRAFT[j], Vector2(lx, ly), 12, P14)
			_bold("%2d" % craft(who, j), Vector2(lx + 30, ly), 12, P15)


## 返回 false = 退出配置画面
func key_config(code: int) -> bool:
	var ids := idle()
	var n := ids.size()
	var s := slots_of(house)
	match cmode:
		0:
			match code:
				KEY_ESCAPE, KEY_CTRL:
					ts._hint = ""
					Game.play_sound(0x202)
					return false
				KEY_UP:
					if n:
						csel -= 1
						if csel < 1 and ctop > 0:
							ctop -= 1
							csel = 1
						csel = maxi(csel, 0)
						Game.play_sound(0x201)
				KEY_DOWN:
					if n:
						csel += 1
						if csel > CROWS:
							ctop = mini(ctop + 1, maxi(n - CROWS, 0))
							csel = CROWS
						csel = mini(csel, n - ctop)
						Game.play_sound(0x201)
				KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
					if csel == 0:
						if s.size():
							cmode = 1
							cslot = 1
							Game.play_sound(0x200)
					elif ctop + csel - 1 < n:
						_place_selected()
		1, 2:
			match code:
				KEY_ESCAPE, KEY_CTRL:
					cmode = 0
					ts._hint = ""
					Game.play_sound(0x202)
				KEY_LEFT, KEY_RIGHT:
					cslot = clampi(cslot + (-1 if code == KEY_LEFT else 1), 1, maxi(s.size(), 1))
					Game.play_sound(0x201)
				KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
					_slot_ok()
	return true


func _place_selected() -> void:
	var ids := idle()
	var r: Dictionary = ids[ctop + csel - 1]
	var cap := int(MenuTianshu.TYPES[int(house.type)][2])
	if slots_of(house).size() < cap:
		assign(house, r)
		if ids.size() - 1 - ctop < CROWS:
			ctop = maxi(ctop - 1, 0)
		csel = 0
	else:
		cmode = 2
		cslot = 1
	Game.play_sound(0x200)


func _slot_ok() -> void:
	var s := slots_of(house)
	if cmode == 1:
		if unassign(house, cslot - 1):
			cslot = maxi(cslot - 1, 1)
			if slots_of(house).is_empty():
				cmode = 0
			Game.play_sound(0x200)
		return
	# 交换
	var ids := idle()
	if ctop + csel - 1 >= ids.size() or cslot - 1 >= s.size():
		ts._hint = "交换怪物发生错误"
		Game.play_sound(0x20e)
		return
	var r: Dictionary = ids[ctop + csel - 1]
	unassign(house, cslot - 1)
	assign(house, r)
	cmode = 0
	cslot = 1
	Game.play_sound(0x200)


func mouse_config(p: Vector2, clicked: bool) -> void:
	var s := slots_of(house)
	if cmode == 0:
		var n := idle().size()
		var vis := mini(CROWS, n - ctop)
		for r in range(0, vis + 1):
			if p.x > 580 and p.x < 740 and p.y > 117 + 25 * r and p.y < 142 + 25 * r:
				if r != csel:
					csel = r
					Game.play_sound(0x201)
				if clicked:
					if r == 0:
						if s.size():
							cmode = 1
							cslot = 1
							Game.play_sound(0x200)
					else:
						_place_selected()
				return
		if clicked and p.x > 18 and p.x < 540 and p.y > 130 and p.y < 350 and s.size():
			csel = 0
			cmode = 1
			Game.play_sound(0x200)
		return
	for k in s.size():
		if p.x > 7 + 105 * k and p.x < 87 + 105 * k and p.y > 130 and p.y < 350:
			if cslot != k + 1:
				cslot = k + 1
				Game.play_sound(0x201)
			if clicked:
				_slot_ok()
			return
	if clicked and p.x > 570 and p.x < 740 and p.y > 142 and p.y < 542:
		cmode = 0
		Game.play_sound(0x202)
