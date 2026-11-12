class_name MainMenu
extends CanvasLayer
## 主菜单 (原版 [0xa83ce0]==1: 地图上按 Enter / 小键盘 Enter 打开 0x47c918 → 0x47e45a, 音效 510; 绘制 0x47f1c6)
##   背景 0065 主介面底图 18 帧轮播; 顶栏 0068 第 0 帧 (0,5), 底栏第 1 帧 (0,560)
##   右侧 10 块木板 0068 第 3–12 帧 (619, 48+50k), 从 y=−120 落下
##   7 个指令 (从 x=810 滑入, 表 0x4e60cc/0x4e60e8): 物品 (641,170) 装备 (710,180) 奇术 (674,260) 机关 (623,322)
##     天书 (692,356) 记载 (621,426) 系统 (708,447); 平常 0252 第 k 帧, 悬停 0089 第 2k/2k+1 帧交替; 机关要旗标 7, 天书要旗标 9
##   关闭 0171 (740,4)
##   状态页 0x47f46d: 第 k 个入队角色 (旗标 1/2/3 顺序) 的面板在 (415/215/15, 55), 从下方滑入; 面板 0068 第 13+角色 帧 196×486;
##     名字 (+30,+310) 16px; 等级「%2d 级」(+30,+332); 生命 / 灵力 / 体力: 图标 0266 (+32,+387/408/430),
##     条 0068 第 17(车芸)/18、19、20 帧 (+50,+385/407/429) 长 80×值/上限, 文字「%d/%-4d」12px (+35,+377/399/421);
##     下一级经验值 (+30,+448), 数值 (+122,+448)
##   资源 0x47fa35: 图标 0068 第 25–29 帧 (633, 50+25k), 数值「%-6d」(660, 50+25k): 金钱 金属 木材 煤炭 木甲技术
##   物品页 0x487676 / 0x48860e: 清单 0081 第 0 帧 (240,73), 「名称」「数量」, 行高 32, 选中行 280×32 白 alpha 0x32; 说明栏 0081 第 1 帧 (62,478)
##   装备页 0x4801e6 / 0x480820: 立绘 0082 第 0–2 帧 (62,70), 装备栏 0082 第 3 帧 (360,70), 可换装备 0082 第 4 帧 (355,272), 底栏 (62,478)
## 子画面内部的文字坐标只逆向了主要部分, 其余按素材格子摆放

signal closed

const BG := "ui/all_sys/0065_000_主介面底图/%03d.png"
const EL := "ui/all_sys/0068_000_主介面底图元件/%03d.png"
const CMD_N := "ui/all_sys/0252_000_主命令小图平常/%03d.png"
const CMD_H := "ui/all_sys/0089_000_主命令小图形/%03d.png"
const CLOSE := "ui/all_sys/0171_000_离开叉叉/%03d.png"
const ICON3 := "ui/all_sys/0266_000_命灵体/%03d.png"
const ICON3_PC := Vector2(12, 15)   # ACT 9004 各帧的 PC 绘制偏移 (draw_act 0x46ab27 画在 (x,y) − PC)
const ITEM_UI := "ui/all_sys/0081_000_主介面物品/%03d.png"
const EQUIP_UI := "ui/all_sys/0082_000_主介面装备/%03d.png"
const CAT := "ui/all_sys/0106_000_物品分类icon/%03d.png"
const CAT_SEL := "ui/all_sys/0107_000_物品分类icon选/%03d.png"
const SAVE_UI := "ui/all_sys/0087_000_主介面存档/%03d.png"
const CMD_POS := [Vector2(641, 170), Vector2(710, 180), Vector2(674, 260), Vector2(623, 322), Vector2(692, 356),
	Vector2(621, 426), Vector2(708, 447)]
const CMD_NAMES := ["物品", "装备", "奇术", "机关", "天书", "记载", "系统"]
const PANEL_POS := [Vector2(415, 55), Vector2(215, 55), Vector2(15, 55)]
const PANEL_FROM := [Vector2(-200, 600), Vector2(800, 600), Vector2(15, 600)]
const TEXT_COL := Color8(117, 76, 36)      # 调色板 15
const DARK_COL := Color8(89, 63, 32)       # 调色板 14
const CREAM := Color8(234, 217, 182)       # 调色板 22
const GREY_COL := Color8(192, 80, 88)
const MEMBER_NAMES := {1: "车芸", 2: "嬴诗", 3: "桓远之"}
## 物品分类页签: [图标帧, 名称, 分类码] (0106 / 0107)
const ITEM_TABS := [[0, "全部", []], [10, "恢复", [202]], [9, "攻击", [201]], [11, "辅助", [203]], [2, "武器", [204]],
	[3, "防具", [205]], [4, "饰品", [206]], [6, "鞋", [208]], [5, "法宝", [207]], [8, "素材", [209]], [7, "剧情", [210, 211, 0]]]
## 装备栏: [名称, 分类码] — 装备栏 0..5 = 武器 護具 飾品 足部 法寶 法寶 (档案 +0x58a..+0x594; 标签表 0x4e6170、子类表 0x4e618c, 逆向确认)
const SLOTS := [["武器", 204], ["防具", 205], ["饰品", 206], ["鞋", 208], ["法宝", 207], ["法宝", 207]]

var field: Node
var page := "status"
var _c: Control
var _tex := {}
var _t := 0.0                 # 打开后的时间 (滑入动画)
var _hover := -1
static var _bg_player := UiAct.Player.new()    # 0xc70300: 不随菜单开关清零
static var _cmd_player := UiAct.Player.new()   # 0xc701e8
static var _cmd_cur := -1                      # [0xc70128] − 1
static var _gear_ang := [0.0, 0.0, 0.0]        # [0xc70150] / [0xc70154] / [0xc70158], 初值 0, 从不复位
var _gear_acc := 0.0


## 三个转动的齿轮 (0x47fead, 记载页 [0xc70124] = 6 不画): ACT 9011 qq14 (PD (−127,−128), 1 倍) 用 0x46a983 画,
## 中心 (79,169) / (199,386) / (528,−1); 每逻辑帧先画再 +0.5° / −0.5° / +0.5° (正 = 顺时针), 只在画菜单时推进
func _draw_gears() -> void:
	if page == "jizai":
		return
	var f := UiAct.frame(9011, 14, 0)
	var pts := [Vector2(79, 169), Vector2(199, 386), Vector2(528, -1)]
	for i in 3:
		UiAct.draw_sprite(_c, f, pts[i], 0.0, float(_gear_ang[i]))
	_gear_acc += get_process_delta_time()
	while _gear_acc >= UiAct.TICK_FIELD:
		_gear_acc -= UiAct.TICK_FIELD
		_gear_ang[0] = 0.0 if float(_gear_ang[0]) + 0.5 >= 360.0 else float(_gear_ang[0]) + 0.5
		_gear_ang[1] = 360.0 if float(_gear_ang[1]) - 0.5 <= 0.0 else float(_gear_ang[1]) - 0.5
		_gear_ang[2] = 0.0 if float(_gear_ang[2]) + 0.5 >= 360.0 else float(_gear_ang[2]) + 0.5
