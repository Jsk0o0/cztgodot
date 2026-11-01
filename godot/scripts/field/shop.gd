class_name Shop
extends CanvasLayer
## 商店 (事件 0xca open_shop, 参数 = 商品编号表; 先问「客倌 您要買東西還是賣東西」(0x45d518), 绘制 0x45e69f):
##   全屏底色; 背景 ACT 9020 qq0 (0245 第 0 帧) (0,0); 顶栏 买 qq2 (0245 第 2 帧) / 卖 qq3 (第 3 帧) (0,0); 底栏 0068 第 1 帧 (0,560)
##   表头条 0245 第 4 帧 (0,60), 清单 第 5 帧 (0,85), 合计条 第 6 帧 (0,435), 滚动条 第 7 帧 (570,54) (超过一页时), 说明栏 第 15 帧 (62,478)
##   表头 12px「名称」(205,65)「单价」(400,65)「数量」(460,65)「现有」(520,65); 金钱图标 (760,6)
##   清单 0x45e9b3(0,85): 第 k 行文字 y = 85+2+25k (16px 字体 0xa7a6d0), 名称 (200, y−1)+(201, y) 双描,
##     单价「%6d」(370 / 371, y), 数量「%2d」(460, y), 现有「%2d」(520, y); 选中行光条 (180, y−12, 380×32) 白 alpha 0x32,
##     并把选中物品的大图 (道具 ACT 第 0 号动作) 画在 (10, 90)。清单底图的行条在 85+25k, 高约 21
##   合计条: 「总价:」「余额:」+「%-7d」; 右侧队员卡 0245 第 12–14 帧 (189×132): 换上后的攻防增减「+%d」「-%d」
## 卖出 (0x45eb92 / 0x45e178): 单价 = ObjDATA 0xC1D 价格 >> 1; 清单按 6 个分类页签 (恢复/辅助/武器/防具/饰品/足部),
##   战斗道具、法宝、素材 / 任务物品不出现; 不可卖的物品 (0xC1D 第 0 字节 = 0) 也列出, 单价显示 0, 确认时「【名】不可贩卖!!」
##   (原版这时仍会把钱加上 — 只影响 5216 投弊式铠甲每件 1 文; 按用户决定修掉, 不加钱)
## 状态机 [0x9f18e0] (0x45d688): 买 / 卖一样, 商品都按 6 个页签分类 (表 0x4e3f5c: 202 203 204 205 206 208)
##   1 BROWSE 选页签: ←/→ 换页 (到头停住), 确认或点清单 → 2 (清空数量); 取消 → 回主提示
##   2 ROWS 调数量: 每行各有数量 (购物车 0x9f18f4), ↑/↓ 换行, ←/→ 或点 −/+ (只认选中行, 按住连发) 改数量;
##     确认 → 3, 鼠标移到 (465,447); 取消 → 清空回 1, 鼠标移到 (160,14)
##   3 BUTTONS 确定 / 取消按钮: ←/→ 换; 确定: 买时总价 0 播 0x20e 不动, 否则问「确定要购买吗?」→ 4; 取消: 清空回 2; 取消键: 回 2 (保留数量)
##   4 ASK 回答: 确定成交回 2 (买的是装备类, 分类 >= 204, 问「要马上装备吗?」→ 5); 取消键或「取消」清空回 2
##   5 ASK2: 确定 → 打开主菜单装备页 (0x47e45a + 0x4801e6), 回 2
##   没有弹框时全程有效: 右上角叉 (760–790, 6–30) 直接离开商店; 点页签 (150+30k, 4–36) → 1, 点当前页签 → 2;
##   鼠标在确定 / 取消上 (445+55k, 442–472) 高亮, 点击 → 3 并马上执行
##   加数量 (0x45dfd7): 买: 单价 + 总价 > 金钱 → 「金钱不够!!」, 不加; 现有 + 数量 <= 99; 卖: 不超过现有
##   未还原: 选页签时选中页签的上下浮动 (0xc70160 那套动画参数), 这里固定在 y=4

