class_name FieldActor
extends Node3D
const HELD_MORPH := preload("res://scripts/held_morph.gd")
## 地图上的角色 (原版角色结构 0xaff1a8 + k*0x674): ACT 模型 + 动作 (QQ) + 路径行走 + 朝向 + 显示 / 透明度
## 模型: extracted/game/actors/act_<ACT>.json (tools/export_actors.py), 动作所在的网格组不同时切换模型节点
## 坐标一律用游戏单位 (地图 MAP 坐标), 由 field 换算到 Godot

## 逻辑帧长: 地图 1/35 秒; 战斗中 1/27 秒 (原版战斗开始 0x43fc94 把帧间隔设成 1000/27 ms, 结束 0x440907 改回 1000/35;
## 主循环 0x46e640 只有到帧才跑逻辑和 ACT 播放, 所以战斗里角色动作 / 特效 / 招式脚本都是 27 帧/秒)。由 Battle 切换
static var TICK := 1.0 / 35.0
const CLIP_TICK := 1.0 / 35.0   # GLB 动画按 35 帧/秒烘焙 (tools/export_actors.py FPS), 播放速度按 TICK 缩放
const NO_TURN_WALK := 0x200800   # 路径步进不转向 (0x46a172), 例: 木甲工房电梯 15014 上下时朝向不变
const DEFAULT_SPEED := 8.0      # 默认移动速度 [0x4e48c4] = 8.0 单位/帧 (35 帧/秒)

var field: Node                 # Field
var id := 0
var act := 0
var meta: Dictionary = {}
var _groups := {}               # 组号 → 模型节点
var _ap: AnimationPlayer
var _skel: Skeleton3D
var _cur_g := -1
var pose := 0
var pose_tick := 0.0            # 当前动作已播放的帧数
var pose_len := 1
var pose_loop := true
var event_id := 0               # 被调查时触发的事件 (set_actor_event / MAPS.DAT)
var ai := 0
var hidden := false
var facing := 0.0               # 原版角度 f: 移动方向 = (sin f, 0, −cos f) (exe 0x47c1d9)
## 角色标志 (+0x1a4): 0x1 隐藏 0x8 不画模型 (地图绘制循环 0x477fda `test flags, 9` 跳过; 迷宫里的隐形阻挡 / 机关触发角色) 0x4 不挡路
var flags := 0:
	set(v):
		flags = v
		_refresh_visible()
## (续) 标志: 0x4 不挡路 0x10 碰到触发 0x400/0x800 调查型 0x1000 不转身 0x2000/0x4000 可对话
var gpos := Vector3.ZERO        # 游戏坐标
var path: Array = []            # 待走的路径点 (游戏坐标)
var speed := DEFAULT_SPEED
var walk_pose := -1             # 行走时播放的动作 (-1 = 保持当前)
var alpha := 1.0
var _alpha_to := 1.0
var _alpha_step := 0.0
var _acc := 0.0
var is_player := false
var expr_act := 0              # 表情 (set_expression 0x78): all_sys ACT 10001+ 与动作 QQ; 0 = 原脸
var expr_qq := 0
var _expr_frames: Array = []
var _expr_loop := true
var _expr_i := 0
var _expr_left := 0
var _expr_mats: Array = []      # 当前组里脸部那一格的材质 [StandardMaterial3D, 原贴图]
static var _faces: Dictionary = {}
static var _face_tex: Dictionary = {}
## ACT 指令 ER 的挂点粒子 (地图角色 0x46e05c, 绘制 0x46b10d 里调用): 动作脚本执行到 ER (动作开始、每次 VO 循环) 时把粒子号写进
## 播放器 +0xc4[slot] (这里 _er_pending), 绘制时在挂点 slot+1 上生成 (0x493634, 停止帧写 +0xf0) 并把 +0xc4[slot] 清 0;
## 之后每帧: 当前模型帧 (AP 值, +0x29e) 等于停止帧 → 停止发射且停止帧清 0 (0x4914eb, 帧 0 不比), 发射点跟着挂点移动。
## set_pose / set_act / hide_actor / set_actor_flag3 先停掉并丢弃全部句柄 (0x46e16a)。例: 「秘密寶箱」粒子 2038 = 树下的发光点 (ACT 16002 动作 5)
var _er_pending := false
var _er_ems := {}                # slot → [FxEmitter, 停止帧]
var held: Array = []            # 手持物 [物品, qq, 挂点] (set_weapon_model 0x8a); 空 = 没拿东西
var _held_node: Node3D


