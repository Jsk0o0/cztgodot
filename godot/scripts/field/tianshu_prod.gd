class_name TianshuProd
extends RefCounted
## 天书工房生产画面 (機關工房 = 状态 6: 输入 0x4b8a1a, 绘制 0x4b9ed2; 其他工房 2–5 同一套版式; 逆向笔记 re/menu_tianshu_prod.md)
##   清单 = MAPS.DAT 段 9..13 {页签, 旗标, 物品…}, 旗标置位才出现 (extracted/game/tianshu.json → workshops)
##   版式: 清单 0142/0 (560,67), 左面板 0142/1 (7,67), 说明栏 0142/2 (7,464), 滚动条 0142/3 (750,62);
##     工房名 (39,82) / 「可生产武器清单」(592,82) 18px 色 19; 页签 0148 第 20/18 帧 (450+30k, 77), 选中 21/19 帧弹跳;
##     行 (593, 115+25k) 16px, 持有数「%2d」(708, y); 高亮 (580, 112+25k, 160, 25); 能做 = 色 15, 做不了 = 色 20
##     详情: 物品图 (87,145); 「生产需求」(327,112) 两侧括号 0144/6,7 (317,113)/(392,113); 资源图标 x=327, 数值 (363, 139/162/181/203) 12px;
##     技能「冶金/整备/制药/神技」(322, 225+23k) 14px, 需求值 (363, 226+23k); 不足 = 色 16; 特殊需求 (327,332), 名称 (322, 354+22j)
##     「确定生产」按钮 0245 第 9 帧 (悬停 8) (382,419), 文字 (322,424) 12px; 说明 (102,467) 3 行宽 470 (INFO, F1 切换 HELP)
##   生产: 点「确定生产」先检查 (技能 → 资源 → 特殊, 失败的类别拼在一条提示里) 并立即扣 1 份 → 数量框 (0144/0 在 (405,200)):
##     「+」再检查再扣 1 份, 「−」退还 1 份, 上限 99−持有; 确定 →「完成 X × n」, 物品进背包 (音效 0x214); 取消退还全部
##   木甲兽页签: 每样只能有 1 个, 单件确认框 0144/1「生产木甲兽?」

const BUILD := "ui/all_sys/0142_天书_建筑介面/%03d.png"
const COMMON := "ui/all_sys/0144_天书_共用介面/%03d.png"
const ICON := "ui/all_sys/0146_天书_Icon_共用/%03d.png"
const HOUSE_ICON := "ui/all_sys/0148_天书_Icon_屋舍/%03d.png"
const BTN := "ui/all_sys/0245_000_买卖介面/%03d.png"
const ARROW := "ui/all_sys/0081_000_主介面物品/%03d.png"
const PAL14 := Color8(89, 63, 32)
const PAL15 := Color8(117, 76, 36)
const PAL16 := Color8(229, 69, 16)
const PAL19 := Color8(166, 124, 82)
const PAL20 := Color8(192, 80, 88)
const PAL24 := Color8(237, 192, 95)
const ROWS := 17
const TAB_NAMES := ["器具", "木甲兽"]
const TAB_FRAME := [[20, 21], [18, 19]]
const RES_KEYS := ["金錢", "金屬", "木材", "煤炭"]
const RES_NAMES := ["金钱", "金属", "木材", "煤炭"]
const RES_FRAME := [4, 0, 1, 2]
const RES_Y := [137, 159, 182, 202]
const RES_TY := [139, 162, 181, 203]
const SKILL_KEYS := ["冶金", "整備", "製藥", "神技"]
const SKILL_NAMES := ["冶金", "整备", "制药", "神技"]

var ts: MenuTianshu
var m: MainMenu
var house: Dictionary
var workshop: Dictionary
var tab := 0
var cur := 0        # 选中行 (屏幕行, 0 起)
var top := 0
var state := 0      # 0 清单 / 1 数量框 / 2 单件确认
var qty := 0
var making := 0     # 正在生产的物品
var dlg := 0        # 对话框焦点 0 确定 / 1 取消
var help := false   # F1: 说明栏显示 HELP
var _t := 0.0
static var _data: Dictionary = {}


func _init(owner: MenuTianshu, h: Dictionary) -> void:
	ts = owner
	m = owner.m
	house = h
	if _data.is_empty():
		var p := Game.extracted_dir.path_join("game/tianshu.json")
		if FileAccess.file_exists(p):
			_data = JSON.parse_string(FileAccess.get_file_as_string(p))
	for w in _data.get("workshops", []):
		if int(w.house_type) == int(h.type):
			workshop = w


# ---------------- 数据 ----------------

