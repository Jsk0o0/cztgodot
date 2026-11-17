class_name Fx
extends Node3D
## 原版战斗特效播放 (数据: extracted/effects/effects.json, 由 tools/effects.py 逆向生成)
## 一个特效 = ACT 动作脚本: 每 tick (1/35 秒) 选模型(FR)/帧号/颜色/缩放/旋转/偏移; 结束后末帧停留 linger_ticks
## 组件: 3D 模型 (MGC*.glb, 按 tick seek 帧, 混合方式按原版材质 flags) / 2D 精灵 / 粒子发射器 (Effect.dat)
## 用法: Fx.spawn(parent, "8101_7", 位置, 朝向 Basis, 相机, 命中回调)

static var TICK := 1.0 / 35.0   # 逻辑帧长, 战斗中 1/27 (见 FieldActor.TICK)
const CLIP_TICK := 1.0 / 35.0   # 特效 GLB 动画按 35 帧/秒烘焙 (tools/effects.py)
const U := 0.01  # 游戏单位 → 米

static var _db: Dictionary
static var _dir := ""
static var _tpl := {}       # glb 相对路径 → 模板节点
static var _shader_add: Shader
static var _shader_mix: Shader
static var _shader_invmul: Shader   # 混合模式 4 / 8 的乘法遍
static var _shader_sqadd: Shader    # 混合模式 8 的加法遍
static var _shader_pt: Shader
static var _tex_cache := {}

var loop_forever := false      # 循环动作不自动结束 (地图 add_ani 的循环特效、标题竹叶)
var hold_last := false         # 停在末帧不删除 (挂在单位身上的 ACT 播放器, 例 收化法器 +0x8b4: 非循环动作播完停在末帧, 由程序清除)
var key := ""
var data: Dictionary
var cam: Camera3D
var on_hit: Callable
var t := 0.0
var _models := {}           # FR → {node, ap, anim, skel, mats, bb}
var _sprite: Sprite3D
var _sprite_frames := {}
var _last_tick := -1
var _emitters: Array = []
var _events_done := {}
# 作为粒子外观播放时 (FxEmitter): 循环播放, 颜色乘 particle_mod, 缩放加 particle_size (原版 0x4933c2: 粒子尺寸加到 CS 缩放上)
var particle := false
var particle_mod := Color(1, 1, 1, 1)
var particle_size := 0.0


static func load_db() -> bool:
	if not _db.is_empty():
		return true
	_dir = Game.extracted_dir.path_join("effects")
	var f := FileAccess.open(_dir.path_join("effects.json"), FileAccess.READ)
	if f == null:
		return false
	_db = JSON.parse_string(f.get_as_text())
	_shader_add = _make_shader("blend_add")
	_shader_mix = _make_shader("blend_mix")
	_shader_invmul = _make_shader("inv_mul")
	_shader_sqadd = _make_shader("sq_add")
	_shader_pt = Shader.new()
	_shader_pt.code = """shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;
uniform sampler2D tex : source_color, filter_linear;
uniform float boost = 1.0;
// 顶点色按 sRGB 解码再乘 (D3D 按字节相乘 = gamma 空间; 贴图 source_color 已解码成线性, 顶点色不解码会偏亮: 实测 200×128 → 147, 原版 100)
vec3 vc(vec3 s) { return mix(s / 12.92, pow((s + 0.055) / 1.055, vec3(2.4)), step(0.04045, s)); }
void vertex() {
	float s = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * s, INV_VIEW_MATRIX[1] * s, INV_VIEW_MATRIX[2] * s, MODEL_MATRIX[3]);
}
void fragment() {
	vec4 c = texture(tex, UV);
	ALBEDO = c.rgb * vc(COLOR.rgb) * COLOR.a * boost;
}
"""
	return true