var _sel := 0                 # 指令选择
var _members: Array = []      # 入队角色号
var _msg := ""
var _msg_t := 0.0
# 物品页
var _tab := 0
var _isel := 0
var _itop := 0
var _target := -1             # 使用物品时选的队员 (下标), -1 = 还没进入选人
# 装备页
var _who := 0
var _slot := 0
var _choose := false          # 正在挑选装备
var _csel := 0
# 系统页
var _ssel := 0
# 机关 / 奇术 / 记载 / 天书 页 (各自一个脚本, 复用这里的绘图与音效)
var _sub: RefCounted


func _ready() -> void:
	layer = 12
	_c = Control.new()
	_c.size = Vector2(800, 600)
	_c.draw.connect(_draw)
	_c.mouse_filter = Control.MOUSE_FILTER_IGNORE   # 点击交给 _unhandled_input (STOP 会让 GUI 吞掉鼠标按键, 菜单收不到点击)
	add_child(_c)
	for m in [1, 2, 3]:
		if State.test_flag(m):
			_members.append(m)
	if _members.is_empty():
		_members = [1]
	Game.play_sound(510)


func tex(p: String) -> Texture2D:
	if not _tex.has(p):
		_tex[p] = Game.load_texture(p)
	return _tex[p]


## 鼠标位置 (800×600); 录制时调试参数 --mouse 注入的位置优先 (Viewport 的鼠标位置读的是真实光标)
func mouse() -> Vector2:
	if field and field._dbg_mouse_on:
		return field._dbg_mouse_ui
	return _c.get_local_mouse_position()


func _img(p: String, pos: Vector2, mod := Color.WHITE) -> void:
	var t := tex(p)
	if t:
		_c.draw_texture(t, pos, mod)


