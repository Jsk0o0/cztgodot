class_name Battle
extends Node
const HELD_MORPH := preload("res://scripts/held_morph.gd")
## 战斗 (SWDMD_GB.EXE 逆向, 见 scratchpad/re/battle_flow_re.md / battle_formula_re.md 的整理)
##   初始化 0x43fb05: 战场 N = BattleField.dat 第 N-1 条 (场景、敌人、站位), 战斗剧情 FIGTALK 第 N-1 槽
##   逻辑 27 帧/秒 (0x4675fb(27)); 每帧: FIGTALK → 行动条 → 执行中的招式 → 结算
##   行动条 (0x4324c8): 无人行动、无菜单、未锁定时, 每帧 += 有效速度/10 (先抵消击退值), 满 1000 即行动, 期间全体暂停
##   我方: 指令菜单 (攻击 / 技能 / 道具 / 防御 / 逃跑); 敌方: AI 脚本 (0x401ae0)
##   车芸 = 云狐单位 (角色 0xb, 用车芸的属性, 画的是云狐 ACT 11) + 不参战的车芸本体 (ACT 1)
## 由地图 (field.gd) 创建: var b := Battle.new(); b.setup(bf, field); add_child(b); var r = await b.finished

signal finished(result: String)          # "win" / "lose" / "escape"

const TICK := 1.0 / 27.0
const ANIM_TICK := 1.0 / 27.0   # 战斗里的动作 / 特效逻辑帧 (以前误用 1/35)
## 我方固定站位 (0x43f0ae): 云狐(车芸) / 嬴诗 / 桓远之 / 车芸本体; 我方面朝 180°(+Z), 敌方 0°(−Z)
const PARTY_POS := {1: Vector3(-275, 83, -390), 2: Vector3(-65, 83, -340), 3: Vector3(100, 83, -400)}
const FIGURE_POS := Vector3(-175, 83, -490)
const STATUS_IDX := [0x4, 0x8, 0x10, 0x20, 0x1000, 0x1000000, 0x800, 0x10000, 0x10000000, 0x20000, 0x20000000,
	0x2000, 0x2000000, 0x4000, 0x4000000]

static var db: Dictionary = {}

const ATB_RATE := 1.2   # 行动条走动的节拍倍率 (原版 1.0)
var bf_id := 0
var bf: Dictionary = {}
var field: Node
var units: Array = []            # 按单位下标 (FIGTALK unitN); 我方从 0 起, 敌方从 6 起
var cam: OrigCamera
var dialog: Dialog
var result := ""
var no_escape := false
var allow_lose := false
var domo_off := false            # FIGTALK 0x7e0: [0x92520e]&0x80 —— DOMO令牌 (3905) 这场不能用 (0x434470)
var end_mode := 0               # FIGTALK 0x7da: [0x925a24] 自动结束方式 (0 正常, 非 0 由脚本收尾, 0x442950)
var hud_panel := true            # [0x4e38a0]: 下方我方状态栏是否显示 (0x45108a); 写入点逆向中, 暂只接 FIGTALK 0x7e4
var story := false   # 剧情战 (事件 start_battle 开的): 不能收化
var locked := false              # FIGTALK lock_battle
var acting := false              # 有单位在行动 (含指令菜单)
var actions_done := 0            # 已完成的行动数 (run_battle_turns 用)
var music := 0
var battle_vars := {}
var counters := {}
var rewards := {"exp": 0, "money": 0, "res": [0, 0, 0], "items": []}

var _w: SubViewport
var _world: Node3D
var _cam3d: Camera3D
var _ui: CanvasLayer
var hud: BattleHud
var active: BattleUnit           # 正在行动的单位 (名牌高亮)
var _msg: Control
var _msg_text := ""
var _msg_id := 0
var _acc := 0.0
var _figtalk_running := false
var _intro_runners := 0
var _tint_rect: ColorRect
var _saved_cam := {}


static func load_db() -> void:
	if db.is_empty():
		db = JSON.parse_string(FileAccess.get_file_as_string(Game.extracted_dir.path_join("game/battle.json")))


## 后台线程解析 (11MB, 放主线程会卡住一帧); 调用方要在 await 期间保持在场景树里
static func load_db_async(tree: SceneTree) -> void:
	if not db.is_empty():
		return
	var res: Array = [null]
	var path := Game.extracted_dir.path_join("game/battle.json")
	var id := WorkerThreadPool.add_task(func(): res[0] = JSON.parse_string(FileAccess.get_file_as_string(path)))
	while not WorkerThreadPool.is_task_completed(id):
		await tree.process_frame
	WorkerThreadPool.wait_for_task_completion(id)
	if db.is_empty() and res[0] is Dictionary:
		db = res[0]


## 连续战斗提示文本 (FIGTALK 0x7df 写入, 跨战斗保留): [「还剩%d组…」, 归零时的文本]
static var countdown_text: Array = ["还有%d场战斗!!", "没有战斗了!!"]


static func obj(id: int) -> Dictionary:
	load_db()
	var r: Dictionary = db.objs.get(str(id), {})
	# 存档里有 mod 物品, 但那个 mod 没启用 / 已卸载: 当剧情类「失效物品」(不能用、卖价 0), 重新启用 mod 就恢复
	if r.is_empty() and id >= Mods.ITEM_BASE and id < Mods.ITEM_BASE + 10000 * 256:
		return {"name": "失效物品", "sub": 210, "price": 0, "sellable": 0, "desc": "来自没有启用的创意工坊 mod，启用后恢复。"}
	return r


func setup(battlefield: int, f: Node) -> void:
	load_db()
	bf_id = battlefield
	bf = db.battlefields.get(str(battlefield), {})
	field = f


func _ready() -> void:
	set_anim_rate(true)
	_build_view()
	_build_units()
	_build_ui()
	_default_cam()
	cam.snap()
	_play_music(81)
	Game.play_sound(516)   # 进入战斗
	Game.quality_view(_w)
	_run_figtalk()
	_debug_keys()


## 调试: --hud-keys=ui_right,ui_accept,… 每隔 0.8 秒按一个键 (截图检查指令环 / 清单 / 游标); wait = 停一拍
func _debug_keys() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--hud-keys="):
			for k in a.substr(11).split(","):
				await get_tree().create_timer(0.8).timeout
				if k == "wait":
					continue
				while not hud.awaiting_input():
					await get_tree().process_frame
				await get_tree().create_timer(0.3).timeout
				var ev := InputEventAction.new()
				ev.action = k
				ev.pressed = true
				Input.parse_input_event(ev)
				await get_tree().create_timer(0.1).timeout
				var ev2 := InputEventAction.new()
				ev2.action = k
				ev2.pressed = false
				Input.parse_input_event(ev2)


# ---------------- 画面 (与地图相同: 3D 画面水平翻转显示) ----------------

func _build_view() -> void:
	var vlayer := CanvasLayer.new()
	vlayer.layer = 1
	add_child(vlayer)
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	vlayer.add_child(bg)
	_w = SubViewport.new()
	_w.own_world_3d = true
	_w.msaa_3d = Viewport.MSAA_4X
	_w.size = Game.view_px()
	get_window().size_changed.connect(func(): _w.size = Game.view_px())
	add_child(_w)
	var rect := TextureRect.new()
	rect.texture = _w.get_texture()
	rect.flip_h = true
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vlayer.add_child(rect)
	_tint_rect = ColorRect.new()
	_tint_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tint_rect.color = Color(1, 1, 1, 0)
	_tint_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
	_tint_rect.material = mat
	vlayer.add_child(_tint_rect)
	_world = Node3D.new()
	_w.add_child(_world)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	Enhance.apply(env, rect)   # 画面增强 (设定开关, 默认原版)
	Enhance.add_sun(_world, env, 120.0)   # 战斗镜头离得远, 阴影范围放大
	var we := WorldEnvironment.new()
	we.environment = env
	_w.add_child(we)
	_cam3d = Camera3D.new()
	_w.add_child(_cam3d)
	Enhance.add_dof(_cam3d, 14.0)   # 画面增强: 景深 (战斗镜头焦点约在战场中央)
	cam = OrigCamera.new(_cam3d)
	if bf.get("scene"):
		_load_bf_floor.call_deferred()
		var st := Game.load_glb("scenes/%s.glb" % bf.scene)
		if st:
			_world.add_child(st)
			unshade(st, true, true)
			for mi in st.find_children("*", "MeshInstance3D", true, false):
				for s in (mi as MeshInstance3D).get_surface_override_material_count():
					var sm := (mi as MeshInstance3D).get_surface_override_material(s) as StandardMaterial3D
					if sm:
						_scene_mats.append([sm, sm.albedo_color, sm.vertex_color_use_as_albedo])
			Enhance.light_world(st)
			_setup_bf_anim(st, str(bf.scene))
			if field and field.get("map_info") != null:
				var mo := Enhance.setup_map(_world, env, int(field.map_id), field.map_info, null)
				if mo:
					mo.position = Vector3(0, 1.5, 0)   # 战场中心   # 背面剔除 (原版 D3D): 镜头常在墙外, 从外面看墙应透明


## 战场场景动画 (逆向确认): 和地图同一个场景 ACT 播放器 0x41d1e3, 每个战斗逻辑拍 (0x4411fa → 0x4422ad) 执行一个 AP,
## 绘制用它产出的帧号; 初始化 0x43fe07 已先执行过一次, 所以第一次画面是第 2 个 AP。指令菜单 / 技能演出期间照常推进。
## 导出的时间轴按地图的 35 拍/秒 (wld2gltf), 这里播放速度乘 27/35; 逐帧贴图平移 (uv_anim) 同样按战斗拍。
## MAPS.DAT 第 15 段的贴图滚动只在地图绘制里做 (0x47815f), 战斗不滚
var _bf_uv: Array = []   # [{mats, frames}]
var _bf_t := 0.0


func _setup_bf_anim(st: Node, scene_name: String) -> void:
	for ap in st.find_children("*", "AnimationPlayer", true, false):
		var p := ap as AnimationPlayer
		if p.has_animation(scene_name):
			p.get_animation(scene_name).loop_mode = Animation.LOOP_LINEAR
			p.speed_scale = 27.0 / 35.0
			p.play(scene_name)
			p.seek(1.0 / 35.0, true)
			if OS.get_cmdline_user_args().has("--trace-events"):
				print("BFANIM %s len=%.3fs tracks=%d" % [scene_name, p.get_animation(scene_name).length, p.get_animation(scene_name).get_track_count()])
	var path := Game.extracted_dir.path_join("scenes/%s.markers.json" % scene_name)
	var info: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	if not info is Dictionary:
		return
	var uv: Dictionary = info.get("uv_anim", {})
	for node_name in uv:
		var n := st.find_child(str(node_name), true, false)
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
			_bf_uv.append({"mats": mats, "frames": uv[node_name].frames})
			Enhance.water(mats)
			if OS.get_cmdline_user_args().has("--trace-events"):
				print("BFUV %s mats=%d frames=%d" % [node_name, mats.size(), (uv[node_name].frames as Array).size()])


func _bf_anim_tick(delta: float) -> void:
	_bf_t += delta
	var tick := int(_bf_t / TICK) + 1
	for e in _bf_uv:
		var fr: Array = e.frames
		var k := tick % fr.size()
		var off := Vector3(float(fr[k][0]), float(fr[k][1]), 0)
		for m in e.mats:
			(m as StandardMaterial3D).uv1_offset = off
		Enhance.water_tick(e.mats, off)


## 默认战斗镜头 (0x44036a): 注视 (15, 40, −240), 角度 (16, 359, 0), 距离 1600
func _default_cam() -> void:
	for ch in 3:
		cam.set_mode(ch, 1)
	cam.set_target(Vector3(15, 40, -240))
	cam.set_angles(16, 359, 0)
	cam.set_distance(1600)
	cam.zoom_kt = 10.0


## vcolor: 场景 (WLD) 的「贴图 × 顶点色」—— 原版 TL 顶点 diffuse = 模型顶点色, DX6 默认 MODULATE (逆向见 tools/wld2gltf.py vertex_color);
## 暗场景的明暗烘在顶点色里。D3D 按字节相乘, 所以顶点色当 sRGB 处理 (实测: 贴图 200 × 顶点色 128 → 99, 当线性则 147)
func unshade(root: Node, cull := false, vcolor := false) -> void:
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			var m := mi.get_active_material(s)
			if m is StandardMaterial3D:
				var sm := (m as StandardMaterial3D).duplicate() as StandardMaterial3D
				sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				sm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC   # 斜看的墙面 / 地面不糊成条纹
				if sm.resource_name.contains("_blend"):   # WLD flags & 0xf == 2: 原版 SRCALPHA / INVSRCALPHA, 关 Z 写; alpha = 贴图 × 顶点 (tools/wld2gltf.py)
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
					# 背面剔除 (原版 D3D)。场景模型的绕序并不统一 (地图木工房剔除背面会消失), 战斗场景剔除背面显示正常
					sm.cull_mode = BaseMaterial3D.CULL_BACK
				if sm.resource_name.ends_with("_add"):
					sm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
					sm.vertex_color_use_as_albedo = true   # 顶点 alpha 决定加法层亮度 (wld2gltf: 地面光斑等)
				mi.set_surface_override_material(s, sm)


func to_world(g: Vector3) -> Vector3:
	return g * 0.01


func floor_at(_g: Vector3, _y: float, _dy := 0.0) -> Variant:
	return null


func world_node() -> Node:
	return _w


func cam3d() -> Camera3D:
	return _cam3d


func screen_pos(w: Vector3) -> Vector2:
	var p := _cam3d.unproject_position(w)
	var s := Vector2(_w.size)
	return Vector2((1.0 - p.x / s.x) * 800.0, p.y / s.y * 600.0)


## 对白窗口锚定: Dialog 用 1000+单位下标 作为说话者
func actor(key: int) -> FieldActor:
	var i := key - 1000
	if i >= 0 and i < units.size() and units[i]:
		var u: BattleUnit = units[i]
		return u.figure if u.figure and u.member == 1 else u.actor
	return null


# ---------------- 单位 ----------------

func _make_actor(act: int, p: Vector3, facing: float) -> FieldActor:
	var a := FieldActor.new()
	_world.add_child(a)
	a.setup(self, act, act)
	a.set_game_pos(p, false)
	a.set_facing(facing)
	return a


var _seen_ids := {}


func _build_units() -> void:
	units.resize(16)
	var k := 0
	for m in [1, 2, 3]:
		if State.test_flag(m):
			units[k] = _party_unit(m, k)
			k += 1
	if State.test_flag(1):
		# 车芸本体 (ObjDATA #11 的单位, 角色 1, 不参战; 0x440052)
		var fig := BattleUnit.new()
		fig.index = k
		fig.absent = true
		fig.name = "车芸"
		units[k] = fig
		for u in units:
			if u and u.member == 1:
				u.figure = _make_actor(1, FIGURE_POS, 180)
				fig.actor = u.figure
				face(u, 0)
		k += 1
	var i := 6
	for e in bf.get("enemies", []):
		var p: Array = e.pos
		units[i] = _enemy_unit(int(e.id), i, Vector3(p[0], p[1], p[2]), float(e.get("facing", 0)))
		if not _seen_ids.has(int(e.id)):   # 怪物图鉴: 进入战斗时战场里每种敌人各 +5 (0x440315)
			_seen_ids[int(e.id)] = true
			Fame.add_monster(int(e.id), 5)
		i += 1


func _party_unit(m: int, k: int) -> BattleUnit:
	var mem := State.member(m)
	var u := BattleUnit.new()
	u.index = k
	u.party = true
	u.member = m
	u.id = m
	u.rec = obj(m)
	u.name = str(u.rec.get("name", ""))
	u.level = int(mem.lv)
	u.hp = int(mem.hp)
	u.hp_max = int(mem.hp_max)
	u.mp = int(mem.mp)
	u.mp_max = int(mem.mp_max)
	u.sp = int(mem.sp)
	u.sp_max = int(mem.sp_max)
	u.juji = int(mem.get("juji", 0))
	u.base = State.member_stats(m)
	u.crit = int(u.base.get("crit", 0))
	var eq: Array = State.equip.get(m, [])
	u.weapon = obj(int(eq[0])).duplicate() if eq.size() and int(eq[0]) else {}
	u.accessory = obj(int(eq[2])).duplicate() if eq.size() > 2 and int(eq[2]) else {}
	u.home = PARTY_POS[m]
	u.facing = 180.0
	# 车芸的战斗单位画成云狐 (角色 0xb → ACT 11)
	u.actor = _make_actor(11 if m == 1 else m, u.home, u.facing)
	# 手持当前武器 (道具 ACT 第 1 号动作, 挂点 1): 嬴诗 / 桓远之拿在手上, 车芸的刀 (水云、冷烟…) 装在云狐身上
	if eq.size() and int(eq[0]):
		u.actor.set_held(int(eq[0]), 1, 3 if m == 1 else 1)   # 云狐把刀衔在嘴里 (挂点 3 在头部前端)
	face(u, 0)
	if u.hp <= 0:
		u.dead = true
		if u.actor.has_pose(26):
			u.actor.play(26)
			u.actor.pose_tick = u.actor.pose_len - 1   # 开场就倒着: 直接停在倒地动作末帧
	return u


func _enemy_unit(id: int, i: int, p: Vector3, facing: float) -> BattleUnit:
	var r := obj(id)
	var u := BattleUnit.new()
	u.index = i
	u.id = id
	u.rec = r
	var dr: Array = r.get("drops", [])
	u.tech_pool = int(dr[2][1]) if dr.size() > 2 else 0   # 机关侦查术可挖的存量 (掉落表第 2 组, 0x4311db)
	u.name = str(r.get("name", ""))
	u.level = int(r.get("level", 1))
	var sub := int(r.get("sub", 0))
	u.money = 0 if sub in [118, 119] else u.level * (50 if sub == 120 else 10)
	u.hp_max = maxi(int(r.get("hp", 1)), 1)
	u.hp = u.hp_max
	u.mp_max = int(r.get("mp", 0))
	u.mp = u.mp_max
	u.sp_max = int(r.get("sp", 0))
	u.sp = u.sp_max
	for k in ["atk", "def", "spd", "matk", "mdef", "hit", "eva", "mhit", "meva"]:
		u.base[k] = int(r.get(k, 0))
	u.crit = int(r.get("crit", 0))
	u.elem = r.get("elem", [0, 0, 0, 0, 0, 0, 0])
	u.weapon = r.duplicate()
	var w := obj(int(r.get("power", 0)))
	if w.has("elem"):
		u.weapon.elem = w.elem
	u.home = p
	u.facing = facing
	u.gauge = 50 + randi() % 150
	var act := int(r.get("act", id))   # 创意工坊 mod 怪物: 模型 / 动作用复制来源那只原版怪物的 ACT
	u.actor = _make_actor(act, p, facing)
	# 敌方手持武器 (ObjDATA 武器编号, 例 晋兵「敌方士兵枪」): 道具 ACT 第 1 号动作挂到挂点 1, 同我方嬴诗 / 桓远之
	var wid := int(r.get("power", 0))
	if wid >= 3000 and wid < 6000 and u.actor:
		u.actor.set_held(wid, 1, 1)
	if act in [2024, 2124, 2224, 2324] and u.actor:   # 四首木甲: 武器 ACT 第 3 号动作是头部转盘 (0x43dba7)
		u.actor.variant = u.variant
		u.actor.set_layer(wid)
	aura_setup(u)   # 首领光环 (开场全亮, 0x4402ae)
	return u


func alive(side_party: bool) -> Array:
	return units.filter(func(u): return u and u.party == side_party and not u.dead and not u.absent and u.actor)


# ---------------- 每帧 ----------------

var _hb := 0.0


## 战斗待机动作: 动作 14 (备战姿势, 循环) —— FIGTALK 用 set_unit_anim(…, 14) 让单位回到常态, 招式脚本也以动作 14 收尾。
## 单位当前是不循环的动作且已播完 (被击中 5、跳回原位、施法收招…) 时回到 14; 正在行动 / 防御 / 倒下的不动
## 我方表情 (0x436a5c(n) → 单位 +0x834/+0x836 = 表情 ACT 10001–10003 / QQ, 换脸部贴图, 同事件 set_expression):
##   0 常态 (开场、招式结束 0x43203e、受击动作结束 0x43b843) · 1 出招 (0x431aa3) · 3 受击 (0x433348) · 4 倒地 · 5 胜利 (0x443146)
const FACES := {1: [10001, {0: 13, 1: 60, 3: 67, 4: 67, 5: 20}], 2: [10002, {0: 13, 1: 51, 3: 92, 4: 66, 5: 39}],
	3: [10003, {0: 13, 1: 13, 3: 92, 4: 66, 5: 20}]}


func face(u: BattleUnit, n: int) -> void:
	if u == null or not u.party or not FACES.has(u.member):
		return
	# 车芸这个单位的模型是云狐, 表情只加在车芸本体 (figure) 上; 本体还没建好时不加 —
	# 云狐 ACT 11 的材质表第 5/6 格也被标成「脸」, 加上去会把云狐身上的贴图换成车芸的脸
	if u.member == 1 and u.figure == null:
		return
	var a: FieldActor = u.figure if u.figure else u.actor
	if a:
		a.set_expression(int(FACES[u.member][0]), int(FACES[u.member][1].get(n, 13)))
		if OS.get_cmdline_user_args().has("--trace-events"):
			print("FACE %s n=%d qq=%d mats=%d" % [u.name, n, int(FACES[u.member][1].get(n, 13)), a.meta.get("groups", [{}])[0].get("face_mats", {}).size()])


const IDLE_POSE := 14
const READY_POSE := 0x32      # 开指令环时的备战动作 (0x431787(0x32))
const VICTORY_POSE := 0x23    # 胜利动作 (0x443142)


## 状态染色 (0x432a6a, 车芸本体除外): 毒 (0x4) 1E A0 00, 石化 (0x10) 64 64 64, 咒封 (0x20) 00 BE E6, 按这个先后取第一个
func _status_tints() -> void:
	for u in units:
		if u == null or u.actor == null or u.absent:
			continue
		var c := Color.WHITE
		if u.has(Formula.ST_POISON):
			c = Color8(0x1E, 0xA0, 0x00)
		elif u.has(Formula.ST_STONE):
			c = Color8(0x64, 0x64, 0x64)
		elif u.has(Formula.ST_SEAL):
			c = Color8(0x00, 0xBE, 0xE6)
		u.actor.set_tint(c)


func _idle_tick() -> void:
	_status_tints()
	if result != "":
		return   # 胜负已分: 保持胜利 / 倒地动作
	for u in units:
		if u == null or u.actor == null or u.dead or u.defending or u == active or u == viewer_actor:
			continue
		if viewer_actor and u.actor == viewer_actor.figure:
			continue
		if u.absent or (active and u.actor == active.figure):
			continue   # 车芸本体 (不参战的附属单位): 云狐出招时由招式脚本控制, 不能被拉回待机 (机关侦查术跑过去 / 跑回来没有动作)
		if u.actor.pose == 12 and OS.get_cmdline_user_args().has("--trace-events"):
			print("IDLE_RUN unit=%d (待机中仍在跑步)" % units.find(u))
		_to_idle(u.actor)
		if u.figure:
			_to_idle(u.figure)


func _to_idle(a: FieldActor) -> void:
	var q := IDLE_POSE if a.has_pose(IDLE_POSE) else 0
	if a.pose == q:
		return
	# 站立 0 / 指令环备战 50 (循环) 在不行动时回到待机; 其它循环动作 (防御、状态动作…) 保持; 不循环的播完才回
	# 地图跑步 12 (敌兵没有冲刺 / 跳回动作时借用) 在战斗里不行动时也回待机
	if a.pose in [0, 12, READY_POSE] or (not a.pose_loop and a.pose_tick >= a.pose_len):
		a.play(q)


