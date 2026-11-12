class_name Dialog
extends CanvasLayer
## 对白 / 旁白 / 提示窗口: 原版事件指令 0x0a text → add_talkmsg 0x464be7, 绘制 talk_render 0x463be8, 输入 0x4649cf
## text 参数 (角色, w1..w9, 文本):
##   w1 自动推进时间 (×10 ms, 0 = 不自动); (w2,w3) 起点 → (w4,w5) 目标 (左上角, 800×600); w6 移动速度 (0 直接出现,
##   有 0x800 时 w6 像素/帧匀速, 否则每帧走剩余距离/w6); w7×w8 宽高 (像素; 0x4000 时为字数×行数; 0 = 自动)
##   w9 标志: 0x1 只能等计时 / 0x2 纯色底 (window_color ARGB) + 对话框边框图, 否则九宫格皮肤 / 0x8 不画继续箭头 /
##   0x10 忽略点击 / 0x20 文字显示完才开始计时 / 0x800 匀速滑动 / 0x1000 头顶单行小泡 / 0x2000 锚定在角色头上 /
##   0x4000 宽高以字/行计 (w8==1 时以 (x,y) 为中心) / 0x8000 不画边框图
## 文字: 宋体 20px (原版 GDI「細明體」回退宋体), 全角前进 20+字距, 行高 20+行距, 伪粗体 + 1px 黑影, 不抗锯齿
## 控制码: %N 换行, %Cn 调色板颜色, %Sn 每 n 帧出一个字 (%S0 一次显示完), %P 分页, %B<标签>. 选项, %T<物品>. 物品名, %K 固定速度
## 推进: 左键 / 空格 / 回车 —— 第一次按显示完本页, 再按下一页 / 关闭; 选项用 ↑↓ / 鼠标, 回车确认

signal closed(actor: int)

## 调色板 0x4e4818 (前 11 项; %C5 说话者 / 名字栏, %C9 高亮)
const PALETTE := [Color8(255, 255, 255), Color8(0, 0, 0), Color8(255, 0, 0), Color8(0, 255, 0), Color8(0, 0, 255),
	Color8(231, 207, 171), Color8(209, 168, 100), Color8(204, 196, 178), Color8(237, 192, 95), Color8(255, 168, 50),
	Color8(0, 128, 255)]
const SKIN := "ui/all_sys/0139_000_九公格框1/000.png"      # ACT 9008 九宫格 (32×32 格)
const BORDER := "ui/all_sys/0009_000_对话框/000.png"       # ACT 9002 对话框边框 504×114
const ARROW := ["ui/all_sys/0227_000_游标图1/002.png", "ui/all_sys/0227_000_游标图1/003.png"]
const BAR := "ui/all_sys/0115_000_光棒/000.png"           # ACT 9014 选中光棒
const FRAME := 1.0 / 35.0

var field: Node
var windows := {}                # 角色号 → TalkWindow
var last_choice := 0
var auto_choice := 0             # 自动推进时选第几个选项 (自动通关测试换着选)
var auto_seq: Array = []          # 自动通关: 一个事件里第 k 个选项框选第几项 (有就优先用)
var _auto_menu_i := 0
var _auto_last := ""
var _auto_same := 0
var auto_advance := 0.0          # 调试: 等待按键的窗口显示多少秒后自动推进 (--auto-advance=秒), 选项选第一个
var choice_wait := 0.0           # 调试: 自动推进时选项框多停几秒 (--choice-wait=秒, 录制用; 0 = 同 auto_advance)
var tex := {}
var font: FontVariation


func _ready() -> void:
	layer = 10   # 在淡入淡出遮罩 (8) 之上: 原版开场字幕就是黑幕上的字
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--auto-advance="):
			auto_advance = float(a.substr(15))
		elif a.begins_with("--choice-wait="):
			choice_wait = float(a.substr(14))
		elif a.begins_with("--choices="):   # 调试: 自动推进时依次选第几个选项 (0 起, 逗号分隔)
			auto_seq = Array(a.substr(10).split(",")).map(func(x): return int(x))
	for k in [SKIN, BORDER, BAR] + ARROW:
		tex[k] = Game.load_texture(k)
	font = talk_font()


static var _talk_font: FontVariation


