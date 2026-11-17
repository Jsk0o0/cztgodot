class_name MenuTianshu
extends RefCounted
## 主菜单「天书」(旗标 9; 初始化 0x496105, 输入 0x4964f6, 绘制 0x496e7c; 逆向笔记 re/menu_tianshu.md)
##   独立的 3D 城镇画面: 地图 14997「测试_天书新世界」, 相机注视 (5800,1230,6000) 俯仰 21° 偏航 347° 距离 8250
##   首次打开: 茅草屋 (5577,1000,6404) + 机关工房 (4861,1000,6209), 居民天书书吏 2040 (人物在 (7000,1000,6500)); 旗标 120
##   工具栏 0x4aeacc: 顶栏 0141/1 (0,5), 底栏 0141/2 (0,562); 建造/居民/屋舍 0147 第 0/2/4 帧 (焦点 +1) 在 (560/610/660, 6);
##     离开 0171 (740,5); 资源图标 0146 第 4/0/1/2/3 帧 (90/170/240/310/380, 15), 数字 12px 褐色 (110/190/260/330/400, 17) 画两次;
##     人口 0147/6 (445,6) + 「居民/容量」(475,17); 底栏提示 16px 调色板 14 (50,570)
##   分页 (状态 1): 底图 0141/0 全屏; 清单 0142/0 (560,67) + 滚动条 0142/3 (750,62), 标题 (592,82) 调色板 19, 行高 25,
##     高亮 (577, 77+25k, 160, 30); 左侧 0142/1 (7,67) + 0142/2 (7,464)
##   建造放置 (子状态 1/2, 0x49b902; 逆向笔记 re/menu_tianshu_prod.md §7): 20×17 斜格, 格边 212, 格 (r,c) 中心
##     (2022+212(r+c), 1000, 6179−212(r−c)); 房舍位置 (2632+212(r+c)+dx, 6550−212(r−c)+dz); 放置中悬空 y=2000;
##     可建格画黄色、占地格蓝 (可放) / 红 (不可放); 确认框 0144/1 (310,250)「屋舍建造确定?」, 扣 1 级费用, 音效 0x215
##   屋舍详情按钮 (307+30k, 77): 工房「生产」→ TianshuProd (状态 2–6), 「拆除」(不退资源, 最后一幢住房不能拆)
##   仙术道场「修练 / 法术」→ TianshuDojo (状态 8); 房舍升级、转生台没做

const TB := "ui/all_sys/0141_天书_主介面底图/%03d.png"
const BUILD := "ui/all_sys/0142_天书_建筑介面/%03d.png"
const RES := "ui/all_sys/0143_天书_居民介面/%03d.png"
const COMMON := "ui/all_sys/0144_天书_共用介面/%03d.png"
const HOUSE_ICON := "ui/all_sys/0148_天书_Icon_屋舍/%03d.png"
const OKBTN := "ui/all_sys/0245_000_买卖介面/%03d.png"
const ICON := "ui/all_sys/0146_天书_Icon_共用/%03d.png"
const MENU := "ui/all_sys/0147_天书_Icon_Menu/%03d.png"
const LEAVE := "ui/all_sys/0171_000_离开叉叉/%03d.png"
const PAL14 := Color8(89, 63, 32)
const PAL15 := Color8(117, 76, 36)
const PAL19 := Color8(166, 124, 82)
const PAL24 := Color8(237, 192, 95)
const PAL20 := Color8(192, 80, 88)
const PAL16 := Color8(229, 69, 16)
const BTN_X := [560, 610, 660, 740]
const BTN_NAMES := ["建造", "居民", "屋舍", "离开"]
const RES_X := [90, 170, 240, 310, 380]
const RES_FRAME := [4, 0, 1, 2, 3]
const RES_NAMES := ["金钱", "金属", "木材", "煤炭", "木甲技术"]
## 建筑类型 t → [名称, ObjDATA ID, 位置数, 上限, 解锁旗标 (0 = 一直可建)] (0x4e6808 / 0x49ad32 / 0x4a32d1 / 0x497f43)
const TYPES := {
	1: ["茅草屋", 9501, 3, 22, 0], 2: ["木造屋", 9502, 6, 22, 0x79], 3: ["砖瓦屋", 9503, 10, 22, 0x7a],
	4: ["武器工房", 9504, 5, 1, 0x7b], 5: ["铠装工房", 9507, 5, 1, 0x7c], 6: ["炼丹房", 9510, 5, 1, 0x7d],
	7: ["法宝工房", 9513, 5, 1, 0x7e], 8: ["机关工房", 9516, 5, 1, 0], 9: ["鬼神阵", 9519, 1, 2, 0x7f],
	10: ["仙术道场", 9524, 1, 1, 0x80], 11: ["转生台", 9526, 0, 1, 0x81],
}
const STEMS := "甲乙丙丁戊己庚辛壬癸"
## 特殊居民的人物位置 (0x498197; 建立时 z −= 50, 0x49aeaf)
const SPECIAL := {1052: Vector3(10500, 800, 4800), 1060: Vector3(8300, 2600, 11500), 2040: Vector3(7000, 1000, 6500), 1001: Vector3(3900, 1000, 6000)}
## 特殊居民每帧来回走动 (0x4a1c43–0x4a1e16): ACT → [动作, 初始朝向, 计数初值 / 重置值, 阈值,
##   计数 < 阈值时的位移和朝向, 否则的位移和朝向]。每帧先计数 −1, 减到 0 就重置, 再按阈值选一组
const SPECIAL_WALK := {
	1052: [12, 0.0, 1500, 500, Vector3(3.8, -0.03, -8.4), 45.0, Vector3(-1.9, 0.015, 4.2), 225.0],
	1060: [51, 315.0, 2200, 1100, Vector3(5.8, 0.5, 3.7), 135.0, Vector3(-5.8, -0.5, -3.7), 315.0],
	2040: [51, 270.0, 1000, 500, Vector3(3, 0, 3), 135.0, Vector3(-3, 0, -3), 315.0],
	1001: [51, 180.0, 2000, 1000, Vector3(0, 0, 3), 180.0, Vector3(0, 0, -3), 0.0],
}
const MAP := 14997
## 屋舍详情按钮: 类型 → [[图标帧 (0148), 高亮帧, 动作]] (0x49f3ed; 动作 1 生产 / 4 拆除)
const HBTN_PROD := [3, 4, 1]
const HBTN_DEL := [0, 1, 4]
const HBTN_CFG := [6, 7, 2]   # 配置 (9023 qq14/15)
const HBTN_TRAIN := [12, 13, 5]   # 仙术道场「修练」(9023 qq23/24, 0x4a022a)
const HBTN_MAGIC := [15, 16, 6]   # 仙术道场「法术」(9023 qq26/27)

