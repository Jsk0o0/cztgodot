class_name WorkshopScreen
extends CanvasLayer
## 创意工坊 (标题画面「工坊」进入; 非原版功能, 布局按 Figma 稿「游戏内 · 创意工坊」, 800×600 逻辑坐标)。
## 素材全用游戏自己的 (同存档画面 0x473f57): 竹纹底图 / 上下横条 / 离开叉叉 / 存档槽底图当列表卡片 / 选择存档外框 /
## 滚动条与箭头 / 物品页纸张当详情底 / 光棒 (选中项、主按钮) / 九宫格对话框 (确认框、提示)
## 只有本地工坊 (用户要求去掉在线工坊): Mods.installed 列表 (启用 / 停用、加载顺序、删除); mod 由玩家自己把 .pod 放进 mod 文件夹,
## 点「刷新」(R / F5) 重新扫描文件夹, 不用重启游戏; 新放进来的 mod 默认不启用 (Mods._enabled_ids)。
## 改动写进设置, 关闭时 Mods.reload(), 之后开始 / 读取的游戏用新结果。
## 按键: ↑↓ 选择, Enter 启用 / 停用, Shift+↑↓ 调整顺序, Delete 删除 (要确认), R / F5 刷新, Esc / 右键 返回

signal closed

const INK := Color8(74, 46, 23)
const INK2 := Color8(138, 96, 56)
const INK3 := Color8(155, 107, 60)
const ACCENT := Color8(200, 100, 30)
const ACCENT_D := Color8(164, 79, 18)
const PAPER := Color8(255, 246, 228)
const LINE := Color8(196, 154, 102)
const OK_C := Color8(47, 107, 58)
const BAD_C := Color8(155, 47, 31)
const LIST_X := 16.0
const LIST_Y := 64.0
const CARD_W := 418.0
const CARD_H := 96.0
const CARD_GAP := 8.0
const ROWS := 4
const PANEL := Rect2(470, 64, 314, 488)
const BG := "ui/all_sys/0087_000_主介面存档/009.png"          # 竹纹底图 800×600
const SLOT := "ui/all_sys/0087_000_主介面存档/000.png"        # 存档槽 576×133
const TRACK := "ui/all_sys/0087_000_主介面存档/001.png"       # 滚动条槽 29×414
const BAR_TOP := "ui/all_sys/0068_000_主介面底图元件/000.png"
const BAR_BOTTOM := "ui/all_sys/0068_000_主介面底图元件/001.png"
const CLOSE := "ui/all_sys/0171_000_离开叉叉/%03d.png"        # 0 平常 / 1 指到
const FRAME_SEL := "ui/all_sys/0094_001_选择存档外框/000.png" # 563×126
const SHEET := "ui/all_sys/0081_000_主介面物品/000.png"       # 物品页纸张 356×348
const ARROW := "ui/all_sys/0081_000_主介面物品/%03d.png"      # 3 / 4 上下, 5 / 6 按下
const COL := Color8(117, 76, 36)     # 游戏菜单文字 (调色板 15)
const EMPTY_AREA := Rect2(16, 64, 768, 488)
const EMPTY_BTN := Rect2(310, 64 + 24 + 25 * 11 + 1, 180, 20)   # 空状态按钮: 纸张第 11 行
const REFRESH_BTN := Rect2(626, 8, 100, 26)   # 顶栏右侧, 离开叉叉左边

var _c: Control
var sel := 0
var top := 0
var _confirm := false        # 删除确认框
var _confirm_sel := 1        # 0 删除 / 1 取消 (默认停在取消)
var _toast := ""
var _toast_t := 0.0
var _previews := {}          # mod id → Texture2D
var _dirty := false          # 改过启用 / 顺序 / 删除 → 关闭时重新加载
var _tex := {}


func tex(p: String) -> Texture2D:
	if not _tex.has(p):
		_tex[p] = Game.load_texture(p)
	return _tex[p]


