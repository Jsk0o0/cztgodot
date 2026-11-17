class_name UiModelView
extends RefCounted
## 界面里的 3D 人物 (天书居民资料、配置画面的工作位置): 一个盖住整个 800×600 界面的 SubViewport + 正交相机 (1 像素 = 0.01 米)
##   set_models([[ACT, 脚底 x, 脚底 y, 参考像素高], …]): 脚底放在界面坐标上, 按「身高 170 的人形在这里有多少像素」缩放 —
##   数值是原版天书相机 (注视 (5800,1230,6000)、俯仰 16°、距离 8250、焦距 1000) 下的投影 (verify_scene.md §3.4);
##   播放备战动作 0x32 (没有就 80 / 0)

var rect := Rect2(0, 0, 800, 600)
var height := 6.0          # 正交相机竖向看到的世界高度 (米): 600 像素 → 1 像素 0.01 米
var _vp: SubViewport
var _view: TextureRect
var _cam: Camera3D
var _models: Array = []    # [ACT, x, FieldActor]
var field: Node


func _init(parent: Control, f: Node) -> void:
	field = f
	_vp = SubViewport.new()
	_vp.size = Vector2i(rect.size * 2.0)
	_vp.transparent_bg = true
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	parent.add_child(_vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	_vp.add_child(env)
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = height
	_cam.position = Vector3(0, 0, 10)
	_vp.add_child(_cam)
	_view = TextureRect.new()
	_view.texture = _vp.get_texture()
	_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_view.stretch_mode = TextureRect.STRETCH_SCALE
	_view.position = rect.position
	_view.size = rect.size
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(_view)


func free_all() -> void:
	if is_instance_valid(_vp):
		_vp.queue_free()
	if is_instance_valid(_view):
		_view.queue_free()


func set_visible(v: bool) -> void:
	if is_instance_valid(_view):
		_view.visible = v


## models: [[ACT, 脚底 x, 脚底 y, 参考像素高, (可选) 原版绘制角度], …]; 和当前一样就不重建
## 角度: 天书 UI 画模型 0x495177 的最后一个参数; 居民页是 359 (= 面向镜头), 换算同 FieldActor.set_facing (Godot 旋转 = −角度 + 常数)
func set_models(models: Array) -> void:
	if str(models) == str(_models.map(func(e): return e[5])):
		return
	for e in _models:
		if is_instance_valid(e[4]):
			(e[4] as Node).queue_free()
	_models.clear()
	for md in models:
		var act := int(md[0])
		var a: FieldActor = null
		if act > 0 and FileAccess.file_exists(Game.extracted_dir.path_join("game/actors/act_%d.json" % act)):
			a = FieldActor.new()
			_vp.add_child(a)
			a.setup(field, act, act)
			for q in [0x32, 80, 0]:
				if a.has_pose(q):
					a.play(q, true)
					break
			a.position = Vector3((float(md[1]) - 400.0) * 0.01, (300.0 - float(md[2])) * 0.01, 0)
			a.scale = Vector3.ONE * (float(md[3]) / 170.0)   # 模型 1 单位 = 0.01 米, 身高 170 的人形正好 md[3] 像素
			a.rotation_degrees.y = 180.0 - (float(md[4]) - 359.0 if md.size() > 4 else 0.0)   # 359 → 180 面向镜头
		_models.append([act, md[1], md[2], md[3], a, md])
