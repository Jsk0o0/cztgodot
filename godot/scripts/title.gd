extends Node
## 标题画面, 按原版还原 (SWDMD_GB.EXE 0x4701e8 状态机 / 0x470660 绘制):
##   背景 = ACT 9003 第 0 帧「000_標題介面800x600」(800×600)
##   菜单 = 開始 / 讀取 / 設定 / 離開 / 動畫, 纵坐标表 299/344/389/434/479 (间距 45 = 按钮高)
##          按钮图 210×45: 帧 1-5 常态, 6-10 选中, 11-15 按下
##   选定后先播「000_桓遠之眨眼」(5 帧, 贴在 137,275) 睁眼, 播完才执行该项 (原版 [0xa60264]/[0xa60268])
##   音乐 = MAPS.DAT 地图音乐表 1 号记录 → Fate100.mp3
## 调试截图: godot --path godot res://scenes/title.tscn -- --shot=/path/out.png [--shot-delay=3] [--shot-select=2] [--shot-press]

const UI_DIR := "ui/all_sys/0100_000_标题介面800x600/"
const EYE_DIR := "ui/all_sys/0012_000_桓远之眨眼/"
const TITLE_MUSIC := "Fate100.mp3"
const MENU_X := 460              # 按钮居中于标题字下方 (原版文字版画在 x=530)
const MENU_Y := [299, 344, 389, 434, 479, 524]   # 第 3 项「工坊」是新增 (原版只有 5 项, 用户要求放在「设定」上面), 同样间隔 45
const MENU_Y_OFFSET := -10        # 文字基准 → 按钮图顶部
const EYE_POS := Vector2(137, 275)
static var _eye_done := false   # 0xa60150 / [0xa60268]: 整个进程只眨一次
const ITEMS := ["start", "load", "workshop", "settings", "quit", "movie"]
const CUSTOM_DIR := "ui/custom/"   # 新增按钮图 (tools/make_title_buttons.py 按原版样式生成)
const BROWN := Color(0.36, 0.22, 0.10)
const PAPER := Color(0.97, 0.94, 0.86, 0.96)

var _root: Control
var _buttons: Array[TextureRect] = []
var _tex_normal: Array[Texture2D] = []
var _tex_hover: Array[Texture2D] = []
var _tex_press: Array[Texture2D] = []
var _eye: TextureRect
var _eye_frames: Array[Texture2D] = []
var _fade: ColorRect
var _panel: Control
var _sel := 0
var _busy := false
var _card: Control
var _locked := false   # 没验证到原版游戏目录: 面板关不掉, 不能开始


func _ready() -> void:
	if OS.get_cmdline_user_args().has("--open-workshop"):   # 调试: 启动后直接打开创意工坊
		_open_workshop_debug.call_deferred()
	print("TITLE screen entered")
	if Game.cursor:
		Game.cursor.set_state(9001, 9)   # 标题 (0x470660): 普通指针
		Game.cursor.fps = GameCursor.FPS_FIELD
	_build()
	var ex_test := _arg_value("--extract-test=")
	if ex_test != "":   # 调试: 用指定的正版目录直接跑提取 (--extract-dir=输出, --extractor=提取程序), 不改设置, 做完退出
		_run_extract(ex_test, _arg_value("--extract-dir="), true)
	elif OS.get_cmdline_user_args().has("--extract-ask"):   # 调试: 只显示提取说明面板 (截图用; 配 --extract-dir)
		_ask_extract()
	elif not Game.data_ready() and Game.extractor_path() != "":
		# 发行版 (本机提取): 先验证正版目录, 再从它提取素材 (_ask_extract)
		if Game.check_game_dir(Game.game_dir) != "":
			_ask_game_dir(Game.check_game_dir(Game.game_dir))
		else:
			_ask_extract()
	elif not Game.data_ready():
		# 发行版: 素材包放在程序旁边的 packs/ (Game._load_packs); 开发环境: local_paths.cfg 指向提取目录
		_message("找不到游戏素材\n\n请确认程序旁边的 packs 文件夹完整（至少要有 common.pck 和各章节的 .pck）。\n\n素材包目录：%s\n提取目录：%s" % [OS.get_executable_path().get_base_dir().path_join("packs"), Game.extracted_dir])
	elif Game.check_game_dir(Game.game_dir) != "":
		_ask_game_dir(Game.check_game_dir(Game.game_dir))
	else:
		Game.play_music(TITLE_MUSIC, 2.0)
	_fade_to(0.0, 1.2)
	_debug_args()
	if Game.demo:
		await get_tree().create_timer(4.0).timeout
		_sel = 0
		_refresh(_sel)
		await get_tree().create_timer(1.0).timeout
		_choose()