func _img(p: String, r: Rect2, mod := Color.WHITE) -> void:
	var t := tex(p)
	if t:
		_c.draw_texture_rect(t, r, false, mod)


func _mouse() -> Vector2:
	return _c.get_local_mouse_position()


## 列表卡片: 存档槽底图; 没选中的压暗 (同存档画面), 选中的套「选择存档外框」
func _card_bg(r: Rect2, selected: bool) -> void:
	_img(SLOT, r)
	if selected:
		_img(FRAME_SEL, Rect2(r.position - Vector2(3, 3), r.size + Vector2(6, 6)))
	else:
		_c.draw_rect(r, Color(0, 0, 0, 0.22))


## 详情 / 空状态底: 物品页纸张。原图 356×348, 横线每 25 像素一条 (第 21–24 行起): 不纵向拉伸,
## 顶部 24 像素 + 中段 300 像素 (12 行) 重复铺 + 底部 24 像素; 只横向缩放到目标宽。文字按 SHEET_ROW 行距写在线之间
const SHEET_ROW := 25.0


func _sheet(r: Rect2) -> void:
	var t := tex(SHEET)
	if t == null:
		return
	var sx := r.size.x / 356.0
	_c.draw_texture_rect_region(t, Rect2(r.position, Vector2(r.size.x, 24)), Rect2(0, 0, 356, 24))
	var y := 24.0
	while y < r.size.y - 24:
		var h := minf(300.0, r.size.y - 24 - y)
		_c.draw_texture_rect_region(t, Rect2(r.position + Vector2(0, y), Vector2(r.size.x, h)), Rect2(0, 24, 356, h))
		y += h
	_c.draw_texture_rect_region(t, Rect2(r.position + Vector2(0, r.size.y - 24), Vector2(r.size.x, 24)), Rect2(0, 324, 356, 24))


## 纸张上第 k 行文字的 y (写在两条横线之间)
func _row(r: Rect2, k: int) -> float:
	return r.position.y + 24 + SHEET_ROW * k + 2


## 按钮: 主按钮 = 光棒; 次按钮 = 半透明光棒; 不可用 = 压暗 (光棒同对话框选项, ACT 9014)
func _button(r: Rect2, text: String, enabled: bool, primary := false, danger := false) -> void:
	var hover := r.has_point(_mouse()) and enabled
	var a := (1.0 if primary else 0.45) * (1.0 if enabled else 0.3) * (1.15 if hover else 1.0)
	var bt := tex(Dialog.BAR)
	if bt:   # 光棒四周渐变到黑 (本来叠在深色对话框上用), 放在纸上只取中间亮黄的部分
		_c.draw_texture_rect_region(bt, r, Rect2(6, 5, 52, 6), Color(1, 1, 1, clampf(a, 0, 1)))
	_c.draw_rect(r, Color(0.46, 0.3, 0.14, 0.55 if enabled else 0.25), false, 1.0)
	var col := (BAD_C if danger else COL) if enabled else Color(0.46, 0.3, 0.14, 0.4)
	_t(text, r.position + Vector2(0, (r.size.y - 14) * 0.5 - 1), 14, col, primary and enabled, r.size.x, HORIZONTAL_ALIGNMENT_CENTER)


## 滚动条 (同存档画面: 槽 + 上下箭头 + 浅色滑块)
func _scroll(total: int) -> void:
	if total <= ROWS:
		return
	var x := LIST_X + CARD_W + 4
	_img(TRACK, Rect2(x, LIST_Y, 29, 414))
	var span := 322.0
	_c.draw_rect(Rect2(x + 9, LIST_Y + 47 + int(span * top / total), 11, maxi(8, int(span * ROWS / total))), Color8(255, 253, 227, 200))
	_img(ARROW % 3, Rect2(x + 5, LIST_Y + 24, 18, 18))
	_img(ARROW % 4, Rect2(x + 5, LIST_Y + 373, 18, 18))


