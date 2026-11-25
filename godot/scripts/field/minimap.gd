class_name Minimap
extends Control
## 地图上的小地图 (对象 0xa83b30; 绘制 0x4793da + 外框 0x479048, 输入 0x47a826–0x47ac42; 逆向见 development.md「小地图」)
## 窗口: 每次进图回到 (10,30)–(160,170) (0x4681ef)
## 图片: 场景 ACT 的第 <楼层> 号动作 (extracted/game/minimap.json), 1000×1000, 1 像素 = 30 游戏单位, 窗口中心 = 主角
## 三态 [0xafe894] (随存档保存): 0 不透明, 1 半透明, 2 隐藏 (旗标 8041)
## 只画主角标记: 其他标记是编号 0x46a–0x473 的角色, 只有「使用中 / 閒置中」物品部署才会产生, 我们还没有这个系统, 地图数据里也没有这些角色
##
## 宽屏补丁追加:
##   1. 任务目标 / 出口钉一面小红旗 (真实贴图位置, 超出窗口的部分裁掉)
##   2. 小地图右边显示当前没做完的任务文字
##   3. 按住左键拖动是平移地图内容 (不再拖窗口), 平移有上限, 露不出窗口外的 3D 画面
##   4. 人物走动时视图自动回到「角色箭头居中」

const FLAG_HIDDEN := 8041
const FLAG_EVENT := 8080
const FLAG_BLOCK := 45             # 0x478563: 置位时不画
const MAP_HAS_MINIMAP := 0x40      # 地图标志
const UNITS_PER_PX := 30.0         # 0x468130 → 0x469240
const MARK_SIZE := 5               # 标记半径 (0x4680dd)
const MARK_COLOR := Color(1, 1, 0) # 0xffffff00; 混合模式 0 (src=ONE, dst=ZERO), 半透明时也不透明
const VEIL := Color8(0x50, 0x82, 0x50, 0x78)
const EDGE_OUT := Color8(0xc0, 0xc0, 0xc0)
const EDGE_IN := Color8(0x18, 0x50, 0x70)
const ALPHA := 5.0 / 16.0          # 贴图模式 0x14, 透明度 5 (0–15 档)
const ACT := 9006                  # 外框 0, 齿轮 1, 指针 2, 三个按钮 3/4/5
const GOAL_COLOR := Color(0.93, 0.10, 0.10)   # 红旗旗面
const GOAL_EDGE := Color(0.18, 0.0, 0.0, 0.85) # 旗面描边
## 这些地图的图和世界坐标有偏移 (0x468142–0x4681e0): 地图号 → (x, y) 像素
const SCROLL := {13019: Vector2i(261, -248), 12622: Vector2i(248, -155), 12631: Vector2i(305, -373), 12632: Vector2i(305, -373),
	12633: Vector2i(305, -373), 12634: Vector2i(305, -373), 12635: Vector2i(305, -373), 12636: Vector2i(232, -215), 12638: Vector2i(70, -83)}

static var _table: Dictionary = {}
static var _quest_db: Dictionary = {}

var field: Node
var rect := Rect2i(10, 30, 150, 140)
var translucent := false
var scroll := Vector2i.ZERO
var _floors: Dictionary = {}
var _tex: Texture2D
var _gear := 0.0            # [0xc6e240]
var _gear_acc := 0.0
var _hover := [false, false, false]   # [0xc6e664] / [0xc6e668] / [0xc6e66c]
var _in_window := false
var _drag := false          # [0xc6e65c]
var _drag_from := Vector2i.ZERO
var _goal: Variant = null   # 当前任务目标的世界坐标 (Vector3) / null
var _goal_map := -1
var _goal_acc := 0.0
var _pan := Vector2.ZERO    # 拖动平移 (像素); 0 = 角色箭头在窗口正中
var _last_p := Vector3.INF  # 上一帧人物位置, 用来判断「人物开始走动了」


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _table.is_empty():
		var p := Game.extracted_dir.path_join("game/minimap.json")
		if FileAccess.file_exists(p):
			_table = JSON.parse_string(FileAccess.get_file_as_string(p))


## 0x4680af–0x468225: 进图时窗口回到默认位置, 换上这张图当前楼层的图片, 再按三态设定
func load_map(mid: int) -> void:
	rect = Rect2i(10, 30, 150, 140)
	scroll = SCROLL.get(mid, Vector2i.ZERO)
	_pan = Vector2.ZERO
	_last_p = Vector3.INF
	_floors = _table.get(str(mid), {})
	set_floor(State.map_floor)
	apply_mode()