func entries() -> Array:
	var out: Array = []
	for g in workshop.get("groups", []):
		if int(g.tab) != tab + 1 or not State.test_flag(int(g.flag)):
			continue
		for it in g.items:
			var id := int(it.id)
			# 等级字段 ≠0 或木甲兽页签: 只在条件全满足时出现 (正在生产的那件例外) (0x4ba3cb)
			if id != making:
				if int(it.get("level_9a", 0)) != 0 and not check(it, 1, false):
					continue
				if tab == 1 and (not check(it, 1, false) or State.item_count(id) > 0):
					continue
			out.append(it)
	return out


## 房舍生产技能 = 住在这幢房里的居民 ObjDATA 0xBBF 之和 (0x4b6cd8)
func house_skill(j: int) -> int:
	var n := 0
	for r in State.ts_residents:
		if int(r.house) == int(house.seq):
			var c: Dictionary = ts.craft_of(int(r.id))
			n += int(c.get(SKILL_NAMES[j], 0))
	return n


## 特殊材料: 同一 ID 出现几次就要几个 → [[id, 名称, 需要数]]
func specials(it: Dictionary) -> Array:
	var out: Array = []
	for s in it.get("special", []):
		var id := int(s.get("id", 0)) if s is Dictionary else int(s)
		var nm := str(s.get("name", "")) if s is Dictionary else str(Battle.obj(id).get("name", id))
		var found := false
		for e in out:
			if int(e[0]) == id:
				e[2] = int(e[2]) + 1
				found = true
		if not found and id > 0:
			out.append([id, nm, 1])
	return out


func _res_have(k: int) -> int:
	return [State.money, State.metal, State.wood, State.coal][k]


## 0x4bd7f9: 三类都检查, 失败的类别按 技能 → 资源 → 特殊 拼进一条提示
func check(it: Dictionary, n: int, say: bool) -> bool:
	var msg := ""
	var ok := true
	var req: Dictionary = it.get("skill_req", {})
	for j in 4:
		if house_skill(j) < int(req.get(SKILL_KEYS[j], 0)):
			ok = false
	if not ok:
		msg += " 生产技能不足  "
	var cost: Dictionary = it.get("cost", {})
	var res_ok := true
	for k in 4:
		if _res_have(k) - int(cost.get(RES_KEYS[k], 0)) * n < 0:
			res_ok = false
	if not res_ok:
		msg += " 生产资源不足  "
	var sp_ok := true
	for s in specials(it):
		if State.item_count(int(s[0])) < int(s[2]) * n:
			sp_ok = false
	if not sp_ok:
		msg += " 特殊资源不足  "
	if say and msg != "":
		m._say(msg.strip_edges())
	return ok and res_ok and sp_ok


func _take(it: Dictionary, n: int) -> void:
	var c: Dictionary = it.get("cost", {})
	State.money -= int(c.get("金錢", 0)) * n
	State.metal -= int(c.get("金屬", 0)) * n
	State.wood -= int(c.get("木材", 0)) * n
	State.coal -= int(c.get("煤炭", 0)) * n
	for s in specials(it):
		State.give_item(int(s[0]), -int(s[2]) * n)


func _refund(it: Dictionary, n: int) -> void:
	_take(it, -n)


func _sel_item() -> Dictionary:
	var es := entries()
	if es.is_empty():
		return {}
	if making:
		for e in es:
			if int(e.id) == making:
				return e
	return es[clampi(top + cur, 0, es.size() - 1)]


# ---------------- 绘制 ----------------

func _bold(s: String, p: Vector2, size: int, col: Color) -> void:
	m._text(s, p, size, col)
	m._text(s, p + Vector2(1, 0), size, col)


