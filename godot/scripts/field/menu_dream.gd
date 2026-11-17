class_name MenuDream
extends RefCounted
## 轮回篇 (同人原创) 主菜单「梦的碎片」页: 车芸想起的一周目片段, 以及哪些已经被她改变
## 数据: rinne.json → Mods.rinne_fragments [{text, seen: [旗标号], changed: 旗标号}] (tools/rinne_build.py 的 @fragment)
##   任一出现旗标成立才列出; 改变旗标成立标「已改变」, 否则「未改变」
## 版式借用记载页 (底图 0085 帧 1 / 2, 行距 25, 调色板 15 / 20 / 22), 全屏子页, Esc / 右上叉叉返回

const UI := "ui/all_sys/0085_000_主介面记载/%03d.png"
const PAL14 := Color8(89, 63, 32)
const PAL15 := Color8(117, 76, 36)
const PAL20 := Color8(192, 80, 88)
const PAL22 := Color8(234, 217, 182)
const ROWS := 14

var m: MainMenu
var top := 0


func _init(menu: MainMenu) -> void:
	m = menu


func fullscreen() -> bool:
	return true


static func entries() -> Array:
	var out: Array = []
	for f in Mods.rinne_fragments:
		var seen := false
		for id in f.get("seen", []):
			if State.test_flag(int(id)):
				seen = true
		if seen:
			var ch := int(f.get("changed", 0))
			out.append({"text": str(f.text), "changed": ch != 0 and State.test_flag(ch)})
	return out


func _bold(s: String, p: Vector2, size: int, col: Color) -> void:
	m._text(s, p, size, col)
	m._text(s, p + Vector2(1, 0), size, col)


func draw(_t: float, _delta: float) -> void:
	m._img(UI % 1, Vector2(0, 75))
	m._img(UI % 2, Vector2(0, 450))
	m._img(UI % 0, Vector2(0, 100))   # 记载页任务列表的纸底 (同 MenuJizai._draw_quests)
	_bold("梦的碎片", Vector2(345, 50), 18, PAL22)
	m._text("梦的碎片", Vector2(60, 565), 20, PAL14)
	m._text("梦的碎片", Vector2(61, 565), 20, PAL14)
	var es := entries()
	if es.is_empty():
		_bold("（还没有想起什么……）", Vector2(230, 102), 16, PAL15)
		return
	top = clampi(top, 0, maxi(es.size() - ROWS, 0))
	for k in ROWS:
		if top + k >= es.size():
			break
		var e: Dictionary = es[top + k]
		var y := 102.0 + 25 * k
		_bold(str(e.text), Vector2(230, y), 16, PAL15)
		_bold("已改变" if e.changed else "未改变", Vector2(630, y), 16, PAL20 if e.changed else PAL14)
	if es.size() > ROWS:
		_bold("%d / %d" % [mini(top + ROWS, es.size()), es.size()], Vector2(600, 455), 12, PAL14)


func key(code: int) -> bool:
	match code:
		KEY_UP:
			top = maxi(top - 1, 0)
			return true
		KEY_DOWN:
			top += 1   # draw 里夹住
			return true
	return false


func wheel(up: bool) -> void:
	key(KEY_UP if up else KEY_DOWN)


func mouse(_p: Vector2, _clicked: bool) -> void:
	pass