func _process(delta: float) -> void:
	_hb += delta
	_bf_anim_tick(delta)
	_scol_tick(delta)
	_talkmsg_tick(delta)
	if _dim:
		_dim.visible = not State.test_flag(8051)
	_turn_acc += delta
	while _turn_acc >= TICK:   # 单位绘制每帧一次 (战斗 27 帧/秒)
		_turn_acc -= TICK
		_turn_tick()
	_ov_acc += delta
	while _ov_acc >= Fx.TICK:
		_ov_acc -= Fx.TICK
		_ov_t += Fx.TICK
		_ov_tick()
		_aura_tick()
	if _cam3d:   # 画面增强景深: 对焦战场中心 (战斗镜头远近变化很大, 固定焦距会把整个战场都糊掉)
		Enhance.update_dof(_cam3d, _cam3d.global_position.distance_to(Vector3(0, 1.0, 0)))
	_update_decoys()
	if OS.get_cmdline_user_args().has("--trace-idle"):
		for u in units:
			if u and not u.party and u.actor and u.actor._skel:
				var sk: Skeleton3D = u.actor._skel
				print("IDLE f=%d pose=%d y=%.2f" % [Engine.get_process_frames(), u.actor.pose, sk.get_bone_global_pose(sk.find_bone("marker3_00")).origin.y])
				break
	if _hb > 2.0 and OS.get_cmdline_user_args().has("--trace-events"):
		_hb = 0.0
		print("HB acting=%s locked=%s result=%s intro=%d" % [acting, locked, result, _intro_runners])
	cam.tick(delta)
	_idle_tick()
	if result != "":
		return
	# 行动条走动时节拍加快 (偏离原版, 用户要求): 状态计时、毒、击退同一个节拍一起快, 平衡不变, 只是等得短; 演出速度不变
	_acc += delta * (ATB_RATE if not acting and not locked and _intro_runners == 0 else 1.0)
	while _acc >= TICK:
		_acc -= TICK
		if result == "":
			_knock_tick()
		if not acting and not locked and _intro_runners == 0:
			_atb_tick()


## 行动条击退 (0x436cba, 每个节拍、每个单位的状态机最先执行 — 有人在出招时也照样执行):
##   击退值 > 0 且行动条 > 0 时, 两者各减 max(1, 击退值 / 10), 行动条最低 0 → 被打中的人行动条看得见地往回退;
##   击退值 > 0 时清掉「已就绪」; 行动条退到 0 且正在吟咒会打断吟咒;
##   行动条已经是 0 时击退值不减, 留着在 _atb_tick 里先抵消增长 (0x4324c8)
func _knock_tick() -> void:
	for u in units:
		if u == null or u.dead or u.knock <= 0:
			continue
		if u.gauge > 0:
			var d := maxi(1, u.knock / 10)
			u.gauge = maxi(u.gauge - d, 0)
			u.knock = maxi(u.knock - d, 0)
			# 行动条被打退到 0: 解除吟咒 (只有从 > 0 推到 0 的这一拍); 已付的消耗不退
			if u.gauge <= 0 and u.chanting:
				u.chanting = false
				u.chant_speed = 0
				u.chant_fx = 1
				u.chant_fx_t = 0.0
				_message("%s解除吟咒状态!!" % u.name)


## 进入吟咒 (0x439e52): 显示「X进入吟咒状态!!」(盖掉技能名), 起咒 ATK 只是演出 (不结算); 行动条在起咒结束时清零 (0x43203e)
## 吟咒期间以吟咒速度涨行动条, 满了就自动释放; 消耗在进入时已付 (我方 _pay, 怪物的次数在选技能时已扣)
func _enter_chant(u: BattleUnit, r: Dictionary, ts: Array) -> void:
	u.chanting = true
	u.chant_speed = int(r.get("chant", 0))
	u.chant_rec = r
	u.chant_atk = 1000
	u.chant_targets = ts.slice(0, 16)
	u.chant_fx = 2
	u.chant_fx_t = 0.0
	_message("%s进入吟咒状态!!" % u.name)
	await _run_atk(u, ts, r, int(r.get("atk_id", 0)), false, false)


## 释放 (0x439f4f): 不进 AI / 指令环, 不再扣消耗; 全体 = 还活着的原目标; 单体原目标死了就按下标取对方阵营第一个活着的
func _release_chant(u: BattleUnit) -> void:
	hud_panel = false   # 0x43a16d: 吟咒释放 (敌我都算)
	var r := u.chant_rec
	u.chanting = false
	u.chant_speed = 0
	u.chant_fx = 0
	var ts: Array = []
	var scope := int(r.get("scope", 0))
	if scope == 2:
		ts = [u]
	else:
		ts = u.chant_targets.filter(func(t): return t and not t.dead and not t.absent)
		if scope == 0 and ts.is_empty():
			var side := int(r.get("side", 2))
			for t in units:
				if t and not t.dead and not t.absent and t.actor and (side == 0 or (t.party == u.party) == (side == 1)):
					ts = [t]
					break
			if ts.is_empty():
				ts = u.chant_targets.slice(0, 1)
	_message(str(r.get("name", "")))
	await _run_atk(u, ts, r, u.chant_atk, false)


## 行动条 (0x4324c8): 我方先、敌方后, 按下标; 满 1000 的第一个单位立即行动
func _atb_tick() -> void:
	_dbg_status()
	for u in units:
		if u == null or u.dead or u.absent or u.actor == null:
			continue
		# 每帧 (我方 0x44162b / 敌方 0x4418cf): 先走状态计时 0x435d1e (睡眠石化也照走), 再结算毒 0x4362c5, 最后行动条
		for m in u.status_tick():
			_message("%s%s了!!" % [u.name, m])   # 「%s解除X狀態了!!」(400,80), 先清旧消息
		if u.poison_dmg > 0 and OS.get_cmdline_user_args().has("--trace-events"):
			print("POISON %s hp=%d dmg=%d t=%.2f" % [u.name, u.hp, u.poison_dmg, Time.get_ticks_msec() / 1000.0])
		if u.poison_dmg > 0:
			# 毒伤 = 满一轮那一刻的当前 HP × 5%, 向下取整 → 永远毒不死; HP < 20 时为 0 不弹
			var d: int = u.poison_dmg
			u.poison_dmg = 0
			u.hp = maxi(u.hp - d, 0)
			hud.pop(u, "hp", d)
		var gain: int = (u as BattleUnit).eff_speed() / 10
		if u.knock > 0:
			u.knock -= gain
			if u.knock > 0:
				continue
			gain = -u.knock
			u.knock = 0
		u.gauge = mini(u.gauge + gain, 1000)
		if u.gauge >= 1000:
			u.gauge = 0
			_take_turn(u)
			return


var _dbg_status_done := false


## 调试: --status=槽:状态位:轮数 第一次有人行动前给该槽单位挂状态 (测试状态计时 / 毒)
func _dbg_status() -> void:
	if _dbg_status_done:
		return
	_dbg_status_done = true
	for fa in OS.get_cmdline_user_args():
		if fa.begins_with("--status="):
			var v := fa.substr(9).split(":")
			var su: Variant = units[int(v[0])] if int(v[0]) < units.size() else null
			if su:
				Formula.try_status(su, int(v[1]), int(v[2]))
				if OS.get_cmdline_user_args().has("--trace-events"):
					print("DBG_STATUS %s bit=%s turns=%s" % [su.name, v[1], v[2]])


func _take_turn(u: BattleUnit) -> void:
	if u.party and not u.summon and not u.chanting:
		hud_panel = true   # 0x441804: 我方单位轮到 (非吟咒、非护驾)
	# (以前这里把单位恢复成不透明, 依据是 0x441c76 → 0x433ff0; 复核后 0x441c76 是召护驾的生成, 不是行动开始, 删掉)
	acting = true
	active = u
	u.defending = false
	u.actions_taken += 1
	if viewer:
		u.gauge = 0   # 技能观看器: 谁都不自己行动
	elif skill_testing:
		await _skill_test_turn(u)
	elif u.chanting:
		await _release_chant(u)   # 吟咒放出不走回合开始处理 0x439245
	elif u.party and not u.summon:
		_turn_start(u)
		await _player_turn(u)
	else:
		_turn_start(u)
		if not u.dead:   # 被宣告死亡杀死 ([0x4e2a30] = −1) 就不行动
			await _enemy_turn(u)   # 敌人, 以及护驾 (用怪物自己的 AI 脚本, 阵营自动翻转)
	_check_down(u)
	actions_done += 1
	# 行动结束 (0x44134d–0x4413ad): 当前目标 [0x925254] 没死 → 逐渐转回默认朝向 (我方 180°, 敌方 0°)
	if _cur_target and not _cur_target.dead and is_instance_valid(_cur_target.actor):
		turn_unit(_cur_target, 180.0 if _cur_target.party else 0.0)
	_cur_target = null
	_guards_hide()
	hud_panel = true   # 0x4413da: 行动结束
	_check_end()
	active = null
	acting = false


# ---------------- 我方指令 ----------------

## 指令 (原版指令环 0x455266, 指令表 0x4e3ac8: 每个角色一行 — 上 攻击 / 下 防御 / 左 技能 (桓远之为天书) / 右 用器;
## 技能子环: 车芸 云狐 / 绝技 / 木甲 / 修复, 嬴诗 武术 / 绝技, 桓远之 奇术 / 绝技 / 收伏 / 护驾; 用器子环: 物品 (+ 法宝, 未做))
## 技能按分类码归类: 305 绝技, 306 木甲 (机关术), 302 修复, 其余 (201 攻击 / 202 恢复 / 203 辅助) 归第一项, 清单分三页
const MAIN_CMDS := {1: ["攻击", "防御", "技能", "用器"], 2: ["攻击", "防御", "技能", "用器"], 3: ["攻击", "防御", "天书", "用器"]}
const SKILL_CMDS := {1: ["云狐", "绝技", "木甲", "修复"], 2: ["武术", "绝技", "", ""], 3: ["奇术", "绝技", "收伏", "护驾"]}
const SKILL_SUBS := [[201, 202, 203], [305], [306], [302]]


func auto_pick() -> bool:
	return Game.demo or OS.get_cmdline_user_args().has("--auto-battle") or (hud != null and hud.auto)


## 我方回合镜头 (0x4439c4, 开指令环时调用): 先把当前镜头存为「招式前镜头」, 再瞬切 (模式 1) 到该队员的特写;
## 招式脚本最后的 restore 回到存下的远景。自动战斗 (0x44538c) 在开指令环之前就出手, 没有特写。
## 旗标 8000 置位时不切 (原版的镜头开关)
const TURN_CAM := {
	1: [Vector3(-260.45, 145, -443.83), Vector3(15, 198, 0), 490.0],   # 车芸 (云狐)
	2: [Vector3(-60.76, 173, -395.71), Vector3(1, 205, 0), 340.0],     # 嬴诗
	3: [Vector3(81.8, 191, -462.03), Vector3(6, 194, 0), 370.0]}       # 桓远之
var _turn_cam_saved := false
var _turn_closeup := false    # 这个回合用特写


func _player_turn(u: BattleUnit) -> void:
	var closeup := not auto_pick() and not State.test_flag(8000) and TURN_CAM.has(u.member) and not hud.want_escape
	if not auto_pick() and u.actor and u.actor.has_pose(READY_POSE):
		u.actor.play(READY_POSE)   # 开指令环: 备战动作
	_turn_closeup = closeup
	_turn_cam_start(u)
	await _player_turn_body(u)
	_turn_closeup = false
	_end_turn_cam()


## 开指令环 / 选目标取消回到指令环 (0x44e482): 瞬切到该队员的特写
func _turn_cam_start(u: BattleUnit) -> void:
	if not _turn_closeup or _turn_cam_saved:
		return
	_saved_cam = {"ft": cam.ft, "angt": cam.angt, "dt": cam.dt, "follow": cam.follow, "off": cam.follow_off}
	_turn_cam_saved = true
	var tc: Array = TURN_CAM[u.member]
	cam.follow = null
	for ch in 3:
		cam.set_mode(ch, 1)
	cam.set_target(tc[0])
	cam.set_angles(tc[1].x, tc[1].y, tc[1].z)
	cam.set_distance(tc[2])


## 进入选目标 (0x44e6a7 开头) 或指令确定后 (0x44380b): 瞬切回特写之前的镜头 —— 特写只在选指令时出现
func _end_turn_cam() -> void:
	if not _turn_cam_saved:
		return
	_turn_cam_saved = false
	for ch in 3:
		cam.set_mode(ch, 1)   # 瞬切
	cam.follow = _saved_cam.get("follow")
	cam.follow_off = _saved_cam.get("off", Vector3.ZERO)
	cam.set_target(_saved_cam.get("ft", cam.ft))
	var ag: Vector3 = _saved_cam.get("angt", cam.angt)
	cam.set_angles(ag.x, ag.y, ag.z)
	cam.set_distance(float(_saved_cam.get("dt", cam.dt)))


func _restore_cam() -> void:
	for ch in 3:
		cam.set_mode(ch, 3)
		cam.set_speed(ch, 6)
	cam.follow = _saved_cam.get("follow")
	cam.follow_off = _saved_cam.get("off", Vector3.ZERO)
	cam.ft = _saved_cam.get("ft", cam.ft)
	var ag: Vector3 = _saved_cam.get("angt", cam.angt)
	cam.set_angles(ag.x, ag.y, ag.z)
	cam.set_distance(float(_saved_cam.get("dt", cam.dt)))


func _player_turn_body(u: BattleUnit) -> void:
	if hud.want_escape:
		hud.want_escape = false
		await _try_escape(u)
		return
	# 自动战斗: 生命低于 35% 时先用恢复道具
	if auto_pick() and u.hp * 100 < u.hp_max * 35:
		for it in State.items:
			var rh := obj(int(it))
			if int(rh.get("sub", 0)) == 202 and int(rh.get("atk_id", 0)):
				State.give_item(int(it), -1)
				await _do_action(u, rh, [u])
				return
	# 自动战斗: 敌人全都物防极高 (如彩障之阵 9999) 时改用仙术
	if auto_pick() and not u.dead:
		var foes := alive(false)
		if foes.size() and foes.all(func(x): return int(x.base.get("def", 0)) >= 5000):
			for s2 in _skills_of(u, [201, 302, 305, 306]):
				var rs := obj(int(s2))
				var cs: Dictionary = rs.get("cost", {})
				if int(rs.get("side", 2)) == 2 and Formula.cost_of(int(cs.get("mp", 0)), u.mp_max) <= u.mp \
						and Formula.cost_of(int(cs.get("sp", 0)), u.sp_max) <= u.sp:
					var tsk: Variant = await _choose_target(u, 2, int(rs.get("scope", 0)))
					if tsk != null:
						_pay(u, rs)
						await _do_action(u, rs, tsk if tsk is Array else [tsk])
						return
	var m: int = clampi(u.member, 1, 3)
	var dead := u.dead
	for fa in OS.get_cmdline_user_args():   # 调试: --force-cmd=artifact:ID 直接用法宝 (不看装备)
		if fa.begins_with("--force-cmd=artifact:") and not dead and u.member == (int(fa.get_slice(":", 2)) if fa.get_slice_count(":") > 2 else 1):   # …:ID[:队员]
			if await _use_artifact(u, int(fa.get_slice(":", 1))):
				return
	if m == 3 and not dead:   # 调试: --force-cmd=capture / summon 让桓远之直接收化 / 召护驾
		for fa in OS.get_cmdline_user_args():
			if fa == "--force-cmd=capture" and await _capture(u):
				return
			if fa == "--force-cmd=summon" and await _summon(u):
				return
	while true:
		var labels: Array = MAIN_CMDS[m]
		var k := await hud.ring(labels, [not dead, not dead, true, true])
		match k:
			0:
				var t: Variant = await _choose_target(u, 2, 0)
				if t == null:
					continue
				await _do_attack(u, [t])
				return
			1:
				await _do_defend(u)
				return
			2:
				var subl: Array = SKILL_CMDS[m]
				var en: Array = []
				for c in 4:
					if m == 3 and c >= 2:
						en.append(not dead)   # 桓远之 收伏 / 护驾: 指令环里从不画灰, 不能用时选了才提示 (0x44fc7c / 0x44fe7c)
					else:
						en.append(str(subl[c]) != "" and _skills_of(u, SKILL_SUBS[c]).size() > 0 and (not dead or c == 3))
				var c2 := await hud.ring(subl, en, true, str(labels[2]))
				if c2 < 0:
					continue
				if m == 3 and c2 == 2:
					if await _capture(u):
						return
					continue
				if m == 3 and c2 == 3:
					if await _summon(u):
						return
					continue
				var subs: Array = SKILL_SUBS[c2]
				var pages: Array = []
				for sb in (subs if subs.size() > 1 else [subs]):
					pages.append(_skill_entries(u, sb if sb is Array else [sb]))
				var sk: Variant = await hud.list(str(subl[c2]), pages, 0 if subs.size() > 1 else -1)
				if sk == null:
					continue
				var r := obj(int(sk))
				var ts: Variant = await _choose_target(u, int(r.get("side", 2)), int(r.get("scope", 0)))
				if ts == null:
					continue
				_pay(u, r)
				await _do_action(u, r, ts if ts is Array else [ts])
				return
			3:
				# 用器子环: 上 物品, 左 / 右 = 两个法宝栏 (标签 0x4e3a48[法宝编号 − 5186]; 5203 / 5209 是被动的, 不能使用)
				var fb: Array = _artifact_slots(u)
				var c3 := await hud.ring(["物品", "", ARTIFACT_LABEL.get(fb[0], ""), ARTIFACT_LABEL.get(fb[1], "")],
					[true, false, fb[0] > 0, fb[1] > 0], true, "用器")
				if c3 < 0:
					continue
				if c3 >= 2:
					if await _use_artifact(u, int(fb[c3 - 2])):
						return
					continue
				var pages2: Array = []
				for sb in [201, 202, 203]:
					pages2.append(_item_entries(sb))
				var pg := 1 if pages2[0].is_empty() and pages2[1].size() else 0
				var it2: Variant = await hud.list("物品", pages2, 1, pg)
				if it2 == null:
					continue
				var ri := obj(int(it2))
				var ti: Variant = await _choose_target(u, int(ri.get("side", 1)), int(ri.get("scope", 0)))
				if ti == null:
					continue
				State.give_item(int(it2), -1)
				await _do_action(u, ri, ti if ti is Array else [ti])
				return


# ---------------- 收化 (指令 11, 0x44fc7c / 0x43c2ac) ----------------

## 成功率 (0x432e84): d = 桓远之等级 − 目标等级; H/M = 目标当前 / 最大生命 (整数除法); 成功 = rand%100 ≤ t
static func capture_chance(d: int, hp: int, hp_max: int, sub_: int, story_: bool) -> int:
	if story_ or sub_ == 120:
		return -1
	var q4 := hp <= hp_max / 4
	var q3 := hp <= hp_max / 3
	var q2 := hp <= hp_max / 2
	if d > 10:
		return 99
	if d >= 6:
		return 99 if q2 else 70
	if d >= 1:
		return 99 if q2 else 60
	if d >= -5:
		return 70 if q4 else (60 if q3 else (50 if q2 else 30))
	if d >= -10:
		return 40 if q4 else (30 if q3 else (20 if q2 else 15))
	if d >= -20:
		return 5 if q3 else -1
	if d >= -30:
		return 5 if q4 else -1
	if d >= -40:
		return 2 if q4 else -1
	return -1


## 收化几率 (u = 桓远之, t = 目标); 创意工坊 mod 怪物不能收化 (收化后进天书居民 / 护驾 / 生产, 那些系统按原版怪物号查数据)
func capture_odds(u: BattleUnit, t: BattleUnit) -> int:
	if t.rec.has("mod"):
		return -1
	return capture_chance(u.level - t.level, t.hp, t.hp_max, int(t.rec.get("sub", 0)), story)


func _fx_at(key: String, gpos: Vector3, facing: float) -> Fx:
	if not Fx.has(key):
		return null
	return Fx.spawn(world_node(), key, to_world(gpos), Basis(Vector3.UP, deg_to_rad(-facing)), cam3d())


func _fx_len(key: String) -> float:
	return float(Fx._db.get(key, {}).get("ticks", 30)) * Fx.TICK if Fx.has(key) else 0.5


## 返回 false = 没有行动 (提示后回到指令环)
func _capture(u: BattleUnit) -> bool:
	if story:
		_message("无法收化!!")
		Game.play_sound(0x20e)
		return false
	if MenuTianshu.capacity_of(State.ts_houses) <= State.ts_residents.size():
		_message("怪物居住空间不够，无法收化!!")
		Game.play_sound(0x20e)
		return false
	var pool := alive(false).filter(func(x): return not x.summon)
	if pool.is_empty():
		_message("没有可以作用的目标!!")
		Game.play_sound(0x20e)
		return false
	_end_turn_cam()
	var tv: Variant = pool[0] if pool.size() == 1 else await hud.pick(pool)
	if tv == null:
		_turn_cam_start(u)
		return false
	var t: BattleUnit = tv
	face(u, 1)
	# 演出 (§1.2, 按 27 拍/秒): 0x39 → 法器 8003 动作 5 挂在手上 → 0x3a 循环 → 判定
	if u.actor.has_pose(0x39):
		u.actor.play(0x39)
		await get_tree().create_timer(u.actor.pose_len * FieldActor.TICK).timeout
	var hand: Variant = marker_pos(u, 1)
	var hp: Vector3 = (hand if hand != null else u.pos() + Vector3(0, 120, 0)) + Vector3(0, -20, 65)
	var tool := _fx_at("8003_5", hp, u.actor.facing)
	if tool:
		tool.hold_last = true   # 法器是施法者 +0x8b4 的播放器: 非循环, 播完停在末帧 (以前设成循环播放)
	if u.actor.has_pose(0x3a):
		u.actor.play(0x3a, true)
	# 子状态 2: 法器动作逐帧前进, 到它的命中帧 (8003_5 的 d 记号) 才掷收化判定 (以前等整段动画播完)
	var hit_tick := 0
	for ev in Fx._db.get("8003_5", {}).get("events", []):
		if str(ev.get("type", "")) == "hit":
			hit_tick = int(ev.tick)
			break
	await get_tree().create_timer(hit_tick * Fx.TICK).timeout
	var c := capture_odds(u, t)
	var ok := c >= 0 and randi() % 100 <= c
	if OS.get_cmdline_user_args().has("--trace-events"):
		print("CAPTURE %s chance=%d ok=%s" % [t.name, c + 1, ok])
	if ok:
		Fame.add_monster(t.id, 100)   # 认识度直接 +100 (0x44c5d7)
		t.captured = true
		t.hp = 0
		_check_down(t)
		# 子状态 0x32: 等目标死亡动作走完 (0x43481a: +0x19e8 ≠ 0 且 +0x19e4 == 0) 再 add_resident (以前写的是「至少 0.6 秒」)
		while is_instance_valid(t.actor) and t.actor.pose == 26 and t.actor.pose_tick < t.actor.pose_len - 1:
			await get_tree().process_frame
		State.ts_residents.push_front({"id": t.id, "house": 0})   # add_resident: 当场插到居民链表头
		_message("收化成功!!")
	else:
		for k in 5:   # 40 拍挣扎, 每 8 拍受击一下
			hurt(t)
			await get_tree().create_timer(8.0 / 27.0).timeout
		var e := t.level - u.level
		var msg := "收化失败!!"
		if int(t.rec.get("sub", 0)) == 120:
			msg = "无法收化!!"
		elif e >= 11 and e <= 20:
			msg = "捉妖失败，机率偏低!!"
		elif e >= 21 and e <= 30:
			msg = "捉妖失败，难以捕捉!!"
		elif e >= 31 and e <= 40:
			msg = "捉妖失败，极低机率!!"
		_message(msg)
	await get_tree().create_timer(30.0 / 27.0).timeout
	if is_instance_valid(tool):
		tool.queue_free()
	var back := _fx_at("8003_6", hp, u.actor.facing)
	if back:
		back.hold_last = true
	await get_tree().create_timer(_fx_len("8003_6")).timeout   # 子状态 0x35: 等收回动作播完 (+0x974&1) 就清掉
	if is_instance_valid(back):
		back.queue_free()
	if u.actor.has_pose(0x3b):
		u.actor.play(0x3b)
		await get_tree().create_timer(u.actor.pose_len * FieldActor.TICK).timeout
	face(u, 0)
	u.gauge = 0
	return true


# ---------------- 护驾 (指令 12, 0x44fe7c / 0x441b15; 记录 0xa7ffe0 = 鬼神阵位置 0 的居民 + 后备加成) ----------------