func draw(delta: float) -> void:
	_t += delta
	var es := entries()
	m._img(BUILD % 0, Vector2(560, 67))
	m._img(BUILD % 1, Vector2(7, 67))
	m._img(BUILD % 2, Vector2(7, 464))
	m._img(BUILD % 3, Vector2(750, 62))
	if es.size():
		var y0 := 110.0 if es.size() <= ROWS else 110.0 + top * 385.0 / es.size()
		var h := 385.0 if es.size() <= ROWS else 385.0 * ROWS / es.size()
		m._c.draw_rect(Rect2(759, y0, 11, h), Color8(255, 253, 227, 200))
		m._img(ARROW % 3, Vector2(755, 87))
		m._img(ARROW % 4, Vector2(755, 500))
	_bold(ts.house_name(house), Vector2(39, 82), 18, PAL19)
	_bold("可生产武器清单", Vector2(592, 82), 18, PAL19)   # 原版機關工房也用这串
	m._img(COMMON % 6, Vector2(317, 113))
	m._img(COMMON % 7, Vector2(392, 113))
	_bold("生产需求", Vector2(327, 112), 16, PAL14)
	var mp := m.mouse()
	var hov := state == 0 and Rect2(382, 416, 44, 28).has_point(mp)
	m._img(BTN % (8 if hov else 9), Vector2(382, 419))
	_bold("确定生产", Vector2(322, 424), 12, PAL14)
	_bold("F1详细说明" if help else "F1功能说明", Vector2(19, 469), 12, PAL14)
	var yb: int = UiAct.bounce(67, int(_t * 35.0)) - 67   # 0x4ba2e2: y0 = 67, 画在 trunc(y + 10)
	for k in 2:
		if k == tab:
			m._img(HOUSE_ICON % TAB_FRAME[k][1], Vector2(450 + 30 * k, 77 + yb))
		else:
			m._img(HOUSE_ICON % TAB_FRAME[k][0], Vector2(450 + 30 * k, 77))
	if es.size():
		m._c.draw_rect(Rect2(580, 112 + 25 * cur, 160, 25), Color(1, 1, 1, 0x78 / 255.0))
	for k in ROWS:
		if top + k >= es.size():
			break
		var it: Dictionary = es[top + k]
		var have := State.item_count(int(it.id))
		var can := check(it, 1, false) and (have < 99 if tab == 0 else have == 0)
		_bold(str(it.name), Vector2(593, 115 + 25 * k), 16, PAL15 if can else PAL20)
		_bold("%2d" % have, Vector2(708, 115 + 25 * k), 16, PAL15)
	var sel := _sel_item()
	if not sel.is_empty():
		_draw_detail(sel)
	match state:
		1:
			_draw_qty(mp)
		2:
			_draw_single(mp)


func _draw_detail(it: Dictionary) -> void:
	var icon := str(it.get("icon_png", ""))
	if icon != "":
		m._img("ui/" + icon, Vector2(87, 145))
	var cost: Dictionary = it.get("cost", {})
	for k in 4:
		var need := int(cost.get(RES_KEYS[k], 0))
		m._img(ICON % RES_FRAME[k], Vector2(327, RES_Y[k]))
		_bold("%2d" % need, Vector2(363, RES_TY[k]), 12, PAL15 if _res_have(k) >= need else PAL16)
	var req: Dictionary = it.get("skill_req", {})
	for j in 4:
		var need := int(req.get(SKILL_KEYS[j], 0))
		_bold(SKILL_NAMES[j], Vector2(322, 225 + 23 * j), 14, PAL14)
		_bold("%2d" % need, Vector2(363, 226 + 23 * j), 12, PAL15 if house_skill(j) >= need else PAL16)
	var sp := specials(it)
	if sp.size():
		m._img(COMMON % 6, Vector2(317, 333))
		m._img(COMMON % 7, Vector2(392, 333))
		_bold("特殊需求", Vector2(327, 332), 16, PAL14)
		for j in mini(sp.size(), 3):
			var ok := State.item_count(int(sp[j][0])) >= int(sp[j][2])
			_bold(str(sp[j][1]), Vector2(322, 354 + 22 * j), 16, PAL15 if ok else PAL16)
			_bold("%d" % int(sp[j][2]), Vector2(397, 354 + 22 * j), 16, PAL15 if ok else PAL16)
	var txt := str(it.get("help_0x142" if help else "info_0x102", ""))
	ts.wrap_text(txt, Vector2(102, 467), 470, 3)


func _draw_qty(mp: Vector2) -> void:
	m._c.draw_rect(Rect2(0, 0, 800, 600), Color(0, 0, 0, 0x50 / 255.0))
	m._img(COMMON % 0, Vector2(405, 200))
	_bold("生产数量", Vector2(459, 225), 16, PAL15)
	m._img(ICON % (12 if Rect2(453, 247, 20, 25).has_point(mp) else 11), Vector2(453, 247))
	m._img(ICON % (10 if Rect2(523, 247, 20, 25).has_point(mp) else 9), Vector2(523, 247))
	m._img(BTN % (8 if dlg == 0 else 9), Vector2(433, 280))
	m._img(BTN % (10 if dlg == 1 else 11), Vector2(515, 280))
	m._text("%2d" % qty, Vector2(483, 247), 20, PAL24, Color(0, 0, 0))