signal closed

const UI := "ui/all_sys/0245_000_买卖介面/%03d.png"
const EL := "ui/all_sys/0068_000_主介面底图元件/%03d.png"
const CAT := "ui/all_sys/0106_000_物品分类icon/%03d.png"
const TEXT_COL := Color8(117, 76, 36)
const DARK_COL := Color8(89, 63, 32)
const CREAM := Color8(234, 217, 182)
const GREY_COL := Color8(192, 80, 88)
const ROWS := 14   # 0x45d33d
const MEMBER_CARD := {1: 12, 3: 13, 2: 14}
const SLOT_OF_SUB := {204: 0, 205: 1, 206: 2, 208: 3}
const TABS := [202, 203, 204, 205, 206, 208]   # 0x4e3f5c
const TAB_FRAME := [11, 9, 2, 3, 4, 6]         # ACT 9024 qq2–7 / 选中 qq17–22 → 0106 / 0107 的帧
const CAT_SEL := "ui/all_sys/0107_000_物品分类icon选/%03d.png"
const CLOSE := "ui/all_sys/0171_000_离开叉叉/%03d.png"   # ACT 9023 qq7 / qq8
enum {BROWSE = 1, ROWS_EDIT = 2, BUTTONS = 3, ASK = 4, ASK2 = 5}

var goods: Array = []
var selling := false
var _c: Control
var _tex := {}
var _sel := 0
var _top := 0
var _tab := 0
var _state := BROWSE
var _cart := {}      # 物品 → 数量
var _btn := 0        # 0 确定 / 1 取消
var _btn_hover := false
var _x_hover := false
var _flash := 0      # 点 −/+ 的按下图: 1 − / 2 +
var _flash_n := 0
var _ask := {}       # 弹框: {box, buttons, hits, glyphs, sel}
var _hold := 0       # 鼠标按住 −/+ 的帧数 (连发)
var _hold_t := 0.0
var left := false    # 点右上角叉离开
var _msg := ""
var _msg_t := 0.0
var _msg_at := Vector2(320, 200)


func _ready() -> void:
	layer = 12
	_c = Control.new()
	_c.size = Vector2(800, 600)
	_c.mouse_filter = Control.MOUSE_FILTER_IGNORE   # 点击交给 _unhandled_input (STOP 会让 GUI 吞掉鼠标按键)
	_c.draw.connect(_draw)
	add_child(_c)


func tex(p: String) -> Texture2D:
	if not _tex.has(p):
		_tex[p] = Game.load_texture(p)
	return _tex[p]


func _img(p: String, pos: Vector2) -> void:
	var t := tex(p)
	if t:
		_c.draw_texture(t, pos)