## 第 k 座鬼神阵 (类型 9, 最多 2 座) 的护驾记录: 主护驾 = 位置 0 的居民, 位置 1–4 的后备按比例加到主护驾 (0x4a54c7)
func guard_rec(k: int) -> Dictionary:
	var hs := State.ts_houses.filter(func(h): return int(h.type) == 9)
	if k >= hs.size():
		return {}
	var sl: Array = hs[k].get("slots", [])
	if sl.is_empty():
		return {}
	var r := obj(int(sl[0])).duplicate(true)
	r["_id"] = int(sl[0])
	var div := {"hp": 4, "mp": 4, "sp": 4, "atk": 10, "def": 12, "matk": 24, "mdef": 15}   # 速度加成原版写错字段, 不生效
	for key in div:
		var add := 0
		for i in range(1, sl.size()):
			add += int(obj(int(sl[i])).get(key, 0))
		r[key] = int(r.get(key, 0)) + add / int(div[key])
	return r


var _guard_out := {}   # 鬼神阵序号 → 场上的护驾单位


func _summon(u: BattleUnit) -> bool:
	# 护驾清单 (0x44fe7c / 0x458aed): 两个鬼神阵位置各一行; 空行确认时才提示没有护驾 (0x44dfe6)
	var rows: Array = []
	for k0 in 2:
		var r0 := guard_rec(k0)
		rows.append({} if r0.is_empty() else {"rec": r0, "out": _guard_out.has(k0)})
	var k := -1
	while true:
		var pick: Variant = await hud.guard_list(rows)
		if pick == null:
			return false
		k = int(pick)
		if (rows[k] as Dictionary).is_empty():
			_message("【鬼神阵】没有安排护驾")
			Game.play_sound(0x20e)
			continue
		if not _guard_out.has(k):
			if not _can_pay(u, guard_rec(k)):   # 0x44ded1 → 0x434470 不通过: 提示, 留在清单
				_message("能力不足,无法呼唤护驾!!")
				Game.play_sound(0x20e)
				continue
			break
		# 已在场 → 退驾确认 (状态 8 → 0x44de29): 护驾每帧 +25 淡入, 弹「是否退驾？」(0x466f7d(400, 280, …)), 状态 0xb 等回答 (0x44e00a)
		var g: BattleUnit = _guard_out[k]
		fade_unit(g, false, 0x19)
		if await _ask_choice("是否退驾？　%B 是 .  %B 否 . %Q") == 0:
			await _dismiss(u, g)
			return true
		fade_unit(g, true, 0x19)   # 选「否」: 淡出, 回到护驾清单 (状态 8)
	var r := guard_rec(k)
	_pay(u, r)
	_end_turn_cam()
	face(u, 1)
	# 子状态 0 (0x441b15): 桓远之播动作 0x32, 等它的命中帧 (动作里的 d 记号, 0x43c11c 的 0x80000000) 才放出护驾 (以前是「动作时长 × 0.6」)
	if u.actor.has_pose(0x32):
		u.actor.play(0x32)
		var hit := u.actor.pose_len - 1
		for mk in u.actor.meta.poses[str(0x32)].get("marks", []):
			if str(mk[1]) == "d":
				hit = int(mk[0])
				break
		while u.actor.pose == 0x32 and u.actor.pose_tick < hit:
			await get_tree().process_frame
	# 站位 (0x4e2a68): 第 0 只 (100,80,−200), 第 1 只 (−100,80,−200); 兕 / 幻影踏弩 / 机关龙神 另有固定坐标
	var fixed := {1055: Vector3(283, 80, -121), 1076: Vector3(465, 85, -201), 1093: Vector3(240, 80, -305)}
	var id := int(r["_id"])
	var p: Vector3 = fixed.get(id, Vector3(100 if k == 0 else -100, 80, -200))
	var i := units.find(null)
	if i < 0 or i >= 6:
		i = 5
	var g := _enemy_unit(id, i, p, 180.0)
	g.party = true
	g.summon = true
	g.guard_k = k
	g.rec = r
	for key in ["hp", "mp", "sp"]:
		g.set(key + "_max", maxi(int(r.get(key, 0)), 1 if key == "hp" else 0))
	g.hp = g.hp_max   # HP 取护驾记录的当前值 (0x43127e); 记录在战斗中不回写 (退驾不保存剩余生命), 平时就是上限
	g.mp = g.mp_max
	g.sp = g.sp_max
	for key in ["atk", "def", "matk", "mdef"]:
		g.base[key] = int(r.get(key, 0))
	g.gauge = 0
	units[i] = g
	_guard_out[k] = g
	# 0x434947(0, 0x19): 从全透明每帧 +25 淡入; 子状态 0x33 等淡入完 (+0x19f8 == 0) → 0x34 结束行动
	# (以前是 0.6 秒补间 + 多等 0.7 秒, 还弹了一条原版没有的「护驾：xx」提示)
	fade_unit(g, false, 0x19)
	await get_tree().create_timer(ceilf(255.0 / 0x19) * TICK).timeout
	face(u, 0)
	u.gauge = 0
	return true


## 护驾平时是隐身的 (逆向 0x44e9a9(−1), 由行动结束的处理 0x441347 调用): 任何单位行动结束后, 在场、活着、不在死亡状态的
## 护驾都每帧 −25 淡出 (0x434947(1, 0x19)); 只在招式涉及它时显示。隐身时仍可被选为目标 (AI 选目标不看透明度)
## 未实现: AI 单体选中护驾时先以 20/帧淡入 (0x402e81, 随后招式入队立即全显); 吟咒中的护驾轮到时淡入 (0x4417c5)
var _cur_target: BattleUnit = null


## 回合开始 0x439245 (行动条满、出指令 / AI 之前; 吟咒放出不走): 回合数 +1 → 完璧 → 挪移 → 自动情绪
## 未实现: 宣告死亡 (+0x1b78, 由某种效果设为 3, 来源未查)
func _turn_start(u: BattleUnit) -> void:
	u.turn_count += 1
	if u.wanbi_turns > 0:
		u.wanbi_turns -= 1
		if u.wanbi_turns <= 0:
			u.wanbi_rate = 0
			_message("%s解除【完璧】功能!!" % u.name)
	if u.redirect:
		u.nuoyi_turns -= 1
		if u.nuoyi_turns <= 0:
			_nuoyi_clear(u, true)
	# 宣告死亡: 倒数 > 0 → −1 并弹出新的数字; 到 0 → 以当前 HP 弹伤害、HP = 0、清空状态, 倒地 (3 → 2 → 1 → 第三次轮到时 0 并死亡)
	if u.doom > 0:
		u.doom -= 1
		if OS.get_cmdline_user_args().has("--trace-events"):
			print("DOOM %s -> %d" % [u.name, u.doom])
		hud.pop(u, "doom", u.doom)
		if u.doom == 0:
			u.doom = -1
			hud.pop(u, "hp", u.hp)
			u.hp = 0
			for b in Formula.STATUS_NAMES:
				u.clear_status(b)
			_check_down(u)
	_auto_emotion(u)


## 挪移转向 (0x43af60, 对被打的单位): 只转法术 (记录 kind 3), 子类 202 / 203 / 302 的招式到来时挪移整个失效;
## 转向对象已死也失效; 次数 ≤ 0 不转; 否则次数 −1 (到 0 时解除并提示), 这一次照样转过去
func _nuoyi_target(t: BattleUnit, rec: Dictionary) -> BattleUnit:
	if t.redirect == null or rec.get("_normal", false) or int(rec.get("kind", 0)) != 3:
		return t
	if int(rec.get("sub", 0)) in [202, 203, 302] or t.redirect.dead or not is_instance_valid(t.redirect.actor):
		_nuoyi_clear(t, false)
		return t
	if t.nuoyi_uses <= 0:
		return t
	var to := t.redirect
	t.nuoyi_uses -= 1
	if t.nuoyi_uses <= 0:
		_nuoyi_clear(t, true)
	return to


## 视破判定 (0x43a49d, 不用随机数): 按法宝修练等级 L 和等级差 d = 自身等级 − 目标等级:
##   L ≤ 1: d ≥ 5; L = 2: 自身等级 ≥ 目标等级; L = 3: d ≥ −10; L = 4: d ≥ −20; L = 5: 必定成功
##   (原版先用「类型 1」去认识度表查怪物编号, 查到就直接成功; 类型 1 是法宝修练记录, 编号 5201 起, 实际查不到, 这里不做)
## 成功: 认识度 +100 (0x44c5d7) 并打开属性面板 [0x925950] = 1 —— 施法者的行动一直不结束 (行动条全停),
##   直到按下 Enter / 空格 / 小键盘 Enter / 左键 / 右键 / Ctrl / Esc (0x44cc2b), 没有计时、没有音效
## 失败: 「视破失败」(400,80, 2 秒)
func _spy(u: BattleUnit, t: BattleUnit) -> void:
	var lv := State.artifact_level(5205)
	var d := u.level - t.level
	var ok := false
	match lv:
		0, 1:
			ok = d >= 5
		2:
			ok = u.level >= t.level
		3:
			ok = d >= -10
		4:
			ok = d >= -20
		5:
			ok = true
	if not ok:
		_message("视破失败")
		return
	Fame.add_monster(t.id, 100)
	hud.spy = t
	await get_tree().process_frame
	hud._drop_clicks()
	var auto_t := 0.0
	while true:
		await get_tree().process_frame
		if auto_pick():
			auto_t += get_process_delta_time()
			if auto_t > 1.0:
				break
		if Input.is_action_just_pressed("ui_accept") or Input.is_key_pressed(KEY_ESCAPE) or Input.is_key_pressed(KEY_CTRL) \
				or Input.is_key_pressed(KEY_KP_ENTER) or hud._clicked() or hud._rclicked():
			break
	hud.spy = null


## 法宝「双重」(5207, 指令 21 → 0x45011a / 0x450228 / 0x44eb65, 逆向确认):
## * 使用: 提示「双重：请选择第一式」(400,40); 咒封中 → 0x20e +「现在无法使用!!」, 回到用器环
## * 清单 = 该角色技能子环第一项的法术清单 (子类 201 / 202 / 203); 确定时消耗检查 0x434470 —— 选第二式时两式消耗相加再比
##   不够 → 0x20e +「条件不足，无法施展。」(400,40), 留在清单; 够 → 0x200, 选目标
## * 第一式目标选好 → 提示「双重：请选择第二式」(400,80), 再检查一次咒封, 重开清单; 第二式目标选好 → 执行
## * 取消: 第二式清单 → 回到第一式 (重新提示); 第一式清单 → 双重作废回用器环, 不扣任何东西; 选目标时取消 → 回清单
## * 执行: 第一式扣自己的消耗 → 演出; 演出结束同一帧接第二式 (两式只算一个回合, 中间行动条不走):
##   敌人全灭 → 放弃; 单体且目标已死 → 改成第一个活着的敌人; 目标全死 → 放弃; 单式消耗检查不过 → 0x20e 放弃 (无提示);
##   否则扣第二式消耗 → 演出。第二式不检查吟咒、不走回合开始处理
func _double(u: BattleUnit) -> bool:
	var m: int = clampi(u.member, 1, 3)
	_message("双重：请选择第一式", 40)
	if u.has(Formula.ST_SEAL):
		Game.play_sound(0x20e)
		_message("现在无法使用!!")
		return false
	var picks: Array = []   # [[记录, 目标表]]
	while true:
		var pages: Array = []
		for sb in SKILL_SUBS[0]:
			pages.append(_skill_entries(u, [sb]))
		var sk: Variant = await hud.list(str(SKILL_CMDS[m][0]), pages, 0)
		if OS.get_cmdline_user_args().has("--trace-events"):
			print("DOUBLE pick=%s picks=%d pages=%s" % [str(sk), picks.size(), str(pages.map(func(x): return x.size()))])
		if sk == null:
			Game.play_sound(0x1ff)
			if picks.size() == 1:
				picks.clear()
				_message("双重：请选择第一式", 80)
				continue
			return false
		var r := obj(int(sk))
		if not _double_can_pay(u, picks, r) or not _usable_extra(r, int(sk)):
			Game.play_sound(0x20e)
			_message("条件不足，无法施展。", 40)
			continue
		Game.play_sound(0x200)
		var tv: Variant = await _choose_target(u, int(r.get("side", 2)), int(r.get("scope", 0)))
		if tv == null:
			continue
		picks.append([r, tv if tv is Array else [tv]])
		if picks.size() == 1:
			_message("双重：请选择第二式", 80)
			if u.has(Formula.ST_SEAL):
				Game.play_sound(0x20e)
				_message("现在无法使用!!")
				return false
			continue
		break
	var r1: Dictionary = picks[0][0]
	_pay(u, r1)
	await _do_action(u, r1, picks[0][1])
	var foes := alive(false)
	if foes.is_empty():
		return true
	var r2: Dictionary = picks[1][0]
	var t2: Array = (picks[1][1] as Array).filter(func(x): return x and not x.dead and not x.absent)
	if t2.is_empty():
		if int(r2.get("scope", 0)) == 0:
			t2 = [foes[0]]
		else:
			return true
	if not _can_pay(u, r2):
		Game.play_sound(0x20e)
		return true
	_pay(u, r2)
	await _do_action(u, r2, t2)
	return true


## 0x434512: 选第二式时 (双重模式 2) 把第一式的生命 / 体力 / 灵力 / 绝技消耗加进来一起比
func _double_can_pay(u: BattleUnit, picks: Array, r: Dictionary) -> bool:
	if picks.is_empty():
		return _can_pay(u, r)
	var c1: Dictionary = (picks[0][0] as Dictionary).get("cost", {})
	var c2: Dictionary = r.get("cost", {})
	var mp := Formula.cost_of(int(c1.get("mp", 0)), u.mp_max) + Formula.cost_of(int(c2.get("mp", 0)), u.mp_max)
	var sp := Formula.cost_of(int(c1.get("sp", 0)), u.sp_max) + Formula.cost_of(int(c2.get("sp", 0)), u.sp_max)
	var hp := Formula.cost_of(int(c1.get("hp", 0)), u.hp_max) + Formula.cost_of(int(c2.get("hp", 0)), u.hp_max)
	var jj := int(c1.get("juji", 0)) + int(c2.get("juji", 0))
	return u.mp >= mp and u.sp >= sp and u.hp > hp and u.juji >= jj


func _nuoyi_clear(u: BattleUnit, msg: bool) -> void:
	u.redirect = null
	u.nuoyi_turns = 0
	u.nuoyi_uses = 0
	if msg:
		_message("%s解除【挪移】功能!!" % u.name)


## 自动情绪 (0x439245 后段): 护驾跳过; 装备青莲心灯 (4916) 的跳过; 敌方实际不会产生 (前三种被跳过, 悲哀要濒死位, 只有我方有)。
## 四项依次检查, 可以连续触发 (后一个顶掉前一个); 概率 = rand%100 ≤ 门槛; 没触发计数保留, 条件不满足计数清零; 持续 5 轮
func _auto_emotion(u: BattleUnit) -> void:
	if not u.party or u.summon:
		return
	if (State.equip.get(u.member, []) as Array).has(4916):
		return
	if u.hp >= u.hp_max and not u.has(Formula.ST_JOY):
		u.emo_joy += 1
		if _emo_roll(u.emo_joy, {5: 20, 6: 40, 7: 70}, 8):
			u.emo_joy = 0
			_emotion(u, Formula.ST_JOY)
	else:
		u.emo_joy = 0
	if u.juji == 100 and not u.has(Formula.ST_MANIA):
		u.emo_mania += 1
		if _emo_roll(u.emo_mania, {5: 20, 6: 50, 7: 75}, 8):
			u.emo_mania = 0
			_emotion(u, Formula.ST_MANIA)
	else:
		u.emo_mania = 0
	if not u.has(Formula.ST_RAGE) and units.any(func(x): return x and x != u and x.party and x.dead):
		if randi() % 100 <= 50:
			u.emo_sorrow = 0
			_emotion(u, Formula.ST_RAGE)
	if u.low_hp() and not u.has(Formula.ST_SORROW):
		u.emo_sorrow += 1
		if _emo_roll(u.emo_sorrow, {4: 25, 5: 50, 6: 75}, 7):
			u.emo_sorrow = 0
			_emotion(u, Formula.ST_SORROW)
	else:
		u.emo_sorrow = 0


func _emo_roll(cnt: int, table: Dictionary, always: int) -> bool:
	if cnt >= always:
		return true
	if not table.has(cnt):
		return false
	return randi() % 100 <= int(table[cnt])


func _emotion(u: BattleUnit, bit: int) -> void:
	if Formula.try_status(u, bit, 5):
		_message("%s变成%s状态了!!" % [u.name, Formula.STATUS_NAMES.get(bit, "")])


func _guards_hide() -> void:
	for g in _guard_out.values():
		if is_instance_valid(g.actor) and not g.dead and g.actor.visible:
			fade_unit(g, true, 0x19)


## 单行提示框 0x466f7d (版式见 Dialog.tip_layout)。带 %B 选项时 (0x4649cf / 0x465656):
##   鼠标进入按钮判定矩形 → 选中 (换了就播 0x201); 左键在矩形里确认; ←/↑ 选上一个、→/↓ 选下一个 (到头不循环, 照样播 0x201);
##   Enter / 空格 / 小键盘 Enter 确认; 默认选第 0 项。有选项时计时暂停 (选完才继续), 没选项时到时自动关
## 未实现: 取消键在 [0x9f2e90] = 0 时等于选第 0 项 (该标志战斗里的取值未查), 先忽略取消键
var _tm := {}   # {text, center, sel, nbtn, left (秒), answer, rects}


func _talkmsg(text: String, center: Vector2, secs: float, rects: Array = []) -> void:
	var L := Dialog.tip_layout(text, center)
	_tm = {"text": text, "center": center, "sel": 0, "nbtn": L.buttons.size(), "left": secs, "answer": -1,
		"rects": rects if rects.size() else L.hits}
	_msg.queue_redraw()


func _talkmsg_tick(delta: float) -> void:
	if _tm.is_empty():
		return
	if int(_tm.nbtn) > 0 and int(_tm.answer) < 0:
		var mp := _msg.get_local_mouse_position()
		for k in (_tm.rects as Array).size():
			if (_tm.rects[k] as Rect2).has_point(mp) and int(_tm.sel) != k:
				_tm.sel = k
				Game.play_sound(0x201)
		_msg.queue_redraw()
		return
	_tm.left = float(_tm.left) - delta
	if float(_tm.left) <= 0.0:
		_tm = {}
		_msg.queue_redraw()


func _talkmsg_input(e: InputEvent) -> bool:
	if _tm.is_empty() or int(_tm.nbtn) == 0 or int(_tm.answer) >= 0:
		return false
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		for k in (_tm.rects as Array).size():
			if (_tm.rects[k] as Rect2).has_point(_msg.get_local_mouse_position()):
				_tm.answer = k
		return true
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_RIGHT:
		_talkmsg_cancel()
		return true
	if e is InputEventKey and e.pressed and not e.echo:
		match e.keycode:
			KEY_ESCAPE, KEY_CTRL:
				_talkmsg_cancel()
			KEY_LEFT, KEY_UP:
				_tm.sel = maxi(int(_tm.sel) - 1, 0)
				Game.play_sound(0x201)
			KEY_RIGHT, KEY_DOWN:
				_tm.sel = mini(int(_tm.sel) + 1, int(_tm.nbtn) - 1)
				Game.play_sound(0x201)
			KEY_ENTER, KEY_SPACE, KEY_KP_ENTER:
				_tm.answer = int(_tm.sel)
		_msg.queue_redraw()
		return true
	return false


## 取消键 (逆向确认): 选项按钮输入 0x465656 每帧在战斗输入之前运行, 先播 0x202;
##   全局标志 [0x9f2e90] (Game.cancel_lock) 为 0 时选中项强制成 0 并留下「已取消」标记 [0xa84cf4]:
##   - FIGTALK 选项 (menu_switch 0x45c761 只看「已确认」和选中项) → 当场取第 0 项
##   - 退驾提示 (战斗状态 0xb): 战斗自己的取消处理 0x44e3b0 再播 0x1ff, 不关提示; 分派 0x44e00a 只在回车 / 左键时读选中项,
##     所以只是光标被拨回「是」, 下次回车才执行
##   标志不为 0 时只有音效
func _talkmsg_cancel() -> void:
	Game.play_sound(0x202)
	if bool(_tm.get("dismiss", false)):
		Game.play_sound(0x1ff)
	if Game.cancel_lock != 0:
		return
	Game.cancel_residual = true
	_tm.sel = 0
	if not bool(_tm.get("dismiss", false)):
		_tm.answer = 0


func _talkmsg_wait() -> int:
	while not _tm.is_empty() and int(_tm.answer) < 0:
		if auto_pick() and int(_tm.nbtn) > 0:
			_tm.answer = 0
			break
		await get_tree().process_frame
	return int(_tm.answer) if not _tm.is_empty() else -1


## 退驾确认 (0x44de95: (400, 280), 时长 100000 = 1000 秒); 战斗另有写死的鼠标判定 0x44d5cb: 第 k 项 x∈[405+60k, 460+60k), y∈[270, 295)
func _ask_choice(text: String) -> int:
	_talkmsg(text, Vector2(400, 280), 1000.0, [Rect2(405, 270, 55, 25), Rect2(465, 270, 55, 25)])
	_tm.dismiss = true
	var r := await _talkmsg_wait()
	_tm = {}   # 回答后由调用方清框 (0x4653e4)
	_msg.queue_redraw()
	return r


## 退驾 (动作状态 0x20, 逐帧 0x441e7d, 逆向确认):
##   桓远之播动作 0x32; 命中帧 (d 记号) → 护驾立即完全显示; 再过 30 帧: 在护驾位置留下残影 (0x436b68) 并立即移除护驾;
##   残影存在 50 帧 → 再等 16 帧 → 桓远之结束行动 (动作 14, 朝向 180)
func _dismiss(u: BattleUnit, g: BattleUnit) -> void:
	_end_turn_cam()
	if u.actor.has_pose(0x32):
		u.actor.play(0x32)
		var hit := u.actor.pose_len - 1
		for mk in u.actor.meta.poses[str(0x32)].get("marks", []):
			if str(mk[1]) == "d":
				hit = int(mk[0])
				break
		while u.actor.pose == 0x32 and u.actor.pose_tick < hit:
			await get_tree().process_frame
	fade_unit(g, false, 0xff)
	await get_tree().create_timer(30 * TICK).timeout
	_dismiss_ghost(g)
	_guard_leave(g)
	await get_tree().create_timer((50 + 16) * TICK).timeout
	end_action(u)


## 退驾残影 (0x436b68 → 0x48e5cc(记录, 1)): 用该怪自己的模型播动作 14, 从护驾位置匀速移到 z − 200 (50 帧, 第 t 帧 = 起点 + 差 × t/50),
## 每帧不透明度 = 255 − 计数 × 255 / 50 (整数除法, 计数先 +1), 加色混合 (渲染模式 1), 50 帧后删除;
## 矩阵角度参数 180 (P: 偏航 180°)
func _dismiss_ghost(g: BattleUnit) -> void:
	var from := g.pos()
	var to := from - Vector3(0, 0, 200)
	var a := _make_actor(g.actor.act, from, 180.0)
	if a.has_pose(14):
		a.play(14, true)
	var mats: Array = []   # 材质是模型缓存共用的, 复制一份再改
	for mi in a.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for si in m.get_surface_override_material_count():
			var sm := m.get_surface_override_material(si) as StandardMaterial3D
			if sm:
				sm = sm.duplicate() as StandardMaterial3D
				sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				sm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
				sm.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
				m.set_surface_override_material(si, sm)
				mats.append(sm)
	var acc := 0.0
	var cnt := 0
	while cnt < 50 and is_instance_valid(a):
		var alpha := float(255 - (cnt + 1) * 255 / 50) / 255.0
		a.set_game_pos(from + (to - from) * float(cnt) / 50.0, false)
		for sm in mats:
			(sm as StandardMaterial3D).albedo_color.a = alpha
		await get_tree().process_frame
		acc += get_process_delta_time()
		while acc >= TICK and cnt < 50:
			acc -= TICK
			cnt += 1
	if is_instance_valid(a):
		a.queue_free()


