extends Node
## 地图探索 + 事件演出 (原版: 地图更新 0x47a3f6, 事件 VM 0x405fcd, 进地图 0x467ece, 移动碰撞 0x468a89)
## 坐标: 事件脚本 / NPC / 事件框 / 碰撞都是地图坐标 (游戏单位); 渲染位置 = (地图坐标 + 偏移) × 0.01, 偏移 = WLD 包围盒最小角
## 画面按原版左手系水平翻转显示 (同技能预览)
## 数据: extracted/game/ (tools/export_game.py: events/*.json, maps.json, collision/, new_game.json, names.json;
##       tools/export_actors.py: actors/)

const TICK := 1.0 / 35.0
const RUN_SPEED := 14.0          # 跑 (默认) 14 单位/帧, 动作 12; R 切换走 5 单位/帧, 动作 4 (0x47c0bc)
const WALK_SPEED := 5.0
const WORLD_SPEED := 8.0         # 世界地图 (地图标志 0x80) 8 单位/帧, 跑步动作
const RUN_POSE := 12
const WALK_POSE := 4
const IDLE_POSE := 0
const PROBE := 50.0              # 空格调查: 前方 50 单位的探测框, 或 3D 距离 ≤ 100 (0x47c770)
const TALK_DIST := 100.0
const CLICK_DIST := 350.0        # 鼠标点击 NPC 对话的水平距离上限 (0x47ac47)
const FOOT := 30.0               # 脚下方盒 (x±30, y..y+100, z±30) 与阻挡盒检测

var maps: Dictionary = {}
var names: Dictionary = {}
var newgame: Dictionary = {}
var _event_files := {}
var warned_ops := {}

var map_id := 0
var map_info: Dictionary = {}
var menu_thumb: Image
var _motes: Node3D   # 画面增强: 环境粒子 (跟着镜头注视点)
var offset := Vector3.ZERO
var actors := {}                 # 角色号 → FieldActor
var player: FieldActor
var cutscene := false
var busy := false                # 事件执行中 (原版事件期间暂停地图更新)
var running := true              # 跑 / 走
var steps := 0                   # 遇敌步数
var cam: OrigCamera
var dialog: Dialog

var _w: SubViewport
var _world: Node3D
var _stage: Node3D
var _floor: StaticBody3D
var _visual_floor: StaticBody3D   # 画面上的地面 (场景模型), 物理层 2: 只用来把人物模型画在看得见的地面上
var _boxes: Array = []           # 阻挡盒 [AABB] (地图坐标)
var _cam3d: Camera3D
var _fade: ColorRect
var _fade_a := 0.0
var _hud: Label
var minimap: Minimap
var _in_battle := false
var _event_cam := {}
var _acc := 0.0
var _video: VideoStreamPlayer
var _rmb := false
var _dbg_mouse := Vector2.INF
var _dbg_key := Vector2i.ZERO


## 调试: 用注入事件移动鼠标 (不动真实光标), 按 800×600 界面坐标
var _dbg_mouse_ui := Vector2(400, 300)
var _dbg_mouse_on := false


func _dbg_mouse_move(to: Vector2, secs: float, click: bool) -> void:
	_dbg_mouse_on = true
	var from := _dbg_mouse_ui
	var n := maxi(int(secs * 30.0), 1)
	var sz := Vector2(get_viewport().get_visible_rect().size)
	for k in n:
		_dbg_mouse_ui = from.lerp(to, smoothstep(0.0, 1.0, float(k + 1) / n))
		var ev := InputEventMouseMotion.new()
		ev.position = _dbg_mouse_ui / Vector2(800, 600) * sz
		ev.global_position = ev.position
		Input.parse_input_event(ev)
		await get_tree().process_frame
	if click:
		for pressed in [true, false]:
			var b := InputEventMouseButton.new()
			b.button_index = MOUSE_BUTTON_LEFT
			b.pressed = pressed
			b.position = _dbg_mouse_ui / Vector2(800, 600) * sz
			b.global_position = b.position
			Input.parse_input_event(b)
			await get_tree().process_frame


## 鼠标位置 (800×600 界面坐标)
func _mouse_ui() -> Vector2:
	return get_viewport().get_mouse_position() / Vector2(get_viewport().get_visible_rect().size) * Vector2(800, 600)


## 启动调试参数; 读档后重进场景时不再套用 (否则 --map / --menu 会盖掉刚读的档, 无限重进), 只留截图参数
var _from_save := false


const VIEWER_ARGS := ["--map=12403", "--pos=1000,230,500", "--flags=1,2,3,7", "--member-lv=40", "--battle=41", "--no-encounter"]


func _args() -> PackedStringArray:
	if _from_save:
		return PackedStringArray()
	var a := OS.get_cmdline_user_args()
	if Game.skill_viewer:
		a.append_array(PackedStringArray(VIEWER_ARGS))
	return a


func _ready() -> void:
	_from_save = State.just_loaded
	State.just_loaded = false
	if not _from_save:
		for la in OS.get_cmdline_user_args():
			if la.begins_with("--load="):   # 调试: 从存档开始 (测试后面的章节, 不用每次从序章跑起); 其他参数照常套用
				State.load_slot(int(la.substr(7)))
				State.just_loaded = false
			elif la.begins_with("--snapshot="):   # 编辑器播放预览: 回到某个剧情事件开始前的那一刻 (再配 --event= 播它)
				State.load_snapshot(la.substr(11))
	_load_data()
	_build()
	var start := -1
	var forced_map := 0
	for a in _args():
		if a.begins_with("--event="):
			start = int(a.substr(8))
		elif a.begins_with("--map="):
			forced_map = int(a.substr(6))
	if State.map_id == 0 and forced_map == 0:
		new_game()
		if start < 0:
			start = 1   # 新游戏: 事件 1 → call_event 10 (序章开场)
	if forced_map:
		if State.map_id == 0:
			new_game()
		var fp := _first_pos(forced_map)
		for a2 in _args():
			if a2.begins_with("--pos="):
				var v := a2.substr(6).split(",")
				fp = Vector3(float(v[0]), float(v[1]), float(v[2]))
		await change_map(forced_map, fp, 0)
	elif State.map_id != 0:
		await change_map(State.map_id, State.player_pos, State.player_facing)
		if not State.cam.is_empty():
			cam.from_save(State.cam)
			State.cam = {}
	for a3 in _args():
		if a3.begins_with("--flags="):   # 调试: 预置剧情旗标 (逗号分隔)
			for f in a3.substr(8).split(","):
				State.set_flag(int(f), true)
	for a4 in _args():   # 播放预览: 镜头还原成快照那一刻 (同 camera_restore 的做法, 注视主角 +100)
		if a4.begins_with("--snapshot="):
			var sj: Variant = JSON.parse_string(FileAccess.get_file_as_string(a4.substr(11)))
			if sj is Dictionary and (sj as Dictionary).has("cam") and player:
				var c: Dictionary = sj.cam
				for ch in 3:
					cam.set_mode(ch, 1)
				cam.set_target(player.gpos + Vector3(0, 100, 0))
				cam.set_angles(float(c.ang[0]), float(c.ang[1]), float(c.ang[2]))
				cam.set_distance(float(c.d))
				cam.zoom_kt = float(c.k)
	if start >= 0 and _args().has("--preview-talk"):
		# 播放预览借用了别的事件的快照 (这个对话事件自动通关没触发到): 照原版「上前对话」——车芸站到挂这个事件的 NPC 旁边
		# (四个方向里第一个能调查到它的), 再走 _start_npc_event (双方转身规则同原版)
		var npc: FieldActor = null
		for a5 in actors.values():
			if a5 != player and a5.event_id == start and not a5.hidden:
				npc = a5
				break
		if npc and player:
			for off in [Vector3(0, 0, 90), Vector3(0, 0, -90), Vector3(90, 0, 0), Vector3(-90, 0, 0)]:
				player.set_game_pos(npc.gpos + off)
				player.face_point(npc.gpos)
				if is_investigate_hit(npc, player.gpos, player.facing):
					break
			cam.set_target(player.gpos + Vector3(0, 100, 0))
			_start_npc_event(npc)
			start = -1
	if start >= 0:
		if _args().has("--quit-after-event"):   # 调试 / 录像: 播完起始事件 (含其中的战斗) 就打印用时退出
			var t0 := Time.get_ticks_msec()
			_debug_args()
			await run_event(start)
			while busy:
				await get_tree().process_frame
			print("EVENT_DONE %d t=%.1f player=%s" % [start, (Time.get_ticks_msec() - t0) / 1000.0, str(player.gpos.round()) if player else "-"])
			get_tree().quit()
			return
		run_event(start)
	_debug_args()
	for a in _args():
		if a.begins_with("--equip="):
			# 调试: --equip=角色:格:物品 (格 4/5 = 法宝)
			var e := a.substr(8).split(":")
			var eq: Array = State.equip.get(int(e[0]), [0, 0, 0, 0, 0, 0, 0, 0])
			while eq.size() < 8:
				eq.append(0)
			eq[int(e[1])] = int(e[2])
			State.equip[int(e[0])] = eq
		elif a.begins_with("--artifact-exp="):   # 调试: --artifact-exp=法宝:修练值 (预设修练值, 测结算的法宝升级)
			var e := a.substr(15).split(":")
			State.artifact_exp[int(e[0])] = int(e[1])
		elif a.begins_with("--menu="):   # 调试: 启动后打开主菜单的某页 (status / item / equip / system)
			var pg := a.substr(7)
			get_tree().create_timer(1.5).timeout.connect(func():
				open_menu()
				await get_tree().process_frame
				var mm := get_node_or_null("MainMenu")
				if mm and pg != "status":
					mm._open_page({"item": 0, "equip": 1, "qishu": 2, "jiguan": 3, "tianshu": 4, "jizai": 5, "system": 6}.get(pg, 0))
					if pg == "equip" and _args().has("--menu-choose"):
						mm._key_equip(KEY_ENTER))
		elif a.begins_with("--press="):   # 调试: --press=键名:秒 (例 space:2) 模拟按键
			var kp := a.substr(8).split(":")
			get_tree().create_timer(float(kp[1])).timeout.connect(func():
				var ev := InputEventKey.new()
				ev.keycode = OS.find_keycode_from_string(kp[0])
				ev.pressed = true
				Input.parse_input_event(ev)
				var ev2 := ev.duplicate()
				ev2.pressed = false
				Input.parse_input_event(ev2))
		elif a.begins_with("--video="):   # 调试: 2 秒后播放一段过场动画 (--video=文件名)
			get_tree().create_timer(2.0).timeout.connect(func(): play_video(a.substr(8)))
		elif a.begins_with("--battle-at="):   # 调试: --battle-at=秒:战场 到时开一场战斗 (走正常的战后流程, 测连续战斗计数)
			var ba := a.substr(12).split(":")
			get_tree().create_timer(float(ba[0])).timeout.connect(func(): if not busy: _encounter(int(ba[1])))
		elif a == "--snow":   # 调试: 2 秒后开下雪 (同事件 0x6b)
			get_tree().create_timer(2.0).timeout.connect(func(): set_weather(true))
		elif a.begins_with("--ts-init"):   # 调试: 天书初始房舍 (+ --ts-init=ID: 再建一座鬼神阵, 位置 0 放这个居民)
			State.ts_houses = [{"type": 1, "pos": [5577, 1000, 6404], "seq": 1, "row": 7, "col": 7, "orient": 0, "angle": 45.0},
				{"type": 8, "pos": [4861, 1000, 6209], "seq": 2, "row": 6, "col": 4, "orient": 0, "angle": 45.0}]
			State.ts_residents = [{"id": 2040, "house": 0}]
			if a.contains("="):
				var gid := int(a.get_slice("=", 1))
				State.ts_houses.append({"type": 9, "pos": [6000, 1000, 7000], "seq": 3, "slots": [gid]})
				State.ts_residents.push_front({"id": gid, "house": 3})
		elif a.begins_with("--tip-test="):   # 调试: 2 秒后弹上方提示
			get_tree().create_timer(2.0).timeout.connect(func(): show_top_tip(a.substr(11)))
		elif a == "--park-mouse":   # 调试: 录制时界面不读真实光标 (鼠标停在画面外, 除非用 --mouse 移动)
			_dbg_mouse_on = true
			_dbg_mouse_ui = Vector2(-100, -100)
		elif a.begins_with("--hold="):   # 调试: --hold=键名:开始秒:持续秒 按住一个键 (录制用)
			var kh := a.substr(7).split(":")
			var ev := InputEventKey.new()
			ev.keycode = OS.find_keycode_from_string(kh[0])
			get_tree().create_timer(float(kh[1])).timeout.connect(func():
				ev.pressed = true
				Input.parse_input_event(ev))
			get_tree().create_timer(float(kh[1]) + float(kh[2])).timeout.connect(func():
				var up := ev.duplicate()
				up.pressed = false
				Input.parse_input_event(up))
		elif a.begins_with("--mouse="):   # 调试: --mouse=秒:x:y[:移动秒[:click]] 把鼠标平滑移到界面坐标 (800×600), 可选最后点一下 (录制用)
			var mv := a.substr(8).split(":")
			get_tree().create_timer(float(mv[0])).timeout.connect(func(): _dbg_mouse_move(
				Vector2(float(mv[1]), float(mv[2])), float(mv[3]) if mv.size() > 3 else 0.0, mv.size() > 4 and mv[4] == "click"))
		elif a.begins_with("--teleport="):   # 调试: --teleport=秒:x,y,z 到时把主角移过去
			var tp := a.substr(11).split(":")
			var v := tp[1].split(",")
			get_tree().create_timer(float(tp[0])).timeout.connect(func():
				if player:
					player.set_game_pos(Vector3(float(v[0]), float(v[1]), float(v[2])))
					if v.size() > 3:
						player.set_facing(float(v[3])))
		elif a.begins_with("--face="):
			get_tree().create_timer(1.0).timeout.connect(func(): if player: player.set_facing(float(a.substr(7))))
		elif a.begins_with("--shop="):   # 调试: 打开商店 (--shop=物品,物品…; 加 --shop-sell 直接进卖)
			var goods := Array(a.substr(7).split(",")).map(func(x): return int(x))
			get_tree().create_timer(1.5).timeout.connect(func():
				if _args().has("--shop-prompt"):   # 走真实开店流程 (先问买 / 卖)
					open_shop(goods)
					return
				var sh := Shop.new()
				sh.goods = goods
				sh.selling = _args().has("--shop-sell")
				add_child(sh))
		elif a.begins_with("--res="):   # 调试: 资源 (--res=金钱,金属,木材,煤炭)
			var v := a.substr(6).split(",")
			State.money = int(v[0])
			State.metal = int(v[1])
			State.wood = int(v[2])
			State.coal = int(v[3])
		elif a.begins_with("--fame="):   # 调试: 怪物认识度 (--fame=id:进度,id:进度)
			for kv in a.substr(7).split(","):
				Fame.add_monster(int(kv.get_slice(":", 0)), int(kv.get_slice(":", 1)))
		elif a.begins_with("--hurt="):   # 调试: 队员掉血 (--hurt=百分比), 测试回复类奇术 / 物品
			for mem in [1, 2, 3]:
				var md := State.member(mem)
				md.hp = int(md.hp_max) * int(a.substr(7)) / 100
		elif a.begins_with("--give="):
			State.give_item(int(a.substr(7)), 1)
		elif a.begins_with("--warp="):
			# 调试: 1 秒后 (或 --warp-delay=秒) 换到 --warp=地图:x,y,z (测试读取画面)
			var wd := 1.0
			for a5 in _args():
				if a5.begins_with("--warp-delay="):
					wd = float(a5.substr(13))
			await get_tree().create_timer(wd).timeout
			var wp := a.substr(7).get_slice(":", 1).split(",")
			var from_map := map_id
			var from_pos := player.gpos if player else Vector3.ZERO
			await change_map(int(a.substr(7).get_slice(":", 0)), Vector3(float(wp[0]), float(wp[1]), float(wp[2])), 0)
			if _args().has("--warp-back"):   # 再换回来、再过去, 测缓存
				await get_tree().create_timer(1.0).timeout
				await change_map(from_map, from_pos, 0)
				await get_tree().create_timer(1.0).timeout
				await change_map(int(a.substr(7).get_slice(":", 0)), Vector3(float(wp[0]), float(wp[1]), float(wp[2])), 0)
		elif a.begins_with("--member-lv="):
			# 调试: 队员 (车芸) 直接升到指定等级 (按成长表逐级加)
			var lv := int(a.substr(12))
			var t0 := State.tech
			var tt0 := State.tech_total
			for mi in [1, 2, 3]:   # 三人都升 (嬴诗 / 桓远之没入队时也先记上)
				var m := State.member(mi)
				State.add_exp(mi, State.exp_threshold(lv - 1) - int(m.exp))
			State.tech = t0   # 调试升级不加木甲技术点数 (机关页首次打开时按等级累计)
			State.tech_total = tt0
	for a in _args():
		if a.begins_with("--battle="):
			for f in a.get_slice("=", 1).get_slice(":", 1).split(","):
				if f != "":
					State.set_flag(int(f), true)   # --battle=N:1,2 同时让嬴诗 (旗标 2) 入队
			for a4 in _args():
				if a4.begins_with("--member-exp="):   # 调试: 车芸的累计经验 (测试升级)
					State.member(1).exp = int(a4.substr(13))
			busy = true
			await start_battle(int(a.substr(9).get_slice(":", 0)))
			busy = false
	if Game.demo:
		await get_tree().create_timer(3.0).timeout
		while busy:
			await get_tree().process_frame
		await get_tree().create_timer(4.0).timeout
		await fade(6, Color.BLACK, 0, 255)
		Game.stop_music(1.0)
		await get_tree().create_timer(1.2).timeout
		print("AP QUIT via end-of-demo")
		get_tree().quit()