var m: MainMenu
var tab := 0          # 打开的分页: 0 无 / 1 建造 / 2 居民 / 3 屋舍
var focus := 0        # 工具栏键盘焦点 1..4 (0 = 主画面)
var sel := 0
var _hint := ""
var _label := ""
var _label_pos := Vector2.ZERO
var _label_col := Color.WHITE
var _vp: SubViewport
var _view: TextureRect
var _world: Node3D
var _cam: OrigCamera
var _offset := Vector3.ZERO
var _models: Array = []   # [节点, 名称函数, 类型/居民]
var _drag_x := -1.0
var mode := ""          # "" 普通 / place 放置 / confirm 建造确认 / prod 生产 / demolish 拆除确认
var hbtn := -1          # 屋舍详情按钮焦点 (−1 = 在清单)
var dlg := 0            # 确认框焦点 0 确定 / 1 取消
var prod: TianshuProd
var res: TianshuRes
var dojo: TianshuDojo
var exiled: Array = []    # 流放名单 (0xea4d9c; 打开 / 离开天书时清空)
var ghost: Dictionary   # 放置中的房舍 {type, row, col, orient, angle}
var _ghost_node: FieldActor
var _cam_saved: Array = []
var _t := 0.0
static var _db: Dictionary = {}
static var _ts: Dictionary = {}
static var _crafts: Dictionary = {}


func _init(menu: MainMenu) -> void:
	m = menu
	if _db.is_empty():
		var p := Game.extracted_dir.path_join("game/records.json")
		if FileAccess.file_exists(p):
			_db = JSON.parse_string(FileAccess.get_file_as_string(p)).get("houses", {})
	if _ts.is_empty():
		var p := Game.extracted_dir.path_join("game/tianshu.json")
		if FileAccess.file_exists(p):
			_ts = JSON.parse_string(FileAccess.get_file_as_string(p))
	if State.ts_houses.is_empty():
		# 0x497fef: 茅草屋占 (7,7) 起, 機關工房占 (6,4) 起
		State.ts_houses = [
			{"type": 1, "pos": [5577, 1000, 6404], "seq": 1, "row": 7, "col": 7, "orient": 0, "angle": 45.0},
			{"type": 8, "pos": [4861, 1000, 6209], "seq": 2, "row": 6, "col": 4, "orient": 0, "angle": 45.0},
		]
		State.ts_residents = [{"id": 2040, "house": 0}]
	if State.ts_grid.size() != 340:
		# 可建格: 按地图 14997 的碰撞地面算出的初值 (已含两幢初始房舍的占格)
		State.ts_grid = []
		for row in _ts.get("grid", {}).get("initial_P", []):
			for v in row:
				State.ts_grid.append(int(v))
		if State.ts_grid.size() != 340:
			State.ts_grid.resize(340)
			State.ts_grid.fill(1)
	State.set_flag(120)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--ts-res="):   # 调试: 加入居民 (--ts-res=ID,ID…), 测试配置 / 驱逐 / 流放
			for id in arg.substr(9).split(","):
				if not State.ts_residents.any(func(r): return int(r.id) == int(id)):
					State.ts_residents.push_front({"id": int(id), "house": 0})
	res = TianshuRes.new(self)
	dojo = TianshuDojo.new(self)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--ts-dojo-open="):   # 调试: 打开天书后直接进道场画面 (train / magic)
			for h in State.ts_houses:
				if int(h.type) == 10:
					tab = 3
					sel = State.ts_houses.find(h)
					mode = "dojo"
					dojo.open(h, arg.ends_with("magic"))
	Game.play_sound(0x205)
	_build_world()


func fullscreen() -> bool:
	return true


func own_bg() -> bool:
	return true


func free_fx() -> void:
	if res:
		res.free_fx()
	if dojo:
		dojo.free_fx()
	if is_instance_valid(_vp):
		_vp.queue_free()
	if is_instance_valid(_view):
		_view.queue_free()


# ---------------- 3D ----------------