func _guard_leave(g: BattleUnit) -> void:
	_guard_out.erase(g.guard_k)
	# 退驾不回写 HP (verify_capture §2.4): 下次召出仍是记录里的数值 (以前存了这次的剩余生命, 和原版相反)
	g.actor.queue_free()   # 0x433ff0 重置该槽: 立即消失, 没有淡出 (残影另画)
	units[units.find(g)] = null


## 护驾阵亡 (0x442738 → 0x4b132f): 从鬼神阵位置 0 和居民链表里永久删除, 后备前移补上
func _guard_down(g: BattleUnit) -> void:
	_guard_out.erase(g.guard_k)
	var hs := State.ts_houses.filter(func(h): return int(h.type) == 9)
	if g.guard_k < hs.size():
		var sl: Array = hs[g.guard_k].get("slots", [])
		if sl.size() and int(sl[0]) == g.id:
			sl.remove_at(0)
			hs[g.guard_k].slots = sl
	for r in State.ts_residents:
		if int(r.id) == g.id:
			State.ts_residents.erase(r)
			break
	State.guard_hp.erase(str(g.id))
	# 护驾死亡 (状态 0x35 子状态 0 就返回, 调用方马上 0x43203e → 0x434947(1, 0x19)): 从当前不透明度每帧 −25 淡出;
	# 原版没有「阵亡」提示 (以前那条是自己加的)
	fade_unit(g, true, 0x19)
	get_tree().create_timer(ceilf(255.0 / 0x19) * TICK).timeout.connect(func():
		if is_instance_valid(g.actor):
			g.actor.visible = false)


## 战斗结束 (0x4405c1): 活着的护驾回满, 下次可再召
func _guards_end() -> void:
	for k in _guard_out:
		State.guard_hp.erase(str((_guard_out[k] as BattleUnit).id))
	_guard_out.clear()


var _force_hit := false