func _load_data() -> void:
	var base := Game.extracted_dir.path_join("game")
	maps = JSON.parse_string(FileAccess.get_file_as_string(base.path_join("maps.json")))
	names = JSON.parse_string(FileAccess.get_file_as_string(base.path_join("names.json")))
	Mods.apply(maps, names.people, names.items)   # 创意工坊: mod 的 NPC 追加进地图角色表, 名字加进人名表, 物品名加进物品名表
	newgame = JSON.parse_string(FileAccess.get_file_as_string(base.path_join("new_game.json")))
	Mods.apply_newgame(newgame)   # 创意工坊: 改开局 (金钱 / 物品 / 装备 / 技能 / 开局队伍) 和车芸的地图模型
	# 全部常驻角色的原始记录 (MAPS.DAT 段 2): 角色被脚本搬到别的地图 (place_actor_map) 时, 用它的 ACT / 标志 / 朝向生成
	for mid in maps:
		for r in maps[mid].get("npcs", []):
			base_recs[int(r.actor)] = r
	for r in newgame.get("actors", []):
		base_recs[int(r.actor)] = r


## 新游戏 (0x4701e8): MAPS.DAT 段 1 (金钱 300、道具、装备、技能) + 全局角色 (车芸为主控), 置旗标 1 (车芸入队)
func new_game() -> void:
	State.reset()
	var ini: Dictionary = newgame.init
	State.money = int(ini.money)
	for it in ini["items"]:
		State.give_item(int(it), 1)
	for k in ini.equip:
		State.equip[int(k)] = ini.equip[k].map(func(x): return int(x))
	for k in ini.skills:
		State.skills[int(k)] = ini.skills[k].map(func(x): return int(x))
	State.set_flag(1, true)
	for m in newgame.get("party", []):   # 创意工坊改开局: 开局就在队的队员 (旗标 1/2/3)
		State.set_flag(int(m), true)
	State.party = [1]


func event_code(eid: int) -> Array:
	if eid >= Mods.EVENT_BASE:
		return Mods.event_code(eid)
	if Mods.has_override(eid):   # 创意工坊方案改过的原版事件
		return Mods.override_code(eid)
	var fn := "talks1-1"
	if eid > 5000:
		fn = "talks3"
	elif eid > 2000:
		fn = "talks2"
	elif eid > 1500:
		fn = "talks1-4"
	elif eid > 1000:
		fn = "talks1-3"
	elif eid > 500:
		fn = "talks1-2"
	if not _event_files.has(fn):
		_event_files[fn] = JSON.parse_string(FileAccess.get_file_as_string(
			Game.extracted_dir.path_join("game/events/%s.json" % fn)))
	var d: Dictionary = _event_files[fn]
	var key: Variant = d.events.get(str(eid))
	if key == null:
		return []
	return d.codes[key]


func person_name(n: int) -> String:
	return str(names.people.get(str(n), ""))


# ---------------- 画面 ----------------

func _build() -> void:
	var vlayer := CanvasLayer.new()
	vlayer.layer = -1
	add_child(vlayer)
	_w = SubViewport.new()
	_w.own_world_3d = true
	_w.msaa_3d = Viewport.MSAA_4X
	add_child(_w)
	# 原版左手系: 3D 画面水平翻转显示
	var rect := TextureRect.new()
	rect.texture = _w.get_texture()
	rect.flip_h = true
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vlayer.add_child(rect)
	var fit := func(): _w.size = Game.view_px()
	fit.call()
	get_window().size_changed.connect(fit)

	_world = Node3D.new()
	_w.add_child(_world)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	_w.add_child(we)
	Enhance.apply(env, rect)   # 画面增强 (设定开关, 默认原版)
	_env = env
	Enhance.add_sun(_world, env)
	_cam3d = Camera3D.new()
	_cam3d.near = 0.1
	_cam3d.far = 500.0
	_w.add_child(_cam3d)
	Enhance.add_dof(_cam3d)   # 画面增强: 景深 (远景模糊)
	cam = OrigCamera.new(_cam3d)
	# 新游戏默认 (0x467221): 俯仰 10, 偏航 0, 距离 1250; 之后由各 change_map 事件脚本自己设定
	cam.ang = Vector3(10, 0, 0)
	cam.angt = cam.ang
	cam.d = 1250.0
	cam.dt = 1250.0

	dialog = Dialog.new()
	dialog.field = self
	add_child(dialog)

	var top := CanvasLayer.new()
	top.layer = 8
	add_child(top)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(_fade)
	minimap = Minimap.new()
	minimap.field = self
	top.add_child(minimap)
	top.move_child(minimap, 0)   # 在淡入淡出遮罩之下
	_build_menu_scroll(top)
	_hud = Label.new()
	_hud.position = Vector2(8, 4)
	_hud.add_theme_font_override("font", Game.font_body)
	_hud.add_theme_font_size_override("font_size", 13)
	_hud.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	_hud.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_hud.add_theme_constant_override("outline_size", 3)
	top.add_child(_hud)


## 原版混合模式 4 (exe 0x41676c, INVDESTALPHA / INVSRCCOLOR, 关 Z 写): 后台缓冲 16 位无 alpha → 结果 = 目标 × (1 − 源色)。
## 例: 驿站路面的车辙 (近黑贴图, 几乎只留下细线)、昆仑界的贴地阴影。
## 原版在 gamma 空间按字节运算, 所以贴图不解码 (不用 source_color), 算完 1 − 源色再转线性交给 blend_mul。
## 顶点雾 (0x412d6e) 不分物体类型: D3D 先把源色推向雾色再混合, 所以远处这类面会把底色压暗并偏色, 雾量公式同 OrigFog。
## 在 OrigFog 之后画 (render_priority): 原版地面的雾在它之前就画好了
static var _sh_inv_mul: Shader


static func _inv_mul_material(tex: Texture2D) -> ShaderMaterial:
	if _sh_inv_mul == null:
		OrigFog.register_globals()
		_sh_inv_mul = Shader.new()
		_sh_inv_mul.code = """shader_type spatial;
render_mode unshaded, blend_mul, depth_draw_never, cull_disabled, fog_disabled;
uniform sampler2D tex : filter_linear_mipmap_anisotropic, repeat_enable;
global uniform vec3 orig_fog_col;
global uniform vec3 orig_fog_par;   // far_z, off_v, start_v
void fragment() {
	vec3 s = clamp(texture(tex, UV).rgb * COLOR.rgb, 0.0, 1.0);
	float sz = orig_fog_par.x / (orig_fog_par.x - 200.0) * (1.0 - 200.0 / max(-VERTEX.z * 100.0, 1.0));
	float vv = sz - orig_fog_par.y;
	float a = (vv > orig_fog_par.z && vv < 1.0) ? (vv - orig_fog_par.z) / (1.0 - orig_fog_par.z) : 0.0;
	vec3 k = vec3(1.0) - mix(s, orig_fog_col, a);
	ALBEDO = mix(k / 12.92, pow((k + 0.055) / 1.055, vec3(2.4)), step(0.04045, k));
}
"""
	var m := ShaderMaterial.new()
	m.shader = _sh_inv_mul
	m.render_priority = 127
	m.set_shader_parameter("tex", tex)
	return m


## vcolor: 场景 (WLD) 的「贴图 × 顶点色」—— 原版 TL 顶点 diffuse = 模型顶点色, DX6 默认 MODULATE (逆向见 tools/wld2gltf.py vertex_color);
## 暗场景的明暗烘在顶点色里。D3D 按字节相乘, 所以顶点色当 sRGB 处理 (实测: 贴图 200 × 顶点色 128 → 99, 当线性则 147)
func unshade(root: Node, cull := false, vcolor := false) -> void:
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(s)
			if mat is StandardMaterial3D:
				var sm := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
				sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				sm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC   # 斜看的墙面 / 地面不糊成条纹
				for ta in OS.get_cmdline_user_args():   # 调试: --tint-tex=贴图号 把用这张贴图的面染红
					if ta.begins_with("--tint-tex=") and sm.resource_name.begins_with("tex" + ta.substr(11)):
						sm.albedo_color = Color(1, 0.2, 0.2)
				var raw_blend := OS.get_cmdline_user_args().has("--no-scene-blend")   # 调试 / 录对比: 模式 2、4 的面按不透明画 (修复前的样子)
				if sm.resource_name.contains("_blend") and not raw_blend:   # WLD flags & 0xf == 2: 原版 SRCALPHA / INVSRCALPHA, 关 Z 写; alpha = 贴图 × 顶点 (tools/wld2gltf.py)
					sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					sm.vertex_color_use_as_albedo = true
					sm.vertex_color_is_srgb = true
				if sm.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
					# 镂空贴图 (衣服挂饰、头发边、树叶): 远处缩小时 mipmap 把 alpha 平均掉, 镂空边缘逐帧时有时无 = 闪烁的光点;
					# 用 alpha-to-coverage + 抗锯齿边缘, 配合 MSAA 让镂空边缘平滑
					sm.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE_AND_TO_ONE
					sm.alpha_antialiasing_edge = 0.3
				if sm.albedo_texture == null:
					sm.vertex_color_use_as_albedo = true   # 无贴图的模型靠顶点色 (出入口箭头等)
				if vcolor:
					sm.vertex_color_use_as_albedo = true
					sm.vertex_color_is_srgb = true
				if cull:
					sm.cull_mode = BaseMaterial3D.CULL_BACK
				if sm.resource_name.contains("_mul") and not raw_blend:   # WLD flags & 0xf == 4 (tools/wld2gltf.py)
					mi.set_surface_override_material(s, _inv_mul_material(sm.albedo_texture))
					continue
				if sm.resource_name.ends_with("_add"):
					sm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
					sm.vertex_color_use_as_albedo = true   # 顶点 alpha 决定加法层亮度 (wld2gltf: 地面光斑等)
				mi.set_surface_override_material(s, sm)


func to_world(g: Vector3) -> Vector3:
	return (g + offset) * 0.01


func to_game(w: Vector3) -> Vector3:
	return w / 0.01 - offset


## 3D 位置 → UI 坐标 (800×600, 已考虑水平翻转)
func screen_pos(w: Vector3) -> Vector2:
	var p := _cam3d.unproject_position(w)
	var s := Vector2(_w.size)
	return Vector2((1.0 - p.x / s.x) * 800.0, p.y / s.y * 600.0)


# ---------------- 碰撞 (WLD 地面三角形 + 阻挡盒, 0x468a89) ----------------

## 碰撞地面 (WLD) 和画面上的地面不完全重合: 曲沃城整片碰撞面比石板路高约 14 单位 (34 个 NPC 有 27 个浮起 >10),
## 人物站在碰撞面上看起来浮空 (开了画面增强、影子落在真正的地面上时特别明显)。
## 逻辑位置 (gpos、碰撞、寻路) 不变, 只把模型往下画到画面地面 —— 在碰撞面下方 40 单位内找场景模型的面, 找不到就不动
func _build_visual_floor() -> void:
	if is_instance_valid(_visual_floor):
		_visual_floor.free()   # 立即删 (queue_free 要到帧末): 换图同一帧还留着, 射线会打到旧图的面
	_visual_floor = StaticBody3D.new()
	_visual_floor.collision_layer = 2
	_visual_floor.collision_mask = 0
	_world.add_child(_visual_floor)
	var faces := PackedVector3Array()
	for n in _stage.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		var xf := mi.global_transform
		var f := mi.mesh.get_faces()
		for i in f.size():
			f[i] = xf * f[i]
		faces.append_array(f)
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	_visual_floor.add_child(cs)


## 显示高度修正 (游戏单位, ≤ 0): 画面地面比碰撞地面低多少
func visual_dy(g: Vector3) -> float:
	if not is_instance_valid(_visual_floor):
		return 0.0
	# 脚下 5 个点 (中心 + 前后左右 20 单位) 各找一次, 取最高的面: 站在地台 / 台阶边上时中心射线会擦过边缘落到下面的地面,
	# 只看中心会把人拉进地台里 (用户反馈「有的房间人物嵌在地下」)
	var space := _world.get_world_3d().direct_space_state
	var best := -1e9
	for o in [Vector3.ZERO, Vector3(20, 0, 0), Vector3(-20, 0, 0), Vector3(0, 0, 20), Vector3(0, 0, -20)]:
		var q := PhysicsRayQueryParameters3D.create(to_world(g + o + Vector3(0, 5, 0)), to_world(g + o - Vector3(0, 40, 0)), 2)
		q.hit_back_faces = true
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			best = maxf(best, to_game(hit.position).y - g.y)
	if best < -1e8:
		return 0.0
	return minf(best, 0.0)


func _load_collision(wld: String) -> void:
	if _floor:
		_floor.free()   # 同上: 立即删, 免得新图贴地打到旧图的碰撞面
	_floor = StaticBody3D.new()
	_world.add_child(_floor)
	_boxes.clear()
	var f := FileAccess.open(Game.extracted_dir.path_join("game/collision/%s.bin" % wld), FileAccess.READ)
	if f == null:
		return
	var nt := f.get_32()
	var nb := f.get_32()
	var tri := f.get_buffer(nt * 36).to_float32_array()
	var verts := PackedVector3Array()
	verts.resize(nt * 3)
	for i in nt * 3:
		verts[i] = to_world(Vector3(tri[i * 3], tri[i * 3 + 1], tri[i * 3 + 2]))
	_floor_box = AABB()
	for i in verts.size():
		_floor_box = AABB(verts[i], Vector3.ZERO) if i == 0 else _floor_box.expand(verts[i])
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(verts)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	_floor.add_child(cs)
	var bx := f.get_buffer(nb * 24).to_float32_array()
	for i in nb:
		var mn := Vector3(bx[i * 6], bx[i * 6 + 1], bx[i * 6 + 2])
		var mx := Vector3(bx[i * 6 + 3], bx[i * 6 + 4], bx[i * 6 + 5])
		_boxes.append(AABB(mn, mx - mn))