## 原版文字 (0x40d9fc, GDI 栅格): (x, y) 是字格左上角; 半角字符占字号的一半宽, 全角占一个字号宽
## 半角 = ASCII (Big5 单字节); ★ ※ 「」 这类符号在 Big5 里是双字节, 占全格 —
## 格式串靠空格对齐 (如「    %d/%-4d」「%-6d」), 所以逐字按格子排, 不用比例字体的字宽
func _text(s: String, pos: Vector2, size: int, col := TEXT_COL, outline := CREAM) -> void:
	var f: Font = Game.font_body
	var x := pos.x
	var base_y := pos.y + size * 0.88
	for ch in s:
		var half := ch.unicode_at(0) < 0x80
		if ch != " ":
			# ★ ☆ ※ 这类符号 (U+2000–U+2BFF) 在这套字体里占满整格, 原版字体里比汉字小一圈: 缩到 80%, 在格里居中, 和后面的字留出间隔
			var cu := ch.unicode_at(0)
			var fs := int(size * 0.8) if cu >= 0x2000 and cu < 0x2c00 else (Game.half_size(size, 2) if half else size)
			var w := f.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var cx := x + ((size * 0.5 + Game.HALF_GAP if half else float(size)) - w) * 0.5
			var by := base_y - (size - fs) * 0.4
			_c.draw_string_outline(f, Vector2(cx, by), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 2, outline)
			_c.draw_string(f, Vector2(cx, by), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		x += size * 0.5 + Game.HALF_GAP if half else float(size)


func _process(delta: float) -> void:
	_t += delta
	if Game.cursor:
		Game.cursor.set_state(9001, 9)   # 主菜单 (0x47f1c6): 普通指针; 天书城镇画面在 draw 里另设
		Game.cursor.fps = GameCursor.FPS_FIELD
	if _msg_t > 0:
		_msg_t -= delta
	var m := mouse()
	if _sub and _sub.has_method("mouse"):
		_sub.mouse(m, false)
	_hover = -1
	for k in (0 if _sub and _sub.has_method("own_bg") else 7):
		if Rect2(_cmd_pos(k), tex(CMD_N % k).get_size() if tex(CMD_N % k) else Vector2(80, 80)).has_point(m):
			_hover = k
	_c.queue_redraw()


func _slide(k: float) -> float:
	return clampf((_t - k) / 0.3, 0.0, 1.0)


func _cmd_pos(k: int) -> Vector2:
	var to: Vector2 = CMD_POS[k]
	return Vector2(lerpf(810, to.x, _slide(0.05 * k)), to.y)


func _cmd_enabled(k: int) -> bool:
	match k:
		3:
			return State.test_flag(7)
		4:
			return State.test_flag(9)
	return true


# ---------------- 绘制 ----------------

func _draw() -> void:
	# 天书: 自己画 3D 画面和工具栏
	if _sub and _sub.has_method("own_bg"):
		_sub.draw(_t, get_process_delta_time())
		_draw_msg()
		return
	_c.draw_rect(Rect2(0, 0, 800, 600), Color(0, 0, 0, 1))
	# 背景齿轮 ACT 9011 qq0 (0x47f1c6): 全局播放器 0xc70300 整个进程只播一次 (18 帧 × 27 逻辑帧, 只在画菜单时推进),
	# 之后每次打开菜单都停在最后一帧 017 (以前是每 0.5 秒换一帧一直循环)
	_bg_player.set_state(9011, 0)
	_bg_player.advance(get_process_delta_time())
	_bg_player.draw(_c, Vector2.ZERO)
	_draw_gears()
	_img(EL % 0, Vector2(0, 5))
	_img(EL % 1, Vector2(0, 560))
	# 全屏子页 (记载页、奇术选施法对象 [0xc701d8]=1) 不画右侧木板 / 指令 / 资源 (0x47f2f4)
	var full: bool = _sub != null and _sub.has_method("fullscreen") and _sub.fullscreen()
	if full:
		_sub.draw(_t, get_process_delta_time())
		var cm0 := mouse()
		_img(CLOSE % (1 if Rect2(740, 4, 30, 30).has_point(cm0) else 0), Vector2(740, 4))
		_draw_msg()
		return
	for k in 10:
		_img(EL % (3 + k), Vector2(619, lerpf(-120, 48 + 50 * k, _slide(0.02 * k))))
	_draw_resources(Vector2(660, 50))
	# 指令图标 (0x47f948): 只有「当前项」[0xc70128] 用共用播放器 0xc701e8 画 ACT 9019 —— 主页 qq k (两帧各 7 逻辑帧循环),
	# 子页 qq 20 + k (单帧); qq 一变就从头播。鼠标移开时当前项不清 (最后悬停的那个一直播); 其他项画静态图
	if _hover >= 0:
		_cmd_cur = _hover
	_cmd_player.advance(get_process_delta_time())
	for k in 7:
		var p := _cmd_pos(k)
		var mod := Color(1, 1, 1, 1) if _cmd_enabled(k) else Color(0.5, 0.5, 0.5, 0.8)
		if k == _cmd_cur and _cmd_enabled(k):
			_cmd_player.set_state(9019, k if page == "status" else 20 + k)
			_cmd_player.draw(_c, p, 1.0, mod)
		else:
			_img(CMD_N % k, p, mod)
	var cm := mouse()
	_img(CLOSE % (1 if Rect2(740, 4, 30, 30).has_point(cm) else 0), Vector2(740, 4))
	match page:
		"status":
			for i in _members.size():
				var to: Vector2 = PANEL_POS[i]
				_draw_panel(_members[i], PANEL_FROM[i].lerp(to, _slide(0.1)))
		"item":
			_draw_items()
		"equip":
			_draw_equip()
		"system":
			_draw_system()
		_:
			if _sub:
				_sub.draw(_t, get_process_delta_time())
	_draw_msg()


func _draw_msg() -> void:
	if _msg_t > 0:
		var r := Rect2(200, 260, 400, 60)
		_c.draw_rect(r, Color(0, 0, 0, 0.7))
		_text(_msg, r.position + Vector2(20, 18), 18, CREAM, Color(0.1, 0.07, 0.03))


func _draw_resources(o: Vector2) -> void:
	var vals := [State.money, State.metal, State.wood, State.coal, State.tech]
	for k in 5:
		_img(EL % (25 + k), Vector2(o.x - 27, o.y + 25 * k))
		_text("%-6d" % int(vals[k]), Vector2(o.x, o.y + 25 * k), 16)


## 状态面板 (0x47f46d)
func _draw_panel(m: int, o: Vector2) -> void:
	var idx := m - 1
	_img(EL % (13 + idx), o)
	var d := State.member(m)
	_text(MEMBER_NAMES.get(m, ""), o + Vector2(30, 310), 16, DARK_COL)
	_text("%2d" % int(d.lv), o + Vector2(30, 332), 16)
	_text("级", o + Vector2(49, 332), 16, DARK_COL)
	var rows := [[int(d.hp), int(d.hp_max), 0 if m == 1 else 1, 17 if m == 1 else 18, 0],
		[int(d.mp), int(d.mp_max), 2, 19, 22], [int(d.sp), int(d.sp_max), 3, 20, 44]]
	for r in rows:
		var dy: int = r[4]
		_text("    %d/%-4d" % [r[0], r[1]], o + Vector2(35, 377 + dy), 12)
		_img(ICON3 % int(r[2]), o + Vector2(32, 387 + dy) - ICON3_PC)
		# 数值条 0x46df94: 先画底槽 (9011 qq18 = 0068 第 16 帧), 再按比例画填充
		_img(EL % 16, o + Vector2(50, 385 + dy))
		var bar := tex(EL % int(r[3]))
		var w := 80.0 * float(r[0]) / maxf(float(r[1]), 1.0)
		if bar and w > 0:
			_c.draw_texture_rect_region(bar, Rect2(o + Vector2(50, 385 + dy), Vector2(w, 8)), Rect2(0, 0, w, 8))
	_text("下一级经验值:", o + Vector2(30, 448), 12, DARK_COL)
	_text("%-8d" % maxi(State.exp_threshold(int(d.lv)) - int(d.exp), 0), o + Vector2(122, 448), 12)


# ---------------- 输入 ----------------

func _unhandled_input(e: InputEvent) -> void:
	get_viewport().set_input_as_handled()
	if e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_RIGHT:
			if _sub and _sub.has_method("own_bg"):
				if _sub.has_method("right_click"):
					_sub.right_click()   # 天书分页里右键 = 取消 (道场 0x101); 主画面右键拖动转镜头
				return
		if e.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			if _sub and _sub.has_method("wheel"):
				_sub.wheel(e.button_index == MOUSE_BUTTON_WHEEL_UP)
			return
			_back()
			return
		if e.button_index != MOUSE_BUTTON_LEFT:
			return
		var m := mouse()
		if _sub and _sub.has_method("own_bg"):
			_sub.mouse(m, true)
			return
		if Rect2(740, 4, 30, 30).has_point(m):
			_close()
			return
		if _hover >= 0 and not (_sub and _sub.has_method("fullscreen") and _sub.fullscreen()):
			_open_page(_hover)
			return
		match page:
			"item":
				_click_items(m)
			"equip":
				_click_equip(m)
			"system":
				_click_system(m)
			_:
				if _sub and _sub.has_method("mouse"):
					_sub.mouse(m, true)
		return
	if not (e is InputEventKey and e.pressed):
		return
	if e.keycode in [KEY_ESCAPE, KEY_CTRL]:   # 取消 = ESC / 左右 Ctrl (内部键码 0x1b / 0x82 / 0x83, 各画面都按这一组判断, 例 0x48045c)
		if _sub and _sub.key(KEY_ESCAPE):
			return
		_back()
		return
	match page:
		"status":
			if e.keycode in [KEY_DOWN, KEY_RIGHT]:
				_sel = (_sel + 1) % 7
				_cmd_cur = _sel
				Game.play_sound(Game.SFX_UI_SELECT)
			elif e.keycode in [KEY_UP, KEY_LEFT]:
				_sel = (_sel + 6) % 7
				_cmd_cur = _sel
				Game.play_sound(Game.SFX_UI_SELECT)
			elif e.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
				_open_page(_sel)
		"item":
			_key_items(e.keycode)
		"equip":
			_key_equip(e.keycode)
		"system":
			_key_system(e.keycode)
		_:
			if _sub:
				_sub.key(e.keycode)


func _open_page(k: int) -> void:
	if not _cmd_enabled(k):
		Game.play_sound(Game.SFX_UI_ERROR)
		return
	Game.play_sound(Game.SFX_UI_OK)
	_sel = k
	_cmd_cur = k
	match k:
		0:
			page = "item"
			_tab = 0
			_isel = 0
			_itop = 0
			_target = -1
		1:
			page = "equip"
			_who = 0
			_slot = 0
			_choose = false
		6:
			page = "system"
			_ssel = 0
			_sys_quit = false
			_sys_set = false
		2:
			page = "qishu"
			_sub = MenuQishu.new(self)
		3:
			page = "jiguan"
			_sub = MenuJiguan.new(self)
		4:
			page = "tianshu"
			_sub = MenuTianshu.new(self)
		5:
			page = "jizai"
			_sub = MenuJizai.new(self)
		_:
			_say("%s：暂未开放" % CMD_NAMES[k])


func _back() -> void:
	Game.play_sound(514 if page == "system" else Game.SFX_UI_CANCEL)   # 系统页取消 0x202
	if page == "item" and _target >= 0:
		_target = -1
	elif page == "equip" and _choose:
		_choose = false
	elif page == "system" and _sys_quit:
		return   # 离开确认框不能用取消键关 (0x4658cb(1))
	elif page == "system" and _sys_set:
		_sys_set = false   # 设定面板: Esc / 右键回到页签
	elif page != "status":
		page = "status"
		if _sub and _sub.has_method("free_fx"):
			_sub.free_fx()
		_sub = null
	else:
		_close()


func _close() -> void:
	Game.play_sound(514)
	closed.emit()
	queue_free()


func _say(s: String) -> void:
	_msg = s
	_msg_t = 1.6


# ---------------- 物品 ----------------

func _item_list() -> Array:
	var subs: Array = ITEM_TABS[_tab][2]
	var out: Array = []
	for it in State.items:
		if int(State.items[it]) <= 0:
			continue
		var r := Battle.obj(int(it))
		if subs.size() and int(r.get("sub", 0)) not in subs:
			continue
		out.append(int(it))
	out.sort()
	return out


## 物品页 (0x488747(x,y), 清单原点 (240,73)): 表头「名称」(+25,+6)「数量」(+250,+6) 12px;
## 第 k 行 名字 (+19, +26+25k) 12px, 数量「%2d」(+249, 同行); 选中行 (x, +18+25k, 280×32) 白 alpha 0x32
## 大图标 (0xc72420 对象) 在 (55,95); 说明栏 (62,478) 见 note_rows
const ITEM_ROWS := 12


## 说明栏: 功能说明 (例「恢复生命200」) 和描述合并显示, 不用按 F1。这是有意偏离原版 (原版平时只有描述, F1 切换 [0xc701dc], 0x47fc78),
## 所以「F1详细说明」标签也去掉了, 文字从标签的位置开始; 每行 [文字, 颜色], 功能说明用深色, 最多 3 行, 16px, 行高 25
static func note_rows(r: Dictionary, width := 540.0) -> Array:
	var rows: Array = []
	for line in wrap_note(str(r.get("note", "")), width):
		rows.append([line, DARK_COL])
	for line in wrap_note(str(r.get("desc", "")), width):
		if rows.size() < 3:
			rows.append([line, TEXT_COL])
	return rows


func _draw_note(r: Dictionary, b: Vector2) -> void:
	var rows := MainMenu.note_rows(r)
	for i in rows.size():
		_text(rows[i][0], b + Vector2(12, 3 + 25 * i), 16, rows[i][1])


static func wrap_note(s: String, width := 540.0, size := 16, max_lines := 3) -> PackedStringArray:
	var out := PackedStringArray()
	var line := ""
	var x := 0.0
	for ch in s:
		var w := size * 0.5 if ch.unicode_at(0) < 0x80 else float(size)
		if x + w > width:
			out.append(line)
			line = ""
			x = 0.0
			if out.size() >= max_lines:
				return out
		line += ch
		x += w
	if line != "":
		out.append(line)
	return out


func _draw_items() -> void:
	var o := Vector2(lerpf(640, 240, _slide(0)), 73)
	for k in ITEM_TABS.size():
		var p := Vector2(244 + 32 * k, 38)
		_img((CAT_SEL if k == _tab else CAT) % int(ITEM_TABS[k][0]), p)
	_img(ITEM_UI % 0, o)
	_text("名称", o + Vector2(25, 6), 12)
	_text("数量", o + Vector2(250, 6), 12)
	var list := _item_list()
	for i in ITEM_ROWS:
		var k := _itop + i
		if k >= list.size():
			break
		var r := Battle.obj(int(list[k]))
		if k == _isel:
			_c.draw_rect(Rect2(o.x, o.y + 18 + 25 * i, 280, 32), Color(1, 1, 1, 0x32 / 255.0))
		var col := TEXT_COL if _usable(int(list[k])) else DARK_COL
		_text(str(r.get("name", list[k])), o + Vector2(19, 26 + 25 * i), 12, col)
		_text("%2d" % int(State.items[list[k]]), o + Vector2(249, 26 + 25 * i), 12, col)
	var b := Vector2(62, lerpf(600, 478, _slide(0)))
	_img(ITEM_UI % 1, b)
	if _isel < list.size():
		var r2 := Battle.obj(int(list[_isel]))
		_draw_note(r2, b)
		var icon := str(r2.get("icon", ""))
		if icon != "" and _target < 0:
			_img(icon, Vector2(lerpf(-200, 55, _slide(0)), 95))
	if _target >= 0:
		_draw_panel(_members[_target], Vector2(30, 55))
		_text("◀ 使用对象 ▶", Vector2(60, 40), 16, CREAM, Color(0.1, 0.07, 0.03))


## 地图上能否选对象使用 (0x488af9): 子类 202 恢复 / 203 辅助, 且「可用场合」(背包条目 +0xea = 记录 +0xde = field_use) 为 1 或 2。
## 机关金乌 3903、指向小狐 3904 原版另有处理, 还没逆完, 先不开放 (雪肌冰鲍 3803 见 State.item_level_up)
func _usable(id: int) -> bool:
	var r := Battle.obj(id)
	if id == 3801:
		return true
	if id in [3903, 3904]:
		return false
	return int(r.get("sub", 0)) in [202, 203] and int(r.get("field_use", 0)) in [1, 2]


func _key_items(k: int) -> void:
	var list := _item_list()
	if _target >= 0:
		if k in [KEY_LEFT, KEY_UP]:
			_target = (_target + _members.size() - 1) % _members.size()
		elif k in [KEY_RIGHT, KEY_DOWN]:
			_target = (_target + 1) % _members.size()
		elif k in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
			_use_item(int(list[_isel]), _members[_target])
		return
	if k == KEY_DOWN:
		_isel = mini(_isel + 1, maxi(list.size() - 1, 0))
		Game.play_sound(Game.SFX_UI_SELECT)
	elif k == KEY_UP:
		_isel = maxi(_isel - 1, 0)
		Game.play_sound(Game.SFX_UI_SELECT)
	elif k == KEY_RIGHT or k == KEY_LEFT:
		_tab = (_tab + (1 if k == KEY_RIGHT else ITEM_TABS.size() - 1)) % ITEM_TABS.size()
		_isel = 0
		_itop = 0
		Game.play_sound(Game.SFX_UI_PAGE)
	elif k in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE] and _isel < list.size():
		var iid := int(list[_isel])
		if iid >= 5526 and iid <= 5533:
			# 玉蝉 (0x4883c3 / 0x48982f, 逆向确认): 旗标 1037 (事件 516 设) 成立才能用, 不选人;
			# 启动事件 = 道具号 − 5001 (525–532), 不查地图和位置 (位置判断在脚本里); 菜单不扣, 由脚本 take_item 扣
			if State.test_flag(1037):
				_use_event_item(iid - 5001, iid, false)
			else:
				Game.play_sound(Game.SFX_UI_ERROR)
				_say("这个物品不能使用!!")
		elif iid == 3902:
			# 土地神符: 当前地图在 MAPS.DAT 第 17 段表里 (maps.json talisman_event) 才能用, 启动那条事件, 菜单扣 1 个
			var tev: Variant = field.map_info.get("talisman_event") if field else null
			if tev != null:
				_use_event_item(int(tev), iid, true)
			else:
				Game.play_sound(Game.SFX_UI_ERROR)
				_say("现在无法使用!!")
		elif iid == 3901:
			# 诱敌女娃 (0x48997e, 逆向确认): 0x404f17(主角, 步数, 强制=1) 跳过步数分段和机率, 只要地图能遇敌且主角在遇敌区里就挑一个战场;
			# 成功: 音效 0x21d、扣 1 个、关菜单开战 (0x43fb05); 失败: 音效 0x20e +「现在无法使用!!」(0x4e3220), 不扣 (用户反馈: 以前没效果)
			var bf: int = field.lure_battle() if field else 0
			if bf > 0:
				pending_battle = bf
				_use_event_item(-1, iid, true)
			else:
				Game.play_sound(Game.SFX_UI_ERROR)
				_say("现在无法使用!!")
		elif iid == 3801:
			_use_mystery_fruit()
		elif _usable(int(list[_isel])):
			_target = 0
			Game.play_sound(Game.SFX_UI_OK)
		else:
			Game.play_sound(Game.SFX_UI_ERROR)
			_say("现在无法使用")
	_itop = clampi(_itop, _isel - ITEM_ROWS + 1, _isel)