func _ready() -> void:
	layer = 20
	_c = Control.new()
	_c.size = Vector2(800, 600)
	_c.mouse_filter = Control.MOUSE_FILTER_STOP
	_c.draw.connect(_draw)
	_c.gui_input.connect(_on_gui)
	add_child(_c)
	_fit()
	get_viewport().size_changed.connect(_fit)


func _fit() -> void:
	var vs := get_viewport().get_visible_rect().size
	var s := minf(vs.x / 800.0, vs.y / 600.0)
	_c.scale = Vector2(s, s)
	_c.position = (vs - Vector2(800, 600) * s) * 0.5


func _list() -> Array:
	return Mods.installed


func _cur() -> Dictionary:
	var l := _list()
	return l[sel] if sel >= 0 and sel < l.size() else {}


func _process(delta: float) -> void:
	if _toast_t > 0:
		_toast_t -= delta
	_c.queue_redraw()


func _say(s: String) -> void:
	_toast = s
	_toast_t = 2.0


# ---------------- 操作 ----------------

func _toggle() -> void:
	var m := _cur()
	if m.is_empty():
		return
	if m.status == "error":
		Game.play_sound(Game.SFX_UI_ERROR)
		_say("这个 mod 无法加载：%s" % m.error)
		return
	if m.dev:
		Game.play_sound(Game.SFX_UI_ERROR)
		_say("开发模式加载的 mod 总是启用")
		return
	Mods.set_enabled(m.id, not m.enabled)
	m.status = "pending" if m.enabled else "disabled"
	_dirty = true
	Game.play_sound(Game.SFX_UI_OK)
	_say(("已启用「%s」" if m.enabled else "已停用「%s」") % m.name)


func _move(d: int) -> void:
	var l := _list()
	var j := sel + d
	if sel < 0 or j < 0 or j >= l.size():
		Game.play_sound(Game.SFX_UI_ERROR)
		return
	var m: Dictionary = l[sel]
	l[sel] = l[j]
	l[j] = m
	sel = j
	Mods.set_order(l.map(func(x): return x.id))
	_dirty = true
	Game.play_sound(Game.SFX_UI_SELECT)
	_keep_visible()


func _ask_delete() -> void:
	var m := _cur()
	if m.is_empty():
		return
	if m.dev:
		Game.play_sound(Game.SFX_UI_ERROR)
		_say("开发模式加载的 mod 不能在这里删除")
		return
	_confirm = true
	_confirm_sel = 1
	Game.play_sound(Game.SFX_UI_OK)


func _do_delete() -> void:
	var m := _cur()
	_confirm = false
	if Mods.uninstall(m.id):
		_dirty = true
		sel = clampi(sel, 0, maxi(_list().size() - 1, 0))
		Game.play_sound(Game.SFX_UI_OK)
		_say("已删除「%s」" % m.name)
	else:
		Game.play_sound(Game.SFX_UI_ERROR)
		_say("删除失败，请检查文件是否被占用")


## 重新扫描 mod 文件夹 (玩家刚放进 / 拿走 .pod 后点), 同时套用之前改过的启用 / 顺序
func _refresh() -> void:
	var cur_id := str(_cur().get("id", ""))
	Mods.reload()
	_dirty = false
	_previews.clear()
	var l := _list()
	sel = 0
	for i in l.size():
		if str(l[i].id) == cur_id:
			sel = i
	sel = clampi(sel, 0, maxi(l.size() - 1, 0))
	_keep_visible()
	Game.play_sound(Game.SFX_UI_OK)
	_say("已刷新：共 %d 个 mod" % l.size())


func _close() -> void:
	Game.play_sound(514)
	if _dirty:
		Mods.reload()
	closed.emit()
	queue_free()


func _keep_visible() -> void:
	top = clampi(top, sel - ROWS + 1, sel)
	top = clampi(top, 0, maxi(_list().size() - ROWS, 0))


# ---------------- 输入 ----------------

