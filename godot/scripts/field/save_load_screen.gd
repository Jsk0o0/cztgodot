class_name SaveLoadScreen
extends CanvasLayer
## 存档 / 读档画面 (0x474f9e 存 / 0x475e78 读, 绘制共用 0x473f57; 逆向笔记 re/verify_save.md §2)
## 100 个档位 (00–99), 一屏 3 个, 右侧滚动条; 主菜单系统页、存档点 (op 0xcb)、标题「读取」共用
## 关闭时发 closed(loaded): loaded = 读档成功, 调用方切换到场景

signal closed(loaded: bool)

const TOTAL := 100
const BG := "ui/all_sys/0087_000_主介面存档/009.png"
const SLOT := "ui/all_sys/0087_000_主介面存档/000.png"
const TRACK := "ui/all_sys/0087_000_主介面存档/001.png"
const BAR_TOP := "ui/all_sys/0068_000_主介面底图元件/000.png"
const BAR_BOTTOM := "ui/all_sys/0068_000_主介面底图元件/001.png"
const ICON := "ui/all_sys/0068_000_主介面底图元件/%03d.png"
const ARROW := "ui/all_sys/0081_000_主介面物品/%03d.png"
const CLOSE := "ui/all_sys/0171_000_离开叉叉/%03d.png"
const HEAD := "ui/all_sys/0105_000_人物图像/%03d.png"
const COL := Color8(117, 76, 36)     # 调色板 15
const COL2 := Color8(89, 63, 32)     # 调色板 14 (「级」)

## 存档和读档各记各的 top / cursor (0xbd06fc.. / 0xbd0704..), 一次运行内保持
static var _pos := {"save": [0, 0], "load": [0, 0]}
static var _first := true

var mode := "save"                   # "save" / "load"
var from_title := false
var thumb: Image                     # 存档用的缩略图 (160×120)
var field: Node                      # 有的话用它的调试鼠标位置

var _c: Control
var _tex := {}
var top := 0
var cursor := 0
var _info: Array = [{}, {}, {}]      # 可见 3 档的头信息
var _thumbs: Array = [null, null, null]
var _dim := [150.0, 150.0, 150.0]    # 暗化层 alpha (选中的 −10/帧 到 0, 其余 +10/帧 到 150)
var _arrow_hi := 0                   # 滚动那一帧高亮箭头: −1 上 / 1 下
var _confirm := {}                   # 确认框: {text, opts, sel, rect, cb}
var _done_t := -1.0                  # 「存档完毕!!」剩余显示时间
var _close_t := -1.0                 # 覆盖存档后 30 帧自动关闭
var _last_click := -100.0
var _last_click_k := -1
var _busy := false
var saved := false                   # 这次确实写了档 (神秘果据此扣数量)


func _ready() -> void:
	layer = 20
	_c = Control.new()
	_c.size = Vector2(800, 600)
	# 鼠标直接在本层 (layer 20, 最上面) 接: 以前设 IGNORE 交给 _unhandled_input, 但从标题打开时下面的标题控件会先把点击吞掉,
	# 叉、滚动条、双击都没反应。STOP + gui_input 就不依赖下层放行
	_c.mouse_filter = Control.MOUSE_FILTER_STOP
	_c.gui_input.connect(_on_gui_input)
	_c.draw.connect(_draw)
	add_child(_c)
	var p: Array = _pos[mode]
	top = p[0]
	cursor = p[1]
	# 本次运行第一次从标题打开: 滚到最新的存档 (0x4761f7; 原版只扫到 98 号, 这里扫全部)
	if _first and from_title:
		var best := ""
		for n in TOTAL:
			var h := State.slot_header(n)
			var at := str(h.get("saved_at", ""))
			if at != "" and at > best:
				best = at
				top = mini(n, TOTAL - 3)
				cursor = n - top
	_first = false
	_reload()


func tex(p: String) -> Texture2D:
	if not _tex.has(p):
		_tex[p] = Game.load_texture(p)
	return _tex[p]


func _mouse() -> Vector2:
	if field and field.get("_dbg_mouse_on"):
		return field._dbg_mouse_ui
	return _c.get_local_mouse_position()


func _reload() -> void:
	for k in 3:
		_info[k] = State.slot_header(top + k)
		_thumbs[k] = null
		if not _info[k].is_empty():
			var img := State.slot_thumb(top + k)
			if img:
				_thumbs[k] = ImageTexture.create_from_image(img)