## 文字: 半角占字号一半宽, 全角一个字号宽 (原版 GDI 排版)
func _text(s: String, pos: Vector2, size: int, col := TEXT_COL) -> void:
	var f: Font = Game.font_body
	var x := pos.x
	for ch in s:
		var half := ch.unicode_at(0) < 0x80
		if ch != " ":
			var fs := Game.half_size(size, 2) if half else size   # 半角字缩一点, 数字之间留空
			var w := f.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var p := Vector2(x + ((size * 0.5 + Game.HALF_GAP if half else float(size)) - w) * 0.5, pos.y + size * 0.88)
			_c.draw_string_outline(f, p, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 2, CREAM)
			_c.draw_string(f, p, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		x += size * 0.5 + Game.HALF_GAP if half else float(size)


func _list() -> Array:
	var cat := int(TABS[_tab])
	if not selling:
		return goods.filter(func(id): return int(Battle.obj(int(id)).get("sub", 0)) == cat)
	var out: Array = []
	for it in State.items:
		var r := Battle.obj(int(it))
		if int(State.items[it]) > 0 and int(r.get("sub", 0)) == cat:
			out.append(int(it))
	out.sort()
	return out


func _total() -> int:
	var t := 0
	for id in _cart:
		t += price(id) * int(_cart[id])
	return t


func _sellable(id: int) -> bool:
	return int(Battle.obj(id).get("sellable", 1)) != 0


func price(id: int) -> int:
	var p := int(Battle.obj(id).get("price", 0))
	return p >> 1 if selling else p


func _process(delta: float) -> void:
	if Game.cursor:
		Game.cursor.set_state(9001, 9)   # 商店 (0x45e69f): 普通指针
		Game.cursor.fps = GameCursor.FPS_FIELD
	if _msg_t > 0:
		_msg_t -= delta
	var m := _c.get_local_mouse_position()
	if _ask.is_empty():
		_x_hover = Rect2(760, 6, 30, 24).has_point(m)
		_btn_hover = false
		for k in 2:
			if Rect2(445 + 55 * k, 442, 45, 30).has_point(m):
				_btn = k
				_btn_hover = true
	else:
		for k in (_ask.hits as Array).size():
			if (_ask.hits[k] as Rect2).has_point(m) and int(_ask.sel) != k:
				_ask.sel = k
				Game.play_sound(0x201)
	# 按住 −/+ 连发 (0x4428f8: 按下当帧, 之后过 3 帧起每 3 帧一次)
	if _state == ROWS_EDIT and _hold and _ask.is_empty() and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_hold_t += delta
		while _hold_t >= 3.0 / 35.0:
			_hold_t -= 3.0 / 35.0
			_step(1 if _hold == 2 else -1)
	else:
		_hold = 0
	_c.queue_redraw()


func _draw() -> void:
	_c.draw_rect(Rect2(0, 0, 800, 600), Color.BLACK)
	_img(UI % 0, Vector2.ZERO)
	_img(UI % (3 if selling else 2), Vector2.ZERO)
	_img(EL % 1, Vector2(0, 560))
	_img(UI % 4, Vector2(0, 60))
	_img(UI % 5, Vector2(0, 85))
	_img(UI % 6, Vector2(0, 435))
	var list := _list()
	_img(UI % 7, Vector2(570, 54))
	_img(UI % 15, Vector2(62, 478))
	_text("名称", Vector2(205, 65), 12)
	_text("单价", Vector2(400, 65), 12)
	_text("数量", Vector2(460, 65), 12)
	_text("现有", Vector2(520, 65), 12)
	_text("金钱 %d" % State.money, Vector2(640, 12), 16, DARK_COL)
	_img(CLOSE % (1 if _x_hover else 0), Vector2(760, 6))
	for k in TABS.size():
		_img((CAT_SEL if k == _tab else CAT) % int(TAB_FRAME[k]), Vector2(150 + 30 * k, 4))
	for i in ROWS:
		var k := _top + i
		if k >= list.size():
			break
		var id: int = list[k]
		var r := Battle.obj(id)
		var y := 87.0 + 25.0 * i
		_img(UI % 16, Vector2(420, y - 7))   # − (ACT 9020 qq17, 0x45ef94)
		_img(UI % 17, Vector2(430, y - 7))   # + (qq18)
		if k == _sel and _state >= ROWS_EDIT:
			if _flash:   # 按下图 qq19 / qq20, 画 5 帧 (0x45efc6)
				_img(UI % (17 + _flash), Vector2(420 + 10 * (_flash - 1), y - 7))
				_flash_n += 1
				if _flash_n >= 5:
					_flash = 0
					_flash_n = 0
			_c.draw_rect(Rect2(180, y - 12, 380, 32), Color(1, 1, 1, 0x32 / 255.0))
			var icon := str(r.get("icon", ""))
			if icon != "":
				_img(icon, Vector2(10, 90))
		var ok := (selling and _sellable(id)) or (not selling and State.money >= price(id))
		var col := TEXT_COL if ok else GREY_COL
		_text(str(r.get("name", id)), Vector2(200, y - 1), 16, col)
		_text("%6d" % price(id), Vector2(370, y), 16, col)
		_text("%2d" % int(_cart.get(id, 0)), Vector2(460, y), 16, col)
		_text("%2d" % int(State.items.get(id, 0)), Vector2(520, y), 16, col)
	# 合计条
	var total := _total()
	_text("总价:", Vector2(30, 443), 16, DARK_COL)
	_text("%-7d" % total, Vector2(90, 443), 16)
	_text("余额:", Vector2(300, 443), 16, DARK_COL)
	_text("%-7d" % (State.money + total if selling else State.money - total), Vector2(360, 443), 16)
	# 确定 / 取消 (0x45f017): ACT 9020 qq8 / qq9, 选中叠 qq10 / qq11, 底栏提示
	for k in 2:
		_img(UI % ([9, 11][k]), Vector2(445 + 55 * k, 442))
	if _state == BUTTONS or _btn_hover:
		_img(UI % ([8, 10][_btn]), Vector2(445 + 55 * _btn, 442))
		_text(["确定", "取消"][_btn], Vector2(60, 569), 16, CREAM)
	# 说明
	if _sel < list.size() and _state >= ROWS_EDIT:
		var rows := MainMenu.note_rows(Battle.obj(int(list[_sel])))
		for i in rows.size():
			_text(rows[i][0], Vector2(74, 481 + 25 * i), 16, rows[i][1])
		_draw_cards(int(list[_sel]))
	if not _ask.is_empty():
		Dialog.draw_tip_layout(_c, _ask, int(_ask.sel))
	elif _msg_t > 0:
		Dialog.draw_tip_layout(_c, Dialog.tip_layout(_msg, _msg_at))


## 右侧队员卡: 装备类商品显示每个能装备的队员换上后的攻防变化
func _draw_cards(id: int) -> void:
	var r := Battle.obj(id)
	var sub := int(r.get("sub", 0))
	if not SLOT_OF_SUB.has(sub):
		return
	var y := 60.0
	for m in [1, 2, 3]:
		if not State.test_flag(m):
			continue
		_img(UI % int(MEMBER_CARD[m]), Vector2(606, y))
		if int(r.get("users", 7)) & (1 << (m - 1)):
			var eq: Array = State.equip.get(m, [])
			var slot: int = SLOT_OF_SUB[sub]
			var old := Battle.obj(int(eq[slot]) if eq.size() > slot else 0)
			var dy := 0
			for k in [["攻", "atk"], ["防", "def"]]:
				var dv := int(r.get(k[1], 0)) - int(old.get(k[1], 0))
				if dv != 0:
					_text("%s%s" % [k[0], ("+%d" % dv) if dv > 0 else ("-%d" % -dv)], Vector2(700, y + 90 + dy), 14,
						Color8(40, 120, 40) if dv > 0 else GREY_COL)
					dy += 18
		else:
			_text("不能装备", Vector2(690, y + 100), 14, GREY_COL)
		y += 140


func _say(s: String, at := Vector2(320, 200), secs := 1.0) -> void:
	_msg = s
	_msg_at = at
	_msg_t = secs


## 弹框: box 不空时是固定框 0x465467 (文字从 box + (24, 24) 起), 否则是单行提示框 0x466f7d(320, 200)
func _open_ask(text: String, box := Rect2()) -> void:
	var L := Dialog.tip_layout(text, Vector2(320, 200))
	if box.has_area():
		var d: Vector2 = box.position + Vector2(24, 24) - L.box.position - Vector2(20, 16)
		L.box = box
		L.buttons = L.buttons.map(func(r): return Rect2(r.position + d, r.size))
		L.hits = L.hits.map(func(r): return Rect2(r.position + d, r.size))
		for g in L.glyphs:
			g[1] += d
	L.sel = 0
	_ask = L


func _clear_cart() -> void:
	_cart.clear()


func _enter_rows() -> void:
	if _list().is_empty():
		return
	_clear_cart()
	_state = ROWS_EDIT


func _unhandled_input(e: InputEvent) -> void:
	get_viewport().set_input_as_handled()
	if not _ask.is_empty():
		_ask_input(e)
		return
	if e is InputEventMouseButton and e.pressed:
		_mouse(e)
		return
	if not (e is InputEventKey and e.pressed):
		return
	var cancel: bool = e.keycode in [KEY_ESCAPE, KEY_CTRL]
	var ok: bool = e.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]
	match _state:
		BROWSE:
			if e.keycode == KEY_LEFT and not e.echo:
				_set_tab(maxi(_tab - 1, 0))
			elif e.keycode == KEY_RIGHT and not e.echo:
				_set_tab(mini(_tab + 1, TABS.size() - 1))
			elif ok:
				_enter_rows()
			elif cancel:
				_close()
		ROWS_EDIT:
			if e.keycode == KEY_DOWN or e.keycode == KEY_UP:
				var n := _list().size()
				_sel = clampi(_sel + (1 if e.keycode == KEY_DOWN else -1), 0, maxi(n - 1, 0))
				_top = clampi(_top, _sel - ROWS + 1, _sel)
				Game.play_sound(0x201)
			elif e.keycode == KEY_LEFT:
				_step(-1)
			elif e.keycode == KEY_RIGHT:
				_step(1)
			elif ok:
				_state = BUTTONS
				_btn = 0
				Game.warp_mouse(Vector2(465, 447))
			elif cancel:
				_back_to_browse()
		BUTTONS:
			if e.keycode == KEY_LEFT and not e.echo:
				_btn = 0
			elif e.keycode == KEY_RIGHT and not e.echo:
				_btn = 1
			elif ok:
				_press_button()
			elif cancel:
				Game.play_sound(0x202)
				_state = ROWS_EDIT