func setup(f: Node, actor_id: int, act_id: int) -> void:
	field = f
	id = actor_id
	name = "actor_%d" % actor_id
	set_act(act_id)


func set_act(act_id: int) -> void:
	if act_id == act and not meta.is_empty():
		return
	act = act_id
	clear_er()   # set_act (0x14 → 0x46e16a)
	for n in _groups.values():
		n.queue_free()
	_groups.clear()
	_cur_g = -1
	meta = {}
	var p := Game.extracted_dir.path_join("game/actors/act_%d.json" % act_id)
	if Mods.has_model(act_id):   # 创意工坊自定义模型 (mod 的 models.json)
		meta = Mods.model_meta(act_id)
	elif FileAccess.file_exists(p):
		meta = JSON.parse_string(FileAccess.get_file_as_string(p))
	else:
		push_warning("缺少角色模型 ACT %d (运行 make actors)" % act_id)
	play(0, true)


func _group_node(g: int) -> Node3D:
	if _groups.has(g):
		return _groups[g]
	var grs: Array = meta.get("groups", [])
	if g < 0 or g >= grs.size():
		return null
	var n: Node3D = Mods.instantiate_model(act) if str(grs[g].glb) == "@mod" else Game.load_glb("game/actors/" + str(grs[g].glb))
	if n == null:
		return null
	add_child(n)
	field.unshade(n, false, true)   # 贴图 × 顶点色 (原版 PLY 同场景: diffuse = 顶点色; 人物全白, 地图物件 111 个有烘好的明暗)
	Enhance.light_actor(n)   # 画面增强第二档: 人物明暗 + 轮廓光 + 投影
	if str(grs[g].glb) != "@mod":
		HELD_MORPH.attach(n, "game/actors/" + str(grs[g].glb))   # 逐帧 UV 动画 (例 解封轩辕剑 ACT 4115 道具剑身光流)
	_groups[g] = n
	_shadow_mis.clear()
	return n


## 播放动作 QQ (原版 set_pose 0x15): 循环与否取自 ACT 动作结尾 (VO 循环 / 2O 停在末帧)
## ACT 每帧变换 (tools/act.py xform; 原版 ACT 播放器 0x41d1e3, 绘制 0x495255 + 0x414758, 逆向确认):
##   顶点 = Ry(TR.y + 朝向)·Rx(TR.x) · (CS × v + PD × CS) + 单位位置 (列向量; 数据里有 TR.x 的行 TR.z 都是 0)
##   颜色 = OC (ARGB, 乘到贴图上); 混合 = XF & 0xF: 0 不透明 (忽略 alpha) / 1 加法 src×α + dst / 2 半透明 (0x41676c)
## 例: 嬴诗 穿迷雾 动作 61 九帧内向前位移到 550 (冲过敌人), 雷神多数动作放大 1.6 倍, 鬼魂类动作加法半透明
var _xform: Array = []
var _xf_state := ""          # 当前已套用的颜色 / 混合 (避免每帧改材质)
var tint := Color.WHITE      # 状态染色 (战斗 0x432a6a: 毒 1E A0 00 / 石化 64 64 64 / 咒封 00 BE E6), 乘在动作颜色上
var _xf_orig := {}           # 材质 → [albedo_color, transparency, blend_mode] 原值


func _apply_xform() -> void:
	if not _groups.has(_cur_g):
		return
	var n: Node3D = _groups[_cur_g]
	var row: Array = []
	if not _xform.is_empty():
		var f := int(pose_tick)
		row = _xform[0]
		for r in _xform:
			if int(r[0]) <= f:
				row = r
			else:
				break
	if row.is_empty():
		if n.transform != Transform3D.IDENTITY:
			n.transform = Transform3D.IDENTITY
		_set_xf_color(n, Color.WHITE, 0)
		return
	var sc := Vector3(float(row[1]), float(row[2]), float(row[3]))
	# 原版 Ry(θ) 是标准右手 Ry(−θ) (0x4135a5), 与朝向的换算一致; Rx 是标准 Rx(+θ) (0x4134d8)
	var r := Basis(Vector3.UP, deg_to_rad(-float(row[8]))) * Basis(Vector3.RIGHT, deg_to_rad(float(row[7])))
	var pd := Vector3(float(row[4]), float(row[5]), float(row[6])) * sc * 0.01
	n.transform = Transform3D(r * Basis.from_scale(sc), r * pd)
	var xf := int(row[14]) & 0xF if row.size() > 14 else 0
	_set_xf_color(n, Color8(int(row[11]), int(row[12]), int(row[13]), int(row[10])), xf)