func _unhandled_input(e: InputEvent) -> void:
	if not (e is InputEventKey and e.pressed and not e.echo):
		return
	get_viewport().set_input_as_handled()
	var k := (e as InputEventKey).keycode
	if _confirm:
		if k in [KEY_LEFT, KEY_UP]:
			_confirm_sel = 0
			Game.play_sound(0x201)
		elif k in [KEY_RIGHT, KEY_DOWN]:
			_confirm_sel = 1
			Game.play_sound(0x201)
		elif k in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
			if _confirm_sel == 0:
				_do_delete()
			else:
				_confirm = false
				Game.play_sound(514)
		elif k in [KEY_ESCAPE, KEY_CTRL]:
			_confirm = false
			Game.play_sound(514)
		return
	var shift := (e as InputEventKey).shift_pressed
	match k:
		KEY_ESCAPE:
			_close()
		KEY_UP:
			if shift:
				_move(-1)
			elif sel > 0:
				sel -= 1
				Game.play_sound(Game.SFX_UI_SELECT)
				_keep_visible()
		KEY_DOWN:
			if shift:
				_move(1)
			elif sel < _list().size() - 1:
				sel += 1
				Game.play_sound(Game.SFX_UI_SELECT)
				_keep_visible()
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			_toggle()
		KEY_DELETE, KEY_BACKSPACE:
			_ask_delete()
		KEY_R, KEY_F5:
			_refresh()


func _btn_rects() -> Array:
	# 详情面板底部: [主按钮, 上移, 下移, 删除]
	var y := _row(PANEL, 16) - 1   # 按钮落在纸张第 16 行, 高度不超过两条横线之间
	var x := PANEL.position.x + 24
	return [Rect2(x, y, 104, 20), Rect2(x + 110, y, 50, 20), Rect2(x + 166, y, 50, 20), Rect2(x + 222, y, 44, 20)]


func _confirm_rects() -> Array:
	return [Rect2(290, 318, 100, 34), Rect2(410, 318, 100, 34)]