func _mouse(e: InputEventMouseButton) -> void:
	if e.button_index == MOUSE_BUTTON_RIGHT:
		match _state:
			BROWSE:
				_close()
			ROWS_EDIT:
				_back_to_browse()
			BUTTONS:
				Game.play_sound(0x202)
				_state = ROWS_EDIT
		return
	var list := _list()
	if e.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:   # 滚动条 0x46659d
		_top = clampi(_top + (1 if e.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1), 0, maxi(list.size() - ROWS, 0))
		return
	if e.button_index != MOUSE_BUTTON_LEFT:
		return
	var m := _c.get_local_mouse_position()
	if _x_hover:
		left = true
		_close()
		return
	for k in TABS.size():   # 0x45d76d
		if Rect2(150 + 30 * k, 4, 30, 32).has_point(m):
			_state = BROWSE
			if k == _tab:
				_enter_rows()
			else:
				_set_tab(k)
			return
	if _btn_hover:
		_press_button()
		return
	var row := int((m.y - 80) / 25)
	if m.y < 80 or row >= ROWS or _top + row >= list.size():
		return
	if _state == ROWS_EDIT and _top + row == _sel:
		if m.x >= 420 and m.x < 440:
			_hold = 1
		elif m.x >= 440 and m.x < 460:
			_hold = 2
		if _hold:
			_hold_t = -3.0 / 35.0
			_step(1 if _hold == 2 else -1)
			return
	if m.x >= 180 and m.x < 560:
		_sel = _top + row
		Game.play_sound(0x201)
		if _state == BROWSE:
			_enter_rows()
			_sel = _top + row


