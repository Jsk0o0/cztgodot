class_name FxEmitter
extends MultiMeshInstance3D
## Effect.dat 粒子发射器 (参数含义见 effects.json 的 _meta.particle_fields / particle_sim)
## 每个粒子原版会播放自己的 ACT 外观动画 (记录 +0xc4/+0xc6):
##   外观是 3D 模型 → 每个粒子生成一个 Fx (循环播放, 颜色 = 粒子颜色, 缩放 + 粒子尺寸), 与原版一致
##   外观是 2D 精灵 → 朝向相机的面片 (MultiMesh, 加法混合), 尺寸取外观包围盒; 每个粒子从出生起按外观动作的 frame 轨道逐帧播放
##   (原版粒子 +0x94/+0x96 = 外观 ACT / 动作, 0x492c48 出生时设定; 每帧 0x41d1e3 推进, 绘制 0x4934fd 取 +0x9c 精灵组的第 +0x9e 帧)。
##   以前只画首帧: 开宝箱 2036 等 7 个粒子的外观 8122 / 8119 首帧全黑, 加法混合下完全看不见

const U := 0.01

var p: Dictionary
var anchor: Node3D
var anchor_local := Vector3.ZERO
var owner_fx: Node
var stop_tick := 0
var emitting := true
const TICK := 1.0 / 35.0
var _floor_w := 0.0
var _parts: Array = []      # 每粒子: [pos, vel, age, life, col0, a0, size0, size1, g0]
var _spawn_acc := 0.0
var _total := 0
var _vis_size := 0.5
var _rng := RandomNumberGenerator.new()
var _vis_key := ""        # 3D 外观: 每个粒子一个 Fx
var _cam: Camera3D
var _spr_frames: Array = []   # 精灵外观: 每 tick 的帧号 (frame 轨道展开); 空 = 不是精灵或只有一帧
var _spr_loop := true
static var _arr_cache := {}   # 精灵外观 → [贴图数组, 帧号表, 循环]


func setup(params: Dictionary, visual: Dictionary, base_dir: String, camera: Camera3D = null) -> void:
	p = params
	top_level = true
	_rng.randomize()
	_cam = camera
	if visual.get("kind", "") == "model" and Fx.has(str(p.get("visual", ""))):
		_vis_key = str(p.visual)
	_floor_w = float(p.get("floor_y", 0.0)) * U
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = visual.get("kind", "") == "sprite"
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	mm.mesh = q
	mm.instance_count = maxi(int(p.get("count", 20)), 1)
	mm.visible_instance_count = 0
	multimesh = mm
	var mat := ShaderMaterial.new()
	mat.shader = Fx._shader_pt
	var arr := _sprite_frames(visual, base_dir) if visual.get("kind", "") == "sprite" else null
	if arr:
		mat.shader = Fx.particle_array_shader()
		mat.set_shader_parameter("frames", arr)
	else:
		_spr_frames = []
		mat.set_shader_parameter("tex", _visual_texture(visual, base_dir))
	mat.set_shader_parameter("boost", Enhance.fx_boost())
	material_override = mat
	var bb: Array = visual.get("bbox", [-50, -50, -50, 50, 50, 50])
	_vis_size = maxf(bb[3] - bb[0], bb[4] - bb[1]) * U
	if not int(p.get("continuous", 1)):
		for i in int(p.get("count", 1)):
			_spawn()


## 精灵外观的全部帧做成贴图数组 + 每 tick 的帧号表; 只有一帧时返回 null (照旧用单张贴图)
func _sprite_frames(visual: Dictionary, base_dir: String) -> Texture2DArray:
	var files: Array = []
	for fr in visual.get("sprites", {}):
		files = visual.sprites[fr].get("frames", [])
		if files.size():
			break
	if files.size() < 2:
		return null
	var key := base_dir.path_join(files[0]) + "|" + str(visual.get("act", "")) + "_" + str(visual.get("sub", ""))
	if _arr_cache.has(key):
		var c: Array = _arr_cache[key]
		_spr_frames = c[1]
		_spr_loop = c[2]
		return c[0]
	var imgs: Array[Image] = []
	var size := Vector2i.ZERO
	for f in files:
		var t := Fx.texture(base_dir.path_join(f))
		var im: Image = t.get_image() if t else null
		if im == null:
			return null
		im = im.duplicate()
		if im.is_compressed():
			im.decompress()
		im.convert(Image.FORMAT_RGBA8)
		if size == Vector2i.ZERO:
			size = im.get_size()
		elif im.get_size() != size:
			im.resize(size.x, size.y, Image.INTERPOLATE_BILINEAR)
		im.generate_mipmaps()
		imgs.append(im)
	var arr := Texture2DArray.new()
	if arr.create_from_images(imgs) != OK:
		return null
	var ticks := maxi(int(visual.get("ticks", 1)), 1)
	var tr: Array = visual.get("tracks", {}).get("frame", [])
	_spr_frames = []
	var v := 0
	var j := 0
	for t in ticks:
		while j < tr.size() and int(tr[j][0]) <= t:
			v = int(tr[j][1])
			j += 1
		_spr_frames.append(clampi(v, 0, imgs.size() - 1))
	_spr_loop = bool(visual.get("loop", true))
	_arr_cache[key] = [arr, _spr_frames, _spr_loop]
	return arr


