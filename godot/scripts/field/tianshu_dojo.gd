class_name TianshuDojo
extends RefCounted
## 天书「仙术道场」(房舍类型 10)。屋舍详情三个按钮: 修练 (0148/012, 动作 5)、法术 (0148/015, 动作 6)、拆除。
## 状态 8: 输入 0x4aa2b6, 绘制 0x497134 → 子状态 [0xea42cc] == 3 ? 法术画面 0x4ac726 : 修练画面 0x4ac9c1。
## 「修练」不重设子状态 (原版: 用工具栏离开法术画面后, 再按修练还是进法术画面, 直到在法术画面按取消离开)。
##
## 数据 (State): 当前修练 dojo_cur (0xa763f0)、修练记录 dojo_list (链表 0xa763c0, 表头在前)、仙术装备表 xian_equip (0xa807f0, 20 格)。
##   妖怪记录 special_skill (+0x40, kv 0x3F8) = 能教的仙术; 仙术记录 learn_need (+0xb8, kv 0x3F9) = 修练需要值。
##   战斗胜利 (桓远之在队) 进度 += 经验 / 10 (battle._victory); 学会的仙术要在法术画面装备, 战斗和奇术页里才加给桓远之。
##
## 修练画面 (0x4ac9c1, 子状态 0 清单 / 1「是否更替?」/ 2「是否撤回?」):
##   0142/000 (560,67)、0145/005 (6,67)、0145/006 (6,317)、滚动槽 0142/003 (750,62); 滚动块 (759, 110+top·385/n, 11, …),
##   箭头 0081/003 (755,87)、0081/004 (755,500); 选中条 (583, 77+25·光标, 160, 30) 白 0x50
##   标题 (20 号 色 19)「师范妖魔清单」(602,82)「修练中仙术」(196,79)「可修练妖魔仙术」(196,329)
##   清单 (0x4acee4): 先道场里的师范 (仙术 ≠ 0), 再闲置居民 (能教的仙术没修完、同一种妖怪只列一次); 行 (593, 115+25k) 18 号,
##     师范色 21、闲置色 23, 一屏 17 行
##   上方「修练中」资料原点 (6,67), 下方 (光标在闲置居民上) 原点 (6,317): 种族图标 (285,60)+o, 名字 (185,68)+o, 等级 (340,68)+o,
##     「级」(370,68)+o, 仙术名 (185,90)+o, 进度/需要 (300,90)+o, 说明 (185,135)+o 宽 340 行距 21 最多 4 行;
##     下方另画妖怪 3D 模型 (0x495177: 世界 (4600,1450,2000)×4, 角度 8 → 投影脚底 (124,505))
## 法术画面 (0x4ac726 / 输入 0x4aaf99): 左「未装备仙术」= 修完的仙术 (按修练记录顺序), 右「已装备仙术」= 装备表前 8 格;
##   焦点 0 左 / 1 右 / 2 替换 (装满 8 格后再装备)。

const BUILD := "ui/all_sys/0142_天书_建筑介面/%03d.png"
const HOUSEP := "ui/all_sys/0145_天书_屋舍介面/%03d.png"
const COMMON := "ui/all_sys/0144_天书_共用介面/%03d.png"
const LIST := "ui/all_sys/0081_000_主介面物品/%03d.png"
const RACE := "ui/all_sys/0134_000_种族分类icon/%03d.png"
const OKBTN := "ui/all_sys/0245_000_买卖介面/%03d.png"
const P14 := Color8(89, 63, 32)
const P15 := Color8(117, 76, 36)
const P19 := Color8(166, 124, 82)
const P20 := Color8(192, 80, 88)
const P21 := Color8(91, 110, 70)
const P23 := Color8(89, 86, 143)
const PAGE := 17
const MPAGE := 8
# 原版字号 → 这里的字号 (天书其他画面同一换算: 20 → 18, 18 → 16, 16 → 14)
const F_TITLE := 18
const F_TEXT := 16

