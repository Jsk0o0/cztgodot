extends Node
## 手柄 (Xbox / PS 等, 由 Godot 的标准映射识别): 把手柄输入转成键盘事件, 各画面不用改; 原版没有对应键的才走下面的 Pad.* 虚拟键
## 原版 (逆向见 development.md「手柄」): DirectInput, 只读 lX / lY 和 12 个按钮, 轴范围 ±1000, 死区 10%; 内部键码:
##   0x104–0x107 摇杆左右上下 (= 方向键 0x86–0x89)
##   0x108 按钮 0 确认 (= Enter / 空格), 0x109 按钮 1 取消 (= Esc / Ctrl / 右键)
##   0x10a 按钮 2: 地图上按住 + 左右转镜头
##   0x10b 按钮 3: 地图上开主菜单; 自在页转动模型开关; 天书放置时旋转
##   0x10c / 0x10d 按钮 4 / 5: 地图和自在页按住转向左 / 右; 天书放置时旋转
## 按钮序号按 Xbox 手柄的 DirectInput 顺序对到 A B X Y LB RB; PS 手柄按位置对应 (叉 = A, 圈 = B, 方块 = X, 三角 = Y, L1, R1)
## 以下是原版没有、为现代手柄加的 (原版的手柄按不到这些功能): 十字键 = 方向, 右摇杆转镜头, Start / Options 开主菜单,
##   Back / Share = M 小地图, 按下左摇杆 = R 跑走切换, 按下右摇杆 = Tab 镜头回正, 战斗里 X = Q 逃跑 / Y = A 自动, 法阵谜题 X / LB / RB 旋转

## 虚拟键: 只有个别画面认, 其他画面当没按
const X := KEY_F16
const Y := KEY_F13
const LB := KEY_F14
const RB := KEY_F15
const START := KEY_F17
const CONFIRM_ONLY := KEY_F18   # 只认 Enter 不认空格的地方 (0x450b44: Enter / 0xa0 / 0x108)

const BUTTONS := {
	JOY_BUTTON_A: [KEY_SPACE, CONFIRM_ONLY], JOY_BUTTON_B: [KEY_ESCAPE], JOY_BUTTON_X: [X], JOY_BUTTON_Y: [Y],
	JOY_BUTTON_LEFT_SHOULDER: [LB], JOY_BUTTON_RIGHT_SHOULDER: [RB], JOY_BUTTON_START: [START], JOY_BUTTON_BACK: [KEY_M],
	JOY_BUTTON_LEFT_STICK: [KEY_R], JOY_BUTTON_RIGHT_STICK: [KEY_TAB],
	JOY_BUTTON_DPAD_UP: [KEY_UP], JOY_BUTTON_DPAD_DOWN: [KEY_DOWN], JOY_BUTTON_DPAD_LEFT: [KEY_LEFT], JOY_BUTTON_DPAD_RIGHT: [KEY_RIGHT]}
## 原版死区 10%, 但原版面向数字方向; 模拟摇杆用 10% 时稍微偏一点就变成斜走, 这里放宽
const STICK := 0.4
const TICK := 1.0 / 35.0
## 连发 (0x44efdc + [+0x18e0] = 5, 方向键用): 第 1 拍, 之后超过 10 拍的 5 的倍数 (15, 20, 25…)
const REPEAT := 5

var _buttons := {}     # 按下的 [设备, 按钮]
var _axes := {}        # [设备, 轴] → 值
var _held := {}        # 键码 → 已按住的秒数
var _bg := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_bg = OS.get_cmdline_user_args().has("--bg")   # 测试窗口没有焦点
	Input.joy_connection_changed.connect(func(device: int, connected: bool):
		if not connected:
			_forget(device))


func _forget(device: int) -> void:
	for k in _buttons.keys():
		if k[0] == device:
			_buttons.erase(k)
	for k in _axes.keys():
		if k[0] == device:
			_axes.erase(k)


func _input(e: InputEvent) -> void:
	if e is InputEventJoypadButton:
		if e.pressed:
			_buttons[[e.device, e.button_index]] = true
		else:
			_buttons.erase([e.device, e.button_index])
	elif e is InputEventJoypadMotion:
		_axes[[e.device, e.axis]] = e.axis_value
	else:
		return
	# 默认的 ui_* 动作也绑了手柄键 (十字键等): 不吃掉的话 _unhandled_input 里一按走两格
	get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and not _bg:
		_buttons.clear()
		_axes.clear()


func _axis(axis: int) -> float:
	var v := 0.0
	for k in _axes:
		if k[1] == axis and absf(_axes[k]) > absf(v):
			v = _axes[k]
	return v


func _button(b: int) -> bool:
	for k in _buttons:
		if k[1] == b:
			return true
	return false


func _send(code: int, pressed: bool, echo := false) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code as Key
	ev.physical_keycode = code as Key
	ev.pressed = pressed
	ev.echo = echo
	Input.parse_input_event(ev)


func _process(delta: float) -> void:
	var want := {}
	for b in BUTTONS:
		if _button(b):
			for c in BUTTONS[b]:
				want[c] = true
	var sx := _axis(JOY_AXIS_LEFT_X)
	var sy := _axis(JOY_AXIS_LEFT_Y)
	if sx <= -STICK:
		want[KEY_LEFT] = true
	elif sx >= STICK:
		want[KEY_RIGHT] = true
	if sy <= -STICK:
		want[KEY_UP] = true
	elif sy >= STICK:
		want[KEY_DOWN] = true
	for c in _held.keys():
		if not want.has(c):
			_held.erase(c)
			_send(c, false)
	for c in want:
		if not _held.has(c):
			_held[c] = 0.0
			_send(c, true)
		elif c in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]:
			var before := int(_held[c] / TICK) + 1
			_held[c] += delta
			for n in range(before + 1, int(_held[c] / TICK) + 2):
				if n > 10 and n % REPEAT == 0:
					_send(c, true, true)


## 转动: 1 = 向左 (偏航 +, 同 ←), −1 = 向右; 地图上 LB / RB 按住转 (0x47b88c / 0x47b956), 右摇杆是加的
func turn() -> int:
	var v := _axis(JOY_AXIS_RIGHT_X)
	return (1 if _held.has(LB) or v <= -STICK else 0) - (1 if _held.has(RB) or v >= STICK else 0)


## 地图上按住 X / LB / RB 时方向键转镜头, 不走路 (0x47b71a)
func camera_modifier() -> bool:
	return _held.has(X) or _held.has(LB) or _held.has(RB)


func held(code: int) -> bool:
	return _held.has(code)