## 替身 (状态 0x400, 0x432d7e): 本体旁边画一个自己的复制体, 待机动作 14;
## 我方在 (x+75, z+100) 朝向 180, 敌方在 (x−75, z−100) 朝向 0;
## 绘制标志 4 (0x432e6f → 0x4168c4): 只是给每个面的混合模式或上第 2 位 —— 原来不透明的面变成模式 4
## (不写深度, 结果 = 背景 × (1 − 贴图色), 看起来是反色压暗的影子); 原来是加法 / 普通的面变成 5 / 6, 原版不处理 (沿用上一状态, 定不下来)
static var _decoy_shader: Shader
func _update_decoys() -> void:
	for u in units:
		if u == null:
			continue
		var want: bool = u.actor != null and not u.dead and not u.absent and u.has(Formula.ST_DECOY)
		if want and u.decoy == null:
			var off := Vector3(75, 0, 100) if u.party else Vector3(-75, 0, -100)
			u.decoy = _make_actor(u.actor.id, u.actor.gpos + off, 180.0 if u.party else 0.0)
			if u.decoy.has_pose(IDLE_POSE):
				u.decoy.play(IDLE_POSE, true)
			if _decoy_shader == null:
				_decoy_shader = Shader.new()
				_decoy_shader.code = """shader_type spatial;
render_mode unshaded, blend_mul, depth_draw_never, cull_disabled;
uniform sampler2D tex : source_color, filter_linear;
void fragment() {
	vec4 c = texture(tex, UV);
	if (c.a < 0.5) { discard; }
	ALBEDO = vec3(1.0) - c.rgb;
}
"""
			for n in u.decoy.find_children("*", "MeshInstance3D", true, false):
				var mi := n as MeshInstance3D
				for si in mi.mesh.get_surface_count():
					var src := mi.get_active_material(si)
					if src is StandardMaterial3D and (src as StandardMaterial3D).blend_mode == BaseMaterial3D.BLEND_MODE_MIX \
							and (src as StandardMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_ALPHA:
						var sm := ShaderMaterial.new()
						sm.shader = _decoy_shader
						sm.set_shader_parameter("tex", (src as StandardMaterial3D).albedo_texture)
						mi.set_surface_override_material(si, sm)
		elif not want and u.decoy != null:
			u.decoy.queue_free()
			u.decoy = null


# ---------------- 木甲术 (re/verify_mech_skills.md) ----------------

func _mech_skill(att: BattleUnit, t: BattleUnit, sid: int) -> void:
	if sid == 6024:
		_mech_scout(t)
	else:
		_mech_break(t, sid)


## 机关侦查术 (0x438d0c): 按对这个目标的第几次侦查掷骰, 挖走存量的全部 / 7成 / 4成 / 1成, 不超过车芸这一级还能拿的木甲技术点
func _mech_scout(t: BattleUnit) -> void:
	if t.party:
		_message("侦察对象无效!!")
		return
	var lv := int(State.member(1).lv)
	var cap := -int(State.tech_total)
	for row in db.get("techpts", []):
		if int(row[0]) == lv:
			cap += int(row[2])
	if t.tech_pool <= 0 or cap <= 0:
		Game.play_sound(0x2a8)
		_message("已无侦察的必要!!")
		return
	t.scan_count += 1
	var th: Array = [10, 20, 80, 100] if t.scan_count == 1 else ([10, 70, 90, 100] if t.scan_count == 2 else [70, 80, 140, 140])
	var r := randi() % 800 % 100
	var amt := 0
	if r <= th[0]:
		amt = t.tech_pool
	elif r <= th[1]:
		amt = t.tech_pool * 7 / 10
	elif r <= th[2]:
		amt = t.tech_pool * 4 / 10
	elif r <= th[3]:
		amt = t.tech_pool / 10
	amt = mini(amt, cap)
	if skill_testing:
		print("MECHSCOUT n=%d r=%d pool=%d cap=%d amt=%d" % [t.scan_count, r, t.tech_pool, cap, amt])
	if amt <= 0:
		hud.symbol_pop(t, 5)   # 0x438e2e: 头顶符号 ACT 9007 qq5 (失败)
		Game.play_sound(0x2a8)
		return
	State.tech += amt
	State.tech_total += amt
	t.tech_pool -= amt
	_message("获得「木甲技术」%d点!!" % amt)
	hud.symbol_pop(t, 4)   # 0x438e9a: 头顶符号 qq4 (成功)
	Game.play_sound(0x2a6)


## 拆解 / 卸甲 / 瘫痪 (0x438efe): 木甲术等级 1..3 (木甲板解锁); rand(900)%100 定失败 / 减益 / 彻底破坏
func _mech_break(t: BattleUnit, sid: int) -> void:
	var tier := clampi(int(State.mech_lv.get(sid, 1)), 1, 3)
	var r := randi() % 900 % 100
	var is118 := int(t.rec.get("sub", 0)) == 118
	var silent := false
	if skill_testing:
		print("MECHBREAK tier=%d r=%d is118=%s" % [tier, r, is118])
	if r <= [15, 10, 5][tier - 1]:
		Game.play_sound(0x2a8)
		hud.pop(t, "miss")   # 结果 0 = 失败
		return
	if r >= [90, 85, 80][tier - 1]:
		_message("%s彻底破坏" % t.name)
		Game.play_sound(0x2ab)
		var dmg := t.hp_max if is118 else t.hp_max / 5   # 按最大 HP, 不经过任何修正
		t.hp = clampi(t.hp - dmg, 0, t.hp_max)
		hud.pop(t, "hp", dmg)
		hurt(t)
		_check_down(t)
		if is118:
			return
		silent = true   # 首领: 扣 1/5 之后照样挂减益, 只是不提示「××成功」
	var pct: int = [[45, 15], [75, 25], [100, 30]][tier - 1][0 if is118 else 1]
	var stats: Array = {6025: ["atk", "matk"], 6026: ["def", "mdef"], 6027: ["spd"]}[sid]
	for k in stats:
		t.add_buff(str(k), -t.base_stat(str(k)) * pct / 100, 5)   # 不叠加: 同属性旧的增减益被覆盖
	if not silent:
		_message("%s%s" % [t.name, {6025: "拆解成功", 6026: "卸甲成功", 6027: "瘫痪成功"}[sid]])
	Game.play_sound(0x2a6)
var skill_test: Array = []   # 调试 --skill-test: 依次施放的技能 [技能号, 角色号]
var skill_testing := false
var viewer: SkillViewer   # 技能观看器 (make preview / --skill-viewer)
var viewer_actor: BattleUnit
var afterimages := {}   # 单位 → AtkRunner.Afterimage (残影设在单位上)
var trails := {}   # 单位 → AtkRunner.WeaponTrail (武器拖尾设在单位上, 招式结束后照常淡完)


## ATK 0x86 变身 (四首变化、雪猛 变身…, exe 0x43b05e 逆向确认): 换成新的 ObjDATA 记录和模型;
## 当前 HP / MP / SP (记录 +0x30 / +0x34 / +0x38) 先存后原样写回 (不按新上限截断), 状态 (+0x1964)、行动条不动, 播待机 14
func transform_unit(u: BattleUnit, id: int) -> BattleUnit:
	var i := units.find(u)
	if i < 6 or obj(id).is_empty():
		return null
	var p := u.pos()
	var f := u.actor.facing if u.actor else 0.0
	var nu := _enemy_unit(id, i, p, f)
	nu.variant = u.variant
	if nu.actor:
		nu.actor.set_variant(u.variant)
	nu.hp = u.hp
	nu.mp = u.mp
	nu.sp = u.sp
	nu.status = u.status
	nu.status_turns = u.status_turns
	nu.status_prog = u.status_prog
	nu.gauge = u.gauge
	nu.home = u.home
	if u.actor:
		u.actor.queue_free()
	units[i] = nu
	if active == u:
		active = nu
	return nu


## 单位淡化 0x434947(开/关, 速度) (招式 0x37 / FIGTALK 0x7e2 共用): 开 = 透明度每帧减「速度」到 0 后隐藏; 关 = 从全透明每帧加「速度」到 255; 255 = 瞬间
func fade_unit(u: BattleUnit, on: bool, speed: int) -> void:
	# 0x434947(on, speed): on = 0 淡入 (先把不透明度清 0, 每帧 +speed); on = 1 淡出 (从当前不透明度每帧 −speed); speed 255 = 立即
	if u == null or not is_instance_valid(u.actor):
		return
	for g in u.actor.find_children("*", "GeometryInstance3D", true, false):
		var gi := g as GeometryInstance3D
		var tw_old: Variant = gi.get_meta("fade_tw") if gi.has_meta("fade_tw") else null   # get_meta 默认值给 null 仍会报错
		if tw_old is Tween and (tw_old as Tween).is_valid():
			(tw_old as Tween).kill()
		var from := gi.transparency if on else 1.0
		var to := 1.0 if on else 0.0
		var frames := 0.0 if speed >= 255 or speed <= 0 else ceilf(absf(to - from) * 255.0 / speed)
		if frames <= 0.0:
			gi.transparency = to
			continue
		gi.transparency = from
		var tw := create_tween()
		tw.tween_property(gi, "transparency", to, frames * TICK)
		gi.set_meta("fade_tw", tw)


## 游泳挑战 (战斗状态 0x1e; 更新 0x453566, 输入 0x450cf0; 战场 299 湿砍):
##   子状态 0: 倒数鸭 ACT 9331 画在 (380,480), 播完 → 清提示、音效 629、音乐 199、限时 = 现在 + 参数0×10 毫秒 (真实时间)
##   子状态 1: 法宝指示图 ACT 9324 画在 (390,500); 每帧: 剩余 = (限时 − 现在)/10 (百分之一秒), ≤ 300 时镜头注视点 = 单位 6 + (−100,100,100);
##     还有「推进帧」→ 推进帧 −1、单位 6 x −= 参数1, x ≤ −1172 → 成功; 没有推进帧且 x < 1017 → x += 参数1 (往回漂)
##     确认键 (左键 / Enter / 空格) 每按一下推进帧 +5, 上限 15; 剩余 ≤ 0 → 子状态 2 (失败)
##   每帧都画剩余的 4 位数 (ACT 9314 = 数字, 千 / 百位在 (460,100) / (510,100) 放大 1.5, 十 / 个位在 (570,110) / (610,110) 放大 1.2)
var mg_state := 0
var swim_ok := false
var swim := {}   # 给 HUD 画: sub, value, t (子状态内的帧数)


## 拼图小游戏 (战斗状态 0x1f; 逐帧 0x453a5e, 输入 0x45066b, 逆向确认; 战场 299 = FIGTALK 298):
##   棋盘 4 列 × 3 行, 格 i → 列 i/3、行 i%3; 判定框 x∈[132+136列, 268+136列), y∈[126+136行, 262+136行)
##   子状态 0: 格 i 放图块 i、不旋转, 光标 / 手上都空, 清旗标 3336 / 3337 → 1;  1: 只画 (00:00), 等脚本开始
##   2 (开始 / F1 重置): 清消息, 音效 0x275, 记开始时间 (真实时间), 音乐 199; 洗牌 for i: r = rand(100+i) % 12 交换格 i / r;
##     再给每格的图块随机朝向 rand(40) & 3; 光标 0 → 3
##   3: 计时 (秒, 没有时限); 左键 / 确认后判定胜利 = 每格 i 都是图块 i 且朝向 0 → 光标 −1, 音效 0x210, 「挑战成功！！」(400,250) → 4
##   4: ≤ 20 秒置旗标 3336, 否则 3337 → 5..0x3f 显示最终时间 59 帧 → 0x40 战斗结算结束 (F2 放弃直接到 0x40, 不置旗标)
## 原版的缺陷: 拿着图块按 F1 时洗牌会把「空」也洗进去并越界写旋转值; 这里跳过空格的旋转值 (不越界), 手上的图块保留
var puzzle := {}


func _puzzle_start() -> void:
	mg_state = 0x1f
	puzzle = {"sub": 0, "board": [], "rot": [], "cursor": -1, "held": -1, "grab": Vector2.ZERO, "t0": 0, "secs": 0, "n": 0}
	_puzzle_run()


func _puzzle_run() -> void:
	var acc := 0.0
	while not puzzle.is_empty() and result == "":
		await get_tree().process_frame
		acc += get_process_delta_time()
		while acc >= TICK and not puzzle.is_empty():
			acc -= TICK
			_puzzle_tick()


func _puzzle_tick() -> void:
	var z := puzzle
	match int(z.sub):
		0:
			z.board = range(12)
			z.rot = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
			z.cursor = -1
			z.held = -1
			State.set_flag(3336, false)
			State.set_flag(3337, false)
			z.secs = 0
			z.sub = 1
		2:
			dialog.close_all()
			_tm = {}
			Game.play_sound(0x275)
			z.t0 = Time.get_ticks_msec()
			_play_music(199)
			var b: Array = z.board
			for i in 12:
				var r := randi() % (100 + i) % 12
				var tmp: int = b[i]
				b[i] = b[r]
				b[r] = tmp
			for i in 12:
				if int(b[i]) >= 0:
					z.rot[int(b[i])] = randi() % 40 & 3
			z.cursor = 0
			z.sub = 3
		3:
			z.secs = (Time.get_ticks_msec() - int(z.t0)) / 1000
		4:
			z.secs = (Time.get_ticks_msec() - int(z.t0)) / 1000
			State.set_flag(3336 if int(z.secs) <= 20 else 3337)
			z.sub = 5
		0x40:
			puzzle = {}
			_finish("win")   # 0x4405c1
		_:
			if int(z.sub) >= 5 and int(z.sub) < 0x40:
				z.sub = int(z.sub) + 1


## 格子判定 (0x45066b)
static func puzzle_cell_at(p: Vector2) -> int:
	for i in 12:
		var c := i / 3
		var r := i % 3
		if p.x >= 132 + 136 * c and p.x < 268 + 136 * c and p.y >= 126 + 136 * r and p.y < 262 + 136 * r:
			return i
	return -1


static func puzzle_cell_pos(i: int) -> Vector2:
	return Vector2(194 + 136 * (i / 3), 193 + 136 * (i % 3))


func _puzzle_input(e: InputEvent) -> bool:
	var z := puzzle
	if z.is_empty() or int(z.sub) != 3:
		return false
	var mp := _msg.get_local_mouse_position()
	if e is InputEventKey and e.pressed and not e.echo:
		var c := int(z.cursor)
		var moved := true
		match e.keycode:
			KEY_F1:
				z.sub = 2
				return true
			KEY_F2:
				z.sub = 0x40
				return true
			KEY_RIGHT:
				c = 0 if c == 11 else (1 if c + 3 == 12 else (2 if c + 3 == 13 else c + 3))
			KEY_LEFT:
				c = 11 if c == 0 else (9 if c == 1 else (10 if c == 2 else c - 3))
			KEY_UP:
				c = 11 if c - 1 < 0 else c - 1
			KEY_DOWN:
				c = 0 if c + 1 >= 12 else c + 1
			KEY_SHIFT, Pad.X, Pad.LB, Pad.RB:
				_puzzle_rotate()
				return true
			KEY_ENTER, KEY_KP_ENTER, Pad.CONFIRM_ONLY:
				if c >= 0:
					Game.play_sound(0x200)
					_puzzle_take(c, Vector2(10, 10), true)
				return true
			_:
				moved = false
		if moved:
			z.cursor = c
			Game.play_sound(0x201)
			_puzzle_warp(puzzle_cell_pos(c) + Vector2(20, 20))
		return true
	if e is InputEventMouseMotion:
		var h := puzzle_cell_at(mp)
		if h >= 0 and h != int(z.cursor):
			z.cursor = h
			Game.play_sound(0x201)
		return false
	if e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_RIGHT:
			_puzzle_rotate()
			return true
		if e.button_index == MOUSE_BUTTON_LEFT:
			var i := puzzle_cell_at(mp)
			if i < 0:
				Game.play_sound(0x20e)
			else:
				Game.play_sound(0x200)
				_puzzle_take(i, mp - puzzle_cell_pos(i), false)
			return true
	return false


## 旋转 (右键 / Shift): 手上有图块 → 朝向 +1 (mod 4), 音效 0x202; 没有 → 0x20e
func _puzzle_rotate() -> void:
	var z := puzzle
	if int(z.held) >= 0:
		z.rot[int(z.held)] = (int(z.rot[int(z.held)]) + 1) % 4
		Game.play_sound(0x202)
	else:
		Game.play_sound(0x20e)


## 拿起 / 放下 / 交换 (左键 0x100: 抓取偏移 = 鼠标 − 格子位置; Enter: 偏移 (10,10) 并把鼠标移到该格, 放进空格时不移)
func _puzzle_take(i: int, grab: Vector2, warp: bool) -> void:
	var z := puzzle
	var b: Array = z.board
	var held := int(z.held)
	var cell := int(b[i])
	if held >= 0 and cell >= 0:
		b[i] = held
		z.held = cell
		z.grab = grab
	elif held >= 0:
		b[i] = held
		z.held = -1
		warp = false
	elif cell >= 0:
		z.held = cell
		b[i] = -1
		z.grab = grab
	if warp:
		_puzzle_warp(puzzle_cell_pos(i) + Vector2(20, 20))
	var ok := true
	for k in 12:
		if int(b[k]) != k or int(z.rot[k]) != 0:
			ok = false
	if ok:
		z.cursor = -1
		Game.play_sound(0x210)
		_talkmsg("挑战成功！！", Vector2(400, 250), 2.0)
		z.sub = 4


## 0x40e160 SetCursorPos: 把系统鼠标移到界面坐标 p
func _puzzle_warp(p: Vector2) -> void:
	var vp := get_viewport()
	var s := Vector2(vp.get_visible_rect().size) / Vector2(800, 600)
	vp.warp_mouse(p * s)


func _swim(limit: int, step: int) -> void:
	mg_state = 0x1e
	swim_ok = false
	swim = {"sub": 0, "value": limit, "t": 0}
	var u := _unit(6)
	var deadline := 0
	var pend := 0
	var acc := 0.0
	var count_len := 0
	for f in hud.ui_act(9331, 0):
		count_len += int(f[1])
	while result == "":
		await get_tree().process_frame
		if hud.mg_pressed(0.3) and int(swim.sub) == 1:
			pend = mini(pend + 5, 15)
		acc += get_process_delta_time()
		while acc >= TICK:
			acc -= TICK
			swim.t = int(swim.t) + 1
			match int(swim.sub):
				0:
					if int(swim.t) >= count_len:
						dialog.close_all()
						Game.play_sound(629)
						if field and field.has_method("play_music_track"):
							field.play_music_track(199, 0)
						deadline = Time.get_ticks_msec() + limit * 10
						swim.sub = 1
						swim.t = 0
				1:
					if int(swim.value) > 0:
						swim.value = int((deadline - Time.get_ticks_msec()) / 10)
						if int(swim.value) <= 300 and u:
							cam.f = u.pos() + Vector3(-100, 100, 100)
							cam.ft = cam.f
					else:
						swim.sub = 2
						swim.value = 0
					if u and u.actor:
						var p := u.actor.gpos
						if pend > 0:
							pend -= 1
							p.x -= step
							if p.x <= -1172.0:
								swim_ok = true
								swim.sub = 2
						elif p.x < 1017.0:
							p.x += step
						u.actor.set_game_pos(p, false)
						u.home = p
			if int(swim.sub) == 2 or int(swim.value) < 0:
				mg_state = 0
				swim = {}
				return


## 单位转向 (0x431a65(x, 角度, z, 立即)): 写目标朝向 +0x1988; 立即 = 1 时当前朝向 +0x1990 直接等于目标, 否则单位绘制 (0x43280f)
## 每帧逼近: d = |int(当前 − 目标)|; d ≤ 10 或 d ≥ 350 → 到位; d ≤ 180 → 当前 += (目标 − 当前) × 0.25;
## d > 180 → 步长 = (360 − d) × 0.25, 当前 > 目标时 当前 += 步长, 否则 当前 = 360 − 步长 (原版就是这么写的)
var _turns := {}   # 单位 → 目标朝向
var _turn_acc := 0.0


func turn_unit(u: BattleUnit, angle: float, immediate := false) -> void:
	if u.actor == null:
		return
	if immediate:
		u.actor.set_facing(angle)
		_turns.erase(u)
	else:
		_turns[u] = angle


func _turn_tick() -> void:
	for u in _turns.keys():
		var tgt: float = _turns[u]
		if u.actor == null or not is_instance_valid(u.actor):
			_turns.erase(u)
			continue
		var cur: float = u.actor.facing
		var d := absi(int(cur - tgt))
		if cur == tgt or d <= 10 or d >= 350:
			cur = tgt
		elif d <= 180:
			cur += (tgt - cur) * 0.25
		else:
			var stp := (360.0 - d) * 0.25
			cur = cur + stp if cur > tgt else 360.0 - stp
		u.actor.facing = cur   # 不经 set_facing 的 fposmod: 原版 +0x1990 不取模
		u.actor.rotation.y = deg_to_rad(-cur)
		if cur == tgt:
			_turns.erase(u)


## 全屏覆盖闪光 (ATK 0x98 → 0x925a28 播放器, 每帧 0x442619 用 0x46a983 画成 (2.1+1)×(1.35+1) 倍的 2D 精灵 = 800×600):
## ACT 7042「全萤幕速度线」QQ 0 一次 10 帧 / QQ 1 循环, 加法混合, 颜色按 OC 轨道; sub < 0 = 清除 (0xffff)
var _ov: TextureRect
var _ov_data: Dictionary
var _ov_frames: Array = []
var _ov_t := 0.0


func overlay_fx(sub: int) -> void:
	if _ov:
		_ov.queue_free()
		_ov = null
	if sub < 0:
		return
	var key := "7042_%d" % sub
	if not Fx.has(key):
		return
	_ov_data = Fx._db[key]
	var fr := str(int(_ov_data.tracks.fr[0][1]))
	_ov_frames = _ov_data.sprites.get(fr, {}).get("frames", [])
	_ov = TextureRect.new()
	_ov.size = Vector2(800, 600)
	_ov.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_ov.stretch_mode = TextureRect.STRETCH_SCALE
	_ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cm := CanvasItemMaterial.new()
	cm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_ov.material = cm
	_ov_t = 0.0
	_ui.add_child(_ov)
	_ov_tick()


func _ov_tick() -> void:
	if _ov == null:
		return
	var total := int(_ov_data.ticks)
	var tick := int(_ov_t / Fx.TICK)
	if tick >= total:
		if not bool(_ov_data.get("loop", false)):
			_ov.queue_free()
			_ov = null
			return
		tick = tick % total
	var frame := 0
	var col: Array = [255, 255, 255, 255]
	for e in _ov_data.tracks.frame:
		if int(e[0]) <= tick:
			frame = int(e[1])
	for e in _ov_data.tracks.color:
		if int(e[0]) <= tick:
			col = e[1]
	if _ov_frames.size():
		_ov.texture = Fx.texture(Fx._dir.path_join(_ov_frames[clampi(frame, 0, _ov_frames.size() - 1)]))
	_ov.modulate = Color(col[1] / 255.0, col[2] / 255.0, col[3] / 255.0, col[0] / 255.0)


## 战斗画面压暗 (0x44232b): 旗标 8051 清除时每帧叠一层 alpha 8/255 的黑 (招式脚本开头置位、中途清除)
var _dim: ColorRect
var _ov_acc := 0.0


## 目标虚影 (ATK 0x4a → 0x436911, 破胆 / 裂心 / 震慑 / 威吓 / 雷霆威吓): 目标当前姿势的 3 份分身, 从目标位置升到挂点 2 上方 200 处,
## 各 20 / 25 / 30 帧 (效果对象 +0x1cc), 位置线性插值 (+0x150 & 4) 并淡出 (& 8)
func target_ghosts(t: BattleUnit) -> void:
	var a := t.actor
	if a == null:
		return
	var top: Variant = marker_pos(t, 2)
	var end: Vector3 = (top if top != null else t.pos()) + Vector3(0, 200, 0)
	var from := t.pos()
	for dur in [20, 25, 30]:
		var r: Array = AtkRunner.bake_ghost(a, world_node(), Color.WHITE)
		var ghost: Node3D = r[0]
		var mats: Array = r[1]
		var secs := float(dur) * Fx.TICK
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(ghost, "position", ghost.position + to_world(end) - to_world(from), secs)
		for gm in mats:
			tw.tween_property(gm, "albedo_color:a", 0.0, secs)
		tw.chain().tween_callback(ghost.queue_free)


## 首领光环 (0x43f1ac → 单位 +0xbf0 的 ACT 8139 播放器, 每帧 0x43f2d3 在 (x, 83, z) 画; 0x4402ae 开场全亮):
## 单位编号 → QQ: 2014 囚牛 0, 2015 嘲风 1, 2018 / 2418 霸下 2, 2019 螭吻 3, 2022 睚眦 6, 2023 蒲牢 7
const AURA_QQ := {2014: 0, 2015: 1, 2018: 2, 2019: 3, 2022: 6, 2023: 7, 2418: 2}
var _auras := {}   # 单位 → {fx, alpha, step, dir, fading}


func aura_setup(u: BattleUnit) -> void:
	if not AURA_QQ.has(u.id) or u.actor == null:
		return
	var key := "8139_%d" % int(AURA_QQ[u.id])
	if not Fx.has(key):
		return
	var fx: Variant = Fx.spawn(world_node(), key, to_world(_aura_pos(u)), Basis(), cam3d(), Callable())
	if fx == null:
		return
	fx.loop_forever = true
	_auras[u] = {"fx": fx, "alpha": 255.0, "step": 0.0, "dir": 1, "fading": false}
	if OS.get_cmdline_user_args().has("--trace-fx"):
		print("AURA unit=%s key=%s" % [u.name, key])


## 光环位置 (0x43f2d3 → 0x46ade2 的参数): x = +0x1854, z = +0x185c, y = 常量 [0x4cdce8] = 83.0 (绝对高度, 不是单位高度 + 83);
## 以前加在单位高度上, 战场单位本来就站在 y≈83, 魔法阵被抬到半腰 (用户反馈「蒲牢的魔法阵在半腰」)
func _aura_pos(u: BattleUnit) -> Vector3:
	var p := u.pos()
	return Vector3(p.x, 83.0, p.z)


## 0x43f1ac(dir, step, from): dir 1 淡入到 255 / 0 淡出到 0, 每帧变 step; step 255 = 立刻
func aura_fade(u: BattleUnit, dir_in: bool, step: int) -> void:
	if not _auras.has(u):
		return
	var st: Dictionary = _auras[u]
	st.dir = 1 if dir_in else 0
	st.step = float(step)
	st.fading = step != 255
	if step == 255:
		st.alpha = 255.0 if dir_in else 0.0


func _aura_tick() -> void:
	for u in _auras.keys():
		var st: Dictionary = _auras[u]
		var fx: Variant = st.fx
		if not is_instance_valid(fx):
			_auras.erase(u)
			continue
		if u.actor == null or not is_instance_valid(u.actor):   # 单位被换掉 (变身 / 召唤顶替)
			fx.queue_free()
			_auras.erase(u)
			continue
		if st.fading:
			st.alpha = clampf(st.alpha + (st.step if st.dir == 1 else -st.step), 0.0, 255.0)
			if st.alpha <= 0.0 or st.alpha >= 255.0:
				st.fading = false
		fx.global_position = to_world(_aura_pos(u))
		fx.particle_mod = Color(1, 1, 1, st.alpha / 255.0)
		fx.visible = st.alpha > 0.0 and not u.dead


## ATK 0x88 (0x44c060): 结束施术者行动 —— 0x43203e 复位 (待机 14、朝向复位、行动条清零)
func end_action(u: BattleUnit) -> void:
	if u.actor:
		if u.actor.has_pose(IDLE_POSE):
			u.actor.play(IDLE_POSE)
		u.actor.set_facing(180.0 if u.party else 0.0)
	u.gauge = 0


## 呼风唤雨 (ATK 0x3ee → 0x445c4b): 0x124 字节的粒子系统 (类 0x4ce064, 每粒子 0x1bc), 按 0x491d93 / 0x491ff2 / 0x492185:
##   出生 x = (r−0.5)×3000, y = 1000, z = (r−0.2)×3000 (战场坐标); 竖直初速 −(r+1)×3.005×(r×50+200) /秒, 水平 0;
##   加速度 a = r×2×9.8 (每秒再加 (6×9.8−a)/寿命), 每秒 vy −= a×9.8; y < 50 死亡; 每秒补 400 个 (count), 最多 400 个;
##   画法: 本帧位置 (alpha 0x32) → 上一帧位置 (alpha 0x96) 的白色线段 (0x4149a3); 0x3ef 删除 (无技能用), 战斗结束清 (0x4405d8)
func rain_start(count: int, _p1: int) -> void:
	rain_stop()
	_rain = RainLines.new()
	_rain.bt = self
	_rain.count = count
	world_node().add_child(_rain)
	if not State.test_flag(21):   # 0x4676f5(0x15) 为 0 时循环播 491 (0x4befee)
		Game.play_sound_loop(491)


func rain_stop() -> void:
	if is_instance_valid(_rain):
		_rain.queue_free()
	_rain = null
	Game.stop_sound_loop(491)


var _rain: RainLines


class RainLines extends MeshInstance3D:
	var bt: Node
	var count := 400
	var _parts: Array = []   # [pos, prev, vy, a, da, alive]
	var _acc := 0.0
	var _im := ImmediateMesh.new()

	func _ready() -> void:
		mesh = _im
		top_level = true
		global_transform = Transform3D.IDENTITY
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.vertex_color_use_as_albedo = true
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		material_override = mat
		cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	func _spawn() -> void:
		var pos := Vector3((randf() - 0.5) * 3000.0, 1000.0, (randf() - 0.2) * 3000.0)
		var vy := -(randf() + 1.0) * 3.005 * (randf() * 50.0 + 200.0)
		var a := randf() * 2.0 * 9.8
		var life := randf() * 0.3 + 0.2
		_parts.append([pos, pos, vy, a, (6.0 * 9.8 - a) / life])

	func _process(delta: float) -> void:
		var dt := minf(delta, 0.1)
		_acc += dt * float(count)
		while _acc >= 1.0 and _parts.size() < count:
			_acc -= 1.0
			_spawn()
		_acc = minf(_acc, 1.0)
		var keep: Array = []
		for q in _parts:
			q[1] = q[0]
			q[0] = q[0] + Vector3(0, q[2] * dt, 0)
			q[2] -= q[3] * dt * 9.8
			q[3] += q[4] * dt
			if q[0].y >= 50.0:
				keep.append(q)
		_parts = keep
		_im.clear_surfaces()
		if _parts.is_empty():
			return
		_im.surface_begin(Mesh.PRIMITIVE_LINES)
		for q in _parts:
			_im.surface_set_color(Color(1, 1, 1, 0x32 / 255.0))
			_im.surface_add_vertex(bt.to_world(q[0]))
			_im.surface_set_color(Color(1, 1, 1, 0x96 / 255.0))
			_im.surface_add_vertex(bt.to_world(q[1]))
		_im.surface_end()


## ATK 0x90 偷钱 (exe 0x448638 → 0x43b173, 逆向确认): 每个目标 rand(1100) % 100 ≤ 80 (81%) 成功, 否则失误;
##   目标是我方: 队伍金钱 −数额 (不低于 0); 目标是敌人 (我方偷): 拿走它身上钱的一半 (取整), 上限 9999999
##   (目标身上有皓月宝镜反弹 +0x1960 & 0x100000 时改为对施术者生效, 提示「被【皓月宝镜】反弹」—— 皓月宝镜还没实现)
func steal_money(t: BattleUnit, amount: int, caster: BattleUnit = null) -> void:
	if t.reflect and caster:   # 皓月宝镜 (ATK 0x96): 改为对施术者生效, 提示「被【皓月宝镜】反弹」
		_message("被【皓月宝镜】反弹")
		t = caster
	if randi() % 1100 % 100 > 80:
		hud.pop(t, "miss")
		return
	if t.party:
		var take := mini(amount, State.money) if amount > 0 else 0
		State.money = maxi(State.money - take, 0)
		hud.pop(t, "money", take)
	else:
		var half := t.money / 2 if t.money > 1 else t.money
		if t.money > 1:
			t.money = maxi(t.money - half, 0)
		State.money = mini(State.money + half, 9999999)
		hud.pop(t, "money", half)


## ATK 0x46 / 0x80 召唤 (exe 0x444fd1 / 0x44525b, 逆向确认): 新单位放进第一个已倒的敌方槽, 没有就新开一槽 (最多 16 个单位);
## 0x46 的位置: 10 个候选点依次试 —— 前排 x = −400 / −220 / −40 / 140 / 320, z = 0 / 100 / 100 / 100 / 0; 后排同 x, z = 250 / 250 / 350 / 350 / 350;
##   要求那里有地面 (0x443678: 从 y + 200 往下找战场碰撞三角形) 且不与活着的敌人包围盒 (动作 XB + 位置) 重叠 (候选盒 x ± 40, y 80–180, z ± 40);
## 0x80 用脚本给的坐标 (同样检查地面 / 重叠)。y = 83 (0x46) / 脚本给的 y (0x80); 朝向 0; 出现时立刻全透明, 之后由招式脚本淡入
const SUMMON_SPOTS := [[-400, 0], [-220, 100], [-40, 100], [140, 100], [320, 0], [-400, 250], [-220, 250], [-40, 350], [140, 350], [320, 350]]


func atk_summon(id: int, _caster: BattleUnit, at: Variant) -> BattleUnit:
	var p: Variant = null
	if at is Vector3:
		if _spot_free(at.x, at.y, at.z):
			p = at
	else:
		for sp in SUMMON_SPOTS:
			if _spot_free(float(sp[0]), 80.0, float(sp[1])):
				p = Vector3(float(sp[0]), 83.0, float(sp[1]))
				break
	if p == null:
		return null
	var slot := -1
	for i in range(6, units.size()):
		var o: BattleUnit = units[i]
		if o != null and o.dead and not o.party:
			slot = i
			break
	if slot < 0:
		for i in range(6, units.size()):
			if units[i] == null:
				slot = i
				break
	if slot < 0:
		return null
	var old: BattleUnit = units[slot]
	if old and old.actor:
		old.actor.queue_free()
	var nu := _enemy_unit(id, slot, p, 0.0)
	units[slot] = nu
	for mi in nu.actor.find_children("*", "GeometryInstance3D", true, false):
		(mi as GeometryInstance3D).transparency = 1.0   # 0x434947(1, 255): 立刻隐藏
	if not _seen_ids.has(id):
		_seen_ids[id] = true
		Fame.add_monster(id, 5)
	return nu


## 0x443678 / 0x444ee4: 这里能不能放召唤的单位 —— 有地面, 且候选盒 (x ± 40, y 80–180, z ± 40) 不与活着的敌人包围盒重叠 (0x4103bc, 严格不等)
func _spot_free(x: float, y: float, z: float) -> bool:
	if not _floor_exists(x, y, z):
		return false
	var amin := Vector3(x - 40, 80, z - 40)
	var amax := Vector3(x + 40, 180, z + 40)
	for i in range(6, units.size()):
		var u: BattleUnit = units[i]
		if u == null or u.dead or u.actor == null:
			continue
		var bb: Array = u.actor.meta.get("poses", {}).get(str(u.actor.pose), {}).get("bbox", [])
		if bb.size() < 6:
			continue
		var p := u.pos()
		var bmin := Vector3(bb[0], bb[1], bb[2]) + p
		var bmax := Vector3(bb[3], bb[4], bb[5]) + p
		if amax.x > bmin.x and amax.y > bmin.y and amax.z > bmin.z and amin.x < bmax.x and amin.y < bmax.y and amin.z < bmax.z:
			return false
	return true


## 战场地面碰撞 (tools/export_battle.py → collision/bf_<场景>.bin: 三角形以场景包围盒最小角为原点)
var _bf_floor: StaticBody3D
var _bf_floor_min := Vector3.ZERO


func _load_bf_floor() -> void:
	var f := FileAccess.open(Game.asset_path("game/collision/bf_%s.bin" % str(bf.get("scene", ""))), FileAccess.READ)
	if f == null:
		return
	var nt := f.get_32()
	_bf_floor_min = Vector3(f.get_float(), f.get_float(), f.get_float())
	var tri := f.get_buffer(nt * 36).to_float32_array()
	var verts := PackedVector3Array()
	verts.resize(nt * 3)
	for k in nt * 3:
		verts[k] = to_world(Vector3(tri[k * 3], tri[k * 3 + 1], tri[k * 3 + 2]) + _bf_floor_min)
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(verts)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	_bf_floor = StaticBody3D.new()
	_bf_floor.collision_layer = 1 << 9
	_bf_floor.add_child(cs)
	_world.add_child(_bf_floor)


func _floor_exists(x: float, y: float, z: float) -> bool:
	if _bf_floor == null:
		return true   # 没有这个战场的碰撞数据: 不挡
	var space := _world.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(to_world(Vector3(x, y + 200.0, z)), to_world(Vector3(x, _bf_floor_min.y - 10.0, z)), 1 << 9)
	q.hit_back_faces = true
	return not space.intersect_ray(q).is_empty()


## 技能观看器施放: caster > 0 = 队员号, < 0 = 怪物 (−ObjDATA 编号, 换到敌方 6 号位); skill 0 = 普通攻击
func viewer_cast(caster: int, skill: int) -> void:
	# 观看器里单位不会轮流行动 (淡出的单位要到轮到自己时才复位, 0x433ff0), 每次施放前统一复位成可见 —— 只用于观看器
	for vu in units:
		if vu and vu.actor:
			for g in vu.actor.find_children("*", "GeometryInstance3D", true, false):
				(g as GeometryInstance3D).transparency = 0.0
	var u: BattleUnit = null
	if caster > 0:
		for x in units:
			if x and x.party and x.member == caster and not x.absent:
				u = x
	else:
		var mid := -caster
		var old: BattleUnit = units[6]
		if old == null or old.id != mid:
			var p := Vector3(0, 83, 380)
			if old:
				p = old.home
				if old.actor:
					old.actor.queue_free()
			units[6] = _enemy_unit(mid, 6, p, 0)
		for i in range(7, units.size()):   # 只留施法的怪物
			var o: BattleUnit = units[i]
			if o and o.actor:
				o.absent = true
				o.actor.visible = false
		u = units[6]
	if u == null:
		return
	if caster > 0 and (units[6] == null or not units[6].actor or units[6].party):
		units[6] = _enemy_unit(int(bf.enemies[0].id) if bf.get("enemies", []).size() else 1007, 6, Vector3(0, 83, 380), 0)
	u.mp = u.mp_max
	u.sp = u.sp_max
	u.juji = 100
	u.gauge = 0
	var foes: Array = alive(not u.party)
	if foes.is_empty():
		return
	viewer_actor = u   # 观看器正在施放的单位: 待机检查跳过它 (和车芸本体), 不然跑步动作被拉回站立 (「飘过去」); 回合循环会改 active, 不能用它
	if skill == 0:
		await _do_attack(u, [foes[0]])
	else:
		var r := obj(skill)
		var side := int(r.get("side", 2))
		var scope := int(r.get("scope", 0))
		var ts: Array
		if scope == 2:
			ts = [u]
		elif side == 1:
			var mates: Array = alive(u.party)
			for t in mates:
				t.hp = maxi(t.hp_max / 2, 1)   # 先扣一半, 才看得出回复量
			ts = mates if scope == 1 else [u]
		else:
			ts = foes if scope == 1 else foes.slice(0, 1)
		_message(str(r.get("name", "")))
		await _run_atk(u, ts, r, int(r.get("atk_id", 0)), false)
	await get_tree().create_timer(0.8).timeout
	viewer_actor = null
	for t in units:   # 复原
		if t and not t.absent:
			if t.dead:
				t.dead = false
				t.actor.visible = true
				for n in t.actor.find_children("*", "MeshInstance3D", true, false):
					(n as GeometryInstance3D).transparency = 0.0
			t.hp = t.hp_max
			t.status = 0
			t.status_turns.clear()
			t.status_prog.clear()
			t.buffs.clear()
			t.chanting = false
			t.gauge = 0
			if t.actor and t.actor.has_pose(IDLE_POSE):
				t.actor.play(IDLE_POSE)


## 技能测试 (--skill-test): 轮到会这招的队员就放下一招; 敌人不行动、每招后回满; 打印 SKILLTEST 结果
func _skill_test_turn(u: BattleUnit) -> void:
	if not u.party or u.summon:
		u.gauge = 0
		return
	var k := -1
	for i in skill_test.size():
		if int(skill_test[i][1]) == u.member:
			k = i
			break
	if k < 0:
		u.gauge = 0
		if skill_test.filter(func(x): return units.any(func(v): return v and v.party and not v.dead and v.member == int(x[1]))).is_empty():
			print("SKILLTEST_DONE")
			skill_testing = false
			_finish("win")
		return
	var id := int(skill_test[k][0])
	skill_test.remove_at(k)
	var r := obj(id)
	u.mp = u.mp_max
	u.sp = u.sp_max
	u.hp = u.hp_max
	u.juji = 100
	var side := int(r.get("side", 2))
	var scope := int(r.get("scope", 0))
	var ts: Array
	if scope == 2:
		ts = [u]
	elif side == 1:
		ts = units.filter(func(x): return x and x.party and not x.summon and not x.absent) if scope == 1 else [u]
	else:
		ts = alive(false) if scope == 1 else alive(false).slice(0, 1)
	for t in ts:
		if t.party and t != u:
			t.hp = maxi(t.hp_max / 2, 1)   # 我方目标先扣一半, 才看得出回复量
	if side == 1 and scope != 2:
		u.hp = maxi(u.hp_max / 2, 1)
	var before := {}
	for t in units:
		if t:
			t.buffs.clear()
			before[t] = [t.hp, t.status]
	var t0 := Time.get_ticks_msec()
	print("SKILLTEST_BEGIN %d %s member=%d atk=%d side=%d scope=%d f=%d" % [id, r.get("name", ""), u.member, int(r.get("atk_id", 0)), side, scope, Engine.get_frames_drawn()])
	var done := [false]
	get_tree().create_timer(25.0).timeout.connect(func():
		if not done[0]:
			print("SKILLTEST_STUCK %d %s" % [id, r.get("name", "")]))
	await _do_action(u, r, ts)
	done[0] = true
	var parts: Array = []
	for t in units:
		if t and before.has(t):
			var dh: int = t.hp - int(before[t][0])
			var ds: int = t.status & ~int(before[t][1])
			if dh != 0 or ds != 0:
				parts.append("%s:%+d%s" % [t.name, dh, (" st=0x%x" % ds) if ds else ""])
	for t in units:
		if t and t.buffs.size():
			var bb := {}
			for bk in t.buffs:
				bb[bk] = [int(t.buffs[bk][0]), int(t.buffs[bk][1]), t.base_stat(bk)]
			print("SKILLBUFF " + JSON.stringify({"t": t.name, "buffs": bb, "fx1": r.get("fx1", []), "fx2": r.get("fx2", []),
				"buff_rate": int(r.get("buff_rate", 0)), "turns": int(r.get("turns", 0))}))
	print("SKILLTEST %d %s member=%d ms=%d %s" % [id, r.get("name", ""), u.member, Time.get_ticks_msec() - t0, " ".join(parts) if parts.size() else "NO_EFFECT"])
	await get_tree().create_timer(2.3 if OS.get_cmdline_user_args().has("--skill-test-hold") else 0.3).timeout
	for t in units:   # 复原: 敌人回满并清状态、复活; 我方回满
		if t:
			if t.dead and not t.party:
				t.dead = false
				t.status = 0
				t.actor.visible = true
				for n in t.actor.find_children("*", "MeshInstance3D", true, false):
					(n as GeometryInstance3D).transparency = 0.0
				if t.actor.has_pose(14):
					t.actor.play(14)
			t.hp = t.hp_max
			t.status &= ~Formula.ST_DEAD
			t.status_turns.clear()
			t.status_prog.clear()
			t.status = 0
			t.buffs.clear()
			t.chanting = false
			t.gauge = 0   # 九天算尺追加的奋力一击必中 (roll_hit 6)


## 固定伤害 (0x433540 类型 0x2459 → 0x437320): 直接扣 HP, 无视防御 / 属性 / 状态倍率 / 完璧
func _fixed_damage(t: BattleUnit, dmg: int) -> void:
	t.hp = clampi(t.hp - dmg, 0, t.hp_max)
	hud.pop(t, "hp", dmg)
	hurt(t)
	_check_down(t)
	_check_end()


## 情绪状态 (0x4397e5 + 互斥矩阵 0x4cdb7c): 走统一的施加规则 (同一时间只有一种状态)
func _add_emotion(t: BattleUnit, bit: int, turns: int) -> void:
	Formula.try_status(t, bit, turns)


## 放一个 3D 道具 (法宝小游戏): 挂在单位的挂点位置 + 偏移 (游戏单位), 朝向 deg
func _prop(path: String, t: BattleUnit, marker: int, off: Vector3, deg: float) -> Node3D:
	var n := Game.load_glb(path)
	if n == null:
		return null
	_w.add_child(n)
	unshade(n)
	var mp: Variant = marker_pos(t, marker)
	var gp: Vector3 = (mp if mp != null else t.pos() + Vector3(0, 100, 0)) + off
	n.position = to_world(gp)
	n.rotation_degrees.y = deg
	for ap in n.find_children("*", "AnimationPlayer", true, false):
		var ap2 := ap as AnimationPlayer
		if ap2.get_animation_list().size():
			ap2.play(ap2.get_animation_list()[0])
	if path.begins_with("game/held/"):
		HELD_MORPH.attach(n, path)   # 手持物的逐帧变形 (例 鼠槌锤子 5212)
	return n


## 四非真面 (0x45209d): 脸谱本体在目标头顶 (挂点 3 上方 50), 每帧转 speed 度; 四个标签 (5210 qq2..5) 在四面,
## R = 角度 − 镜头偏航 落在 (225,315] 喜 / (135,225] 怒 / (45,135] 哀 / 其余 乐, 朝向镜头那面放大 (中心 1.3 倍附加);
## 按键停下 → 标签 2.5 / 2.3 倍交替闪 12 帧 → 返回 0 喜 / 1 怒 / 2 哀 / 3 乐
func _sifei(t: BattleUnit, speed: int) -> int:
	var root := Node3D.new()
	_w.add_child(root)
	var mp: Variant = marker_pos(t, 3)
	root.position = to_world((mp if mp != null else t.pos() + Vector3(0, 150, 0)) + Vector3(0, 50, 0))
	var body := Game.load_glb("game/held/item_5210_1.glb")
	if body:
		root.add_child(body)
		unshade(body)
	var labels: Array = []
	var centers := [270.0, 180.0, 90.0, 0.0]
	for k in 4:
		var piv := Node3D.new()
		root.add_child(piv)
		piv.rotation_degrees.y = centers[k]
		var lb := Game.load_glb("game/held/item_5210_%d.glb" % (k + 2))
		if lb:
			piv.add_child(lb)
			unshade(lb)
			lb.position = Vector3(0, 0, 0.7)
		labels.append(lb)
	var ang := 0.0
	var acc := 0.0
	var stop := -1
	var k_now := 0
	hud._mg_was = true
	while true:
		await get_tree().process_frame
		if stop < 0 and hud.mg_pressed(0.03):
			stop = 0
		acc += get_process_delta_time()
		while acc >= TICK:   # 小游戏逐帧更新 (0x45205a), 战斗 27 帧/秒
			acc -= TICK
			if stop < 0:
				ang = fmod(ang + speed, 360.0)
			else:
				stop += 1
		var r := fposmod(ang - cam.ang.y, 360.0)
		k_now = 0 if (r > 225 and r <= 315) else (1 if (r > 135 and r <= 225) else (2 if (r > 45 and r <= 135) else 3))
		var c: float = centers[k_now]
		var off := absf(fposmod(r - c + 180.0, 360.0) - 180.0)
		var sc := 1.3 if off <= 5.0 else 1.3 * maxf(45.0 - off, 0.0) / 45.0
		if stop >= 0:
			sc = 1.5 if (stop / 2) % 2 == 0 else 1.3
		root.rotation_degrees.y = ang
		for k in 4:
			if labels[k]:
				(labels[k] as Node3D).scale = Vector3.ONE * (1.0 + (sc if k == k_now else 0.0))
		if stop >= 12:
			break
	root.queue_free()
	return k_now


const ARTIFACT_LABEL := {5201: "聚劲", 5202: "完璧", 5204: "绝手", 5205: "视破", 5206: "回气", 5207: "双重", 5208: "龙爪",
	5210: "意乱", 5211: "龙颿", 5212: "鼠槌", 5213: "推算", 5214: "挪移", 5215: "转轮"}


## 装备着的法宝 (装备栏第 4、5 格 = P+0x592 / 0x594)
func _artifacts(u: BattleUnit) -> Array:
	var eq: Array = State.equip.get(u.member, [])
	return [int(eq[4]) if eq.size() > 4 else 0, int(eq[5]) if eq.size() > 5 else 0]


func _artifact_slots(u: BattleUnit) -> Array:
	return _artifacts(u).map(func(x): return x if ARTIFACT_LABEL.has(x) else 0)


## 使用法宝 (指令 15–29 → 0x4500d6; 效果 0x43a312, 参数取修练表当前等级); 返回 false = 取消
func _use_artifact(u: BattleUnit, id: int) -> bool:
	if id == 5207:
		return await _double(u)   # 双重走自己的指令 21 (0x45011a): 不读法宝记录、不扣消耗、不放法宝演出
	var r := obj(id)
	var p := State.artifact_params(id)
	var p0 := int(p[0]) if p.size() > 0 else 0
	var p1 := int(p[1]) if p.size() > 1 else 0
	var tv: Variant = await _choose_target(u, int(r.get("side", 1)), int(r.get("scope", 0)))
	if tv == null:
		return false
	var ts: Array = tv if tv is Array else [tv]
	if not _can_pay(u, r):   # 法宝消耗灵力 (80/80/50/50, 常转法轮 120; 0x4346e5)
		# 原版战斗里没有「灵力不足」这句 (那句只在地图菜单 0x4839be); 不足时原版显示哪条未查清, 先不显示
		Game.play_sound(0x20e)
		return false
	_pay(u, r)
	_message("使用法宝【%s】" % str(r.get("name", "")))   # 0x432006: 「使用法寶【%s】」
	await _run_atk(u, ts, r, int(r.get("atk_id", id)), false, false)
	match id:
		5201:   # 聚劲: 攻击 / 防御按参数增减 (以基础值为底), 必定成功
			for t in ts:
				t.add_buff("atk", Formula.amount(p0, t.base_stat("atk")), 3)
				t.add_buff("def", Formula.amount(p1, t.base_stat("def")), 3)
		5202:   # 完璧: p0 回合内物理伤害用金钱抵付
			for t in ts:
				t.wanbi_turns = p0
				t.wanbi_rate = maxi(p1, 1)
		5204:   # 绝手: 成功率 clamp(2×(40 − 目标等级 + 自身等级), 20, 100)%, 清除全部状态与增减益
			for t in ts:
				if randi() % 100 < clampi(2 * (40 - t.level + u.level), 20, 100):
					for b in Formula.STATUS_NAMES:
						t.clear_status(b)
					t.buffs.clear()   # 原版绝手成功 / 失败都不显示文字 (表里的两句没有代码引用)
				else:
					hud.pop(t, "miss")
		5205:   # 视破 (0x43a49d)
			for t in ts:
				await _spy(u, t)
		5206:   # 回气: 回复所缺生命 / 灵力 / 体力的 p0%
			for t in ts:
				var h := Formula.amount(p0, t.hp_max - t.hp)
				t.hp = mini(t.hp + h, t.hp_max)
				hud.pop(t, "heal", h)
				var m2 := Formula.amount(p0, t.mp_max - t.mp)
				t.mp = mini(t.mp + m2, t.mp_max)
				if m2:
					hud.pop(t, "mp", m2)
				var s2 := Formula.amount(p0, t.sp_max - t.sp)
				t.sp = mini(t.sp + s2, t.sp_max)
				if s2:
					hud.pop(t, "sp", s2)
		5207:   # 双重: 下一次施法放两次
			pass   # 不会走到这里: 双重在 _use_artifact 开头就转去 _double
		5208:   # 龙爪: 偷窃 (掉落第 1 组, rand(400)%100 ≤ 几率, 成功后清空)
			for t in ts:
				var dr: Array = t.rec.get("drops", [])
				if dr.size() > 1 and int(dr[1][1]) and randi() % 400 % 100 <= int(dr[1][0]):
					State.give_item(int(dr[1][1]), 1)
					_message("成功偷取到%s!!" % obj(int(dr[1][1])).get("name", ""))   # 0x4368b0
					t.rec = t.rec.duplicate(true)
					t.rec.drops[1] = [0, 0]
				elif dr.size() > 1 and int(dr[1][1]):
					_message("偷窃失败!!")   # 0x4368ef
				else:
					_message("此敌人身上已无物品!!")   # 0x43684d
		5214:   # 挪移: 打向自己的招式转给选中的敌人 (unit+0x1bf4)
			for t in ts:
				if not t.party:
					u.redirect = t   # 原版施放时不显示文字 (只有到期时「%s解除【挪移】功能!!」)
					u.nuoyi_turns = p0   # 0x43aa19: +0x1bf8 = 修练参数 +0x1c (回合), +0x1bfc = +0x20 (次数)
					u.nuoyi_uses = p1
		5215:   # 转轮 (常转法轮): 转盘定结果
			await _wheel(u, ts)
		5210:   # 意乱 (四非真面, 0x45209d): 目标头顶的四面脸谱一直转, 按键停下, 朝向镜头的那面定情绪; 必定成功, 4 回合
			var t: BattleUnit = ts[0]
			var k := await _sifei(t, maxi(p0, 1))
			_add_emotion(t, [Formula.ST_JOY, Formula.ST_RAGE, Formula.ST_SORROW, Formula.ST_MANIA][k], int(r.get("turns", 4)))
		5211:   # 龙颿 (0x45275c): 拉霸定数字 = 固定伤害 (无视防御 / 状态), 第 k 个目标延迟 15k 帧
			var dmg := await hud.longfan(maxi(p0, 1), maxi(p1, 1))
			for i in ts.size():
				if i:
					await get_tree().create_timer(15.0 * TICK).timeout   # 0x45275c: 第 k 个目标延迟 15k 帧 (战斗 27 帧/秒)
				_fixed_damage(ts[i], dmg)
		5212:   # 鼠槌 (0x45264c): 4 秒内每按一下锤一下, 每下固定伤害 (旗标 5530 后翻倍)
			var per := maxi(p0, 1) * (2 if State.test_flag(5530) else 1)
			var t2: BattleUnit = ts[0]
			var ham := _prop("game/held/item_5212_1.glb", t2, 2, Vector3(0, 0, -100 * (1 if t2.party else -1)), 270.0)
			await hud.shuchui(func():
				Game.play_sound(978)
				if is_instance_valid(ham):
					for ap in ham.find_children("*", "AnimationPlayer", true, false):
						(ap as AnimationPlayer).stop()
						(ap as AnimationPlayer).play((ap as AnimationPlayer).get_animation_list()[0])
				if not t2.dead:
					_fixed_damage(t2, per))
			if is_instance_valid(ham):
				ham.queue_free()
		5213:   # 推算 (九天算尺, 0x452a20): 停在判定窗内 → 立刻追加一次必中的奋力一击 (不占回合)
			if await hud.suanchi(maxi(p0, 1)):
				for t3 in ts:
					if not t3.dead:
						await _do_attack(u, [t3], true, true)
			else:
				for t3 in ts:
					hud.pop(t3, "miss")
				_message("推算失误!!")
		_:
			pass
	return true


## 常转法轮结果 (0x452f39): 0 对方石化 / 1 敌方全灭 / 2 我方全补 / 3 自己石化 / 4 平安即福 / 5 自己衰竭 / 6 对方衰竭
## 石化 = 状态 0x10 (5 回合); 衰竭 = 0x4397e5(位 1): 走伤害路径, 伤害 = 当前 HP − 上限/4 (不足上限/4 时为 0), 弹伤害数字
## 结果在倒数 30 帧后施加, 随即结束 ([0x92522c] = 0), 没有额外等待
func _wheel(u: BattleUnit, ts: Array) -> void:
	var res := await hud.wheel()   # 结果只在转盘列表里高亮 (0x4533eb), 不另弹顶部消息
	match res:
		0:
			for t in ts:
				Formula.try_status(t, Formula.ST_STONE, 5)
		1:
			for t in alive(false):
				hud.pop(t, "hp", t.hp)
				t.hp = 0
				_check_down(t)
		2:
			for t in alive(true):
				hud.pop(t, "heal", t.hp_max - t.hp)
				t.hp = t.hp_max
				t.mp = t.mp_max
				t.sp = t.sp_max
		3:
			Formula.try_status(u, Formula.ST_STONE, 5)
		5:
			_exhaust(u)
		6:
			for t in ts:
				_exhaust(t)
	_check_end()


## 「衰竭」0x4397e5(1, …) (0x439967): 伤害 = 当前 HP − 上限 / 4 (当前 HP 不超过上限 / 4 时为 0), 伤害飘字 0x2459
func _exhaust(t: BattleUnit) -> void:
	var q := t.hp_max / 4
	var d := t.hp - q if t.hp > q else 0
	if d > 0:
		hud.pop(t, "hp", d)
		t.hp -= d


func _try_escape(u: BattleUnit) -> void:
	if no_escape:
		_message("无法脱离战斗!!")
		return
	if Formula.escape_ok(alive(true), alive(false)):
		await get_tree().create_timer(0.8).timeout
		_finish("escape")
	else:
		_message("%s逃跑失败" % u.name)
		await get_tree().create_timer(0.6).timeout


func _skills_of(u: BattleUnit, subs: Array) -> Array:
	var out: Array = []
	for s2 in State.skills.get(u.member, []):
		var r := obj(int(s2))
		if r.is_empty() or int(r.get("atk_id", 0)) == 0:
			continue
		var sb := int(r.get("sub", 0))
		if sb in subs or (subs.has(201) and sb not in [302, 305, 306]):
			out.append(int(s2))
	return out


func _skill_entries(u: BattleUnit, subs: Array) -> Array:
	var out: Array = []
	for s2 in State.skills.get(u.member, []):
		var r := obj(int(s2))
		if r.is_empty() or int(r.get("atk_id", 0)) == 0 or int(r.get("sub", 0)) not in subs:
			continue
		var c: Dictionary = r.get("cost", {})
		var cost := Formula.cost_of(int(c.get("mp", 0)), u.mp_max)
		if cost == 0:
			cost = Formula.cost_of(int(c.get("sp", 0)), u.sp_max)
		out.append({"id": int(s2), "name": str(r.name), "right": "%3d" % cost, "ok": _can_pay(u, r) and _usable_extra(r, int(s2)),
			"desc": str(r.get("desc", "")), "note": str(r.get("note", ""))})
	return out


func _item_entries(sb: int) -> Array:
	var out: Array = []
	for it in State.items:
		var r := obj(int(it))
		if r.get("kind") == 2 and int(r.get("sub", 0)) == sb and int(r.get("atk_id", 0)) and int(State.items[it]) > 0:
			out.append({"id": int(it), "name": str(r.name), "right": "%2d" % int(State.items[it]), "ok": _usable_extra(r, int(it)),
				"desc": str(r.get("desc", "")), "note": str(r.get("note", "")), "icon": str(r.get("icon", ""))})
	return out


## 使用检查 0x434470 里消耗之外的条件 (逆向确认):
## * 机关招式要持有对应的木甲 (0x462379 查背包 0xbceca0 数量 > 0): 伏兵 6011 → 投射木甲兵 5545, 火砲 6012 → 木甲穷奇 5544,
##   威吓 6019 / 千羽 6022 / 穿云 6023 → 木甲机风鹰 5543 (以前没检查, 没有木甲也能放)
## * DOMO令牌 3905: [0x92520e]&0x80 (FIGTALK 0x7e0) 时不能用; 另外任一敌方槽位单位 +0x1960 & 1 时也不能用
##   —— 这一位不是由战斗指令置位的 (0x434a03 的调用都不带 1), 来源未定位, 暂不检查
const NEED_ITEM := {6011: 5545, 6012: 5544, 6019: 5543, 6022: 5543, 6023: 5543}


func _usable_extra(r: Dictionary, id: int) -> bool:
	if NEED_ITEM.has(id) and int(State.items.get(NEED_ITEM[id], 0)) <= 0:
		return false
	if id == 3905 and domo_off:
		return false
	return true


func _can_pay(u: BattleUnit, r: Dictionary) -> bool:
	var c: Dictionary = r.get("cost", {})
	return u.mp >= Formula.cost_of(int(c.get("mp", 0)), u.mp_max) and u.sp >= Formula.cost_of(int(c.get("sp", 0)), u.sp_max) \
		and u.hp > Formula.cost_of(int(c.get("hp", 0)), u.hp_max) and u.juji >= int(c.get("juji", 0))


func _pay(u: BattleUnit, r: Dictionary) -> void:
	var c: Dictionary = r.get("cost", {})
	u.mp = maxi(u.mp - Formula.cost_of(int(c.get("mp", 0)), u.mp_max), 0)
	u.sp = maxi(u.sp - Formula.cost_of(int(c.get("sp", 0)), u.sp_max), 0)
	u.hp = maxi(u.hp - Formula.cost_of(int(c.get("hp", 0)), u.hp_max), 1)
	u.juji = maxi(u.juji - int(c.get("juji", 0)), 0)


# ---------------- 执行动作 ----------------

## 普通攻击: 先判暴击 (状态 0x28 → 用 0x3EE 的演出, 我方 ×2/×3, 怪物 ×2)
func _do_attack(u: BattleUnit, ts: Array, force_crit := false, must_hit := false) -> void:
	var crit := force_crit or Formula.roll_crit(u)
	_force_hit = must_hit
	var rec: Dictionary = u.weapon.duplicate()
	rec["_normal"] = true
	# 法宝「鬼鸡爪子」(5203, 被动): 普攻打全体, 伤害按修练参数缩放 (0x43a3a2)
	if u.party and _artifacts(u).has(5203):
		ts = alive(false)
		var p := State.artifact_params(5203)
		if p.size():
			rec["_scale"] = int(p[0])
	var atk := int(rec.get("atk2_id", 0)) if crit and int(rec.get("atk2_id", 0)) else int(rec.get("atk_id", 0))
	if atk == 0:
		atk = int(u.rec.get("atk_id", 1101))
	if crit:
		_message("奋力一击!!")   # 0x4e2fb8, 不带人名
	await _run_atk(u, ts, rec, atk, crit)
	_force_hit = false


## 下方状态栏开关 [0x4e38a0] (写入点逆向确认): 战斗开始 1; 我方单位轮到 (0x441804)、任一行动结束 (0x4413da)、
## 我方受击 / 回复 / HP·MP·SP 结算 (0x433348 / 0x433540 / 0x437320) → 1; 我方执行技能类指令 (指令 6/7/9/10/13 = sub 201–203 / 305 / 306,
## 0x450228)、任一单位吟咒释放 (0x439f4f)、强制胜利 (FIGTALK 0x96 / 0x97) → 0; FIGTALK 0x7e4 / ATK 0x99 → 参数
const PANEL_HIDE_SUBS := [201, 202, 203, 305, 306]


func _do_action(u: BattleUnit, r: Dictionary, ts: Array) -> void:
	if u.party and int(r.get("kind", 0)) == 3 and int(r.get("sub", 0)) in PANEL_HIDE_SUBS:
		hud_panel = false
	_message(str(r.get("name", "")))
	await _run_atk(u, ts, r, int(r.get("atk_id", 0)), false)


func _do_defend(u: BattleUnit) -> void:
	_end_turn_cam()
	u.defending_cmd = true
	if u.actor.has_pose(3):
		u.actor.play(3)
	apply_settle(u, u, {}, 1, false)
	u.defending_cmd = false
	u.defending = true
	await get_tree().create_timer(0.6).timeout


func _run_atk(u: BattleUnit, ts: Array, rec: Dictionary, atk_id: int, crit: bool, settle := true) -> void:
	if ts.size() == 1 and ts[0] is BattleUnit and ts[0] != u:
		_cur_target = ts[0]   # [0x925254]: 单体招式的目标 (群体时存什么未查, 不记)
	# 招式入队 (0x446e0d): 施法者或任何目标是护驾 → 这些护驾立即完全显示 (0x434947(0, 0xff))
	for x in [u] + ts:
		if x is BattleUnit and x.summon and not x.dead and x.actor:
			fade_unit(x, false, 0xff)
	var a: Dictionary = db.atk.get(str(atk_id), {})
	var steps: Array = a.get("steps", [])
	if a.has("variants"):
		var vs: Array = a.variants
		var tot := 0
		for v in vs:
			tot += int(v.weight)
		var r := randi() % maxi(tot, 1)
		for v in vs:
			r -= int(v.weight)
			if r < 0:
				steps = v.steps
				break
	var run := AtkRunner.new()
	run.bt = self
	run.caster = u
	run.targets = ts
	run.settle = settle
	run.act = rec
	run.crit = crit
	run.steps = steps
	add_child(run)
	face(u, 1)
	_end_turn_cam()
	_saved_cam = {"ft": cam.ft, "angt": cam.angt, "dt": cam.dt, "follow": cam.follow, "off": cam.follow_off}
	await run.run()   # 直接等执行函数 (全是镜头指令的演出会同步跑完, 等信号会错过)
	run.queue_free()
	if not u.dead:
		face(u, 0)
	aura_fade(u, true, 20)   # 0x44127d: 行动结束 (+0x19cc) 后光环以每帧 20 淡入


func _default_cam_smooth() -> void:
	for ch in 3:
		cam.set_mode(ch, 3)
		cam.set_speed(ch, 6)
	cam.set_target(Vector3(15, 40, -240))
	cam.set_angles(16, 359, 0)
	cam.set_distance(1600)
	cam.zoom_kt = 10.0


## 结算一次 (0x443cd8 → 0x437858 → 0x437320)
func apply_settle(att: BattleUnit, t: BattleUnit, rec: Dictionary, hit_result: int, crit: bool) -> void:
	if t == null or t.absent:
		return
	# 法宝「挪移」(5214): 打向我方的招式转给指定的敌人
	t = _nuoyi_target(t, rec)
	var sid := int(rec.get("atk_id", 0))
	# 宣告死亡 (0x437bcd): 攻击者当前动作记录是 3405「三更勾魂锣」(ATK 4405, 数据里唯一) 且命中 → 目标有替身就只拿掉替身、显示无效;
	# 否则倒数无条件设为 3 (弹数字 3), 不扣血; 不分敌我
	if sid == 4405 and hit_result == 1 and not rec.get("_normal", false):
		if t.has(Formula.ST_DECOY):
			t.clear_status(Formula.ST_DECOY)
			hud.pop(t, "invalid")
		else:
			t.doom = 3
			hud.pop(t, "doom", 3)
			if OS.get_cmdline_user_args().has("--trace-events"):
				print("DOOM_SET %s" % t.name)
		return
	if sid >= 6024 and sid <= 6027 and hit_result == 1 and not rec.get("_normal", false):
		_mech_skill(att, t, sid)   # 木甲术: 不走普通伤害公式 (0x437ba5 / 0x4388fa)
		return
	var r := Formula.settle(att, t, rec, hit_result, crit)
	if rec.has("_scale") and int(r.hp) > 0:
		r.hp = maxi(1, int(r.hp) + Formula.amount(int(rec._scale), int(r.hp)))   # dmg × (1 + p0%)
	if OS.get_cmdline_user_args().has("--trace-events"):
		print("SETTLE %s→%s hit=%d crit=%s atk=%d def=%d result=%s" % [att.name, t.name, hit_result, crit,
			att.stat("atk"), t.stat("def"), str(r)])
	if skill_testing or OS.get_cmdline_user_args().has("--trace-settle"):
		# 技能验证: 输入和结果都打出来, 由 tools/verify_skills.py 按原版公式独立复算
		print("SETTLEJ " + JSON.stringify({"att": att.name, "att_party": att.party, "att_lv": att.level, "att_matk": att.stat("matk"),
			"att_atk": att.stat("atk"), "att_status": att.status, "t": t.name, "t_party": t.party, "t_lv": t.level,
			"t_mdef": t.stat("mdef"), "t_def": t.stat("def"), "t_status": t.status, "t_defending": t.defending,
			"t_elem": t.defense_elem(), "rec_id": int(rec.get("id", 0)), "rec_name": str(rec.get("name", "")),
			"kind": int(rec.get("kind", 0)), "sub": int(rec.get("sub", 0)), "power": int(rec.get("power", 0)),
			"elem": rec.get("elem", []), "w_elem": att.attack_elem(), "normal": bool(rec.get("_normal", false)),
			"hit": hit_result, "crit": crit, "hp": int(r.hp), "mp": int(r.get("mp", 0)), "sp": int(r.get("sp", 0)),
			"miss": bool(r.miss), "text": str(r.text), "t_hp_max": t.hp_max, "t_mp_max": t.mp_max, "t_sp_max": t.sp_max,
			"fx1": rec.get("fx1", []), "fx2": rec.get("fx2", []), "t_hp": t.hp, "t_sub": int(t.rec.get("sub", 0)),
			"t_member": t.member, "status_mask": int(rec.get("status", 0)), "status_op": int(rec.get("status_op", 0)),
			"immune": int(rec.get("immune", 0)), "target_class": int(rec.get("target_class", 0))}))
	if r.miss:
		hud.pop(t, "miss")
		return
	if str(r.text) != "":
		if str(r.text) == "无效":
			hud.pop(t, "invalid")
		# 原版这里不显示文字 (「替身」只在解除时「解除替身狀態了!!」)
	var dmg := int(r.hp)
	# 法宝「完璧」(5202): 物理伤害用金钱抵付, 每枚金钱抵 p1 点 (0x43ae07)
	if dmg > 0 and t.wanbi_turns > 0 and (rec.get("_normal", false) or int(rec.get("kind", 0)) == 1):
		var cost := ceili(float(dmg) / maxf(t.wanbi_rate, 1))
		if State.money >= cost:
			State.money -= cost
			_message("【投币式铠甲】发挥效用")   # 0x43ae5d
			dmg = 0
	if dmg != 0:
		if dmg > 0 and t.dead:
			return
		t.hp = clampi(t.hp - dmg, 0, t.hp_max)
		if dmg > 0:
			hud.pop(t, "hp", dmg)
			hurt(t)
			if att.party and not t.party:
				_juji_gain_hit(att, t)
			elif t.party:
				_juji_gain_hurt(t, att, dmg)
		else:
			if t.dead and t.hp > 0:
				t.revive()
			hud.pop(t, "heal", -dmg)
	if int(r.mp):
		t.mp = clampi(t.mp + int(r.mp), 0, t.mp_max)
		hud.pop(t, "mp", int(r.mp))
	if int(r.sp):
		t.sp = clampi(t.sp + int(r.sp), 0, t.sp_max)
		hud.pop(t, "sp", int(r.sp))
	_check_down(t)


## 蓄劲值 (§3g)
func _juji_gain_hit(att: BattleUnit, t: BattleUnit) -> void:
	var d := t.level - att.level
	var g := 2 if d < 0 else (3 if d <= 5 else (4 if d <= 10 else (5 if d <= 15 else (6 if d <= 20 else 10))))
	att.juji = mini(100, att.juji + g)


func _juji_gain_hurt(t: BattleUnit, att: BattleUnit, dmg: int) -> void:
	var g := dmg * 100 / maxi(t.hp_max, 1)
	var d := att.level - t.level
	if d >= 11:
		g /= 5
	elif d >= 6:
		g /= 4
	elif d >= 0:
		g /= 3
	t.juji = mini(100, t.juji + g)


func hurt(t: BattleUnit) -> void:
	if t.actor == null or t.dead:
		return
	# 受击动作 (0x43b843): 25 (0x19); 防御中 24 (0x18)。动作自带叫喊音效 (ACT 的 VW 标签)
	var hq := 24 if (t.defending and t.actor.has_pose(24)) else 25
	# 已经在播受击动作 (状态 0x37) 时不重播 (0x43b93b): 一招里 e 记号 + 结算会连着调好几次, 每次从第 0 帧重来会一闪一闪
	if t.actor.pose == hq and t.actor.pose_tick < t.actor.pose_len - 1:
		return
	if t.actor.has_pose(hq):
		t.actor.play(hq)
	if t.party:
		face(t, 3)
	# 状态 0x37 (0x43b843): 受击动作播完 → 动作 14 (站立); 不转身朝攻击者, 也没有位移 (以前加的后退补间是自己加的)
	_hurt_done(t, hq)


func _hurt_done(t: BattleUnit, hq: int) -> void:
	var a := t.actor
	while is_instance_valid(a) and a.pose == hq and a.pose_tick < a.pose_len - 1:
		await get_tree().process_frame
	if not is_instance_valid(a) or t.dead or a.pose != hq:
		return
	if a.has_pose(IDLE_POSE):
		a.play(IDLE_POSE)
	if t.summon:
		fade_unit(t, true, 0x19)   # 0x43b928: 护驾受击结束淡出
	if t.party and t != active:
		face(t, 0)


func _check_down(t: BattleUnit) -> void:
	if t.hp > 0 or t.dead:
		return
	# 法宝「菩萨发咒」(5209, 被动): 每场免死一次 (unit+0x1963 |= 2, 0x4364cb)
	if t.party and not t.survive_used and _artifacts(t).has(5209):
		t.survive_used = true
		t.hp = 1
		return
	t.dead = true
	t.status |= Formula.ST_DEAD
	t.chanting = false   # 死亡静默解除吟咒
	t.chant_speed = 0
	t.chant_fx = 0
	# 倒地动作 26 (0x1a, 0x430d8e / 0x43d076; 0x35 是「死亡」动作状态号, 不是动作号), 自带惨叫和落地声
	if t.actor.has_pose(26):
		t.actor.play(26)
	face(t, 4)
	if t.summon:
		_guard_down(t)
		return
	if not t.party:
		var kv: Array = t.rec.get("kill_var", [])
		if kv.size() == 2:   # 创意工坊: mod 怪物被打倒时给 mod 变量 +1 (角色变量, 同事件 add_actor_var)
			State.set_actor_var(int(kv[0]), int(kv[1]), State.actor_var(int(kv[0]), int(kv[1])) + 1)
		if not t.captured:   # 被收化的不给经验 / 金钱 / 资源 (0x442738 第 2 个参数); 掉落照常 (0x45aa24 不查 +0x1a08)
			var rw: Dictionary = t.rec.get("reward", {})
			rewards.exp += int(rw.get("exp", 0))
			rewards.money += int(rw.get("money", 0))
			var res: Array = rw.get("res", [0, 0, 0])
			for k in 3:
				rewards.res[k] += int(res[k])
		var drops: Array = t.rec.get("drops", [])
		if drops.size() and int(drops[0][1]) and randi() % 300 % 100 < int(drops[0][0]):
			rewards.items.append(int(drops[0][1]))
		if t.captured:
			_capture_death(t)
		else:
			_enemy_death(t)


## 被收化的死亡表现 (死亡方式 2, 0x43c497 写入): 子状态 0 当帧就放特效 8117 动作 0 (单位位置 +(0, 20, 50));
## 倒地动作 26 播放期间不透明度 ≥ 150 时每帧 −5; 播完后继续 −5 到 ≤ 150; 然后每帧缩放减去 0.05 × 原缩放,
## 任一轴 ≤ 0.2 时不透明度清 0 (不再画)
func _capture_death(t: BattleUnit) -> void:
	var a := t.actor
	_death_fx(t)
	var alpha := 255
	var s0 := a.scale
	var acc := 0.0
	var sub := 1
	while is_instance_valid(a) and sub < 5:
		await get_tree().process_frame
		acc += get_process_delta_time()
		while acc >= TICK and sub < 5:
			acc -= TICK
			match sub:
				1:
					if alpha >= 150:
						alpha -= 5
					if not (a.pose == 26 and a.pose_tick < a.pose_len - 1):
						sub = 3
				3:
					if alpha > 150:
						alpha -= 5
					else:
						sub = 4
				4:
					a.scale -= s0 * 0.05
					if a.scale.x <= 0.2 or a.scale.y <= 0.2 or a.scale.z <= 0.2:   # 原版比的是绝对值 0.2
						alpha = 0
						sub = 5
		for g in a.find_children("*", "GeometryInstance3D", true, false):
			(g as GeometryInstance3D).transparency = 1.0 - alpha / 255.0
	if is_instance_valid(a):
		a.visible = false


## 敌人死亡表现 (状态 0x35, 0x43c977; 死亡方式 1): 等倒地动作 26 播完 → 在单位位置 +(0, 20, 50) 放特效 ACT 8117 (0x1fb5)
## 动作 0 (朝向 = 单位朝向) → 每帧不透明度 −5, 到 ≤ 5 停 (50 帧) → 删掉特效, 单位不再画
## 我方队员倒地后不淡出 (子状态 2 直接结束); 收化 (方式 2) 走收化流程
## 死亡特效 (0x43cd99 / 收化在 0x43d0a7): 记录子类 (unit +0x13ac = 记录 +0x98, 数据里的 sub) 是 0x76 / 0x77 (机关类)
## → 音效 0x357 + 粒子系统 2023「機關爆炸」(0x493634, 在 (x, y+30, z), 累计 20 颗自己结束); 否则 ACT 8117 动作 0 在 (x, y+20, z+50)
func _death_fx(t: BattleUnit) -> Node:
	if int(t.rec.get("sub", 0)) in [0x76, 0x77]:
		Game.play_sound(0x357)
		Fx.spawn_particles(world_node(), 2023, to_world(t.pos() + Vector3(0, 30, 0)), cam3d())
		return null
	return _fx_at("8117_0", t.pos() + Vector3(0, 20, 50), t.actor.facing)

func _enemy_death(t: BattleUnit) -> void:
	var a := t.actor
	while is_instance_valid(a) and a.pose == 26 and a.pose_tick < a.pose_len - 1:
		await get_tree().process_frame
	if not is_instance_valid(a):
		return
	var fx := _death_fx(t)
	if OS.get_cmdline_user_args().has("--trace-events"):
		print("DEATH_FX %s f=%d" % [t.name, Engine.get_frames_drawn()])
	var alpha := 255
	var acc := 0.0
	while alpha > 5:
		await get_tree().process_frame
		acc += get_process_delta_time()
		while acc >= TICK and alpha > 5:
			acc -= TICK
			alpha -= 5
		if not is_instance_valid(a):
			break
		for g in a.find_children("*", "GeometryInstance3D", true, false):
			(g as GeometryInstance3D).transparency = 1.0 - alpha / 255.0
	if fx and is_instance_valid(fx):
		fx.queue_free()
	if is_instance_valid(a):
		a.visible = false


func _check_end() -> void:
	# 结束流程 0x442925: 锁定中 ([0x9253c0], FIGTALK 0x18) 或自动结束方式非 0 ([0x925a24]) 时不触发; 解锁时再检查一次
	if result != "" or viewer or end_mode != 0 or locked:
		return
	if alive(false).is_empty():
		_finish("win")
	elif alive(true).filter(func(x): return not x.summon).is_empty():   # 护驾不算活着的队员
		_finish("lose")


# ---------------- 敌方 AI (0x401ae0) ----------------

func _enemy_turn(u: BattleUnit) -> void:
	for fa in OS.get_cmdline_user_args():   # 调试: --force-enemy-skill=技能号 敌人轮到时直接对我方放这招
		if fa.begins_with("--force-enemy-skill=") and not u.party:
			var fr := obj(int(fa.substr(20)))
			if fr.size():
				var fts: Array = alive(true) if int(fr.get("scope", 0)) == 1 else alive(true).slice(0, 1)
				_message(str(fr.get("name", "")))
				await _run_atk(u, fts, fr, int(fr.get("atk_id", 0)), false)
				u.gauge = 0
				return
	var code: Array = db.ai.get(str(int(u.rec.get("ai", 0))), [])
	var at := {}
	for i in code.size():
		at[int(code[i][0])] = i
	var side := 1
	var rule: Variant = null
	var cand: Array = []
	var pc := 0
	var guard := 0
	while pc < code.size() and guard < 200:
		guard += 1
		var ins: Array = code[pc]
		pc += 1
		var op := int(ins[1])
		var a: Array = ins[2]
		var tg: Array = ins[3]
		match op:
			0x190:
				side = int(a[0])
				rule = null
			0x19a:
				rule = ["hp_below", int(a[0])]
			0x7d4:
				rule = ["has", STATUS_IDX[clampi(int(a[0]), 0, STATUS_IDX.size() - 1)]]
			0x7d5:
				rule = ["not", STATUS_IDX[clampi(int(a[0]), 0, STATUS_IDX.size() - 1)]]
			0x19c:
				rule = ["only"]
			0x1a1:
				rule = ["ally"]   # 「自己属于玩家阵营」(护驾), 和后面的 0x1f5 100 连用跳到简化 AI
			0x193:
				cand = _ai_candidates(u, side, rule)
				if await _ai_try(u, int(a[0]), cand, side):
					return
				rule = null
			0x1f4:
				var r := randi() % 100
				for k in a.size():
					r -= int(a[k])
					if r < 0:
						pc = at.get(int(tg[k]), pc)
						break
			0x1f5:
				cand = _ai_candidates(u, side, rule) if rule != null else [u]
				if cand.size() and randi() % 100 < int(a[0]):
					pc = at.get(int(tg[0]), pc)
				rule = null
			0x1f6:
				if alive(not u.party).size() >= int(a[0]):
					pc = at.get(int(tg[0]), pc)
			0x7d0:
				var n := int(a[1])
				if (int(a[0]) == 0 and u.actions_taken == n) or (int(a[0]) != 0 and n > 0 and u.actions_taken % n == 0):
					pc = at.get(int(tg[0]), pc)
			0x7d6:
				if alive(int(a[0]) == 1).size() >= int(a[1]):
					pc = at.get(int(tg[0]), pc)
			0x7d9:
				pass
			0x3e8:
				battle_vars[int(a[0])] = 1
			0x3e9:
				battle_vars[int(a[0])] = 0
			0x3ea:
				if int(battle_vars.get(int(a[0]), 0)) == 1:
					pc = at.get(int(tg[0]), pc)
			0x3eb:
				counters[int(a[0])] = int(counters.get(int(a[0]), 0)) + 1
			0x3ec:
				counters[int(a[0])] = 0
			0x3ed:
				if int(counters.get(int(a[0]), 0)) >= int(a[1]):
					pc = at.get(int(tg[0]), pc)
			0x000a, 0x0032:
				pc = at.get(int(tg[randi() % tg.size()] if op == 0x32 else tg[0]), pc)
			0x0066, 0xffff:
				break
	# 走到结尾还没选出行动: 普攻随机目标
	var ps := alive(true)
	if ps.size():
		await _do_attack(u, [ps[randi() % ps.size()]])


func _ai_candidates(u: BattleUnit, side: int, rule: Variant) -> Array:
	var pool: Array
	match side:
		1:
			pool = alive(not u.party)
		2:
			pool = alive(u.party)
		_:
			pool = [u]
	if rule == null:
		return pool
	match str(rule[0]):
		"hp_below":
			pool = pool.filter(func(x): return x.hp * 100 < x.hp_max * int(rule[1]))
			pool.sort_custom(func(x, y): return x.hp * y.hp_max < y.hp * x.hp_max)
			return pool.slice(0, 1)
		"has":
			return pool.filter(func(x): return x.status & int(rule[1]))
		"not":
			return pool.filter(func(x): return not (x.status & int(rule[1])))
		"only":
			return pool if pool.size() == 1 else []
		"ally":
			return [u] if u.summon else []
	return pool


## 尝试行动 w: 1 普攻, 2 休息 (回复最大 HP 1/10), 3–7 技能槽 1–5 (受每场次数限制, 咒封不可), 8 逃跑
func _ai_try(u: BattleUnit, w: int, cand: Array, side: int) -> bool:
	if cand.is_empty():
		return false
	var pick: BattleUnit = cand[randi() % cand.size()]
	match w:
		1:
			await _do_attack(u, [pick])
			return true
		2:
			var h := u.hp_max / 10
			u.hp = mini(u.hp + h, u.hp_max)
			hud.pop(u, "heal", h)
			await get_tree().create_timer(0.6).timeout
			return true
		8:
			u.absent = true
			u.fled = true   # +0x1a08 = 1 (0x43d3f0)
			u.actor.visible = false
			_message("%s逃跑了" % u.name)   # 0x43d37c
			return true
	if w >= 3 and w <= 7:
		if u.has(Formula.ST_SEAL):
			return false
		var slot := w - 3
		var sk: Array = u.rec.get("skills", [])
		var lim: Array = u.rec.get("uses", [])
		if slot >= sk.size() or int(sk[slot]) == 0:
			return false
		if slot < lim.size() and int(lim[slot]) > 0 and int(u.uses.get(slot, 0)) >= int(lim[slot]):
			return false
		u.uses[slot] = int(u.uses.get(slot, 0)) + 1
		var r := obj(int(sk[slot]))
		var ts: Array = [pick]
		if int(r.get("scope", 0)) == 1:
			ts = cand
		elif int(r.get("scope", 0)) == 2:
			ts = [u]
		if int(r.get("chant", 0)) > 0:   # 吟咒技能 (0x402eb3 → 0x439e52)
			await _enter_chant(u, r, ts)
			return true
		await _do_action(u, r, ts)
		return true
	return false


# ---------------- 战斗剧情 FIGTALK (0x45b7bd) ----------------

func _run_figtalk() -> void:
	var code: Array = db.figtalk.get(str(int(bf.get("figtalk", bf_id - 1))), [])
	var at := {}
	for i in code.size():
		at[int(code[i][0])] = i
	_figtalk_running = true
	var caption := ""
	var wcol := Color(10 / 255.0, 10 / 255.0, 10 / 255.0, 150 / 255.0)
	var pc := 0
	var after := 0
	while pc < code.size():
		if result != "":
			# 战斗已经分出胜负 (最后一个敌人倒下就结束了), 但脚本里「检查敌人都倒下 → 设旗标」那几行还没跑到
			# (例 北狄比试 战场 44/46/255 赢了设 5901–5903; 不补跑就永远算输)。
			# 胜利后只再跑流程 / 旗标类指令 (最多 200 步), 其余 (对白、演出) 跳过
			if result != "win" or after > 200:
				break
			after += 1
			var op0: String = code[pc][1]
			if not (op0 in ["goto", "set_flag", "clear_flag", "set_battle_flag", "clear_battle_flag", "end_script", "end"]
					or op0.begins_with("if_") or op0 == "run_battle_turns"):
				pc += 1
				continue
		var ins: Array = code[pc]
		pc += 1
		var op: String = ins[1]
		var a := ins.slice(2, ins.size() - 1)
		var jumps: Array = ins[-1] if ins.size() > 2 and ins[-1] is Array else []
		if OS.get_cmdline_user_args().has("--trace-events"):
			print("FT @%d %s %s" % [int(ins[0]), op, str(a)])
		match op:
			"set_battle_music":
				music = int(a[0])
			"play_battle_music":
				_play_music(music if music else 81)
			"set_battle_flag_9253d0":
				no_escape = true
			"switch_battlefield":   # 0x9a: 换到另一个战场, 从它的 FIGTALK 重新开始 (地图端接着开新战斗)
				_finish("switch:%d" % int(a[0]))
			"counter_text":   # 0x7df (0x45c265): 只换文本 — 战斗收尾时 (field.start_battle) 用; 跨战斗保留, 不存档
				Battle.countdown_text = [str(a[0]), str(a[1])]
			"window_type":   # 0x0e (0x45b8d1): 字距 [0x4e4814] (与事件脚本 text_char_spacing 同一个全局值)
				Dialog.char_spacing = int(a[0])
			"window_style2":   # 0x0f (0x45b8e0): 行距 [0x4e4816]
				Dialog.line_spacing = int(a[0])
			"set_battle_bit_92520e_80":   # 0x7e0: [0x92520e] |= 0x80 —— 这场战斗「DOMO令牌」(3905) 不能用 (使用检查 0x434470)
				domo_off = true
			"set_battle_param_4e38a0":   # 0x7e4 (0x4515ce): [0x4e38a0] = v —— 下方我方状态栏是否显示 (战斗界面 0x45108a: 1 才画)
				hud_panel = int(a[0]) == 1
			"set_battle_bit_92520f_1":
				allow_lose = true
			"set_unit_status":
				var u := _unit(int(a[0]))
				if u and int(a[1]) & 0x10:
					u.absent = true
					if u.actor:
						u.actor.visible = false
			"set_initiative":
				_initiative(int(a[0]))
			"start_battle":
				# 0x17 (0x45b957 / 0x45c705, 逆向确认): 锁住战斗; 先手类型 [0x925a00] 为 2 (敌方先发制人) 用第二个参数, 否则第一个,
				# 然后清掉先手类型; 把这个 ATK 演出排进队列。之后每帧等「ATK 执行过镜头释放 (op 0x1f, [0x92520f] & 4)
				# 且镜头到位」, 满足后清释放位、**解锁**, 才往下走
				locked = true
				var intro_id := int(a[1]) if _first_type == 2 else int(a[0])
				_first_type = 0
				_intro(intro_id)
				while not (_cam_released and cam.arrived()):
					await get_tree().process_frame
				_cam_released = false
				locked = false
			"run_battle_turns":
				var n := int(a[0])
				# 0x16 (0x45c73e): 记下回合数 [0x925258] = n, 之后每帧检查「没有行动在进行 ([0x9253bc]=0) 且回合数用完」才往下;
				# 不碰锁定标志 (数据里 338 处之前都已解锁或刚开战)
				if n < 0:
					break
				var goal := actions_done + n
				while (actions_done < goal or acting) and result == "":
					await get_tree().process_frame
			"lock_battle":   # 0x18 (0x45b948): [0x9253c0] = 1 —— 只置标志: 不派发新行动 (0x441683)、不走结束流程 (0x442944)
				locked = true
			"unlock_battle":
				locked = false
				_check_end()
			"speaker_name":
				caption = str(a[1])
			"window_color":
				wcol = Color(a[1] / 255.0, a[2] / 255.0, a[3] / 255.0, a[0] / 255.0)
			"text":
				var key := 1000 + int(a[0])
				dialog.show_text(key, a.slice(1, 10), str(a[10]), wcol, caption)
				caption = ""
			"wait_text":
				var k2 := 1000 + int(a[0])
				while dialog.is_open(k2):
					await get_tree().process_frame
			"wait":
				await get_tree().create_timer(int(a[0]) * 0.01).timeout
			"set_flag":
				State.set_flag(int(a[0]), true)
			"clear_flag":
				State.set_flag(int(a[0]), false)
			"if_not_flag_goto":
				if not State.test_flag(int(a[0])) and jumps.size():
					pc = at.get(int(jumps[0]), pc)
			"goto":
				if jumps.size():
					pc = at.get(int(jumps[0]), pc)
			"set_battle_flag":   # 战斗局部旗标 (与 AI VM 0x3e8 共用)
				battle_vars[int(a[0])] = 1
			"clear_battle_flag":
				battle_vars[int(a[0])] = 0
			"if_battle_flag_goto":
				if int(battle_vars.get(int(a[0]), 0)) == 1 and jumps.size():
					pc = at.get(int(jumps[0]), pc)
			"force_unit_skill":   # 0x51 (0x45c874): 施术者 a0 对唯一目标 a1 施放技能 a3; a2 = 动作状态 (6–10/13 施放技能, 数据里只有 9/10)
				# 不扣消耗、不吟咒、不扣使用次数; 上方显示技能名 2 秒 (0x431d2c), 等演出完, 行动条清零 (0x43203e)
				var fc := _unit(int(a[0]))
				var ft := _unit(int(a[1]))
				var fr := Battle.obj(int(a[3]))
				if fc and fc.actor and fr.size():
					if int(a[2]) == 1:
						push_warning("force_unit_skill a2=1 (普通攻击) 未实现")
					_message(str(fr.get("name", "")))
					await _run_atk(fc, [ft] if ft else [], fr, int(fr.get("atk_id", 0)), false)
					fc.gauge = 0
			"if_unit_down_goto":
				var u2 := _unit(int(a[0]))
				if u2 and (u2.dead or u2.absent) and jumps.size():
					pc = at.get(int(jumps[0]), pc)
			"if_random_goto":
				if randi() % 500 % 100 <= int(a[0]) and jumps.size():
					pc = at.get(int(jumps[0]), pc)
			"set_unit_anim":
				var u3 := _unit(int(a[0]))
				if u3 and u3.actor and u3.actor.has_pose(int(a[1])):
					u3.actor.play(int(a[1]))
			"wait_unit_anim":
				var u4 := _unit(int(a[0]))
				if u4 and u4.actor:
					var fr := int(a[1])
					var t0 := Time.get_ticks_msec()
					while not u4.actor.anim_reached(fr) and Time.get_ticks_msec() - t0 < 8000:
						await get_tree().process_frame
			"add_unit_at":   # 0x7e3 (0x45ce91): 0x444ee4 位置可用才 0x44525b 新增 —— 与招式 0x80 在指定坐标召唤同一条路径
				atk_summon(int(a[0]), null, Vector3(a[1], a[2], a[3]))
			"change_unit_obj":   # 0x7ed (0x45cffd): 0x43b05e 变身 (同招式 0x86, 保留 HP/MP/SP) + 0x403091 写 +0x1968
				var u5 := _unit(int(a[0]))
				if u5:
					transform_unit(u5, int(a[1]))
			# ---- 第一章起用到的指令 (tools/battle_vm.json; C = 汇编确认, P = 推断) ----
			"if_flag_goto":
				if State.test_flag(int(a[0])) and jumps.size():
					pc = at.get(int(jumps[0]), pc)
			"system_message":   # 0x7d7 (0x45c0db): 清掉消息框, 弹单行提示框 0x466f7d(400, 200, 0, 200 = 2 秒, 文本 + %Q); 不等待
				dialog.close_all()
				_talkmsg(str(a[0]), Vector2(400, 200), 2.0)
			"menu_switch":   # 0x11 (0x45c761): 等选项确认, 按所选下标跳转, 然后释放按钮 (0x465625; 提示框到时自己关)
				var choice := 0
				if not _tm.is_empty() and int(_tm.nbtn) > 0:
					choice = await _talkmsg_wait()
					if not _tm.is_empty():
						_tm.nbtn = 0
				else:
					while dialog.windows.size():
						await get_tree().process_frame
					choice = dialog.last_choice
				if jumps.size():   # 跳转表是指令的最后一项 (已经拆到 jumps)
					pc = at.get(int(jumps[clampi(choice, 0, jumps.size() - 1)]), pc)
			"wait_message":   # 0x7d8: 等所有消息框关闭 (对白框和提示框在同一个链表)
				while dialog.windows.size() or not _tm.is_empty():
					await get_tree().process_frame
			"clear_messages":
				dialog.close_all()
				_tm = {}
				_msg.queue_redraw()
			"play_sound":
				Game.play_sound(int(a[0]))
			"if_item_goto":   # 0x65: 持有该物品 ≥ n
				if int(State.items.get(int(a[0]), 0)) >= int(a[1]) and jumps.size():
					pc = at.get(int(jumps[0]), pc)
			"if_resources_ge_goto":   # 0x66: 金钱 / 木材 / 金属 / 煤炭 全部 ≥
				if State.money >= int(a[0]) and State.wood >= int(a[1]) and State.metal >= int(a[2]) and State.coal >= int(a[3]) and jumps.size():
					pc = at.get(int(jumps[0]), pc)
			"add_resources":   # 0x82
				State.money = clampi(State.money + int(a[0]), 0, 9999999)
				State.wood = clampi(State.wood + int(a[1]), 0, 9999)
				State.metal = clampi(State.metal + int(a[2]), 0, 9999)
				State.coal = clampi(State.coal + int(a[3]), 0, 9999)
			"add_battle_reward_item":   # 0x83: 战后获得 (最多 10 种)
				for k in int(a[1]):
					if rewards.items.size() < 10 or rewards.items.has(int(a[0])):
						rewards.items.append(int(a[0]))
			"take_item":   # 0x84
				State.give_item(int(a[0]), -int(a[1]))
			"force_victory":   # 0x96: 敌方全部算倒下; 状态栏隐藏 (0x45cb8a)
				hud_panel = false
				for u in alive(false):
					u.hp = 0
					_check_down(u)
				_check_end()
			"fade_end_battle", "end_battle":   # 0x99 淡出后结算 / 0x7eb 立即结算 (0x4405c1, 按胜利结算)
				if result == "":
					_finish("win")
				break
			"kill_unit":   # 0x7ef: 99999 伤害直接倒下
				var ku := _unit(int(a[0]))
				if ku and not ku.dead:
					ku.hp = 0
					_check_down(ku)
					_check_end()
			"clear_unit_status":   # 0x3d
				var cu := _unit(int(a[0]))
				if cu:
					for b in Formula.STATUS_NAMES:
						if int(a[1]) & int(b):
							cu.clear_status(int(b))
			"if_unit_captured_goto":   # 0x7ee (0x45bfa3): 单位 +0x1a08 ≠ 0 = 已被收化 (0x43c4c9) 或已逃离战场 (0x43d3f0) 就跳
				var cu2 := _unit(int(a[0]))
				if cu2 and (cu2.captured or cu2.fled) and jumps.size():
					pc = at.get(int(jumps[0]), pc)
			"replace_unit":   # 0x32: 单位槽换成新的 ObjDATA 角色 (原位置、新模型)
				var ru := _unit(int(a[0]))
				if ru and int(a[0]) >= 6:
					var rp := ru.pos()
					var rf := ru.actor.facing if ru.actor else 0.0
					if ru.actor:
						ru.actor.queue_free()
					units[int(a[0])] = _enemy_unit(int(a[1]), int(a[0]), rp, rf)
				elif ru:
					ru.rec = obj(int(a[1]))
					ru.name = str(ru.rec.get("name", ru.name))
			"move_unit_to":   # 0x7dc (参数含义 P): 单位, 动作, 速度 (单位/秒), x, y, z
				var mu := _unit(int(a[0]))
				if mu and mu.actor:
					var to := Vector3(float(a[3]), float(a[4]), float(a[5]))
					if mu.actor.has_pose(int(a[1])):
						mu.actor.play(int(a[1]), true)
					mu.actor.face_point(to)
					var dur := mu.actor.gpos.distance_to(to) / maxf(float(a[2]), 1.0)
					mu.moving = true
					var tw := create_tween()
					tw.tween_method(func(v: Vector3): mu.actor.set_game_pos(v, false), mu.actor.gpos, to, dur)
					tw.tween_callback(func():
						mu.moving = false
						mu.home = to
						if mu.actor.has_pose(IDLE_POSE):
							mu.actor.play(IDLE_POSE))
			"wait_unit_move":
				var wu := _unit(int(a[0]))
				while wu and wu.moving:
					await get_tree().process_frame
			"turn_unit":   # 0x7de (0x45c22a): 0x431a65(0, 角度, 0, 0) —— 写目标朝向, 逐帧转过去 (不是立即)
				var tu := _unit(int(a[0]))
				if tu:
					turn_unit(tu, float(a[1]))
			"set_unit_pos":   # 0x7e7
				var pu := _unit(int(a[0]))
				if pu and pu.actor:
					pu.actor.set_game_pos(Vector3(float(a[1]), float(a[2]), float(a[3])), false)
					pu.home = pu.actor.gpos
			"set_battle_byte_925a24":   # 0x7da (0x45c131): 自动结束方式 [0x925a24]; 非 0 时结束流程 0x442950 不触发, 由脚本收尾
				end_mode = int(a[0])
			"set_unit_19f4":   # 0x7e2 (0x45ce6a): 0x434947(开/关, 速度) —— 与招式 0x37 同一个单位淡化
				var fu := _unit(int(a[0]))
				if fu and fu.actor:
					fade_unit(fu, int(a[1]) != 0, int(a[2]))
			"create_overlay_b":
				# 0x3f0 (0x445d76): 下雪粒子 (类 0x4ce040, 500 片, ACT 8001 qq2), 但创建时没摆初始位置、粒子数组是未清零的堆内存
				# (0x4914e1(1) 跳过初始摆放) —— 实际显示取决于残留内存, 静态分析定不下来, 不实现
				pass
			"start_minigame":   # 0x7e5 (0x45cef4): 状态 0x1e 游泳挑战, 不等待 (下一条 0x7e6 等它结束)
				_swim(int(a[0]), int(a[1]))
			"wait_minigame_goto":   # 0x7e6 (0x45cf2f): 状态还是 0x1e 就等; 成功 ([0x9efb54]=1) 清零并跳转
				while mg_state == 0x1e and result == "":
					await get_tree().process_frame
				if swim_ok and jumps.size():
					swim_ok = false
					pc = at.get(int(jumps[0]), pc)
			"reset_minigame":   # 0x7e8 (0x45cf94): 进入状态 0x1f 拼图, 子状态 0 (摆好正确图, 显示 00:00); 不等待
				_puzzle_start()
			"set_minigame_9efb58":   # 0x7ea (0x45cfd1): 子状态 2 = 开始 (哨音、计时、洗牌)
				if not puzzle.is_empty():
					puzzle.sub = 2
			"wait_minigame2_goto":   # 0x7e9 (0x45cfb1): 状态还是 0x1f 就等; [0x9efb54] = 1 才跳转 —— 拼图从不写它, 所以不跳
				while mg_state == 0x1f and result == "":
					await get_tree().process_frame
			"end_script", "end":
				break
	_figtalk_running = false


func _unit(i: int) -> BattleUnit:
	return units[i] if i >= 0 and i < units.size() else null


## 先手 (FIGTALK 0x7d5 → 0x445fce): 1 我方先发制人, 2 敌方先发制人, 其余随机 (≤10 我方先, ≥90 敌方先)
var _first_type := 0          # [0x925a00]: 先手结果 1 我方 / 2 敌方 (0x445fce 先清 0 再写), start_battle 用完清掉
var _cam_released := false    # [0x92520f] & 4


func _initiative(v: int) -> void:
	_first_type = 0
	var r := randi() % 400 % 100
	if v == 1 or (v not in [1, 2] and r <= 10):
		for u in alive(true):
			u.gauge = 900 + randi() % 100
		_first_type = 1
		_message("我方先发制人")
	elif v == 2 or r >= 90:
		_first_type = 2
		for u in alive(false):
			u.gauge = 900 + randi() % 100
		_message("敌方先发制人")


## start_battle a, b: 开场演出 ATK (只动镜头, 不结算)
func _intro(atk_id: int) -> void:
	var caster: BattleUnit = null
	for u in units:
		if u and u.actor and u.party:
			caster = u
			break
	if caster == null:
		return
	_intro_runners += 1
	await _run_atk(caster, alive(false), {}, atk_id, false, false)
	_intro_runners -= 1


func _play_music(track: int) -> void:
	var f: String = str(field.names.music.get(str(track), "")) if field else ""
	if f.ends_with(".mp3"):
		Game.play_music(f, 0.5)


# ---------------- 招式演出的回调 ----------------

## 挂点 m 的 Godot 世界坐标 (找不到返回 null)
func marker_world(u: BattleUnit, m: int) -> Variant:
	var g: Variant = marker_pos(u, m)
	return g * 0.01 if g != null else null


func marker_pos(u: BattleUnit, m: int) -> Variant:
	var a := u.actor
	if a == null:
		return null
	for sk in a.find_children("*", "Skeleton3D", true, false):
		var s := sk as Skeleton3D
		if not s.is_visible_in_tree():
			continue
		for bi in s.get_bone_count():
			if s.get_bone_name(bi).begins_with("marker%d_" % m):
				return (s.global_transform * s.get_bone_global_pose(bi).origin) / 0.01
	return null


func cam_op(st: Dictionary, caster: BattleUnit, ts: Array) -> void:
	var a: Array = st.args
	match str(st.op):
		# 0x29 / 0x2a (0x44a74e / 0x4476d6): 注视点一次性设为「执行者 / 第一个目标的位置 + 偏移」, 并记下对象和偏移;
		# 每帧持续跟随要 0x2b 打开 [0x9253c4] (0x44c195), 但 0x2b 在全部招式数据里一次都没用到 —— 原版战斗镜头从不持续跟随
		# (以前这里实现成一直跟着走, 是推测)。0x2a 在车芸本体模式下目标是云狐时改对准车芸本体 (0x439bf9 / 0x445c0e)
		"follow_caster":
			cam.set_target(caster.pos() + Vector3(a[0], a[1], a[2]))
		"follow_target":
			if ts.size():
				var t: BattleUnit = ts[0]
				var p: Vector3 = t.pos()
				if st.get("fig", false) and t.figure:
					p = t.figure.gpos
				cam.set_target(p + Vector3(a[0], a[1], a[2]))
		"pos":
			cam.set_target(Vector3(a[0], a[1], a[2]))
		"look":
			cam.set_angles(float(a[0]), float(a[1]), float(a[2]), int(a[3]) if a.size() > 3 else 0)
		"zoom":
			cam.set_distance(float(a[0]))
		"mode_a":
			cam.set_mode(0, int(a[0]))
		"mode_b":
			cam.set_mode(1, int(a[0]))
		"mode_c":
			cam.set_mode(2, int(a[0]))
		"mode_ab":
			cam.set_mode(0, int(a[0]))
			cam.set_mode(1, int(a[0]))
		"speed_a":
			cam.set_speed(0, float(a[0]))
		"speed_b":
			cam.set_speed(1, float(a[0]))
		"speed_c":
			cam.set_speed(2, float(a[0]))
		"reset_follow":
			cam.follow = null
		"release":
			cam.follow = null
			_cam_released = true   # ATK 0x1f camera_release: [0x92520f] |= 4 (唯一写入点), FIGTALK start_battle 等它
		"restore":
			# restore_camera (0x3e): 恢复这个招式开始前保存的镜头 (0x907990 → 0x908228)
			_restore_cam()


## 镜头指令等到位 (camera_instant_off 时, 原版每条 look / zoom / pos 都等镜头移到位才往下执行); 最多 4 秒
func cam_wait() -> void:
	var t0 := Time.get_ticks_msec()
	while not cam.arrived() and Time.get_ticks_msec() - t0 < 4000:
		await get_tree().process_frame


## 战场场景色 (ATK 0x3a → 0x44b3cc; 每战斗帧 0x478e10, 逆向确认):
##   指令设 速度 / 起始色 C / 目标色 T; 每帧 d = T − C (RGB 向量), |d| > 速度 → C += 截断(单位化 d × 速度) (按字节),
##   否则 C = T, 且 T 任一分量为 255 时速度清 0 (停止渐变); 颜色 = 0xFFRRGGBB, 全白 (= −1) 时走普通路径
##   效果只在画战场 WLD 时 (0x44240c → 0x4147ea → 0x419871): 每个顶点的颜色直接换成这个常量色 (不是相乘), 再和贴图组合;
##   角色和特效不受影响。战斗结束恢复。以前用全屏乘法遮罩近似 (连角色、特效一起染色), 已改
var _scene_mats: Array = []      # [材质, 原颜色, 原「顶点色当颜色」]
var _scol := [255, 255, 255]     # 当前 C
var _scol_to := [255, 255, 255]  # 目标 T
var _scol_speed := 0.0
var _scol_acc := 0.0


func tint_to(st: Dictionary) -> void:
	_scol_speed = float(st.get("speed", 0))
	_scol = (st.get("from", [255, 255, 255]) as Array).duplicate()
	_scol_to = (st.get("to", [255, 255, 255]) as Array).duplicate()
	_apply_scol()


func _scol_tick(delta: float) -> void:
	_scol_acc += delta
	while _scol_acc >= TICK:
		_scol_acc -= TICK
		if _scol_speed == 0.0:
			continue
		var d := Vector3(float(_scol_to[0]) - _scol[0], float(_scol_to[1]) - _scol[1], float(_scol_to[2]) - _scol[2])
		if d.length() > _scol_speed:
			var step := d.normalized() * _scol_speed
			_scol = [(int(_scol[0]) + int(step.x)) & 0xFF, (int(_scol[1]) + int(step.y)) & 0xFF, (int(_scol[2]) + int(step.z)) & 0xFF]
		else:
			_scol = (_scol_to as Array).duplicate()
			if 255 in _scol_to:
				_scol_speed = 0.0
		_apply_scol()


func _apply_scol() -> void:
	var white: bool = int(_scol[0]) == 255 and int(_scol[1]) == 255 and int(_scol[2]) == 255
	var c := Color8(int(_scol[0]), int(_scol[1]), int(_scol[2]))
	for e in _scene_mats:
		var sm: StandardMaterial3D = e[0]
		if white:
			sm.albedo_color = e[1]
			sm.vertex_color_use_as_albedo = e[2]
		else:
			sm.albedo_color = Color(c.r, c.g, c.b, (e[1] as Color).a)
			sm.vertex_color_use_as_albedo = false


# ---------------- 界面 ----------------

func _build_ui() -> void:
	dialog = Dialog.new()
	dialog.field = self
	add_child(dialog)
	_ui = CanvasLayer.new()
	_ui.layer = 7
	add_child(_ui)
	hud = BattleHud.new()
	hud.bt = self
	add_child(hud)
	hud.slide_in()
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 8.0 / 255.0)
	_dim.size = Vector2(800, 600)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_dim)
	_msg = Control.new()
	_msg.size = Vector2(800, 600)
	_msg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_msg.draw.connect(func():
		Dialog.draw_top_tip(_msg, _msg_text, 1.0, Vector2(400, _msg_y))
		if not _tm.is_empty():
			Dialog.draw_top_tip(_msg, _tm.text, 1.0, _tm.center, int(_tm.sel) if int(_tm.nbtn) > 0 else -1))
	_ui.add_child(_msg)