## 原版是 GDI 宋体 20px、无抗锯齿、伪粗体; 在高分辨率下发糊, 改用清晰的抗锯齿黑体, 缺字时回退系统字体
static func talk_font() -> FontVariation:
	if _talk_font == null:
		var base := SystemFont.new()
		base.font_names = PackedStringArray(["Hiragino Sans GB", "PingFang SC", "Source Han Sans SC", "Noto Sans CJK SC",
			"Microsoft YaHei", "Songti SC"])
		base.font_weight = 500
		base.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		base.allow_system_fallback = true
		_talk_font = FontVariation.new()
		_talk_font.base_font = base
	return _talk_font


## 翻页箭头 ACT 9019 qq16 (0227 的 002/003 各 9 逻辑帧循环): 全局播放器 0x9f2d78, 所有对话框共用;
## 只要有对话消息存在就每帧走一格 (0x463c25), 不随换页 / 开新框重来
static var arrow_player := UiAct.Player.new()


func _process(delta: float) -> void:
	if windows.is_empty():
		return
	arrow_player.set_state(9019, 16)
	arrow_player.battle = is_equal_approx(FieldActor.TICK, UiAct.TICK_BATTLE)
	arrow_player.advance(delta)


func is_open(actor: int) -> bool:
	return windows.has(actor)


func close(actor: int) -> void:
	if windows.has(actor):
		var w: TalkWindow = windows[actor]
		windows.erase(actor)
		w.queue_free()
		closed.emit(actor)


func close_all() -> void:
	for a in windows.keys():
		close(a)


## 字距 / 行距 (op 0x0e / 0x0f 写 [0x4e4814] / [0x4e4816]): 全局值, 事件脚本和战斗脚本 (FIGTALK 0x0e / 0x0f) 共用,
## 程序启动时为 5 / 5 (数据段初值), 之后一直沿用最后一次设定 (以前事件脚本默认 2 / 5、战斗里不生效, 是推测)
static var char_spacing := 5
static var line_spacing := 5


func show_text(actor: int, p: Array, text: String, bg: Color, caption: String, spacing := -1, line_gap := -1, anchor: Variant = null) -> void:
	if spacing < 0:
		spacing = char_spacing
	if line_gap < 0:
		line_gap = line_spacing
	close(actor)
	var w := TalkWindow.new()
	w.dlg = self
	w.actor = actor
	w.anchor = anchor   # 标志 0x40: 用这个世界坐标 (而不是角色) 当头顶锚点 (例 战斗台词气泡 0x447c87)
	w.setup(p, text, bg, caption, spacing, line_gap)
	add_child(w)
	windows[actor] = w


## 选项提示框 0x465467(x, y, 宽, 高, _, _, 文本, 框 2): 标志 8 (不画翻页箭头), 文字内缩 (+0x6c, +0x6e) = (24, 24), 字距 2, 行距 6
func show_prompt(box: Rect2, text: String) -> void:
	var r := [0, box.position.x, box.position.y, box.position.x, box.position.y, 0, box.size.x, box.size.y, 8]
	show_text(0xff01, r, text, Color.BLACK, "", 2, 6)
	var w: TalkWindow = windows[0xff01]
	w.inset = Vector2(24, 24)
	w.tip_skin = true


## 玩家按确认: 交给第一个接受点击的窗口
func advance() -> bool:
	for a in windows.keys():
		var w: TalkWindow = windows[a]
		if w.on_confirm():
			return true
	return false


func has_input_window() -> bool:
	for w in windows.values():
		if (w as TalkWindow).wants_input():
			return true
	return false


