class_name Dialog
extends CanvasLayer











signal closed(actor: int)


const PALETTE := [Color8(255, 255, 255), Color8(0, 0, 0), Color8(255, 0, 0), Color8(0, 255, 0), Color8(0, 0, 255), 
	Color8(231, 207, 171), Color8(209, 168, 100), Color8(204, 196, 178), Color8(237, 192, 95), Color8(255, 168, 50), 
	Color8(0, 128, 255)]
const SKIN := "ui/all_sys/0139_000_九公格框1/000.png"
const BORDER := "ui/all_sys/0009_000_对话框/000.png"
const ARROW := ["ui/all_sys/0227_000_游标图1/002.png", "ui/all_sys/0227_000_游标图1/003.png"]
const BAR := "ui/all_sys/0115_000_光棒/000.png"
const FRAME := 1.0 / 35.0

var field: Node
var windows := {}
var last_choice := 0
var auto_choice := 0
var auto_seq: Array = []
var _auto_menu_i := 0
var _auto_last := ""
var _auto_same := 0
var auto_advance := 0.0
var choice_wait := 0.0
static var TRACE := OS.get_cmdline_user_args().has("--trace-dlg")
var tex := {}
var font: FontVariation


func _ready() -> void:
	layer = 10
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--auto-advance="):
			auto_advance = float(a.substr(15))
		elif a.begins_with("--choice-wait="):
			choice_wait = float(a.substr(14))
		elif a.begins_with("--choices="):
			auto_seq = Array(a.substr(10).split(",")).map( func(x): return int(x))
	for k in [SKIN, BORDER, BAR] + ARROW:
		tex[k] = Game.load_texture(k)
	font = talk_font()


static var _talk_font: FontVariation



static func talk_font() -> FontVariation:
	if _talk_font == null:
		var base := SystemFont.new()
		base.font_names = PackedStringArray(["Hiragino Sans GB", "PingFang SC", "Source Han Sans SC", "Noto Sans CJK SC", 
			"Microsoft YaHei", "Songti SC"])
		base.font_weight = 500
		base.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		base.allow_system_fallback = true
		_talk_font = FontVariation.new()
		_talk_font.base_font = base
	return _talk_font




static var arrow_player := UiAct.Player.new()


func _process(delta: float) -> void:
	if windows.is_empty():
		return
	arrow_player.set_state(9019, 16)
	arrow_player.battle = is_equal_approx(FieldActor.TICK, UiAct.TICK_BATTLE)
	arrow_player.advance(delta)


func is_open(actor: int) -> bool:
	return windows.has(actor)


func close(actor: int) -> void:
	if windows.has(actor):
		var w: TalkWindow = windows[actor]
		windows.erase(actor)
		if w.voiced != "":
			Game.stop_voice(w.voiced)
		w.queue_free()
		closed.emit(actor)


func close_all() -> void:
	for a in windows.keys():
		close(a)




static var char_spacing := 5
static var line_spacing := 5


func show_text(actor: int, p: Array, text: String, bg: Color, caption: String, spacing := -1, line_gap := -1, anchor: Variant = null) -> void:
	if spacing < 0:
		spacing = char_spacing
	if line_gap < 0:
		line_gap = line_spacing
	close(actor)
	var w := TalkWindow.new()
	w.dlg = self
	w.actor = actor
	w.anchor = anchor
	w.setup(p, text, bg, caption, spacing, line_gap)
	add_child(w)
	windows[actor] = w
	w.voiced = Game.play_voice(text)
	if TRACE:
		print("DLG %.1f show a=%d limit=%.2f pages=%d voice=%s len=%.2f text=%s" % [Time.get_ticks_msec() / 1000.0,
			actor, w.limit, w.pages.size(), w.voiced, Game.voice_len(), text.replace("\n", "⏎").substr(0, 60)])



func show_prompt(box: Rect2, text: String) -> void:
	var r := [0, box.position.x, box.position.y, box.position.x, box.position.y, 0, box.size.x, box.size.y, 8]
	show_text(65281, r, text, Color.BLACK, "", 2, 6)
	var w: TalkWindow = windows[65281]
	w.inset = Vector2(24, 24)
	w.tip_skin = true



func advance() -> bool:
	for a in windows.keys():
		var w: TalkWindow = windows[a]
		if w.on_confirm():
			return true
	return false


func has_input_window() -> bool:
	for w in windows.values():
		if (w as TalkWindow).wants_input():
			return true
	return false
