func _close(loaded := false) -> void:
	if _busy:
		return
	if OS.get_cmdline_user_args().has("--trace-ui"):
		print("SAVE_UI close loaded=%s" % str(loaded))
	_busy = true
	_pos[mode] = [top, cursor]
	closed.emit(loaded)
	queue_free()


func _process(delta: float) -> void:
	if Game.cursor:
		Game.cursor.set_state(9001, 9)   # 存读档 (0x473f57): 普通指针
		Game.cursor.fps = GameCursor.FPS_FIELD
	for k in 3:
		_dim[k] = clampf(_dim[k] + (-600.0 if k == cursor else 600.0) * delta, 0.0, 150.0)
	if _done_t > 0:
		_done_t -= delta
		if _done_t <= 0:
			_close()
	if _close_t > 0:
		_close_t -= delta
		if _close_t <= 0:
			_close()
	if not _confirm.is_empty():
		var m := _mouse()
		for i in _confirm.opts.size():
			if _opt_rect(i).has_point(m) and _confirm.sel != i:
				_confirm.sel = i
				Game.play_sound(Game.SFX_UI_SELECT)
	_c.queue_redraw()


# ---------------- 绘制 (0x473f57) ----------------

func _img(p: String, at: Vector2) -> void:
	var t := tex(p)
	if t:
		_c.draw_texture(t, at)


