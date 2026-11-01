extends Node
## 手柄验收: 用 Input.parse_input_event 发模拟的手柄事件 (走和真手柄一样的事件流), 看地图、菜单、镜头的反应
## make test-pad → PAD PASS / FAIL

var field: Node
var _fail := 0


func _ok(c: bool, what: String) -> void:
	print("  %s %s" % ["ok  " if c else "FAIL", what])
	if not c:
		_fail += 1


func _btn(b: int, down: bool) -> void:
	var e := InputEventJoypadButton.new()
	e.button_index = b as JoyButton
	e.pressed = down
	Input.parse_input_event(e)


func _axis(a: int, v: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.axis = a as JoyAxis
	e.axis_value = v
	Input.parse_input_event(e)


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _tap(b: int) -> void:
	_btn(b, true)
	await _wait(0.1)
	_btn(b, false)
	await _wait(0.2)


func _ready() -> void:
	while field.player == null or field.busy:
		await get_tree().process_frame
	await _wait(1.0)
	var p: FieldActor = field.player

	var p0: Vector3 = p.gpos
	_axis(JOY_AXIS_LEFT_X, 0.9)
	await _wait(0.6)
	_axis(JOY_AXIS_LEFT_X, 0.0)
	await _wait(0.2)
	_ok(p.gpos.distance_to(p0) > 20.0, "左摇杆走路")
	_ok(not Input.is_key_pressed(KEY_RIGHT), "松开摇杆: 方向键抬起")
	p0 = p.gpos
	_axis(JOY_AXIS_LEFT_X, 0.2)
	await _wait(0.4)
	_axis(JOY_AXIS_LEFT_X, 0.0)
	_ok(p.gpos.distance_to(p0) < 1.0, "小幅度不算方向")
	p0 = p.gpos
	_btn(JOY_BUTTON_DPAD_UP, true)
	await _wait(0.5)
	_btn(JOY_BUTTON_DPAD_UP, false)
	await _wait(0.2)
	_ok(p.gpos.distance_to(p0) > 20.0, "十字键走路")

	field.cam.set_mode(1, 1)
	var y0: float = field.cam.angt.y
	_btn(JOY_BUTTON_LEFT_SHOULDER, true)
	await _wait(0.3)
	_btn(JOY_BUTTON_LEFT_SHOULDER, false)
	await _wait(0.1)
	var dy := fposmod(field.cam.angt.y - y0 + 180.0, 360.0) - 180.0
	_ok(dy > 2.0, "LB 转镜头, 偏航增加 (%.1f)" % dy)
	y0 = field.cam.angt.y
	_axis(JOY_AXIS_RIGHT_X, 1.0)
	await _wait(0.3)
	_axis(JOY_AXIS_RIGHT_X, 0.0)
	await _wait(0.1)
	dy = fposmod(field.cam.angt.y - y0 + 180.0, 360.0) - 180.0
	_ok(dy < -2.0, "右摇杆转镜头 (%.1f)" % dy)
	await _tap(JOY_BUTTON_RIGHT_STICK)
	_ok(is_equal_approx(field.cam.angt.y, 0.0), "按右摇杆: 镜头回正")

	var run0: bool = field.running
	await _tap(JOY_BUTTON_LEFT_STICK)
	_ok(field.running != run0, "按左摇杆: 跑走切换")
	await _tap(JOY_BUTTON_BACK)
	_ok(State.minimap_mode == 1, "Back: 小地图切换")
	State.minimap_mode = 0
	field.minimap.apply_mode()

	await _tap(JOY_BUTTON_Y)
	await _wait(0.5)
	var menu: Node = field.get_node_or_null("MainMenu")
	_ok(menu != null, "Y 开主菜单")
	if menu:
		var s0: int = menu._sel
		_axis(JOY_AXIS_LEFT_Y, 1.0)
		await _wait(0.08)
		_axis(JOY_AXIS_LEFT_Y, 0.0)
		await _wait(0.3)
		_ok(menu._sel != s0, "摇杆移动菜单光标 (%d → %d)" % [s0, menu._sel])
		s0 = menu._sel
		_btn(JOY_BUTTON_DPAD_DOWN, true)
		await _wait(0.9)
		_btn(JOY_BUTTON_DPAD_DOWN, false)
		await _wait(0.2)
		_ok(menu._sel != s0, "按住连发 (%d → %d)" % [s0, menu._sel])
		await _tap(JOY_BUTTON_B)
		await _wait(1.0)
		_ok(field.get_node_or_null("MainMenu") == null, "B 关主菜单")
	await _tap(JOY_BUTTON_START)
	await _wait(0.5)
	_ok(field.get_node_or_null("MainMenu") != null, "Start 开主菜单")
	# 物品页说明栏: 功能说明 (恢复量等) 和描述合并显示
	State.items[3001] = 3
	menu = field.get_node("MainMenu")
	menu._open_page(0)
	await _wait(1.0)
	var rows := MainMenu.note_rows(Battle.obj(3001))
	_ok(rows.size() == 2 and rows[0][0] == "恢复生命200", "说明栏: 第一行功能说明, 后面描述")
	var shot := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--pad-shot="):
			shot = a.substr(11)
	if shot != "":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(shot)
	# 标题画面: 十字键一下走一格 (默认 ui_* 动作也绑了手柄键, 不能走两格)
	var tree := get_tree()
	reparent(tree.root)
	tree.change_scene_to_file("res://scenes/title.tscn")
	await _wait(3.0)
	var title: Node = tree.current_scene
	var t0: int = title._sel
	await _tap(JOY_BUTTON_DPAD_DOWN)
	_ok(title._sel == t0 + 1, "标题: 十字键走一格 (%d → %d)" % [t0, title._sel])
	await _tap(JOY_BUTTON_DPAD_UP)
	_ok(title._sel == t0, "标题: 走回来")
	print("PAD PASS" if _fail == 0 else "PAD FAIL %d" % _fail)
	get_tree().quit()
