class_name Enhance
## 画面增强 (偏离原版的可选效果, 设定里开关, 默认关 = 原版画面)
## 第一档: 只做后期, 不动材质 —— 原版的光影是画在贴图 / 顶点色里的, 加实时光会和它叠成两层
##   泛光: 只让技能光效发光 —— 增强时加法光效的亮度乘 FX_BOOST 推到 1.0 以上, 泛光阈值 1.0, 白衣服、天空等贴图 (≤1) 不受影响
##   调色: 对比度 / 饱和度略提; 暗角: 画面四角压暗

const FX_BOOST := 1.3


static func on() -> bool:
	var args := OS.get_cmdline_user_args()
	if args.has("--no-enhance"):
		return false
	return args.has("--enhance") or bool(Game.get_setting("video", "enhance", false))


## 光效亮度倍数 (fx.gd 的加法着色器用)
static func fx_boost() -> float:
	return FX_BOOST if on() else 1.0


static func apply(env: Environment, rect: TextureRect) -> void:
	if not on():
		return
	env.glow_enabled = true
	env.glow_normalized = true
	for i in 7:
		env.set_glow_level(i, i in [1, 2, 3, 4])
	env.glow_intensity = 0.7
	env.glow_strength = 1.0
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.0
	env.glow_hdr_scale = 2.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 1.12
	env.adjustment_brightness = 1.0
	if rect:
		var sh := Shader.new()
		sh.code = """shader_type canvas_item;
uniform float vignette = 0.35;
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	vec2 d = UV - vec2(0.5);
	float v = 1.0 - vignette * smoothstep(0.35, 0.85, length(d * vec2(1.0, 0.9)) * 1.25);
	COLOR = vec4(c.rgb * v, c.a);
}
"""
		var m := ShaderMaterial.new()
		m.shader = sh
		rect.material = m


# ---------------- 第二档: 人物光照 + 投影 ----------------
## 不替换原材质 (表情换脸、淡入淡出都直接改原材质), 而是给每个面加渲染通道 (next_pass):
##   人物: 乘法通道 = 方向光明暗 (向光面略亮、背光面略暗) + 加法通道 = 轮廓光
##   场景: 乘法通道走光照, 只取阴影 —— 环境光 0.65 + 主光 0.35 × 阴影 → 没被挡住时 ×1.0 (= 原版), 影子里 ×0.65
## 只有人物投影; 场景模型不投影 (原版贴图里已经画了建筑的阴影, 再投一次会叠成两层)

const SUN_DIR := Vector3(0.45, -0.8, 0.4)   # 世界坐标下光照方向 (从上方斜照)
const SHADOW_K := 0.5

static var _sh_actor_mul: Shader
static var _sh_actor_rim: Shader
static var _sh_world: Shader
static var _sh_world_cull: Shader   # 场景面剔除背面时 (unshade cull=true), 附加通道也要剔除, 不然背面看不见的面会被画出来


static func _shaders() -> void:
	if _sh_actor_mul:
		return
	_sh_actor_mul = Shader.new()
	_sh_actor_mul.code = """shader_type spatial;
render_mode unshaded, blend_mul, depth_draw_never, cull_disabled, fog_disabled;
uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform bool cutout = false;
uniform vec3 sun_dir;
void fragment() {
	if (cutout && texture(tex, UV).a < 0.5) discard;
	vec3 l = normalize((VIEW_MATRIX * vec4(-sun_dir, 0.0)).xyz);
	float w = dot(NORMAL, l) * 0.5 + 0.5;
	ALBEDO = vec3(mix(0.74, 1.1, w));
}
"""
	_sh_actor_rim = Shader.new()
	_sh_actor_rim.code = """shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled;
uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform bool cutout = false;
uniform vec3 rim_color = vec3(1.0, 0.92, 0.8);
uniform float rim = 0.6;
void fragment() {
	vec4 c = texture(tex, UV);
	if (cutout && c.a < 0.5) discard;
	// 导出的模型做过左右翻转, 法线朝向不统一: 用夹角的绝对值
	// 轮廓光按贴图颜色加 (深色头发只略提亮, 浅色衣服边缘才明显; 有的发型法线大多朝侧面, 加纯色会整片发灰)
	float f = pow(1.0 - abs(dot(NORMAL, VIEW)), 3.0);
	ALBEDO = c.rgb * rim_color * f * rim;
}
"""
	_sh_world = Shader.new()
	_sh_world.code = """shader_type spatial;
render_mode blend_mul, depth_draw_never, CULL, fog_disabled, specular_disabled;
uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform bool cutout = false;
uniform float k = 0.35;
void fragment() {
	if (cutout && texture(tex, UV).a < 0.5) discard;
	ALBEDO = vec3(1.0);
}
void light() {
	DIFFUSE_LIGHT += vec3(ATTENUATION * k);
}
"""
	_sh_world_cull = Shader.new()
	_sh_world_cull.code = _sh_world.code.replace("CULL", "cull_back")
	_sh_world.code = _sh_world.code.replace("CULL", "cull_disabled")


