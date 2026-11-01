extends Node
## 小地图验收: 三态 (M / 双击 / 按钮)、拖动、楼层、事件中隐藏、存读档字段、各状态截图 (--minimap-shots=目录)
## make test-minimap → MINIMAP PASS / FAIL

var field: Node
var _fail := 0


func _ok(c: bool, what: String) -> void:
	print("  %s %s" % ["ok  " if c else "FAIL", what])
	if not c:
		_fail += 1


func _frames(n := 3) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(dir: String, name: String) -> void:
	if dir == "":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(dir.path_join(name + ".png"))


func _ready() -> void:
	while field.player == null or field.busy:
		await get_tree().process_frame
	await get_tree().create_timer(1.0).timeout
	var dir := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--minimap-shots="):
			dir = a.substr(16)
	var mm: Minimap = field.minimap
	await _frames()
	_ok(mm.visible and mm.rect == Rect2i(10, 30, 150, 140), "进图默认窗口 (10,30)–(160,170)")
	_ok(mm._tex != null, "有图片")
	await _shot(dir, "1_opaque")

	mm.cycle()
	await _frames()
	_ok(mm.translucent and State.minimap_mode == 1 and mm.visible, "M: 半透明")
	await _shot(dir, "2_translucent")
	mm.cycle()
	await _frames()
	_ok(State.minimap_mode == 2 and State.test_flag(8041) and not mm.visible, "M: 隐藏")
	await _shot(dir, "3_hidden")
	mm.cycle()
	await _frames()
	_ok(State.minimap_mode == 0 and not mm.translucent and not State.test_flag(8041) and mm.visible, "M: 回到不透明")

	mm.tick(Vector2(50, 180), false)
	_ok(mm.cursor_q() == 9 and mm.blocks_walk(), "第二个按钮 (l+30..50, b..b+20): 指针, 不走路")
	_ok(mm.press(Vector2(50, 180), false) and mm.translucent, "第二个按钮: 半透明")
	_ok(mm.press(Vector2(50, 180), false) and not mm.translucent, "第二个按钮: 恢复")
	_ok(mm.press(Vector2(30, 180), false) and State.minimap_mode == 2, "第一个按钮: 隐藏")
	mm.cycle()
	await _frames()
	field.cam.set_mode(1, 1)
	field.cam.set_angles(field.cam.angt.x, 120, field.cam.angt.z)
	_ok(mm.press(Vector2(70, 180), false) and is_equal_approx(field.cam.angt.y, 0.0), "第三个按钮: 镜头回正")
	_ok(not mm.press(Vector2(95, 180), false), "按钮区外不吃点击")

	_ok(mm.press(Vector2(60, 80), false), "窗口内按下")
	mm.tick(Vector2(60, 80), true)
	_ok(mm.cursor_q() == 12 and mm.blocks_walk(), "拖动中: 四向光标")
	mm.tick(Vector2(160, 130), true)
	_ok(mm.rect.position == Vector2i(110, 80), "跟着鼠标移动")
	mm.tick(Vector2(160, 130), false)
	_ok(not mm.blocks_walk(), "松开结束拖动")
	await _frames()
	await _shot(dir, "4_dragged")
	mm.press(Vector2(160, 130), true)
	_ok(State.minimap_mode == 1, "双击: 切下一态")
	mm.cycle()
	mm.cycle()

	State.set_flag(8080, true)
	await _frames()
	_ok(not mm.visible, "事件中不画")
	State.set_flag(8080, false)
	await _frames()

	var t0: Texture2D = mm._tex
	mm.set_floor(2)
	_ok(State.map_floor == 2 and mm._tex != null and mm._tex != t0, "楼层 2 换图")
	await _frames()
	await _shot(dir, "5_floor2")
	mm.set_floor(9)
	_ok(mm._tex == null, "没有的楼层: 不画图")
	await _frames()
	mm.set_floor(1)

	State.minimap_mode = 1
	var d: Dictionary = State.to_dict()
	_ok(int(d.minimap_mode) == 1 and int(d.map_floor) == 1, "存档字段")
	State.minimap_mode = 0

	# 天书放置时 M 开关的小地图 (0x4a21cc)
	State.set_flag(9, true)   # 主菜单「天书」
	State.money = 999999
	State.wood = 9999
	State.metal = 9999
	State.coal = 9999
	field.open_menu()
	await get_tree().process_frame
	var menu: Node = field.get_node("MainMenu")
	menu._open_page(4)
	await get_tree().create_timer(2.0).timeout
	var ts: MenuTianshu = menu._sub
	ts._start_place(1)
	await _frames(10)
	ts._place_key(KEY_M)
	_ok(ts._plan_on, "天书放置: M 打开平面图")
	await _frames(10)
	await _shot(dir, "6_tianshu_plan")
	ts._place_key(KEY_M)
	_ok(not ts._plan_on, "天书放置: M 关闭")
	print("MINIMAP PASS" if _fail == 0 else "MINIMAP FAIL %d" % _fail)
	get_tree().quit()