## 原版文字: 16px, 在 x 和 x+1 各画一遍 (伪粗体); at = 字格左上角
## 按字格排: 半角占字号一半宽, 全角占一个字号宽 (格式串靠空格对齐, 如「%3d:%02d」)
func _text(s: String, at: Vector2, size := 16, col := COL) -> void:
	var f: Font = Game.font_body
	var x := at.x
	var base_y := at.y + size * 0.88
	for ch in s:
		var half := ch.unicode_at(0) < 0x80
		var cell := size * 0.5 + Game.HALF_GAP if half else float(size)
		if ch != " ":
			var fs := Game.half_size(size, 1) if half else size   # 半角字缩一点 (伪粗体多 1 像素), 数字之间留空
			var w := f.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var cx := x + (cell - w) * 0.5
			_c.draw_string(f, Vector2(cx, base_y), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
			_c.draw_string(f, Vector2(cx + 1, base_y), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		x += cell


func _draw() -> void:
	_c.draw_rect(Rect2(0, 0, 800, 600), Color8(0x1a, 0x1a, 0x1a))
	_img(BG, Vector2.ZERO)
	_img(BAR_TOP, Vector2(0, 5))
	_img(BAR_BOTTOM, Vector2(0, 560))
	_img(CLOSE % (1 if Rect2(740, 4, 30, 28).has_point(_mouse()) else 0), Vector2(740, 4))
	_text("存档" if mode == "save" else "读档", Vector2(119, 8), 20, Color8(117, 76, 36))
	for k in 3:
		var y := 126 + 140 * k
		_img(SLOT, Vector2(85, y - 26))
		_text("%02d" % (top + k), Vector2(110, y + 86))
		var h: Dictionary = _info[k]
		if h.is_empty():
			continue
		var party: Array = h.get("party", [])
		var lv: Array = h.get("levels", [1, 1, 1])
		for m in 3:
			if m < party.size() and int(party[m]) > 0:
				_img(HEAD % m, Vector2(229 + 85 * m, y - 23))
				_text("%2d" % int(lv[m]), Vector2(249 + 80 * m, y + 86))
				_text("级", Vector2(269 + 80 * m, y + 86), 16, COL2)
		var res := [h.get("money", 0), h.get("metal", 0), h.get("wood", 0), h.get("coal", 0), h.get("tech", 0)]
		var iy := [-20, 1, 21, 42, 65]
		var ty := [-21, 0, 22, 44, 66]
		for i in 5:
			_img(ICON % (25 + i), Vector2(550, y + iy[i]))
			_text("%d" % int(res[i]), Vector2(575, y + ty[i]))
		var d: Array = h.get("date", [0, 0, 0])
		_text("%4d/%02d/%02d" % [int(d[0]), int(d[1]), int(d[2])], Vector2(500, y + 86))
		var s := int(h.get("play_seconds", 0))
		_text("%3d:%02d" % [s / 3600, s / 60 % 60], Vector2(590, y + 86))
		_text(str(h.get("map_name", "")), Vector2(135, y + 86))
	for k in 3:
		if _thumbs[k]:
			_c.draw_texture_rect(_thumbs[k], Rect2(110, 117 + 140 * k, 110, 90), false)
	for k in 3:
		_c.draw_rect(Rect2(85, 100 + 140 * k, 574, 132), Color(0, 0, 0, _dim[k] / 255.0))
	# 滚动条 (0x466a29)
	_img(TRACK, Vector2(665, 100))
	_c.draw_rect(Rect2(674, 147 + int(322.0 * top / TOTAL), 11, int(322.0 * 3 / TOTAL)), Color8(255, 253, 227, 200))
	_img(ARROW % (5 if _arrow_hi < 0 else 3), Vector2(670, 124))
	_img(ARROW % (6 if _arrow_hi > 0 else 4), Vector2(670, 473))
	_arrow_hi = 0
	if _done_t > 0:
		_box(Rect2(224, 70 + 130 * cursor, 192, 64), "存档完毕!!")
	if not _confirm.is_empty():
		_box(_confirm.rect, str(_confirm.text))
		var bar := tex(Dialog.BAR)
		if bar:
			_c.draw_texture_rect(bar, _opt_rect(_confirm.sel), false, Color(1, 1, 1, 120 / 255.0))
		for i in _confirm.opts.size():
			var r := _opt_rect(i)
			_shadow_text(str(_confirm.opts[i]), r.position + Vector2(4, 21))


func _box(r: Rect2, t: String) -> void:
	Dialog.draw_nine(_c, tex(Dialog.SKIN), r)
	_shadow_text(t, r.position + Vector2(15, 27))


func _shadow_text(s: String, at: Vector2) -> void:
	var f: Font = Game.font_body
	_c.draw_string(f, at + Vector2(1, 1), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.BLACK)
	_c.draw_string(f, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)


## 确认框里的按钮: 和问句在同一行, 中间隔一个「/」(原版字面写的)
func _opt_rect(i: int) -> Rect2:
	var r: Rect2 = _confirm.rect
	var x := r.position.x + 15 + 20.0 * str(_confirm.text).length() + 8
	for j in i:
		x += 20.0 * str(_confirm.opts[j]).length() + 28
	return Rect2(x - 4, r.position.y + 6, 20.0 * str(_confirm.opts[i]).length() + 8, 28)


# ---------------- 输入 (0x4750de / 0x475fbe; 滚动条 0x46659d) ----------------

func _on_gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		_c.accept_event()
		_handle(e)


func _unhandled_input(e: InputEvent) -> void:
	get_viewport().set_input_as_handled()
	if e is InputEventMouseButton:
		return   # 鼠标按键走 _on_gui_input
	_handle(e)


func _handle(e: InputEvent) -> void:
	if _busy or _close_t > 0:
		return
	if _done_t > 0:
		if (e is InputEventMouseButton and e.pressed) or (e is InputEventKey and e.pressed):
			_done_t = 0.001   # 点击提前关闭
		return
	if not _confirm.is_empty():
		_confirm_input(e)
		return
	if e is InputEventMouseButton and e.pressed:
		_mouse_input(e as InputEventMouseButton)
	elif e is InputEventKey and e.pressed:
		_key_input((e as InputEventKey).keycode)


func _key_input(k: int) -> void:
	match k:
		KEY_ESCAPE, KEY_CTRL:
			Game.play_sound(514)
			_close()
		KEY_UP:
			_move(-1)
		KEY_DOWN:
			_move(1)
		KEY_PAGEUP:
			_page(-1)
		KEY_PAGEDOWN:
			_page(1)
		KEY_HOME:
			Game.play_sound(Game.SFX_UI_PAGE)
			top = 0
			cursor = 0
			_reload()
		KEY_END:
			Game.play_sound(Game.SFX_UI_PAGE)
			top = TOTAL - 3
			cursor = 2
			_reload()
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			_confirm_slot()


func _mouse_input(e: InputEventMouseButton) -> void:
	var m := _mouse()
	if OS.get_cmdline_user_args().has("--trace-ui"):
		print("SAVE_UI click %s btn=%d dbl=%s top=%d cursor=%d" % [str(m), e.button_index, str(e.double_click), top, cursor])
	match e.button_index:
		MOUSE_BUTTON_RIGHT:
			Game.play_sound(514)
			_close()
		MOUSE_BUTTON_WHEEL_UP:
			_page(-1)
		MOUSE_BUTTON_WHEEL_DOWN:
			_page(1)
		MOUSE_BUTTON_LEFT:
			if Rect2(740, 4, 30, 28).has_point(m):
				Game.play_sound(514)
				_close()
			elif Rect2(672, 122, 18, 20).has_point(m):
				_move(-1, true)
			elif Rect2(672, 471, 18, 21).has_point(m):
				_move(1, true)
			elif Rect2(670, 135, 15, 340).has_point(m):
				# 点轨道: 滑块上方翻上一页, 下方翻下一页
				Game.play_sound(Game.SFX_UI_PAGE)
				var knob := 147 + int(322.0 * top / TOTAL)
				top = clampi(top + (-3 if m.y < knob else 3), 0, TOTAL - 3)
				_reload()
			elif Rect2(85, 100, 575, 410).has_point(m):
				# 单击只选中, 双击才确认 (0x476ad8)
				var k := clampi(int((m.y - 92) / 140), 0, 2)
				var now := Time.get_ticks_msec() / 1000.0
				var dbl := e.double_click or (k == _last_click_k and now - _last_click < 0.4)
				_last_click = now
				_last_click_k = k
				cursor = k
				if dbl:
					_last_click_k = -1
					_confirm_slot()


## ↑↓: 光标移动, 到边时滚动列表, 不循环 (播 513)
func _move(d: int, click := false) -> void:
	Game.play_sound(Game.SFX_UI_SELECT)
	_arrow_hi = d
	var old_top := top
	cursor += d
	if cursor < 0:
		cursor = 0
		top = maxi(top - 1, 0)
	elif cursor > 2:
		cursor = 2
		top = mini(top + 1, TOTAL - 3)
	if top != old_top or click:
		_reload()


## PageUp / PageDown / 滚轮: 先跳到屏首 / 屏尾, 已在屏首 / 屏尾再翻一页 (播 530)
func _page(d: int) -> void:
	Game.play_sound(Game.SFX_UI_PAGE)
	if d < 0:
		if cursor != 0:
			cursor = 0
		else:
			top = maxi(top - 3, 0)
	else:
		if cursor != 2:
			cursor = 2
		else:
			top = mini(top + 3, TOTAL - 3)
	_reload()


func _confirm_slot() -> void:
	var n := top + cursor
	var exists: bool = not (_info[cursor] as Dictionary).is_empty()
	if mode == "load":
		# 空档位什么都不做; 有效档位当帧读档, 不播音效、不淡出 (0x4761be)
		if exists and State.load_slot(n):
			_close(true)
		return
	if exists:
		# 覆盖确认 (0x475348: 显示前 [0x9f2e90] = 1, 之后不复位 → 取消键只播 0x202)
		Game.cancel_lock = 1
		_confirm = {"text": "确定要覆盖吗?", "opts": ["确定.", "放弃."], "sel": 0,
			"rect": Rect2(225, 170 + 140 * cursor, 320, 64)}
		return
	_write(n)
	_done_t = 1.0   # 「存档完毕!!」1 秒或点击后关闭, 关闭后整个画面跟着关


func _confirm_input(e: InputEvent) -> void:
	var pick := -1
	if e is InputEventKey and e.pressed:
		match (e as InputEventKey).keycode:
			KEY_LEFT, KEY_UP:   # 0x465656: 不循环, 到头也播 0x201
				_confirm.sel = maxi(int(_confirm.sel) - 1, 0)
				Game.play_sound(0x201)
			KEY_RIGHT, KEY_DOWN:
				_confirm.sel = mini(int(_confirm.sel) + 1, _confirm.opts.size() - 1)
				Game.play_sound(0x201)
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				pick = _confirm.sel
			KEY_ESCAPE, KEY_CTRL:
				Game.play_sound(0x202)   # 标志为 1, 取消键没有别的效果
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		for i in _confirm.opts.size():
			if _opt_rect(i).has_point(_mouse()):
				pick = i
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_RIGHT:
		Game.play_sound(0x202)
	if pick < 0:
		return
	pick = Game.take_answer(pick)   # 0x46559d: 有「已取消」标记时当成 −1 (放弃)
	if pick < 0:
		pick = 1
	Game.play_sound(Game.SFX_UI_OK)
	_confirm = {}
	if pick == 0:
		# 覆盖: 写档 → 刷新列表 → 30 帧后自动关闭, 不显示「存档完毕」
		_write(top + cursor)
		_close_t = 30.0 / 35.0


func _write(n: int) -> void:
	saved = true
	if field and field.has_method("save_game"):
		field.save_game(n, thumb)
	else:
		State.save_slot(n, thumb)
	_reload()
