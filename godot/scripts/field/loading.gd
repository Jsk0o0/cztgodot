class_name Loading
extends CanvasLayer
## 换地图时的读取画面 (原版 0x46e1ba(p), 逆向确认; 由各读取阶段调用, p = 0..10, 每调用一次画一帧 —— 按阶段推进, 不按时间):
##   背景 draw_act(9005, bg, 0, 0), bg = rand(4) (每次 load_map 随机, 0258 第 0–3 张, 静态)
##   黑底 (250, 485, 377, 14) → 进度框 9005 qq5 画在 (250, 485) (锚点 31,33) → 进度条 9005 qq6 拉伸成 宽 w = p·10·377/100 × 高 14, 在 (250, 485)
##   金乌 draw_act(9005, 7 + bg % 2, 232 + w, 477): 只看背景编号的奇偶, 整次读取都不变 —— **不扑翅、不上下晃**
##   (以前金乌按 8 帧/秒扑翅加正弦晃动、进度条平滑追赶、读完还多停 0.15 秒, 都是自己加的)

var progress := 0.0                      # 0..1 (= 阶段 p / 10)
var _bg := 0
var _fill: TextureRect
var _bird: TextureRect
var _t := 0.0


func _ready() -> void:
	layer = 11
	_bg = randi() % 4
	var bg := TextureRect.new()
	bg.texture = UiAct.frame(9005, _bg, 0).get("tex")
	bg.position = Vector2.ZERO
	bg.size = Vector2(800, 600)
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	add_child(bg)
	var black := ColorRect.new()
	black.color = Color.BLACK
	black.position = Vector2(250, 485)
	black.size = Vector2(377, 14)
	add_child(black)
	var f5 := UiAct.frame(9005, 5, 0)
	var fr := TextureRect.new()
	fr.texture = f5.get("tex")
	fr.position = Vector2(250, 485) - (f5.get("pivot", Vector2.ZERO) as Vector2)
	add_child(fr)
	_fill = TextureRect.new()
	_fill.texture = UiAct.frame(9005, 6, 0).get("tex")
	_fill.position = Vector2(250, 485)
	_fill.size = Vector2(0, 14)
	_fill.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_fill.stretch_mode = TextureRect.STRETCH_SCALE   # 0x46ac17 拉伸
	add_child(_fill)
	_bird = TextureRect.new()
	_bird.texture = UiAct.frame(9005, 7 + _bg % 2, 0).get("tex")
	add_child(_bird)
	_place()


var _max_dt := 0.0


func _process(delta: float) -> void:
	_t += delta
	_max_dt = maxf(_max_dt, delta)
	_place()


func _place() -> void:
	var p := clampi(int(progress * 10.0), 0, 10)
	var w := p * 10 * 377 / 100
	_fill.size = Vector2(w, 14)
	_fill.visible = w > 0
	_bird.position = Vector2(232 + w, 477)


## 读完: 最后一个阶段 (p = 10) 画一帧
func finish() -> void:
	progress = 1.0
	_place()
	await get_tree().process_frame
	if OS.get_cmdline_user_args().has("--trace-events"):
		print("LOADING total=%.2fs longest_frame=%.0fms" % [_t, _max_dt * 1000.0])