## 精灵粒子 (贴图数组版): 同 _shader_pt, 帧号放在 INSTANCE_CUSTOM.x (FxEmitter 逐粒子推进外观动画)
static var _shader_pt_arr: Shader


static func particle_array_shader() -> Shader:
	if _shader_pt_arr == null:
		_shader_pt_arr = Shader.new()
		_shader_pt_arr.code = _shader_pt.code.replace("uniform sampler2D tex : source_color, filter_linear;", "uniform sampler2DArray frames : source_color, filter_linear_mipmap;\nvarying float layer;") \
			.replace("void vertex() {", "void vertex() {\n\tlayer = INSTANCE_CUSTOM.x;") \
			.replace("vec4 c = texture(tex, UV);", "vec4 c = texture(frames, vec3(UV, layer));")
	return _shader_pt_arr


static func _make_shader(blend: String) -> Shader:
	# 原版: 加法 = SRCALPHA,ONE (贴图无 alpha, 亮度即强度); 普通 = SRCALPHA,INVSRCALPHA
	var sh := Shader.new()
	# 贴图 × 顶点色 (D3D MODULATE): 加法层亮度再乘顶点 alpha, 混合层 alpha 乘顶点 alpha
	var body := "ALBEDO = c.rgb * vc(COLOR.rgb) * COLOR.a * tint.rgb * tint.a * boost;" if blend == "blend_add" else "ALBEDO = c.rgb * vc(COLOR.rgb) * tint.rgb; ALPHA = c.a * COLOR.a * tint.a;"
	if blend == "inv_mul":   # 目标 × (1 − 源色)
		blend = "blend_mul"
		body = "ALBEDO = vec3(1.0) - clamp(c.rgb * vc(COLOR.rgb) * tint.rgb, 0.0, 1.0);"
	elif blend == "sq_add":   # + 源色²
		blend = "blend_add"
		body = "vec3 s = clamp(c.rgb * vc(COLOR.rgb) * tint.rgb, 0.0, 1.0); ALBEDO = s * s;"
	sh.code = """shader_type spatial;
render_mode unshaded, %s, depth_draw_never, cull_disabled, skip_vertex_transform;
uniform sampler2D tex : source_color, filter_linear, repeat_enable;
uniform vec4 tint = vec4(1.0);
uniform float boost = 1.0;   // 画面增强: 加法光效提亮到 1.0 以上, 好让泛光只作用在光效上 (Enhance.fx_boost)
// 顶点色按 sRGB 解码再乘 (D3D 按字节相乘 = gamma 空间; 贴图 source_color 已解码成线性, 顶点色不解码会偏亮: 实测 200×128 → 147, 原版 100)
vec3 vc(vec3 s) { return mix(s / 12.92, pow((s + 0.055) / 1.055, vec3(2.4)), step(0.04045, s)); }
// 特效常有平铺在地上的面片 (例: 疾雷咒 8112_1 落点的溅射, y≈0), 和战场地面共面会深度抖动成一块块白斑:
// 视空间里朝镜头拉近 0.5 个百分点 (15 米处约 7 厘米), 让特效稳定地画在地面上
void vertex() {
	VERTEX = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz * 0.995;
}
void fragment() {
	vec4 c = texture(tex, UV);
	%s
}
""" % [blend, body]
	return sh


static func clear_cache() -> void:
	for n in _tpl.values():
		if n:
			n.free()
	_tpl.clear()
	_variant_cache.clear()
	_tex_cache.clear()


## 程序直接创建的粒子系统 (0x48fc7b(编号, x, y, z) / 0x493634): 发射点固定在 place (Godot 世界坐标)
static func spawn_particles(parent: Node, pid: int, place: Vector3, camera: Camera3D) -> FxEmitter:
	var p: Dictionary = _db.get("_particles", {}).get(str(pid), {})
	if p.is_empty():
		return null
	var em := FxEmitter.new()
	parent.add_child(em)
	em.global_position = place
	em.setup(p, _db.get(str(p.get("visual", "")), {}), _dir, camera)
	em.global_position = place
	return em