func _click_items(m: Vector2) -> void:
	for k in ITEM_TABS.size():
		if Rect2(244 + 32 * k, 38, 30, 30).has_point(m):
			_tab = k
			_isel = 0
			_itop = 0
			Game.play_sound(Game.SFX_UI_PAGE)
			return
	var o := Vector2(240, 73)
	var list := _item_list()
	if _target >= 0:
		_use_item(int(list[_isel]), _members[_target])
		return
	if Rect2(o.x, o.y + 22, 290, 25 * ITEM_ROWS).has_point(m):
		var k2 := _itop + int((m.y - o.y - 22) / 25)
		if k2 < list.size():
			if k2 == _isel:
				_key_items(KEY_ENTER)
			else:
				_isel = k2
				Game.play_sound(Game.SFX_UI_SELECT)


## 道具启动事件 (0x48982f → 0x405c21): 先关菜单 (0x47e45a), 事件发起者 = 队长, 播 0x21d, 需要时扣 1 个;
## 事件由 field 在菜单关闭后启动 (pending_event)
var pending_event := -1
var pending_battle := 0   # 诱敌女娃: 菜单关闭后开这场战斗


func _use_event_item(ev: int, iid: int, consume: bool) -> void:
	pending_event = ev
	Game.play_sound(0x21d)
	if consume:
		State.give_item(iid, -1)
	closed.emit()
	queue_free()