var ts: MenuTianshu
var m: MainMenu
var house: Dictionary
var sub := 0          # [0xea42cc]: 0 清单 / 1 更替框 / 2 撤回框 / 3 法术画面
var dlg := 1          # 是否框焦点 0 是 / 1 否
var top := 0          # [0xea43e0]
var cur := 1          # [0x4e7048] (1 起)
var mfocus := 0       # [0xea42d0]: 0 左 / 1 右 / 2 替换
var ltop := 0
var lcur := 1
var rtop := 0
var rcur := 1
var cur_id := 0       # [0xea42d8] 左表光标所在的仙术
var _rcount := 0      # [0xea43f4] 右表条数 (绘制时算)
var _last_mp := Vector2(-1, -1)
var _view: UiModelView


func _init(owner: MenuTianshu) -> void:
	ts = owner
	m = owner.m


func free_fx() -> void:
	if _view:
		_view.free_all()
	_view = null


func hide_models() -> void:
	if _view:
		_view.set_visible(false)


## 屋舍详情按「修练」/「法术」进来 (0x49e499): 修练不动子状态, 法术设子状态 3
func open(h: Dictionary, magic: bool) -> void:
	house = h
	if magic:
		sub = 3
	Game.play_sound(0x200)


## 0x49b838: 回到屋舍分页并选中这幢
func _exit() -> void:
	ts.mode = ""
	ts.tab = 3
	ts.focus = 3
	ts.sel = maxi(State.ts_houses.find(house), 0)
	ts.hbtn = -1
	hide_models()


func _bytes(s: String) -> int:
	var n := 0
	for ch in s:
		n += 1 if ch.unicode_at(0) < 0x80 else 2
	return n


func _bold(s: String, p: Vector2, size: int, col: Color) -> void:
	m._text(s, p, size, col)
	m._text(s, p + Vector2(1, 0), size, col)


func _spell(id: int) -> int:
	return int(Battle.obj(id).get("special_skill", 0))


func _need(spell: int) -> int:
	return State.dojo_need(spell)


func _cap() -> int:
	return int(MenuTianshu.TYPES[10][2])


## 清单 0x4acee4: [{t: 10 师范 / 0 闲置, id, r: 居民记录}]
func entries() -> Array:
	var out: Array = []
	var ids: Array = []
	for id in house.get("slots", []):
		if _spell(int(id)) != 0:
			out.append({"t": 10, "id": int(id), "r": null})
			ids.append(int(id))
	for r in State.ts_residents:
		var id := int(r.id)
		if id == 0 or int(r.house) != 0 or ids.has(id):
			continue
		var sp := _spell(id)
		if sp == 0:
			continue
		var n := State.dojo_find(sp)
		if not n.is_empty() and int(n.done) != 0:
			continue
		out.append({"t": 0, "id": id, "r": r})
		ids.append(id)
	return out


# ---------------- 绘制 ----------------

func draw() -> void:
	if sub == 3:
		hide_models()
		_draw_magic()
	else:
		_draw_train()