static func has(k: String) -> bool:
	return load_db() and _db.has(k)


static func spawn(parent: Node, k: String, place: Vector3, facing: Basis, camera: Camera3D, hit_cb := Callable(),
		as_particle := false) -> Fx:
	if not has(k):
		return null
	var fx := Fx.new()
	fx.key = k
	fx.data = _db[k]
	fx.cam = camera
	fx.on_hit = hit_cb
	fx.particle = as_particle
	parent.add_child(fx)
	fx.global_position = place
	if not fx.data.get("ignore_facing", false):
		fx.global_basis = facing.orthonormalized()
	fx._build()
	fx._apply(0)
	if OS.get_cmdline_user_args().has("--debug-fx"):
		print("FX ", k, " at ", place, " kind=", fx.data.kind, " models=", fx._models.keys(), " ticks=", fx.data.ticks)
	return fx


static func template(rel: String) -> Node3D:
	if not _tpl.has(rel):
		var doc := GLTFDocument.new()
		var st := GLTFState.new()
		if doc.append_from_file(Game.asset_abs(_dir.path_join(rel)), st) != OK:
			_tpl[rel] = null
		else:
			_tpl[rel] = doc.generate_scene(st)
	var n: Node3D = _tpl[rel]
	return n.duplicate() if n else null


static func texture(path: String) -> Texture2D:
	if not _tex_cache.has(path):
		_tex_cache[path] = Game.image_texture(path)   # 高清模式下读 hd 版, 报告原尺寸 (精灵大小不变)
	return _tex_cache[path]


# ---------------- 构建 ----------------

func _build() -> void:
	if data.kind == "model":
		for fr in data.models:
			if data.models[fr] == null:
				continue   # 模型没导出 (例: 5500_5 引用的 15045)
			var m: Dictionary = data.models[fr]
			var n := template(m.glb)
			if n == null:
				continue
			add_child(n)
			n.visible = false
			var ap := n.find_children("*", "AnimationPlayer", true, false)
			var skel := n.find_children("*", "Skeleton3D", true, false)
			var entry := {"node": n, "ap": ap[0] if ap.size() else null, "anim": m.ply,
				"skel": skel[0] if skel.size() else null, "mats": [], "bb": []}
			_setup_materials(n, m, entry)
			if entry.skel:
				for bn in m.get("billboard_nodes", []):
					var bi: int = entry.skel.find_bone(bn)
					if bi >= 0:
						entry.bb.append(bi)
			if entry.ap:
				entry.ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
			_setup_morph(n, m, entry)
			_models[fr] = entry
	else:
		_sprite = Sprite3D.new()
		_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_sprite.shaded = false
		_sprite.double_sided = true
		_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.vertex_color_use_as_albedo = true
		mat.no_depth_test = false
		_sprite.material_override = mat
		add_child(_sprite)
		for fr in data.get("sprites", {}):
			_sprite_frames[fr] = data.sprites[fr]


static var _variant_cache := {}  # glb → {"frames": {动画: [target]}, "meshes": {网格名: [ArrayMesh/target]}}