## 改选中行的数量 (0x45dfab)
func _step(d: int) -> void:
	var list := _list()
	if _sel >= list.size():
		return
	var id: int = list[_sel]
	var n := int(_cart.get(id, 0))
	var have := int(State.items.get(id, 0))
	Game.play_sound(0x201)
	if d < 0:
		_flash = 1
		n = maxi(n - 1, 0)
	elif selling:
		_flash = 2
		n = mini(n + 1, have)
	elif price(id) + _total() > State.money:
		Game.play_sound(0x20e)
		_say("金钱不够!!")
		_hold = 0
		return
	else:
		_flash = 2
		n = n + 1 if n + 1 + have <= 99 else n
	_flash_n = 0
	if n > 0:
		_cart[id] = n
	else:
		_cart.erase(id)


func _back_to_browse() -> void:
	Game.play_sound(0x202)
	_clear_cart()
	_state = BROWSE
	_sel = 0
	_top = 0
	Game.warp_mouse(Vector2(160, 14))


## 确定 / 取消按钮 (0x45dccd)
func _press_button() -> void:
	if _btn == 1:
		Game.play_sound(0x1ff)
		_clear_cart()
		_state = ROWS_EDIT
		return
	if _total() == 0 and not selling:
		Game.play_sound(0x20e)
		_state = BUTTONS
		return
	_state = ASK
	Game.play_sound(0x1fe)
	_open_ask(("确定要卖掉吗？" if selling else "确定要购买吗？") + "  %B确定. / %B取消.", Rect2(160, 220, 360, 64))