## 神秘果 (3801「随时存档」, 0x48839d): 打开存档画面, 不查禁存标志; 云梦泽 12621 不能用; 真的存了档才扣 1 个 (0x489c73)
func _use_mystery_fruit() -> void:
	if field and int(field.map_id) == 12621:
		Game.play_sound(Game.SFX_UI_ERROR)
		_say("云梦泽莫名的力量,使神秘果无法使用!!")
		return
	Game.play_sound(Game.SFX_UI_OK)
	var sc := SaveLoadScreen.new()
	sc.mode = "save"
	sc.thumb = field.menu_thumb if field else null
	sc.field = field
	add_child(sc)
	await sc.closed
	if sc.saved:
		State.give_item(3801, -1)


## 地图上对队员使用道具 (0x48982f): 全体道具 (scope 1, 0x4899cf) 对每个队员各套一次 0x488ffa, 全部无效才算失败;
## 单人道具先按对象类别 (0xC22, 0x489a43: 车芸 & 4 / 其他人 & 8) 拒绝「此角色无法使用此物品!!」, 再套 0x488ffa;
## 失败「目前不需要恢复!!」(0x4e62a0, 音效 0x20e), 不扣道具; 成功播 0x21d (0x489af8) 并扣 1 个
func _use_item(id: int, m: int) -> void:
	var r := Battle.obj(id)
	var ok := false
	if int(r.get("scope", 0)) == 1:
		for mem in _members:
			ok = _item_effect(mem, r) or ok
	else:
		var tc := int(r.get("target_class", 0))
		if (m == 1 and tc & 0x4) or (m != 1 and tc & 0x8):
			Game.play_sound(Game.SFX_UI_ERROR)
			_say("此角色无法使用此物品!!")
			return
		ok = State.item_level_up(m) if id == 3803 else _item_effect(m, r)
	if not ok:
		Game.play_sound(Game.SFX_UI_ERROR)
		_say("等级已到上限!!" if id == 3803 else "目前不需要恢复!!")  # 0x489abb: 3803 用 0x4e65ac
		return
	State.give_item(id, -1)
	Game.play_sound(0x21d)
	_say("%s使用了【%s】" % [MEMBER_NAMES.get(m, ""), r.get("name", "")])
	if int(State.items.get(id, 0)) <= 0:
		_target = -1


## 道具对一个队员的效果 (0x488ffa, 记录 = 背包条目 +0xc); 返回是否有效。
## 1. 全体道具 (scope 1) 按对象类别跳过: 车芸 & 4、其他人 & 8
## 2. 永久加值 (加在队员数值上, 原版这些格子含装备加成 — 见 0x461bd8): 生命 / 灵力 / 体力上限 (0xBBA)、
##    攻 防 (fx1[2] [3])、仙攻 仙防 (fx2[1] [2])、速度 (fx2[5]) — 大于 10000 时按 (值 − 10000)% (99 当 100) 算, 算出 0 就按原值加;
##    命中 (fx1[4])、回避 (fx2[4])、仙命中、仙回避 (0xBBB)、会心 (0x3EF) 直接加。有任何一项就算有效
## 3. 回复: 生命 fx1[0] / 灵力 fx2[0] / 体力 fx1[1], 同样的百分比规则, 加完不超过上限;
##    「有效」改看回复: 有生命回复就看生命是否未满, 否则依次看灵力、体力 (永久加值的结果被覆盖)
## 4. 状态 (0xC21 = status | status_op << 16): 含 0x10000000 一定有效, 再含 2 就复活; 倒下的人 (HP 0) 不复活就无效
##    注意原版在第 4 步才判无效, 所以对倒下的人用永久加值道具会先加上数值、但道具不扣 — 照原版
func _item_effect(m: int, r: Dictionary) -> bool:
	var d := State.member(m)
	var tc := int(r.get("target_class", 0))
	if int(r.get("scope", 0)) == 1 and ((m == 1 and tc & 0x4) or (m != 1 and tc & 0x8)):
		return false
	var fx1: Array = r.get("fx1", [0, 0, 0, 0, 0, 0])
	var fx2: Array = r.get("fx2", [0, 0, 0, 0, 0, 0, 0])
	var eff := false
	for kv in [["hp_max", int(r.get("hp", 0))], ["mp_max", int(r.get("mp", 0))], ["sp_max", int(r.get("sp", 0))],
			["hit", int(fx1[4])], ["eva", int(fx2[4])], ["mhit", int(r.get("mhit", 0))], ["meva", int(r.get("meva", 0))],
			["crit", int(r.get("crit", 0))]]:
		if int(kv[1]) > 0:
			d[kv[0]] = int(d.get(kv[0], 0)) + int(kv[1])
			eff = true
	var cur := State.member_stats(m)
	for kv in [["atk", int(fx1[2])], ["def", int(fx1[3])], ["matk", int(fx2[1])], ["mdef", int(fx2[2])], ["spd", int(fx2[5])]]:
		var v: int = kv[1]
		if v <= 0:
			continue
		d[kv[0]] = int(d.get(kv[0], 0)) + _item_amount(v, int(cur[kv[0]]))
		eff = true
	var hp := 0
	var mp := 0
	var sp := 0
	if int(fx1[0]) > 0:
		hp = _item_amount(int(fx1[0]), int(d.hp_max))
		eff = int(d.hp) != int(d.hp_max)
	if int(fx2[0]) > 0:
		mp = _item_amount(int(fx2[0]), int(d.mp_max))
		if not eff:
			eff = int(d.mp) != int(d.mp_max)
	if int(fx1[1]) > 0:
		sp = _item_amount(int(fx1[1]), int(d.sp_max))
		if not eff:
			eff = int(d.sp) != int(d.sp_max)
	var st := int(r.get("status", 0)) | (int(r.get("status_op", 0)) << 16)
	var dead := int(d.hp) <= 0
	if st & 0x10000000:
		eff = true
		if st & 0x2:
			dead = false
	if not eff or dead:
		return false
	d.hp = mini(int(d.hp) + hp, int(d.hp_max))
	d.mp = mini(int(d.mp) + mp, int(d.mp_max))
	d.sp = mini(int(d.sp) + sp, int(d.sp_max))
	return true