func _draw_train() -> void:
	var es := entries()
	var n := es.size()
	m._img(BUILD % 0, Vector2(560, 67))
	m._img(HOUSEP % 5, Vector2(6, 67))
	m._img(HOUSEP % 6, Vector2(6, 317))
	m._img(BUILD % 3, Vector2(750, 62))
	if n:
		var h := 385.0 * PAGE / n if n > PAGE else 385.0
		m._c.draw_rect(Rect2(759, 110 + top * 385.0 / n, 11, h), Color8(255, 253, 227, 200))
		m._img(LIST % 3, Vector2(755, 87))
		m._img(LIST % 4, Vector2(755, 500))
		m._c.draw_rect(Rect2(583, 77 + 25 * cur, 160, 30), Color(1, 1, 1, 0x50 / 255.0))
	# 0x4acb3a: 没有当前修练而道场满员 → 自动迁出师范
	if int(State.dojo_cur.spell) == 0 and house.get("slots", []).size() >= _cap():
		if ts.res.unassign(house, 0):
			ts._place_models()
			es = entries()
			n = es.size()
	_bold("师范妖魔清单", Vector2(602, 82), F_TITLE, P19)
	_bold("修练中仙术", Vector2(196, 79), F_TITLE, P19)
	_bold("可修练妖魔仙术", Vector2(196, 329), F_TITLE, P19)
	for e in es:
		if int(e.t) == 10:
			_info(int(e.id), Vector2(6, 67), int(State.dojo_cur.prog))
	for k in range(top, mini(top + PAGE, n)):
		var e: Dictionary = es[k]
		_bold("%-8s " % str(Battle.obj(int(e.id)).get("name", e.id)), Vector2(593, 115 + 25 * (k - top)), F_TEXT,
			P21 if int(e.t) == 10 else P23)
	var i := top + cur - 1
	if i >= 0 and i < n and int(es[i].t) != 10:
		var sp := _spell(int(es[i].id))
		var nd := State.dojo_find(sp)
		_info(int(es[i].id), Vector2(6, 317), 0 if nd.is_empty() else int(nd.prog))
		if _view == null:
			_view = UiModelView.new(m._c, m.field)
		_view.set_visible(true)
		_view.set_models([[int(es[i].id), 124, 505, 152, 8]])   # (4600,1450,2000)×4 角度 8, 同居民页相机投影
	else:
		hide_models()
	if sub in [1, 2]:
		m._c.draw_rect(Rect2(0, 0, 800, 600), Color(0, 0, 0, 0x50 / 255.0))
		m._img(COMMON % 1, Vector2(310, 250))
		_bold("是否更替?" if sub == 1 else "是否撤回?", Vector2(350, 267), F_TEXT, P15)
		m._img(OKBTN % (8 if dlg == 0 else 9), Vector2(340, 303))
		m._img(OKBTN % (10 if dlg == 1 else 11), Vector2(400, 303))


## 一块妖怪 + 仙术资料; o = 面板原点 (上 (6,67) / 下 (6,317)), prog = 显示的进度
func _info(id: int, o: Vector2, prog: int) -> void:
	var b := ts.res.beast(id)
	m._img(RACE % int(b.get("race_tab", 0)), o + Vector2(285, 60))
	_bold(str(b.get("name", id)), o + Vector2(185, 68), F_TEXT, P15)
	_bold("%2d" % int(b.get("level", 0)), o + Vector2(340, 68), F_TEXT, P15)
	_bold("级", o + Vector2(370, 68), F_TEXT, P14)
	var sp := _spell(id)
	var so := Battle.obj(sp)
	_bold(str(so.get("name", "")), o + Vector2(185, 90), F_TEXT, P14)
	_bold("%d/%d" % [prog, _need(sp)], o + Vector2(300, 90), F_TEXT, P15)
	_wrap(str(so.get("desc", "")), o + Vector2(185, 135), 340.0, 21, 4)


func _wrap(s: String, at: Vector2, width: float, step: int, lines: int) -> void:
	var rows := MainMenu.wrap_note(s, width, F_TEXT, lines)
	for k in rows.size():
		_bold(rows[k], at + Vector2(0, step * k), F_TEXT, P15)


## 左表: 修练记录顺序里完成的仙术 (0x4adba6)
func learned() -> Array:
	var out: Array = []
	for x in State.dojo_list:
		var id := int(x.spell)
		var nd := State.dojo_find(id)
		if not nd.is_empty() and int(nd.done) == 1:
			out.append(id)
	return out


## 右表: 装备表前 8 格, 遇空格停 (0x4addad)
func equipped() -> Array:
	var out: Array = []
	for k in MPAGE:
		var id := int(State.xian_equip[k])
		if id == 0:
			break
		out.append(id)
	return out