## 地面高度: 在 (x, z) 处从 y_ref+dy+100 向下到 y_ref−100 找地面三角形 (地图坐标); 找不到返回 null
func floor_at(g: Vector3, y_ref: float, dy := 0.0) -> Variant:
	if _floor == null:
		return null
	var space := _world.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(to_world(Vector3(g.x, y_ref + dy + 100.0, g.z)),
		to_world(Vector3(g.x, y_ref - 100.0, g.z)), 1)   # 只查碰撞地面 (层 1), 不查画面地面 (层 2)
	q.hit_back_faces = true
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return null
	return to_game(hit.position).y


## 兼容旧调用
func ground_y(g: Vector3, y_hint: float) -> Variant:
	return floor_at(g, y_hint)


func _blocked_by_box(g: Vector3) -> bool:
	var foot := AABB(Vector3(g.x - FOOT, g.y, g.z - FOOT), Vector3(FOOT * 2, 100, FOOT * 2))
	for b in _boxes:
		if (b as AABB).intersects(foot):
			return true
	return false


## 两个盒子严格重叠 (0x4103bc: 三个轴都 B.max > A.min 且 B.min < A.max, 碰到边不算)
static func box_overlap(a: Array, b: Array) -> bool:
	for i in 3:
		if not (b[i + 3] > a[i] and b[i] < a[i + 3]):
			return false
	return true


## 角色碰撞盒 (0x46926a 里对每个角色做的变换): XB 乘 (1 + 缩放) (缩放 +0x1dc 为 0 时跳过), 绕 Y 轴转到朝向,
## 平移到位置 (+off), 取 8 个角的外包盒。弧度 = 角度 × 0.01745 (原版常量 0x4cd480);
## 旋转 (0x413755): wx = c·x − s·z, wz = s·x + c·z
func actor_box(a: FieldActor, off := Vector3.ZERO) -> Array:
	var bb: Array = a.xb()
	var k := a.scale.x - 1.0          # 缩放 +0x1dc (显示倍数 = 1 + 它)
	var mn := Vector3(bb[0], bb[1], bb[2])
	var mx := Vector3(bb[3], bb[4], bb[5])
	if k != 0.0:
		mn *= 1.0 + k
		mx *= 1.0 + k
	var r := a.facing * 0.01745
	var c := cos(r)
	var s := sin(r)
	var p := a.gpos + off
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for i in 8:
		var x: float = mx.x if i & 1 else mn.x
		var y: float = mx.y if i & 2 else mn.y
		var z: float = mx.z if i & 4 else mn.z
		var w := Vector3(c * x - s * z, y, s * x + c * z) + p
		lo = lo.min(w)
		hi = hi.max(w)
	return [lo.x, lo.y, lo.z, hi.x, hi.y, hi.z]


## 主角事件框 / 遇敌区检测用的盒子 (0x46d4f2 / 0x404f17): 当前动作 XB + 位置, 不缩放不旋转
func leader_box(g: Vector3) -> Array:
	var bb: Array = player.xb()
	return [bb[0] + g.x, bb[1] + g.y, bb[2] + g.z, bb[3] + g.x, bb[4] + g.y, bb[5] + g.z]


## 角色之间的碰撞 (主角输入移动 0x469a4f, 逆向确认)。返回 [结果, 角色]:
##   结果 −1 = 没被角色挡住 (接着做地图移动), ≥ 0 = 被挡住或碰到接触触发 (不再试单轴滑动)
## * 旗标 8052 置位时整段跳过 (没有角色碰撞也没有接触触发)
## * 跳过: id > 0xff00 (无符号, 等于 0xff00 仍参与)、隐藏 (标志 1)
## * 接触触发 (对方标志 0x10): 用 (dx, 0, dz) 测盒子, 碰到就返回该角色 (调用者启动它的事件)
## * 跳过自己、标志 4 (不挡路); 盒子 (dx, dy, dz) 不重叠 → 下一个; 第一个重叠的就结束循环
## * 重叠时 (对方没有可推动标志 0x2): 主角被弹开 0x469790 —— 朝背离对方的方向 3 单位, 撞到其他角色就不动, 否则走地图移动
## 未实现 (数据里没有角色带这些标志, 剧情指令也不设): 0x2 可推动 / 0x800000 / 0x800 可攀上 / 0x10000 可穿过、
##   实例 +0x1a8 bit 2 (含义未明)
func _actor_collide(me: FieldActor, d: Vector3) -> Array:
	if State.test_flag(8052):
		return [-1, null]
	for a in actors.values():
		if a.id > 0xff00:
			continue
		if a.hidden or a.flags & 0x1:
			continue
		if me == player and a.flags & 0x10 and box_overlap(actor_box(me, Vector3(d.x, 0, d.z)), actor_box(a)):
			return [0, a]
		if a == me or a.flags & 0x4:
			continue
		if not box_overlap(actor_box(me, d), actor_box(a)):
			continue
		if OS.get_cmdline_user_args().has("--trace-move"):
			print("ACTOR_BLOCK by=%d me=%s other=%s mebox=%s obox=%s" % [a.id, str(me.gpos.round()), str(a.gpos.round()), str(actor_box(me, d)), str(actor_box(a))])
		if me == player and not (a.flags & 0x2):
			_bounce(me, a, d.y)
		return [0, a]
	return [-1, null]


## 自动寻路测试用: 主角站到 g 时会不会和角色盒子重叠
func blocked_by_actor_at(g: Vector3, ignore: Array = []) -> bool:
	var box := actor_box(player, g - player.gpos)
	for a in actors.values():
		if a == player or a.id > 0xff00 or a.hidden or a.flags & 0x5 or a in ignore:
			continue
		if box_overlap(box, actor_box(a)):
			return true
	return false


## 被弹开 (0x469790): 方向 = 对方减自己 (坐标先截成整数, 只看 XZ), 与 (0,0,−1) 的夹角 (dir.x < 0 时取 360 − 角),
## 位移 = (cos, sin)((角 + 90) mod 360) × 3; 先查其他角色 (跳过 id > 0xff00、隐藏、自己; 不跳过对方), 撞到就不动
func _bounce(me: FieldActor, b: FieldActor, dy: float) -> void:
	var dir := Vector3(float(int(b.gpos.x) - int(me.gpos.x)), 0, float(int(b.gpos.z) - int(me.gpos.z))).normalized()
	var ang := rad_to_deg(acos(clampf(dir.dot(Vector3(0, 0, -1)), -1.0, 1.0)))
	if dir.x < 0:
		ang = 360.0 - ang
	var r := deg_to_rad(fmod(ang + 90.0, 360.0))
	var off := Vector3(cos(r) * 3.0, dy, sin(r) * 3.0)
	var box := actor_box(me, off)
	for c in actors.values():
		if c.id > 0xff00 or c.hidden or c.flags & 0x1 or c == me:
			continue
		if box_overlap(box, actor_box(c)):
			return
	_map_move(me, off)


## 地图移动 (0x468a89): 目标 XZ ≥ 0, 竖直线段找地面, 脚下方盒不碰阻挡盒 → 移过去并贴地
func _map_move(a: FieldActor, step: Vector3) -> bool:
	var np: Vector3 = a.gpos + step
	# 0x468a89 开头 (逆向确认): 带 0x40 (set_collision w=0) 且不带 0x1000000, 或旗标 8042 置位且带 0x8000 →
	# 直接位移: 不找地面、不查阻挡盒和边界 (浮台载人时角色 1 悬空跟着走)
	if (a.flags & 0x40 and not a.flags & 0x1000000) or (State.test_flag(8042) and a.flags & 0x8000):
		a.gpos = np
		a.position = to_world(np)
		return true
	if np.x < 0 or np.z < 0:
		return false
	var y: Variant = floor_at(np, a.gpos.y, step.y)
	if y == null:
		return false
	np.y = y
	if _blocked_by_box(np):
		return false
	a.gpos = np
	a.position = to_world(np)
	a.position.y += visual_dy(np) * 0.01   # 画到看得见的地面上
	return true


## 主角移动 (0x47c291 / 0x47c2ca / 0x47c305): 先试整步; 只有被地图挡住 (−2) 时才依次试只走 x、只走 z (贴墙滑动);
## 被角色挡住就停下; 挡住它的角色带接触触发标志 0x10 (且没隐藏) → 启动它的事件 (0x47c345)
func try_move(a: FieldActor, d: Vector3) -> bool:
	for step in [d, Vector3(d.x, 0, 0), Vector3(0, 0, d.z)]:
		var res := _actor_collide(a, step)
		if int(res[0]) >= 0:
			var other: FieldActor = res[1]
			if a == player and other and not other.hidden and other.flags & 0x10 and other.event_id > 0:
				_start_npc_event(other)
			return false
		if _map_move(a, step):
			return true
	return false


# ---------------- 地图 ----------------

func _first_pos(mid: int) -> Vector3:
	var m: Dictionary = maps.get(str(mid), {})
	for n in m.get("npcs", []):
		if int(n.actor) == 1:
			return Vector3(n.pos[0], n.pos[1], n.pos[2])
	var bx: Array = m.get("boxes", [])
	if bx.size():
		var p: Array = bx[0].pos
		return Vector3(p[0] + 250, p[1], p[2] + 250)
	return Vector3(500, 0, 500)


## change_map (0x32): 当前角色写回常驻表, 载入新图并放置主控 (位置、朝向), 贴地
func change_map(mid: int, pos: Vector3, facing: float) -> void:
	dialog.close_all()
	_save_actors()
	var t_change := Time.get_ticks_msec()
	if mid != map_id or _stage == null:
		# 读取画面 (原版 0258 / 0272); 先画出来再开始读, 读完等进度条走满
		var ld := Loading.new()
		add_child(ld)
		await get_tree().process_frame
		await get_tree().process_frame
		await _load_map(mid, ld)
		await ld.finish()
		ld.queue_free()
		if OS.get_cmdline_user_args().has("--trace-events"):
			print("MAPCHANGE %d %dms" % [mid, Time.get_ticks_msec() - t_change])
	_spawn_player()
	# 世界地图 (地图标志 0x80, 四张大地图) 上主角 (角色 1) 画小: 缩放 +0x1dc 改成 −0.4 → 显示为 0.6 倍 (0x4787e3)
	var wa: FieldActor = actors.get(1)
	if wa:
		wa.scale = Vector3.ONE * (0.6 if int(map_info.get("flags", 0)) & 0x80 else 1.0)
	player.path.clear()
	player.set_game_pos(pos)
	player.set_facing(facing)
	if OS.get_cmdline_user_args().has("--trace-jump"):
		print("CHANGEMAP %d player=%d id=%d actors1=%s pos=%s" % [mid, player.get_instance_id(), player.id, str(actors.get(1).get_instance_id()) if actors.has(1) else "-", str(player.gpos.round())])
	State.map_id = mid
	MainMenu.sync_quest_tip()   # 设定「任务更新提示」→ 旗标 38 (进地图时同步, 0x4688cf)
	cam.origin = offset * 0.01
	cam.follow = null
	cam.set_mode(0, 1)
	cam.set_target(player.gpos + Vector3(0, 100, 0))
	cam.snap()
	# 地图标志 0x08: 进图就下雪 (12626 昆仑界冬之岛、13004 太恒山), 只维持到换地图
	set_weather(bool(int(map_info.get("flags", 0)) & 0x08), 800.0)
	steps = 0
	running = true
	await get_tree().process_frame


func _save_actors() -> void:
	for a in actors.values():
		if a == player:
			continue
		var r := State.actor_rec(a.id)
		r.map = map_id
		r.pos = [a.gpos.x, a.gpos.y, a.gpos.z]
		r.facing = a.facing
		r.hidden = a.hidden
		r.event = a.event_id