## 0x488ffa 的数值: 大于 10000 = 底数的 (值 − 10000)% (正好 99 当 100), 算出 0 就用原值; 否则就是原值
static func _item_amount(v: int, base: int) -> int:
	if v > 10000:
		var p := v - 10000
		if p == 99:
			p = 100
		var inc := base * p / 100
		if inc != 0:
			return inc
	return v


# ---------------- 装备 ----------------

func _equip_of(m: int) -> Array:
	var eq: Array = State.equip.get(m, [])
	while eq.size() < 8:
		eq.append(0)
	State.equip[m] = eq
	return eq


func _candidates(m: int, slot: int) -> Array:
	var sub: int = SLOTS[slot][1]
	var bit := 1 << (m - 1)
	var out: Array = [0]   # 0 = 卸下
	for it in State.items:
		var r := Battle.obj(int(it))
		if int(State.items[it]) > 0 and int(r.get("sub", 0)) == sub and int(r.get("users", 7)) & bit:
			out.append(int(it))
	return out


## 装备页: 立绘面板 0x4816cf(62,70): 名字 (+41,+14) 等级「%2d」(+210,+14)「级」(+230,+14), 左右箭头 0082 第 7/6 帧 (+20/+250,+14);
##   生命 / 灵力 / 体力: 标签 (+163, +72/116/160), 数值「%d/%-4d」(+195, +90/134/178), 图标 0266 (+170, +100/143/187), 条 (+183, +98/142/186);
##   累计经验值 (+163,+202) 数值 (+175,+220); 攻击 / 防御 / 速度 (+35, +310/332/354), 仙攻 / 仙防 (+160, +310/332) 「      %-4d」
## 装备栏 0x480a04(360,70): 标题「角色所有装备」(+52,+13); 第 k 栏名称 (+62, +58+46k), 选中 (+47, +50+46k, 155×32)
## 可换装备 0x480ea9(355,272): 标题「目前装备」+栏位 (+60,+5), 当前装备名 (+70,+20), 第 i 行 名字 (+15, +52+25i) 数量「%2d」(+170)
func _draw_equip() -> void:
	var m: int = _members[_who]
	var p := Vector2(lerpf(-200, 62, _slide(0)), 70)
	_img(EQUIP_UI % (m - 1), p)
	var d := State.member(m)
	if _members.size() > 1:
		_img(EQUIP_UI % 7, p + Vector2(20, 14))
		_img(EQUIP_UI % 6, p + Vector2(250, 14))
	_text(MEMBER_NAMES.get(m, ""), p + Vector2(41, 14), 16, DARK_COL)
	_text("%2d" % int(d.lv), p + Vector2(210, 14), 16)
	_text("级", p + Vector2(230, 14), 16, DARK_COL)
	var rows := [["生命:", int(d.hp), int(d.hp_max), 0 if m == 1 else 1, 17 if m == 1 else 18],
		["灵力:", int(d.mp), int(d.mp_max), 2, 19], ["体力:", int(d.sp), int(d.sp_max), 3, 20]]
	for i in 3:
		var r: Array = rows[i]
		var dy := 44 * i
		_text(str(r[0]), p + Vector2(163, 72 + dy), 14, DARK_COL)
		_text("%d/%-4d" % [r[1], r[2]], p + Vector2(195, 90 + dy), 12)
		_img(ICON3 % int(r[3]), p + Vector2(170, 100 + dy) - ICON3_PC)
		_img(EL % 16, p + Vector2(183, 98 + dy))
		var bar := tex(EL % int(r[4]))
		var w := 80.0 * float(r[1]) / maxf(float(r[2]), 1.0)
		if bar and w > 0:
			_c.draw_texture_rect_region(bar, Rect2(p + Vector2(183, 98 + dy), Vector2(w, 8)), Rect2(0, 0, w, 8))
	_text("累计经验值:", p + Vector2(163, 202), 12, DARK_COL)
	_text("%d" % int(d.exp), p + Vector2(175, 220), 12)
	var cur := State.member_stats(m)
	var nxt := cur
	var eq := _equip_of(m)
	if _choose:
		var c: Array = _candidates(m, _slot)
		var old := int(eq[_slot])
		eq[_slot] = int(c[_csel])
		nxt = State.member_stats(m)
		eq[_slot] = old
	var stats := [["攻击:", "atk", 35, 310], ["防御:", "def", 35, 332], ["速度:", "spd", 35, 354],
		["仙攻:", "matk", 160, 310], ["仙防:", "mdef", 160, 332]]
	for st in stats:
		var at := p + Vector2(float(st[2]), float(st[3]))
		_text(str(st[0]), at, 14, DARK_COL)
		_text("      %-4d" % int(cur[st[1]]), at + Vector2(0, 1), 14)
		if _choose and int(nxt[st[1]]) != int(cur[st[1]]):
			var up: bool = int(nxt[st[1]]) > int(cur[st[1]])
			_text("→%d" % int(nxt[st[1]]), at + Vector2(84, 1), 14, Color8(40, 120, 40) if up else GREY_COL)
	# 装备栏
	var s2 := Vector2(lerpf(640, 360, _slide(0)), 70)
	_img(EQUIP_UI % 3, s2)
	_text("角色所有装备", s2 + Vector2(52, 13), 16, DARK_COL)
	for k in 6:
		if k == _slot:
			_c.draw_rect(Rect2(s2 + Vector2(47, 50 + 46 * k), Vector2(155, 32)), Color(1, 1, 1, 0x64 / 255.0))
		var id := int(eq[k])
		_text("%-10s" % (str(Battle.obj(id).get("name", "")) if id else ""), s2 + Vector2(62, 58 + 46 * k), 16)
	var b := Vector2(62, lerpf(600, 478, _slide(0)))
	_img(ITEM_UI % 1, b)
	var sel_id := int(eq[_slot])
	if _choose:
		var cc: Array = _candidates(m, _slot)
		sel_id = int(cc[_csel])
	if sel_id:
		_draw_note(Battle.obj(sel_id), b)
	if _choose:
		var l := Vector2(355, 272)
		_img(EQUIP_UI % 4, l)
		_text("目前装备" + str(SLOTS[_slot][0]), l + Vector2(60, 5), 14, DARK_COL)
		var curid := int(eq[_slot])
		_text(str(Battle.obj(curid).get("name", "")) if curid else "（无）", l + Vector2(70, 20), 14)
		var c2: Array = _candidates(m, _slot)
		for i in mini(c2.size(), 5):
			if i == _csel:
				_c.draw_rect(Rect2(l + Vector2(8, 48 + 25 * i), Vector2(194, 26)), Color(1, 1, 1, 0x64 / 255.0))
			var id2 := int(c2[i])
			_text(str(Battle.obj(id2).get("name", "")) if id2 else "（卸下）", l + Vector2(15, 52 + 25 * i), 14)
			if id2:
				_text("%2d" % int(State.items[id2]), l + Vector2(170, 52 + 25 * i), 14)


