extends Node
## 创意工坊 T1 验收测试 (field 收到 --mod-t1-test 时挂上): --mod=../mods/t1-tweaks --map=12201
## tweaks.json: 1. 解析结果 (键码 / 页 / 镜头范围 / 飘字样式和贴图)  2. 大地图按 Esc 打开主菜单并到系统页, 菜单里 Esc 一路退出不会再打开
## 3. 滚轮: 往上滚俯仰角 −2、距离 −100, 往下滚反过来; 到下限停住  4. Tab 回到滚动前  5. 带 Shift 的 Esc 不开菜单
## 6. 坏的 tweaks.json 整个 mod 拒绝加载。结果打印 T1 PASS / T1 FAIL

var field: Node
var fails: Array = []


func _ready() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print("T1 %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		fails.append(what)


func _key(code: int, shift := false) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	ev.shift_pressed = shift
	Input.parse_input_event(ev)
	var up := ev.duplicate()
	up.pressed = false
	Input.parse_input_event(up)
	for i in 3:
		await get_tree().process_frame


func _wheel(up: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
	ev.pressed = true
	ev.position = Vector2(400, 300)
	Input.parse_input_event(ev)
	await get_tree().process_frame
	await get_tree().process_frame


func _run() -> void:
	await get_tree().create_timer(3.0).timeout
	while field.busy:
		await get_tree().process_frame
	var tw: Dictionary = Mods.tweaks
	_check(tw.has("field_menu") and KEY_ESCAPE in tw.field_menu.keys and tw.field_menu.page == "system", "field_menu 解析: Esc → 系统页")
	_check(tw.has("camera") and tw.camera.wheel == "both" and is_equal_approx(tw.camera.pitch_min, 8.0), "camera 解析")
	var dn: Dictionary = tw.get("damage_numbers", {})
	_check(not dn.is_empty() and dn.digits is Texture2D and dn.font == null and dn.kinds.size() == 2
		and dn.kinds.hp.splash is Texture2D and dn.kinds.hp.color.is_equal_approx(Color.html("#f4ecdc")), "damage_numbers 解析: 数字图 + 墨迹, 只换 hp / heal")
	# Esc 开菜单
	await _key(KEY_ESCAPE, true)
	_check(not field.has_node("MainMenu"), "Shift+Esc 不开菜单")
	await _key(KEY_ESCAPE)
	var mm: Node = field.get_node_or_null("MainMenu")
	_check(mm != null and mm.page == "system", "Esc 打开主菜单的系统页")
	await _key(KEY_ESCAPE)   # 系统页 → 主菜单
	await _key(KEY_ESCAPE)   # 关菜单
	for i in 5:
		await get_tree().process_frame
	_check(not field.has_node("MainMenu") and not field.busy, "菜单里按 Esc 退出后不会马上又打开")
	# 滚轮
	var p0: float = field.cam.angt.x
	var d0: float = field.cam.dt
	await _wheel(true)
	_check(is_equal_approx(field.cam.angt.x, clampf(p0 - 2.0, minf(8.0, p0), maxf(60.0, p0))) and is_equal_approx(field.cam.dt, clampf(d0 - 100.0, minf(900.0, d0), maxf(3000.0, d0))),
		"往上滚: 俯仰 %.1f → %.1f, 距离 %.0f → %.0f" % [p0, field.cam.angt.x, d0, field.cam.dt])
	for i in 60:
		await _wheel(true)
	_check(field.cam.angt.x >= minf(8.0, p0) - 0.01 and field.cam.dt >= minf(900.0, d0) - 0.01, "一直往上滚停在下限 (俯仰 %.1f, 距离 %.0f)" % [field.cam.angt.x, field.cam.dt])
	await _wheel(false)
	await _key(KEY_TAB)
	_check(is_equal_approx(field.cam.angt.x, p0) and is_equal_approx(field.cam.dt, d0) and is_equal_approx(field.cam.angt.y, 0.0), "Tab 回到滚动前的俯仰 / 距离, 偏航 0")
	# 坏的 tweaks.json
	var bad := {"mod.json": '{"id": "kp.t1-bad"}'.to_utf8_buffer(), "tweaks.json": '{"camera": {"wheel": "spin"}}'.to_utf8_buffer()}
	var m := {"id": "kp.t1-bad", "status": "pending", "error": ""}
	_check(Mods._parse_tweaks(m, bad) == null and m.status == "error", "坏的 tweaks.json 拒绝加载: %s" % m.error)
	var bad2 := {"tweaks.json": '{"damage_numbers": {"font": "x.ttf"}}'.to_utf8_buffer()}
	var m2 := {"id": "kp.t1-bad2", "status": "pending", "error": ""}
	_check(Mods._parse_tweaks(m2, bad2) == null, "字体文件不存在拒绝加载: %s" % m2.error)
	print("T1 PASS" if fails.is_empty() else "T1 FAIL %s" % str(fails))
	get_tree().quit()