func set_tint(c: Color) -> void:
	if c == tint:
		return
	tint = c
	_xf_state = ""
	_apply_xform()


func _set_xf_color(n: Node3D, c: Color, xf: int) -> void:
	c = Color(c.r * tint.r, c.g * tint.g, c.b * tint.b, c.a)
	var key := "%s|%d" % [c.to_html(), xf]
	if key == _xf_state:
		return
	_xf_state = key
	_xf_alpha = c.a if xf in [1, 2] else 1.0
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for si in m.get_surface_override_material_count():
			var sm := m.get_surface_override_material(si) as StandardMaterial3D
			if sm == null:
				continue
			if not _xf_orig.has(sm):
				_xf_orig[sm] = [sm.albedo_color, sm.transparency, sm.blend_mode]
			var o: Array = _xf_orig[sm]
			var base: Color = o[0]
			if sm.next_pass is ShaderMaterial:   # 画面增强的明暗通道跟着动作透明一起减弱
				(sm.next_pass as ShaderMaterial).set_shader_parameter("mat_alpha", c.a if xf in [1, 2] else 1.0)
			match xf:
				1:   # 加法: src × α + dst
					sm.albedo_color = Color(base.r * c.r, base.g * c.g, base.b * c.b, c.a)
					sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					sm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
				2:   # 半透明
					sm.albedo_color = Color(base.r * c.r, base.g * c.g, base.b * c.b, c.a)
					sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					sm.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
				_:   # 不透明: alpha 不起作用
					sm.albedo_color = Color(base.r * c.r, base.g * c.g, base.b * c.b, base.a)
					sm.transparency = o[1]
					sm.blend_mode = o[2]


## ATK wait_anim N (0x13): 定格在第 N 帧 (播放器 +0xa4 / +0xa6 都设成 N), 直到下一次 play()
var _hold := false
var _pose_wrapped := false
var _idle_next := false
var _fit := 1.0   # 动画时长 / 动作帧数时长 (创意工坊战斗模型: 自定义动画拉伸到原版动作的帧数, 见 Mods 怪物 model)


func resume_anim() -> void:
	if _hold:
		_hold = false
		if _ap:
			_ap.play()


func hold_at(frame: int) -> void:
	_hold = true
	pose_tick = float(frame)
	if _ap:
		_ap.seek(float(frame) / 35.0 * _fit, true)
		_ap.pause()


func play(q: int, force_loop := false) -> void:
	if OS.get_cmdline_user_args().has("--trace-play") and (id == 1 or id == 2 or id == 2020):
		print("PLAY f=%d q=%d from %s" % [Engine.get_process_frames(), q, str(get_stack().slice(1, 3).map(func(x): return "%s:%d" % [x.function, x.line]))])
	pose = q
	pose_tick = 0.0
	_pose_wrapped = false
	_idle_next = false
	_hold = false
	var pm: Dictionary = meta.get("poses", {}).get(str(q), {})
	if pm.is_empty():
		return
	pose_len = int(pm.ticks)
	pose_loop = bool(pm.get("loop", false)) or force_loop
	_er_pending = not pm.get("er", []).is_empty()
	_xform = pm.get("xform", [])
	var g := int(pm.g)
	var n := _group_node(g)
	if n == null:
		return
	if g != _cur_g:
		for k in _groups:
			_groups[k].visible = (k == g)
		_cur_g = g
		var aps := n.find_children("*", "AnimationPlayer", true, false)
		_ap = aps[0] if aps.size() else null
		var sks := n.find_children("*", "Skeleton3D", true, false)
		_skel = sks[0] if sks.size() else null
		_attach_held()
		_bind_face()
	if _ap and _ap.has_animation(str(pm.clip)):
		var anim := _ap.get_animation(str(pm.clip))
		anim.loop_mode = Animation.LOOP_LINEAR if pose_loop else Animation.LOOP_NONE
		if pose_loop:
			# glTF 的动画时长只到最后一个关键帧 ((n−1)/35 秒), 循环时最后一帧会瞬间跳回第一帧 (少一帧过渡, 每圈顿一下,
			# 例: 雷神待机 60 帧, 接缝处的位移是平常的两倍)。把时长补成完整的 n/35 秒, 最后一帧平滑过渡回第一帧
			anim.length = maxf(anim.length, float(pm.ticks) / 35.0)
		if _skel:
			_skel.reset_bone_poses()
		_fit = 1.0
		if pm.get("fit", false) and int(pm.ticks) > 0 and anim.length > 0.0:
			_fit = anim.length / (float(pm.ticks) / 35.0)
		_ap.speed_scale = CLIP_TICK / TICK * _fit
		_ap.play(str(pm.clip), 0.0)
		# 立刻套用新动作的第一帧: 否则要等下一帧才更新, 这一帧骨架停在绑定姿势 (reset_bone_poses 之后),
		# 绑定姿势和动作差很多的模型会闪一下 (例: 雷神 2020 被打 / 回待机时整个往上跳一帧)
		_ap.seek(0.0, true)
	_apply_xform()