func _key_equip(k: int) -> void:
	var m: int = _members[_who]
	if _choose:
		var c: Array = _candidates(m, _slot)
		if k == KEY_DOWN:
			_csel = mini(_csel + 1, c.size() - 1)
		elif k == KEY_UP:
			_csel = maxi(_csel - 1, 0)
		elif k in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
			_do_equip(m, _slot, int(c[_csel]))
		return
	if k == KEY_DOWN:
		_slot = (_slot + 1) % 6
		Game.play_sound(Game.SFX_UI_SELECT)
	elif k == KEY_UP:
		_slot = (_slot + 5) % 6
		Game.play_sound(Game.SFX_UI_SELECT)
	elif k in [KEY_LEFT, KEY_RIGHT]:
		_who = (_who + (1 if k == KEY_RIGHT else _members.size() - 1)) % _members.size()
		Game.play_sound(Game.SFX_UI_PAGE)
	elif k in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
		_choose = true
		_csel = 0
		Game.play_sound(Game.SFX_UI_OK)


func _click_equip(m: Vector2) -> void:
	var s := Vector2(360, 70)
	if _choose:
		var l := Vector2(355, 272)
		if Rect2(l.x, l.y + 48, 210, 25 * 5).has_point(m):
			var i := int((m.y - l.y - 48) / 25)
			var c: Array = _candidates(_members[_who], _slot)
			if i < c.size():
				if i == _csel:
					_key_equip(KEY_ENTER)
				else:
					_csel = i
			return
	if Rect2(s.x + 40, s.y + 50, 170, 46 * 6).has_point(m):
		_slot = clampi(int((m.y - s.y - 50) / 46), 0, 5)
		_choose = true
		_csel = 0
		Game.play_sound(Game.SFX_UI_OK)
	elif Rect2(62, 70, 288, 50).has_point(m):
		_key_equip(KEY_RIGHT)


## 换装备 (0x461bd8 / 0x461da9): 旧装备回背包, 新装备从背包取出
func _do_equip(m: int, slot: int, id: int) -> void:
	var eq := _equip_of(m)
	var old := int(eq[slot])
	if old == id:
		_choose = false
		return
	if id and slot >= 4 and int(eq[9 - slot]) == id and int(State.items.get(id, 0)) < 1:
		_say("已经装备了这件法宝")
		return
	if old:
		State.give_item(old, 1)
	if id:
		State.give_item(id, -1)
	eq[slot] = id
	Game.play_sound(524)
	_choose = false


# ---------------- 系统 (0x48a51e 输入 / 0x48a9e5 绘制; re/verify_save.md §1) ----------------
## 右上角 4 个页签图标: 存档 / 读档 / 设定 / 离开 (原版没有「回标题」); 第一次点只选中, 再点一次 = 确认

const SYS_TAB := "ui/all_sys/0086_000_主介面系统/%03d.png"
const SYS_TIPS := ["存档", "读档", "设定", "离开"]
var _sys_quit := false      # 「确定要离开吗?」确认框
var _sys_set := false       # 设定面板 (子状态 3)
var _set_row := 0
var _sys_qsel := 0
var _sys_bounce := 0.0


func _sys_tab_at(m: Vector2) -> int:
	# 命中区左边界不随 i 增加 (原版 bug, 和记载页一样): [450,476) [476,511) [511,546) [546,581)
	if m.y < 6 or m.y >= 38 or m.x < 450:
		return -1
	for i in 4:
		if m.x < 476 + 35 * i:
			return i
	return -1


func _draw_system() -> void:
	if not _sys_quit and not _sys_set:   # 进入子画面后弹跳停住
		_sys_bounce += get_process_delta_time() * 35.0
	var y := UiAct.bounce(8, int(_sys_bounce))   # 0x489f04
	for i in 4:
		if i != _ssel:
			_img(SYS_TAB % (i + 4), Vector2(450 + 35 * i, 6))
	_img(SYS_TAB % (_ssel + 8), Vector2(450 + 35 * _ssel, y))
	var hv := _sys_tab_at(mouse())
	_text(SYS_TIPS[hv if hv >= 0 else _ssel], Vector2(60, 565), 20, Color8(89, 63, 32))
	if _sys_set:
		_draw_settings()
	if _sys_quit:
		var r := Rect2(144, 100, 370, 64)
		Dialog.draw_nine(_c, tex(Dialog.SKIN), r)
		var f2: Font = Game.font_body
		var opts := ["离开游戏.", "取消."]
		var x := 159.0 + 20 * 8
		_c.draw_string(f2, Vector2(160, 128), "确定要离开吗?", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.BLACK)
		_c.draw_string(f2, Vector2(159, 127), "确定要离开吗?", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)
		for k in 2:
			var w := 20.0 * str(opts[k]).length()
			if k == _sys_qsel and tex(Dialog.BAR):
				_c.draw_texture_rect(tex(Dialog.BAR), Rect2(x - 4, 106, w + 8, 28), false, Color(1, 1, 1, 120 / 255.0))
			_c.draw_string(f2, Vector2(x + 1, 128), opts[k], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.BLACK)
			_c.draw_string(f2, Vector2(x, 127), opts[k], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)
			x += w + 28


# ---- 设定面板 (0x48aa7b; re/verify_save.md §1.5) ----
## 面板 0086/001 (487×441) 画在 (100,70), 6 行行距 66: 3 条滑杆 (文字速度 / 音乐 / 音效) + 3 个二选一开关
## 后 3 个开关按原版代码的用法 (0x477d28 / 0x47a3f6): 场景特效 开/关 ([0xbcf448]=0 才更新绘制特效列表 0x48fc24),
## 第 5 项「任务更新提示」开/关 = 旗标 38 (关 → 置位, 剧情脚本里 282 处 if_flag_goto 38 跳过「任务更新」提示框;
## 原版在进地图 0x4688cf 和关系统页 0x489f91 时同步), 镜头模式 模式二 = 鼠标到屏幕左右边缘 (x<10 / x>790) 时每帧转 2°
const SET_ROWS := [["text_speed", "慢", "快"], ["music", "小", "大"], ["sfx", "小", "大"],
	["effects", "开", "关"], ["quest_tip", "开", "关"], ["cam_mode", "模式一", "模式二"]]