const TIP_SKIN := "ui/all_sys/0251_000_九宫格框2/000.png"
static var _tip_skin: Texture2D
static var _bar_tex: Texture2D





static func tip_layout(t: String, c: Vector2) -> Dictionary:
	var n := 0
	var counting := true
	var glyphs: Array = []
	var bars: Array = []
	var col: Color = PALETTE[0]
	var i := 0
	var x := 0.0
	var in_btn := false
	var btn_x := 0.0
	var btn_b := 0
	var lab_b := 0
	var hits_raw: Array = []
	while i < t.length():
		var ch := t[i]
		if ch == "%" and i + 1 < t.length():
			var k := t[i + 1]
			if k == "Q":
				break
			if k in ["C", "O", "D", "S"]:
				if k == "C" and i + 2 < t.length():
					var d := t[i + 2].to_int()
					col = PALETTE[d] if d < PALETTE.size() else col
				i += 3
				continue
			if k in ["B", "A"]:
				in_btn = k == "B"
				btn_x = x
				btn_b = n
				lab_b = 0
				i += 2
				continue
			if k == "N":
				counting = false
				i += 2
				continue
		if ch == ".":
			if in_btn:
				bars.append([btn_x, x])
				hits_raw.append([btn_b, lab_b])
				in_btn = false
			i += 1
			continue
		var full := ch.unicode_at(0) >= 128
		if counting:
			n += 2 if full else 1
		if in_btn:
			lab_b += 2 if full else 1
		glyphs.append([ch, x, col])
		x += 22.0 if full else 12.0
		i += 1
	var w := 22 * (n >> 1) + 40 + 10 * (n & 1)
	var box := Rect2(Vector2(c.x - w / 2, c.y - 26), Vector2(w, 52))
	var org := box.position + Vector2(20, 16)
	var out_g: Array = []
	for g in glyphs:
		out_g.append([g[0], org + Vector2(float(g[1]), 0), g[2]])
	var out_b: Array = []
	for b in bars:
		out_b.append(Rect2(org + Vector2(float(b[0]) - 4, -4), Vector2(float(b[1]) - float(b[0]) + 8, 28)))
	var hits: Array = []
	for h in hits_raw:
		hits.append(Rect2(box.position + Vector2(20 + 12 * int(h[0]), 16), Vector2((int(h[1]) >> 1) * 22, 20)))
	return {"box": box, "glyphs": out_g, "buttons": out_b, "hits": hits}


static func draw_top_tip(ci: CanvasItem, t: String, alpha := 1.0, center := Vector2(400, 80), sel := -1) -> void:
	if t == "" or alpha <= 0.0:
		return
	ci.modulate.a = alpha
	draw_tip_layout(ci, tip_layout(t, center), sel)