static func _cutout(sm: StandardMaterial3D) -> bool:
	return sm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED


## 人物 (FieldActor 的模型 / 手持物): 明暗 + 轮廓光, 投影
static func light_actor(root: Node) -> void:
	if not on():
		return
	_shaders()
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		for s in mi.mesh.get_surface_count():
			var sm := mi.get_surface_override_material(s) as StandardMaterial3D
			if sm == null or sm.blend_mode == BaseMaterial3D.BLEND_MODE_ADD or sm.next_pass:
				continue
			var mul := ShaderMaterial.new()
			mul.shader = _sh_actor_mul
			mul.set_shader_parameter("tex", sm.albedo_texture)
			mul.set_shader_parameter("cutout", _cutout(sm))
			mul.set_shader_parameter("sun_dir", SUN_DIR.normalized())
			var rim := ShaderMaterial.new()
			rim.shader = _sh_actor_rim
			rim.set_shader_parameter("tex", sm.albedo_texture)
			rim.set_shader_parameter("cutout", _cutout(sm))
			# 轮廓光去掉: 远处的小面 (NPC、地图物件的屋脊等) 法线和视线夹角每帧微变, 轮廓光一闪一闪 (用户反馈「远处 NPC 身上有闪烁的光点」);
			# 关掉后闪烁像素 17000 → 33。着色器留着, 以后要用得按距离淡出
			if OS.get_cmdline_user_args().has("--enh-rim"):
				mul.next_pass = rim
			sm.next_pass = mul


## 场景: 接收人物的影子, 自己不投影
static func light_world(root: Node) -> void:
	if not on():
		return
	_shaders()
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for s in mi.mesh.get_surface_count():
			var sm := mi.get_surface_override_material(s) as StandardMaterial3D
			if sm == null or sm.blend_mode == BaseMaterial3D.BLEND_MODE_ADD or sm.next_pass:
				continue
			if sm.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA:   # 半透明面: 底下的面已经接了影子, 再乘一遍影子会过重
				continue
			var w := ShaderMaterial.new()
			w.shader = _sh_world_cull if sm.cull_mode == BaseMaterial3D.CULL_BACK else _sh_world
			w.set_shader_parameter("tex", sm.albedo_texture)
			w.set_shader_parameter("cutout", _cutout(sm))
			w.set_shader_parameter("k", _world_k)
			_world_mats.append(w)
			sm.next_pass = w


## 主光 (只用来产生影子) + 环境光 1 − k
static func add_sun(parent: Node, env: Environment, max_dist := 40.0) -> void:
	if not on():
		return
	env.ambient_light_energy = 1.0 - SHADOW_K
	var sun := DirectionalLight3D.new()
	sun.name = "EnhanceSun"
	sun.shadow_enabled = not OS.get_cmdline_user_args().has("--enh-no-shadow")
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = max_dist
	sun.shadow_blur = 2.0
	sun.light_energy = 1.0
	sun.basis = Basis.looking_at(SUN_DIR.normalized(), Vector3.UP)
	parent.add_child(sun)


# ---------------- 第三档: 按地图类型的氛围 (光照方向 / 环境粒子 / 调色) + 水面闪光 ----------------
## 地图类型取 maps.json 名字的第二段 (户外 / 城镇 / 地图 / 室内 / 迷宫 / 剧情); 名字带「夜」的按夜景
## 光照方向原版没有数据 (阴影画在贴图里), 按类型给一个大致方向: 户外太阳偏高偏西, 室内几乎正上方 (窗光),
## 迷宫光很弱 (影子也淡); 个别地图对不上时在 OVERRIDE 里单独写

const PRESETS := {
	"day":    {"sun": Vector3(0.45, -0.8, 0.4), "shadow": 0.5, "motes": "pollen", "tint": Color(1.03, 1.0, 0.95)},
	"indoor": {"sun": Vector3(0.2, -1.0, 0.25), "shadow": 0.4, "motes": "dust", "tint": Color(1.04, 1.0, 0.94)},
	"cave":   {"sun": Vector3(0.1, -1.0, 0.1), "shadow": 0.3, "motes": "dust_dim", "tint": Color(0.96, 0.98, 1.04)},
	"night":  {"sun": Vector3(-0.3, -0.8, 0.5), "shadow": 0.35, "motes": "firefly", "tint": Color(0.92, 0.96, 1.08)},
}
## 地图号 → 预设名 / 覆盖字段 (名字分类对不上的: 竹林、断崖、木甲工房一带的「迷宫」其实在户外; 研究石室是室内)
const OVERRIDE := {12603: "day", 12607: "day", 12602: "day", 12606: "day", 12605: "indoor"}