# ---------------- 构建 ----------------

func _build() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE   # 全屏底层默认 STOP 会吞掉鼠标, 盖在上面的读取画面就收不到点击 (按钮自己是 STOP)
	layer.add_child(_root)

	var bg := TextureRect.new()
	bg.texture = Game.load_texture(UI_DIR + "000.png")
	bg.position = Vector2.ZERO
	bg.size = Vector2(800, 600)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bg)

	for k in 5:
		_eye_frames.append(Game.load_texture(EYE_DIR + "%03d.png" % k))
	_eye = TextureRect.new()
	_eye.position = EYE_POS
	_eye.visible = _eye_done   # 眨过一次之后 [0xa60268] 一直为 1: 每帧画 9003 qq16 (睁眼帧 004)
	if _eye_done and _eye_frames.size() >= 5:
		_eye.texture = _eye_frames[4]
	_root.add_child(_eye)

	for k in ITEMS.size():
		# 六项都用 tools/make_title_buttons.py 按原版样式生成的简体字按钮 (用户要求统一, 不和原版繁体手写字混用);
		# 没生成时前五项退回原版图
		if FileAccess.file_exists(Game.asset_path(CUSTOM_DIR + "title_%s_n.png" % ITEMS[k])):
			_tex_normal.append(Game.load_texture(CUSTOM_DIR + "title_%s_n.png" % ITEMS[k]))
			_tex_hover.append(Game.load_texture(CUSTOM_DIR + "title_%s_h.png" % ITEMS[k]))
			_tex_press.append(Game.load_texture(CUSTOM_DIR + "title_%s_p.png" % ITEMS[k]))
		else:
			var o: int = ["start", "load", "settings", "quit", "movie"].find(ITEMS[k])   # 原版图的序号
			_tex_normal.append(Game.load_texture(UI_DIR + "%03d.png" % (1 + o)) if o >= 0 else null)
			_tex_hover.append(Game.load_texture(UI_DIR + "%03d.png" % (6 + o)) if o >= 0 else null)
			_tex_press.append(Game.load_texture(UI_DIR + "%03d.png" % (11 + o)) if o >= 0 else null)
		var b := TextureRect.new()
		b.position = Vector2(MENU_X, MENU_Y[k] + MENU_Y_OFFSET)
		b.size = Vector2(210, 45)
		b.mouse_filter = Control.MOUSE_FILTER_STOP
		b.mouse_entered.connect(_on_hover.bind(k))
		b.gui_input.connect(_on_button_input.bind(k))
		_root.add_child(b)
		_buttons.append(b)
	_refresh()
	# 飘落的竹叶 (原版 3D 粒子, 画在界面之上)
	_root.add_child(TitleLeaves.new())

	_panel = Control.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_panel)

	_fade = ColorRect.new()
	_fade.color = Color.BLACK
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_fade)


func _refresh(pressed := -1) -> void:
	for k in _buttons.size():
		var t := _tex_normal[k]
		if k == pressed:
			t = _tex_press[k]
		elif k == _sel:
			t = _tex_hover[k]
		_buttons[k].texture = t


# ---------------- 输入 ----------------