func _load_map(mid: int, ld: Loading = null) -> void:
	cam.set_type(1)   # 0x4683bb: 换地图时镜头类型回到 1
	# 0x467ece: 换到不在连续战斗地图列表里的地图时, 清除计数和旗标 18
	if State.test_flag(18) and not State.countdown_maps.has(mid):
		State.regs[1] = 0
		State.set_flag(18, false)
	for e in _anis.filter(func(x): return int(x.act) != 9200):
		if is_instance_valid(e.node):
			(e.node as Node).queue_free()
		_anis.erase(e)
	for a in actors.values():
		a.queue_free()
	actors.clear()
	player = null
	# 0x467901 读完地图文件后调 0x4041bd: 角色槽 0–3 (编号 0xff01–0xff04, 主角 / 队伍) 保留, 槽 4 起整块清零 (0xb00b78 起
	# 每 0x674 字节 memset), 手持物 (set_weapon_model 0x8a 写的 +0x184 挂点 / +0x5d0 物品 / +0x5d2 qq) 跟着清掉。
	# 剧情里的嬴诗 0x0002 等都在槽 4 起, 所以换图 / 读档后不再拿着武器 (以前一直保留, 嬴诗从序章 #61 起永远拿剑)
	for id in State.actors:
		if int(id) < 0xff01:
			(State.actors[id] as Dictionary).erase("held")
	if _stage:
		_stage.queue_free()
		_stage = null
	map_id = mid
	map_info = maps.get(str(mid), {})
	minimap.load_map(mid)
	var off: Array = map_info.get("offset", [0, 0, 0])
	offset = Vector3(off[0], off[1], off[2])
	if ld:
		ld.progress = 0.15
	if map_info.get("scene"):
		# 后台线程读场景 (主线程照常画读取画面)
		var t0 := Time.get_ticks_msec()
		_stage = await Game.load_glb_async(str(map_info.scene))
		if OS.get_cmdline_user_args().has("--trace-events"):
			print("LOAD stage %dms" % (Time.get_ticks_msec() - t0))
		if _stage:
			_world.add_child(_stage)
			# 背面剔除 (原版 0x41228a 全程 CULLMODE=CCW, 墙是单面的): 镜头转到墙外时看得进房间, 不会被墙背面挡住。
			# 画面水平翻转后, Godot 的 CULL_BACK 正好对应原版的 CCW。序章 15 张图逐张比对过, 没有丢几何体;
			# 调试: --no-cull 关掉 (verify_scene.md §1.2)
			unshade(_stage, not OS.get_cmdline_user_args().has("--no-cull"), true)
			_build_visual_floor()
			Enhance.light_world(_stage)   # 画面增强第二档: 场景接收人物影子
			_motes = Enhance.setup_map(_world, _env, mid, map_info, _motes)   # 第三档: 按地图类型的光照方向 / 环境粒子 / 冷暖
			_find_backdrop()
			_setup_scene_anim(str(map_info.scene).get_file().get_basename())
	if ld:
		ld.progress = 0.6
		await get_tree().process_frame
	var t1 := Time.get_ticks_msec()
	_load_collision(str(map_info.get("wld", "")))
	# 新加的碰撞体要过一个物理帧才进得了查询 (direct_space_state); 不等的话下面摆角色贴地查不到 / 查到乱的面,
	# 例: 华山山道 → 秦宫 (#1001) 秦穆公数据 y 431 被贴到 336, 嵌在王座台里 (用户反馈); 直接 --map 加载中间有等待所以没事
	await get_tree().physics_frame
	if _backdrop and (OS.get_cmdline_user_args().has("--trace-events") or autoplay):
		var half := maxf(_floor_box.size.x, _floor_box.size.z) * 0.5
		print("BACKDROP map=%d r=%.1f floor_half=%.1f %s" % [mid, _backdrop_r, half, "固定 (墙)" if half > 0 and _backdrop_r <= 1.5 * half else "跟随镜头"])
	if OS.get_cmdline_user_args().has("--trace-events"):
		print("LOAD collision %dms" % (Time.get_ticks_msec() - t1))
	t1 = Time.get_ticks_msec()
	if OS.get_cmdline_user_args().has("--load-bench"):
		var lst := _map_actor_glbs(mid)
		var tb := Time.get_ticks_msec()
		var sz := 0
		for r in lst:
			sz += FileAccess.get_file_as_bytes(Game.asset_path(str(r))).size()
			var nd := Game._build_glb(Game.asset_path(str(r)))
			if nd:
				nd.free()
		print("BENCH %d glbs %.1fMB sync %dms" % [lst.size(), sz / 1048576.0, Time.get_ticks_msec() - tb])
		t1 = Time.get_ticks_msec()
	# 预读这张图上角色的模型 (后台线程), 之后生成角色时直接复制
	await Game.preload_glbs(_map_actor_glbs(mid), func(k, n): if ld: ld.progress = 0.6 + 0.3 * k / maxf(n, 1))
	Game.quality_view(_w)
	_preload_neighbors(mid)   # 不 await: 后台预读相邻地图
	if OS.get_cmdline_user_args().has("--trace-events"):
		print("LOAD actors %dms" % (Time.get_ticks_msec() - t1))
	# 常驻角色表: MAPS.DAT 段 2 的初始记录, 被 State.actors (脚本改动 / 写回) 覆盖
	var recs := {}
	for r in map_info.get("npcs", []):
		recs[int(r.actor)] = r.duplicate()
	for aid in State.actors:
		var s: Dictionary = State.actors[aid]
		if s.has("map"):
			if int(s.map) == mid:
				if not recs.has(aid):
					# 被脚本搬到这张图、本图没有记录的角色 (place_actor_map): ACT 用它原始记录的 (例: 兔子箱 2461 记录在 13031, ACT 62),
					# 不是角色号 — 预读 _map_actor_glbs 也是这么取的
					var base: Dictionary = base_recs.get(aid, {})
					# 动作 / 标志也用原始记录: 例 7163 / 7164 (记录在 13030, ACT 16002 动作 4), 搬到小娥家后不是宝箱 (动作 0)
					recs[aid] = {"actor": aid, "act": int(base.get("act", aid)), "pose": int(base.get("pose", 0)), "facing": int(base.get("facing", 0)),
						"pos": [0, 0, 0], "event": int(base.get("event", 0)), "ai": 0, "flags": int(base.get("flags", 0x2000))}
			elif recs.has(aid):
				recs.erase(aid)
	for aid in recs:
		var r: Dictionary = recs[aid]
		var s2: Dictionary = State.actors.get(aid, {})
		var act := int(s2.get("act", r.act))
		if (act >= 12000 and act < 15000) or aid >= 0xff00 or aid == 0:
			continue  # 12000–14999 是整张场景 (WLD); 15000+ 是地图物件 (出入口箭头 16005、宝箱 16002、门…), 照常显示
		var a := _spawn(aid, act)
		var p: Array = s2.get("pos", r.pos)
		# 地图物件 (ACT 15000+: 建筑、出入口箭头、宝箱…) 照数据高度放, 不贴地: 碰撞地面比画面地形低, 贴地会把大地图上的城镇小屋压进地里
		a.set_game_pos(Vector3(p[0], p[1], p[2]), act < 15000)
		a.set_facing(float(s2.get("facing", r.facing)))
		if OS.get_cmdline_user_args().has("--trace-floor"):
			print("FLOOR %d act=%d data_y=%d snapped_y=%.0f wide=%s" % [aid, act, int(p[1]), a.gpos.y, str(floor_at(Vector3(p[0], p[1], p[2]), p[1], 1500.0))])
		a.flags = int(r.get("flags", 0))
		a.event_id = int(s2.get("event", r.event))
		a.ai = int(s2.get("ai", r.get("ai", 0)))
		if a.ai > 0:
			_npc_ai(a)   # 地图 NPC 走动脚本 (不 await)
		a.set_hidden(bool(s2.get("hidden", a.flags & 0x1)))
		var pose := int(s2.get("pose", r.get("pose", 0)))
		if pose:
			a.play(pose)
	if ld:
		ld.progress = 0.9
	play_map_music(0)
	var title: String = str(map_info.get("title", ""))
	_hud.text = title if title != "" else str(map_info.get("name", mid)).get_slice("_", 2)


## 从这张图能去的地图: 出入口 / NPC / 区域事件里的 change_map 目标 (跟进 call_event 两层)
func _neighbor_maps(mid: int) -> Array:
	var m: Dictionary = maps.get(str(mid), {})
	var todo: Array = []
	for key in ["boxes", "zones", "npcs"]:
		for r in m.get(key, []):
			if int(r.get("event", 0)) > 0:
				todo.append([int(r.event), 0])
	var seen := {}
	var out: Array = []
	while todo.size():
		var e: Array = todo.pop_back()
		if seen.has(e[0]):
			continue
		seen[e[0]] = true
		for ins in event_code(int(e[0])):
			match str(ins[1]):
				"change_map":
					var to := int(ins[2])
					if to != mid and not out.has(to) and maps.has(str(to)):
						out.append(to)
				"call_event":
					if int(e[1]) < 2:
						todo.append([int(ins[2]), int(e[1]) + 1])
	return out


## 地图 NPC AI (AI.GLL 里的「地图 NPC AI」脚本, battle.json ai[编号]; 指令见 tools/decompile_ai.py):
##   0x10 等待 n×10ms, 0x16 切换动作, 0x19 设朝向 (0x401646: 写 +0x1b0 当前角度), 0x1a 走路速度, 0x1d 走到 (x,y,z), 0x1e 等走完, 0x0b 若旗标跳转, 0x63 从头再来, 0xffff 返回
## 剧情 / 菜单进行中 (busy) 暂停; 角色被删 (换图) 就结束
var _npc_speed := 5.0   # 走路速度 [0x4d1140]: 所有 NPC 共用一个全局 (初值 5.0), 0x1a 改了不恢复, 换图也不重置

func _npc_ai(a: FieldActor) -> void:
	Battle.load_db()
	var code: Array = Battle.db.get("ai", {}).get(str(a.ai), [])
	if code.size() <= 1:
		return
	var at := {}
	for i in code.size():
		at[int(code[i][0])] = i
	var pc := 0
	var guard := 0
	while is_instance_valid(a) and a.is_inside_tree():
		if busy or a.hidden:
			await get_tree().create_timer(0.2).timeout
			continue
		if pc >= code.size():
			pc = 0
		var ins: Array = code[pc]
		pc += 1
		var op := int(ins[1])
		var args: Array = ins[2]
		guard += 1
		if guard > 200:   # 一圈里没有任何等待: 防止死循环卡住主线程
			guard = 0
			await get_tree().process_frame
		match op:
			0x10:
				guard = 0
				await get_tree().create_timer(int(args[0]) * 0.01).timeout
			0x16:
				if a.has_pose(int(args[0])):
					a.play(int(args[0]), true)
			0x19:
				a.set_facing(float(args[0]))
			0x1a:
				_npc_speed = float(args[0])
			0x1d:
				a.walk_to(Vector3(float(args[0]), float(args[1]), float(args[2])), _npc_speed)
			0x1e:
				guard = 0
				while is_instance_valid(a) and a.is_inside_tree() and a.is_moving():
					await get_tree().process_frame
			0x0b:
				if State.test_flag(int(args[0])) and ins[3].size():
					pc = at.get(int(ins[3][0]), pc)
			0x0a:
				if ins[3].size():
					pc = at.get(int(ins[3][0]), pc)
			0x63:
				pc = 0
				guard = 0
				await get_tree().process_frame
			0xffff:
				guard = 0
				await get_tree().create_timer(0.5).timeout
				pc = 0


## 后台预读相邻地图的场景和角色模型 (进图读完之后开始, 玩的时候慢慢读; 真的走过去时就直接用缓存)
var _bg_preload_id := 0
var _worst_dt := 0.0


func _preload_neighbors(mid: int) -> void:
	if OS.get_cmdline_user_args().has("--no-bg-preload"):
		return
	_bg_preload_id += 1
	var my := _bg_preload_id
	await get_tree().create_timer(1.0).timeout
	var t0 := Time.get_ticks_msec()
	var n := 0
	await Battle.load_db_async(get_tree())
	if my != _bg_preload_id or not is_inside_tree():
		return
	var bat := _battle_glbs(mid)   # 先读本图遇敌要用的: 比相邻地图来得早
	n += bat.size()
	await Game.preload_glbs(bat, Callable(), true)
	for nb in _neighbor_maps(mid):
		if my != _bg_preload_id or not is_inside_tree():
			return   # 又换图了: 停掉旧的
		var lst: Array = _map_actor_glbs(nb)
		var sc := str(maps.get(str(nb), {}).get("scene", ""))
		if sc != "":
			lst.push_front(sc)
		n += lst.size()
		await Game.preload_glbs(lst, Callable(), true)
	if OS.get_cmdline_user_args().has("--trace-events"):
		print("BGPRELOAD map=%d neighbors=%s glbs=%d %dms" % [mid, str(_neighbor_maps(mid)), n, Time.get_ticks_msec() - t0])


## 这张图随机遇敌用到的战场场景, 以及怪物和队员的全部模型组 (战斗动作常在别的组, 播到时才读会卡)
func _battle_glbs(mid: int) -> Array:
	var info: Dictionary = maps.get(str(mid), {})
	if not info.get("encounters", false):
		return []
	var acts := {}
	for m in State.party:
		acts[11 if int(m) == 1 else int(m)] = true   # 战斗模型 (_party_unit): 车芸用 11
		acts[int(State.actor_rec(int(m)).get("act", m))] = true
	var out: Array = []
	for z in info.get("zones", []):
		for b in z.battlefields:
			var bf: Dictionary = Battle.db.battlefields.get(str(int(b)), {})
			var sc := "scenes/%s.glb" % str(bf.get("scene", ""))
			if bf.get("scene") and not out.has(sc):
				out.append(sc)
			for e in bf.get("enemies", []):
				acts[int(e.id)] = true
	for act in acts:
		var p := Game.extracted_dir.path_join("game/actors/act_%d.json" % act)
		if not FileAccess.file_exists(p):
			continue
		var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(p))
		for g in meta.get("groups", []):
			if str(g.glb) != "@mod":
				out.append("game/actors/" + str(g.glb))
	return out


func _map_actor_glbs(mid: int) -> Array:
	# 只预读初始动作所在的模型组 (其余组在播到时才读)
	var acts := {}   # ACT → {动作: true}
	for r in maps.get(str(mid), {}).get("npcs", []):
		var st: Dictionary = State.actors.get(int(r.actor), {})
		acts.get_or_add(int(st.get("act", r.act)), {})[int(st.get("pose", r.get("pose", 0)))] = true
	for aid in State.actors:
		var st2: Dictionary = State.actors[aid]
		if int(st2.get("map", -1)) == mid:
			acts.get_or_add(int(st2.get("act", base_recs.get(aid, {}).get("act", aid))), {})[int(st2.get("pose", 0))] = true
	for m in State.party:
		acts.get_or_add(int(State.actor_rec(int(m)).get("act", m)), {})[0] = true
	var out: Array = []
	for act in acts:
		if act >= 12000 and act < 15000:
			continue
		var p := Game.extracted_dir.path_join("game/actors/act_%d.json" % act)
		if not FileAccess.file_exists(p):
			continue
		var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(p))
		var grs: Array = meta.get("groups", [])
		for q in acts[act]:
			var pm: Dictionary = meta.get("poses", {}).get(str(q), meta.get("poses", {}).get("0", {}))
			var g := int(pm.get("g", 0))
			if g < grs.size():
				out.append("game/actors/" + str(grs[g].glb))
	return out


func _spawn(aid: int, act: int) -> FieldActor:
	var a := FieldActor.new()
	_world.add_child(a)
	a.setup(self, aid, act)
	actors[aid] = a
	var h: Array = State.actors.get(aid, {}).get("held", [])
	if h.size() == 3:
		a.set_held(int(h[0]), int(h[1]), int(h[2]))
	return a


func _spawn_player() -> void:
	var leader := int(State.party[0]) if State.party.size() else 1
	if player and player.id == leader:
		return
	if actors.has(leader):
		player = actors[leader]
	else:
		# 模型: 存档里的角色记录 > 全局角色表 (MAPS.DAT 段 2, 新游戏的 actors; 原版车芸是 ACT 1) > 角色号
		player = _spawn(leader, int(State.actor_rec(leader).get("act", base_recs.get(leader, {}).get("act", leader))))
		# 隐藏标志跨换图保留: 原版读图 0x4041bd 只清角色槽 4 起, 主角 / 队伍槽 0–3 (含标志) 不动。
		# 剧情「hide_actor(车芸) → 换图」后都要自己 show_actor (5 处); 结局 #1612 隐藏车芸后换到太一圣殿, 以前车芸又冒出来叠在嬴诗身上 (用户反馈)
		player.set_hidden(bool(State.actor_rec(leader).get("hidden", false)))
	player.is_player = true
	player.flags |= 0x8000


func actor(id: int) -> FieldActor:
	if id == 0xff02 or id == 0xff01:
		return null
	return actors.get(id)


func place_actor(id: int, pos: Vector3) -> void:
	var a := actor(id)
	if a == null:
		return
	a.path.clear()
	a.set_game_pos(pos)


func place_actor_map(id: int, mid: int, pos: Vector3) -> void:
	var rec := State.actor_rec(id)
	rec.map = mid
	rec.pos = [pos.x, pos.y, pos.z]
	if mid == map_id:
		var a := actor(id)
		if a == null:
			# 例: 木工房出口事件 7206 把神秘兔子 2461 (记录在地图 13031, ACT 62, 隐藏) 搬到木工房再 show_actor
			var br: Dictionary = base_recs.get(id, {})
			a = _spawn(id, int(rec.get("act", br.get("act", id))))
			a.flags = int(br.get("flags", 0x2000))
			a.event_id = int(rec.get("event", br.get("event", 0)))
			a.set_facing(float(rec.get("facing", br.get("facing", 0))))
			a.set_hidden(bool(rec.get("hidden", int(br.get("flags", 0)) & 0x1)))
			var pose := int(rec.get("pose", br.get("pose", 0)))
			if pose:
				a.play(pose)
		a.path.clear()
		a.set_game_pos(pos)
	elif actors.has(id) and actors[id] != player:
		actors[id].queue_free()
		actors.erase(id)


func set_actor_hidden(id: int, h: bool) -> void:
	State.actor_rec(id).hidden = h
	var a := actor(id)
	if a:
		a.set_hidden(h)


## set_weapon_model (0x8a): 角色, 物品 (道具 ACT), qq, 挂点 (0 = 卸下)。主角 0xff01 指车芸
func set_weapon(id: int, item: int, qq: int, marker: int) -> void:
	var a := actor(id) if id != 0xff01 else player
	if a:
		a.set_held(item, qq, marker)
	State.actor_rec(id).held = [item, qq, marker] if marker > 0 else []


func heal_member(id: int, hp: int, mp: int, sp: int) -> void:
	State.heal_member(id, hp, mp, sp)


# ---------------- 音乐 / 视频 / 淡入淡出 ----------------

func play_music_track(track: int, fade_10ms: int) -> void:
	var f: String = str(names.music.get(str(track), ""))
	if f != "" and not f.ends_with(".wav"):
		Game.play_music(f, maxf(fade_10ms * 0.01, 0.5))
	elif f.ends_with(".wav"):
		Game.stop_music(maxf(fade_10ms * 0.01, 0.3))


func play_map_music(fade_10ms: int) -> void:
	var m: Variant = State.map_music.get(map_id, map_info.get("music"))
	if m is Array and m.size() and int(m[0]) > 0:
		play_music_track(int(m[0]), fade_10ms)