static func draw_tip_layout(ci: CanvasItem, L: Dictionary, sel := -1) -> void:
	if _tip_skin == null:
		_tip_skin = Game.load_texture(TIP_SKIN)
	draw_nine(ci, _tip_skin, L.box, true)
	var f := talk_font()
	for g in L.glyphs:
		var p: Vector2 = g[1] + Vector2(0, 17)
		ci.draw_string(f, p + Vector2(1, 1), g[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0, 0, 0))
		ci.draw_string(f, p, g[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, g[2])
	if sel >= 0 and sel < L.buttons.size():
		if _bar_tex == null:
			_bar_tex = Game.load_texture(BAR)
		if _bar_tex:
			ci.draw_texture_rect(_bar_tex, L.buttons[sel], false, Color(1, 1, 1, 120 / 255.0))


static func draw_nine(ci: CanvasItem, t: Texture2D, r: Rect2, center_tex := false, center := true) -> void:
	if t == null:
		ci.draw_rect(r, Color(0, 0, 0, 0.6))
		return
	var c := 32.0
	var x := r.position.x
	var y := r.position.y
	var w := r.size.x
	var h := r.size.y


	var by := y + h - 32.0
	var rx := x + w - 31.0
	var cell := func(k: int) -> Rect2: return Rect2((k % 4) * c, int(k / 4.0) * c, c, c)





	var fill := Rect2(x - 1.0, y + 4.0, w - 2.0, by + 28.0 - (y + 4.0))
	if center and fill.size.x > 0 and fill.size.y > 0:
		if center_tex:
			ci.draw_texture_rect_region(t, fill, cell.call(3), Color(1, 1, 1, 150 / 255.0))
		else:
			ci.draw_rect(fill, Color8(17, 18, 0, int(239 * 150 / 255.0)))
	var pieces := [
		[Rect2(x, y, w, c), 1, false], [Rect2(x, by, w, c), 5, false], 
		[Rect2(x - 5.0, y + 2.0, c, h - 32.0), 2, false], [Rect2(rx, y + 2.0, c, h - 32.0), 2, true], 
		[Rect2(x - 5.0, y, c, c), 0, false], [Rect2(rx, y, c, c), 0, true], 
		[Rect2(x - 5.0, by, c, c), 4, false], [Rect2(rx, by, c, c), 4, true]]
	for pc in pieces:
		var dst: Rect2 = pc[0]
		if dst.size.x <= 0 or dst.size.y <= 0:
			continue
		if pc[2]:
			ci.draw_set_transform(Vector2(dst.position.x * 2 + dst.size.x, 0), 0, Vector2(-1, 1))
			ci.draw_texture_rect_region(t, dst, cell.call(pc[1]))
			ci.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
		else:
			ci.draw_texture_rect_region(t, dst, cell.call(pc[1]))



func auto_pick(opts: Array) -> int:
	var key := str(opts)
	_auto_same = _auto_same + 1 if key == _auto_last else 0
	_auto_last = key
	if _auto_same >= 3 and auto_seq.is_empty():
		return opts.size() - 1
	if auto_seq.size():
		var c := int(auto_seq[mini(_auto_menu_i, auto_seq.size() - 1)])
		_auto_menu_i += 1
		return clampi(c, 0, maxi(opts.size() - 1, 0))
	return clampi(auto_choice, 0, maxi(opts.size() - 1, 0))


func _choose(actor: int, k: int) -> void:
	last_choice = k
	close(actor)


func item_name(id: int) -> String:
	if field and field.names.items.has(str(id)):
		return str(field.names.items[str(id)])
	return str(id)




class TalkWindow:
	extends Control

	var dlg: Dialog
	var actor := 0
	var voiced := ""
	var p: Array = []
	var flags := 0
	var bg := Color.BLACK
	var spacing := 2
	var line_gap := 5
	var pos := Vector2.ZERO
	var target := Vector2.ZERO
	var wsize := Vector2(510, 120)
	var inset := Vector2(15, 10)
	var tip_skin := false
	var grow := 1.0
	var anchor: Variant = null
	var pages: Array = []
	var page := 0
	var shown := 0
	var page_chars := 0
	var timer := 0.0
	var limit := 0.0
	var t_frame := 0.0
	var countdown := 0
	var options: Array = []
	var sel := 0
	var age := 0.0
	var done_t := 0.0
	var caption := ""
	var centered := false

	func setup(params: Array, text: String, color: Color, cap: String, sp: int, lg: int) -> void:
		p = params
		flags = int(p[8])
		add_to_group("talk_windows")
		bg = color
		spacing = sp
		line_gap = lg
		caption = cap
		limit = int(p[0]) * 0.01
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var cw := 20 + spacing
		var w := float(p[6])
		var h := float(p[7])
		var units := flags & 16384 != 0
		var lines := _layout(text, cw, w, units)
		var inner_w := 0.0
		for ln in lines:
			inner_w = maxf(inner_w, _line_width(ln, cw))
		var lh := 20 + line_gap
		if flags & 8192 and w == 0:
			wsize = Vector2(maxf(inner_w + 30, 60), maxf(lines.size() * lh + 20, 40))
		elif units:
			var cols := w if w > 0 else ceilf(inner_w / cw)
			var rows := h if h > 0 else float(lines.size())
			wsize = Vector2(cols * cw + 30, rows * lh + (20 if rows > 1 else 15))
		else:
			wsize = Vector2(w if w > 0 else inner_w + 30, h if h > 0 else lines.size() * lh + 20)

		var per := lines.size() if flags & 8192 else maxi(1, int((wsize.y - 20) / lh))
		if units and h > 0:
			per = int(h)
		pages = []
		var cur: Array = []
		for ln in lines:
			if ln.size() == 1 and ln[0][0] == "\f":
				pages.append(cur)
				cur = []
				continue
			cur.append(ln)
			if cur.size() >= per:
				pages.append(cur)
				cur = []
		if cur.size():
			pages.append(cur)
		if pages.is_empty():
			pages = [[]]
		_start_page()
		pos = Vector2(p[1], p[2])
		target = Vector2(p[3], p[4])
		if units and h == 1:
			pos -= wsize * 0.5
			target -= wsize * 0.5
		if float(p[5]) == 0:
			pos = target
		if flags & 8192:
			grow = 0.0
		# 有多个选项的窗口 (选择题): 一律摆到 800×600 界面正中, 不跟着说话人的头走
		if not options.is_empty():
			centered = true
			pos = Vector2(maxf(0.0, (800.0 - wsize.x) * 0.5), maxf(0.0, (600.0 - wsize.y) * 0.5))
			target = pos
		position = pos
		size = wsize


	func _layout(text: String, cw: int, w: float, units: bool) -> Array:
		var lines: Array = [[]]
		var col: Color = Dialog.PALETTE[0]
		var speed := 3
		var max_w := 1000000000.0
		if flags & 8192 and w == 0:
			max_w = 10 * cw if text.length() > 10 else 1000000000.0
		elif units and w > 0:
			max_w = w * cw
		elif w > 0:
			max_w = w - 30
		var i := 0
		while i < text.length():
			var ch := text[i]
			if ch == "%" and i + 1 < text.length():
				var c := text[i + 1]
				if c == "N":
					lines.append([])
					i += 2
					continue
				if c in ["n", "A", "K"]:
					i += 2
					continue
				if c == "P":
					lines.append([["\f", col, 0]])
					lines.append([])
					i += 2
					continue
				if c == "Q":
					break
				if c in ["C", "S", "O", "D", "F"]:
					var j := i + 2
					var num := ""
					while j < text.length() and text[j].is_valid_int() and num.length() < 2:
						num += text[j]
						j += 1
					if c == "C" and num != "":
						col = Dialog.PALETTE[clampi(int(num), 0, Dialog.PALETTE.size() - 1)]
					elif c == "S" and num != "":
						speed = int(num)
					i = j
					continue
				if c == "T":
					var e := text.find(".", i + 2)
					var nm := dlg.item_name(int(text.substr(i + 2, e - i - 2))) if e > 0 else ""
					for k in nm:
						lines[-1].append([k, col, speed])
					i = e + 1 if e > 0 else text.length()
					continue
				if c == "B":
					var e2 := text.find(".", i + 2)
					if e2 < 0:
						e2 = text.length()
					var label := text.substr(i + 2, e2 - i - 2)
					options.append({"text": label, "line": lines.size() - 1, "col": _line_width(lines[-1], cw)})
					for k in label:
						lines[-1].append([k, col, speed])
					i = e2 + 1
					continue
			if _line_width(lines[-1], cw) + _char_w(ch, cw) > max_w + 0.5:
				lines.append([])

			lines[-1].append([ch, col, 0 if ch == " " or ch == "　" else speed])
			i += 1
		while lines.size() > 1 and lines[-1].is_empty():
			lines.pop_back()
		return lines

	func _char_w(ch: String, cw: int) -> float:

		return cw if ch.unicode_at(0) >= 128 else cw - 10

	func _line_width(ln: Array, cw: int) -> float:
		var s := 0.0
		for c in ln:
			s += _char_w(c[0], cw)
		return s

	func _start_page() -> void:
		shown = 0
		page_chars = 0
		for ln in pages[page]:
			page_chars += ln.size()
		countdown = 0
		timer = 0.0

	func page_done() -> bool:
		return shown >= page_chars

	func wants_input() -> bool:
		return not (flags & 1) and (limit <= 0.0 or options.size() > 0)


	func on_confirm() -> bool:

		if options.size() and page_done() and page == pages.size() - 1:
			dlg._choose(actor, sel)
			return true

		if flags & 1 or (flags & 16 and timer < limit):
			return false
		if not page_done():
			shown = page_chars
			return true
		_next()
		return true

	func _next() -> void:
		if page < pages.size() - 1:
			page += 1
			_start_page()
			if Dialog.TRACE:
				print("DLG %.1f page-> %d/%d a=%d chars=%d" % [Time.get_ticks_msec() / 1000.0, page + 1, pages.size(), actor, page_chars])
		else:
			dlg.close(actor)

	func _process(delta: float) -> void:
		age += delta
		t_frame += delta
		while t_frame >= Dialog.FRAME and is_inside_tree():
			t_frame -= Dialog.FRAME
			_frame()
		queue_redraw()

	func _frame() -> void:
		var d := target - pos
		if d.length() > 0.5:
			var sp := float(p[5])
			if flags & 2048:
				pos += d.normalized() * minf(sp, d.length())
			elif sp > 0:
				pos += d / sp if d.length() > sp else d * 0.5
			else:
				pos = target
		if grow < 1.0:
			grow = minf(1.0, grow + 0.2)
		if flags & 8192 and not centered:
			_follow_head()
		position = pos

		if not page_done():
			age = 0.0   # 打字期间不计自动剧情的时间, 打完才从头算停留
			countdown -= 1
			while countdown <= 0 and not page_done():
				var c: Array = _char_at(shown)
				shown += 1
				if int(c[2]) > 0:

					var ts := int(MainMenu.setting("text_speed") * 100.0)
					countdown = maxi(int(c[2]) + [2, 1, 0, -1, -2, -3][clampi(ts / 20, 0, 5)], 1)
					break
		# 语音保护 (用户反馈: 独白"纪元前六二九年…"语音没读完就跳下一句). 这句配音还在播就不自动推进:
		# 原版剧本的 limit (停留时间) 是按阅读速度给的, 加了配音后配音比 limit 长, 以前到点就翻页把话截断
		var vbusy: bool = Game._voice != null and Game._voice.playing
		if limit > 0.0 and (page_done() or not (flags & 32)):
			timer += Dialog.FRAME
			if vbusy:
				timer = minf(timer, limit)   # 到点但语音没播完: 压住, 播完立刻翻
			# 有配音的句子: 停留时间从「文字全部显示完」起算, 而不是从这页开始显示就计时 ——
			# 否则字还在一个一个往上冒, 计时已经跑完, 语音一结束画面立刻切走 (用户反馈: 读到"约"就被跳)
			if voiced != "":
				if not page_done():
					timer = 0.0
				elif age < limit:
					timer = minf(timer, limit - Dialog.FRAME)
			if timer >= limit and options.is_empty():
				if Dialog.TRACE:
					print("DLG limit next a=%d limit=%.2f age=%.2f voice=%s" % [actor, limit, age, str(vbusy)])
				_next()
				return
		if Game.demo and (limit <= 0.0 or options.size()) and page_done():
			done_t += Dialog.FRAME
			if done_t >= clampf(page_chars * 0.07, 1.4, 4.0):
				done_t = 0.0
				if options.size():
					page = pages.size() - 1
					dlg._choose(actor, dlg.auto_pick(options))
				else:
					_next()
				return
		if options.size() and dlg.choice_wait > 0.0 and dlg.auto_seq.size() and age >= dlg.choice_wait * 0.55:
			sel = clampi(int(dlg.auto_seq[mini(dlg._auto_menu_i, dlg.auto_seq.size() - 1)]), 0, options.size() - 1)
		if dlg.auto_advance > 0.0 and vbusy:
			age = minf(age, maxf(dlg.auto_advance - 0.15, 0.0))   # 配音没播完不翻页, 播完约 0.15 秒后翻
		# 自动剧情: 只自动翻叙事页; 遇到选项就停住等玩家选 (以前连选项也 auto_pick 乱选)
		if dlg.auto_advance > 0.0 and limit <= 0.0 and options.is_empty() and age >= dlg.auto_advance:
			age = 0.0
			shown = page_chars
			if Dialog.TRACE:
				print("DLG auto next a=%d ad=%.2f voice=%s" % [actor, dlg.auto_advance, str(vbusy)])
			_next()

	func _char_at(k: int) -> Array:
		var n := 0
		for ln in pages[page]:
			if k < n + ln.size():
				return ln[k - n]
			n += ln.size()
		return [" ", Color.WHITE, 0]



	func _follow_head() -> void:
		var hp: Vector2
		if flags & 64 and anchor is Vector3:
			hp = dlg.field.screen_pos(anchor)
		else:
			var a: Node3D = dlg.field.actor(actor) if dlg.field else null
			if a == null:
				return
			hp = dlg.field.screen_pos(a.global_position + Vector3(0, 1.9, 0))
		var x := hp.x - wsize.x / 2.0 if hp.x < 320 else hp.x - wsize.x / 3.0
		var y := hp.y - wsize.y
		target = Vector2(clampf(x, 20, maxf(20, 630 - wsize.x)), clampf(y, 20, maxf(20, 470 - wsize.y)))
		if age < 0.05:
			pos = target

	func _input(e: InputEvent) -> void:
		if options.is_empty() or not page_done() or page != pages.size() - 1:
			return



		if e is InputEventKey and e.pressed and not e.echo:
			if e.keycode in [KEY_UP, KEY_LEFT]:
				sel = maxi(sel - 1, 0)
				Game.play_sound(513)
				get_viewport().set_input_as_handled()
			elif e.keycode in [KEY_DOWN, KEY_RIGHT]:
				sel = mini(sel + 1, options.size() - 1)
				Game.play_sound(513)
				get_viewport().set_input_as_handled()
			elif e.keycode in [KEY_ESCAPE, KEY_CTRL]:
				_cancel_key()
				get_viewport().set_input_as_handled()
		elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			# 选择题窗口: 点哪条就选哪条; 没点在选项上就算点空了 (以前会悄悄选默认项 0)
			var mb := make_input_local(e) as InputEventMouseButton
			var lp: Vector2 = mb.position
			var hit := -1
			for k in options.size():
				if _option_rect(k).has_point(lp):
					hit = k
					break
			if hit >= 0:
				sel = hit
				dlg._choose(actor, hit)
			get_viewport().set_input_as_handled()
		elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_RIGHT:
			_cancel_key()
			get_viewport().set_input_as_handled()
		elif e is InputEventMouseMotion:
			# 宽屏补丁: 界面层有居中偏移 (CanvasLayer.offset), 事件坐标要用 make_input_local 换算成窗口本地坐标
			var mv := make_input_local(e) as InputEventMouseMotion
			_hover_update(mv.position)

	func _hover_update(lp: Vector2) -> void:
		for k in options.size():
			if _option_rect(k).has_point(lp) and sel != k:
				sel = k
				Game.play_sound(513)
				queue_redraw()

	func _cancel_key() -> void:
		Game.play_sound(514)
		if Game.cancel_lock == 0:
			Game.cancel_residual = true
			dlg._choose(actor, 0)

	func _option_rect(k: int) -> Rect2:
		var o: Dictionary = options[k]
		var lh := 20 + line_gap
		var n := 0
		for pg in page:
			n += pages[pg].size()
		var row := int(o.line) - n
		var cw := 20 + spacing
		var tw := 0.0
		for ch in str(o.text):
			tw += _char_w(ch, cw)
		return Rect2(inset.x + float(o.col) - 4, inset.y + row * lh - 4, tw + 8, 28)

	func _draw() -> void:
		var sz := wsize * (0.4 + 0.6 * grow) if grow < 1.0 else wsize
		if flags & 2:
			var a := bg.a   # 黑底对话框: 不再随 age 渐显, 一出现就是最终半透明黑
			draw_rect(Rect2(Vector2.ZERO, sz), Color(bg.r, bg.g, bg.b, a))
			if not (flags & 32768) and dlg.tex.get(Dialog.BORDER):
				draw_texture(dlg.tex[Dialog.BORDER], Vector2(3, 3))
		elif tip_skin:
			if Dialog._tip_skin == null:
				Dialog._tip_skin = Game.load_texture(Dialog.TIP_SKIN)
			Dialog.draw_nine(self, Dialog._tip_skin, Rect2(Vector2.ZERO, sz), true)
		elif not (flags & 32768):
			_nine_at(Rect2(Vector2.ZERO, sz))
		if caption != "":
			_nine_at(Rect2(0, -39, caption.length() * 16 + 20, 40))
			_text_at(Vector2(4, -26 + 14), caption, Dialog.PALETTE[5], 16)
		if options.size() and page_done() and page == pages.size() - 1 and dlg.tex.get(Dialog.BAR):
			draw_texture_rect(dlg.tex[Dialog.BAR], _option_rect(sel), false, Color(1, 1, 1, 120 / 255.0))
		var lh := 20 + line_gap
		var cw := 20 + spacing
		var k := 0
		var y := inset.y
		for ln in pages[page]:
			var x := inset.x
			for c in ln:
				if k >= shown:
					break
				if c[0] != "\f":
					_text_at(Vector2(x, y + 17), c[0], c[1], 20)
				x += _char_w(c[0], cw)
				k += 1
			y += lh
		if page_done() and options.is_empty() and not (flags & 8) and not (flags & 1):
			Dialog.arrow_player.draw(self, sz - Vector2(32, 32))
			queue_redraw()

	func _text_at(at: Vector2, s: String, col: Color, fs: int) -> void:
		draw_string(dlg.font, at + Vector2(1, 1), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0))
		draw_string(dlg.font, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

	func _nine_at(r: Rect2) -> void:
		Dialog.draw_nine(self, dlg.tex.get(Dialog.SKIN), r)