const SET_TRACK := Rect2(272, 0, 218, 14)


static func setting(key: String) -> float:
	match key:
		"music", "sfx":
			return float(Game.get_setting("audio", key, 0.8))
		"text_speed":
			return float(Game.get_setting("ui", key, 0.4))
	return float(Game.get_setting("ui", key, 0))


static func set_setting(key: String, v: float) -> void:
	Game.set_setting("audio" if key in ["music", "sfx"] else "ui", key, v)
	if key == "quest_tip":
		sync_quest_tip()


static func sync_quest_tip() -> void:
	State.set_flag(38, int(setting("quest_tip")) == 1)


func _set_row_y(i: int) -> float:
	return 70 + 53 + 66 * i


func _draw_settings() -> void:
	_img(SYS_TAB % 1, Vector2(100, 70))
	_text("轩辕剑外传 苍之涛 V1.04", Vector2(250, 70), 16, Color8(89, 63, 32))
	_text("设定后请按Esc离开", Vector2(400, 490), 16, Color8(89, 63, 32))
	for i in 6:
		var y := _set_row_y(i)
		var r: Array = SET_ROWS[i]
		var v := setting(str(r[0]))
		if i < 3:
			var bar := tex("ui/all_sys/0253_000_设定滑轨棒/000.png")
			var w := SET_TRACK.size.x * clampf(v, 0.0, 1.0)
			if bar and w > 0:
				_c.draw_texture_rect_region(bar, Rect2(SET_TRACK.position.x, y - 7, w, 14), Rect2(0, 0, bar.get_width() * w / SET_TRACK.size.x, bar.get_height()))
			_text(str(r[1]), Vector2(248, y - 8), 16)
			_text(str(r[2]), Vector2(496, y - 8), 16)
		else:
			_img(SYS_TAB % 3, Vector2(254 + 90 * int(v), y - 6))
			_text(str(r[1]), Vector2(270, y - 8), 16)
			_text(str(r[2]), Vector2(360, y - 8), 16)
		if i == _set_row:
			_img(SYS_TAB % 2, Vector2(130, y - 7))


func _key_settings(k: int) -> void:
	var r: Array = SET_ROWS[_set_row]
	var key := str(r[0])
	if k == KEY_DOWN:
		_set_row = (_set_row + 1) % 6
		Game.play_sound(Game.SFX_UI_SELECT)
	elif k == KEY_UP:
		_set_row = (_set_row + 5) % 6
		Game.play_sound(Game.SFX_UI_SELECT)
	elif k in [KEY_LEFT, KEY_RIGHT]:
		var d := -1 if k == KEY_LEFT else 1
		if _set_row < 3:
			set_setting(key, clampf(snappedf(setting(key) + 0.1 * d, 0.05), 0.0, 1.0))
		else:
			set_setting(key, 0 if d < 0 else 1)
		Game.play_sound(Game.SFX_UI_SELECT)


func _click_settings(m: Vector2) -> void:
	for i in 6:
		var y := _set_row_y(i)
		if absf(m.y - y) > 16:
			continue
		_set_row = i
		var key := str(SET_ROWS[i][0])
		if i < 3 and m.x >= SET_TRACK.position.x - 10 and m.x <= SET_TRACK.end.x + 10:
			set_setting(key, clampf((m.x - SET_TRACK.position.x) / SET_TRACK.size.x, 0.0, 1.0))
			Game.play_sound(Game.SFX_UI_SELECT)
		elif i >= 3:
			for v in 2:
				if absf(m.x - (260 + 90 * v)) < 30:
					set_setting(key, v)
					Game.play_sound(Game.SFX_UI_SELECT)


func _sys_quit_rect(k: int) -> Rect2:
	return Rect2(155 + 160 + (0.0 if k == 0 else 20 * 5 + 28), 106, 20.0 * (5 if k == 0 else 3) + 8, 28)


func _key_system(k: int) -> void:
	if _sys_set:
		_key_settings(k)
		return
	if _sys_quit:
		if k in [KEY_LEFT, KEY_UP]:   # 0x465656: 不循环, 到头也播 0x201
			_sys_qsel = 0
			Game.play_sound(0x201)
		elif k in [KEY_RIGHT, KEY_DOWN]:
			_sys_qsel = 1
			Game.play_sound(0x201)
		elif k in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
			_sys_quit_pick(_sys_qsel)
		return
	if k == KEY_RIGHT:
		_ssel = (_ssel + 1) % 4
		Game.play_sound(Game.SFX_UI_SELECT)
	elif k == KEY_LEFT:
		_ssel = (_ssel + 3) % 4
		Game.play_sound(Game.SFX_UI_SELECT)
	elif k in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
		_sys_confirm()


func _click_system(m: Vector2) -> void:
	if _sys_set:
		_click_settings(m)
		return
	if _sys_quit:
		for k in 2:
			if _sys_quit_rect(k).has_point(m):
				_sys_quit_pick(k)
		return
	var i := _sys_tab_at(m)
	if i < 0:
		return
	if i == _ssel:
		_sys_confirm()
		return
	Game.play_sound(Game.SFX_UI_SELECT)
	_ssel = i


func _sys_quit_pick(k: int) -> void:
	Game.play_sound(Game.SFX_UI_OK)
	_sys_quit = false
	k = Game.take_answer(k)   # 0x46559d: 有「已取消」标记时当成 −1 (回到系统页)
	Game.cancel_lock = 0      # 0x48a6bc: 回答之后清 0
	if k == 0:
		if OS.get_cmdline_user_args().has("--autoplay"):
			print("AP QUIT via system menu %s" % str(get_stack()))
		get_tree().quit()


func _sys_confirm() -> void:
	match _ssel:
		0:
			# 禁存地图 (MAPS.DAT seg5 flags & 0x10, 基本是迷宫和山路)
			if field and int(field.map_info.get("flags", 0)) & 0x10:
				Game.play_sound(Game.SFX_UI_ERROR)
				_say("现在不能存档!!")
				return
			Game.play_sound(Game.SFX_UI_OK)
			_sys_screen("save")
		1:
			Game.play_sound(Game.SFX_UI_OK)
			_sys_screen("load")
		2:
			Game.play_sound(Game.SFX_UI_OK)
			_sys_set = true
			_set_row = 0
		3:
			Game.play_sound(Game.SFX_UI_OK)
			_sys_quit = true
			_sys_qsel = 0
			Game.cancel_lock = 1   # 0x48a866: 显示「确定要离开吗?」前置 1


func _sys_screen(mode: String) -> void:
	var s := SaveLoadScreen.new()
	s.mode = mode
	s.thumb = field.menu_thumb if field else null   # 用打开菜单前截的场景画面
	s.field = field
	add_child(s)
	var loaded: bool = await s.closed
	if loaded:
		get_tree().change_scene_to_file("res://scenes/field.tscn")