func _draw_single(_mp: Vector2) -> void:
	m._c.draw_rect(Rect2(0, 0, 800, 600), Color(0, 0, 0, 0x50 / 255.0))
	m._img(COMMON % 1, Vector2(405, 200))
	_bold("生产木甲兽?", Vector2(440, 218), 16, PAL15)
	m._img(BTN % (8 if dlg == 0 else 9), Vector2(435, 253))
	m._img(BTN % (10 if dlg == 1 else 11), Vector2(495, 253))


# ---------------- 输入 ----------------

func _start() -> void:
	var it := _sel_item()
	if it.is_empty():
		return
	var have := State.item_count(int(it.id))
	if have >= 99 or (tab == 1 and have >= 1):
		m._say("个数已达上限")
		Game.play_sound(0x20e)
		return
	if not check(it, 1, true):
		Game.play_sound(0x20e)
		return
	_take(it, 1)
	qty = 1
	making = int(it.id)
	dlg = 0
	state = 2 if tab == 1 else 1
	Game.play_sound(0x200)


func _plus() -> void:
	var it := _sel_item()
	if not check(it, 1, false):
		return
	_take(it, 1)
	qty += 1
	var cap := 99 - State.item_count(making)
	if qty > cap:
		qty = cap
		_refund(it, 1)
	Game.play_sound(0x208)


func _minus() -> void:
	if qty > 1:
		qty -= 1
		_refund(_sel_item(), 1)
	Game.play_sound(0x208)


func _confirm() -> void:
	var it := _sel_item()
	m._say("完成 %s X %d" % [it.name, qty] if state == 1 else "完成 %s" % it.name)
	State.give_item(making, qty)
	Game.play_sound(0x214)
	qty = 0
	making = 0
	state = 0


func _cancel(snd := 0x1ff) -> void:
	_refund(_sel_item(), qty)
	qty = 0
	making = 0
	state = 0
	Game.play_sound(snd)


func _move(d: int) -> void:
	var n := entries().size()
	if n == 0:
		return
	if d > 0 and top + cur + 1 < n:
		if cur + 1 >= ROWS:
			top += 1
		else:
			cur += 1
		Game.play_sound(0x201)
	elif d < 0 and top + cur > 0:
		if cur > 0:
			cur -= 1
		else:
			top -= 1
		Game.play_sound(0x201)


## 返回 false = 退出生产画面
func key(code: int) -> bool:
	if state != 0:
		match code:
			KEY_ESCAPE, KEY_CTRL:
				_cancel(0x202 if state == 1 else 0x1ff)
			KEY_LEFT, KEY_RIGHT:
				dlg = 1 - dlg
				Game.play_sound(0x201)
			KEY_UP:
				if state == 1:
					_plus()
			KEY_DOWN:
				if state == 1:
					_minus()
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				if dlg == 0:
					_confirm()
				else:
					_cancel()
		return true
	match code:
		KEY_ESCAPE, KEY_CTRL:
			Game.play_sound(0x202)
			return false
		KEY_UP:
			_move(-1)
		KEY_DOWN:
			_move(1)
		KEY_LEFT, KEY_RIGHT:
			var t := clampi(tab + (-1 if code == KEY_LEFT else 1), 0, 1)
			if t != tab:
				tab = t
				cur = 0
				Game.play_sound(0x201)
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			_start()
		KEY_F1, Pad.X:
			help = not help
			Game.play_sound(0x1fe)
	return true


func mouse(p: Vector2, clicked: bool) -> void:
	if state == 1:
		if Rect2(433, 278, 44, 24).has_point(p):
			dlg = 0
		elif Rect2(515, 278, 44, 24).has_point(p):
			dlg = 1
		if clicked:
			if Rect2(523, 247, 20, 25).has_point(p):
				_plus()
			elif Rect2(453, 247, 20, 25).has_point(p):
				_minus()
			elif Rect2(433, 278, 44, 24).has_point(p):
				_confirm()
			elif Rect2(515, 278, 44, 24).has_point(p):
				_cancel()
		return
	if state == 2:
		if clicked and Rect2(435, 250, 44, 26).has_point(p):
			_confirm()
		elif clicked and Rect2(495, 250, 44, 26).has_point(p):
			_cancel()
		return
	# 悬停页签就切换 (原版不用点)
	for k in 2:
		if Rect2(450 + 30 * k, 77, 25, 35).has_point(p) and k != tab:
			tab = k
			cur = 0
			Game.play_sound(0x201)
	var n := entries().size()
	for k in mini(ROWS, n - top):
		if Rect2(580, 115 + 25 * k, 160, 25).has_point(p):
			if k != cur:
				cur = k
				Game.play_sound(0x201)
			if clicked:
				_start()
			return
	if clicked and Rect2(382, 416, 44, 28).has_point(p):
		_start()