func _visual_texture(visual: Dictionary, base_dir: String) -> Texture2D:
	if visual.get("kind", "") == "sprite":
		for fr in visual.get("sprites", {}):
			var frames: Array = visual.sprites[fr].get("frames", [])
			if frames.size():
				return Fx.texture(base_dir.path_join(frames[0]))
	for fr in visual.get("models", {}):
		var n := Fx.template(visual.models[fr].glb)
		if n:
			for mi in n.find_children("*", "MeshInstance3D", true, false):
				var m := (mi as MeshInstance3D).mesh.surface_get_material(0)
				if m is BaseMaterial3D and (m as BaseMaterial3D).albedo_texture:
					var tex := (m as BaseMaterial3D).albedo_texture
					n.free()
					return tex
			n.free()
	return null


func alive() -> bool:
	return emitting or not _parts.is_empty()


func _emit_point() -> Vector3:
	if anchor and is_instance_valid(anchor):
		return anchor.global_transform * anchor_local
	return owner_fx.global_position if owner_fx else global_position


func _r() -> float:
	return _rng.randf()


func _spawn() -> void:
	var maxt := int(p.get("max_total", 0))
	if maxt > 0 and _total >= maxt:
		return
	_total += 1
	# 出生 (0x492377, 逆向确认): 位置 = 发射点 + ((U−0.5)·抖动x, (U−0.5)·抖动y, (U−0.5)·抖动z);
	# attract 与 flag_f7 都为 1 时 y 不抖动 (留在发射点高度)
	var e := _emit_point()
	var pos := e + Vector3((_r() - 0.5) * p.spawn_box_x, (_r() - 0.5) * p.spawn_box_y, (_r() - 0.5) * p.spawn_box_z) * U
	if int(p.get("attract", 0)) == 1 and int(p.get("flag_f7", 0)) == 1:
		pos.y = e.y
	# 方向: 方向表 6 个值全 0 → 球面, A = (r1−r2)/32767·2π, B = (r3−r4)/32767·spread·π/180 (都是三角分布),
	#   v = (cosA·sinB, cosB, sinA·sinB) —— 极轴是 +Y, spread 小时近乎正上方 (以前当成离水平面的俯仰角, 是推测, 错的);
	# 否则在 [min, max] 区间均匀取 x / y / z, 不归一化。方向是世界坐标, 不随特效朝向旋转; 再乘速度 (速度 + U·随机量)
	var db: Array = p.get("dir_box", [0, 0, 0, 0, 0, 0])
	var dir: Vector3
	var a := (_r() - _r()) * TAU
	var b := (_r() - _r()) * deg_to_rad(float(p.spread_deg))
	if db.max() == 0 and db.min() == 0:
		dir = Vector3(cos(a) * sin(b), cos(b), sin(a) * sin(b))
	else:
		dir = Vector3(lerpf(db[0], db[1], _r()), lerpf(db[2], db[3], _r()), lerpf(db[4], db[5], _r()))
	var speed := (float(p.speed) + _r() * float(p.speed_random)) * U
	var c0: Array = p.color_start
	var cr: Array = p.color_random
	var col := Color(clampf((c0[0] + _r() * cr[0]) / 255.0, 0, 1), clampf((c0[1] + _r() * cr[1]) / 255.0, 0, 1),
		clampf((c0[2] + _r() * cr[2]) / 255.0, 0, 1))
	var a0 := clampf((float(p.alpha_start) + _r() * float(p.alpha_random)) / 255.0, 0, 1)
	var s0 := float(p.size_start) + _r() * float(p.size_random)
	var s1 := float(p.size_end) + _r() * float(p.get("size_end_random", 0.0))
	var g0 := float(p.gravity_start) + _r() * float(p.gravity_random)
	var life := maxf(float(p.life) + _r() * float(p.life_random), 0.05)
	var node: Fx = null
	if _vis_key != "":
		node = Fx.spawn(self, _vis_key, pos, Basis(), _cam, Callable(), true)
		if node:
			node.top_level = true
	var yaw := atan2(dir.x, dir.z) if Vector2(dir.x, dir.z).length() > 0.0001 else 0.0
	_parts.append([pos, dir * speed, 0.0, life, col, a0, s0, s1, g0, node, yaw, -speed / U])


