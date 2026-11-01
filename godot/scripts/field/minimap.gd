class_name Minimap
extends Control
## 地图上的小地图 (对象 0xa83b30; 绘制 0x4793da + 外框 0x479048, 输入 0x47a826–0x47ac42; 逆向见 development.md「小地图」)
## 窗口: 每次进图回到 (10,30)–(160,170) (0x4681ef); 拖动不限位
## 图片: 场景 ACT 的第 <楼层> 号动作 (extracted/game/minimap.json), 1000×1000, 1 像素 = 30 游戏单位, 窗口中心 = 主角
## 三态 [0xafe894] (随存档保存): 0 不透明, 1 半透明, 2 隐藏 (旗标 8041)
## 只画主角标记: 其他标记是编号 0x46a–0x473 的角色, 只有「使用中 / 閒置中」物品部署才会产生, 我们还没有这个系统, 地图数据里也没有这些角色

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
## 这些地图的图和世界坐标有偏移 (0x468142–0x4681e0): 地图号 → (x, y) 像素
const SCROLL := {13019: Vector2i(261, -248), 12622: Vector2i(248, -155), 12631: Vector2i(305, -373), 12632: Vector2i(305, -373),
	12633: Vector2i(305, -373), 12634: Vector2i(305, -373), 12635: Vector2i(305, -373), 12636: Vector2i(232, -215), 12638: Vector2i(70, -83)}

static var _table: Dictionary = {}

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
	_floors = _table.get(str(mid), {})
	set_floor(State.map_floor)
	apply_mode()


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


## 每帧: 悬停状态 + 拖动 (0x47abb4: 按住就跟着移动, 不限位)
func tick(mouse: Vector2, held: bool) -> void:
	if not visible:
		idle()
		return
	var m := Vector2i(mouse)
	if _drag:
		if held:
			rect.position += m - _drag_from
			_drag_from = m
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
			cycle()
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
	queue_redraw()


func _outline(x: int, y: int, w: int, h: int, c: Color) -> void:
	draw_rect(Rect2(x + 0.5, y + 0.5, w, h), c, false, 1.0)


func _draw() -> void:
	var p: Vector3 = field.player.gpos if field.player else Vector3.ZERO
	var facing: float = field.player.facing if field.player else 0.0
	var pos := rect.position
	var cx := pos.x + rect.size.x / 2
	var cy := pos.y + rect.size.y / 2
	_outline(pos.x - 1, pos.y - 1, rect.size.x + 1, rect.size.y + 1, EDGE_OUT)
	_outline(pos.x, pos.y, rect.size.x + 1, rect.size.y + 1, EDGE_IN)
	if _tex:
		draw_rect(Rect2(pos.x, pos.y, rect.size.x - 2, rect.size.y), VEIL)
		# 贴图左下角 = 世界原点: 屏幕 x = 中心 + 偏移 − 主角 x/30, 屏幕 y = 中心 + 偏移 + 主角 z/30 − 贴图高
		var ts := Vector2i(_tex.get_size())
		var o := Vector2i(cx + scroll.x - int(p.x / UNITS_PER_PX), cy + scroll.y + int(p.z / UNITS_PER_PX) - ts.y)
		var clip := rect.intersection(Rect2i(o, ts))
		if clip.has_area():
			draw_texture_rect_region(_tex, Rect2(clip), Rect2(clip.position - o, clip.size), Color(1, 1, 1, ALPHA if translucent else 1.0))
	_draw_mark(Vector2(cx, cy), fposmod(facing + 180.0, 360.0))
	_draw_frame()


## 主角箭头 (0x4797e1): 尖 (0,−s), 两翼 (±(s−1), s), 凹口 (0, s/2), 绕 Y 转 −角度 (0x4135a5), 取 x / z 当屏幕 x / y
func _draw_mark(c: Vector2, ang: float) -> void:
	var s := MARK_SIZE
	var r := deg_to_rad(ang)
	var pts: Array[Vector2] = []
	for v in [Vector2(1 - s, s), Vector2(0, -s), Vector2(s - 1, s), Vector2(0, s * 2 / 4)]:
		pts.append(Vector2(c.x + int(cos(r) * v.x + sin(r) * v.y), c.y + int(-sin(r) * v.x + cos(r) * v.y)))
	var col := PackedColorArray([MARK_COLOR, MARK_COLOR, MARK_COLOR])
	draw_primitive(PackedVector2Array([pts[0], pts[1], pts[3]]), col, PackedVector2Array())
	draw_primitive(PackedVector2Array([pts[3], pts[1], pts[2]]), col, PackedVector2Array())


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