func _on_gui(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed:
		var m: Vector2 = (e as InputEventMouseButton).position
		match (e as InputEventMouseButton).button_index:
			MOUSE_BUTTON_RIGHT:
				if _confirm:
					_confirm = false
				else:
					_close()
			MOUSE_BUTTON_WHEEL_UP:
				top = maxi(top - 1, 0)
			MOUSE_BUTTON_WHEEL_DOWN:
				top = clampi(top + 1, 0, maxi(_list().size() - ROWS, 0))
			MOUSE_BUTTON_LEFT:
				_click(m)


func _click(m: Vector2) -> void:
	if _confirm:
		var r := _confirm_rects()
		if (r[0] as Rect2).has_point(m):
			_do_delete()
		elif (r[1] as Rect2).has_point(m):
			_confirm = false
			Game.play_sound(514)
		return
	if Rect2(740, 4, 30, 30).has_point(m):
		_close()
		return
	if REFRESH_BTN.has_point(m):
		_refresh()
		return
	var l := _list()
	for i in ROWS:
		var k := top + i
		if k < l.size() and _card_rect(i).has_point(m):
			if k == sel:
				_toggle()
			else:
				sel = k
				Game.play_sound(Game.SFX_UI_SELECT)
			return
	if not _cur().is_empty():
		var b := _btn_rects()
		if (b[0] as Rect2).has_point(m):
			_toggle()
		elif (b[1] as Rect2).has_point(m):
			_move(-1)
		elif (b[2] as Rect2).has_point(m):
			_move(1)
		elif (b[3] as Rect2).has_point(m):
			_ask_delete()
	elif _list().is_empty() and EMPTY_BTN.has_point(m):
		_open_folder()


func _open_folder() -> void:
	DirAccess.make_dir_recursive_absolute(Mods.ROOT)
	OS.shell_open(ProjectSettings.globalize_path(Mods.ROOT))
	Game.play_sound(Game.SFX_UI_OK)


# ---------------- 绘制 ----------------

func _card_rect(i: int) -> Rect2:
	return Rect2(LIST_X, LIST_Y + i * (CARD_H + CARD_GAP), CARD_W, CARD_H)


func _t(s: String, at: Vector2, size := 16, col := INK, bold := false, width := -1.0, align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	var f: Font = Game.font_body
	_c.draw_string(f, at + Vector2(0, size * 0.88), s, align, width, size, col)
	if bold:
		_c.draw_string(f, at + Vector2(1, size * 0.88), s, align, width, size, col)


## 自动换行 (按字宽), 返回用掉的高度
func _para(s: String, at: Vector2, width: float, size := 13, col := INK, max_lines := 4, line_h := 0.0) -> float:
	var f: Font = Game.font_body
	var lines: Array = []
	var cur := ""
	for ch in s:
		if f.get_string_size(cur + ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > width:
			lines.append(cur)
			cur = ""
		cur += ch
	if cur != "":
		lines.append(cur)
	if lines.size() > max_lines:
		lines = lines.slice(0, max_lines)
		lines[max_lines - 1] = str(lines[max_lines - 1]).left(-1) + "…"
	var lh := line_h if line_h > 0 else size * 1.6
	for i in lines.size():
		_t(lines[i], at + Vector2(0, i * lh), size, col)
	return lines.size() * lh


func _box(r: Rect2, fill: Color, border: Color, radius := 6.0, bw := 1.0) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = border
	sb.set_border_width_all(int(bw))
	sb.set_corner_radius_all(int(radius))
	_c.draw_style_box(sb, r)


func _badge(at: Vector2, s: String, col: Color, bg: Color) -> float:
	var w := Game.font_body.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 14
	_box(Rect2(at, Vector2(w, 18)), bg, col, 9)
	_t(s, at + Vector2(7, 2), 11, col)
	return w


func _preview(m: Dictionary) -> Texture2D:
	var key := str(m.id)
	if not _previews.has(key):
		var t: Texture2D = null
		var pv: Variant = m.get("preview", PackedByteArray())
		var b: PackedByteArray = pv if pv is PackedByteArray else PackedByteArray()
		if b.size():
			var img := Image.new()
			if img.load_png_from_buffer(b) == OK:
				t = ImageTexture.create_from_image(img)
		_previews[key] = t
	return _previews[key]


func _thumb(r: Rect2, m: Dictionary) -> void:
	var t := _preview(m)
	if t:
		_c.draw_texture_rect(t, r, false)
	else:
		# 没有封面: 按 id 取一个暖色渐变占位
		var h := float(absi(str(m.id).hash()) % 360) / 360.0
		var a := Color.from_hsv(fmod(0.08 + h * 0.5, 1.0), 0.45, 0.92)
		var b := Color.from_hsv(fmod(0.05 + h * 0.5, 1.0), 0.7, 0.6)
		_c.draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]),
			PackedColorArray([a, a.lerp(b, 0.5), b, a.lerp(b, 0.5)]))
	_c.draw_rect(r, Color8(169, 128, 79), false, 1.0)


func _size_text(n: int) -> String:
	if n >= 1048576:
		return "%.1f MB" % (n / 1048576.0)
	return "%d KB" % maxi(1, int(ceil(n / 1024.0)))


func _status_badge(at: Vector2, m: Dictionary) -> float:
	match m.status:
		"error":
			return _badge(at, "⚠ 无法加载 · " + str(m.error), BAD_C, Color8(251, 227, 220))
		"disabled":
			return _badge(at, "○ 未启用", INK2, Color8(246, 234, 210))
		"pending":
			return _badge(at, "● 已启用（重新进入后生效）", OK_C, Color8(230, 242, 223))
	return _badge(at, "● 已启用", OK_C, Color8(230, 242, 223))