func _build_world() -> void:
	var info: Dictionary = m.field.maps.get(str(MAP), {})
	var off: Array = info.get("offset", [0, 0, 0])
	_offset = Vector3(off[0], off[1], off[2])
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.size = Game.view_px()
	m.add_child(_vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color8(226, 222, 196)   # 穹顶放大后顶部露出的部分用绢画底色补上
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	_world = Node3D.new()
	_vp.add_child(_world)
	var stage := Game.load_glb(str(info.get("scene", "")))
	if stage:
		_world.add_child(stage)
		m.field.unshade(stage, false, true)   # 贴图 × 顶点色 (同地图场景)
		# 天空穹顶半径只有 50 米, 而天书相机在 82 米外俯瞰: 以地图中心放大 3 倍把相机包进去
		for n in stage.find_children("*_backdrop", "Node3D", true, false) + stage.find_children("*_fx", "Node3D", true, false):
			(n as Node3D).scale *= 3.0
	var c3 := Camera3D.new()
	_vp.add_child(c3)
	_cam = OrigCamera.new(c3, _offset * 0.01)
	_cam.f = Vector3(5800, 1230, 6000)
	_cam.ft = _cam.f
	_cam.ang = Vector3(21, 347, 0)
	_cam.angt = _cam.ang
	_cam.d = 8250.0
	_cam.dt = _cam.d
	_cam.view_dist = 40000.0
	_cam.apply()
	# 原版左手系: 水平翻转显示; 放在菜单画布下面
	_view = TextureRect.new()
	_view.texture = _vp.get_texture()
	_view.flip_h = true
	_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_view.stretch_mode = TextureRect.STRETCH_SCALE
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(_view)
	m.move_child(_view, 0)
	_place_models()


var _walkers := {}   # 特殊居民 ACT → {pos (已减 50), facing, cnt}; 天书画面期间保留


func _place_models() -> void:
	for e in _models:
		(e[0] as Node).queue_free()
	_models.clear()
	for h in State.ts_houses:
		var t: Array = TYPES[int(h.type)]
		var g := Vector3(h.pos[0], h.pos[1], h.pos[2]) + (_rise_off(int(h.seq)) if _rise.has(int(h.seq)) else Vector3.ZERO)
		var a := _actor(int(t[1]), g, float(h.get("angle", 45.0)))
		if a:
			_models.append([a, h, 0])
	for r in State.ts_residents:
		var id := int(r.id)
		if SPECIAL.has(id):
			var w: Array = SPECIAL_WALK[id]
			if not _walkers.has(id):
				_walkers[id] = {"pos": SPECIAL[id] - Vector3(0, 0, 50), "facing": float(w[1]), "cnt": int(w[2])}
			var a := _actor(id, _walkers[id].pos, float(_walkers[id].facing), int(w[0]))
			if a:
				_models.append([a, null, id])


## 绘制原点 T (房舍 0x4a1a67 / 居民同样调用 0x495177; 拾取 0x41047c 用同一个 T):
##   角度 (截成整数) ∈ {−60, 0, 45, 180, 225}: (XB.maxx + x − 750, y, XB.minz + z)
##   ∈ {90, 135, 270, 315}: (XB.maxz + x − 750, y, XB.minx + z); 其他角度原版不重建矩阵 (不会出现)
static func draw_origin(g: Vector3, bb: Array, ang: float) -> Vector3:
	var r := int(ang)
	if r in [90, 135, 270, 315]:
		return Vector3(float(bb[5]) + g.x - 750.0, g.y, float(bb[0]) + g.z)
	return Vector3(float(bb[3]) + g.x - 750.0, g.y, float(bb[2]) + g.z)


## g = 存档里的位置 (房舍 +4..+0xc / 居民当前位置); 模型画在 T, 朝向 = 角度 (ACT 的 PD / CS 由 FieldActor 自己加)
func _actor(act: int, g: Vector3, facing: float, pose := 0) -> FieldActor:
	if not FileAccess.file_exists(Game.extracted_dir.path_join("game/actors/act_%d.json" % act)):
		return null
	var a := FieldActor.new()
	_world.add_child(a)
	a.setup(m.field, act, act)
	if pose != 0:
		a.play(pose, true)
	a.set_meta("src", g)
	_put(a, g, facing)
	return a


func _put(a: FieldActor, g: Vector3, facing: float) -> void:
	a.set_meta("src", g)   # 原版升起 / 走动改的就是存档坐标本身, 标签锚点跟着动
	a.set_facing(facing)
	a.position = (draw_origin(g, a.xb(), facing) + _offset) * 0.01


var _walk_acc := 0.0
var _rise := {}   # 房舍序号 → 升起计数 +0x19c (30 → 0)


## 建成时的烟 (0x49bb3d–0x49bc3e): 粒子系统 2095「蓋房子煙霧」, 位置 = 房舍坐标 + (dx, 100, dz) (dx/dz 取整):
##   角度 ∈ {−60,0,45,180,225}: A = maxz − 300, B = (maxx − 1150)·0.69 → dx = int(0.69A + B), dz = int(B − 0.70667A)
##   角度 ∈ {90,135,270,315}:  C = (maxz − 1150)·0.69, D = maxx − 300 → dx = int(0.69D + C), dz = int(C − 0.70667D)
##   其他角度偏移为 0 (max* = 当前动作 XB)
func _build_smoke(h: Dictionary) -> void:
	var bb: Array = [0, 0, 0, 0, 0, 0]
	for e in _models:
		if e[1] == h and is_instance_valid(e[0]):
			bb = (e[0] as FieldActor).xb()
	if is_instance_valid(_ghost_node):
		bb = _ghost_node.xb()
	var r := int(float(h.get("angle", 45.0)))
	var dx := 0
	var dz := 0
	if r in [-60, 0, 45, 180, 225]:
		var a := float(bb[5]) - 300.0
		var b := (float(bb[3]) - 1150.0) * 0.69
		dx = int(0.69 * a + b)
		dz = int(b - 0.7066666 * a)
	elif r in [90, 135, 270, 315]:
		var c := (float(bb[5]) - 1150.0) * 0.69
		var d := float(bb[3]) - 300.0
		dx = int(0.69 * d + c)
		dz = int(c - 0.7066666 * d)
	var g := Vector3(float(h.pos[0]) + dx, float(h.pos[1]) + 100.0, float(h.pos[2]) + dz)
	Fx.spawn_particles(_world, 2095, (g + _offset) * 0.01, _cam.cam)


## 升起 (0x4a3729, 每次画房舍前调用, 计数不为 0 时): y += 10; 计数为偶数 z −= 10, 奇数 z += 10; 然后计数 −1
## (起点 y −300, 30 帧回到原位, z 抖动净 0)。这里存成相对存档坐标的偏移
var _rise_d := {}


func _rise_off(sq: int) -> Vector3:
	return _rise_d.get(sq, Vector3(0, -300, 0))


func _rise_step(sq: int) -> void:
	var cnt: int = _rise[sq]
	if cnt <= 0:
		_rise.erase(sq)
		_rise_d.erase(sq)
		return
	var o := _rise_off(sq)
	o.y += 10.0
	o.z += -10.0 if cnt % 2 == 0 else 10.0
	cnt -= 1
	if cnt <= 0:
		_rise[sq] = 0   # 这一帧放回原位, 下一帧删掉
		_rise_d[sq] = Vector3.ZERO
	else:
		_rise[sq] = cnt
		_rise_d[sq] = o


## 特殊居民每帧走一步 (地图逻辑帧 35/秒)
func _walk_tick(delta: float) -> void:
	_walk_acc += delta
	while _walk_acc >= OrigCamera.TICK:
		_walk_acc -= OrigCamera.TICK
		for sq in _rise.keys():
			_rise_step(sq)
		for id in _walkers:
			var st: Dictionary = _walkers[id]
			var w: Array = SPECIAL_WALK[id]
			st.cnt = int(st.cnt) - 1
			if int(st.cnt) == 0:
				st.cnt = int(w[2])
			if int(st.cnt) < int(w[3]):
				st.pos += w[4]
				st.facing = float(w[5])
			else:
				st.pos += w[6]
				st.facing = float(w[7])
	for e in _models:
		if e[1] != null and _rise.has(int(e[1].seq)) and is_instance_valid(e[0]):
			var h: Dictionary = e[1]
			_put(e[0], Vector3(h.pos[0], h.pos[1], h.pos[2]) + _rise_off(int(h.seq)), float(h.get("angle", 45.0)))
		if e[1] == null and _walkers.has(int(e[2])) and is_instance_valid(e[0]):
			var st2: Dictionary = _walkers[int(e[2])]
			_put(e[0], st2.pos, float(st2.facing))


func _screen(w: Vector3) -> Vector2:
	var p := _cam.cam.unproject_position(w)
	var s := Vector2(_vp.size)
	return Vector2((1.0 - p.x / s.x) * 800.0, p.y / s.y * 600.0)


func house_name(h: Dictionary) -> String:
	var t := int(h.type)
	var n := 0
	for o in State.ts_houses:
		if int(o.type) == t and int(o.seq) < int(h.seq):
			n += 1
	return str(TYPES[t][0]) + (STEMS[n % 10] if t <= 3 or t == 9 else "")


func house_label(h: Dictionary) -> String:
	var t := int(h.type)
	if t <= 3:
		return house_name(h)
	return "%s: %d/%d " % [house_name(h), _workers(h), int(TYPES[t][2])]


func _workers(h: Dictionary) -> int:
	return h.get("slots", []).size()


func capacity() -> int:
	return capacity_of(State.ts_houses)


## 0x4b8769: 住房 (类型 < 4) 的位置数之和
static func capacity_of(houses: Array) -> int:
	var n := 0
	for h in houses:
		if int(h.type) < 4:
			n += int(TYPES[int(h.type)][2])
	return n


## 鼠标下的房舍 / 人物 (0x496a46 点击、0x49740e 悬停, 逆向确认):
## * 盒子 = 当前动作 XB 原值 (不乘 CS), 用绘制矩阵 (T + 绕 Y 转角度) 变换 8 个角, 投影到屏幕取外包矩形
## * 命中 (0x41047c): 矩形中心严格在 800×600 内, 鼠标 (取整) 在 [取整 min, 取整 max] 内 (两端都含)
## * 深度 = 投影 z' 的 (最小 + 最大) / 2; 最近者初值 1.0; 先遍历房舍, 居民要严格更近才胜出
func _pick(p: Vector2) -> Array:
	var best: Array = []
	var bd := 1.0
	var mx := int(p.x)
	var my := int(p.y)
	for pass_ in 2:
		for e in _models:
			if (e[1] != null) != (pass_ == 0):
				continue
			var a := e[0] as FieldActor
			if not is_instance_valid(a):
				continue
			var r := _proj_box(a)
			if r.is_empty():
				continue
			var c := Vector2((r[0] + r[2]) * 0.5, (r[1] + r[3]) * 0.5)
			if not (c.x > 0 and c.x < 800 and c.y > 0 and c.y < 600):
				continue
			if mx < int(r[0]) or mx > int(r[2]) or my < int(r[1]) or my > int(r[3]):
				continue
			if float(r[4]) < bd:
				bd = float(r[4])
				best = e
	return best


## XB 盒子 8 个角投影 → [min x, min y, max x, max y, 深度] (界面坐标, 已水平翻转)
func _proj_box(a: FieldActor) -> Array:
	var bb: Array = a.xb()
	var c3 := _cam.cam
	var inv := c3.global_transform.affine_inverse()
	var n := c3.near * 100.0
	var f := c3.far * 100.0
	var lo := Vector2(INF, INF)
	var hi := -lo
	var zlo := INF
	var zhi := -INF
	for i in 8:
		var l := Vector3(bb[3] if i & 1 else bb[0], bb[4] if i & 2 else bb[1], bb[5] if i & 4 else bb[2])
		var w := a.global_transform * (l * 0.01)
		var zv := -(inv * w).z * 100.0
		if zv <= 0.0:
			continue
		var sp := _screen(w)
		lo = lo.min(sp)
		hi = hi.max(sp)
		var zp := f / (f - n) * (1.0 - n / zv)   # D3D 透视的 z/w
		zlo = minf(zlo, zp)
		zhi = maxf(zhi, zp)
	if zlo == INF:
		return []
	return [lo.x, lo.y, hi.x, hi.y, (zlo + zhi) * 0.5]


## 悬停标签的位置 (0x41040b): 投影存档位置本身 (不加 T), z/w > 1 时画到屏外
func _label_anchor(e: Array) -> Vector2:
	var g: Vector3 = (e[0] as Node).get_meta("src")
	var w := (g + _offset) * 0.01
	var zv := -(_cam.cam.global_transform.affine_inverse() * w).z * 100.0
	if zv < 0.0 or zv > _cam.cam.far * 100.0:   # z/w > 1 (镜头后方或远裁剪面外)
		return Vector2(850, 0)
	return _screen(w)


# ---------------- 绘制 ----------------

func draw(_tt: float, delta: float) -> void:
	_t += delta
	_walk_tick(delta)
	if is_instance_valid(_vp) and _vp.size != Game.view_px():
		_vp.size = Game.view_px()
	_camera_input(delta)
	var c := m._c
	var mp := m.mouse()
	var page_open := mode in ["prod", "config", "dojo"] or (tab in [1, 2, 3] and mode not in ["place", "confirm"])
	if tab != 2 and mode != "config":
		res.hide_models()
	if mode != "dojo":
		dojo.hide_models()
	_view.visible = not page_open
	if mode in ["place", "confirm"]:
		if mode == "place":
			_place_mouse(mp)
		_draw_grid()
	if page_open:
		m._img(TB % 0, Vector2.ZERO)
	elif _label != "" and mode == "":
		m._text(_label, _label_pos, 16, _label_col, Color(0, 0, 0))
	m._img(TB % 1, Vector2(0, 5))
	m._img(TB % 2, Vector2(0, 562))
	for k in 3:
		var on := focus == k + 1 or tab == k + 1
		m._img(MENU % (2 * k + (1 if on else 0)), Vector2(BTN_X[k], 6))
	m._img(LEAVE % (1 if Rect2(740, 4, 30, 28).has_point(mp) or focus == 4 else 0), Vector2(740, 5))
	var vals := [State.money, State.metal, State.wood, State.coal, State.tech]
	var fmt := ["%-7d", "%-5d", "%-5d", "%-5d", "%-5d"]
	for k in 5:
		m._img(ICON % RES_FRAME[k], Vector2(RES_X[k], 15))
		_bold(fmt[k] % vals[k], Vector2(RES_X[k] + 20, 17), 12, PAL15)
	m._img(MENU % 6, Vector2(445, 6))
	_bold("%d/%-3d" % [State.ts_residents.size(), capacity()], Vector2(475, 17), 12, PAL15)
	match mode:
		"prod":
			prod.draw(delta)
		"place":
			# 0x4973b2 → 0x4a0842: 鼠标在工具栏 / 资源图标上显示名称, 否则显示这行
			_update_hint(m.mouse())
			if _hint == "":
				_hint = " [鼠标右键] 取消  [Shift] 旋转  [M] 小地图"
		"confirm":
			_draw_confirm("屋舍建造确定?")
		"config":
			res.draw_config()
		"dojo":
			dojo.draw()
		"leave":
			_draw_leave()
		_:
			match tab:
				1:
					_draw_build()
				2:
					res.draw_residents()
				3:
					_draw_houses()
					if mode == "demolish":
						_draw_confirm("屋舍拆除确定?")
	_bold(_hint, Vector2(50, 570), 16, PAL14)


func _bold(s: String, p: Vector2, size: int, col: Color) -> void:
	m._text(s, p, size, col)
	m._text(s, p + Vector2(1, 0), size, col)


## 离开时流放名单不为空 (状态 10, 0x4ae968): 默认焦点「取消」
func _draw_leave() -> void:
	m._c.draw_rect(Rect2(0, 0, 800, 600), Color(0, 0, 0, 0x50 / 255.0))
	m._img(COMMON % 1, Vector2(310, 250))
	_bold("流放居民将自动驱逐", Vector2(326, 264), 14, PAL20)
	_bold("确定离开", Vector2(360, 283), 14, PAL20)
	m._img(OKBTN % (8 if dlg == 0 else 9), Vector2(340, 303))
	m._img(OKBTN % (10 if dlg == 1 else 11), Vector2(400, 303))


## 确认框 (0x49d029): 遮罩 + 0144/1 (310,250), 文字 (334,265), 确定 0245/9 (340,303), 取消 0245/11 (400,303); 焦点用 8 / 10 帧
func _draw_confirm(txt: String) -> void:
	m._c.draw_rect(Rect2(0, 0, 800, 600), Color(0, 0, 0, 0x50 / 255.0))
	m._img(COMMON % 1, Vector2(310, 250))
	_bold(txt, Vector2(334, 265), 16, PAL15)
	m._img(OKBTN % (8 if dlg == 0 else 9), Vector2(340, 303))
	m._img(OKBTN % (10 if dlg == 1 else 11), Vector2(400, 303))


# ---------------- 建造放置 ----------------

func _cell(r: int, c: int) -> int:
	if r < 0 or r >= 20 or c < 0 or c >= 17:
		return 0
	return int(State.ts_grid[17 * r + c])


func _footprint(t: int, orient: int) -> Array:
	var keys: Array = _ts.get("footprints", {}).keys()
	if t - 1 >= keys.size():
		return [[0, 0]]
	var f: Dictionary = _ts.footprints[keys[t - 1]].get(str(orient % 4), {})
	return f.get("cells_rc", [[0, 0]])


func _cells_of(h: Dictionary) -> Array:
	var out: Array = []
	if not h.has("row"):
		return out
	for rc in _footprint(int(h.type), int(h.get("orient", 0))):
		out.append([int(h.row) + int(rc[0]), int(h.col) + int(rc[1])])
	return out


func _can_place(h: Dictionary) -> bool:
	for rc in _cells_of(h):
		if _cell(rc[0], rc[1]) != 1:
			return false
	return true


## 0x4a27de: 房舍世界坐标 (dx,dz 由类型和朝向决定)
func _house_pos(h: Dictionary, y: float) -> Vector3:
	var t := int(h.type)
	var odd := (int(float(h.get("angle", 45.0))) / 90) % 2 == 1
	var d := Vector2(17, -78)
	if t == 1:
		d = Vector2(119, -220) if odd else Vector2(-23, -146)
	elif t == 7:
		d = Vector2(159, -26) if odd else Vector2(6, 35)
	elif t >= 8:
		d = Vector2(109, 83)
	var r := int(h.row)
	var c := int(h.col)
	return Vector3(2632 + 212 * (r + c) + d.x, y, 6550 - 212 * (r - c) + d.y)


func _start_place(t: int) -> void:
	if not _check_build(t):
		return
	ghost = {"type": t, "row": 7, "col": 7, "orient": 0, "angle": 45.0}
	_ghost_node = _actor(int(TYPES[t][1]), _house_pos(ghost, 2000), 45.0)
	# 放置相机 (0x49b796): 俯仰 48°、偏航 358°、距离 10610, 注视高度 890
	_cam_saved = [_cam.f, _cam.ang, _cam.d]
	_cam.f = Vector3(5600, 890, 6550)
	_cam.ft = _cam.f
	_cam.ang = Vector3(48, 358, 0)
	_cam.angt = _cam.ang
	_cam.d = 10610.0
	_cam.dt = _cam.d
	_cam.apply()
	mode = "place"
	_last_mp = m.mouse()
	Game.play_sound(0x1fe)


func _end_place() -> void:
	if is_instance_valid(_ghost_node):
		_ghost_node.queue_free()
	_ghost_node = null
	if _cam_saved.size():
		_cam.f = _cam_saved[0]
		_cam.ft = _cam.f
		_cam.ang = _cam_saved[1]
		_cam.angt = _cam.ang
		_cam.d = _cam_saved[2]
		_cam.dt = _cam.d
		_cam.apply()
	_hint = ""


func _move_ghost() -> void:
	if is_instance_valid(_ghost_node):
		_put(_ghost_node, _house_pos(ghost, 2000 if mode == "place" else 1000), float(ghost.angle))


## 0x4a25eb: 鼠标射线和每格的 300×300 盒子 (x∈[2017+212(r+c), +300], z∈[6179−212(r−c)−300, 6179−212(r−c)]), 取行优先第一个命中
var _last_mp := Vector2.INF


func _place_mouse(p: Vector2) -> void:
	# 鼠标模式: 鼠标动了才拾取 (原版键盘操作时 [0xea1c90]=1, 鼠标一动就切回鼠标模式)
	var moved := p != _last_mp
	_last_mp = p
	if not moved or not Rect2(0, 40, 800, 520).has_point(p):
		return
	var s := Vector2(_vp.size)
	var vp := Vector2((1.0 - p.x / 800.0) * s.x, p.y / 600.0 * s.y)
	var o := _cam.cam.project_ray_origin(vp)
	var n := _cam.cam.project_ray_normal(vp)
	var plane_y := (1000.0 + _offset.y) * 0.01
	if absf(n.y) < 1e-4:
		return
	var w := o + n * ((plane_y - o.y) / n.y)
	var g := w / 0.01 - _offset
	for r in 20:
		for c in 17:
			var x0 := 2017.0 + 212 * (r + c)
			var z1 := 6179.0 - 212 * (r - c)
			if g.x >= x0 and g.x <= x0 + 300 and g.z >= z1 - 300 and g.z <= z1:
				if r != int(ghost.row) or c != int(ghost.col):
					ghost.row = r
					ghost.col = c
					_move_ghost()
					Game.play_sound(0x201)
				return


func _diamond(r: int, c: int) -> PackedVector2Array:
	var x0 := 1810.0 + 212 * (r + c)
	var z0 := 6179.0 - 212 * (r - c)
	var pts := PackedVector2Array()
	for q in [Vector2(x0, z0), Vector2(x0 + 212, z0 + 212), Vector2(x0 + 424, z0), Vector2(x0 + 212, z0 - 212)]:
		pts.append(_screen((Vector3(q.x, 1000, q.y) + _offset) * 0.01))
	return pts


static var _plan_on := false   # [0xea2edc] 放置时的小地图, 只有 M 改它, 一直保留到退出游戏


## 0x4a218e / 0x4a226e: 可建格黄色, 占地格蓝 (可放) / 红 (不可放)
## 放置时 M 开关的小地图 (0x4a21cc, [0xea2edc]): (27,50) 起 170×200 的底, 每格 10×10: 可建格橙、已占格深灰, 占地格同色画在上面
func _draw_grid() -> void:
	for r in 20:
		for c in 17:
			if _cell(r, c) == 1:
				m._c.draw_colored_polygon(_diamond(r, c), Color8(250, 250, 10, 50))
	if _plan_on:
		m._c.draw_rect(Rect2(27, 50, 170, 200), Color8(250, 250, 250, 0x50))
		for r in 20:
			for c in 17:
				if _cell(r, c) == 1:
					m._c.draw_rect(Rect2(27 + c * 10, 50 + r * 10, 10, 10), Color8(250, 200, 10, 0x64))
				elif _cell(r, c) == 2:
					m._c.draw_rect(Rect2(27 + c * 10, 50 + r * 10, 10, 10), Color8(50, 50, 50, 0x64))
	var ok := _can_place(ghost)
	var col := Color8(10, 10, 250, 100) if ok else Color8(250, 10, 10, 100)
	for rc in _cells_of(ghost):
		if rc[0] < 20 and rc[1] < 17:
			m._c.draw_colored_polygon(_diamond(rc[0], rc[1]), col)
			if _plan_on:
				m._c.draw_rect(Rect2(27 + int(rc[1]) * 10, 50 + int(rc[0]) * 10, 10, 10), col)


func _check_build(t: int) -> bool:
	var cnt := State.ts_houses.filter(func(h): return int(h.type) == t).size()
	if cnt >= int(TYPES[t][3]):
		m._say("%s 限制%d幢" % [TYPES[t][0], int(TYPES[t][3])])
		Game.play_sound(0x20e)
		return false
	var info := _cost(t)
	if State.money < int(info.get("金钱", 0)) or State.metal < int(info.get("金属", 0)) \
			or State.wood < int(info.get("木材", 0)) or State.coal < int(info.get("煤炭", 0)):
		m._say("建造需求资源不足")
		Game.play_sound(0x20e)
		return false
	return true


## 确定建造 (0x4a2907 扣费 → 0x4a2876 占格)
func _build_confirmed() -> void:
	var t := int(ghost.type)
	if not _check_build(t):
		mode = "place"
		_move_ghost()
		return
	var info := _cost(t)
	State.money -= int(info.get("金钱", 0))
	State.metal -= int(info.get("金属", 0))
	State.wood -= int(info.get("木材", 0))
	State.coal -= int(info.get("煤炭", 0))
	var seq := 1
	while State.ts_houses.any(func(h): return int(h.seq) == seq):
		seq += 1
	var pos := _house_pos(ghost, 1000)
	var h := ghost.duplicate()
	h.seq = seq
	h.pos = [pos.x, pos.y, pos.z]
	_build_smoke(h)
	if OS.get_cmdline_user_args().has("--trace-ui"):
		print("TS_BUILD seq=%d type=%d pos=%s angle=%s row=%d col=%d" % [seq, t, str(h.pos), str(h.angle), int(h.row), int(h.col)])
	_rise[seq] = 30   # 0x49bb25: y −= 300, +0x19c = 30 → 每帧 0x4a3729 升起
	for rc in _cells_of(h):
		State.ts_grid[17 * int(rc[0]) + int(rc[1])] = 2
	State.ts_houses.append(h)
	State.ts_houses.sort_custom(func(a, b): return int(a.seq) < int(b.seq))
	Game.play_sound(0x215)
	mode = ""
	_end_place()
	_place_models()
	res.return_exiles()
	tab = 0
	focus = 0


func _place_key(code: int) -> void:
	var r := int(ghost.row)
	var c := int(ghost.col)
	match code:
		KEY_LEFT:
			c = maxi(c - 1, 0)
		KEY_RIGHT:
			c = mini(c + 1, 13 if r <= 1 else (14 if r <= 3 else 16))
		KEY_UP:
			r = maxi(r - 1, 4 if c > 14 else (2 if c == 14 else 0))
		KEY_DOWN:
			r = mini(r + 1, 19)
		KEY_M:   # 0x49c567
			_plan_on = not _plan_on
			return
		KEY_SHIFT, Pad.Y, Pad.LB, Pad.RB:   # 0x49c3e0: 旋转键 0x80 / 0x81 (左右 Shift) / 手柄 / 滚轮; 以前 R 和 Ctrl 也转 (Ctrl 是取消)
			ghost.orient = (int(ghost.orient) + 1) % 4
			ghost.angle = fmod(float(ghost.angle) + 90.0, 360.0)
			_move_ghost()
			Game.play_sound(0x1fe)
			return
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			_place_ok()
			return
		KEY_ESCAPE, KEY_CTRL:
			mode = ""
			_end_place()
			Game.play_sound(0x202)
			return
		_:
			return
	if r != int(ghost.row) or c != int(ghost.col):
		ghost.row = r
		ghost.col = c
		_move_ghost()
		Game.play_sound(0x201)


func _place_ok() -> void:
	if _can_place(ghost):
		mode = "confirm"
		dlg = 0
		_move_ghost()
		Game.play_sound(0x200)
	else:
		Game.play_sound(0x20e)


# ---------------- 屋舍详情 ----------------

func house_buttons(h: Dictionary) -> Array:
	var t := int(h.type)
	var out: Array = []
	if (t >= 4 and t <= 8) or t == 11:
		out.append(HBTN_PROD)
	if (t >= 4 and t <= 7) or t == 9:   # 鬼神阵: 配置护驾 (位置 0 = 主护驾)
		out.append(HBTN_CFG)
	if t == 10:
		out.append(HBTN_TRAIN)
		out.append(HBTN_MAGIC)
	if t != 9:
		out.append(HBTN_DEL)
	return out


func _sel_house() -> Dictionary:
	var hs := State.ts_houses
	return {} if hs.is_empty() else hs[clampi(sel, 0, hs.size() - 1)]


func _draw_houses() -> void:
	var hs := State.ts_houses
	_list_panel("现有屋舍清单", hs.map(func(h): return house_name(h)))
	if hs.is_empty():
		return
	var h := _sel_house()
	var t := int(h.type)
	_bold(house_name(h), Vector2(40, 100), 20, PAL14)
	if t < 4:
		var live := State.ts_residents.filter(func(r): return int(r.house) == int(h.seq))
		_bold("居民 %d/%d" % [live.size(), int(TYPES[t][2])], Vector2(40, 132), 14, PAL15)
	else:
		_bold("工作人数 %d/%d" % [_workers(h), int(TYPES[t][2])], Vector2(40, 132), 14, PAL15)
	var bs := house_buttons(h)
	var mp := m.mouse()
	var yb: int = UiAct.bounce(67, int(_t * 35.0)) - 67   # 0x4a062e: y0 = 67, 画在 trunc(y + 10)
	for k in bs.size():
		var on := hbtn == k or Rect2(307 + 30 * k, 72, 25, 35).has_point(mp)
		m._img(HOUSE_ICON % int(bs[k][1 if on else 0]), Vector2(307 + 30 * k, 77 + yb if hbtn == k else 77))
		if on and mode == "":
			_hint = {1: "生产", 2: "配置", 4: "拆除", 5: "修练", 6: "法术"}.get(int(bs[k][2]), "")
	if t == 10:
		_draw_dojo_info(h)
	wrap_text(str(_cost(t).get("desc", "")), Vector2(30, 467), 490)


## 仙术道场的屋舍详情 (0x4a022a–0x4a05dd): 「师范妖魔」+ 师范名字, 「学习法术」+ 仙术名 + 当前修练进度 / 需要值
## (仙术取最后一个位置的妖怪; 进度永远是当前修练 0xa763f6)。原版字号 16 / 18 → 14 / 16
func _draw_dojo_info(h: Dictionary) -> void:
	_bold("师范妖魔", Vector2(329, 178), 14, PAL14)
	m._img(ICON % 6, Vector2(309, 177))
	var sp := 0
	for id in h.get("slots", []):
		var nm := str(Battle.obj(int(id)).get("name", id))
		_bold(nm, Vector2(350 - 3 * dojo._bytes(nm), 201), 16, PAL16)
		sp = int(Battle.obj(int(id)).get("special_skill", 0))
	_bold("学习法术", Vector2(329, 244), 14, PAL14)
	m._img(ICON % 6, Vector2(309, 243))
	var so := Battle.obj(sp)
	if sp != 0 and not so.is_empty():
		var nm := str(so.get("name", ""))
		_bold(nm, Vector2(350 - 3 * dojo._bytes(nm), 267), 16, PAL16)
		_bold("%4d/%d" % [int(State.dojo_cur.prog), State.dojo_need(sp)], Vector2(317, 290), 16, PAL15)


func _house_action(k: int) -> void:
	var h := _sel_house()
	var bs := house_buttons(h)
	if k < 0 or k >= bs.size():
		return
	match int(bs[k][2]):
		1:
			prod = TianshuProd.new(self, h)
			mode = "prod"
			Game.play_sound(0x200)
		2:
			mode = "config"
			res.open_config(h)
		4:
			mode = "demolish"
			dlg = 0
			Game.play_sound(0x200)
		5, 6:
			mode = "dojo"
			dojo.open(h, int(bs[k][2]) == 6)


## 0x4a3142: 最后一幢住房不能拆; 拆除不退资源, 占格改回可建, 屋内居民变闲置
func _demolish() -> void:
	var h := _sel_house()
	mode = ""
	var t := int(h.type)
	if t < 4:
		if State.ts_houses.filter(func(o): return int(o.type) < 4).size() <= 1:
			m._say("请留一栋居住屋吧~~")
			Game.play_sound(0x20e)
			return
		# 拆了会住不下: 先选人流放 (0x4b2c69), 选够了才真的拆
		var spare := capacity() - State.ts_residents.size()
		var cap := int(TYPES[t][2])
		if spare < cap:
			hbtn = -1
			res.start_exile(h, cap - spare)
			return
	elif not h.get("slots", []).is_empty():
		m._say("屋内怪物任务解除!")
	remove_house(h)
	res.return_exiles()
	Game.play_sound(0x200)


## 拆掉一幢房舍: 占格改回可建, 屋内居民变闲置 (0x4a2a8e)
func remove_house(h: Dictionary) -> void:
	for rc in _cells_of(h):
		if _cell(rc[0], rc[1]) == 2:
			State.ts_grid[17 * int(rc[0]) + int(rc[1])] = 1
	for r in State.ts_residents:
		if int(r.house) == int(h.seq):
			r.house = 0
	h.slots = []
	State.ts_houses.erase(h)
	sel = clampi(sel, 0, maxi(State.ts_houses.size() - 1, 0))
	hbtn = -1
	_place_models()


## 居民的生产能力 (ObjDATA 0xBBF, 记载页的图鉴数据里有)
func craft_of(id: int) -> Dictionary:
	if _crafts.is_empty():
		var p := Game.extracted_dir.path_join("game/records.json")
		if FileAccess.file_exists(p):
			for b in JSON.parse_string(FileAccess.get_file_as_string(p)).get("bestiary", []):
				_crafts[int(b.id)] = b.get("craft", {})
	return _crafts.get(id, {})


## 0x4979fb: 鼠标所在按钮 / 资源图标的名称; 键盘模式显示焦点按钮
func _update_hint(p: Vector2) -> void:
	_hint = ""
	if focus > 0:
		_hint = BTN_NAMES[focus - 1]
		return
	for k in 4:
		if p.x >= BTN_X[k] and p.x < BTN_X[k] + 25 and p.y >= 5 and p.y < 35:
			_hint = BTN_NAMES[k]
	for k in 5:
		if p.x >= RES_X[k] - 1 and p.x < RES_X[k] + 18 and p.y >= 7 and p.y < 27:
			_hint = RES_NAMES[k]
	if Rect2(447, 7, 23, 25).has_point(p):
		_hint = "人口"


func _camera_input(delta: float) -> void:
	if tab != 0 or mode != "" or _cam == null:
		return
	var d := 0.0
	# 内部键码 0x80 / 0x81 = 左 / 右 Shift (键盘初始化 0x40e685 的扫描码表: DIK 0x2a → 0x80, DIK 0x36 → 0x81; Ctrl 是 0x82 / 0x83, 不转镜头)
	var shift := Input.is_key_pressed(KEY_SHIFT)
	if shift:
		if Input.is_key_pressed(KEY_LEFT):
			d -= 2.0
		if Input.is_key_pressed(KEY_RIGHT):
			d += 2.0
		d *= delta * 35.0
	d -= Pad.turn() * 2.0 * delta * 35.0
	var mp := m.mouse()
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		if _drag_x >= 0 and absf(mp.x - _drag_x) >= 1:
			d += 4.0 * signf(mp.x - _drag_x)
		_drag_x = mp.x
	else:
		_drag_x = -1.0
	# 光标 (0x4964f6 状态 0): 按住 Shift → 旋转 (qq11, 0x4966f1); 右键拖动中 → 旋转 (0x49686f); 否则普通指针 (0x4969ac); 旗标 8053 → 普通指针
	if Game.cursor:
		var rot := not State.test_flag(8053) and (shift or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT))
		Game.cursor.set_state(9001, 11 if rot else 9)
	if d != 0.0:
		# 偏航限制在 300°→360°/0°→129°
		var y := fposmod(_cam.ang.y + d, 360.0)
		if y > 129.0 and y < 300.0:
			y = 129.0 if d > 0 else 300.0
		_cam.ang.y = y
		_cam.angt.y = y
		_cam.apply()
	_update_hint(mp)
	_label = ""
	var e := _pick(mp)
	if not e.is_empty():
		var sp := _label_anchor(e).floor()
		if e[1] != null:
			_label = house_label(e[1])
			_label_col = Color.WHITE
			_label_pos = sp + Vector2(-70, -60)
		else:
			_label = str(Battle.obj(int(e[2])).get("name", ""))
			_label_col = PAL24
			_label_pos = sp + Vector2(-70, -50)