## fade (0x35): 遮罩 alpha 从 from 每帧移动 speed 到 to (0–255)
func fade(speed: int, col: Color, from: int, to: int) -> void:
	_fade_a = float(from)
	_fade.color = Color(col.r, col.g, col.b, _fade_a / 255.0)
	while not is_equal_approx(_fade_a, float(to)):
		await get_tree().process_frame
		if fast_forward():
			_fade_a = float(to)
		else:
			_fade_a = move_toward(_fade_a, float(to), maxf(speed, 1) * get_process_delta_time() / TICK)
		_fade.color = Color(col.r, col.g, col.b, _fade_a / 255.0)


func play_video(file: String) -> void:
	var p := Game.video_path(file)
	if not FileAccess.file_exists(p) or autoplay or OS.get_cmdline_user_args().has("--no-video"):   # --no-video: 调试跳过影片
		return
	var st := VideoStreamTheora.new()
	st.file = p
	_video = VideoStreamPlayer.new()
	_video.stream = st
	_video.set_anchors_preset(Control.PRESET_FULL_RECT)
	_video.expand = true
	var layer := CanvasLayer.new()
	layer.layer = 9
	add_child(layer)
	var black := ColorRect.new()
	black.color = Color.BLACK
	black.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(black)
	layer.add_child(_video)
	_video.play()
	Game.fit_video(_video, p)
	while _video.is_playing():
		await get_tree().process_frame
		if OS.get_cmdline_user_args().has("--trace-events") and Engine.get_process_frames() % 60 == 0:
			print("VIDEO fps=%d pos=%.1f" % [Engine.get_frames_per_second(), _video.stream_position])
		if Input.is_action_just_pressed("ui_accept") or Input.is_action_just_pressed("ui_cancel"):
			break
	layer.queue_free()
	_video = null


func fast_forward() -> bool:
	# 按住 Ctrl 快进剧情; 只在游戏窗口有焦点时生效 (否则在别的程序里按 Ctrl 也会快进)
	var ff := get_window().has_focus() and Input.is_key_pressed(KEY_CTRL)
	if ff and not _ff_logged and OS.get_cmdline_user_args().has("--trace-events"):
		_ff_logged = true
		print("FAST-FORWARD (Ctrl) t=%.1f" % (Time.get_ticks_msec() / 1000.0))
	return ff


var _ff_logged := false


# ---------------- 镜头 ----------------

## camera_restore (0x73): 回到事件开始时的镜头 (注视主角 +100), 插值方式 3 (0x8c 之后为瞬间)
func camera_restore(snap: bool) -> void:
	var ang: Vector3 = _event_cam.get("ang", cam.angt)
	for ch in 3:
		cam.set_mode(ch, 1 if snap else 3)
		cam.set_speed(ch, 8.0)
	if player:
		cam.set_target(player.gpos + Vector3(0, 100, 0))
	cam.set_angles(ang.x, ang.y, ang.z)
	cam.set_distance(_event_cam.get("d", cam.dt))
	cam.zoom_kt = _event_cam.get("k", 10.0)
	var t0 := Time.get_ticks_msec()
	while not cam.arrived() and Time.get_ticks_msec() - t0 < 4000:
		await get_tree().process_frame
	for ch in 3:
		cam.set_mode(ch, 1)


# ---------------- 事件 ----------------

var vms: Array = []      # 正在跑的事件 (自动通关看门狗诊断用)
var _event_depth := 0   # 同时在跑的事件数 (进图事件会在上一个事件还没跑完时开始; 用单个 bool, 里面的跑完会把 busy 提前清掉)


## 剧情快照 (--snap-dir=目录, 自动通关时打开): 每个事件第一次执行前, 记下那一刻的存档状态、所在地图、地图上在场的角色
## (编辑器按真实剧情顺序列事件、显示当时在场的人物、从这一刻播放预览)。文件 = <目录>/<事件号>.json, 已有的不覆盖
var _snap_dir := ""
var _snap_seq := 0


func _snapshot(eid: int) -> void:
	if _snap_dir == "":
		for a in _args():
			if a.begins_with("--snap-dir="):
				_snap_dir = a.substr(11)
				DirAccess.make_dir_recursive_absolute(_snap_dir)
		if _snap_dir == "":
			_snap_dir = "-"
	if _snap_dir == "-" or event_code(eid).is_empty():
		return
	var path := _snap_dir.path_join("%d.json" % eid)
	if FileAccess.file_exists(path):
		return
	_save_actors()
	State.map_id = map_id
	if player:
		State.player_pos = player.gpos
		State.player_facing = player.facing
	var cast: Array = []
	for a in actors.values():
		if a == player or a.hidden or not a.is_visible_in_tree():
			continue
		cast.append({"actor": a.id, "act": a.act, "pose": a.pose, "pos": [roundi(a.gpos.x), roundi(a.gpos.y), roundi(a.gpos.z)],
			"facing": roundi(a.facing), "name": person_name(a.id), "event": a.event_id})
	if player:
		cast.append({"actor": player.id, "act": player.act, "pose": player.pose, "player": true, "name": person_name(player.id),
			"pos": [roundi(player.gpos.x), roundi(player.gpos.y), roundi(player.gpos.z)], "facing": roundi(player.facing)})
	_snap_seq += 1
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		var stage := 0   # --snap-stage=N: 分段自动通关的第几段 (编辑器按它分章节)
		for a in _args():
			if a.begins_with("--snap-stage="):
				stage = int(a.substr(13))
		f.store_string(JSON.stringify({"eid": eid, "stage": stage, "time": Time.get_unix_time_from_system(), "seq": _snap_seq,
			"play_seconds": State.play_seconds, "map": map_id, "cast": cast, "state": State.to_dict(),
			"cam": {"ang": [cam.angt.x, cam.angt.y, cam.angt.z], "d": cam.dt, "k": cam.zoom_kt}}))


func run_event(eid: int, owner := 0xff02) -> void:
	_event_depth += 1
	busy = true
	event_took_control = false
	_event_cam = {"ang": cam.angt, "d": cam.dt, "k": cam.zoom_kt}
	var e := eid
	var guard := 0
	while e >= 0 and guard < 50 and not aborted:
		guard += 1
		if not events_run.has(e):
			_snapshot(e)
		events_run[e] = true
		var vm := EventVM.new(self, e, owner)
		vms.append(vm)
		await vm.run()
		vms.erase(vm)
		e = vm.next_event
		owner = 0xff02
	_event_depth -= 1
	if aborted:
		return
	if _event_depth > 0:
		return   # 外层事件还在跑: 不清 busy / 镜头
	busy = false
	cutscene = false
	State.set_flag(8015, false)   # 事件收尾 0x40b87d: 不管脚本清没清都清掉这两个 (8080 置位时不画光标)
	State.set_flag(8080, false)
	minimap.apply_mode()   # 0x40b869
	# 事件结束时原版清掉所有表情 (0x40b70d → 0x4165ec), 恢复原脸
	for a in actors.values():
		if a.expr_act:
			a.set_expression(0, 0)
	for ch in 3:
		cam.set_mode(ch, 1)
	if player and event_took_control:
		player.play(IDLE_POSE)   # 演出结束回到站立; 立刻结束的事件不打断主角的动作


# ---------------- 动画特效 (原版动画列表 0xa85480: add_ani 0x37 / 0x5b / 0x5c / 0x5d, del_ani 0x38 / 0x60, wait_ani 0x5f) ----------------
## 3D 特效 (all_magic 8xxx、地图物件 15xxx …) 用 Fx (tools/effects.py 生成, 键 "act_qq");
## ACT 9200 是回忆插图 (all_sys 0044 单张图第 qq 帧, 800×600), 画在 2D 层 (旁白模式时盖在黑底上)

var base_recs := {}             # 角色号 → MAPS.DAT 段 2 原始记录
var _anis: Array = []           # [{act, qq, node, gpos, to, speed, follow}]
var shake := false
var _narr: CanvasLayer
var _narr_bg: ColorRect


func add_ani(act: int, qq: int, gpos: Vector3, to: Variant = null, speed := 0.0, follow: FieldActor = null) -> void:
	var e := {"act": act, "qq": qq, "gpos": gpos, "to": to, "speed": speed, "follow": follow, "node": null}
	if act == 9200:
		var cg := TextureRect.new()
		cg.texture = Game.load_texture("ui/all_sys/0044_单张图_轩外单张图/%03d.png" % qq)
		cg.size = Vector2(800, 600)
		cg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		cg.modulate.a = 0.0
		_narr_layer().add_child(cg)
		create_tween().tween_property(cg, "modulate:a", 1.0, 0.4)
		e.node = cg
	else:
		e.node = Fx.spawn(_world, "%d_%d" % [act, qq], to_world(gpos), Basis(), _cam3d)
		if e.node and bool((e.node as Fx).data.get("loop", false)):
			(e.node as Fx).loop_forever = true
		if e.node == null:
			push_warning("缺少地图特效 %d_%d (make game-data)" % [act, qq])
	_anis.append(e)


func _narr_layer() -> CanvasLayer:
	if _narr == null:
		_narr = CanvasLayer.new()
		_narr.layer = 9
		add_child(_narr)
		_narr_bg = ColorRect.new()
		_narr_bg.color = Color.BLACK
		_narr_bg.size = Vector2(800, 600)
		_narr_bg.visible = false
		_narr.add_child(_narr_bg)
	return _narr


## narration_mode (0x5e): 1 = 只画黑底 + 动画 + 对话框, 不画地图 (画面状态 12); 0 = 恢复
func narration_mode(on: bool) -> void:
	_narr_layer()
	_narr_bg.visible = on


func _ani_match(e: Dictionary, act: int, qq: int) -> bool:
	return int(e.act) == act and int(e.qq) == qq


## del_ani (0x38) / del_ani_wait (0x60): 删掉 act/qq 相同的动画; 插图淡出
func del_ani(act: int, qq: int, wait := false) -> void:
	var tw: Tween = null
	for e in _anis.filter(func(x): return _ani_match(x, act, qq)):
		_anis.erase(e)
		if not is_instance_valid(e.node):
			continue
		var n: Node = e.node
		if n is TextureRect:
			tw = create_tween()
			tw.tween_property(n, "modulate:a", 0.0, 0.4)
			tw.tween_callback(n.queue_free)
		else:
			n.queue_free()
	if wait and tw:
		await tw.finished


## wait_ani (0x5f): 等 act/qq 的动画播完 (不循环的特效播完自动消失)
func ani_done(act: int, qq: int) -> bool:
	for e in _anis:
		if _ani_match(e, act, qq) and is_instance_valid(e.node):
			if e.node is Fx and (e.node as Fx).reached(0):
				continue
			return false
	return true


## 每逻辑帧: 跟随角色 / 按速度飞向终点 (速度 = 单位/帧)
func _ani_tick() -> void:
	for e in _anis.duplicate():
		if not is_instance_valid(e.node):
			_anis.erase(e)
			continue
		var n: Node = e.node
		if not (n is Node3D):
			continue
		if e.follow and is_instance_valid(e.follow):
			e.gpos = (e.follow as FieldActor).gpos
		elif e.to != null and float(e.speed) > 0.0:
			var to: Vector3 = e.to if e.to is Vector3 else (e.to as FieldActor).gpos
			e.gpos = (e.gpos as Vector3).move_toward(to, float(e.speed))
		(n as Node3D).global_position = to_world(e.gpos)


func clear_anis() -> void:
	for e in _anis:
		if is_instance_valid(e.node):
			(e.node as Node).queue_free()
	_anis.clear()


func _start_npc_event(a: FieldActor) -> void:
	if busy:
		return
	if player:
		player.face_point(a.gpos)
		player.play(IDLE_POSE)
	# 调查型 (0x400/0x800) 直接开始; 对话型除非 0x1000 不转身, NPC 面向主角
	if not (a.flags & 0xc00) and not (a.flags & 0x1000) and player:
		a.set_facing(player.facing + 180.0)
	run_event(a.event_id, a.id)


# ---------------- 战斗 / 商店 / 存档 (子系统待接入) ----------------

## 开始战斗 (0x51 → 0x43fb05): 战斗画面盖在地图上, 结束后回到地图 (原版 reload_map, 角色位置不变)
## 输了且该战不允许输 (FIGTALK 0x98 未置) → 游戏结束回标题; 允许输的剧情战继续
func start_battle(bf: int, story := false) -> void:
	if story and OS.get_cmdline_user_args().has("--skip-battles"):   # 调试: 剧情战直接算赢 (测剧情衔接用)
		print("SKIP BATTLE %d" % bf)
		return
	_hud.visible = false
	_in_battle = true
	# 战斗画面盖住地图, 但地图的 SubViewport 仍算可见, 不关的话每帧多渲染一遍整张地图
	_w.render_target_update_mode = SubViewport.UPDATE_DISABLED
	# 原版战斗画面单独绘制, 不受地图淡入淡出影响 (剧情常先淡出成黑再开战): 战斗期间隐藏地图的淡出遮罩, 战后恢复
	_fade.visible = false
	var b := Battle.new()
	for sa in OS.get_cmdline_user_args():   # 调试: --skill-test=技能号:角色号,...
		if sa.begins_with("--skill-test="):
			for e in sa.substr(13).split(","):
				b.skill_test.append([int(e.get_slice(":", 0)), int(e.get_slice(":", 1))])
			b.skill_testing = true
	if Game.skill_viewer or OS.get_cmdline_user_args().has("--skill-viewer"):
		var sv := SkillViewer.new()
		sv.bt = b
		b.viewer = sv
		b.add_child.call_deferred(sv)
	b.story = story   # 事件 start_battle 开的是剧情战 ([0x9253d4]=1, 0x409af5): 禁收化
	b.setup(bf, self)
	add_child(b)
	var in_event := State.test_flag(8080)   # 0x43fca6: 战斗中清掉, 不然剧情战里没有光标; 结束恢复 (0x440739)
	State.set_flag(8080, false)
	var r: String = await b.finished
	if in_event:
		State.set_flag(8080, true)
	var lose_ok := b.allow_lose
	b.queue_free()
	_in_battle = false
	_w.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	_fade.visible = true
	# 自动通关测试 (关了随机遇敌, 没有练级): 不允许输的战斗输了 → 三个队员都升 3 级, 落后最高等级 5 级以上的拉到 最高 − 5, 再打
	# (以前只升 State.party = [1] 即车芸: 一路被抬到 50 级, 嬴诗停在入队的 8 级, 第七段冬之岛白虎战 169 要嬴诗单挑, 连输 6 次)
	if autoplay and r == "lose" and not lose_ok and _ap_retry < 6:
		_ap_retry += 1
		var top := 0
		for m in [1, 2, 3]:
			top = maxi(top, int(State.member(m).lv))
		for m in [1, 2, 3]:
			var md := State.member(m)
			var lv := maxi(int(md.lv) + 3, top - 5)
			State.add_exp(m, State.exp_threshold(lv - 1) - int(md.exp))
			md.hp = md.hp_max
			md.mp = md.mp_max
			md.sp = md.sp_max
		print("AP BATTLE %d 输了, 三个队员升到 %s 重打" % [bf, str([1, 2, 3].map(func(x): return int(State.member(x).lv)))])
		_hud.visible = true
		await start_battle(bf, story)
		return
	_ap_retry = 0
	if r.begins_with("switch:"):   # 战斗脚本换战场 (0x9a)
		await start_battle(int(r.substr(7)), story)
		return
	_hud.visible = true
	if r == "lose" and not lose_ok:
		if autoplay:   # 自动通关: 重打 6 次还输 → 直接报卡住退出 (回标题后机器人脱离场景, 进程会一直挂着)
			print("AP BATTLE %d 重打 6 次还是输了" % bf)
			var ap := get_node_or_null("Autoplay")
			if ap:
				ap._finish("STUCK (战斗 %d 打不过)" % bf)
				return
			get_tree().quit()
			return
		abort_to_title()
		return
	play_map_music(0)
	# 战斗收尾 0x440924: 连续战斗模式下任何战斗结束都减 1, 回到地图后在上方显示剩余场数
	if State.test_flag(18) and int(State.regs[1]) > 0:
		State.regs[1] = int(State.regs[1]) - 1
		var n := int(State.regs[1])
		show_top_tip(Battle.countdown_text[0] % n if n != 0 else Battle.countdown_text[1])