## 逐帧顶点变形 (含 UV 动画): Godot 的 blend shape 不支持 UV, 改为每个 morph target 一份网格, 按帧换 mesh
## 数据: <glb>.morph.json (tools/ply2gltf.py sidecar), 顶点按 (位置, UV) 对应回 PLY 顶点
## 网格用到哪帧才建 (_morph_mesh): 一次建完全部 target 要几十上百毫秒, 首次放招时整帧卡住
func _setup_morph(n: Node, m: Dictionary, entry: Dictionary) -> void:
	var side_path := _dir.path_join(m.glb + ".morph.json")
	if not FileAccess.file_exists(side_path):
		return
	if not _variant_cache.has(m.glb):
		_variant_cache[m.glb] = {"side": JSON.parse_string(FileAccess.get_file_as_string(side_path)), "meshes": {}, "index": {}}
	var vc: Dictionary = _variant_cache[m.glb]
	entry.morph_frames = vc.side.frames.get(m.ply, [])
	entry.morph_vc = vc
	entry.morph_meshes = []
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var mname := str(mi.name)
		if not vc.meshes.has(mname):
			var list: Array = []
			list.resize(vc.side.targets.size())
			vc.meshes[mname] = list
		entry.morph_meshes.append([mi, mi.mesh, vc.meshes[mname]])
	# 动画里的 blend shape 通道不再需要 (换 mesh 实现)
	if entry.ap and entry.ap.has_animation(m.ply):
		var anim: Animation = entry.ap.get_animation(m.ply)
		for ti in range(anim.get_track_count() - 1, -1, -1):
			if anim.track_get_type(ti) == Animation.TYPE_BLEND_SHAPE:
				anim.remove_track(ti)


static func _morph_mesh(vc: Dictionary, base: Mesh, tg: int) -> ArrayMesh:
	var side: Dictionary = vc.side
	var t: Dictionary = side.targets[tg]
	var am := ArrayMesh.new()
	for si in base.get_surface_count():
		var arr := base.surface_get_arrays(si)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var us: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
		# 顶点对回 PLY 顶点: 优先用导出时写进 UV2.x 的原始下标 (tools/ply2gltf.py TEXCOORD_1);
		# 没有 UV2 的旧模型退回按 (位置, UV) 对 —— 重叠顶点会对错 (破命 18 道地光只剩 1 道)
		var u2: Variant = arr[Mesh.ARRAY_TEX_UV2]
		for vi in vs.size():
			var pi: int = -1
			if u2 != null and vi < (u2 as PackedVector2Array).size():
				pi = int(roundf((u2 as PackedVector2Array)[vi].x * 65535.0))
				if pi >= side.base_pos.size():
					pi = -1
			if pi < 0:
				if vc.index.is_empty():
					for i in side.base_pos.size():
						vc.index[_vkey(side.base_pos[i], side.base_uv[i])] = i
				pi = vc.index.get(_vkey([vs[vi].x, vs[vi].y, vs[vi].z], [us[vi].x, us[vi].y]), -1)
			if pi >= 0:
				var p: Array = t.pos[pi]
				var u: Array = t.uv[pi]
				vs[vi] = Vector3(p[0], p[1], p[2])
				us[vi] = Vector2(u[0], u[1])
		arr[Mesh.ARRAY_VERTEX] = vs
		arr[Mesh.ARRAY_TEX_UV] = us
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return am


static func _vkey(p: Array, u: Array) -> String:
	return "%.1f,%.1f,%.1f|%.3f,%.3f" % [p[0], p[1], p[2], u[0], u[1]]


## 混合方式 = (PLY 材质组 flags | 当前 tick 的 XF) 低 4 位 (exe 0x41676c, 逆向确认):
##   0 不透明 (ONE, ZERO, 写深度); 1 加法 (SRCALPHA, ONE); 2 普通 (SRCALPHA, INVSRCALPHA);
##   4 (INVDESTALPHA, INVSRCCOLOR): 后台缓冲没有 alpha 通道 → 目标 alpha 读作 1, 源项为 0 → 结果 = 目标 × (1 − 源色);
##   8 (SRCCOLOR, INVSRCCOLOR): 结果 = 源色² + 目标 × (1 − 源色) (两遍: 乘 1−源 再加 源²);
##   其他值 (3, 5, 6, 7, 9–15) 原版不处理、沿用上一次的状态 —— 定不下来, 这里按含 1 → 加法、含 2 → 普通 画
## 每个面预建所需的材质, XF 变化时 (例: 应龙黑龙 8109_39 第 96 tick 起 XF=1 转为加法淡出) 换材质
func _setup_materials(n: Node, m: Dictionary, entry: Dictionary) -> void:
	var groups: Array = m.get("materials", [])
	entry.surfs = []
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (mi as MeshInstance3D).mesh
		for s in mesh.get_surface_count():
			var src := mesh.surface_get_material(s)
			var tex: Texture2D = (src as BaseMaterial3D).albedo_texture if src is BaseMaterial3D else null
			var flags: int = int(groups[s].flags) if s < groups.size() else 1
			var sf := {"mi": mi, "s": s, "flags": flags, "tex": tex, "mats": {}, "mode": -1}
			entry.surfs.append(sf)
			_surf_mode(sf, 0, entry)