# ---- 清单面板 (建造 / 居民 / 屋舍共用版式) ----

func _list_panel(title: String, rows: Array) -> void:
	m._img(BUILD % 0, Vector2(560, 67))
	m._img(BUILD % 3, Vector2(750, 62))
	_bold(title, Vector2(592, 82), 18, PAL19)
	if rows.size():
		m._c.draw_rect(Rect2(577, 77 + 25 * (sel + 1), 160, 30), Color(1, 1, 1, 0x78 / 255.0))
	for k in mini(rows.size(), 16):
		_bold(str(rows[k]), Vector2(592, 109 + 25 * k), 16, PAL15)
	m._img(BUILD % 1, Vector2(7, 67))
	m._img(BUILD % 2, Vector2(7, 464))


func buildable() -> Array:
	var out: Array = []
	for t in TYPES:
		var f := int(TYPES[t][4])
		if f == 0 or State.test_flag(f):
			out.append(t)
	return out


func _cost(t: int) -> Dictionary:
	return _db.get(str(TYPES[t][1]), {})


func _draw_build() -> void:
	var ts := buildable()
	_list_panel("可建造屋舍清单", ts.map(func(t): return TYPES[t][0]))
	if ts.is_empty():
		return
	var t: int = ts[clampi(sel, 0, ts.size() - 1)]
	var info := _cost(t)
	_bold(str(TYPES[t][0]), Vector2(40, 100), 20, PAL14)
	var cnt := State.ts_houses.filter(func(h): return int(h.type) == t).size()
	_bold("已建 %d / 限制 %d 幢" % [cnt, int(TYPES[t][3])], Vector2(40, 132), 14, PAL15)
	if int(TYPES[t][2]) > 0:
		_bold("可容纳 %d 人" % int(TYPES[t][2]), Vector2(40, 157), 14, PAL15)
	_bold("建造需求资源", Vector2(307, 199), 16, PAL14)
	var have := [State.money, State.metal, State.wood, State.coal]
	var keys := ["金钱", "金属", "木材", "煤炭"]
	for k in 4:
		var need := int(info.get(keys[k], 0))
		m._img(ICON % RES_FRAME[k], Vector2(307, 228 + 25 * k))
		_bold("%s  %d" % [keys[k], need], Vector2(332, 227 + 25 * k), 14, PAL20 if need > int(have[k]) else PAL15)
	wrap_text(str(info.get("desc", "")), Vector2(30, 467), 490)