## 上方提示 (Dialog.draw_top_tip)
func show_top_tip(t: String) -> void:
	if autoplay or OS.get_cmdline_user_args().has("--trace-events"):
		print("TIP " + t)
	var layer := CanvasLayer.new()
	layer.layer = 7
	add_child(layer)
	var c := Control.new()
	c.size = Vector2(800, 600)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(c)
	c.draw.connect(func(): Dialog.draw_top_tip(c, t))
	c.queue_redraw()
	get_tree().create_timer(2.0).timeout.connect(layer.queue_free)


## 商店 (0xca): 先问买还是卖 (0x45d518), 再进商店画面, 关掉后可以再选, 选「离开」结束
func open_shop(goods: Array) -> void:
	if autoplay:
		return
	while true:
		dialog.last_choice = -1
		Game.cancel_lock = 1   # 0x45d610 (开店) / 0x45e5dd (从买卖清单取消回来): 显示主提示前置 1
		dialog.show_prompt(Rect2(144, 300, 352, 96), " 客倌 您要买东西还是卖东西%N    %B买.  /  %B卖.  /  %B离开.")
		Game.warp_mouse(Vector2(230, 360))   # 0x45d646 / 0x45e610: 鼠标移到「买」上
		while dialog.is_open(0xff01):
			await get_tree().process_frame
		var ans := Game.take_answer(dialog.last_choice)   # 0x46559d
		Game.cancel_lock = 0   # 0x45e637: 回答之后清 0
		if ans not in [0, 1]:
			return
		var sh := Shop.new()
		sh.goods = goods.map(func(x): return int(x))
		sh.selling = ans == 1
		add_child(sh)
		await sh.closed
		if sh.left:
			return   # 右上角叉 (0x45d74d): 直接离开, 不再回主提示


## 存档界面 (0xcb, 休息点等): 直接打开主菜单的存档页
## 存档点 (op 0xcb 封印之蛋): 直接打开存档画面, 不经过主菜单、不检查禁存标志; 当场截图作缩略图
func open_save_menu() -> void:
	if autoplay:
		return
	await open_save_screen("save")


## 下雪 (事件 0x6b weather_effect → 0x409b64; 地图标志 0x08 进图自动下, 只有 12626 昆仑界冬之岛、13004 太恒山):
##   资源 ACT 8001 动作 2 (MGC00179: 25×25 面向镜头的方片, 贴图「雪花.bmp」加法混合, 61 帧左右飘动动画做在模型里)
##   500 片, 以中心 ±1500 随机位置在中心高度出生 (0x491707); 中心 = (镜头注视点 x/z, 主角高度 + 1000) (事件) 或主角 + 800 (进图 / 主角移动后 0x47c42d)
##   速度 (单位/毫秒): x = rand·0.00283 − 0.0205, y = −(1 + rand)·0.1049, z = rand·(−0.01992) − 0.0205 → 每秒下落 105–210、往 −x −z 斜飘
##   落到「开启时主角高度 + 10」以下就回到顶上重生 (动画从第 0 帧重播) (0x49193c)
const SNOW_N := 500
var _weather: Node3D
var _snow: Array = []   # [Fx, 位置 (游戏坐标), 速度 (单位/毫秒)]
var _snow_center := Vector3.ZERO
var _snow_floor := 0.0
var _snow_last := Vector3.INF


func set_weather(on: bool, top := 1000.0) -> void:
	if _weather:
		_weather.queue_free()
		_weather = null
	_snow.clear()
	State.set_flag(8061, on)
	if not on or player == null or not Fx.has("8001_2"):
		return
	_weather = Node3D.new()
	_world.add_child(_weather)
	_snow_center = Vector3(cam.f.x, player.gpos.y + top, cam.f.z)
	_snow_floor = player.gpos.y + 10.0
	_snow_last = player.gpos
	for i in SNOW_N:
		var fx := Fx.spawn(_weather, "8001_2", Vector3.ZERO, Basis.IDENTITY, _cam3d)
		if fx:
			fx.loop_forever = true
			var e := [fx, Vector3.ZERO, Vector3.ZERO]
			_snow_respawn(e)
			_snow.append(e)


func _snow_respawn(e: Array) -> void:
	e[1] = Vector3(_snow_center.x + (randf() - 0.5) * 3000.0, _snow_center.y, _snow_center.z + (randf() - 0.5) * 3000.0)
	e[2] = Vector3(randf() * 0.002830 - 0.0205, -(1.0 + randf()) * 0.1049, randf() * -0.019920 - 0.0205)
	(e[0] as Fx).restart()


func _weather_tick(delta: float) -> void:
	if _weather == null or player == null:
		return
	if player.gpos != _snow_last:   # 0x47c42d: 主角移动后生成中心跟到主角上方 800
		_snow_last = player.gpos
		_snow_center = player.gpos + Vector3(0, 800, 0)
	var ms := delta * 1000.0
	for e in _snow:
		e[1] += e[2] * ms
		if e[1].y < _snow_floor:
			_snow_respawn(e)
		(e[0] as Fx).global_position = to_world(e[1])


var autoplay := OS.get_cmdline_user_args().has("--autoplay")
var event_took_control := false
var aborted := false   # 游戏结束 / 回标题: 正在跑的事件全部停下 (避免场景销毁后协程继续访问)


func abort_to_title() -> void:
	if aborted:
		return
	aborted = true
	busy = true
	get_tree().change_scene_to_file.call_deferred("res://scenes/title.tscn")   # 本次事件执行过 script_begin / 对白 / 动作等演出指令 (事件 VM 设置)
var events_run := {}   # 执行过的事件号 (自动通关测试判断进度)
var _ap_retry := 0


func clear_actor_anis(id: int, key := "") -> void:
	for e in _anis.duplicate():
		if key != "" and "%d_%d" % [int(e.act), int(e.qq)] != key:
			continue
		if e.follow and is_instance_valid(e.follow) and (e.follow as FieldActor).id == id:
			if is_instance_valid(e.node):
				(e.node as Node).queue_free()
			_anis.erase(e)


# ---------------- 每帧 ----------------

## 场景动画 (wld2gltf, 逆向确认): 帧序列 = 原版场景动作的 AP 表, 每拍 1/35 秒切一帧不插值, 一轮 AP 数 + 1 拍;
## 物件的矩阵 / 顶点变形放在与场景同名的动画里 (循环播放);
## 逐帧顶点里的整张贴图平移 (瀑布、河水) 另记在 <场景>.markers.json 的 uv_anim (已按 AP 表展开), 每拍改材质 uv1_offset;
## MAPS.DAT 第 15 段贴图滚动记在 uv_scroll[地图号] = [{tex, du, dv}]: 每拍 uv += (du, dv), 不取模 (贴图是重复寻址,
## 取小数部分画面一样); 用这张贴图的物体都滚, 32 槽外没分到的物体导出成 tex<号>_still 材质, 不滚
var _uv_anims: Array = []   # [{mats: [StandardMaterial3D], fps, frames}]
var _uv_scroll: Array = []  # [{mats, d: Vector2 每拍增量}]
var _scene_t := 0.0


func _setup_scene_anim(scene_name: String) -> void:
	_uv_anims.clear()
	_uv_scroll.clear()
	_scene_t = 0.0
	for ap in _stage.find_children("*", "AnimationPlayer", true, false):
		var p := ap as AnimationPlayer
		for an in p.get_animation_list():
			p.get_animation(an).loop_mode = Animation.LOOP_LINEAR
		if p.has_animation(scene_name):
			p.play(scene_name)
	var path := Game.extracted_dir.path_join("scenes/%s.markers.json" % scene_name)
	var info: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	if not info is Dictionary:
		return
	for e in info.get("uv_scroll", {}).get(str(map_id), []):
		var names := ["tex%d" % int(e.tex), "tex%d_add" % int(e.tex), "tex%d_blend" % int(e.tex)]
		var mats: Array = []
		for node in _stage.find_children("*", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			for s in mi.mesh.get_surface_count():
				var m := mi.get_active_material(s)
				if m is StandardMaterial3D and m.resource_name in names and not m in mats:
					mats.append(m)
		if mats.size():
			_uv_scroll.append({"mats": mats, "d": Vector2(float(e.du), float(e.dv))})
			Enhance.water(mats)
		if OS.get_cmdline_user_args().has("--trace-events"):
			print("UVSCROLL tex%d mats=%d d=(%s, %s)" % [int(e.tex), mats.size(), e.du, e.dv])
	var uv: Dictionary = info.get("uv_anim", {})
	for node_name in uv:
		var n := _stage.find_child(str(node_name), true, false)
		if n == null:
			continue
		var mats: Array = []
		for mi in [n] + n.find_children("*", "MeshInstance3D", true, false):
			if mi is MeshInstance3D:
				for s in (mi as MeshInstance3D).mesh.get_surface_count():
					var m := (mi as MeshInstance3D).get_active_material(s)
					if m is StandardMaterial3D:
						mats.append(m)
		if mats.size():
			_uv_anims.append({"mats": mats, "fps": float(uv[node_name].fps), "frames": uv[node_name].frames})
			Enhance.water(mats)   # 画面增强: 流动贴图的面 (水 / 瀑布) 加闪光
			if OS.get_cmdline_user_args().has("--trace-water") and n is Node3D:
				for mi in [n] + n.find_children("*", "MeshInstance3D", true, false):
					if mi is MeshInstance3D:
						var ab: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
						print("WATER %s game=%s size=%s water=%s" % [node_name, to_game(ab.get_center()).round(), ab.size, (mats[0] as Material).has_meta("water_pass")])


func _scene_anim_tick(delta: float) -> void:
	_scene_t += delta
	for e in _uv_anims:
		var fr: Array = e.frames
		var k := int(_scene_t * float(e.fps)) % fr.size()
		var off := Vector3(float(fr[k][0]), float(fr[k][1]), 0)
		for m in e.mats:
			(m as StandardMaterial3D).uv1_offset = off
		Enhance.water_tick(e.mats, off)
	var ticks := int(_scene_t * 35.0)
	for e in _uv_scroll:
		var d: Vector2 = e.d * ticks
		var off := Vector3(fposmod(d.x, 1.0), fposmod(d.y, 1.0), 0)
		for m in e.mats:
			(m as StandardMaterial3D).uv1_offset = off
		Enhance.water_tick(e.mats, off)


## 天空穹顶 / 远景环幕 (wld2gltf 的 <名>_backdrop 节点) 水平跟着镜头走, 当天空盒用:
## 剧情里拉远镜头 (例 天书世界开场 camera_distance 9700) 时镜头不会跑出环幕外, 只看到环幕背面;
## 再以镜头为中心放大到刚好在远裁剪面以内 (画面上的大小不变), 让环幕总在场景后面, 不挡住远处拍的场景
var _backdrop: Node3D
var _backdrop_r := 1.0              # 环幕水平半径 (世界单位)
var _backdrop_box := AABB()         # 环幕原位置的包围盒 (镜头在盒内时环幕不动: 有的迷宫「环幕」其实是围住场景的崖壁)
var _backdrop_basis := Basis.IDENTITY
var _backdrop_center := Vector3.ZERO
var _backdrop_base := Vector3.ZERO


func _find_backdrop() -> void:
	_backdrop = null
	for part in ["backdrop", "fx", "scene"]:   # 调试: --hide-backdrop / --hide-fx / --hide-scene
		if OS.get_cmdline_user_args().has("--hide-" + part):
			for n in _stage.find_children("*_" + part, "Node3D", true, false):
				n.visible = false
	for n in _stage.find_children("*_backdrop", "Node3D", true, false):
		_backdrop = n
		break
	if _backdrop == null:
		return
	var box := AABB()
	var first := true
	var meshes: Array = _backdrop.find_children("*", "MeshInstance3D", true, false)
	if _backdrop is MeshInstance3D:
		meshes.append(_backdrop)   # 环幕本身常是单个网格节点
	for mi in meshes:
		var bb: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
		box = bb if first else box.merge(bb)
		first = false
	if first:
		_backdrop = null
		return
	_backdrop_center = box.get_center()
	_backdrop_r = maxf(maxf(box.size.x, box.size.z) * 0.5, 0.01)
	_backdrop_box = box
	_backdrop_base = _backdrop.global_position
	_backdrop_basis = _backdrop.global_basis


## 地图雾 (MAP 头 +0x56, 0x4146bb → 0x412d09 / 0x412d6e; verify_scene.md §1.3): 原版是顶点雾,
##   投影深度 sz = F/(F−N)·(1 − N/z) (N = 200, F = 视距), v = sz − (1.01 − p5), 起点 start = p3/p4, 终点 1:
##   雾量 = (v − start) / (1 − start), 夹在 0..1; 雾色 = (p0, p1, p2); 黑色底色不受雾影响; 旗标 8081 置位时关闭
##   用全屏四边形读深度缓冲按此公式逐像素算 (OrigFog); 以前用 Godot 深度雾拟合, 不精确
var _env: Environment
var _fog_key := ""
var _fog: OrigFog


func _update_fog() -> void:
	if _env == null:
		return
	var fog: Variant = map_info.get("fog")
	var far := maxf(cam.view_dist, 400.0)
	var on := fog is Array and not State.test_flag(8081) and not OS.get_cmdline_user_args().has("--no-fog")
	var key := "%s|%d|%s" % [str(fog), int(far), on]
	if key == _fog_key:
		return
	_fog_key = key
	_env.fog_enabled = false
	if _fog == null:
		_fog = OrigFog.new()
		_cam3d.add_child(_fog)
	_fog.setup(fog if on else null, far)
	if OS.get_cmdline_user_args().has("--trace-events"):
		print("FOG map=%d far=%.0f p=%s on=%s" % [map_id, far, str(fog), on])


## 碰撞地面的包围盒 (世界坐标): 用来判断「环幕」是不是其实只是围住可走区域的墙
var _floor_box := AABB()


func _backdrop_follow() -> void:
	if _backdrop == null or not is_instance_valid(_backdrop) or OS.get_cmdline_user_args().has("--no-backdrop-follow"):
		return
	# 原版没有跟着镜头走的环幕 (场景、天空都是固定世界矩阵); 这里只给远大于可走区域的天空穹顶 / 远景用。
	# 半径不到可走区域 1.5 倍的是房间的墙 (例: 研究石室 MAP00024 墙半径 1650、地面半跨度 1587), 不动 —
	# 否则镜头一出墙, 墙就被挪走放大, 地板变成悬空孤岛 (verify_scene.md §1.5)
	var half := maxf(_floor_box.size.x, _floor_box.size.z) * 0.5
	if half > 0.0 and _backdrop_r <= 1.5 * half:
		return
	var c := _cam3d.global_position
	var bb := _backdrop_box
	if c.x >= bb.position.x and c.x <= bb.end.x and c.z >= bb.position.z and c.z <= bb.end.z:
		_backdrop.global_transform = Transform3D(_backdrop_basis, _backdrop_base)   # 镜头在环幕内: 原样
		return
	var t := Transform3D(_backdrop_basis, _backdrop_base + Vector3(c.x - _backdrop_center.x, 0, c.z - _backdrop_center.z))
	var k := maxf(1.0, _cam3d.far * 0.9 / _backdrop_r)
	_backdrop.global_transform = Transform3D(Basis.from_scale(Vector3.ONE * k), c * (1.0 - k)) * t


func _process(delta: float) -> void:
	if _menu_scroll:
		_menu_scroll.visible = not busy and not cutscene and not (State.test_flag(8050) or State.test_flag(8080) or State.test_flag(8015))
	# 0x478530: 有小地图的地图, 事件中 / 隐藏 / 旗标 45 不画
	minimap.visible = int(map_info.get("flags", 0)) & Minimap.MAP_HAS_MINIMAP != 0 and not _in_battle \
		and not (State.test_flag(Minimap.FLAG_EVENT) or State.test_flag(Minimap.FLAG_HIDDEN) or State.test_flag(Minimap.FLAG_BLOCK))
	_acc += delta
	while _acc >= TICK:
		_acc -= TICK
		if OS.get_cmdline_user_args().has("--trace-move") and Engine.get_process_frames() % 30 == 0:
			print("TICK f=%d busy=%s player=%s key=%s pose=%d tick=%.0f len=%d loop=%s" % [Engine.get_process_frames(), busy, player != null, _dbg_key, player.pose if player else -1, player.pose_tick if player else 0, player.pose_len if player else 0, player.pose_loop if player else false])
		_moved_tick = false
		if not busy and player:
			_player_tick()
		_cursor_tick()
		_scroll_tick()
		_ani_tick()
	_weather_tick(delta)
	if OS.get_cmdline_user_args().has("--trace-fps"):
		_worst_dt = maxf(_worst_dt, delta)
		if Engine.get_process_frames() % 60 == 0:
			print("FPS %d worst_frame=%.0fms t=%.1f draws=%d objs=%d tris=%dk proc=%.1fms" % [Engine.get_frames_per_second(), _worst_dt * 1000.0, Time.get_ticks_msec() / 1000.0,
					Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
					Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0])
			_worst_dt = 0.0
	cam.tick(delta)
	_update_fog()
	_backdrop_follow()
	_scene_anim_tick(delta)
	Enhance.update_dof(_cam3d, _cam3d.global_position.distance_to(cam.to_world(cam.f)))
	if is_instance_valid(_motes):
		_motes.global_position = cam.to_world(cam.f) + Vector3(0, 1.5, 0)
	if OS.get_cmdline_user_args().has("--trace-cam") and Engine.get_process_frames() % 30 == 0:
		print("CAM t=%.1f eye=%s fwd=%s far=%.0f map=%d" % [Time.get_ticks_msec() / 1000.0, to_game(_cam3d.global_position).round(),
			(-_cam3d.global_basis.z).snapped(Vector3.ONE * 0.01), _cam3d.far, map_id])
		if _backdrop:
			print("  BD pos=%s scale=%.2f r=%.1f center=%s" % [_backdrop.global_position, _backdrop.global_basis.get_scale().x, _backdrop_r, _backdrop_center])
	if shake:
		# screen_shake (0x3a): 每帧给视点加 rand()%10 的抖动 (游戏单位)
		_cam3d.position += Vector3(randi() % 10, randi() % 10, 0) * 0.01


## 地图更新 (0x47a3f6): 输入 → 移动 / 碰撞 → 事件框 → 镜头注视 → 遇敌
func _player_tick() -> void:
	# 镜头转动: Q/E、Shift+←/→ 每帧 2°, 左 = 偏航 +2, 右 = −2 (0x47b8c8 / 0x47b998), Tab 回正 (地图标志 0x20 禁止)
	var map_flags := int(map_info.get("flags", 0))
	if _weather:   # 设定「场景特效」关: 不画天气粒子 (原版 [0xbcf448]≠0 时跳过特效列表 0x48fc24)
		_weather.visible = int(MainMenu.setting("effects")) == 0
	var shift := Input.is_key_pressed(KEY_SHIFT) or Pad.camera_modifier()
	if not (map_flags & 0x20):
		if Input.is_key_pressed(KEY_Q) or (shift and Input.is_key_pressed(KEY_LEFT)) or Pad.turn() > 0:
			cam.set_angles(cam.angt.x, cam.angt.y + 2.0, cam.angt.z)
		if Input.is_key_pressed(KEY_E) or (shift and Input.is_key_pressed(KEY_RIGHT)) or Pad.turn() < 0:
			cam.set_angles(cam.angt.x, cam.angt.y - 2.0, cam.angt.z)
		# 设定「镜头模式二」(0x47b1d0): 鼠标到屏幕左边缘 (x<10) / 右边缘 (x>790) 时每帧转 2°
		if int(MainMenu.setting("cam_mode")) == 1 and not has_node("MainMenu"):
			var mx := _mouse_ui().x
			if mx < 10:   # 0x47b2ae
				cam.set_angles(cam.angt.x, cam.angt.y + 2.0, cam.angt.z)
			elif mx > 790:
				cam.set_angles(cam.angt.x, cam.angt.y - 2.0, cam.angt.z)
	var key := Vector2i.ZERO
	if not shift:
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
			key.y -= 1
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
			key.y += 1
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
			key.x -= 1
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
			key.x += 1
	if _dbg_key != Vector2i.ZERO:
		key = _dbg_key
	var moving := key != Vector2i.ZERO
	var facing := player.facing
	var cam_yaw := FieldActor.facing_of(cam.to_game(_cam3d.global_position) - player.gpos)
	if moving:
		# camYaw = 主角指向镜头的方向 (0x460ebb); 下 = camYaw, 上 +180, 左 +270, 右 +90
		var table := {Vector2i(0, 1): 0, Vector2i(0, -1): 180, Vector2i(-1, 0): 270, Vector2i(1, 0): 90,
			Vector2i(-1, -1): 225, Vector2i(1, -1): 135, Vector2i(-1, 1): 315, Vector2i(1, 1): 45}
		facing = cam_yaw + float(table[key])
	elif (_dbg_mouse != Vector2.INF or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)) and dialog.windows.is_empty() and not minimap.blocks_walk():
		# 按住左键: 朝鼠标相对画面中心 (400,300) 的方向走 (0x47b0fa)
		var m := _mouse_ui() if _dbg_mouse == Vector2.INF else _dbg_mouse
		var v := m - Vector2(400, 300)
		if v.length() > 20:
			# 与键盘一致: 屏幕下 = camYaw, 屏幕右 = camYaw + 90 (画面已按原版翻转, 不能再取反)
			facing = cam_yaw + rad_to_deg(atan2(v.x, v.y))
			moving = true
	if not moving:
		if player.pose in [RUN_POSE, WALK_POSE]:
			player.play(IDLE_POSE)
		return
	var world_map := map_flags & 0x80 != 0
	var spd := WORLD_SPEED if world_map else (RUN_SPEED if running else WALK_SPEED)
	var pose := RUN_POSE if (running or world_map) else WALK_POSE
	player.set_facing(facing)
	var moved := try_move(player, FieldActor.dir_of(facing) * spd)
	if player.pose != pose:
		player.play(pose)
	if OS.get_cmdline_user_args().has("--trace-move") and Engine.get_process_frames() % 20 == 0:
		print("MOVE pose=%d want=%d spd=%.1f world=%s act=%d pos=%s" % [player.pose, pose, spd, world_map, player.act, str(player.gpos.round())])
	if moved:
		_moved_tick = true
		steps += 1
		cam.set_target(player.gpos + Vector3(0, 100, 0))
		if _check_boxes():
			return
		_check_encounter()