## 弹框输入 (0x465656): 方向键换项, 鼠标进按钮换项, 左键 / 确认键回答; 取消键当「取消」
func _ask_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_RIGHT:
			_answer(-1)
		elif e.button_index == MOUSE_BUTTON_LEFT:
			var m := _c.get_local_mouse_position()
			for k in (_ask.hits as Array).size():
				if (_ask.hits[k] as Rect2).has_point(m):
					_answer(k)
					return
		return
	if not (e is InputEventKey and e.pressed and not e.echo):
		return
	match e.keycode:
		KEY_LEFT, KEY_UP:
			_ask.sel = maxi(int(_ask.sel) - 1, 0)
			Game.play_sound(0x201)
		KEY_RIGHT, KEY_DOWN:
			_ask.sel = mini(int(_ask.sel) + 1, (_ask.buttons as Array).size() - 1)
			Game.play_sound(0x201)
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			_answer(int(_ask.sel))
		KEY_ESCAPE, KEY_CTRL:
			_answer(-1)


func _answer(k: int) -> void:
	_ask = {}
	if _state == ASK2:
		_state = ROWS_EDIT
		if k == 0:
			_open_equip()
		return
	if k != 0:
		Game.play_sound(0x1ff if k > 0 else 0x202)
		_clear_cart()
		_state = ROWS_EDIT
		return
	_state = ROWS_EDIT
	if selling:
		_do_sell()
	else:
		_do_buy()
	_clear_cart()
	_sel = mini(_sel, maxi(_list().size() - 1, 0))
	_top = clampi(_top, 0, maxi(_list().size() - ROWS, 0))


func _do_buy() -> void:
	var total := _total()
	if total <= 0:
		Game.play_sound(0x20e)
		return
	Game.play_sound(0x207)
	for id in _cart:
		State.give_item(id, int(_cart[id]))
	State.money -= total
	if int(TABS[_tab]) >= 204:   # 0x45d964: 装备类
		_state = ASK2
		_open_ask("要马上装备吗? %B确定./%B取消.")


func _do_sell() -> void:
	var gain := 0
	var bad := ""
	for id in _cart:
		if not _sellable(id):
			bad = str(Battle.obj(id).get("name", ""))
			continue
		var n := mini(int(_cart[id]), int(State.items.get(id, 0)))
		State.give_item(id, -n)
		gain += price(id) * n
	State.money += gain
	if gain:
		Game.play_sound(0x207)
	if bad != "":
		Game.play_sound(Game.SFX_UI_ERROR)
		_say("【%s】不可贩卖!!" % bad, Vector2(400, 208), 1.4)


## 0x47e45a + 0x4801e6: 关掉后回到商店
func _open_equip() -> void:
	var f := get_parent()
	var m := MainMenu.new()
	m.name = "MainMenu"
	m.field = f
	f.add_child(m)
	m._open_page(1)
	set_process_unhandled_input(false)
	await m.closed
	set_process_unhandled_input(true)


func _set_tab(k: int) -> void:
	if k == _tab:
		return
	_tab = k
	_sel = 0
	_top = 0
	Game.play_sound(0x201)


func _close() -> void:
	Game.play_sound(514)
	closed.emit()
	queue_free()
