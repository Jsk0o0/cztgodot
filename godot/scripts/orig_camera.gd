class_name OrigCamera
extends RefCounted
## 原版镜头 (战斗 0x908228 / 地图 0xa80648 同一个类, exe 0x45f9a5-0x461149)
## 眼睛 = 注视点 F + Rz(c)·Ry'(b)·Rx(a)·(0, 0, -D)  (0x45fddb 建矩阵, 0x45ffd7 取 (0,0,-D)), 看向 F, 世界上方向 +Y
##   a = 俯仰 (正 = 眼睛在上方), b = 偏航 (0 = 眼睛在 -Z 一侧往 +Z 看, 90 = 在 +X 一侧), c = 绕世界 Z 摆动
##   Rx = [[1,0,0],[0,ca,-sa],[0,sa,ca]], Ry' = [[cb,0,-sb],[0,1,0],[sb,0,cb]], Rz = 标准
## 三个通道每 tick (1/35 秒) 更新: A 注视点 (+0x20 模式, +0x18 步长 / +0x1c 除数), B 角度 (+0x2c, +0x24 = 参数/1000 度,
##   +0x28 除数), C 距离 (+0x38, +0x30 / +0x34); 模式 1 瞬切, 2 匀速 (够近就到位), 3 每 tick 走剩余量的 1/除数
## 角度第 4 参数 (+0x48): 0 走最短路, 1 偏航只增, 2 偏航只减
## 投影 (0x41a951): 焦距 = near·k/2 像素 (800×600, near 200), k 默认 10 → 垂直视野 33.4°; 事件 camera_zoom 改 k
## 近裁剪面 = 200 单位 (2 米): 离镜头 2 米内的东西不画 (例: 序章开场站在镜头后的士兵, 长矛不会伸进画面);
## 远裁剪面 = 视距 [0x4e4900] (默认 10000, change_map 第 6 个参数设定)
## 坐标: 游戏单位 (1 米 = 100), Godot 位置 = origin + 游戏坐标 × 0.01; 原版是左手系, 画面需水平翻转显示

const TICK := 1.0 / 35.0

var cam: Camera3D
var origin := Vector3.ZERO
var f := Vector3.ZERO
var ft := Vector3.ZERO
var ang := Vector3(16, 359, 0)
var angt := Vector3(16, 359, 0)
var d := 1600.0
var dt := 1600.0
var mode := [1, 1, 1]          # A 注视点 / B 角度 / C 距离
var sp := [20.0, 1.0, 20.0]    # 匀速步长
var div := [8.0, 8.0, 8.0]     # 缓动除数
var dir := 0
var follow: Node3D             # 跟随的节点 (每 tick 把注视点目标设为它的位置 + follow_off)
var follow_off := Vector3.ZERO
var zoom_k := 10.0
var zoom_kt := 10.0
var view_dist := 10000.0
## 镜头类型 (事件 0x49 camera_type → 0x45faf9): 1 普通环绕跟随; 4 固定机位 — 冻结当前眼睛位置, 之后只转头看注视点
##   (俯仰 / 偏航 / 距离都不起作用); 从 4 切回 1 时把目标偏航改成「固定眼睛 → 注视点」的方向 (0x460f68), 画面不跳;
##   5 = 不更新镜头。换地图时回到 1 (0x4683bb)。全部用法都在隐藏地图 13031「DOMO 工作室」
var cam_type := 1
var eye_w := Vector3.ZERO      # 最近一次的眼睛位置 (世界坐标, 类型 4 时冻结在这里)
var _acc := 0.0


func _init(c: Camera3D, world_origin := Vector3.ZERO) -> void:
	cam = c
	origin = world_origin


func to_game(p: Vector3) -> Vector3:
	return (p - origin) / 0.01


func to_world(g: Vector3) -> Vector3:
	return origin + g * 0.01


static func _mode_of(v: int) -> int:
	return v if v in [2, 3] else 1


func set_target(g: Vector3) -> void:
	follow = null
	ft = g
	if mode[0] == 1:
		f = ft


func set_type(t: int) -> void:
	match t:
		1:
			if cam_type == 4:
				var v := f - to_game(eye_w)
				angt.y = fposmod(rad_to_deg(atan2(-v.x, v.z)), 360.0)
				if mode[1] == 1:
					ang.y = angt.y
			cam_type = 1
		4, 5, 2:
			cam_type = t
		_:
			pass   # 3 无效


func set_follow(n: Node3D, off: Vector3) -> void:
	follow = n
	follow_off = off
	ft = to_game(n.global_position) + off
	if mode[0] == 1:
		f = ft


func set_angles(a: float, b: float, c: float, direction := 0) -> void:
	angt = Vector3(a, b, c)
	dir = direction
	if mode[1] == 1:
		ang = angt


func set_distance(v: float) -> void:
	dt = v
	if mode[2] == 1:
		d = dt


func set_mode(channel: int, m: int) -> void:
	mode[channel] = _mode_of(m)


## 速度设定 (0x45fc90/0x45fcaf/0x45fcd6 与 0x45fd0d/0x45fd2c/0x45fd4d): 步长 ≤0 时为 1, 除数 ≤1 时为 1; 角度步长 ×0.001
func set_speed(channel: int, v: float) -> void:
	sp[channel] = (v * (0.001 if channel == 1 else 1.0)) if v > 0 else 1.0
	div[channel] = v if v > 1 else 1.0