func wrap_text(s: String, at: Vector2, width: float, max_lines := 99) -> void:
	var line := ""
	var y := at.y
	for ch in s.replace("%N", "\n"):
		if ch == "\n" or (line.length() + 1) * 16 > width:
			if y >= at.y + 25 * max_lines:
				return
			_bold(line, Vector2(at.x, y), 16, PAL15)
			y += 25
			line = "" if ch == "\n" else ch
			continue
		line += ch
	if line != "" and y < at.y + 25 * max_lines:
		_bold(line, Vector2(at.x, y), 16, PAL15)



# ---------------- 输入 ----------------

func _rows() -> int:
	match tab:
		1:
			return buildable().size()
		2:
			return State.ts_residents.size()
		3:
			return State.ts_houses.size()
	return 0


func _open(k: int) -> void:
	if mode == "prod":
		_close_prod(false)
	if mode == "dojo":   # 工具栏离开道场: 子状态不清 (原版 0x4abf3a / 0x4ab8ab)
		mode = ""
		dojo.hide_models()
	if k == 4:
		_leave()
		return
	tab = k
	focus = k
	sel = 0
	hbtn = -1
	if k == 2:
		res.sub = 0
		res.sel = 1
	Game.play_sound(0x1fe)


func _close_prod(snd := true) -> void:
	if prod and prod.qty > 0:
		prod._cancel(0x202)
	prod = null
	mode = ""
	if snd:
		Game.play_sound(0x202)