func _draw_magic() -> void:
	var ls := learned()
	var rs := equipped()
	_rcount = rs.size()
	m._img(HOUSEP % 4, Vector2(25, 122))
	m._img(HOUSEP % 3, Vector2(405, 122))
	m._img(HOUSEP % 8, Vector2(355, 115))
	m._img(BUILD % 2, Vector2(127, 364))
	var nl := ls.size()
	if nl:
		var h := 139.0 * MPAGE / nl if nl > MPAGE else 139.0
		m._c.draw_rect(Rect2(364, 163 + ltop * 139.0 / nl, 11, h), Color8(255, 253, 227, 200))
	m._img(LIST % 3, Vector2(360, 140))
	m._img(LIST % 4, Vector2(360, 307))
	if mfocus != 1:
		m._c.draw_rect(Rect2(40, 140 + 22 * lcur, 300, 25), Color(1, 1, 1, 0x78 / 255.0))
	if _rcount and mfocus != 0:
		m._c.draw_rect(Rect2(420, 140 + 22 * rcur, 300, 25), Color(1, 1, 1, 0x78 / 255.0))
	_bold("未装备仙术", Vector2(155, 134), F_TITLE, P19)
	_bold("已装备仙术", Vector2(535, 134), F_TITLE, P19)
	for r in MPAGE:
		var i := ltop + r
		if i >= nl:
			break
		var id := int(ls[i])
		_bold("%-8s " % str(Battle.obj(id).get("name", id)), Vector2(52, 167 + 22 * r), F_TEXT, P20 if rs.has(id) else P15)
		if r + 1 == lcur and mfocus == 0:
			cur_id = id
			_note(id)
	for r in MPAGE:
		var i := rtop + r
		if i >= _rcount:
			break
		_bold("%-8s " % str(Battle.obj(int(rs[i])).get("name", rs[i])), Vector2(432, 167 + 22 * r), F_TEXT, P15)
		if r + 1 == rcur and mfocus != 0:
			_note(int(rs[i]))


## 说明 (222,367) 宽 470 行距 25; 和主菜单奇术页一样把功能说明和描述合在一起 (不做 F1 切换)
func _note(id: int) -> void:
	var rows := MainMenu.note_rows(Battle.obj(id), 470.0)
	for k in rows.size():
		m._text(rows[k][0], Vector2(222, 367 + 25 * k), F_TEXT, rows[k][1])


# ---------------- 输入 ----------------

## 0x4ae00d: 选闲置居民。道场有空位就放进去并开始修练它的仙术, 满了弹「是否更替?」
func _choose(r: Dictionary) -> void:
	if house.get("slots", []).size() < _cap():
		ts.res.assign(house, r)
		ts._place_models()
		var sp := _spell(int(r.id))
		var nd := State.dojo_find(sp)
		if nd.is_empty():
			# 没修过: 只改编号和需要值, 进度 / 完成沿用当前块里的值 (原版就是这样) 再记一条
			State.dojo_cur.spell = sp
			State.dojo_cur.need = _need(sp)
			State.dojo_store(State.dojo_cur)
		elif not is_same(nd, State.dojo_cur):
			State.dojo_cur = nd.duplicate()
		sub = 0
		cur = 1
	else:
		sub = 1
		dlg = 1


## 0x4ae137: 更替。迁出师范、放进新的; 旧修练写回记录; 新仙术修过就接着, 没修过从 0 开始 (这时不记)
func _swap(r: Dictionary) -> void:
	if ts.res.unassign(house, 0):
		ts.res.assign(house, r)
		ts._place_models()
	else:
		ts._hint = "交换怪物发生错误"
	State.dojo_store(State.dojo_cur)
	var sp := _spell(int(r.id))
	var nd := State.dojo_find(sp)
	if nd.is_empty():
		State.dojo_cur = {"spell": sp, "prog": 0, "need": _need(sp), "done": 0}
	elif not is_same(nd, State.dojo_cur):
		State.dojo_cur = nd.duplicate()
	sub = 0
	cur = 1


## 0x4ae261: 撤回。迁出师范, 修练写回记录, 当前清空
func _withdraw() -> void:
	if house.get("slots", []).size() >= _cap():
		if ts.res.unassign(house, 0):
			ts._place_models()
	State.dojo_store(State.dojo_cur)
	State.dojo_cur = {"spell": 0, "prog": 0, "need": 0, "done": 0}
	sub = 0
	cur = 1
	Game.play_sound(0x202)


func _confirm_row() -> void:
	var es := entries()
	var i := top + cur - 1
	if i < 0 or i >= es.size():
		return
	if es[i].r == null:
		sub = 2
		dlg = 1
		Game.play_sound(0x1ff)
	else:
		_choose(es[i].r)
		Game.play_sound(0x200)