## 存档里的镜头 (0xa851b8 整块写进存档, 视距 [0x4e4900] 单独存; 读档 0x475b30 瞬切到存的值, 再恢复三个通道的模式)
func to_save() -> Dictionary:
	return {"f": [ft.x, ft.y, ft.z], "ang": [angt.x, angt.y, angt.z], "d": dt, "k": zoom_kt, "view": view_dist,
		"mode": mode.duplicate(), "type": cam_type, "eye": [to_game(eye_w).x, to_game(eye_w).y, to_game(eye_w).z]}


func from_save(s: Dictionary) -> void:
	follow = null
	cam_type = 1
	ft = Vector3(s.f[0], s.f[1], s.f[2])
	angt = Vector3(s.ang[0], s.ang[1], s.ang[2])
	dt = float(s.d)
	zoom_kt = float(s.k)
	view_dist = float(s.view)
	snap()
	for i in 3:
		mode[i] = int(s.mode[i])
	if int(s.type) == 4:   # 0x475bc5: 固定机位还要恢复眼睛位置
		eye_w = to_world(Vector3(s.eye[0], s.eye[1], s.eye[2]))
		cam_type = 4


func snap() -> void:
	if follow and is_instance_valid(follow):
		ft = to_game(follow.global_position) + follow_off
	f = ft
	ang = angt
	d = dt
	zoom_k = zoom_kt
	apply()


func arrived() -> bool:
	return (f - ft).length() < 1.0 and _ang_delta(ang, angt, 0).length() < 1.0 and absf(d - dt) < 1.0


static func _ang_delta(cur: Vector3, tgt: Vector3, direction: int) -> Vector3:
	var r := Vector3.ZERO
	for i in 3:
		var x := fposmod(tgt[i], 360.0) - fposmod(cur[i], 360.0)
		if i == 1 and direction == 1:
			x = fposmod(x, 360.0)
		elif i == 1 and direction == 2:
			x = -fposmod(-x, 360.0)
		elif x > 180.0:
			x -= 360.0
		elif x < -180.0:
			x += 360.0
		r[i] = x
	return r


## 镜头震动 (ATK 0x49 → 0x44b920, 每帧 0x4414a2): 幅度从 10 起每帧 −1 到 0; 每 3 帧换一次正负; 加在注视点 y 上 (游戏单位)
var _shake_amp := 0
var _shake_on := false
var _shake_sign := 1
var _shake_n := 0
var _shake_off := 0.0


func shake(on: bool) -> void:
	_shake_on = on
	if on:
		_shake_amp = 10
		_shake_sign = 1
		_shake_n = 0
	else:
		_shake_amp = 0
		_shake_off = 0.0


func _shake_step() -> void:
	if not _shake_on or _shake_amp <= 0:
		_shake_off = 0.0
		return
	_shake_n += 1
	if _shake_n >= 3:
		_shake_n = 0
		_shake_sign = -_shake_sign
	_shake_off = float(_shake_sign * _shake_amp)
	_shake_amp -= 1
	if _shake_amp <= 0:
		_shake_amp = 0
		_shake_on = false


func tick(delta: float) -> void:
	_acc += delta
	while _acc >= TICK:
		_acc -= TICK
		_step()
		_shake_step()
	apply()


func _step() -> void:
	if follow and is_instance_valid(follow):
		ft = to_game(follow.global_position) + follow_off
	var df := ft - f
	match mode[0]:
		2:
			f = ft if df.length() <= sp[0] else f + df.normalized() * sp[0]
		3:
			f += df / div[0]
		_:
			f = ft
	var da := _ang_delta(ang, angt, dir)
	match mode[1]:
		2:
			if da.length() <= sp[1]:
				ang = angt
				dir = 0
			else:
				ang += da.normalized() * sp[1]
		3:
			if da.length() < 0.05:
				ang = angt
				dir = 0
			else:
				ang += da / div[1]
		_:
			ang = angt
	var dd := dt - d
	match mode[2]:
		2:
			d = dt if absf(dd) <= sp[2] else d + signf(dd) * sp[2]
		3:
			d += dd / div[2]
		_:
			d = dt
	zoom_k = move_toward(zoom_k, zoom_kt, 0.5)


func eye_and_focus() -> Array:
	var ra := deg_to_rad(ang.x)
	var rb := deg_to_rad(ang.y)
	var rc := deg_to_rad(ang.z)
	var rx := Basis(Vector3(1, 0, 0), Vector3(0, cos(ra), sin(ra)), Vector3(0, -sin(ra), cos(ra)))
	var ry := Basis(Vector3(cos(rb), 0, sin(rb)), Vector3(0, 1, 0), Vector3(-sin(rb), 0, cos(rb)))
	var rz := Basis(Vector3(cos(rc), sin(rc), 0), Vector3(-sin(rc), cos(rc), 0), Vector3(0, 0, 1))
	var v := rz * (ry * (rx * Vector3(0, 0, -d)))
	var fw := to_world(f + Vector3(0, _shake_off, 0))
	return [fw + v * 0.01, fw]


func apply() -> void:
	if cam == null:
		return
	if cam_type == 5:
		return
	var ef := eye_and_focus()
	if cam_type == 4:
		ef[0] = eye_w   # 固定机位: 眼睛不动, 只看向注视点
	else:
		eye_w = ef[0]
	cam.fov = rad_to_deg(2.0 * atan(300.0 / (200.0 * zoom_k / 2.0)))
	cam.near = 2.0
	cam.far = maxf(view_dist * 0.01, 20.0)
	if (ef[0] as Vector3).distance_to(ef[1]) > 0.001:
		cam.look_at_from_position(ef[0], ef[1], Vector3.UP)