func _leave() -> void:
	if mode in ["place", "confirm"]:
		mode = ""
		_end_place()
	if exiled.size() and mode != "leave":
		mode = "leave"
		dlg = 1
		Game.play_sound(0x200)
		return
	mode = ""
	exiled.clear()   # 流放的居民永久消失
	Game.play_sound(0x205)
	m._back()


func _confirm_key(code: int) -> void:
	match code:
		KEY_LEFT, KEY_RIGHT:
			dlg = 1 - dlg
			Game.play_sound(0x201)
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			if dlg == 0:
				_confirm_ok()
			else:
				_confirm_cancel()
		KEY_ESCAPE, KEY_CTRL:
			_confirm_cancel()


func _confirm_ok() -> void:
	if mode == "confirm":
		_build_confirmed()
	elif mode == "leave":
		_leave()
	else:
		_demolish()


func _confirm_cancel() -> void:
	if mode == "confirm":
		mode = "place"
		_move_ghost()
	else:
		mode = ""
		tab = 0 if tab == 0 else tab
	Game.play_sound(0x1ff)


func key(code: int) -> bool:
	match mode:
		"prod":
			if not prod.key(code):
				_close_prod(false)
			return true
		"place":
			_place_key(code)
			return true
		"confirm", "demolish", "leave":
			_confirm_key(code)
			return true
		"config":
			if not res.key_config(code):
				mode = ""
			return true
		"dojo":
			return dojo.key(code)
	if tab == 2:
		if not res.key_residents(code):
			if res.sub == 0:
				tab = 0
				focus = 0
		return true
	if tab == 3 and hbtn >= 0:
		var n := house_buttons(_sel_house()).size()
		match code:
			KEY_ESCAPE, KEY_CTRL:
				hbtn = -1
				Game.play_sound(0x1ff)
			KEY_LEFT:
				hbtn = maxi(hbtn - 1, 0)
				Game.play_sound(0x201)
			KEY_RIGHT:
				hbtn = mini(hbtn + 1, n - 1)
				Game.play_sound(0x201)
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				_house_action(hbtn)
		return true
	if tab != 0:
		match code:
			KEY_ESCAPE, KEY_CTRL:
				tab = 0
				Game.play_sound(0x1ff)
			KEY_UP:
				if sel > 0:
					sel -= 1
					Game.play_sound(0x201)
			KEY_DOWN:
				if sel + 1 < _rows():
					sel += 1
					Game.play_sound(0x201)
			KEY_LEFT, KEY_RIGHT:
				var k := clampi(tab + (-1 if code == KEY_LEFT else 1), 1, 3)
				if k != tab:
					_open(k)
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				if tab == 1:
					var ts := buildable()
					if ts.size():
						_start_place(ts[clampi(sel, 0, ts.size() - 1)])
				elif tab == 3 and house_buttons(_sel_house()).size():
					hbtn = 0
					Game.play_sound(0x201)
		return true
	if focus > 0:
		match code:
			KEY_ESCAPE, KEY_CTRL:
				focus = 0
				Game.play_sound(0x1ff)
			KEY_LEFT:
				if not Input.is_key_pressed(KEY_SHIFT):
					focus = maxi(focus - 1, 1)
					Game.play_sound(0x201)
			KEY_RIGHT:
				if not Input.is_key_pressed(KEY_SHIFT):
					focus = mini(focus + 1, 4)
					Game.play_sound(0x201)
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				_open(focus)
		return true
	match code:
		KEY_ESCAPE, KEY_CTRL:
			_leave()   # 流放名单不为空时先确认 (状态 10)
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			focus = 1
			Game.play_sound(0x200)
	return true