## 战斗 HUD (结算框等) 也用这个
## 九宫格皮肤 (0x465a3c(act, x, y, w, h)): ACT 9008 的 9 个动作, 每块是 32×32 的方块 (XB 0..32, 原点在左上),
## 0x46a983 的缩放参数是「在 CS=1 上加多少」→ 实际倍数 = 1 + 参数:
##   中心 qq4 (格 3, 染色 0x96FFFFFF): 在 (x, y+2), 倍数 (1+(w−34)/31, 1+(h−34)/31) → 约 1.03w × 1.03h, 盖满整个框内
##   上边 qq1 (格 1) 在 (x, y)、下边 qq7 (格 5) 在 (x, y+(h−32)·31/32): 宽 = w (倍数 w/32)
##   左边 qq3 (格 2) 在 (x−5, y+2)、右边 qq5 (格 2 镜像) 在 (x+w−31, y+2): 高 = h−32
##   四角 qq0 / qq2(镜像) / qq6 / qq8(镜像) 在 (x−5 | x+w−31, y | y+(h−32)·31/32), 不缩放
## 绘制顺序 中心 → 上 → 下 → 左 → 右 → 四角, 角盖住边两端 (边格末端 3px 透明, 拉伸后会露缝, 正好被角挡住)
## 单行提示框 0x466f7d(x, y, _, 时长 ×10ms, 文本, _) → add_talkmsg (逆向 0x464be7 / 0x466c08 / 0x463be8):
##   (x, y) 是框中心; 字节数 n: 全角 2 / 半角 1, %C %O %D %S 不计 (跳 3), %B %A 不计 (跳 2), '.' 不计, 第一个 %N 处停止计数并被忽略;
##   框宽 = 22·(n>>1) + 40 + 10·(n&1), 高 52, 左上 = (x − 宽/2, y − 高/2); 九宫格框 2 (ACT 9009); 文字从 +(20,16) 起,
##   20px, 全角前进 22、半角前进 12 (字距 2), 白色 (%C<d> 换调色板色), 模式 4 (对白画法, 带阴影)
##   %B 标签 (到 '.' 为止) 是按钮: 选中项在标签画完后叠光棒 ACT 9014 qq8: (首字 x − 4, y − 4, 标签宽 + 8, 28), alpha 0x78
##   战斗消息 (400, 80, 时长 200 = 2 秒, 同一时间一条、点击无效); FIGTALK 0x7d7 (400, 200); 退驾确认 (400, 280)
const TIP_SKIN := "ui/all_sys/0251_000_九宫格框2/000.png"
static var _tip_skin: Texture2D
static var _bar_tex: Texture2D


## → {box, glyphs: [[字, 位置, 颜色]], buttons: [光棒矩形], hits: [按钮判定矩形]}
## 判定矩形 (add_tbutton 0x4655da) 按「每字节 12 像素」算, 和实际画的位置 (全角 11/字节) 有偏差, 原版如此:
##   x1 = 框x + 20 + 12 × 标签前的字节数, 宽 = (标签字节数 >> 1) × 22, y = 框y + 16, 高 20
static func tip_layout(t: String, c: Vector2) -> Dictionary:
	var n := 0
	var counting := true
	var glyphs: Array = []
	var bars: Array = []
	var col: Color = PALETTE[0]
	var i := 0
	var x := 0.0
	var in_btn := false
	var btn_x := 0.0
	var btn_b := 0
	var lab_b := 0
	var hits_raw: Array = []
	while i < t.length():
		var ch := t[i]
		if ch == "%" and i + 1 < t.length():
			var k := t[i + 1]
			if k == "Q":
				break
			if k in ["C", "O", "D", "S"]:
				if k == "C" and i + 2 < t.length():
					var d := t[i + 2].to_int()
					col = PALETTE[d] if d < PALETTE.size() else col
				i += 3
				continue
			if k in ["B", "A"]:
				in_btn = k == "B"
				btn_x = x
				btn_b = n
				lab_b = 0
				i += 2
				continue
			if k == "N":
				counting = false
				i += 2
				continue
		if ch == ".":
			if in_btn:
				bars.append([btn_x, x])
				hits_raw.append([btn_b, lab_b])
				in_btn = false
			i += 1
			continue
		var full := ch.unicode_at(0) >= 0x80
		if counting:
			n += 2 if full else 1
		if in_btn:
			lab_b += 2 if full else 1
		glyphs.append([ch, x, col])
		x += 22.0 if full else 12.0
		i += 1
	var w := 22 * (n >> 1) + 40 + 10 * (n & 1)
	var box := Rect2(Vector2(c.x - w / 2, c.y - 26), Vector2(w, 52))
	var org := box.position + Vector2(20, 16)
	var out_g: Array = []
	for g in glyphs:
		out_g.append([g[0], org + Vector2(float(g[1]), 0), g[2]])
	var out_b: Array = []
	for b in bars:
		out_b.append(Rect2(org + Vector2(float(b[0]) - 4, -4), Vector2(float(b[1]) - float(b[0]) + 8, 28)))
	var hits: Array = []
	for h in hits_raw:
		hits.append(Rect2(box.position + Vector2(20 + 12 * int(h[0]), 16), Vector2((int(h[1]) >> 1) * 22, 20)))
	return {"box": box, "glyphs": out_g, "buttons": out_b, "hits": hits}