## 事件框 (0x46d4f2): 旗标 17 置位时不检测; 主角盒子 (XB + 位置) 与框严格重叠、且未被 set_trigger 禁用 → 启动该事件
func _check_boxes() -> bool:
	if State.test_flag(17):
		return false
	var me := leader_box(player.gpos)
	for t in map_info.get("boxes", []):
		var eid := int(t.event)
		if not State.trigger_enabled(eid):
			continue
		var p: Array = t.pos
		var mn: Array = t.min
		var mx: Array = t.max
		var box := [p[0] + mn[0], p[1] + mn[1], p[2] + mn[2], p[0] + mx[0], p[1] + mx[1], p[2] + mx[2]]
		if box_overlap(me, box) and event_code(eid).size():
			# 不先把主角切成站立: 条件不满足、立刻结束的框事件 (竹林入口 166 等) 每帧都会触发,
			# 切站立会让跑步动画每帧被重置 (看起来是滑着走)。真正开始演出的事件自己会 set_pose
			run_event(eid, 0xff01)
			return true
	return false


## 遇敌 (0x404f17): 概率组按步数分段 (累加), rand(100) < 百分比, 主角在遇敌区域内 → 随机战场 (重复即权重)
func _check_encounter() -> void:
	if not map_info.get("encounters", false) or State.test_flag(10) or OS.get_cmdline_user_args().has("--no-encounter"):
		return
	if State.test_flag(18) and int(State.regs[1]) == 0:   # 0x47c5b1: 连续战斗打完了, 本图不再遇敌
		return
	var zones: Array = map_info.get("zones", [])
	if zones.is_empty():
		return
	var group: int = int(zones[-1].group)
	var groups: Array = newgame.encounter_groups
	if group < 1 or group > groups.size():
		return
	var acc := 0
	var pct := 0
	for br in groups[group - 1]:
		acc += int(br[0])
		if steps < acc:
			pct = int(br[1])
			break
	if randi() % 100 >= pct:
		return
	var me := leader_box(player.gpos)
	for z in zones:
		var mn: Array = z.min
		var mx: Array = z.max
		if box_overlap(me, [mn[0], 0, mn[2], mx[0], 65000, mx[2]]):
			var bfl: Array = z.battlefields
			steps = 0
			_encounter(int(bfl[randi() % bfl.size()]))
			return


func _encounter(bf: int) -> void:
	busy = true
	player.play(IDLE_POSE)
	await start_battle(bf)
	busy = false


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo:
		if e.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
			if dialog.advance():
				get_viewport().set_input_as_handled()
				return
			if not busy and player and e.keycode == KEY_SPACE:
				_investigate()
			elif not busy and player and e.keycode == KEY_ENTER:
				# 原版 0x47c918: 只有 Enter (0x0d) 和手柄 0x10b 打开主菜单 (小键盘 Enter 是 0xa0, 不开)。先标记已处理: 不然同一下 Enter 会传给刚打开的菜单
				get_viewport().set_input_as_handled()
				open_menu()
			return
		if e.keycode in [Pad.Y, Pad.START] and not busy and player:
			get_viewport().set_input_as_handled()
			open_menu()
		elif e.keycode == KEY_R and not busy:
			running = not running
		elif e.keycode == KEY_TAB and not busy:
			reset_camera()
		elif e.keycode == KEY_M and not busy:
			minimap.cycle()
		# 原版地图上 ESC 单独按没有作用 (只有 Shift+ESC 切换旗标 12 的开发键, 0x47a468); 以前 ESC 也开主菜单, 不是原版行为
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		if dialog.advance():
			get_viewport().set_input_as_handled()
			return
		if not busy and player and not State.test_flag(8015) and minimap.press(_dbg_mouse_ui if _dbg_mouse_on else _mouse_ui(), e.double_click):
			get_viewport().set_input_as_handled()
			return
		if not busy and player and _menu_scroll and _menu_scroll.visible and _menu_scroll.get_global_rect().has_point(e.position):
			get_viewport().set_input_as_handled()
			open_menu()
			return
		if not busy and player:
			_click_actor(e.position)
	elif e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_RIGHT:
		_rmb = e.pressed
	elif e is InputEventMouseMotion and _rmb and not busy and not (int(map_info.get("flags", 0)) & 0x20):
		# 右键拖动: 偏航 −= dx × 0.5 (画面已翻转, 方向取反)
		cam.set_angles(cam.angt.x, cam.angt.y + e.relative.x * 0.5, cam.angt.z)


# ---------------- 主菜单 / 存档 ----------------

var _menu_scroll: TextureRect
var _moved_tick := false
var _scroll_off := 0                         # [0xc6e64c]
var _scroll_player := UiAct.Player.new()     # 0x9f7040


## 菜单卷轴 (0x4674fe, 每逻辑帧): 主角这一帧在走 → 播放器清零、偏移 +1 (最多 60, 滑到 x = 810 出画面); 否则偏移 −1 回到 0。
## 鼠标在 x∈[720,800)、y∈[2,50) 时才推进并画 ACT 9019 qq15 (0227 第 4–6 帧各 9 逻辑帧循环), 否则画静态第一帧;
## 画在 (750 + 偏移, 10)。旗标 8050 / 8080 / 8015 任一置位不画
func _scroll_tick() -> void:
	if _menu_scroll == null:
		return
	if _moved_tick:
		_scroll_player.restart()
		_scroll_off = mini(_scroll_off + 1, 60)
	else:
		_scroll_off = maxi(_scroll_off - 1, 0)
	_scroll_player.set_state(9019, 15)
	var mp := _mouse_ui()
	var f: Dictionary
	if mp.x >= 720 and mp.x < 800 and mp.y >= 2 and mp.y < 50:
		_scroll_player.ticks += 1
		f = _scroll_player.current()
	else:
		f = UiAct.frame(9019, 15, 0)
	if not f.is_empty():
		_menu_scroll.texture = f.tex
	_menu_scroll.position = Vector2(750 + _scroll_off, 10)


## 右上角菜单卷轴 (0x4674fe): ACT 9019 qq15 → 0227 第 4–6 帧 (悬停时展开), 画在 (750,10); 过场时隐藏
func _build_menu_scroll(top: CanvasLayer) -> void:
	_menu_scroll = TextureRect.new()
	_menu_scroll.texture = Game.load_texture("ui/all_sys/0227_000_游标图1/004.png")
	_menu_scroll.position = Vector2(750, 10)
	_menu_scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(_menu_scroll)


func open_menu() -> void:
	if busy or has_node("MainMenu"):
		return
	busy = true
	if player:
		player.path.clear()
		player.play(IDLE_POSE)
	menu_thumb = snapshot()   # 打开菜单前截图: 从菜单存档时用这张 (0x47e515)
	var m := MainMenu.new()
	m.name = "MainMenu"
	m.field = self
	add_child(m)
	await m.closed
	busy = false
	if m.pending_event >= 0 and event_code(m.pending_event).size():   # 在菜单里用了会启动事件的道具 (玉蝉 / 土地神符)
		run_event(m.pending_event, player.id if player else 0xff01)
	elif m.pending_battle > 0:   # 诱敌女娃
		steps = 0
		_encounter(m.pending_battle)


## 诱敌女娃 (0x404f17 强制模式): 不看步数和机率; 地图要能遇敌、主角在某个遇敌区里, 从那区的战场里随机挑 (重复即权重); 否则 0
func lure_battle() -> int:
	if not map_info.get("encounters", false) or player == null:
		return 0
	var me := leader_box(player.gpos)
	for z in map_info.get("zones", []):
		var mn: Array = z.min
		var mx: Array = z.max
		if box_overlap(me, [mn[0], 0, mn[2], mx[0], 65000, mx[2]]):
			var bfl: Array = z.battlefields
			if bfl.size():
				return int(bfl[randi() % bfl.size()])
	return 0


func save_game(slot: int, thumb: Image = null) -> void:
	_save_actors()
	State.map_id = map_id
	if player:
		State.player_pos = player.gpos
		State.player_facing = player.facing
	State.cam = cam.to_save()
	State.save_slot(slot, thumb, str(map_info.get("title", "")))   # MAPS.DAT seg21 显示名 (例「曲沃城」)
	State.cam = {}


## 截当前画面作缩略图 (0x46c30a; 原版只取左上 640×480, 这里取整个画面缩放, 偏离原版)
func snapshot() -> Image:
	var img := get_viewport().get_texture().get_image()
	if img:
		img.resize(160, 120, Image.INTERPOLATE_BILINEAR)
	return img