## 右键: 道场画面里同取消键 (0x4aa2b6 / 0x4aaf99 取消键组含右键 0x101); 其他地方右键仍是转镜头
func right_click() -> void:
	if mode == "dojo":
		dojo.key(KEY_ESCAPE)


## 滚轮: 道场清单 / 法术画面同 PgUp / PgDn
func wheel(up: bool) -> void:
	if mode == "dojo":
		dojo.key(KEY_PAGEUP if up else KEY_PAGEDOWN)


func mouse(p: Vector2, clicked: bool) -> bool:
	if clicked and p.y > 5 and p.y < 35 and mode not in ["confirm", "demolish", "leave"] and not (tab == 2 and res.sub == 4) \
			and not (mode == "dojo" and dojo.sub in [1, 2]):
		for k in 4:
			if p.x > BTN_X[k] and p.x < BTN_X[k] + 30:
				if mode == "place":
					mode = ""
					_end_place()
				_open(k + 1)
				return true
	match mode:
		"prod":
			prod.mouse(p, clicked)
			return true
		"place":
			if clicked:
				_place_ok()
			return true
		"config":
			res.mouse_config(p, clicked)
			return true
		"dojo":
			dojo.mouse(p, clicked)
			return true
		"confirm", "demolish", "leave":
			if Rect2(340, 300, 44, 26).has_point(p):
				dlg = 0
				if clicked:
					_confirm_ok()
			elif Rect2(400, 300, 44, 26).has_point(p):
				dlg = 1
				if clicked:
					_confirm_cancel()
			return true
	if tab == 2:
		res.mouse_residents(p, clicked)
		return clicked
	if not clicked:
		if tab != 0 and Rect2(577, 102, 160, 25 * _rows()).has_point(p):
			var k := int((p.y - 102) / 25)
			if k != sel:
				sel = k
				hbtn = -1
		return false
	if tab == 0:
		var e := _pick(p)
		if not e.is_empty() and e[1] != null:
			# 点 3D 房舍 → 屋舍分页并选中这幢 (0x49b838)
			_open(3)
			sel = State.ts_houses.find(e[1])
		return true
	if tab == 3:
		var n := house_buttons(_sel_house()).size()
		for k in n:
			if p.x > 307 + 30 * k and p.x < 332 + 30 * k and p.y > 72 and p.y < 107:
				hbtn = k
				_house_action(k)
				return true
	if Rect2(577, 102, 160, 25 * _rows()).has_point(p):
		sel = int((p.y - 102) / 25)
		if tab == 1:
			var ts := buildable()
			_start_place(ts[clampi(sel, 0, ts.size() - 1)])
	return true