static func preset_of(map_id: int, info: Dictionary) -> Dictionary:
	var name := str(info.get("name", ""))
	var kind := name.get_slice("_", 1)
	var key := "day"
	if name.contains("夜"):
		key = "night"
	elif kind == "室内":
		key = "indoor"
	elif kind == "迷宫" or name.contains("密道") or name.contains("洞"):
		key = "cave"
	var p: Dictionary = PRESETS[key].duplicate()
	p["key"] = key
	var o: Variant = OVERRIDE.get(map_id)
	if o is String:
		p = PRESETS[o].duplicate()
		p["key"] = o
	elif o is Dictionary:
		p.merge(o, true)
	return p


static var _dot_tex: Texture2D


static func _dot() -> Texture2D:
	if _dot_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(0.5, 0.0)
		t.width = 64
		t.height = 64
		_dot_tex = t
	return _dot_tex


## 环境粒子: 跟着镜头注视点的一个盒子 (16×7×16 米) 里慢慢飘
static func make_motes(kind: String) -> GPUParticles3D:
	var cfg := {
		"pollen":   {"n": 110, "size": 0.14, "col": Color(1.5, 1.35, 0.9, 0.6), "vel": Vector3(0.12, 0.05, 0.08), "life": 9.0},
		"dust":     {"n": 140, "size": 0.09, "col": Color(1.3, 1.2, 1.0, 0.45), "vel": Vector3(0.04, 0.02, 0.04), "life": 10.0},
		"dust_dim": {"n": 90, "size": 0.09, "col": Color(0.9, 1.0, 1.2, 0.4), "vel": Vector3(0.03, 0.015, 0.03), "life": 10.0},
		"firefly":  {"n": 40, "size": 0.16, "col": Color(1.4, 2.2, 0.9, 0.9), "vel": Vector3(0.25, 0.15, 0.25), "life": 6.0},
	}
	var c: Dictionary = cfg.get(kind, {})
	if c.is_empty():
		return null
	var p := GPUParticles3D.new()
	p.name = "EnhanceMotes"
	p.amount = int(c.n)
	p.lifetime = float(c.life)
	p.preprocess = float(c.life)
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-10, -5, -10), Vector3(20, 10, 20))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(8, 3.5, 8)
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = (c.vel as Vector3).length()
	pm.gravity = Vector3.ZERO
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	pm.turbulence_noise_speed_random = 0.2
	pm.turbulence_influence_min = 0.05
	pm.turbulence_influence_max = 0.15
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	var fade := Gradient.new()   # 出生淡入、消失淡出
	fade.set_color(0, Color(1, 1, 1, 0))
	fade.set_color(1, Color(1, 1, 1, 0))
	fade.add_point(0.2, Color(1, 1, 1, 1))
	fade.add_point(0.8, Color(1, 1, 1, 1))
	var ft := GradientTexture1D.new()
	ft.gradient = fade
	pm.color_ramp = ft
	if kind == "firefly":
		pm.alpha_curve = null
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(float(c.size), float(c.size))
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _dot()
	m.albedo_color = c.col
	m.no_depth_test = false
	m.disable_fog = true
	q.material = m
	p.draw_pass_1 = q
	return p


## 进图时调用: 换主光方向 / 阴影强度, 放环境粒子, 调色微调; 返回粒子节点 (每帧移到注视点)
static func setup_map(world: Node3D, env: Environment, map_id: int, info: Dictionary, old_motes: Node) -> Node3D:
	if is_instance_valid(old_motes):
		old_motes.queue_free()
	if not on():
		return null
	var p := preset_of(map_id, info)
	var sun := world.get_node_or_null("EnhanceSun") as DirectionalLight3D
	if sun:
		sun.basis = Basis.looking_at((p.sun as Vector3).normalized(), Vector3.UP)
	env.ambient_light_energy = 1.0 - float(p.shadow)
	_world_k = float(p.shadow)
	for mat in _world_mats:
		if is_instance_valid(mat):
			(mat as ShaderMaterial).set_shader_parameter("k", _world_k)
	_world_mats.clear()
	# 冷暖: 1D 查找表从黑到 tint (各通道归一到 ≤1, 多出的部分给亮度)
	var t: Color = p.tint
	var mx := maxf(t.r, maxf(t.g, t.b))
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0))
	g.set_color(1, Color(t.r / mx, t.g / mx, t.b / mx))
	var lut := GradientTexture1D.new()
	lut.gradient = g
	env.adjustment_color_correction = lut
	env.adjustment_brightness = mx
	# 环境粒子 (花粉 / 灰尘 / 萤火虫) 按用户要求去掉: 满屏飘的光点太干扰; make_motes 保留备用
	return null