## 拖动平移的上限: 最多把整张图平移这么多, 拖到头就停住, 窗口里不会露出 3D 画面
func _pan_limits() -> void:
	if _tex == null:
		_pan = Vector2.ZERO
		return
	var ts := _tex.get_size()
	var lim := Vector2(maxf(0.0, (ts.x - rect.size.x) * 0.5), maxf(0.0, (ts.y - rect.size.y) * 0.5))
	_pan = Vector2(clampf(_pan.x, -lim.x, lim.x), clampf(_pan.y, -lim.y, lim.y))


## 事件 set_floor (0x40a00b) / 换图 (0x406e4d)
func set_floor(f: int) -> void:
	State.map_floor = f
	var p: String = _floors.get(str(f), "")
	_tex = Game.load_texture(p) if p != "" else null


## 0x46e2b5: 进图和事件结束时按 [0xafe894] 恢复 (事件可能动过旗标 8041)
func apply_mode() -> void:
	match State.minimap_mode:
		0:
			translucent = false
			State.set_flag(FLAG_HIDDEN, false)
		1:
			translucent = true
			State.set_flag(FLAG_HIDDEN, false)
		2:
			State.set_flag(FLAG_HIDDEN, true)


## M 键 (0x47a826) / 双击窗口 (0x47a998): 不透明 → 半透明 → 隐藏 → 不透明
func cycle() -> void:
	if State.test_flag(FLAG_HIDDEN):
		State.minimap_mode = 0
	elif translucent:
		State.minimap_mode = 2
	else:
		State.minimap_mode = 1
	apply_mode()


func hide_map() -> void:
	State.minimap_mode = 2
	apply_mode()


## 第二个按钮 (0x47aaef): 不透明 ↔ 半透明
func toggle_translucent() -> void:
	State.minimap_mode = 0 if translucent else 1
	apply_mode()


func _button_at(m: Vector2i) -> int:
	var l := rect.position.x
	var b := rect.end.y
	if m.y < b or m.y >= b + 20:
		return -1
	if m.x >= l + 10 and m.x < l + 30:
		return 0
	if m.x >= l + 30 and m.x < l + 50:
		return 1
	if m.x >= l + 50 and m.x < l + 80:
		return 2
	return -1


## 每帧: 悬停状态 + 拖动. 拖动改成平移地图内容 (_pan), 窗口位置不动 (0x47abb4 原本是拖窗口)
func tick(mouse: Vector2, held: bool) -> void:
	if not visible:
		idle()
		return
	var m := Vector2i(mouse)
	if _drag:
		if held:
			_pan += Vector2(m - _drag_from)
			_drag_from = m
			_pan_limits()
		else:
			_drag = false
	var b := _button_at(m)
	for i in 3:
		_hover[i] = b == i
	_in_window = rect.has_point(m)


func idle() -> void:
	_drag = false
	_in_window = false
	_hover = [false, false, false]


## 左键按下; 返回 true = 点在小地图上, 这一下不算走路 / 调查
func press(mouse: Vector2, double: bool) -> bool:
	if not visible:
		return false
	var m := Vector2i(mouse)
	if rect.has_point(m):
		if double:
			_pan = Vector2.ZERO   # 双击 = 回到角色居中 (原来是不透明 → 半透明 → 隐藏)
		else:
			_drag = true
			_drag_from = m
		return true
	match _button_at(m):
		0:
			hide_map()
		1:
			toggle_translucent()
		2:
			field.reset_camera()   # 0x47ba99: 同 Tab
		_:
			return false
	return true


## 拖动中或鼠标在按钮上时, 按住左键不走路 (0x47b19d)
func blocks_walk() -> bool:
	return _drag or _hover.has(true)


## 光标: 窗口内 / 拖动中四向移动 qq12, 按钮上普通指针 qq9, 其余 −1
func cursor_q() -> int:
	if _hover.has(true):
		return 9
	return 12 if _in_window or _drag else -1


func _process(delta: float) -> void:
	if not visible:
		return
	_gear_acc += delta
	while _gear_acc >= UiAct.TICK_FIELD:
		_gear_acc -= UiAct.TICK_FIELD
		_gear += 0.5
		if _gear >= 360.0:
			_gear = 0.0
	_goal_acc += delta
	if _goal_acc >= 0.5 or _goal_map != State.map_id:
		_goal_acc = 0.0
		_goal_map = State.map_id
		_goal = _pick_goal()
	_restore_center(delta)
	queue_redraw()