var _msg_y := 80.0


## 上方提示 0x466f7d(400, y, _, 200, 文本, 2); y 一般是 80 (双重的「请选择第一式」「条件不足」在 40)
func _message(t: String, y := 80.0) -> void:
	if OS.get_cmdline_user_args().has("--trace-events"):
		print("MSG t=%.1f f=%d %s" % [Time.get_ticks_msec() / 1000.0, Engine.get_frames_drawn(), t])
	# 原版: 新提示直接替换旧的 (静态缓冲 0x9f2e94), 2 秒后关闭
	_msg_y = y
	_msg_text = t
	_msg_id += 1
	var my := _msg_id
	_msg.queue_redraw()
	get_tree().create_timer(2.0).timeout.connect(func():
		if my == _msg_id:
			_msg_text = ""
			_msg.queue_redraw())


## 选目标: side 0 任意 / 1 我方 / 2 敌方; scope 0 单体 (游标) / 1 全体 / 2 自己
func _choose_target(u: BattleUnit, side: int, scope: int) -> Variant:
	_end_turn_cam()   # 0x44e6a7: 先回远景, 不然特写里看不到怪
	if scope == 2:
		return u
	var pool: Array
	match side:
		1:
			pool = units.filter(func(x): return x and x.party and x.actor and not x.absent and not x.summon)   # 不能对护驾用道具 / 技能
		2:
			pool = alive(false)
		_:
			pool = units.filter(func(x): return x and x.actor and not x.absent and not x.dead)
	if pool.is_empty():
		_message("没有可以作用的目标!!")
		_turn_cam_start(u)
		return null
	if scope == 1:
		return pool
	if side == 1 and pool.has(u):
		pool.erase(u)
		pool.push_front(u)
	if pool.size() == 1:   # 0x44e8df: 只有一个目标时直接确定
		return pool[0]
	var t: Variant = await hud.pick(pool)
	if t == null:
		_turn_cam_start(u)
	return t