## 手持物 (0x8a): 道具 ACT 第 qq 号动作的模型挂到挂点 marker 的骨骼上; marker = 0 卸下
## 模型由 tools/export_held.py 导出; 相对骨骼的基 (含导出时的 X 翻转) 见 act_*.json 各组的 marker_basis
func set_held(item: int, qq: int, marker: int) -> void:
	held = [item, qq, marker] if marker > 0 and item > 0 else []
	_attach_held()


func _attach_held() -> void:
	if is_instance_valid(_held_node):
		_held_node.get_parent().queue_free()
	_held_node = null
	if held.is_empty() or _skel == null:
		return
	var bone := -1
	for bi in _skel.get_bone_count():
		if _skel.get_bone_name(bi).begins_with("marker%d_" % int(held[2])):
			bone = bi
	if bone < 0:
		return
	var hp := "game/held/item_%d_%d.glb" % [int(held[0]), int(held[1])]
	if not FileAccess.file_exists(Game.asset_path(hp)):
		return   # 原版数据里的空槽武器 (例 5492, 部分狄族勇士的武器指向它), 没有模型
	var n := Game.load_glb(hp)
	if n == null:
		return
	var att := BoneAttachment3D.new()
	_skel.add_child(att)
	att.bone_idx = bone
	att.add_child(n)
	field.unshade(n, false, true)
	Enhance.light_actor(n)
	var grs: Array = meta.get("groups", [])
	var b: Array = [1, -1, -1]
	if _cur_g >= 0 and _cur_g < grs.size():
		b = grs[_cur_g].get("marker_basis", {}).get(str(int(held[2])), b)
	# ×100: 道具 GLB 自带 0.01 缩放, 角色骨架已缩放过
	n.transform = Transform3D(Basis.from_scale(Vector3(b[0], b[1], b[2]) * 100.0), Vector3.ZERO)
	var aps := n.find_children("*", "AnimationPlayer", true, false)
	if aps.size() and (aps[0] as AnimationPlayer).has_animation("held"):
		(aps[0] as AnimationPlayer).get_animation("held").loop_mode = Animation.LOOP_LINEAR
		(aps[0] as AnimationPlayer).play("held")
	HELD_MORPH.attach(n, hp)   # 逐帧 UV 动画 (例 解封轩辕剑 4115 剑身光流)
	_held_node = n
	_shadow_mis.clear()


## 表情 (0x78, 应用于 0x46b10d): 把模型材质表第 slot 格 (脸) 的贴图换成表情 ACT 当前帧的头部贴图; act = 0 恢复
## slot: 默认 5, 角色 ACT 为 4/5/0x22/0x23 时 6, 为 10/0x28/0x2b 时 4。帧序列见 tools/export_faces.py
func set_expression(a: int, q: int) -> void:
	expr_act = a
	expr_qq = q
	_expr_frames = []
	if a > 0:
		if _faces.is_empty():
			var p := Game.extracted_dir.path_join("game/faces.json")
			if FileAccess.file_exists(p):
				_faces = JSON.parse_string(FileAccess.get_file_as_string(p))
		var e: Dictionary = _faces.get(str(a), {}).get(str(q), {})
		_expr_frames = e.get("frames", [])
		_expr_loop = bool(e.get("loop", true))
	_expr_i = 0
	_expr_left = int(_expr_frames[0][1]) if _expr_frames.size() else 0
	_apply_face()


func _face_slot() -> int:
	if act in [4, 5, 0x22, 0x23]:
		return 6
	if act in [10, 0x28, 0x2b]:
		return 4
	return 5


