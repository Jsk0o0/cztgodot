class_name GameCursor
extends CanvasLayer
## 原版鼠标光标 (逆向: 绘制 0x467474, 2D 绘制 0x46ad17, ACT 播放 0x41d1e3; 笔记 development.md「鼠标光标」)
## * 光标是一个 ACT 播放器 (对象 0xa83d1c), 各画面每帧写它的 ACT / QQ ([0xa83db0] / [0xa83db2]), 画在鼠标位置减去 ACT 的锚点 PC
## * 常用: ACT 9001 qq0–7 八方向箭头, 8 手 (调查), 9 普通指针, 10 对话气泡, 11 旋转, 12 四向移动 (小地图);
##         ACT 9109 qq0 沙漏 (战斗行动条走动中), qq1 剑 (战斗中要选东西); ACT 9019 qq16 按钮 (右上角菜单卷轴)
## * 绘制时 (0x467474): 旗标 8050 / 8080 置位, 或地图上鼠标 600 帧没动 ([0xafdc54]) → 不画;
##   有对话框 ([0xa84c48] > 0) 或选项按钮 ([0xa84ce8] > 0) → 强制 ACT 9001 qq9
## * 动画以逻辑帧推进: 地图 / 菜单 35 帧/秒, 战斗 27 帧/秒 (播放器在每帧的绘制里调用一次)
## 系统鼠标指针隐藏, 只画这个

const FPS_FIELD := 35.0
const FPS_BATTLE := 27.0

var act := 9001
var qq := 9
var fps := FPS_FIELD
var idle_hidden := false          # 地图上 600 帧没动鼠标 ([0xafdc54] = 1)
var frozen: Variant = null        # 右键拖动转镜头时原版把鼠标锁在按下的位置 (0x40e160 SetCursorPos), 光标画在这里
var debug_pos: Variant = null     # 调试 / 录像: 注入的鼠标位置 (界面坐标), 有值时画在这里、录像也画

var _acts: Dictionary = {}
var _key := ""
var _frame := 0
var _left := 0
var _acc := 0.0
var _node: Control
var _tex: Texture2D
var _pivot := Vector2.ZERO
var _off := false                 # 录像 / 无窗口时不画


func _ready() -> void:
	layer = 128
	_node = Control.new()
	_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_node.size = Vector2(800, 600)
	_node.draw.connect(_draw)
	add_child(_node)
	var args := OS.get_cmdline_user_args()
	_off = args.has("--park-mouse") or DisplayServer.get_name() == "headless"
	var p := Game.asset_path("ui/acts.json")
	if FileAccess.file_exists(p):
		_acts = JSON.parse_string(FileAccess.get_file_as_string(p))
	if not _off and not _acts.is_empty():
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN


## 各画面每帧调用 (原版直接写 [0xa83db0] / [0xa83db2])
func set_state(a: int, q: int) -> void:
	act = a
	qq = q


var _ca := 0   # 实际在播的 (对话框时被强制成 9001/9, 不改画面请求的 act / qq)
var _cq := 0


func _frames() -> Array:
	return _acts.get(str(_ca), {}).get(str(_cq), {}).get("frames", [])


func _process(delta: float) -> void:
	if (_off and debug_pos == null) or _acts.is_empty():
		return
	var a := act
	var q := qq
	# 0x467474: 有对话框或选项按钮 → 普通指针
	if not get_tree().get_nodes_in_group("talk_windows").is_empty():
		a = 9001
		q = 9
	var key := "%d/%d" % [a, q]
	if key != _key and OS.get_cmdline_user_args().has("--trace-cursor"):
		print("CURSOR %s hidden=%s t=%.1f" % [key, str(hidden_now()), Time.get_ticks_msec() / 1000.0])
	if key != _key:
		# 换动作: 播放结构清零, 从第一帧开始 (0x41d2c0)
		_key = key
		_frame = 0
		_left = 0
		_acc = 0.0
		_ca = a
		_cq = q
		_show()
	_acc += delta
	while _acc >= 1.0 / fps:
		_acc -= 1.0 / fps
		_tick()
	_node.queue_redraw()


func _tick() -> void:
	var fr := _frames()
	if fr.is_empty():
		return
	_left += 1
	if _left >= int(fr[_frame][1]):
		_left = 0
		if _frame < fr.size() - 1:
			_frame += 1
		elif bool(_acts.get(str(_ca), {}).get(str(_cq), {}).get("loop", false)):
			_frame = 0
		_show()


func _show() -> void:
	var fr := _frames()
	if fr.is_empty():
		_tex = null
		return
	var f: Array = fr[clampi(_frame, 0, fr.size() - 1)]
	_tex = Game.load_texture(str(f[0]))
	_pivot = Vector2(float(f[2]), float(f[3]))


func hidden_now() -> bool:
	return State.test_flag(8050) or State.test_flag(8080) or idle_hidden


func _draw() -> void:
	if _tex == null or hidden_now():
		return
	var m: Vector2 = frozen if frozen != null else (debug_pos if debug_pos != null else _node.get_local_mouse_position())
	_node.draw_texture(_tex, (m - _pivot).floor())
