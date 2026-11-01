class_name OrigFog
extends MeshInstance3D
## 原版顶点雾 (0x4146bb 设置, 0x412d09 参数, 0x412d6e 逐顶点; 逆向确认):
##   参数 p0..p5 (地图 MAP 头 +0x56 / 战场记录开头 / 天书常量): 颜色 = (p0, p1, p2) (×255 截断), p4 ≤ 0 = 不开雾;
##   s = p3 / p4, off = 1.01 − p5; 投影深度 sz = Q·(1 − N/z), Q = F/(F − N), N = 200, F = 视距, z = 视空间深度 (游戏单位);
##   v = sz − off; s < v < 1 时雾量 = (v − s)/(1 − s), 否则无雾 —— 双曲线 a − b/z
## 这里用全屏四边形读深度缓冲逐像素算 (原版逐顶点算后 Gouraud 插值, 大三角形内部会有细微差别);
## 没画东西的像素 (清屏底色) 不加雾 (原版底色四边形不受雾影响); 以前用 Godot 深度雾按指数曲线拟合, 不精确

const N := 200.0

static var _shader: Shader


func _init() -> void:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = """
shader_type spatial;
render_mode unshaded, depth_draw_never, depth_test_disabled, cull_disabled, fog_disabled, blend_mix;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform vec3 fog_col : source_color = vec3(0.0);
uniform float far_z = 10000.0;
uniform float off_v = 0.0;
uniform float start_v = 0.0;
void vertex() {
	POSITION = vec4(VERTEX.xy * 2.0, 0.0, 1.0);
}
void fragment() {
	float d = texture(depth_tex, SCREEN_UV).r;
	if (d <= 0.0) {
		discard;
	}
	vec4 v = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
	float z = -v.z / v.w * 100.0;
	float sz = far_z / (far_z - 200.0) * (1.0 - 200.0 / max(z, 1.0));
	float vv = sz - off_v;
	float a = 0.0;
	if (vv > start_v && vv < 1.0) {
		a = (vv - start_v) / (1.0 - start_v);
	}
	ALBEDO = fog_col;
	ALPHA = clamp(a, 0.0, 1.0);
}
"""
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	mesh = q
	var m := ShaderMaterial.new()
	m.shader = _shader
	m.render_priority = 127
	material_override = m
	extra_cull_margin = 16384.0
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visible = false


## p = 6 个 float (null 或 p4 ≤ 0 关雾); far = 视距 (游戏单位)
func setup(p: Variant, far: float) -> void:
	if not (p is Array) or (p as Array).size() < 6 or float(p[4]) <= 0.0:
		visible = false
		return
	var m := material_override as ShaderMaterial
	m.set_shader_parameter("fog_col", Vector3(int(float(p[0]) * 255) / 255.0, int(float(p[1]) * 255) / 255.0, int(float(p[2]) * 255) / 255.0))
	m.set_shader_parameter("far_z", far)
	m.set_shader_parameter("off_v", 1.01 - float(p[5]))
	m.set_shader_parameter("start_v", float(p[3]) / float(p[4]))
	visible = true