## 换组 (换模型) 后重新找脸部材质, 原贴图记下来以便恢复
func _bind_face() -> void:
	for e in _expr_mats:
		(e[0] as StandardMaterial3D).albedo_texture = e[1]
	_expr_mats = []
	var grs: Array = meta.get("groups", [])
	if _cur_g < 0 or _cur_g >= grs.size() or not _groups.has(_cur_g):
		return
	var name_: String = str(grs[_cur_g].get("face_mats", {}).get(str(_face_slot()), ""))
	if name_ == "":
		return
	for mi in (_groups[_cur_g] as Node).find_children("*", "MeshInstance3D", true, false):
		var m3 := mi as MeshInstance3D
		for si in m3.mesh.get_surface_count():
			var mat := m3.get_surface_override_material(si)
			if mat is StandardMaterial3D and mat.resource_name == name_:
				_expr_mats.append([mat, (mat as StandardMaterial3D).albedo_texture])
	_apply_face()


func _apply_face() -> void:
	var tex: Texture2D = null
	if _expr_frames.size():
		var path := str(_expr_frames[_expr_i][0])
		if not _face_tex.has(path):
			_face_tex[path] = Game.load_texture(path)
		tex = _face_tex[path]
	for e in _expr_mats:
		(e[0] as StandardMaterial3D).albedo_texture = tex if tex else e[1]


func _tick_expr() -> void:
	if _expr_frames.size() < 2:
		return
	_expr_left -= 1
	if _expr_left > 0:
		return
	if _expr_i + 1 < _expr_frames.size():
		_expr_i += 1
	elif _expr_loop:
		_expr_i = 0
	else:
		return
	_expr_left = int(_expr_frames[_expr_i][1])
	_apply_face()


## 动作音效: ACT 播放表里的 VW 标记 (第 n 帧播放音效 id), 只有看得见的角色才出声
func _pose_sounds() -> void:
	if hidden or not is_visible_in_tree():
		return
	var pm: Dictionary = meta.get("poses", {}).get(str(pose), {})
	for snd in pm.get("sounds", []):
		if int(snd[0]) == int(pose_tick):
			Game.play_sound(int(snd[1]))
			if OS.get_cmdline_user_args().has("--trace-sounds"):
				print("POSESND act=%d pose=%d sound=%d" % [act, pose, int(snd[1])])


func has_pose(q: int) -> bool:
	return meta.get("poses", {}).has(str(q))


## wait_anim (0x57): 动作播到第 frame 帧 (0 = 播完) 时为真; 循环动作 frame=0 视为一轮
func anim_reached(frame: int) -> bool:
	if _pose_wrapped:   # 循环动作已经走完一圈: 不能只看当前帧, 卡一下就错过末帧的那一拍, 又多等一圈 (电梯门关两次)
		return true
	if frame <= 0:
		return pose_tick >= pose_len - 1
	return pose_tick >= frame


## 放置 (place_actor 0x1b: 写位置后做一次贴地修正)
func set_game_pos(p: Vector3, snap := true) -> void:
	if is_player and OS.get_cmdline_user_args().has("--trace-jump") and Vector2(p.x - gpos.x, p.z - gpos.z).length() > 2000:
		print("JUMP map=%d %s -> %s from %s" % [field.map_id, str(gpos.round()), str(p.round()), str(get_stack().slice(1, 5).map(func(x): return "%s:%d" % [x.function, x.line]))])
	gpos = p
	if snap:
		var y: Variant = field.floor_at(p, p.y)
		if y != null:
			gpos.y = y
	position = field.to_world(gpos)
	if snap and field.has_method("visual_dy") and act < 15000:
		position.y += field.visual_dy(gpos) * 0.01   # 画到看得见的地面上 (碰撞面可能比画面地面高)


func set_facing(deg: float) -> void:
	if OS.get_cmdline_user_args().has("--trace-play") and id == 1:
		print("FACING f=%d %.1f -> %.1f from %s" % [Engine.get_process_frames(), facing, fposmod(deg, 360.0), str(get_stack().slice(1, 3).map(func(x): return "%s:%d" % [x.function, x.line]))])
	facing = fposmod(deg, 360.0)
	# 模型正面是局部 -Z; Godot 旋转 θ 把 -Z 转到 (−sin θ, 0, −cos θ), 要等于 (sin f, 0, −cos f) → θ = −f
	rotation.y = deg_to_rad(-facing)


## 当前动作的 XB 包围盒 [min x, y, z, max x, y, z] (ACT 播放器 +0x200; 换动作时整个结构清零, 没写 XB 就是全 0)
func xb() -> Array:
	var bb: Array = meta.get("poses", {}).get(str(pose), {}).get("bbox", [])
	return bb if bb.size() >= 6 else [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]