func _dlg_ok() -> void:
	if dlg == 1:
		sub = 0
		Game.play_sound(0x1ff)
		return
	if sub == 1:
		var es := entries()
		var i := top + cur - 1
		if i >= 0 and i < es.size() and es[i].r != null:
			_swap(es[i].r)
		else:
			sub = 0
	else:
		_withdraw()
	Game.play_sound(0x200)


## 上下 / 翻页 (0x4aa804 一带): 返回 [光标, 顶行]
static func nav(code: int, c: int, t: int, n: int, page: int) -> Array:
	match code:
		KEY_UP:
			c -= 1
			if c < 1:
				t = maxi(t - 1, 0)
				c = 1
		KEY_DOWN:
			c += 1
			if c > page:
				t = mini(t + 1, maxi(n - page, 0))
				c = page
			if c + t > n:
				c = n - t
		KEY_PAGEUP:
			if t == 0:
				c = 1
			else:
				t = maxi(t - page, 0)
		KEY_PAGEDOWN:
			if n - t <= page:
				c = n - t
			else:
				t += page
				if n - t < page:
					t = n - page
		KEY_END:
			if n > page:
				c = page
				t = n - page
			else:
				c = n
		KEY_HOME:
			t = 0
			c = 1
	return [maxi(c, 1), t]


func key(code: int) -> bool:
	if sub == 3:
		_key_magic(code)
		return true
	if sub in [1, 2]:
		match code:
			KEY_LEFT, KEY_RIGHT:
				dlg = 1 - dlg
				Game.play_sound(0x201)
			KEY_ESCAPE, KEY_CTRL:
				sub = 0
				Game.play_sound(0x202)
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				_dlg_ok()
		return true
	if code in [KEY_ESCAPE, KEY_CTRL]:
		cur = 1
		Game.play_sound(0x202)
		_exit()
		return true
	var n := entries().size()
	if n == 0:
		return true
	match code:
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			_confirm_row()
		KEY_UP, KEY_DOWN, KEY_PAGEUP, KEY_PAGEDOWN, KEY_HOME, KEY_END:
			var r := nav(code, cur, top, n, PAGE)
			cur = r[0]
			top = r[1]
			Game.play_sound(0x201 if code in [KEY_UP, KEY_DOWN] else 0x212)
	return true


func mouse(p: Vector2, clicked: bool) -> void:
	var moved := p != _last_mp
	_last_mp = p
	if sub == 3:
		_mouse_magic(p, clicked, moved)
		return
	if sub in [1, 2]:
		if p.y > 300 and p.y < 326:
			var k := 0 if p.x > 340 and p.x < 384 else (1 if p.x > 400 and p.x < 444 else -1)
			if k >= 0:
				if k != dlg:
					dlg = k
					Game.play_sound(0x201)
				if clicked:
					_dlg_ok()
		return
	var n := entries().size()
	if n == 0:
		return
	for k in mini(PAGE, n - top):
		if p.x > 580 and p.x < 743 and p.y > 115 + 25 * k and p.y < 140 + 25 * k:
			if moved and cur != k + 1:
				cur = k + 1
				Game.play_sound(0x201)
			if clicked:
				cur = k + 1
				_confirm_row()
			return
	if not clicked:
		return
	if Rect2(755, 87, 20, 20).has_point(p):
		key(KEY_UP)
	elif Rect2(755, 500, 20, 20).has_point(p):
		key(KEY_DOWN)
	elif p.x >= 759 and p.x < 770 and n > PAGE:
		if p.y >= 110 + (top + PAGE) * 385.0 / n and p.y < 495:
			top = mini(top + PAGE, n - PAGE)
			Game.play_sound(0x212)
		elif p.y >= 110 and p.y < 110 + top * 385.0 / n:
			top = maxi(top - PAGE, 0)
			Game.play_sound(0x212)


# ---------------- 法术画面 ----------------

## 0x4adf97: 前 8 格里已有 → false; 有空格写入; 8 格全满 → 不写入但也算成功
func _equip(id: int) -> bool:
	for k in MPAGE:
		if int(State.xian_equip[k]) == id:
			return false
	for k in MPAGE:
		if int(State.xian_equip[k]) == 0:
			State.xian_equip[k] = id
			return true
	return true