static func draw_top_tip(ci: CanvasItem, t: String, alpha := 1.0, center := Vector2(400, 80), sel := -1) -> void:
	if t == "" or alpha <= 0.0:
		return
	ci.modulate.a = alpha
	draw_tip_layout(ci, tip_layout(t, center), sel)


## 画 tip_layout 的结果 (框 2 + 文字 + 选中的光棒)
static func draw_tip_layout(ci: CanvasItem, L: Dictionary, sel := -1) -> void:
	if _tip_skin == null:
		_tip_skin = Game.load_texture(TIP_SKIN)
	draw_nine(ci, _tip_skin, L.box, true)
	var f := talk_font()
	for g in L.glyphs:
		var p: Vector2 = g[1] + Vector2(0, 17)   # 同对白框: 字顶 + 17 为基线
		ci.draw_string(f, p + Vector2(1, 1), g[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0, 0, 0))
		ci.draw_string(f, p, g[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, g[2])
	if sel >= 0 and sel < L.buttons.size():
		if _bar_tex == null:
			_bar_tex = Game.load_texture(BAR)
		if _bar_tex:
			ci.draw_texture_rect(_bar_tex, L.buttons[sel], false, Color(1, 1, 1, 0x78 / 255.0))


static func draw_nine(ci: CanvasItem, t: Texture2D, r: Rect2, center_tex := false, center := true) -> void:
	if t == null:
		ci.draw_rect(r, Color(0, 0, 0, 0.6))
		return
	var c := 32.0
	var x := r.position.x
	var y := r.position.y
	var w := r.size.x
	var h := r.size.y
	var by := y + (h - 32.0) * 31.0 / 32.0
	var rx := x + w - 31.0
	var cell := func(k: int) -> Rect2: return Rect2((k % 4) * c, int(k / 4.0) * c, c, c)
	# 中心底: 原版把中心格放大约 1.03 倍铺在框内; 按原公式算出的范围会超出右 / 下边框 (宽 448 的结算框超出约 11 像素),
	# 所以以边框线为界: 左右边框线在 x−3..x+1 / x+w−5..x+w−1, 上下在 y+2..y+6 / by+26..by+30 (皮肤图格 1/2/5 的不透明行列),
	# 底色从线的中间铺到对边线的中间, 不出框。
	# 中心格是几乎均匀的暗色 (平均 RGB 17,18,0、alpha 239), 乘 0x96 后直接画实色:
	# 战斗画面 + 高清贴图下按区域取样这一格会变成透明 (原因未查明), 画实色在所有情况下都一致
	var fill := Rect2(x - 1.0, y + 4.0, w - 2.0, by + 28.0 - (y + 4.0))
	if center and fill.size.x > 0 and fill.size.y > 0:   # center = false: 0x465ea4 模式 0, 不画中心块
		if center_tex:   # 框 2: 中心格是木纹, 拉伸后染 0x96FFFFFF (alpha 150, 0x465aac)
			ci.draw_texture_rect_region(t, fill, cell.call(3), Color(1, 1, 1, 150 / 255.0))
		else:
			ci.draw_rect(fill, Color8(17, 18, 0, int(239 * 150 / 255.0)))
	var pieces := [
		[Rect2(x, y, w, c), 1, false], [Rect2(x, by, w, c), 5, false],
		[Rect2(x - 5.0, y + 2.0, c, h - 32.0), 2, false], [Rect2(rx, y + 2.0, c, h - 32.0), 2, true],
		[Rect2(x - 5.0, y, c, c), 0, false], [Rect2(rx, y, c, c), 0, true],
		[Rect2(x - 5.0, by, c, c), 4, false], [Rect2(rx, by, c, c), 4, true]]
	for pc in pieces:
		var dst: Rect2 = pc[0]
		if dst.size.x <= 0 or dst.size.y <= 0:
			continue
		if pc[2]:   # 水平镜像
			ci.draw_set_transform(Vector2(dst.position.x * 2 + dst.size.x, 0), 0, Vector2(-1, 1))
			ci.draw_texture_rect_region(t, dst, cell.call(pc[1]))
			ci.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
		else:
			ci.draw_texture_rect_region(t, dst, cell.call(pc[1]))


## 自动推进时的选项: 默认 auto_choice; 同一组选项连问 3 次以上改选最后一个 (通常是「离开」), 避免循环
func auto_pick(opts: Array) -> int:
	var key := str(opts)
	_auto_same = _auto_same + 1 if key == _auto_last else 0
	_auto_last = key
	if _auto_same >= 3 and auto_seq.is_empty():
		return opts.size() - 1
	if auto_seq.size():
		var c := int(auto_seq[mini(_auto_menu_i, auto_seq.size() - 1)])
		_auto_menu_i += 1
		return clampi(c, 0, maxi(opts.size() - 1, 0))
	return clampi(auto_choice, 0, maxi(opts.size() - 1, 0))


func _choose(actor: int, k: int) -> void:
	last_choice = k
	close(actor)


func item_name(id: int) -> String:
	if field and field.names.items.has(str(id)):
		return str(field.names.items[str(id)])
	return str(id)


# ---------------------------------------------------------------------------------------------

class TalkWindow:
	extends Control

	var dlg: Dialog
	var actor := 0
	var p: Array = []
	var flags := 0
	var bg := Color.BLACK
	var spacing := 2
	var line_gap := 5
	var pos := Vector2.ZERO
	var target := Vector2.ZERO
	var wsize := Vector2(510, 120)
	var inset := Vector2(15, 10)       # 文字内缩 (+0x6c, +0x6e)
	var tip_skin := false              # 框 2 (ACT 9009), 0x465467 用
	var grow := 1.0                    # 0x2000 气泡从 40×40 放大到全尺寸
	var anchor: Variant = null         # 0x40: 世界坐标锚点
	var pages: Array = []              # 每页: [行...], 行: [[字符, 颜色, 速度], ...]
	var page := 0
	var shown := 0                     # 本页已显示的字符数
	var page_chars := 0
	var timer := 0.0
	var limit := 0.0                   # 自动推进时间 (秒)
	var t_frame := 0.0
	var countdown := 0
	var options: Array = []            # [{text, line, col}]
	var sel := 0
	var age := 0.0
	var done_t := 0.0                  # 演示模式: 本页显示完已停留的时间
	var caption := ""

	func setup(params: Array, text: String, color: Color, cap: String, sp: int, lg: int) -> void:
		p = params
		flags = int(p[8])
		add_to_group("talk_windows")   # 光标: 有对话框时强制普通指针 (0x467474 看 [0xa84c48])
		bg = color
		spacing = sp
		line_gap = lg
		caption = cap
		limit = int(p[0]) * 0.01
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var cw := 20 + spacing                       # 全角字宽
		var w := float(p[6])
		var h := float(p[7])
		var units := flags & 0x4000 != 0
		var lines := _layout(text, cw, w, units)
		var inner_w := 0.0
		for ln in lines:
			inner_w = maxf(inner_w, _line_width(ln, cw))
		var lh := 20 + line_gap
		if flags & 0x2000 and w == 0:
			wsize = Vector2(maxf(inner_w + 30, 60), maxf(lines.size() * lh + 20, 40))
		elif units:
			var cols := w if w > 0 else ceilf(inner_w / cw)
			var rows := h if h > 0 else float(lines.size())
			wsize = Vector2(cols * cw + 30, rows * lh + (20 if rows > 1 else 15))
		else:
			wsize = Vector2(w if w > 0 else inner_w + 30, h if h > 0 else lines.size() * lh + 20)
		# 分页
		var per := lines.size() if flags & 0x2000 else maxi(1, int((wsize.y - 20) / lh))
		if units and h > 0:
			per = int(h)
		pages = []
		var cur: Array = []
		for ln in lines:
			if ln.size() == 1 and ln[0][0] == "\f":    # %P
				pages.append(cur)
				cur = []
				continue
			cur.append(ln)
			if cur.size() >= per:
				pages.append(cur)
				cur = []
		if cur.size():
			pages.append(cur)
		if pages.is_empty():
			pages = [[]]
		_start_page()
		pos = Vector2(p[1], p[2])
		target = Vector2(p[3], p[4])
		if units and h == 1:
			pos -= wsize * 0.5
			target -= wsize * 0.5
		if float(p[5]) == 0:
			pos = target
		if flags & 0x2000:
			grow = 0.0
		position = pos
		size = wsize

	## 文本 → 行 (自动换行), 每个字符带颜色和速度
	func _layout(text: String, cw: int, w: float, units: bool) -> Array:
		var lines: Array = [[]]
		var col: Color = Dialog.PALETTE[0]
		var speed := 3
		var max_w := 1e9
		if flags & 0x2000 and w == 0:
			max_w = 10 * cw if text.length() > 10 else 1e9
		elif units and w > 0:
			max_w = w * cw
		elif w > 0:
			max_w = w - 30
		var i := 0
		while i < text.length():
			var ch := text[i]
			if ch == "%" and i + 1 < text.length():
				var c := text[i + 1]
				if c == "N":
					lines.append([])
					i += 2
					continue
				if c in ["n", "A", "K"]:
					i += 2
					continue
				if c == "P":
					lines.append([["\f", col, 0]])
					lines.append([])
					i += 2
					continue
				if c == "Q":
					break
				if c in ["C", "S", "O", "D", "F"]:
					var j := i + 2
					var num := ""
					while j < text.length() and text[j].is_valid_int() and num.length() < 2:
						num += text[j]
						j += 1
					if c == "C" and num != "":
						col = Dialog.PALETTE[clampi(int(num), 0, Dialog.PALETTE.size() - 1)]
					elif c == "S" and num != "":
						speed = int(num)
					i = j
					continue
				if c == "T":
					var e := text.find(".", i + 2)
					var nm := dlg.item_name(int(text.substr(i + 2, e - i - 2))) if e > 0 else ""
					for k in nm:
						lines[-1].append([k, col, speed])
					i = e + 1 if e > 0 else text.length()
					continue
				if c == "B":
					var e2 := text.find(".", i + 2)
					if e2 < 0:
						e2 = text.length()
					var label := text.substr(i + 2, e2 - i - 2)
					options.append({"text": label, "line": lines.size() - 1, "col": _line_width(lines[-1], cw)})
					for k in label:
						lines[-1].append([k, col, speed])
					i = e2 + 1
					continue
			if _line_width(lines[-1], cw) + _char_w(ch, cw) > max_w + 0.5:
				lines.append([])
			# 空格不占逐字显示时间 (否则开场字幕「   纪元前六二九年…」在原版给的 3 秒内打不完)
			lines[-1].append([ch, col, 0 if ch == " " or ch == "　" else speed])
			i += 1
		while lines.size() > 1 and lines[-1].is_empty():
			lines.pop_back()
		return lines

	func _char_w(ch: String, cw: int) -> float:
		# ui_re.md §2: 全角前进 20 + 字距, 半角前进 10 + 字距 (以前半角写成全角的一半)
		return cw if ch.unicode_at(0) >= 0x80 else cw - 10

	func _line_width(ln: Array, cw: int) -> float:
		var s := 0.0
		for c in ln:
			s += _char_w(c[0], cw)
		return s

	func _start_page() -> void:
		shown = 0
		page_chars = 0
		for ln in pages[page]:
			page_chars += ln.size()
		countdown = 0
		timer = 0.0

	func page_done() -> bool:
		return shown >= page_chars

	func wants_input() -> bool:
		return not (flags & 0x1) and (limit <= 0.0 or options.size() > 0)

	## 确认键: 先显示完本页, 再翻页 / 关闭; 有选项时确认选项
	func on_confirm() -> bool:
		# 选项按钮 (%B) 走独立的输入 0x465656: 左键 / 回车直接确认, 不受消息框 0x1 / 0x10 位影响 (天书书吏的提问是旗标 0x38)
		if options.size() and page_done() and page == pages.size() - 1:
			dlg._choose(actor, sel)
			return true
		# 0x4649cf: 带 0x1 不接受按键; 带 0x10 要等计时到了才接受
		if flags & 0x1 or (flags & 0x10 and timer < limit):
			return false
		if not page_done():
			shown = page_chars
			return true
		_next()
		return true

	func _next() -> void:
		if page < pages.size() - 1:
			page += 1
			_start_page()
		else:
			dlg.close(actor)

	func _process(delta: float) -> void:
		age += delta
		t_frame += delta
		while t_frame >= Dialog.FRAME and is_inside_tree():
			t_frame -= Dialog.FRAME
			_frame()
		queue_redraw()

	func _frame() -> void:
		var d := target - pos
		if d.length() > 0.5:
			var sp := float(p[5])
			if flags & 0x800:
				pos += d.normalized() * minf(sp, d.length())
			elif sp > 0:
				pos += d / sp if d.length() > sp else d * 0.5
			else:
				pos = target
		if grow < 1.0:
			grow = minf(1.0, grow + 0.2)
		if flags & 0x2000:
			_follow_head()
		position = pos
		# 逐字显示: 每 %S 帧出一个字, %S0 一次显示完
		if not page_done():
			countdown -= 1
			while countdown <= 0 and not page_done():
				var c: Array = _char_at(shown)
				shown += 1
				if int(c[2]) > 0:
					# 设定「文字速度」: 每字帧数加修正 [+2,+1,0,−1,−2,−3][值/20] (0x4e4190), 值 0..100
					var ts := int(MainMenu.setting("text_speed") * 100.0)
					countdown = maxi(int(c[2]) + [2, 1, 0, -1, -2, -3][clampi(ts / 20, 0, 5)], 1)
					break
		if limit > 0.0 and (page_done() or not (flags & 0x20)):
			timer += Dialog.FRAME
			if timer >= limit and options.is_empty():
				_next()
				return
		if Game.demo and (limit <= 0.0 or options.size()) and page_done():
			done_t += Dialog.FRAME
			if done_t >= clampf(page_chars * 0.07, 1.4, 4.0):
				done_t = 0.0
				if options.size():
					page = pages.size() - 1
					dlg._choose(actor, dlg.auto_pick(options))
				else:
					_next()
				return
		if options.size() and dlg.choice_wait > 0.0 and dlg.auto_seq.size() and age >= dlg.choice_wait * 0.55:
			sel = clampi(int(dlg.auto_seq[mini(dlg._auto_menu_i, dlg.auto_seq.size() - 1)]), 0, options.size() - 1)   # 录制: 光棒先停到要选的项
		if dlg.auto_advance > 0.0 and (limit <= 0.0 or options.size()) and age >= (dlg.choice_wait if options.size() and dlg.choice_wait > 0.0 else dlg.auto_advance):
			age = 0.0
			shown = page_chars
			if options.size():
				page = pages.size() - 1
				dlg._choose(actor, dlg.auto_pick(options))
			else:
				_next()

	func _char_at(k: int) -> Array:
		var n := 0
		for ln in pages[page]:
			if k < n + ln.size():
				return ln[k - n]
			n += ln.size()
		return [" ", Color.WHITE, 0]

	## 0x2000: 头顶投影 → x = 头x − 宽/2 (头x≥320 时 − 宽/3), y = 头y − 高; 限制在 x∈[20, 630−宽], y∈[20, 470−高]
	## (这些常量是 640×480 时代留下的, 原样作用在 800×600 上)
	func _follow_head() -> void:
		var hp: Vector2
		if flags & 0x40 and anchor is Vector3:
			hp = dlg.field.screen_pos(anchor)
		else:
			var a: Node3D = dlg.field.actor(actor) if dlg.field else null
			if a == null:
				return
			hp = dlg.field.screen_pos(a.global_position + Vector3(0, 1.9, 0))
		var x := hp.x - wsize.x / 2.0 if hp.x < 320 else hp.x - wsize.x / 3.0
		var y := hp.y - wsize.y
		target = Vector2(clampf(x, 20, maxf(20, 630 - wsize.x)), clampf(y, 20, maxf(20, 470 - wsize.y)))
		if age < 0.05:
			pos = target

	func _input(e: InputEvent) -> void:
		if options.is_empty() or not page_done() or page != pages.size() - 1:
			return
		# 选项按钮输入 0x465656 (逆向确认): 方向键换项 (不循环, 到头也播 0x201); 鼠标进入按钮换项 (换了才播 0x201);
		# 取消键 (Esc / 左右 Ctrl / 右键) 先播 0x202, 只有全局标志 [0x9f2e90] (Game.cancel_lock) 为 0 时才等于选中第 0 项并确认,
		# 同时留下「已取消」标记 (Game.cancel_residual); 标志不为 0 时没有别的效果
		if e is InputEventKey and e.pressed and not e.echo:
			if e.keycode in [KEY_UP, KEY_LEFT]:
				sel = maxi(sel - 1, 0)
				Game.play_sound(0x201)
				get_viewport().set_input_as_handled()
			elif e.keycode in [KEY_DOWN, KEY_RIGHT]:
				sel = mini(sel + 1, options.size() - 1)
				Game.play_sound(0x201)
				get_viewport().set_input_as_handled()
			elif e.keycode in [KEY_ESCAPE, KEY_CTRL]:
				_cancel_key()
				get_viewport().set_input_as_handled()
		elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_RIGHT:
			_cancel_key()
			get_viewport().set_input_as_handled()
		elif e is InputEventMouseMotion:
			var lp: Vector2 = (e as InputEventMouseMotion).position - global_position
			for k in options.size():
				if _option_rect(k).has_point(lp) and sel != k:
					sel = k
					Game.play_sound(0x201)

	func _cancel_key() -> void:
		Game.play_sound(0x202)
		if Game.cancel_lock == 0:
			Game.cancel_residual = true
			dlg._choose(actor, 0)

	func _option_rect(k: int) -> Rect2:
		var o: Dictionary = options[k]
		var lh := 20 + line_gap
		var n := 0
		for pg in page:
			n += pages[pg].size()
		var row := int(o.line) - n
		var cw := 20 + spacing
		var tw := 0.0
		for ch in str(o.text):
			tw += _char_w(ch, cw)
		return Rect2(inset.x + float(o.col) - 4, inset.y + row * lh - 4, tw + 8, 28)

	func _draw() -> void:
		var sz := wsize * (0.4 + 0.6 * grow) if grow < 1.0 else wsize
		if flags & 0x2:
			var a := clampf(age * 35.0 * 10.0 / 255.0, 0.0, bg.a)    # alpha 每帧 +10, 到 window_color 的 A
			draw_rect(Rect2(Vector2.ZERO, sz), Color(bg.r, bg.g, bg.b, a))
			if not (flags & 0x8000) and dlg.tex.get(Dialog.BORDER):
				draw_texture(dlg.tex[Dialog.BORDER], Vector2(3, 3))
		elif tip_skin:
			if Dialog._tip_skin == null:
				Dialog._tip_skin = Game.load_texture(Dialog.TIP_SKIN)
			Dialog.draw_nine(self, Dialog._tip_skin, Rect2(Vector2.ZERO, sz), true)
		elif not (flags & 0x8000):
			_nine_at(Rect2(Vector2.ZERO, sz))
		if caption != "":
			_nine_at(Rect2(0, -39, caption.length() * 16 + 20, 40))
			_text_at(Vector2(4, -26 + 14), caption, Dialog.PALETTE[5], 16)
		if options.size() and page_done() and page == pages.size() - 1 and dlg.tex.get(Dialog.BAR):
			draw_texture_rect(dlg.tex[Dialog.BAR], _option_rect(sel), false, Color(1, 1, 1, 120 / 255.0))
		var lh := 20 + line_gap
		var cw := 20 + spacing
		var k := 0
		var y := inset.y
		for ln in pages[page]:
			var x := inset.x
			for c in ln:
				if k >= shown:
					break
				if c[0] != "\f":
					_text_at(Vector2(x, y + 17), c[0], c[1], 20)
				x += _char_w(c[0], cw)
				k += 1
			y += lh
		if page_done() and options.is_empty() and not (flags & 0x8) and not (flags & 0x1):
			Dialog.arrow_player.draw(self, sz - Vector2(32, 32))   # (x + w − 32, y + h − 32)
			queue_redraw()

	func _text_at(at: Vector2, s: String, col: Color, fs: int) -> void:
		draw_string(dlg.font, at + Vector2(1, 1), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0))
		draw_string(dlg.font, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

	func _nine_at(r: Rect2) -> void:
		Dialog.draw_nine(self, dlg.tex.get(Dialog.SKIN), r)
