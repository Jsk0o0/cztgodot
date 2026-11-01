class_name UiAct
extends RefCounted
## 界面 ACT 动画 (导出数据 ui/acts.json, 见 tools/export_ui_acts.py; 播放规则 = ACT 播放器 0x41d1e3):
##   每帧显示 ticks 个逻辑帧 (地图 / 菜单 35 帧/秒, 战斗 27 帧/秒); 循环动作 (VO) 播完回到开头, 否则停在末帧;
##   画在「点 − 锚点 PC」; 有图集矩形时只画那一格
## 无状态用法: UiAct.draw(ci, act, qq, 已过的逻辑帧数, 位置)
## 有状态用法 (换动作就从第 0 帧重播, 同原版写 ACT/QQ 的方式): var p := UiAct.Player.new(); p.set_state(a, q); p.advance(dt); p.draw(ci, pos)

const TICK_FIELD := 1.0 / 35.0
const TICK_BATTLE := 1.0 / 27.0

static var _acts: Dictionary = {}
static var _loaded := false


static func _db() -> Dictionary:
	if not _loaded:
		_loaded = true
		var p := Game.asset_path("ui/acts.json")
		if FileAccess.file_exists(p):
			_acts = JSON.parse_string(FileAccess.get_file_as_string(p))
	return _acts


static func frames(act: int, qq: int) -> Array:
	return _db().get(str(act), {}).get(str(qq), {}).get("frames", [])


static func loops(act: int, qq: int) -> bool:
	return bool(_db().get(str(act), {}).get(str(qq), {}).get("loop", false))


## 一轮的总逻辑帧数
static func length(act: int, qq: int) -> int:
	var n := 0
	for f in frames(act, qq):
		n += int(f[1])
	return n


## 第 ticks 个逻辑帧显示的帧 → {tex, pivot, region (Rect2 或 null), index, done}
static func frame(act: int, qq: int, ticks: int) -> Dictionary:
	var fr := frames(act, qq)
	if fr.is_empty():
		return {}
	var total := length(act, qq)
	var t := ticks
	var done := false
	if total > 0 and t >= total:
		if loops(act, qq):
			t = t % total
		else:
			t = total - 1
			done = true
	var idx := 0
	var acc := 0
	for i in fr.size():
		acc += int(fr[i][1])
		if t < acc:
			idx = i
			break
		idx = i
	var f: Array = fr[idx]
	var reg: Variant = null
	if f.size() > 4 and f[4] is Array and (f[4] as Array).size() >= 4:
		reg = Rect2(float(f[4][0]), float(f[4][1]), float(f[4][2]), float(f[4][3]))
	var ex: Dictionary = f[5] if f.size() > 5 and f[5] is Dictionary else {}
	return {"tex": _texture(str(f[0])), "pivot": Vector2(float(f[2]), float(f[3])), "region": reg, "index": idx, "done": done,
		"cs": Vector2(ex.cs[0], ex.cs[1]) if ex.has("cs") else Vector2.ONE,
		"pd": Vector2(ex.pd[0], ex.pd[1]) if ex.has("pd") else Vector2.ZERO,
		"oc": Color8(int(ex.oc[1]), int(ex.oc[2]), int(ex.oc[3]), int(ex.oc[0])) if ex.has("oc") else Color.WHITE,
		"xf": int(ex.get("xf", 0))}


## 0x46a983 的画法 (逆向确认): 局部点 (u, v) → (x, y) + Rz(角度)·(S·(u + PD.x), S·(v + PD.y)), S = CS + 缩放增量;
## 角度为度、屏幕上顺时针; 不用 PC 锚点; 颜色 = OC; (x, y) 即旋转中心
static func draw_sprite(ci: CanvasItem, f: Dictionary, pos: Vector2, scale_inc := 0.0, angle_deg := 0.0, mod := Color.WHITE) -> void:
	if f.is_empty() or f.tex == null:
		return
	var s: Vector2 = (f.cs as Vector2) + Vector2(scale_inc, scale_inc)
	var r: Rect2 = f.region if f.region != null else Rect2(Vector2.ZERO, (f.tex as Texture2D).get_size())
	var col: Color = (f.oc as Color) * mod
	ci.draw_set_transform(pos, deg_to_rad(angle_deg), s)
	ci.draw_texture_rect_region(f.tex, Rect2(f.pd as Vector2, r.size), r, col)
	ci.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)


## 页签弹跳 (物理 0x495aa0, 各界面 v0 = 3, a = 0.5): 第一次 y = y0, v = v0; 每帧先 y −= v 再 v −= a;
## y > y0 时放回 y0 并重来 → 周期 14 帧 (y0 = 8: 5,2,0,−1,−2,−2,−2,−2,−1,0,2,5,8,8); 画在 trunc(y) (向零取整)
static func bounce(y0: float, frame: int) -> int:
	var y := y0
	var v := 3.0
	for i in frame % 14 + 1:
		y -= v
		v -= 0.5
		if y > y0:
			y = y0
	return int(y)


static func ticks_of(sec: float, battle := false) -> int:
	return int(sec / (TICK_BATTLE if battle else TICK_FIELD))


static func draw(ci: CanvasItem, act: int, qq: int, ticks: int, pos: Vector2, scale := 1.0, mod := Color.WHITE) -> void:
	draw_frame(ci, frame(act, qq, ticks), pos, scale, mod)


static func draw_frame(ci: CanvasItem, f: Dictionary, pos: Vector2, scale := 1.0, mod := Color.WHITE) -> void:
	if f.is_empty() or f.tex == null:
		return
	var tex: Texture2D = f.tex
	var at: Vector2 = pos - (f.pivot as Vector2) * scale
	if f.region != null:   # 高清贴图已按标清尺寸覆盖 (Game.image_texture), 矩形直接用标清坐标
		var r: Rect2 = f.region
		ci.draw_texture_rect_region(tex, Rect2(at, r.size * scale), r, mod)
	else:
		ci.draw_texture_rect(tex, Rect2(at, tex.get_size() * scale), false, mod)


static var _tex := {}


static func _texture(p: String) -> Texture2D:
	if not _tex.has(p):
		_tex[p] = Game.load_texture(p)
	return _tex[p]


class Player:
	extends RefCounted
	var act := 0
	var qq := 0
	var battle := false
	var ticks := 0
	var _acc := 0.0

	func set_state(a: int, q: int) -> void:
		if a != act or q != qq:
			act = a
			qq = q
			ticks = 0
			_acc = 0.0

	func restart() -> void:
		ticks = 0
		_acc = 0.0

	func advance(dt: float) -> void:
		_acc += dt
		var tk := UiAct.TICK_BATTLE if battle else UiAct.TICK_FIELD
		while _acc >= tk:
			_acc -= tk
			ticks += 1

	func current() -> Dictionary:
		return UiAct.frame(act, qq, ticks)

	func draw(ci: CanvasItem, pos: Vector2, scale := 1.0, mod := Color.WHITE) -> void:
		UiAct.draw_frame(ci, current(), pos, scale, mod)