func _on_hover(k: int) -> void:
	if _busy or _panel_open():
		return
	if _sel != k:
		Game.play_sound(0x21a)   # 原版 0x470034: 鼠标移到另一项时播 0x21a
	_sel = k
	_refresh()


func _on_button_input(e: InputEvent, k: int) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and not _panel_open():
		_sel = k
		_choose()


func _unhandled_input(e: InputEvent) -> void:
	if _card or _busy:
		return
	if _panel_open():
		if not _locked and (e.is_action_pressed("ui_cancel") or e.is_action_pressed("ui_accept")):
			_close_panel()
		return
	# ↑↓ (0x47009c / 0x4700df): 每按一下播 0x21a, 到头停住不循环
	if e.is_action_pressed("ui_down"):
		Game.play_sound(0x21a)
		_sel = mini(_sel + 1, ITEMS.size() - 1)
		_refresh()
	elif e.is_action_pressed("ui_up"):
		Game.play_sound(0x21a)
		_sel = maxi(_sel - 1, 0)
		_refresh()
	elif e.is_action_pressed("ui_accept"):
		_choose()


func _input(e: InputEvent) -> void:
	# 序章字幕页 / 动画播放中: 任意键返回
	if _card and e.is_pressed() and (e is InputEventKey or e is InputEventMouseButton or e is InputEventJoypadButton):
		get_viewport().set_input_as_handled()
		var card := _card
		_card = null
		var tw := create_tween()
		tw.tween_property(card, "modulate:a", 0.0, 0.6)
		tw.tween_callback(card.queue_free)
		tw.tween_callback(_reset_title)


# ---------------- 选项 ----------------

func _choose() -> void:
	if _busy:
		return
	_busy = true
	_refresh(_sel)
	# 确认音效 (0x470491): 读取 / 设定 / 离开 / 动画 播 0x1fe; 开始新游戏在进入时播 0x21c (0x470270)
	Game.play_sound(0x21c if ITEMS[_sel] == "start" else 0x1fe)
	# 原版 (0x4701e8 / 0x470660): 開始 / 讀取 / 設定 / 動畫 确认时置 [0xa60264] = 1, 播 ACT 9003 qq17 (5 帧各 16 逻辑帧, 画在 137,275);
	# 进入第 5 帧时结束、才执行该项; 之后 [0xa60268] = 1 一直画 qq16 (第 5 帧静态)。播放器 0xa60150 从不清零 →
	# 只有第一次确认有动画, 以后一帧内就结束。離開 不眨眼, 直接执行
	if ITEMS[_sel] == "quit":
		_do_action("quit")
		return
	_eye.visible = true
	var tw := create_tween()
	if not _eye_done:
		for i in 4:
			var f: Texture2D = _eye_frames[i]
			tw.tween_callback(func(): _eye.texture = f)
			tw.tween_interval(16.0 / 35.0)
	_eye_done = true
	tw.tween_callback(func(): _eye.texture = _eye_frames[4])
	tw.tween_interval(1.0 / 35.0)
	tw.tween_callback(_do_action.bind(ITEMS[_sel]))


func _do_action(item: String) -> void:
	match item:
		"start":
			Game.stop_music(1.5)
			var tw := create_tween()
			tw.tween_property(_fade, "color:a", 1.0, 1.5)
			tw.tween_callback(func():
				State.reset()
				get_tree().change_scene_to_file("res://scenes/field.tscn"))
		"load":
			# 和游戏内同一个读档画面 (0x475e78), 盖在标题上, 标题音乐继续; 第一次打开滚到最新的存档
			var sc := SaveLoadScreen.new()
			sc.mode = "load"
			sc.from_title = true
			add_child(sc)
			if await sc.closed:
				get_tree().change_scene_to_file("res://scenes/field.tscn")   # 地图音乐由进图流程播放
			else:
				_reset_title()
		"settings":
			_show_settings()
		"quit":
			print("AP QUIT via title menu")
			Game.stop_music(1.0)
			var tw := create_tween()
			tw.tween_property(_fade, "color:a", 1.0, 1.0)
			tw.tween_callback(get_tree().quit)
		"movie":
			_play_movie()
		"workshop":
			var ws := WorkshopScreen.new()
			add_child(ws)
			await ws.closed
			_reset_title()