## 拖过地图之后, 只要人物开始走动, 视图就滑回角色居中 (拖动中不回弹)
func _restore_center(delta: float) -> void:
	if field == null or field.player == null:
		_last_p = Vector3.INF
		return
	var p: Vector3 = field.player.gpos
	if _last_p == Vector3.INF:
		_last_p = p
		return
	if _drag:
		_last_p = p
		return
	if _pan != Vector2.ZERO and p.distance_to(_last_p) > 0.5:
		_pan = _pan.lerp(Vector2.ZERO, clampf(delta * 10.0, 0.0, 1.0))
		if _pan.length() < 1.0:
			_pan = Vector2.ZERO
	_last_p = p


## 当前没做完的任务: records.json 里 flag_accept 已置、flag_done 还没置; [完成旗标, 是否主任务, 任务文字]
func _pending_quest_done_flags() -> Array:
	if _quest_db.is_empty():
		var qp := Game.extracted_dir.path_join("game/records.json")
		if FileAccess.file_exists(qp):
			_quest_db = JSON.parse_string(FileAccess.get_file_as_string(qp))
	var out := []
	for q in _quest_db.get("quests", []):
		var acc := int(q.get("flag_accept", 0))
		var done := int(q.get("flag_done", 0))
		if acc > 0 and done > 0 and State.test_flag(acc) and not State.test_flag(done):
			out.append([done, 1 if bool(q.get("main", false)) else 0, str(q.get("text", ""))])
	return out


## 这个框触发后会去哪些地图 (change_map, 跟进一层 call_event)
func _dest_maps(eid: int, out: Array, depth: int) -> void:
	for ins in field.event_code(eid):
		var op := str(ins[1])
		if op == "change_map":
			var to := int(ins[2])
			if not out.has(to):
				out.append(to)
		elif op == "call_event" and depth < 1:
			_dest_maps(int(ins[2]), out, depth + 1)


## 任务文字里有没有出现这张图的标题 (两字一组的粗略匹配, 例「返回茅屋」↔「老家臣茅屋」)
func _title_in_text(title: String, texts: Array) -> bool:
	if title.length() < 2:
		return false
	for i in title.length() - 1:
		var bi := title.substr(i, 2)
		for t in texts:
			if str(t).findn(bi) >= 0:
				return true
	return false


## 名字和任务文字最长的公共连续片段长度 (「與端木老人說話」↔「返回茅屋，找端木老人」= 端木老人 4 字)
func _common_run(name_str: String, texts: Array) -> int:
	var best := 0
	for t in texts:
		var s := str(t)
		var n := name_str.length()
		var m := s.length()
		for i in n:
			for j in m:
				var k := 0
				while i + k < n and j + k < m and name_str[i + k] == s[j + k]:
					k += 1
				if k > best:
					best = k
	return best


## 当前任务的目标点, 从高到低:
##   名字和任务文字重合 (≥3 字, 例「找端木老人」) > 本图事件会置「当前任务完成旗标」
##   > 通往任务目的地那张图的出口 > 只沾任务旗标
func _pick_goal() -> Variant:
	if field == null or field.player == null:
		return null
	var p: Vector3 = field.player.gpos
	var mi: Dictionary = field.map_info
	var quests := _pending_quest_done_flags()
	var texts := []
	for q in quests:
		texts.append(q[2])
	var cands := []
	for key in ["boxes", "zones", "npcs"]:
		for r in mi.get(key, []):
			var eid := int(r.get("event", 0))
			if eid <= 0 or field.events_run.has(eid):
				continue
			var pr: Array = r.get("pos", [])
			if pr.size() < 3:
				continue
			var nm := str(r.get("name", ""))
			var nl := 0
			if not texts.is_empty():
				nl = _common_run(nm, texts)
			var off := State.triggers_off.has(eid)
			if off and nl < 3:
				continue
			var g := Vector3(float(pr[0]), float(pr[1]), float(pr[2]))
			# 单层地图不按高度筛 (同一张平面图上山坡高低差就有几百); 多层才用高度分开楼层
			if _floors.size() > 1 and absf(g.y - p.y) > 500.0:
				continue
			var score := 0
			var fls := []
			for ins in field.event_code(eid):
				if str(ins[1]) == "set_flag":
					fls.append(int(ins[2]))
			for fl in fls:
				var hit := false
				for q in quests:
					if int(fl) == int(q[0]):
						score = maxi(score, 3 if int(q[1]) == 1 else 2)
						hit = true
						break
				if not hit and int(fl) >= 7001 and int(fl) <= 7356:
					score = maxi(score, 1)
			if score < 3 and not texts.is_empty():
				var dests := []
				_dest_maps(eid, dests, 0)
				for d in dests:
					var title := str(field.maps.get(str(d), {}).get("title", ""))
					if title != "" and _title_in_text(title, texts):
						score = maxi(score, 2)
						break
			if nl >= 3:
				score = maxi(score, 20 + nl)
			cands.append([score, g, p.distance_to(g), nm])
	if cands.is_empty():
		return null
	cands.sort_custom(func(x: Array, y: Array) -> bool:
		if x[0] != y[0]:
			return x[0] > y[0]
		return x[2] < y[2])
	if cands[0][0] <= 0:
		return null
	if OS.get_cmdline_user_args().has("--trace-goal"):
		print("GOAL map=%d name=%s pos=%s score=%s d=%.0f" % [State.map_id, cands[0][3], str(cands[0][1]), str(cands[0][0]), cands[0][2]])
	return cands[0][1]