static func _blend_mode(v: int) -> int:
	v &= 0xF
	if v == 0:
		return 0
	if v == 4 or v == 8:
		return v
	if v & 1:
		return 1
	if v & 2:
		return 2
	return 1


func _surf_mode(sf: Dictionary, xf: int, entry: Dictionary) -> void:
	var mode := _blend_mode(int(sf.flags) | xf)
	if mode == sf.mode:
		return
	sf.mode = mode
	if not sf.mats.has(mode):
		var mat: Material
		if mode == 0:
			var sm := StandardMaterial3D.new()
			sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			sm.albedo_texture = sf.tex
			sm.vertex_color_use_as_albedo = true   # 贴图 × 顶点色
			sm.vertex_color_is_srgb = true   # 顶点色按字节相乘 (同着色器里的 vc)
			# 普通层: 原版 = 色键 (贴图纯黑透明, 导出时转成 alpha 0), 用 alpha 测试裁掉; 不然千羽的箭带一块黑底 (用户反馈)
			sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			sm.alpha_scissor_threshold = 0.5
			sm.cull_mode = BaseMaterial3D.CULL_DISABLED
			mat = sm
		else:
			var sh := ShaderMaterial.new()
			sh.shader = _shader_add if mode == 1 else (_shader_invmul if mode in [4, 8] else _shader_mix)
			if mode == 8:
				var sh2 := ShaderMaterial.new()
				sh2.shader = _shader_sqadd
				sh2.set_shader_parameter("tex", sf.tex)
				sh.next_pass = sh2
			sh.set_shader_parameter("tex", sf.tex)
			sh.set_shader_parameter("boost", Enhance.fx_boost())
			mat = sh
		sf.mats[mode] = mat
		entry.mats.append(mat)
	(sf.mi as MeshInstance3D).set_surface_override_material(int(sf.s), sf.mats[mode])


# ---------------- 播放 ----------------

func _track(name: String, tick: int, default: Variant) -> Variant:
	var tr: Array = data.tracks.get(name, [])
	var v: Variant = default
	for e in tr:
		if int(e[0]) <= tick:
			v = e[1]
		else:
			break
	return v


## 从第 0 帧重播 (下雪的雪花重生时, 0x491707)
func restart() -> void:
	t = 0.0


func _process(delta: float) -> void:
	t += delta
	var tick := int(t / TICK)
	var total: int = int(data.ticks)
	if loop_forever and tick >= total:
		# 地图动画 / 标题竹叶: 循环动作一直播, 直到被 del_ani 删掉
		t = fmod(t, total * TICK)
		tick = int(t / TICK)
	if particle:
		if tick >= total:
			t = fmod(t, total * TICK)
			tick = int(t / TICK)
		if tick != _last_tick:
			_apply(tick)
		_billboard()
		return
	var linger: int = int(data.get("linger_ticks", 25))
	if tick != _last_tick:
		_apply(mini(tick, total - 1))
		for ev_i in data.events.size():
			var ev: Dictionary = data.events[ev_i]
			if not _events_done.has(ev_i) and int(ev.tick) <= tick:
				_events_done[ev_i] = true
				_event(ev)
	_emitters = _emitters.filter(func(em): return is_instance_valid(em))
	if tick >= total:
		for em in _emitters:
			em.emitting = false
	_billboard()
	var alive := false
	for em in _emitters:
		if em.alive():
			alive = true
	if hold_last:
		pass
	elif tick >= total + linger and not alive:
		queue_free()
	elif tick >= total + linger:
		for e in _models.values():
			e.node.visible = false
		if _sprite:
			_sprite.visible = false