static func facing_of(d: Vector3) -> float:
	return rad_to_deg(atan2(d.x, -d.z))


static func dir_of(deg: float) -> Vector3:
	var r := deg_to_rad(deg)
	return Vector3(sin(r), 0, -cos(r))


func face_point(p: Vector3) -> void:
	var d := p - gpos
	if absf(d.x) + absf(d.z) < 0.01:
		return
	set_facing(facing_of(d))


func walk_to(p: Vector3, spd: float, pose_q := -1) -> void:
	if is_player and OS.get_cmdline_user_args().has("--trace-jump"):
		print("WALKTO map=%d %s -> %s from %s" % [field.map_id, str(gpos.round()), str(p.round()), str(get_stack().slice(1, 5).map(func(x): return "%s:%d" % [x.function, x.line]))])
	path = [p]
	speed = spd
	walk_pose = pose_q
	if walk_pose >= 0 and pose != walk_pose:
		play(walk_pose)


func is_moving() -> bool:
	return not path.is_empty()


## hide_actor (0x23) / show_actor (0x24) 置 / 清的就是标志 +0x1a4 bit0: 标志里的 0x1 一起改,
## 否则开局隐藏 (记录标志带 0x1) 后被脚本显示的角色仍被调查 (0x9) / 碰撞 / 踩踏触发当成隐藏跳过 (例: 令狐国古井 2060)
func set_hidden(h: bool) -> void:
	hidden = h
	flags = (flags | 0x1) if h else (flags & ~0x1)
	if h:
		clear_er()
	_refresh_visible()


func _refresh_visible() -> void:
	visible = not hidden and not (flags & 0x8)


func fade_alpha(from: int, to: int, spd: int) -> void:
	alpha = from / 255.0
	_alpha_to = to / 255.0
	_alpha_step = maxf(spd, 1) / 255.0
	_apply_alpha()


func fading() -> bool:
	return not is_equal_approx(alpha, _alpha_to)


func _apply_alpha() -> void:
	for n in _groups.values():
		for mi in (n as Node).find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).transparency = 1.0 - alpha


## 画面增强的投影不受 transparency / 材质 alpha 影响: 隐身 (脚本淡出、动作逐帧透明) 时模型看不见了影子还在 (例 云狐旋空收招)。
## 不透明度低于一半就不投影 (原版没有投影, 这是增强档自己的规则)
var _shadow_mis: Array = []
var _xf_alpha := 1.0


func _sync_shadow() -> void:
	if _shadow_mis.is_empty():
		for mi in find_children("*", "MeshInstance3D", true, false):
			if mi.has_meta("enh_shadow"):
				_shadow_mis.append(mi)
		if _shadow_mis.is_empty():
			return
	for mi in _shadow_mis:
		if not is_instance_valid(mi):
			_shadow_mis.clear()
			return
		var g := mi as GeometryInstance3D
		var want := GeometryInstance3D.SHADOW_CASTING_SETTING_ON if g.transparency < 0.5 and _xf_alpha >= 0.5 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if g.cast_shadow != want:
			g.cast_shadow = want


func _process(delta: float) -> void:
	_sync_shadow()
	# 走到终点后下一帧才回站立: 脚本 wait_move 后紧接的 set_pose 先执行 (process_frame 信号在 _process 之前), 这时就不用切了。
	# 否则多画一帧 0 号动作, 像电梯 ACT 15014 的 0 号是另一个模型, 到层时门会闪一下
	if _idle_next:
		_idle_next = false
		if pose != 0 and has_pose(0):
			play(0)
	_acc += delta
	while _acc >= TICK:
		_acc -= TICK
		_tick()