## 红色小旗: 钉在任务目标 / 出口在贴图上的真实位置, 超出小地图窗口的部分裁掉
func _draw_goal() -> void:
	if _goal == null or _tex == null or field == null or field.player == null:
		return
	var p: Vector3 = field.player.gpos
	var cx := rect.position.x + rect.size.x / 2.0 + _pan.x
	var cy := rect.position.y + rect.size.y / 2.0 + _pan.y
	# 贴图 x 向右为正; 贴图里 z 越大越靠上
	var c := Vector2(cx + scroll.x + (_goal.x - p.x) / UNITS_PER_PX, cy + scroll.y + (p.z - _goal.z) / UNITS_PER_PX)
	if not Rect2(c.x - 4, c.y - 13, 16, 15).intersects(_clip_rect()):
		return
	_draw_flag(c, 1)


## 窗口内可绘制区域 (旗子 / 人物箭头超出这个框的部分裁掉)
func _clip_rect() -> Rect2:
	return Rect2(rect.position.x + 1, rect.position.y + 1, rect.size.x - 2, rect.size.y - 2)


## 按窗口裁剪后填充多边形
func _fill_clipped(pts: PackedVector2Array, col: Color) -> void:
	var cr := _clip_rect()
	var cp := PackedVector2Array([cr.position, Vector2(cr.end.x, cr.position.y), cr.end, Vector2(cr.position.x, cr.end.y)])
	var out := Geometry2D.intersect_polygons(pts, cp)
	for poly in out:
		if poly.size() >= 3:
			draw_colored_polygon(poly, col)


## 按窗口裁剪后填充矩形
func _rect_clipped(r: Rect2, col: Color) -> void:
	var rr := r.intersection(_clip_rect())
	if rr.has_area():
		draw_rect(rr, col)


## 旗杆 + 三角旗; c 是旗杆底端, d = 1 旗面向右 / -1 旗面向左
func _draw_flag(c: Vector2, d: int) -> void:
	_rect_clipped(Rect2(c.x - 1, c.y - 11, 2, 11), Color(0.15, 0.1, 0.05))
	_fill_clipped(PackedVector2Array([c + Vector2(1 * d, -11), c + Vector2(9 * d, -8), c + Vector2(1 * d, -4)]), GOAL_EDGE)
	_fill_clipped(PackedVector2Array([c + Vector2(1 * d, -10), c + Vector2(7 * d, -8), c + Vector2(1 * d, -5)]), GOAL_COLOR)
	_rect_clipped(Rect2(c.x - 3, c.y - 1, 6, 2), Color(0.15, 0.1, 0.05))


## 小地图右边显示当前没做完的任务 (每行最多 14 字, 最多 3 行)
func _draw_quests() -> void:
	if field == null or not visible:
		return
	var qs := _pending_quest_done_flags()
	if qs.is_empty():
		return
	qs.sort_custom(func(x: Array, y: Array) -> bool: return int(x[1]) > int(y[1]))
	var lines := []
	for q in qs:
		var t := str(q[2])
		if t == "":
			continue
		var i := 0
		while i < t.length() and lines.size() < 3:
			lines.append(t.substr(i, 14))
			i += 14
		if lines.size() >= 3:
			break
	if lines.is_empty():
		return
	var f: Font = Game.font_body
	var x := rect.end.x + 8
	var y := rect.position.y + 14
	for i in lines.size():
		var t := str(lines[i])
		draw_string_outline(f, Vector2(x, y), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4, Color(0.05, 0.02, 0.0, 0.9))
		draw_string(f, Vector2(x, y), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1.0, 0.92, 0.5))
		y += 20