func _apply(tick: int) -> void:
	_last_tick = tick
	var fr := str(int(_track("fr", tick, 0)))
	var frame := int(_track("frame", tick, 0))
	var col: Array = _track("color", tick, [255, 255, 255, 255])
	var sc: Array = _track("scale", tick, [1, 1, 1])
	var rot: Array = _track("rot", tick, [0, 0, 0])
	var off: Array = _track("offset", tick, [0, 0, 0])
	var xflag := int(_track("xf", tick, 0))
	var tint := Color(col[1] / 255.0, col[2] / 255.0, col[3] / 255.0, col[0] / 255.0) * particle_mod
	var scale_v := Vector3(sc[0], sc[1], sc[2]) + Vector3.ONE * particle_size
	var basis := Basis.from_euler(Vector3(deg_to_rad(rot[0]), deg_to_rad(rot[1]), deg_to_rad(rot[2])))
	var xf := Transform3D(basis * Basis.from_scale(scale_v), basis * (Vector3(off[0], off[1], -off[2]) * U * scale_v))
	if data.kind == "model":
		for k in _models:
			var e: Dictionary = _models[k]
			e.node.visible = (k == fr)
			if k != fr:
				continue
			e.node.transform = xf
			for sf in e.surfs:
				_surf_mode(sf, xflag, e)
			if e.ap and e.ap.has_animation(e.anim):
				if e.ap.current_animation != e.anim:
					e.ap.play(e.anim)
					e.ap.pause()
				e.ap.seek(frame * CLIP_TICK, true)
			if e.has("morph_frames") and e.morph_frames.size():
				var tg: int = int(e.morph_frames[clampi(frame, 0, e.morph_frames.size() - 1)])
				for mm in e.morph_meshes:
					var variants: Array = mm[2]
					if tg < 0 or tg >= variants.size():
						mm[0].mesh = mm[1]
						continue
					if variants[tg] == null:
						variants[tg] = _morph_mesh(e.morph_vc, mm[1], tg)
					mm[0].mesh = variants[tg]
			for mat in e.mats:
				if mat is ShaderMaterial:
					mat.set_shader_parameter("tint", tint)
					if mat.next_pass is ShaderMaterial:
						(mat.next_pass as ShaderMaterial).set_shader_parameter("tint", tint)
				else:
					(mat as StandardMaterial3D).albedo_color = tint
	elif _sprite:
		var sp: Dictionary = _sprite_frames.get(fr, {})
		var frames: Array = sp.get("frames", [])
		if frames.size():
			var path: String = _dir.path_join(frames[clampi(frame, 0, frames.size() - 1)])
			_sprite.texture = texture(path)
		_sprite.transform = xf
		_sprite.modulate = tint
		_sprite.pixel_size = U


func _billboard() -> void:
	if cam == null:
		return
	for e in _models.values():
		if not e.node.visible or e.bb.is_empty() or e.skel == null:
			continue
		# 原版 (0x416a07, 段 flags 0x100000): 骨骼矩阵整个换成 视图矩阵的逆 (只留骨骼自己的平移), 再照常乘世界矩阵
		# (0x41332f, 同普通骨骼的 骨骼 → 世界 顺序)。所以: 世界的旋转 / 缩放 (粒子自转、粒子尺寸、施术者朝向) 照样作用,
		# 骨骼自己的旋转 / 缩放动画被丢掉。以前反算世界旋转让面片永远正对镜头、又保留骨骼缩放:
		# 七曜使者的斗气 (8009 → 粒子 79 → 气团 8005_87) 变成一团团正面的大火球, 原版是随自转侧过来的斜金带
		var skel: Skeleton3D = e.skel
		var cb := cam.global_transform.basis.orthonormalized()
		for bi in e.bb:
			var gp := skel.get_bone_global_pose(bi)
			skel.set_bone_global_pose(bi, Transform3D(cb, gp.origin))