func _reset_title() -> void:
	# 回到标题: 闭眼、恢复菜单; 若画面已黑则重新淡入并播放音乐 (原版 0x4709a9)
	_eye.visible = false
	_busy = false
	_refresh()
	if _fade.color.a > 0.01:
		Game.play_music(TITLE_MUSIC, 2.0)
		_fade_to(0.0, 1.2)


func _show_prologue_card() -> void:
	# 字幕取自原版开场事件 10 的旁白
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 16)
	var lines := [["纪元前六二九年", Game.font_menu, 30, Color(0.95, 0.92, 0.84)],
		["（淝水之战的约一千年前……）", Game.font_body, 16, Color(0.95, 0.92, 0.84, 0.7)],
		["春秋时代．令狐国", Game.font_menu, 40, Color(0.86, 0.74, 0.50)],
		["", Game.font_body, 20, Color.WHITE],
		["—— 原型阶段：后续流程尚未实现，按任意键返回 ——", Game.font_body, 13, Color(1, 1, 1, 0.45)]]
	var tw := create_tween()
	for d in lines:
		var l := _label(d[0], d[1], d[2], d[3])
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.modulate.a = 0.0
		v.add_child(l)
		tw.tween_property(l, "modulate:a", 1.0, 1.0)
	_fade.add_child(v)
	tw.tween_callback(func(): _card = v)


func _play_movie() -> void:
	# 原版「動畫」播放开场 OP_simple.bik; Godot 只能播 Theora, 需先转成 extracted/video/OP_simple.ogv
	var path := Game.video_path("OP_simple.ogv")
	if not FileAccess.file_exists(path):
		_message("播放开场动画\n\n需要先把 VIDEO/OP_simple.bik 转成 Theora 格式：\n%s" % path)
		return
	Game.stop_music(0.5)
	var vp := VideoStreamPlayer.new()
	var st := VideoStreamTheora.new()
	st.file = path
	vp.stream = st
	vp.set_anchors_preset(Control.PRESET_FULL_RECT)
	vp.expand = true
	_fade.color.a = 1.0
	_fade.add_child(vp)
	vp.finished.connect(_on_movie_finished.bind(vp))
	vp.play()
	Game.fit_video(vp, path)
	_card = vp


func _on_movie_finished(vp: Node) -> void:
	_card = null
	vp.queue_free()
	_reset_title()


# ---------------- 面板 (宣纸风格) ----------------

func _panel_open() -> bool:
	return _panel.get_child_count() > 0