func _outline(x: int, y: int, w: int, h: int, c: Color) -> void:
	draw_rect(Rect2(x + 0.5, y + 0.5, w, h), c, false, 1.0)


func _draw() -> void:
	var p: Vector3 = field.player.gpos if field.player else Vector3.ZERO
	var facing: float = field.player.facing if field.player else 0.0
	var pos := rect.position
	# 人物永远在窗口正中 (拖动时整张图偏 _pan)
	var cx := pos.x + rect.size.x / 2.0 + _pan.x
	var cy := pos.y + rect.size.y / 2.0 + _pan.y
	_outline(pos.x - 1, pos.y - 1, rect.size.x + 1, rect.size.y + 1, EDGE_OUT)
	_outline(pos.x, pos.y, rect.size.x + 1, rect.size.y + 1, EDGE_IN)
	# 不透明底: 贴图拖到头也不会露出 3D 画面
	draw_rect(Rect2(pos.x, pos.y, rect.size.x - 2, rect.size.y), Color8(0x08, 0x18, 0x30))
	if _tex:
		draw_rect(Rect2(pos.x, pos.y, rect.size.x - 2, rect.size.y), VEIL)
		# 贴图左下角 = 世界原点: 屏幕 x = 中心 + 偏移 − 主角 x/30, 屏幕 y = 中心 + 偏移 + 主角 z/30 − 贴图高
		var ts := Vector2i(_tex.get_size())
		var o := Vector2i(int(cx + scroll.x) - int(p.x / UNITS_PER_PX), int(cy + scroll.y) + int(p.z / UNITS_PER_PX) - ts.y)
		var clip := rect.intersection(Rect2i(o, ts))
		if clip.has_area():
			draw_texture_rect_region(_tex, Rect2(clip), Rect2(clip.position - o, clip.size), Color(1, 1, 1, ALPHA if translucent else 1.0))
	_draw_goal()
	_draw_mark(Vector2(cx, cy), fposmod(facing + 180.0, 360.0))
	_draw_frame()
	_draw_quests()


## 主角箭头 (0x4797e1): 尖 (0,−s), 两翼 (±(s−1), s), 凹口 (0, s/2), 绕 Y 转 −角度 (0x4135a5), 取 x / z 当屏幕 x / y
func _draw_mark(c: Vector2, ang: float) -> void:
	var s := MARK_SIZE
	if not Rect2(c.x - s - 1, c.y - s - 1, s * 2 + 2, s * 2 + 2).intersects(_clip_rect()):
		return
	var r := deg_to_rad(ang)
	var pts: Array[Vector2] = []
	for v in [Vector2(1 - s, s), Vector2(0, -s), Vector2(s - 1, s), Vector2(0, s * 2 / 4)]:
		pts.append(Vector2(c.x + int(cos(r) * v.x + sin(r) * v.y), c.y + int(-sin(r) * v.x + cos(r) * v.y)))
	_fill_clipped(PackedVector2Array([pts[0], pts[1], pts[3]]), MARK_COLOR)
	_fill_clipped(PackedVector2Array([pts[3], pts[1], pts[2]]), MARK_COLOR)


## 外框 (0x479048): 没悬停的按钮才画 (悬停时露出外框图里画好的高亮样子); 齿轮每帧转 0.5°; 指针随镜头
func _draw_frame() -> void:
	var l := rect.position.x
	var t := rect.position.y
	var b := rect.end.y
	UiAct.draw(self, ACT, 0, 0, Vector2(l - 3, t - 3))
	for i in 3:
		if not _hover[i]:
			UiAct.draw(self, ACT, 3 + i, 0, Vector2(l + 5 + 20 * i, b - 2))
	UiAct.draw_sprite(self, UiAct.frame(ACT, 1, 0), Vector2(l + 0x91, t + 0x93), 0.0, _gear)
	var needle: float = 180.0 - field.cam.ang.y
	if needle >= 360.0:
		needle = 0.0
	UiAct.draw_sprite(self, UiAct.frame(ACT, 2, 0), Vector2(l + 0x91, t + 0x94), 0.0, needle)