static var _world_k := SHADOW_K
static var _world_mats: Array = []


## 水面闪光: 原版做了贴图流动 (uv_anim) 的面 = 水 / 瀑布, 加一层加法通道: 随视角变化的高光 + 细碎闪烁
static var _sh_water: Shader
static var _sh_water_cull: Shader


static func water(mats: Array) -> void:
	if not on():
		return
	if _sh_water == null:
		_sh_water = Shader.new()
		_sh_water.code = """shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, CULL, fog_disabled;
uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 uv_off = vec3(0.0);
uniform float alpha = 1.0;
uniform float use_va = 0.0;   // 半透明水面 (WLD 模式 2): 闪光也乘顶点 alpha
float h(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float n(vec2 p) {
	vec2 i = floor(p), f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h(i), h(i + vec2(1, 0)), f.x), mix(h(i + vec2(0, 1)), h(i + vec2(1, 1)), f.x), f.y);
}
void fragment() {
	vec4 ct = texture(tex, UV + uv_off.xy);
	vec3 c = ct.rgb;
	float fres = pow(1.0 - abs(dot(NORMAL, VIEW)), 2.0);
	vec2 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xz;
	float spark = smoothstep(0.78, 0.95, n(wp * 9.0 + vec2(TIME * 0.7, TIME * 0.4)) * n(wp * 5.0 - TIME * 0.3));
	float lum = dot(c, vec3(0.3, 0.6, 0.1));
	// 乘贴图 alpha: 有的水面原版是半透明 / 几乎看不见的 (例: 竹林 12603 山坡后的河), 不能凭空画出一片
	ALBEDO = vec3(0.85, 0.95, 1.0) * (fres * 0.18 + spark * 0.55) * (0.4 + lum) * ct.a * alpha * mix(1.0, COLOR.a, use_va);
}
"""
		_sh_water_cull = Shader.new()
		_sh_water_cull.code = _sh_water.code.replace("CULL", "cull_back")
		_sh_water.code = _sh_water.code.replace("CULL", "cull_disabled")
	for m in mats:
		var sm := m as StandardMaterial3D
		if sm == null or sm.blend_mode == BaseMaterial3D.BLEND_MODE_ADD or not _is_water(sm.albedo_texture):
			continue
		var w := ShaderMaterial.new()
		w.shader = _sh_water_cull if sm.cull_mode == BaseMaterial3D.CULL_BACK else _sh_water
		w.set_shader_parameter("tex", sm.albedo_texture)
		w.set_shader_parameter("alpha", sm.albedo_color.a if sm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED else 1.0)
		w.set_shader_parameter("use_va", 1.0 if sm.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA else 0.0)
		# 接在已有通道链的最后
		var last: Material = sm
		while last.next_pass:
			last = last.next_pass
		last.next_pass = w
		sm.set_meta("water_pass", w)


## 流动贴图不只是水: 还有烛火 (加法, 黑底)、泥流 / 熔岩 (棕色)、云。按贴图平均色挑出水: 偏蓝或偏白
static func _is_water(t: Texture2D) -> bool:
	if t == null:
		return false
	var img := t.get_image()
	if img == null:
		return false
	img = img.duplicate() as Image
	if img.is_compressed():
		img.decompress()
	img.resize(8, 8, Image.INTERPOLATE_BILINEAR)
	var c := Color(0, 0, 0)
	for y in 8:
		for x in 8:
			c += img.get_pixel(x, y)
	c /= 64.0
	return c.b >= c.r * 1.05 and c.get_luminance() > 0.25 and c.a > 0.3   # 偏蓝 (白色的云海 / 雾不算)


static func water_tick(mats: Array, off: Vector3) -> void:
	for m in mats:
		if not (m as Material).has_meta("water_pass"):   # get_meta 的默认值给 null 等于没给, 会报错
			continue
		var w: Variant = (m as Material).get_meta("water_pass")
		if w:
			(w as ShaderMaterial).set_shader_parameter("uv_off", off)


# ---------------- 景深 ----------------
## 只模糊远景: 焦点 = 镜头到注视点的距离 (主角), 往后 FAR_START 米开始糊, FAR_RAMP 米内过渡到最糊
const FAR_START := 6.0
const FAR_RAMP := 18.0


static func add_dof(camera: Camera3D, focus_m := 12.5) -> void:
	if not on():
		return
	var ca := CameraAttributesPractical.new()
	ca.dof_blur_far_enabled = true
	ca.dof_blur_far_distance = focus_m + FAR_START
	ca.dof_blur_far_transition = FAR_RAMP
	ca.dof_blur_amount = 0.08
	camera.attributes = ca


static func update_dof(camera: Camera3D, focus_m: float) -> void:
	var ca := camera.attributes as CameraAttributesPractical
	if ca:
		ca.dof_blur_far_distance = focus_m + FAR_START