func _unhandled_input(e: InputEvent) -> void:
	if _puzzle_input(e):
		get_viewport().set_input_as_handled()
		return
	if _talkmsg_input(e):
		get_viewport().set_input_as_handled()
		return
	if e.is_action_pressed("ui_accept") or (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT):
		if dialog.advance():
			get_viewport().set_input_as_handled()


# ---------------- 结束 ----------------

## 战斗帧率: 开始 0x43fc94 → 0x4675fb(27), 结束 0x440907 → 0x4675fb(35)
static func set_anim_rate(battle: bool) -> void:
	var t := 1.0 / (27.0 if battle else 35.0)
	FieldActor.TICK = t
	Fx.TICK = t
	AtkRunner.TICK = t


func _exit_tree() -> void:
	set_anim_rate(false)


func _finish(r: String) -> void:
	if result != "":
		return
	result = r
	rain_stop()
	print("BATTLE_END %s t=%.1f" % [r, Time.get_ticks_msec() / 1000.0])
	locked = true
	if not r.begins_with("switch:"):
		await get_tree().create_timer(1.0).timeout
	if r == "win":
		_play_music(8)
		# 胜利姿势 (0x443142): 每个存活的我方单位 (含车芸本体) 播动作 0x23 (35, 不循环, 停在末帧), 结算画面期间一直保持
		for u in units:
			if u and u.party and not u.dead and not u.summon:
				face(u, 5)
				for a in [u.actor, u.figure]:
					if a and a.has_pose(VICTORY_POSE):
						a.play(VICTORY_POSE)
		_victory_cam()
		await _victory()
	elif r == "lose" and not allow_lose:
		await get_tree().create_timer(2.0).timeout
	# 写回我方状态; 倒下的队员复活为 1 HP (0x4405c1)
	_guards_end()
	for u in units:
		if u and u.party and not u.summon:
			var m := State.member(u.member)
			m.hp = maxi(u.hp, 1)
			m.mp = u.mp
			m.sp = u.sp
			m.juji = u.juji
	# 换战场可能在 _ready 里的开场脚本同步走到这里 (滏口陉 34/37/38/39, 旗标未置位时第一条就换),
	# 那时 field.start_battle 还卡在 add_child, 没有 await finished, 信号丢了就永远等下去
	await get_tree().process_frame
	finished.emit(r)