func _tick() -> void:
	_tick_expr()
	_pose_sounds()
	if _layer_ap:
		_tick_layer()
	if not _hold:
		pose_tick += 1.0
	if pose_loop and pose_tick >= pose_len:
		pose_tick = 0.0
		_pose_wrapped = true
		_er_pending = not meta.get("poses", {}).get(str(pose), {}).get("er", []).is_empty()   # VO 回到动作开头, ER 再执行一次
	_tick_er()
	if not _xform.is_empty() or (_groups.has(_cur_g) and (_groups[_cur_g] as Node3D).transform != Transform3D.IDENTITY):
		_apply_xform()
	if not is_equal_approx(alpha, _alpha_to):
		alpha = move_toward(alpha, _alpha_to, _alpha_step)
		_apply_alpha()
	if path.is_empty():
		return
	var tgt: Vector3 = path[0]
	# 路径步进 (0x46a086, 逆向确认): 带 0x40 (set_collision w=0) 时位移含 Y 分量 (目标 − 当前, 三维长度和速度比),
	# 再交给 0x468a89 直接位移不贴地 —— 例 昊天界电梯事件 1518: 关碰撞后同一 XZ 走到 y 8309, 车芸随升降台下到下层
	if flags & 0x40 and not flags & 0x1000000:
		var d3 := tgt - gpos
		var arrive := d3.length() <= speed
		if not arrive and not flags & NO_TURN_WALK:
			face_point(tgt)
		field._map_move(self, d3 if arrive else d3.normalized() * speed)
		if arrive:
			path.pop_front()
			if path.is_empty():
				walk_pose = -1
				_idle_next = true
		return
	var d := Vector3(tgt.x - gpos.x, 0, tgt.z - gpos.z)
	if d.length() <= speed:
		set_game_pos(Vector3(tgt.x, gpos.y, tgt.z))
		path.pop_front()
		if path.is_empty():
			walk_pose = -1
			# 原版路径走完 (0x469f18, 路径标志 0x80000000): 动作 +0x296 清 0 = 站立, 并重播动画 (+0x1a4 |= 0x20)。
			# 脚本常写「set_pose 4 → walk_to → wait_move」后不再设动作 (例: 事件 12 车芸走到端木老人面前), 靠这里停下
			_idle_next = true
		return
	if not flags & NO_TURN_WALK:
		face_point(tgt)
	var step := d.normalized() * speed
	var np := Vector3(gpos.x + step.x, gpos.y, gpos.z + step.z)
	var y: Variant = field.floor_at(np, gpos.y)
	if y != null:
		np.y = y
	gpos = np
	position = field.to_world(gpos)
	if field.has_method("visual_dy") and act < 15000:
		position.y += field.visual_dy(gpos) * 0.01


## 四首木甲 (单位 2024 / 2124 / 2224 / 2324, exe 0x43dba7): 武器 ACT (ObjDATA 武器编号 5474) 的第 3 号动作 = 四个头的转盘
## (80 帧, 用本体矩阵画, 变化号 v = 0/1/2/3 时转到第 1/61/21/41 帧停住, 其余时间一直转); 第 4+v 号动作 = 该头的眼光 (31 帧循环),
## 转盘停在目标帧时画在转盘模型的挂点 (0x1e,0x1f)/(0x22,0x23)/(0x24,0x25)/(0x20,0x21) 上, 缩放 3 (0x46ade2)
const LAYER_FRAME := {0: 1, 1: 61, 2: 21, 3: 41}
const LAYER_EYES := {0: [31, 32], 1: [35, 36], 2: [37, 38], 3: [33, 34]}   # 原版挂点号 +1 (导出的骨骼名同手持物挂点)
var variant := 0
var _layer_item := 0
var _layer_node: Node3D
var _layer_ap: AnimationPlayer
var _layer_skel: Skeleton3D
var _glow: Array = []   # [节点, 节点]


func set_layer(item: int) -> void:
	_layer_item = item
	if is_instance_valid(_layer_node):
		_layer_node.queue_free()
	_layer_node = null
	_layer_ap = null
	_layer_skel = null
	var hp := "game/held/item_%d_3.glb" % item
	if item <= 0 or not FileAccess.file_exists(Game.asset_path(hp)):
		return
	var n := Game.load_glb(hp)
	if n == null:
		return
	add_child(n)
	field.unshade(n)
	Enhance.light_actor(n)
	_shadow_mis.clear()
	_layer_node = n
	var aps := n.find_children("*", "AnimationPlayer", true, false)
	_layer_ap = aps[0] if aps.size() else null
	var sks := n.find_children("*", "Skeleton3D", true, false)
	_layer_skel = sks[0] if sks.size() else null
	if _layer_ap and _layer_ap.has_animation("held"):
		_layer_ap.get_animation("held").loop_mode = Animation.LOOP_LINEAR
		_layer_ap.play("held")
		_layer_ap.seek(float(LAYER_FRAME.get(variant, 1)) / 35.0, true)
		_layer_ap.pause()
	set_variant(variant)