func _exit_tree() -> void:
	if OS.get_cmdline_user_args().has("--trace-fx"):
		print("FX_FREE %s f=%d t=%.2f emitters=%d" % [key, Engine.get_process_frames(), t, _emitters.size()])


func _event(ev: Dictionary) -> void:
	match ev.type:
		"sound":
			# ACT 的 VW 标签: 这一帧放音效 (0x41d1e3 → 0x4bec87)。命中光效、技能特效的声音都在这里 (585 个特效里 384 个带声音)。
			# 粒子系统里每个粒子也是一个特效实例, 原版是否每个都出声没核对, 先只让主特效出声, 免得几十个粒子同时响
			if not particle:
				Game.play_sound(int(ev.id))
				if OS.get_cmdline_user_args().has("--trace-events"):
					print("FXSND %s sound=%d" % [key, int(ev.id)])
		"hit":
			# 'd' = 完整结算一次伤害, 'e' = 只播受击反应 (0x443cd8 的 0x80000000 / 0x40000000)
			if on_hit.is_valid():
				on_hit.call(str(ev.get("kind", "d")))
		"emit":
			var p: Dictionary = _db.get("_particles", {}).get(str(int(ev.particle)), {})
			if p.is_empty():
				return
			var em := FxEmitter.new()
			# 先挂锚点、加进场景再 setup: 一次性 (非连续) 的发射器在 setup 里就把粒子全部生成,
			# 之前顺序反了, 生成时还没有锚点也不在场景里, 粒子全出现在世界原点
			em.anchor = _marker_node(int(ev.slot))
			em.anchor_local = _marker_local(int(ev.slot))
			em.stop_tick = int(ev.get("stop_frame", 0))
			em.owner_fx = self
			add_child(em)
			if OS.get_cmdline_user_args().has("--trace-fx"):
				print("FX_EMIT %s particle=%s f=%d" % [key, str(ev.get("particle")), Engine.get_process_frames()])
			em.setup(p, _db.get(p.get("visual", ""), {}), _dir, cam)
			_emitters.append(em)


func _marker_node(slot: int) -> Node3D:
	var fr := str(int(_track("fr", _last_tick, 0)))
	var e: Dictionary = _models.get(fr, {})
	if e.is_empty():
		return self
	var m: Dictionary = data.models[fr]
	var mk: Dictionary = m.get("markers", {}).get(str(slot + 1), {})
	if mk.is_empty() or e.skel == null:
		return e.node
	var bi: int = e.skel.find_bone(mk.node)
	if bi < 0:
		return e.node
	var ba := BoneAttachment3D.new()
	e.skel.add_child(ba)
	ba.bone_idx = bi
	return ba


func _marker_local(slot: int) -> Vector3:
	var fr := str(int(_track("fr", _last_tick, 0)))
	var m: Dictionary = data.models.get(fr, {})
	var mk: Dictionary = m.get("markers", {}).get(str(slot + 1), {})
	var l: Array = mk.get("local", [0, 0, 0])
	return Vector3(l[0], l[1], l[2])


func current_frame() -> int:
	return int(_track("frame", _last_tick, 0))


## 原版 0x53 wait_effect 等特效播到第 n 帧 (n=0 等结束); 0x05 等结束
func reached(frame: int) -> bool:
	if frame <= 0:
		return _last_tick >= int(data.ticks) - 1
	return current_frame() >= frame or _last_tick >= int(data.ticks) - 1