func _draw() -> void:
	_c.draw_rect(Rect2(0, 0, 800, 600), Color8(0x1a, 0x1a, 0x1a))
	_img(BG, Rect2(0, 0, 800, 600))
	_img(BAR_TOP, Rect2(0, 5, 800, 34))
	_img(BAR_BOTTOM, Rect2(0, 560, 800, 34))
	_t("创意工坊", Vector2(119, 10), 20, COL, true)
	_t("已安装 %d 个" % Mods.installed.size(), Vector2(300, 12), 16, COL, false, 200, HORIZONTAL_ALIGNMENT_CENTER)
	var rb := tex(Dialog.BAR)   # 刷新按钮: 同原来的页签样式 (光棒中间亮黄的部分), 指到时亮
	if rb:
		_c.draw_texture_rect_region(rb, REFRESH_BTN, Rect2(6, 5, 52, 6), Color(1, 1, 1, 0.9 if REFRESH_BTN.has_point(_mouse()) else 0.35))
	_t("↻ 刷新", REFRESH_BTN.position + Vector2(0, 4), 16, COL, REFRESH_BTN.has_point(_mouse()), REFRESH_BTN.size.x, HORIZONTAL_ALIGNMENT_CENTER)
	_img(CLOSE % (1 if Rect2(740, 4, 30, 30).has_point(_mouse()) else 0), Rect2(740, 4, 30, 30))

	_draw_local()

	# 底部按键提示
	var hints := [["↑↓", "选择"], ["Enter", "启用 / 停用"], ["Shift+↑↓", "调整顺序"], ["Del", "删除"], ["R", "刷新"], ["Esc", "返回"]]
	var x := 40.0
	for h in hints:   # 写在底部横条上 (同存档画面的「存档」字样位置)
		_t(h[0], Vector2(x, 568), 14, ACCENT_D, true)
		x += Game.font_body.get_string_size(h[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 6
		_t(h[1], Vector2(x, 568), 14, COL)
		x += Game.font_body.get_string_size(h[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 18
	if _dirty:
		_t("※ 改动在重新开始或读取游戏后生效", Vector2(LIST_X + 6, 480), 13, Color8(255, 246, 228), true)

	if _toast_t > 0:
		var a := clampf(_toast_t / 0.3, 0.0, 1.0)
		var tw := Game.font_body.get_string_size(_toast, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 32
		var tr := Rect2(400 - tw / 2 - 12, 500, tw + 24, 48)
		_c.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
		_c.modulate.a = 1.0
		Dialog.draw_nine(_c, tex(Dialog.SKIN), tr)   # 游戏对话框的九宫格 (ACT 9008)
		_t(_toast, tr.position + Vector2(0, 15), 15, Color(1, 1, 1, a), false, tr.size.x, HORIZONTAL_ALIGNMENT_CENTER)
	if _confirm:
		_draw_confirm()


func _draw_empty(title: String, body: String, with_button := false, btn_text := "打开 mod 文件夹") -> void:
	_sheet(EMPTY_AREA)
	_t("◇", Vector2(370, _row(EMPTY_AREA, 6) - 6), 22, INK3, false, 60, HORIZONTAL_ALIGNMENT_CENTER)
	_t(title, Vector2(150, _row(EMPTY_AREA, 7)), 17, INK, true, 500, HORIZONTAL_ALIGNMENT_CENTER)
	var k := 8
	for line in body.split("\n"):
		_t(line, Vector2(100, _row(EMPTY_AREA, k)), 14, INK2, false, 600, HORIZONTAL_ALIGNMENT_CENTER)
		k += 1
	if with_button:
		_button(EMPTY_BTN, btn_text, true, true)


func _draw_local() -> void:
	var l := _list()
	if l.is_empty():
		_draw_empty("还没有安装 mod", "把 .pod 文件放进 mod 文件夹，再点右上角「刷新」。\n点下面的按钮打开 mod 文件夹。", true)
		return
	var order := 0
	for i in ROWS:
		var k := top + i
		if k >= l.size():
			break
		var m: Dictionary = l[k]
		var r := _card_rect(i)
		_card_bg(r, k == sel)
		_thumb(Rect2(r.position + Vector2(16, 14), Vector2(100, 68)), m)
		_t(str(m.name), r.position + Vector2(128, 10), 16, INK, true, 270)
		var sub := "%s · v%s · %s%s" % [m.author if m.author != "" else "未知作者", m.version, _size_text(int(m.size)),
			" · 开发" if m.dev else ""]
		if m.status == "error" and m.version == "":
			sub = "无法读取 · %s" % _size_text(int(m.size))
		_t(sub, r.position + Vector2(128, 32), 12, INK2, false, 290)
		_status_badge(r.position + Vector2(128, 54), m)
		if m.status == "loaded" or m.status == "pending":
			order = l.slice(0, k + 1).filter(func(x): return x.status in ["loaded", "pending"]).size()
			_t("#%d" % order, r.position + Vector2(372, 14), 13, COL, true, 30, HORIZONTAL_ALIGNMENT_RIGHT)
	_scroll(l.size())
	_draw_detail(_cur())


func _draw_detail(m: Dictionary) -> void:
	_sheet(PANEL)
	if m.is_empty():
		return
	var x := PANEL.position.x + 24
	_thumb(Rect2(x, _row(PANEL, 0), 266, SHEET_ROW * 5 - 4), m)
	if _preview(m) == null:
		_t("没有预览图", Vector2(x + 10, _row(PANEL, 4)), 12, Color(1, 0.96, 0.9, 0.9))
	_t(str(m.name), Vector2(x, _row(PANEL, 5)), 17, INK, true, 266)
	var y := _row(PANEL, 6)
	var sign := "开发文件夹（未签名）" if m.kind == "dir" else ("已验证 · 指纹 %s" % str(m.fingerprint).left(8) if m.fingerprint != "" else "—")
	var rows := [["作者", m.author if m.author != "" else "未知"], ["版本", "%s · %s" % [m.version, _size_text(int(m.size))]],
		["类型", ".pod 加密包" if m.kind == "pod" else "文件夹"], ["签名", sign if m.status != "error" else "未通过"]]
	for row in rows:
		_t(row[0], Vector2(x, y), 14, INK3)
		_t(str(row[1]), Vector2(x + 52, y), 14, INK, false, 214)
		y += SHEET_ROW
	if m.status == "error":
		_t("无法加载：" + str(m.error), Vector2(x, y), 14, BAD_C, true, 266)
		y += SHEET_ROW
	if str(m.description) != "":
		y += _para(str(m.description), Vector2(x, y), 266, 14, Color8(90, 58, 30), 5, SHEET_ROW)
	# 按钮
	var b := _btn_rects()
	var main_txt := "停用" if m.enabled else "启用"
	var can_toggle: bool = m.status != "error" and not m.dev
	_button(b[0], main_txt, can_toggle, true)
	_button(b[1], "上移", sel > 0)
	_button(b[2], "下移", sel < _list().size() - 1)
	_button(b[3], "删除", not m.dev, false, true)


func _draw_confirm() -> void:
	_c.draw_rect(Rect2(0, 0, 800, 600), Color(0, 0, 0, 0.35))
	# 游戏对话框样式: 九宫格深色窗 + 白字, 选项用光棒 (同 dialog.gd 选项, 透明度 120)
	var r := Rect2(250, 220, 300, 150)
	Dialog.draw_nine(_c, tex(Dialog.SKIN), r)
	_t("确定要删除「%s」吗？" % str(_cur().get("name", "")), r.position + Vector2(10, 30), 16, Color.WHITE, false, r.size.x - 20, HORIZONTAL_ALIGNMENT_CENTER)
	_t("文件会被移除，无法恢复。", r.position + Vector2(10, 58), 13, Dialog.PALETTE[5], false, r.size.x - 20, HORIZONTAL_ALIGNMENT_CENTER)
	var cr := _confirm_rects()
	for i in 2:
		if i == _confirm_sel or (cr[i] as Rect2).has_point(_mouse()):
			_img(Dialog.BAR, cr[i], Color(1, 1, 1, 120 / 255.0))
		_t("删除" if i == 0 else "取消", (cr[i] as Rect2).position + Vector2(0, 8), 16, Color.WHITE, i == _confirm_sel, (cr[i] as Rect2).size.x, HORIZONTAL_ALIGNMENT_CENTER)