func set_variant(v: int) -> void:
	variant = v
	for g in _glow:
		if is_instance_valid(g):
			g.queue_free()
	_glow = []
	if _layer_ap == null:
		return
	if _layer_ap.current_animation == "":
		_layer_ap.play("held")
	var hp := "game/held/item_%d_%d.glb" % [_layer_item, 4 + v]
	if not FileAccess.file_exists(Game.asset_path(hp)):
		return
	for m in LAYER_EYES.get(v, []):
		var bone := -1
		if _layer_skel:
			for bi in _layer_skel.get_bone_count():
				if _layer_skel.get_bone_name(bi).begins_with("marker%d_" % int(m)):
					bone = bi
		if bone < 0:
			continue
		var n := Game.load_glb(hp)
		if n == null:
			continue
		var att := BoneAttachment3D.new()
		_layer_skel.add_child(att)
		att.bone_idx = bone
		att.add_child(n)
		field.unshade(n)
		# 0x46ade2: 位置 = 挂点, 旋转 0, 缩放 3; 挂点骨骼带着本体缩放, 道具 GLB 自带 0.01 → 反掉骨骼的缩放再乘 3×100
		n.top_level = false
		n.transform = Transform3D(Basis.from_scale(Vector3.ONE * 300.0), Vector3.ZERO)
		var aps := n.find_children("*", "AnimationPlayer", true, false)
		if aps.size() and (aps[0] as AnimationPlayer).has_animation("held"):
			(aps[0] as AnimationPlayer).get_animation("held").loop_mode = Animation.LOOP_LINEAR
			(aps[0] as AnimationPlayer).play("held")
		HELD_MORPH.attach(n, hp)   # 眼光 5474 qq4–7 的逐帧变形
		n.visible = false
		_glow.append(n)


func _tick_layer() -> void:
	var target := int(LAYER_FRAME.get(variant, 1))
	var frame := int(roundf(_layer_ap.current_animation_position * 35.0))
	var at := frame == target
	if at:
		_layer_ap.pause()
	elif not _layer_ap.is_playing():
		_layer_ap.play("held")
	for g in _glow:
		if is_instance_valid(g):
			g.visible = at


## 挂点粒子: 角色画出来时 (不隐藏) 才生成 / 检查停止 (原版只在绘制 0x46b10d 里做)
func _tick_er() -> void:
	if hidden or not is_visible_in_tree():
		return
	var pm: Dictionary = meta.get("poses", {}).get(str(pose), {})
	if _er_pending:
		_er_pending = false
		for e in pm.get("er", []):
			var em := _spawn_er(int(e[0]), int(e[1]))
			if em:
				_er_ems[int(e[0])] = [em, int(e[2])]   # 同一挂点的旧句柄直接覆盖 (0x46e0cc), 不停旧的
	if _er_ems.is_empty():
		return
	var aps: Array = pm.get("aps", [])
	var fr := int(aps[mini(int(pose_tick), aps.size() - 1)]) if aps.size() else int(pose_tick)
	for k in _er_ems.keys():
		var h: Array = _er_ems[k]
		if not is_instance_valid(h[0]):
			_er_ems.erase(k)
			continue
		if fr != 0 and int(h[1]) == fr:
			(h[0] as FxEmitter).emitting = false
			h[1] = 0


func _spawn_er(slot: int, pid: int) -> FxEmitter:
	if _skel == null or not Fx.load_db():
		return null
	var bone := -1
	for bi in _skel.get_bone_count():
		if _skel.get_bone_name(bi).begins_with("marker%d_" % (slot + 1)):
			bone = bi
	if bone < 0:
		return null
	var p: Dictionary = Fx._db.get("_particles", {}).get(str(pid), {})
	if p.is_empty():
		return null
	var nm := "er_%d" % slot
	var att := _skel.get_node_or_null(nm) as BoneAttachment3D   # 每轮循环都会再生成, 挂点节点复用
	if att == null:
		att = BoneAttachment3D.new()
		att.name = nm
		_skel.add_child(att)
		att.bone_idx = bone
	var em := FxEmitter.new()
	em.anchor = att
	field._world.add_child(em)
	em.setup(p, Fx._db.get(str(p.get("visual", "")), {}), Fx._dir, field._cam3d)
	return em


## 0x46e16a: 停止并丢弃全部挂点粒子 (已生成的粒子照常飞完)
func clear_er() -> void:
	for h in _er_ems.values():
		if is_instance_valid(h[0]):
			(h[0] as FxEmitter).emitting = false
	_er_ems.clear()
