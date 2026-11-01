extends Node
## 模型的逐帧顶点变形 (UV 动画): 例 解封轩辕剑 4115 剑身光流 —— 原版 PLY 每帧改光效层 (tex10111, 加法) 的 V 坐标, 101 帧滚一圈
## glTF 的 UV morph Godot 不认, 同 fx.gd _setup_morph: 按当前动画的帧换成对应 morph target 的网格 (用到才建)
## 用于手持物 (game/held, 动画 held) 和角色 / 道具 / 地图物件模型 (game/actors, 动画 pose_<动作号>)
## 数据: <glb>.morph.json (tools/ply2gltf sidecar; export_held.py / export_actors.py --sidecar), 顶点按导出时写进 UV2.x 的原始下标对回 PLY 顶点

const FPS := 35.0
static var _cache := {}   # glb → {"side": sidecar, "frames": {动画: [target]}, "meshes": {网格名: {target: ArrayMesh}}, "base": {网格名: Mesh}}

var _ap: AnimationPlayer
var _frames := {}
var _c: Dictionary
var _mis: Array = []      # [[MeshInstance3D, 原网格], …]
var _cur := -2
var _clip := ""


## 有 sidecar 时给 n 挂上; 返回是否挂了。目标网格用到时才建 (有的模型几百帧, 一次全建会卡住读取)
static func attach(n: Node, glb: String) -> bool:
	var side_path := Game.asset_path(glb + ".morph.json")
	if not FileAccess.file_exists(side_path):
		return false
	var aps := n.find_children("*", "AnimationPlayer", true, false)
	if aps.is_empty():
		return false
	if not _cache.has(glb):
		var side: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(side_path))
		_cache[glb] = {"side": side, "frames": side.frames, "meshes": {}, "base": {}}
	var c: Dictionary = _cache[glb]
	var hm = (load("res://scripts/held_morph.gd") as GDScript).new()
	hm._ap = aps[0]
	hm._frames = c.frames
	hm._c = c
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var key := str(mi.name)
		if not c.base.has(key):
			c.base[key] = (mi as MeshInstance3D).mesh
			c.meshes[key] = {}
		hm._mis.append([mi, (mi as MeshInstance3D).mesh])
	# 动画里的 blend shape 通道不再需要 (换 mesh 实现; 材质是 surface override, 换 mesh 后保留)
	for an in hm._ap.get_animation_list():
		var anim: Animation = hm._ap.get_animation(an)
		for ti in range(anim.get_track_count() - 1, -1, -1):
			if anim.track_get_type(ti) == Animation.TYPE_BLEND_SHAPE:
				anim.remove_track(ti)
	n.add_child(hm)
	return true


## 第 t 个 morph target 的网格 (顶点按导出时写进 UV2.x 的原始下标对回 PLY 顶点)
func _target_mesh(key: String, t: int) -> Mesh:
	var built: Dictionary = _c.meshes[key]
	if built.has(t):
		return built[t]
	var side: Dictionary = _c.side
	var tg: Dictionary = side.targets[t]
	var base: Mesh = _c.base[key]
	var am := ArrayMesh.new()
	for si in base.get_surface_count():
		var arr := base.surface_get_arrays(si)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var us: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
		var u2: Variant = arr[Mesh.ARRAY_TEX_UV2]
		if u2 != null:
			for vi in vs.size():
				var pi := int(roundf((u2 as PackedVector2Array)[vi].x * 65535.0))
				if pi < 0 or pi >= side.base_pos.size():
					continue
				var p: Array = tg.pos[pi]
				var u: Array = tg.uv[pi]
				vs[vi] = Vector3(p[0], p[1], p[2])
				us[vi] = Vector2(u[0], u[1])
		arr[Mesh.ARRAY_VERTEX] = vs
		arr[Mesh.ARRAY_TEX_UV] = us
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		am.surface_set_material(si, base.surface_get_material(si))
	built[t] = am
	return am


func _process(_delta: float) -> void:
	if not is_instance_valid(_ap):
		return
	var clip := str(_ap.assigned_animation)
	var fl: Array = _frames.get(clip, [])
	var t := -1
	if fl.size():
		t = int(fl[clampi(int(_ap.current_animation_position * FPS), 0, fl.size() - 1)])
	if t == _cur and clip == _clip:
		return
	_cur = t
	_clip = clip
	for e in _mis:
		var mi := e[0] as MeshInstance3D
		mi.mesh = _target_mesh(str(mi.name), t) if t >= 0 and t < (_c.side.targets as Array).size() else e[1]