## 胜利镜头 (0x442d22–0x4430f7, 旗标 8000 置位时不切): 随机挑一个在场存活的队员 (云狐代表车芸) 转向 180°;
## rand(37)%3 ≠ 0 (2/3 机率) → 该队员特写: 注视 (位置 + 40 高), 俯仰 10°、偏航 200°、距离 550;
## 否则队里有桓远之 (旗标 3) → 远景 B: 注视 (-45,230,-270) 俯仰 20° 偏航 150° 距离 1000, 没有 → 远景 A: (-220,230,-410) 20°/220° 距离 850;
## 远景再按 rand(25)%3 选变体 (B: 高 430 / (155,-70) / (-245,-470); A: 高 430 / (-20,-210) / (-420,-610))。瞬切 (模式 1)
func _victory_cam() -> void:
	if State.test_flag(8000):
		return
	var cands: Array = units.filter(func(x): return x and x.party and not x.dead and not x.absent and x.actor)
	if cands.is_empty():
		return
	var u: BattleUnit = cands[randi() % cands.size()]
	u.actor.set_facing(180.0)
	var kind := 0 if randi() % 37 % 3 != 0 else (2 if State.test_flag(3) else 1)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--victory-cam="):   # 调试 / 录像: 固定胜利镜头类型 0 特写 / 1 / 2 远景
			kind = int(a.substr(14))
	var v := randi() % 25 % 3
	var tgt: Vector3
	var ang: Vector2
	var dist: float
	match kind:
		0:
			tgt = u.actor.gpos + Vector3(0, 40, 0)
			ang = Vector2(10, 200)
			dist = 550.0
		1:
			tgt = [Vector3(-220, 430, -410), Vector3(-20, 230, -210), Vector3(-420, 230, -610)][v]
			ang = Vector2(20, 220)
			dist = 850.0
		_:
			tgt = [Vector3(-45, 430, -270), Vector3(155, 230, -70), Vector3(-245, 230, -470)][v]
			ang = Vector2(20, 150)
			dist = 1000.0
	cam.follow = null
	for ch in 3:
		cam.set_mode(ch, 1)
	cam.set_target(tgt)
	cam.set_angles(ang.x, ang.y, 0)
	cam.set_distance(dist)


## 胜利结算 (0x455dc1): 每个在场存活的队员都拿全额经验; 金钱 / 资源 / 掉落入背包; 升级 HP/MP/SP 全满
func _victory() -> void:
	State.add_res("money", rewards.money)
	State.add_res("metal", rewards.res[0])
	State.add_res("wood", rewards.res[1])
	State.add_res("coal", rewards.res[2])
	var lines: Array = ["获得金钱 %d" % rewards.money]
	var res_names := ["金属", "木材", "煤炭"]
	for k in 3:
		if int(rewards.res[k]):
			lines.append("获得%s %d" % [res_names[k], int(rewards.res[k])])
	for it in rewards.items:
		State.give_item(it, 1)
		lines.append("得到【%s】" % obj(it).get("name", it))
	var cards: Array = []
	var levelups: Array = []
	for u in units:
		if u and u.party and not u.absent and u.actor and not u.summon:
			var ups: Array = []
			var gain: int = 0 if u.dead else rewards.exp
			# 法宝修练 (0x455dc1): 装备着可修练法宝的队员先分出 总经验/10; 两件都可修练时各得一半, 队员只少一半
			if gain > 0:
				var share := gain / 10
				var fbs: Array = _artifacts(u).filter(func(x): return x > 0 and State.artifact_refinable(x))
				if fbs.size() == 2:
					for f in fbs:
						State.artifact_exp[f] = int(State.artifact_exp.get(f, 0)) + share / 2
					gain -= share / 2
				elif fbs.size() == 1:
					State.artifact_exp[fbs[0]] = int(State.artifact_exp.get(fbs[0], 0)) + share
					gain -= share
			var m := State.member(u.member)
			var old := m.duplicate()
			var old_skills: Array = (State.skills.get(u.member, []) as Array).duplicate()
			if gain > 0:
				ups = State.add_exp(u.member, gain)
			if ups.size():
				u.level = int(m.lv)
				u.hp = int(m.hp_max)
				u.hp_max = int(m.hp_max)
				u.mp = int(m.mp_max)
				u.mp_max = int(m.mp_max)
				u.sp = int(m.sp_max)
				u.sp_max = int(m.sp_max)
				var learned: Array = []
				for sk in State.skills.get(u.member, []):
					if not old_skills.has(sk):
						learned.append(str(obj(int(sk)).get("name", sk)))
				levelups.append({"member": u.member, "name": u.name, "lv": int(m.lv), "old": old, "new": m.duplicate(),
					"learned": learned})
			cards.append({"member": u.member, "name": u.name, "lv": int(m.lv), "gained": gain,
				"next": maxi(State.exp_threshold(int(m.lv)) - int(m.exp), 0), "up": ups.size() > 0})
	await hud.results(cards, lines, levelups)
