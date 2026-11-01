class_name TitleLeaves
extends TextureRect
## 标题画面飘落的竹叶 (原版 0x4709a9 里 0x470b53–0x470d23 建两套「雪花」粒子, 类 vtable 0x4ce040; 全部逆向确认):
##   * 两套都是 6 片, ACT 8001 动作 5 / 动作 6 (模型 MGC00326, 动作 6 带 OC 染色), 中心 (100, 200, 100),
##     宽 1000、深 600、地面 −300; 速度参数 0x491668(1.0, 0.05, 0.05)
##   * 重生 0x491707 (每个分量各取一次 r = rand()%1000 × 0.001):
##       位置 = (cx + (r−0.5)·宽, cy, cz + (r−0.5)·深); 速度 (单位/毫秒) = (r·SX − B, −(1+r)·VY, r·SZ − B), 没有加速度
##       B = 0.05 + 0.0005, VY = 0.05 + 0.0049, b' = 0.05 + 0.001, SX = sin(1°)·b' + 0.001, SZ = −cos(1°)·b' + 0.001
##       ACT 实例清零重建 → 动画从头播, 朝向 / 缩放全部来自 ACT 本身 (粒子不加旋转)
##   * 更新 0x49193c: 位置 += 速度 × 帧间真实毫秒; y < 地面 (严格小于) 就重生
##   * 初始摆放 0x491531 也是逐片调用重生 (都从 y = 200 出发), 随后预跑 1501 次 update(10) = 15.01 秒 (预跑时不画, 动画不走)
##   * 绘制前关雾, 每次绘制 ACT 走一步
## 原版左手系: 画面水平翻转显示 (同地图 / 战斗)
## 镜头: 原版 0x4705dd 写距离 910 等参数, 但各字段如何进投影这里没逐一核实 —— 沿用「距离 910、正对粒子中心」(待核实)
## 用法: add_child(TitleLeaves.new()) — 全屏透明层, 不接收鼠标

const COUNT := 6
const CENTER := Vector3(100, 200, 100)
const WIDTH := 1000.0
const DEPTH := 600.0
const FLOOR := -300.0
const B := 0.05 + 0.0005
const VY := 0.05 + 0.0049
const SX := 0.051 * 0.017452406 + 0.001      # sin(1°)·b' + 0.001
const SZ := -0.051 * 0.999847695 + 0.001     # −cos(1°)·b' + 0.001
const PREWARM_STEPS := 1501
const PREWARM_DT := 10.0

var _vp: SubViewport
var _cam: Camera3D
var _leaves: Array = []                   # [{fx, pos, vel}]


func _ready() -> void:
	position = Vector2.ZERO
	size = Vector2(800, 600)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vp = SubViewport.new()
	_vp.transparent_bg = true
	_vp.own_world_3d = true
	_vp.size = Vector2i(800, 600) * 2
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	texture = _vp.get_texture()
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_SCALE
	flip_h = true
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	# 原版标题镜头距离 910 (0x4705f8 写入 [0xa851f8] = 910.0), 正对中心
	_cam = Camera3D.new()
	_cam.fov = 33.4
	_cam.near = 0.5
	_cam.far = 100.0
	_vp.add_child(_cam)
	_cam.position = to_w(CENTER + Vector3(0, 0, -910))
	_cam.look_at(to_w(CENTER), Vector3.UP)
	if not Fx.has("8001_5"):
		return
	for k in COUNT * 2:
		var key := "8001_5" if k < COUNT else "8001_6"
		var fx := Fx.spawn(_vp, key, Vector3.ZERO, Basis.IDENTITY, _cam)
		if fx == null:
			continue
		fx.loop_forever = true
		_key_black(fx)
		var e := {"fx": fx, "pos": Vector3.ZERO, "vel": Vector3.ZERO}
		_respawn(e)
		_leaves.append(e)
	# 预跑 15.01 秒 (原版两套交替 update(10), 不绘制 → 动画不推进)
	for i in PREWARM_STEPS:
		for e in _leaves:
			_step(e, PREWARM_DT)
	for e in _leaves:
		if is_instance_valid(e.fx):
			(e.fx as Fx).global_position = to_w(e.pos)


## 落叶贴图 (落葉.bmp) 是黑底, 原版按色键把黑色当透明: 换成丢弃透明 / 近黑像素的材质 (动作 6 保留染色)
## 导出的贴图已把色键区设成 alpha 0, 但这些像素的 RGB 是绿色 —— 只看颜色不看 alpha 会露出绿色色块
static var _shader: Shader


func _key_black(fx: Fx) -> void:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform vec4 tint = vec4(1.0);
void fragment() {
	vec4 c = texture(tex, UV);
	if (c.a < 0.5 || max(c.r, max(c.g, c.b)) < 0.08) discard;
	ALBEDO = c.rgb * tint.rgb;
}
"""
	var tint := Color.WHITE
	if fx.key == "8001_6":
		tint = Color8(100, 200, 160)   # OC = ARGB (255, 100, 200, 160)
	for mi in fx.find_children("*", "MeshInstance3D", true, false):
		var m3 := mi as MeshInstance3D
		for si in m3.mesh.get_surface_count():
			var src := m3.get_active_material(si)
			var t: Texture2D = (src as BaseMaterial3D).albedo_texture if src is BaseMaterial3D else null
			if t == null and src is ShaderMaterial:
				t = (src as ShaderMaterial).get_shader_parameter("tex")
			var sm := ShaderMaterial.new()
			sm.shader = _shader
			sm.set_shader_parameter("tex", t)
			sm.set_shader_parameter("tint", tint)
			m3.set_surface_override_material(si, sm)


func to_w(g: Vector3) -> Vector3:
	return g * 0.01


func _r() -> float:
	return float(randi() % 1000) * 0.001


func _respawn(e: Dictionary) -> void:
	e.pos = Vector3(CENTER.x + (_r() - 0.5) * WIDTH, CENTER.y, CENTER.z + (_r() - 0.5) * DEPTH)
	e.vel = Vector3(_r() * SX - B, -(1.0 + _r()) * VY, _r() * SZ - B)
	var fx: Fx = e.fx
	if is_instance_valid(fx):
		fx.restart()


func _step(e: Dictionary, ms: float) -> void:
	e.pos += e.vel * ms
	if e.pos.y < FLOOR:
		_respawn(e)


func _process(delta: float) -> void:
	var ms := float(int(delta * 1000.0))   # 原版传整数毫秒 [0x9f74c4]
	for e in _leaves:
		_step(e, ms)
		var fx: Fx = e.fx
		if is_instance_valid(fx):
			fx.global_position = to_w(e.pos)