## 0x4adfd8 + 0x4ab735: 前 8 格里找到就清掉, 再压紧一趟
func _unequip(id: int) -> bool:
	for k in MPAGE:
		if int(State.xian_equip[k]) == id:
			State.xian_equip[k] = 0
			for j in range(k, MPAGE - 1):
				State.xian_equip[j] = State.xian_equip[j + 1]
				State.xian_equip[j + 1] = 0
			return true
	return false


func _exit_magic() -> void:
	cur = 1
	lcur = 1
	rcur = 1
	sub = 0
	mfocus = 0
	Game.play_sound(0x202)
	_exit()


func _magic_ok() -> void:
	match mfocus:
		0:
			if learned().is_empty():
				return
			var n0 := _rcount
			if _equip(cur_id):
				if n0 >= MPAGE:
					mfocus = 2
				Game.play_sound(0x200)
			else:
				m._say("已装配此法术!!")
				Game.play_sound(0x20e)
		1:
			var rs := equipped()
			var i := rtop + rcur - 1
			if i >= 0 and i < rs.size() and _unequip(int(rs[i])):
				rcur = maxi(rcur - 1, 1)
				Game.play_sound(0x200)
			else:
				ts._hint = "解除法术失败"
				Game.play_sound(0x20e)
		2:
			var i := rtop + rcur - 1
			if i >= 0 and i < MPAGE and int(State.xian_equip[i]) != 0:
				State.xian_equip[i] = cur_id
				mfocus = 0
				rcur = 1
				Game.play_sound(0x200)
			else:
				ts._hint = "法术替换错误"
				Game.play_sound(0x20e)


func _key_magic(code: int) -> void:
	match code:
		KEY_ESCAPE, KEY_CTRL:
			if mfocus == 2:
				mfocus = 0
				Game.play_sound(0x1ff)
			else:
				_exit_magic()
		KEY_LEFT, KEY_RIGHT:
			if mfocus == 0:
				if _rcount:
					mfocus = 1
					Game.play_sound(0x1fe)
				else:
					Game.play_sound(0x20e)
			elif mfocus == 1:
				mfocus = 0
				Game.play_sound(0x1fe)
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			_magic_ok()
		KEY_UP, KEY_DOWN, KEY_PAGEUP, KEY_PAGEDOWN, KEY_HOME, KEY_END:
			if mfocus == 0:
				var n := learned().size()
				if n:
					var r := nav(code, lcur, ltop, n, MPAGE)
					lcur = r[0]
					ltop = r[1]
			else:
				var n := equipped().size()
				if n:
					var r := nav(code, rcur, rtop, n, MPAGE)
					rcur = r[0]
					rtop = r[1]
			Game.play_sound(0x201 if code in [KEY_UP, KEY_DOWN] else 0x212)


func _mouse_magic(p: Vector2, clicked: bool, moved: bool) -> void:
	if mfocus == 0:
		var n := learned().size()
		for k in mini(MPAGE, n - ltop):
			if p.x > 39 and p.x < 339 and p.y > 167 + 22 * k and p.y < 189 + 22 * k:
				if moved and lcur != k + 1:
					lcur = k + 1
					Game.play_sound(0x201)
				if clicked:
					lcur = k + 1
					_magic_ok()
				return
		if clicked and p.x >= 419 and p.x < 733 and p.y >= 167 and p.y < 343:
			_key_magic(KEY_RIGHT)
		return
	var n := equipped().size()
	for k in mini(MPAGE, n - rtop):
		if p.x > 419 and p.x < 733 and p.y > 167 + 22 * k and p.y < 189 + 22 * k:
			if moved and rcur != k + 1:
				rcur = k + 1
				Game.play_sound(0x201)
			if clicked:
				rcur = k + 1
				_magic_ok()
			return
	if clicked and mfocus == 1 and p.x > 39 and p.x < 339 and p.y > 167 and p.y < 343:
		mfocus = 0
		Game.play_sound(0x1fe)