## 打开存档 / 读档画面 (盖在当前画面上); 读档成功就重进场景
func open_save_screen(mode: String, thumb: Image = null) -> bool:
	var s := SaveLoadScreen.new()
	s.mode = mode
	s.thumb = thumb if thumb else snapshot()
	s.field = self
	add_child(s)
	var loaded: bool = await s.closed
	if loaded:
		get_tree().change_scene_to_file("res://scenes/field.tscn")
	return loaded


func _can_talk(a: FieldActor) -> bool:
	return a != player and not a.hidden and a.event_id > 0 and (a.flags & 0x6c00) != 0


## 空格调查 (0x47c770, 逆向确认): 探测位移 = 朝向 × 50; 按角色表顺序, **第一个**命中的就处理 (不挑最近);
## 跳过主角、标志 0x9 (含隐藏)、0x4000000; 命中 = 主角盒子平移探测位移 (dy = 0) 后和对方盒子严格重叠 (0x46926a),
## 或两人中心 3D 距离 ≤ 100; 再要求有事件。标志 0xc00 → 直接开始事件; 否则没有 0x40000 → 对话 (0x1000 不转身);
## 带 0x40000 的跳过看下一个。键盘调查不看 0x6c00 (只有鼠标拾取看)。
## 例: 泰山结界迷宫的浮台 (5674 等, 盒子约 439 × 407) 中心离可站的地面约 250, 只能靠盒子重叠调查到
func is_investigate_hit(a: FieldActor, from: Vector3, facing: float) -> bool:
	var off := FieldActor.dir_of(facing) * PROBE
	return box_overlap(actor_box(player, from - player.gpos + Vector3(off.x, 0, off.z)), actor_box(a)) \
		or a.gpos.distance_to(from) <= TALK_DIST


func _investigate() -> void:
	for a in actors.values():
		if a == player or a.hidden or a.flags & 0x9 or a.flags & 0x4000000:
			continue
		if not is_investigate_hit(a, player.gpos, player.facing) or a.event_id <= 0:
			continue
		if a.flags & 0xc00 or not (a.flags & 0x40000):
			if event_code(a.event_id).size():
				_start_npc_event(a)
			return


## 鼠标点击 NPC: 水平距离 ≤ 350 才对话 (0x47ac47)
func _click_actor(screen: Vector2) -> void:
	# 0x47ac47: 左键按下时用当前指到的 NPC (同光标的拾取 0x47a60b), 水平距离 > 350 不理
	var ui := screen / Vector2(get_viewport().get_visible_rect().size) * Vector2(800, 600)
	var a: FieldActor = pick_actor(ui)
	if a and Vector2(a.gpos.x - player.gpos.x, a.gpos.z - player.gpos.z).length() <= CLICK_DIST:
		_start_npc_event(a)


## 鼠标指到的 NPC (0x47a60b 循环 + 0x41047c): 角色当前动作的包围盒 XB (乘缩放、按朝向旋转、放在角色位置) 的 8 个角投影到屏幕,
## 鼠标落在这 8 点的屏幕外接矩形里、矩形中心在画面内就算指到; 多个时取最近的 (8 角里最小的深度)。
## 条件: 编号非 0 且 < 0xff00、不是主角、有事件、标志含 0x6c00 (可对话 / 调查); 旗标 8010 没置位时跳过隐藏 (0x1) 和标志 0x200 的
func pick_actor(m: Vector2) -> FieldActor:
	var best: FieldActor = null
	var best_d := INF
	for a in actors.values():
		var fa := a as FieldActor
		if fa == player or fa.id == 0 or fa.id >= 0xff00 or fa.event_id <= 0 or not (fa.flags & 0x6c00):
			continue
		if not State.test_flag(8010) and (fa.hidden or fa.flags & 0x200):
			continue
		var pm: Dictionary = fa.meta.get("poses", {}).get(str(fa.pose), {})
		var bb: Array = pm.get("bbox", [])
		if bb.size() < 6:
			continue
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		var depth := INF
		for k in 8:
			var c := Vector3(bb[3] if k & 1 else bb[0], bb[4] if k & 2 else bb[1], bb[5] if k & 4 else bb[2]) * 0.01
			var w: Vector3 = fa.global_transform * c
			if _cam3d.is_position_behind(w):
				depth = -1.0
				break
			var sp := screen_pos(w)
			lo = lo.min(sp)
			hi = hi.max(sp)
			depth = minf(depth, _cam3d.global_position.distance_to(w))
		if depth < 0.0:
			continue
		var ctr := (lo + hi) * 0.5
		if ctr.x <= 0 or ctr.x >= 800 or ctr.y <= 0 or ctr.y >= 600:
			continue
		if m.x < lo.x or m.x > hi.x or m.y < lo.y or m.y > hi.y:
			continue
		if depth < best_d:
			best_d = depth
			best = fa
	return best


## 光标 (地图更新 0x47a3f6 里写 [0xa83db2]): 每个逻辑帧
var _cur_last := Vector2.INF
var _cur_idle := 0
var _rdrag := false


func _cursor_tick() -> void:
	var c := Game.cursor
	if c == null:
		return
	_rmb = _rmb and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)   # 松开事件可能被菜单 / 商店吃掉
	if State.test_flag(8053):
		_end_rdrag(c)
		c.set_state(9001, 9)
		return
	if busy or player == null or State.test_flag(8015):
		_end_rdrag(c)   # 拖动中遇敌 / 进事件: 不解锁的话光标整场战斗都钉在原地
		minimap.idle()
		c.idle_hidden = false   # 战斗 0x44270e、对话框 0x464a24、菜单 0x47e467 都清 [0xafdc54]
		_cur_idle = 0
		return   # 0x47a4c5 / 0x467840: 等待中, 光标不变
	var m := _dbg_mouse_ui if _dbg_mouse_on else _mouse_ui()
	if _dbg_mouse_on:
		c.debug_pos = m
	minimap.tick(m, Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT))
	# 600 帧鼠标没动 → 不画光标 ([0xafdc54] = 1, 0x47a507); 动了就重新计数
	if m != _cur_last:
		_cur_last = m
		_cur_idle = 0
		c.idle_hidden = false
	else:
		_cur_idle += 1
		if _cur_idle >= 600:
			c.idle_hidden = true
	# 八方向箭头: 鼠标相对 (320, 240) 的方向 (0x495ed0 与 (0,1) 的夹角, x<0 取 360−角), 按 22.5 / 67.5 / … / 337.2 度分 8 段
	var d := m - Vector2(320, 240)
	var ang := 0.0
	if d.length() > 0.0:
		ang = rad_to_deg(acos(clampf(d.normalized().y, -1.0, 1.0)))
		if d.x < 0.0:
			ang = 360.0 - ang
	var q := 0
	var bounds := [22.5, 67.5, 112.5, 157.5, 202.5, 247.5, 292.5, 337.2]
	if ang > 22.5 and ang <= 337.2:
		for k in 7:
			if ang > bounds[k] and ang < bounds[k + 1]:
				q = k + 1
	var a := pick_actor(m)
	if a:
		q = 8 if a.flags & 0xc00 else 10   # 调查型手 / 对话气泡
		if a.flags & 0x10 and not (a.flags & 0xc00):
			q = 0   # 碰到触发型 (0x47a7d5)
	# 右键拖动转镜头 (0x47b341): 拖动中显示旋转 (qq11), 鼠标锁在按下的位置
	if _rmb and not (int(map_info.get("flags", 0)) & 0x20):
		if not _rdrag:
			_rdrag = true
			c.frozen = m
		q = 11
	else:
		_end_rdrag(c)
	var act := 9001
	# 主角站着时鼠标在右上角菜单卷轴 (720–800, 2–50) → ACT 9019 qq16 (0x47c61b)
	if q != 11 and player.path.is_empty() and m.x >= 720 and m.x < 800 and m.y >= 2 and m.y < 50:
		act = 9019
		q = 16
	var mq := minimap.cursor_q()
	if q != 11 and mq >= 0:
		act = 9001
		q = mq
	c.set_state(act, q)


## Tab / 小地图第三个按钮 (0x47ba99): 镜头转回偏航 0; 禁止转镜头的地图没有作用
func reset_camera() -> void:
	if not (int(map_info.get("flags", 0)) & 0x20):
		cam.set_angles(cam.angt.x, 0, cam.angt.z)


func _end_rdrag(c: GameCursor) -> void:
	if _rdrag:
		_rdrag = false
		c.frozen = null


# ---------------- 调试 ----------------

## 调试: --mouse-test 依次按住鼠标在画面上 / 下 / 左 / 右 (相对中心 200 像素) 各 1 秒, 打印角色在画面上的位移
func _mouse_test() -> void:
	await get_tree().create_timer(1.0).timeout
	for d in [Vector2(0, -200), Vector2(0, 200), Vector2(-200, 0), Vector2(200, 0)]:
		for mode in ["KEY", "MOUSE"]:
			var g0 := player.gpos
			if mode == "KEY":
				_dbg_key = Vector2i(signi(int(d.x)), signi(int(d.y)))
			else:
				_dbg_mouse = Vector2(400, 300) + (d as Vector2)
			await get_tree().create_timer(0.4).timeout
			_dbg_key = Vector2i.ZERO
			_dbg_mouse = Vector2.INF
			await get_tree().create_timer(0.2).timeout
			print("%-5s 画面方向 %s → 角色在画面上移动 %s" % [mode, d, screen_pos(player.global_position) - screen_pos(to_world(g0))])
			# 回到起点再测下一种
			player.set_game_pos(g0)
			cam.set_target(player.gpos + Vector3(0, 100, 0))
			cam.snap()
			await get_tree().create_timer(0.2).timeout
	print("AP QUIT via direction test")
	get_tree().quit()


func _debug_args() -> void:
	for wa in _args():
		if wa.begins_with("--walk="):   # 调试 / 录像: --walk=开始秒:方向(up/down/left/right/ul/ur/dl/dr):持续秒, 可多个
			var parts := wa.substr(7).split(":")
			var dirs := {"up": Vector2i(0, -1), "down": Vector2i(0, 1), "left": Vector2i(-1, 0), "right": Vector2i(1, 0),
				"ul": Vector2i(-1, -1), "ur": Vector2i(1, -1), "dl": Vector2i(-1, 1), "dr": Vector2i(1, 1)}
			var t0 := float(parts[0])
			var dk: Vector2i = dirs.get(parts[1], Vector2i.ZERO)
			var dur := float(parts[2])
			get_tree().create_timer(t0).timeout.connect(func(): _dbg_key = dk)
			get_tree().create_timer(t0 + dur).timeout.connect(func(): _dbg_key = Vector2i.ZERO)
	if autoplay:
		var ap := Autoplay.new()
		ap.name = "Autoplay"
		ap.field = self
		add_child(ap)
	for a0 in _args():
		if a0.begins_with("--actor-pose="):   # 调试: 让某个角色播放指定动作
			var ap := a0.substr(13).split(":")
			if actors.has(int(ap[0])):
				(actors[int(ap[0])] as FieldActor).play(int(ap[1]))
	if _args().has("--dump-actors"):
		for a in actors.values():
			var fa := a as FieldActor
			var aabb := AABB()
			for mi in fa.find_children("*", "MeshInstance3D", true, false):
				if (mi as MeshInstance3D).is_visible_in_tree():
					aabb = aabb.merge((mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb())
			print("ACTOR %d act=%d pose=%d hidden=%s vis=%s gpos=%s aabb=%s" % [fa.id, fa.act, fa.pose, fa.hidden, fa.is_visible_in_tree(), fa.gpos, aabb.size])
	if _args().has("--mod-m1-test"):   # 创意工坊 M1 验收测试 (scripts/tests/mod_m1_test.gd)
		var t: Node = load("res://scripts/tests/mod_m1_test.gd").new()
		t.field = self
		add_child(t)
	if _args().has("--hidden-spot-test"):   # 隐藏调查点测试 (令狐国古井, scripts/tests/hidden_spot_test.gd)
		var ths: Node = load("res://scripts/tests/hidden_spot_test.gd").new()
		ths.field = self
		add_child(ths)
	if _args().has("--item-use-test"):   # 地图菜单使用道具 (scripts/tests/item_use_test.gd)
		var tiu: Node = load("res://scripts/tests/item_use_test.gd").new()
		tiu.field = self
		add_child(tiu)
	if _args().has("--mod-m6-test"):   # 创意工坊 M6 验收测试 (自定义物品, scripts/tests/mod_m6_test.gd)
		var t6: Node = load("res://scripts/tests/mod_m6_test.gd").new()
		t6.field = self
		add_child(t6)
	if _args().has("--mod-m7-test"):   # 创意工坊 M7 验收测试 (任务, scripts/tests/mod_m7_test.gd)
		var t7: Node = load("res://scripts/tests/mod_m7_test.gd").new()
		t7.field = self
		add_child(t7)
	if _args().has("--mod-m8-test"):   # 创意工坊 M8 验收测试 (怪物 + 战斗, scripts/tests/mod_m8_test.gd)
		var t8: Node = load("res://scripts/tests/mod_m8_test.gd").new()
		t8.field = self
		add_child(t8)
	if _args().has("--mod-m9-test"):   # 创意工坊 M9 验收测试 (自定义战斗模型, scripts/tests/mod_m9_test.gd)
		var t9: Node = load("res://scripts/tests/mod_m9_test.gd").new()
		t9.field = self
		add_child(t9)
	if _args().has("--mod-m10-test"):   # 创意工坊 M10 验收测试 (遇敌 + 变量, scripts/tests/mod_m10_test.gd)
		var t10: Node = load("res://scripts/tests/mod_m10_test.gd").new()
		t10.field = self
		add_child(t10)
	if _args().has("--mod-e2-test"):   # 创意工坊 E2 验收测试 (方案覆盖原版事件 / NPC, scripts/tests/mod_e2_test.gd)
		var te2: Node = load("res://scripts/tests/mod_e2_test.gd").new()
		te2.field = self
		add_child(te2)
	if _args().has("--mod-e4-test"):   # 创意工坊 E4 验收测试 (改队员 / 开局, scripts/tests/mod_e4_test.gd)
		var te4: Node = load("res://scripts/tests/mod_e4_test.gd").new()
		te4.field = self
		add_child(te4)
	if _args().has("--pad-test"):   # 手柄验收 (scripts/tests/pad_test.gd)
		var tp: Node = load("res://scripts/tests/pad_test.gd").new()
		tp.field = self
		add_child(tp)
	if _args().has("--minimap-test"):   # 小地图验收 (scripts/tests/minimap_test.gd)
		var tm: Node = load("res://scripts/tests/minimap_test.gd").new()
		tm.field = self
		add_child(tm)
	if _args().has("--mouse-test"):
		_mouse_test()
	var shot := ""
	var delay := 3.0
	var times: Array = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			shot = a.substr(7)
		elif a.begins_with("--shot-delay="):
			delay = float(a.substr(13))
		elif a.begins_with("--shots="):
			times = Array(a.substr(8).split(",")).map(func(x): return float(x))
	if shot == "":
		return
	if times.size():
		# 连拍: 在各个时刻存 <shot 去扩展名>_<秒>.png, 最后一张后退出
		var t0 := Time.get_ticks_msec()
		for t in times:
			while is_inside_tree() and (Time.get_ticks_msec() - t0) / 1000.0 < t:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			print("SHOT %.1f map=%d pos=%s busy=%s cam=%s/%s tex=%dMB" % [t, map_id, player.gpos if player else Vector3.ZERO, busy, cam.ang, cam.d,
				Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576])
			get_viewport().get_texture().get_image().save_png("%s_%05.1f.png" % [shot.get_basename(), t])
		get_tree().quit()
		return
	await get_tree().create_timer(delay).timeout
	await RenderingServer.frame_post_draw
	print("SHOT map=%d tex=%dMB vram=%dMB" % [map_id, Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576, Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576])   # 显存里的贴图 (比较 标清 / 2K / 4K)
	get_viewport().get_texture().get_image().save_png(shot)
	get_tree().quit()