func _process(delta: float) -> void:
	if anchor != null and not is_instance_valid(anchor):   # 挂点已删 (角色 / 特效不在了): 不再发射, 剩下的粒子放完自删
		anchor = null
		emitting = false
	if owner_fx and owner_fx.has_method("current_frame") and stop_tick > 0 and owner_fx.current_frame() >= stop_tick:
		emitting = false
	if emitting and int(p.get("continuous", 1)):
		_spawn_acc += float(p.get("rate", 10)) * delta
		while _spawn_acc >= 1.0:
			_spawn_acc -= 1.0
			if _parts.size() < multimesh.instance_count:
				_spawn()
	var origin := _emit_point()
	var keep: Array = []
	var ce: Array = p.color_end
	for q in _parts:
		q[2] += delta
		var k: float = q[2] / q[3]
		if k >= 1.0:
			if q[9] and is_instance_valid(q[9]):
				(q[9] as Node).queue_free()
			continue
		var g := lerpf(q[8], float(p.gravity_end), k)
		q[1].y += g * -9.8 * 9.8 * U * delta
		if int(p.get("attract", 0)):
			var to: Vector3 = origin - q[0]
			if int(p.get("attract_flat", 0)):
				to.y = 0
			if to.length() > 0.001:
				q[1] += to.normalized() * 500.0 * U * delta
		var prev_y: float = q[0].y
		q[0] += q[1] * delta
		if _floor_w != 0.0 and q[0].y < _floor_w:
			# 0x492e0c: 粒子落到 floor_y 以下 → 竖直速度快 (< −5/tick) 时退回上一帧位置, 否则放到地面; 竖直速度 ×(−反弹系数),
			# 反弹系数 (+0xc8) 初始化为 0 且从不改写, 所以都是停住不弹 (皓月宝镜、散轩辕之一、封灵孢子等 11 个粒子)
			q[0].y = prev_y if q[1].y * delta / TICK < -5.0 * U else _floor_w
			q[1].y = 0.0
		keep.append(q)
	_parts = keep
	if _vis_key != "":
		multimesh.visible_instance_count = 0
		for q in _parts:
			var fx: Fx = q[9]
			if fx == null or not is_instance_valid(fx):
				continue
			var k: float = q[2] / q[3]
			var size: float = q[6] if float(p.size_end) <= 0.0 else lerpf(q[6], q[7], k)
			var c: Color = q[4]
			fx.particle_mod = Color(lerpf(c.r, ce[0] / 255.0, k), lerpf(c.g, ce[1] / 255.0, k), lerpf(c.b, ce[2] / 255.0, k),
				lerpf(q[5], float(p.alpha_end) / 255.0, k))
			fx.particle_size = size
			fx.global_position = q[0]
			if int(p.get("spin", 0)):
				# 0x492b5a (出生时): 只按初速度的水平方向定 Y 轴转角 (与 (0,0,-1) 的夹角, x<0 取 360−角), X/Z 转角清 0;
				# 0x49307d (每帧): X/Z 转角各加 −初速度 度/秒 (fmod 360)。模型不会按飞行方向俯仰 —— 铄雷咒的雷 (8005_10, 竖直模型)
				# 落下时仍竖直; 以前用 looking_at 把它放倒成贴地的横雷
				var a := deg_to_rad(q[11] * q[2])
				fx.global_basis = Basis(Vector3.UP, q[10]) * Basis.from_euler(Vector3(a, 0.0, a))
			fx._last_tick = -1
		if not alive():
			queue_free()
		return
	var n := mini(_parts.size(), multimesh.instance_count)
	multimesh.visible_instance_count = n
	for i in n:
		var q: Array = _parts[i]
		var k: float = q[2] / q[3]
		var size: float = q[6] if float(p.size_end) <= 0.0 else lerpf(q[6], q[7], k)
		var s := _vis_size * maxf(1.0 + size, 0.05)
		multimesh.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(s, s, s)), q[0]))
		var c: Color = q[4]
		var col := Color(lerpf(c.r, ce[0] / 255.0, k), lerpf(c.g, ce[1] / 255.0, k), lerpf(c.b, ce[2] / 255.0, k),
			lerpf(q[5], float(p.alpha_end) / 255.0, k))
		multimesh.set_instance_color(i, col)
		if not _spr_frames.is_empty():
			var tk := int(q[2] / Fx.TICK)
			tk = tk % _spr_frames.size() if _spr_loop else mini(tk, _spr_frames.size() - 1)
			multimesh.set_instance_custom_data(i, Color(float(_spr_frames[tk]), 0, 0, 0))
	if not alive():
		queue_free()