func _open_panel(title: String, content: Control) -> void:
	for c in _panel.get_children():
		c.queue_free()
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.add_child(center)
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = PAPER
	sb.border_color = Color(BROWN, 0.8)
	sb.set_border_width_all(2)
	sb.set_content_margin_all(28)
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 10
	pc.add_theme_stylebox_override("panel", sb)
	pc.custom_minimum_size = Vector2(460, 0)
	center.add_child(pc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	pc.add_child(v)
	var t := _label(title, Game.font_menu, 28, BROWN)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	v.add_child(content)
	var hint := _label("" if _locked else "（按 Esc / Enter 或点击此处返回）", Game.font_body, 12, Color(BROWN, 0.6))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.mouse_filter = Control.MOUSE_FILTER_STOP
	hint.gui_input.connect(_on_hint_input)
	v.add_child(hint)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_busy = false


func _on_hint_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and not _locked:
		_close_panel()


func _close_panel() -> void:
	for c in _panel.get_children():
		_panel.remove_child(c)
		c.queue_free()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reset_title()


func _message(text: String) -> void:
	var parts := text.split("\n\n", true, 1)
	var body := _label(parts[1] if parts.size() > 1 else "", Game.font_body, 15, BROWN)
	body.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	body.custom_minimum_size = Vector2(400, 0)
	body.add_theme_constant_override("line_spacing", 5)
	_open_panel(parts[0], body)


## 第一次启动 (或原版目录失效): 让玩家选原版安装目录, 验证通过 (Game.check_game_dir) 才能进游戏
func _ask_game_dir(reason: String) -> void:
	_locked = true
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	var body := _label("本作需要正版《轩辕剑外传·苍之涛》才能游玩。\n请选择原版游戏的安装目录。", Game.font_body, 15, BROWN)
	body.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	body.custom_minimum_size = Vector2(400, 0)
	body.add_theme_constant_override("line_spacing", 5)
	v.add_child(body)
	if Game.game_dir != "":
		var err := _label(reason + "\n" + Game.game_dir, Game.font_body, 13, Color(0.62, 0.16, 0.12))
		err.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		err.custom_minimum_size = Vector2(400, 0)
		v.add_child(err)
	v.add_child(_button_row([["选择游戏目录…", _pick_game_dir], ["离开", func(): _do_action("quit")]]))
	_open_panel("驗證正版", v)


## 面板底部一排按钮: [[文字, Callable], ...]
func _button_row(items: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 24)
	for b in items:
		var btn := Button.new()
		btn.text = b[0]
		btn.add_theme_font_override("font", Game.font_menu)
		btn.add_theme_font_size_override("font_size", 18)
		for st in ["normal", "hover", "pressed", "focus"]:
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(BROWN, 0.12 if st == "normal" else 0.22)
			sb.border_color = Color(BROWN, 0.7)
			sb.set_border_width_all(1)
			sb.set_content_margin_all(8)
			btn.add_theme_stylebox_override(st, sb)
		for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			btn.add_theme_color_override(c, BROWN)
		btn.pressed.connect(b[1])
		row.add_child(btn)
	return row


func _body_label(text: String, size := 15, color := BROWN) -> Label:
	var l := _label(text, Game.font_body, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	l.custom_minimum_size = Vector2(400, 0)
	l.add_theme_constant_override("line_spacing", 5)
	return l


func _arg_value(prefix: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(prefix):
			return a.substr(prefix.length())
	return ""


# ---------------- 本机提取 (发行版第一次运行; Game.extractor_path / ExtractRunner) ----------------

const EXTRACT_NEED_BYTES := 6 * 1024 * 1024 * 1024   # 提取结果约 4.5GB, 加上转视频的临时文件
var _ex_runner: ExtractRunner
var _ex_bar: ProgressBar
var _ex_step: Label
var _ex_time: Label
var _ex_t0 := 0
var _ex_test := false


## 提取到哪: 上次没做完 / 版本旧了的目录接着用, 否则 Game.default_extract_dir()
func _extract_dir() -> String:
	if _arg_value("--extract-dir=") != "":   # 调试
		return _arg_value("--extract-dir=")
	var d := Game.extracted_dir
	if d != "" and not d.begins_with("res://") and Game.extract_state(d) != "new":
		return d
	return Game.default_extract_dir()


func _ask_extract() -> void:
	_locked = true
	var dir := _extract_dir()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	var why: String = {
		"partial": "上次提取没有完成，会从中断的地方继续。",
		"old": "游戏更新了素材提取规则，需要重新提取一次。",
	}.get(Game.extract_state(dir), "第一次运行需要从正版游戏提取素材，只需一次。")
	v.add_child(_body_label(why + "\n大约需要十几分钟，占用约 4.5GB 空间。"))
	v.add_child(_body_label("正版目录：%s\n提取位置：%s" % [Game.game_dir, dir], 13, Color(BROWN, 0.75)))
	var da := DirAccess.open(dir)
	var left := da.get_space_left() if da else 0
	var buttons := [["开始提取", func(): _run_extract(Game.game_dir, dir, false)], ["更换游戏目录…", _pick_game_dir], ["离开", func(): _do_action("quit")]]
	if left > 0 and left < EXTRACT_NEED_BYTES and Game.extract_state(dir) == "new":
		v.add_child(_body_label("磁盘剩余空间只有 %.1fGB，不够提取（需要约 6GB）。请清理后再试。" % (left / 1073741824.0), 13, Color(0.62, 0.16, 0.12)))
		buttons.remove_at(0)
	v.add_child(_button_row(buttons))
	_open_panel("提取素材", v)


func _run_extract(game: String, dir: String, test: bool) -> void:
	_locked = true
	_ex_test = test
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	_ex_step = _body_label("正在启动提取程序…")
	v.add_child(_ex_step)
	_ex_bar = ProgressBar.new()
	_ex_bar.custom_minimum_size = Vector2(400, 18)
	_ex_bar.show_percentage = false
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(BROWN, 0.12)
	bg.border_color = Color(BROWN, 0.6)
	bg.set_border_width_all(1)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(BROWN, 0.7)
	_ex_bar.add_theme_stylebox_override("background", bg)
	_ex_bar.add_theme_stylebox_override("fill", fill)
	v.add_child(_ex_bar)
	_ex_time = _body_label("", 13, Color(BROWN, 0.75))
	v.add_child(_ex_time)
	v.add_child(_button_row([["取消", _cancel_extract]]))
	_open_panel("提取素材", v)
	if not test:
		Game.set_setting("paths", "extracted_dir", dir)   # 先记下位置: 中断后下次启动接着用这个目录
	_ex_runner = ExtractRunner.new()
	add_child(_ex_runner)
	_ex_runner.step.connect(_on_extract_step)
	_ex_runner.finished.connect(_on_extract_finished.bind(dir))
	_ex_t0 = Time.get_ticks_msec()
	var err := _ex_runner.start(Game.extractor_path(), game, dir)
	if err != "":
		_on_extract_finished(false, err, dir)


## 各步大致耗时 (秒, 开发机实测, 只用来画进度条), 顺序同 tools/extractor.py 的 STEPS; 空时按步数平分
const EXTRACT_COST := {}


func _on_extract_step(k: int, n: int, name: String, desc: String) -> void:
	if _ex_test:
		print("EX STEP %d/%d %s" % [k, n, name])
	_ex_step.text = "（%d/%d）%s…" % [k, n, desc]
	if EXTRACT_COST.has(name):
		var done := 0.0
		var total := 0.0
		for x in EXTRACT_COST:
			if x == name:
				done = total
			total += float(EXTRACT_COST[x])
		_ex_bar.max_value = total
		_ex_bar.value = done
	else:
		_ex_bar.max_value = n
		_ex_bar.value = k - 1


func _process(_d: float) -> void:
	if _ex_runner and is_instance_valid(_ex_time):
		var s := (Time.get_ticks_msec() - _ex_t0) / 1000
		_ex_time.text = "已用时 %d:%02d　（可以随时取消，下次接着提取）" % [s / 60, s % 60]


func _cancel_extract() -> void:
	if _ex_runner:
		_ex_runner.finished.disconnect(_on_extract_finished)
		_ex_runner.queue_free()   # _exit_tree 里结束提取程序
		_ex_runner = null
	if _ex_test:
		get_tree().quit(1)
		return
	_ask_extract()


func _on_extract_finished(ok: bool, msg: String, dir: String) -> void:
	var log_path := _ex_runner.log_path if _ex_runner else ""
	if _ex_runner:
		_ex_runner.queue_free()
		_ex_runner = null
	if _ex_test:
		print("EX %s %s ready=%s" % ["PASS" if ok and Game.extract_complete(dir) else "FAIL", msg, Game.extract_complete(dir)])
		get_tree().quit(0 if ok else 1)
		return
	if ok:
		_open_panel("提取完成", _body_label("素材已经提取好了，游戏将重新启动。"))
		await get_tree().create_timer(1.5).timeout
		var args := OS.get_cmdline_args()
		if not OS.get_cmdline_user_args().is_empty():
			args += PackedStringArray(["--"]) + OS.get_cmdline_user_args()
		OS.set_restart_on_exit(true, args)   # 重启: 光标、界面动画等启动时读过的素材全部重新加载
		get_tree().quit()
		return
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	v.add_child(_body_label("提取没有成功：\n" + msg, 15, Color(0.62, 0.16, 0.12)))
	if log_path != "":
		v.add_child(_body_label("详细日志：" + log_path, 13, Color(BROWN, 0.75)))
	v.add_child(_button_row([["重试", func(): _run_extract(Game.game_dir, dir, false)], ["更换游戏目录…", _pick_game_dir], ["离开", func(): _do_action("quit")]]))
	_open_panel("提取素材", v)


func _pick_game_dir() -> void:
	var fd := FileDialog.new()
	fd.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.use_native_dialog = true
	fd.title = "选择《轩辕剑外传·苍之涛》安装目录"
	fd.canceled.connect(fd.queue_free)
	fd.dir_selected.connect(func(dir: String):
		fd.queue_free()
		_on_game_dir_selected(dir))
	add_child(fd)
	fd.popup_centered(Vector2i(640, 420))


func _on_game_dir_selected(dir: String) -> void:
	var err := Game.check_game_dir(dir)
	Game.game_dir = dir
	if err != "":
		_ask_game_dir(err)
		return
	Game.set_setting("paths", "game_dir", dir)
	if not Game.data_ready() and Game.extractor_path() != "":
		_ask_extract()
		return
	_locked = false
	_close_panel()
	Game.play_music(TITLE_MUSIC, 2.0)


func _show_settings() -> void:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.add_child(_label("音乐音量", Game.font_menu, 18, BROWN))
	var sl := HSlider.new()
	sl.min_value = 0.0
	sl.max_value = 1.0
	sl.step = 0.05
	sl.value = Game.get_setting("audio", "music", 0.8)
	sl.custom_minimum_size = Vector2(240, 20)
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sl.value_changed.connect(func(x): Game.set_setting("audio", "music", x))
	row.add_child(sl)
	v.add_child(row)
	var fs := CheckBox.new()
	fs.text = "全屏显示"
	fs.add_theme_font_override("font", Game.font_menu)
	fs.add_theme_font_size_override("font_size", 18)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		fs.add_theme_color_override(c, BROWN)
	fs.button_pressed = Game.get_setting("video", "fullscreen", false)
	fs.toggled.connect(func(on): Game.set_setting("video", "fullscreen", on))
	v.add_child(fs)
	# 高清画质: 只有一种高清包时标出是 2K 还是 4K; 2K / 4K 包都在时后面跟二选一
	var hrow := HBoxContainer.new()
	hrow.add_theme_constant_override("separation", 14)
	var hdb := CheckBox.new()
	if Game.hd_dirs.is_empty() and not Game.packs_loaded:
		hdb.text = "高清素材（Real-ESRGAN 放大，需先 make hd）"
	else:
		hdb.text = "高清画质" if Game.hd_dirs.size() > 1 else "高清画质（%dK）" % Game.hd_scale
	_brown_check(hdb)
	hdb.button_pressed = Game.hd
	hdb.disabled = Game.hd_dirs.is_empty()
	hrow.add_child(hdb)
	var res := {}   # 倍数 → 2K / 4K 选项
	if Game.hd_dirs.size() > 1:
		var grp := ButtonGroup.new()
		for k in [2, 4]:
			var r := CheckBox.new()
			r.text = "%dK" % k
			r.button_group = grp
			_brown_check(r)
			r.button_pressed = Game.hd_scale == k
			r.disabled = not Game.hd
			r.toggled.connect(func(on):
				if on:
					Game.set_hd(Game.hd, k)
					Game.set_setting("video", "hd_res", k))
			hrow.add_child(r)
			res[k] = r
	hdb.toggled.connect(func(on):
		Game.set_hd(on, Game.hd_scale)
		for r in res.values():
			r.disabled = not on
		Game.set_setting("video", "hd", on))
	v.add_child(hrow)
	var enb := CheckBox.new()
	enb.text = "画面增强（技能光效泛光、调色、暗角；关闭 = 原版画面）"
	enb.add_theme_font_override("font", Game.font_menu)
	enb.add_theme_font_size_override("font_size", 18)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		enb.add_theme_color_override(c, BROWN)
	enb.button_pressed = bool(Game.get_setting("video", "enhance", false))
	enb.toggled.connect(func(on): Game.set_setting("video", "enhance", on))
	v.add_child(enb)
	v.add_child(HSeparator.new())
	var note := _label(Game.DISCLAIMER, Game.font_body, 12, Color(BROWN, 0.85))
	note.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	note.custom_minimum_size = Vector2(400, 0)
	note.add_theme_constant_override("line_spacing", 4)
	v.add_child(note)
	_open_panel("設　定", v)


# ---------------- 工具 ----------------

func _brown_check(b: CheckBox) -> void:
	b.add_theme_font_override("font", Game.font_menu)
	b.add_theme_font_size_override("font_size", 18)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color"]:
		b.add_theme_color_override(c, BROWN if c != "font_disabled_color" else Color(BROWN, 0.45))


func _label(text: String, font: Font, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _fade_to(a: float, t: float) -> void:
	create_tween().tween_property(_fade, "color:a", a, t)


func _debug_click(kv: PackedStringArray) -> void:
	await get_tree().create_timer(float(kv[0])).timeout
	var p := Vector2(float(kv[1]), float(kv[2]))
	# 界面坐标 → 窗口坐标 (canvas_items 拉伸)
	var wp: Vector2 = get_viewport().get_final_transform() * p
	Input.warp_mouse(wp)
	var mm := InputEventMouseMotion.new()
	mm.position = wp
	Input.parse_input_event(mm)
	await get_tree().process_frame
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.double_click = kv.size() > 3 and kv[3] == "dbl" and pressed
		e.position = wp
		Input.parse_input_event(e)
		if not is_inside_tree():
			return   # 点击已经切走了场景 (例: 双击读档)
		await get_tree().process_frame
	print("TITLE_CLICK %s" % str(p))


func _debug_args() -> void:
	var shot := ""
	var delay := 3.0
	var select := -1
	var press := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			shot = a.substr(7)
		elif a.begins_with("--shot-delay="):
			delay = float(a.substr(13))
		elif a.begins_with("--shot-select="):
			select = int(a.substr(14))
		elif a == "--shot-press":
			press = true
		elif a.begins_with("--title-click="):   # 调试: --title-click=秒:x:y[:dbl] 在界面坐标 (800×600) 注入一次真实鼠标点击 (经过 GUI)
			_debug_click.call_deferred(a.substr(14).split(":"))
	if shot == "":
		return
	if select >= 0:
		_sel = select
		_refresh()
	if press:
		await get_tree().create_timer(1.5).timeout
		_choose()
	await get_tree().create_timer(delay).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(shot)
	get_tree().quit()


func _open_workshop_debug() -> void:
	var ws := WorkshopScreen.new()
	add_child(ws)
	for a in OS.get_cmdline_user_args():   # --ws-keys=down,enter,shift+up,delete: 依次模拟按键 (每个间隔 0.4 秒)
		if a.begins_with("--ws-keys="):
			await get_tree().create_timer(1.0).timeout
			for k in a.substr(10).split(","):
				if k == "wait":   # 等 1.5 秒 (网络请求 / 下载)
					await get_tree().create_timer(1.5).timeout
					continue
				var ev := InputEventKey.new()
				ev.pressed = true
				ev.shift_pressed = k.begins_with("shift+")
				ev.keycode = OS.find_keycode_from_string(k.trim_prefix("shift+").capitalize())
				Input.parse_input_event(ev)
				await get_tree().create_timer(0.4).timeout
