class_name BattleHud
extends CanvasLayer
## 战斗界面 (按原版绘制函数还原, 800×600 坐标; 素材 all_sys 0074 战斗主要零件 = ACT 9302 第 qq 帧):
##   底框 0x4510a5: qq0 (0,480) qq1 (0,430) qq0 (775,540) 齿轮 qq12 (720,490) 木条 qq2 (0,565)
##   右下按钮 0x451210: 自动攻击 qq3/4 (723,570), 逃跑 qq6/7 (746,570); 自动中在 (650,570) 显示 qq37「自動攻擊」
##   队员面板 0x43eb4a: 第 k 个面板原点 (40+200k, 415) (三种滑入方式之一, 0x43fbb4), 头像 / 名牌 / 绝技条 / 生命灵力体力条
##   行动条 0x451330: 木槽 qq27/28 在 (545,50), 标记 x = 548 + 行动值×155/1000; 我方菱形 qq29 + 人头 (y 25), 敌方 qq30 + 种族图标 (y 55)
##   目标信息 0x45a1e9: 名牌 qq24 (10,5), 名字 (86,12) 居中, 生命条 qq25/26 (51,34)
##   指令环 0x455266: 中心齿轮 qq12 (500,150); 主环按钮 qq13/14 上 (532,111) 下 (532,251) 左 (462,181) 右 (602,181),
##     子环按钮 qq16/17/18 上 (532,121) 下 (532,241) 左 (472,181) 右 (592,181), 中心按钮 qq13 (532,181); 字在按钮 +(11,22), 20px
##   清单 0x457bdc: 底板 0078 第 0 帧 (450,90) 311×316, 标题 (x+150,y+10) 18px 左对齐, 页签 9328 (x+25+32k, y+3),
##     第一行 y+45 行高 25: 名字 x+20, 数量 / 消耗 x+235; 选中行 (x, 行y−8, 275×28) 白 alpha 100; 说明 (x+20, y+250) 每行 15 字
##   数字 9305–9308 (0025 战斗数字系列小, 24×24 格): 红 = 生命伤害, 浅蓝 = 生命回复, 绿 = 灵力, 蓝 = 体力; 9311 失误 / 无效

const MAIN := "ui/all_sys/0074_9302_战斗主要零件/%03d.png"
const LIST := "ui/all_sys/0078_9303_战斗清单零件/%03d.png"
const TABS := "ui/all_sys/0029_9328_种类Icon/%03d.png"
const HEADS := "ui/all_sys/0034_9326_人头Icon/%03d.png"
const RACE := "ui/all_sys/0134_000_种族分类icon/%03d.png"
const DIGITS := "ui/all_sys/0025_9305_战斗数字系列小/%03d.png"
const MISS := "ui/all_sys/0026_9311_失误与无效/000.png"
## 选目标标记 (0x4550e1 → 0x4559ca, 状态 3): ACT 9109 qq2 = 3D 模型 SYS00017 (21 帧各 1 逻辑帧循环), 用 0x46ade2 画在
## 目标模型 3 号挂点的世界坐标, 不旋转、不偏移; 播放器 0x9efdf8 + 槽 × 0x114 从不清零 (换目标接着播)。
## 以前画的是 0228 的图 —— 那是行动条等待时的鼠标沙漏 (9109 qq0), 不是目标标记
const MARK_GLB := "models/SYS/SYS00017.glb"
var _marks: Array = []
var _mark_t := 0.0


func _update_marks(delta: float) -> void:
	var ts: Array = [cursor_unit] if cursor_unit and cursor_unit.actor else []
	while _marks.size() < ts.size():
		var n := Game.load_glb(MARK_GLB)
		if n == null:
			return
		bt.world_node().add_child(n)
		_marks.append(n)
	_mark_t += delta
	var f := int(_mark_t / Battle.TICK) % 21
	for i in _marks.size():
		var n: Node3D = _marks[i]
		n.visible = i < ts.size()
		if not n.visible:
			continue
		var u: BattleUnit = ts[i]
		var w: Variant = bt.marker_world(u, 3)
		n.global_position = w if w != null else u.actor.global_position
		for ap in n.find_children("*", "AnimationPlayer", true, false):
			var p := ap as AnimationPlayer
			var names := p.get_animation_list()
			if names.is_empty():
				continue
			var an := p.get_animation(names[0])
			if p.current_animation != names[0]:
				p.play(names[0])
				p.pause()
			p.seek(an.length * float(f) / 20.0, true)
const TEXT_COL := Color8(117, 76, 36)       # 调色板 15
const SHADOW_COL := Color8(234, 217, 182)   # 调色板 22
const GREY_COL := Color8(192, 80, 88)       # 调色板 20 (不能用的条目)
const RING_MAIN := [Vector2(532, 111), Vector2(532, 251), Vector2(462, 181), Vector2(602, 181)]
const RING_SUB := [Vector2(532, 121), Vector2(532, 241), Vector2(472, 181), Vector2(592, 181)]
const RING_CENTER := Vector2(532, 181)
const LIST_POS := Vector2(450, 90)
const LIST_ROWS := 8
## 状态小图标 9319 qq0–7 (0013 每组 6 帧, 末帧 30×30): 毒 睡 石化 咒封 心喜 爆怒 悲哀 狂乐
const STATUS_ICON := [0x4, 0x8, 0x10, 0x20, 0x40, 0x80, 0x100, 0x200]
## 增减益图标 9321: qq 2k 上升 / 2k+1 下降 — 攻击 仙攻 防御 仙防 速度
const BUFF_ICON := {"atk": 0, "matk": 2, "def": 4, "mdef": 6, "spd": 8}

var bt: Node                     # Battle
var auto := false                # 自动攻击
var want_escape := false         # 按了逃跑按钮 (下一个我方回合执行)
var target: BattleUnit           # 左上角显示的目标
var cursor_unit: BattleUnit      # 选目标时的游标
var _c: Control
var _tex := {}
var _t := 0.0
var _slide := {}                 # 面板滑入: 单位 → 当前偏移
var _ring: Dictionary = {}       # 正在显示的指令环
var _list: Dictionary = {}       # 正在显示的清单
var _pops: Array = []            # 飘字 [{unit, kind, n, t, off}]


var _add: Control
var _band: TextureRect
## 吟咒光圈 (0x432135 → ACT 8123 = all_magic 0005_升级特效, 缩 0.6): QQ2 吟咒中 = 帧 1..28 + 54..63 循环; QQ1 被打断 = 帧 1..63 播一次
const CHANT_FX := "ui/all_magic/0005_升级特效/%03d.png"
const CHANT_LOOP := [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28,
	54, 55, 56, 57, 58, 59, 60, 61, 62, 63]


func _draw_add() -> void:
	for u in bt.units:
		if u == null or u.absent or u.actor == null or u.chant_fx == 0:
			continue
		var x: float = 548.0 + u.gauge * 155.0 / 1000.0
		var y := 25.0 if u.party else 55.0
		var f := int(u.chant_fx_t / Battle.TICK)   # 吟咒光圈 ACT 8123 逐帧播 (战斗 27 帧/秒)
		var fr := 0
		if u.chant_fx == 2:
			fr = CHANT_LOOP[f % CHANT_LOOP.size()]
		else:
			if f >= 63:
				u.chant_fx = 0
				continue
			fr = f + 1
		var t := tex(CHANT_FX % fr)
		if t:
			_add.draw_texture_rect(t, Rect2(x + 8 - 38.4, y + 10 - 38.4, 76.8, 76.8), false)


func _ready() -> void:
	layer = 6
	for a in OS.get_cmdline_user_args():   # 调试: --press-auto=秒 开战后这么久模拟按下「自动」
		if a.begins_with("--press-auto="):
			get_tree().create_timer(float(a.substr(13))).timeout.connect(func(): auto = true)
	_c = Control.new()
	_c.size = Vector2(800, 600)
	_c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_c.draw.connect(_draw)
	add_child(_c)
	# 小游戏 / 护驾清单背景带 0x45b5f4 (黑色渐层 ACT 9317, 混合模式 4 = SRC×INVDESTALPHA + DST×INVSRCCOLOR; 后台缓冲没有 alpha →
	# 目标 alpha 读作 1, 源项为 0 → 结果 = 背景 × (1 − 贴图色): 中间灰色部分把背景压暗约一半, 边缘黑色不变。以前当成滤色提亮, 是推测)
	_band = TextureRect.new()
	_band.texture = tex(DARK)
	_band.position = Vector2(0, 75)
	_band.size = Vector2(896, 486)
	_band.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_band.stretch_mode = TextureRect.STRETCH_SCALE
	_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_band.visible = false
	var bsh := Shader.new()
	bsh.code = """shader_type canvas_item;
render_mode blend_mul;
void fragment() {
	COLOR = vec4(vec3(1.0) - texture(TEXTURE, UV).rgb, 1.0);
}
"""
	var bm := ShaderMaterial.new()
	bm.shader = bsh
	_band.material = bm
	add_child(_band)
	move_child(_band, 0)
	# 加法混合的叠加层 (吟咒光圈等)
	_add = Control.new()
	_add.size = Vector2(800, 600)
	_add.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_add.material = mat
	_add.draw.connect(_draw_add)
	add_child(_add)


func tex(path: String) -> Texture2D:
	if not _tex.has(path):
		_tex[path] = Game.load_texture(path)
	return _tex[path]


func main(q: int) -> Texture2D:
	return tex(MAIN % q)


## 正在等玩家操作 (调试按键用)
func awaiting_input() -> bool:
	return not _ring.is_empty() or not _list.is_empty() or cursor_unit != null


func _process(delta: float) -> void:
	_t += delta
	_cursor()
	_update_marks(delta)
	for u in bt.units:
		if u and u.chant_fx != 0:
			u.chant_fx_t += delta
	_add.queue_redraw()
	for k in _slide.keys():
		_slide[k] = (_slide[k] as Vector2).move_toward(Vector2.ZERO, delta * 1600.0)
	for p in _pops:
		p.t += delta
	_pops = _pops.filter(func(p): return p.t < 1.2)
	_c.queue_redraw()


# ---------------- 绘制 ----------------

## 原版文字 (0x40d9fc): (x, y) 为字格左上角, 半角占字号一半宽、全角占一个字号宽 (格式串靠空格对齐), 逐字排版
func _text(s: String, pos: Vector2, size: int, col := TEXT_COL, center := false, shadow := SHADOW_COL) -> void:
	var f: Font = Game.font_body
	var total := 0.0
	for ch in s:
		total += size * 0.5 + Game.HALF_GAP if ch.unicode_at(0) < 0x80 else float(size)
	var x := pos.x - (total / 2.0 if center else 0.0)
	var base_y := pos.y + size * 0.88
	for ch in s:
		var half := ch.unicode_at(0) < 0x80
		if ch != " ":
			var fs := Game.half_size(size, 3) if half else size   # 半角字缩一点, 数字之间留空
			var w := f.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var cx := x + ((size * 0.5 + Game.HALF_GAP if half else float(size)) - w) * 0.5
			_c.draw_string_outline(f, Vector2(cx, base_y), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, shadow)
			_c.draw_string(f, Vector2(cx, base_y), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		x += size * 0.5 + Game.HALF_GAP if half else float(size)


func _img(t: Texture2D, pos: Vector2, mod := Color.WHITE) -> void:
	if t:
		_c.draw_texture(t, pos, mod)


## 只画贴图左边 w 像素 (进度条)
func _img_w(t: Texture2D, pos: Vector2, w: float) -> void:
	if t and w > 0:
		var sz := t.get_size()
		_c.draw_texture_rect_region(t, Rect2(pos, Vector2(minf(w, sz.x), sz.y)), Rect2(Vector2.ZERO, Vector2(minf(w, sz.x), sz.y)))


## 界面 ACT 动画 (ui/acts.json, tools/export_ui_acts.py): 帧表 [[图, 停留帧数, 锚点 x, 锚点 y], ...]
static var _acts: Dictionary = {}


func ui_act(act: int, qq: int) -> Array:
	if _acts.is_empty():
		var p := Game.asset_path("ui/acts.json")
		if FileAccess.file_exists(p):
			_acts = JSON.parse_string(FileAccess.get_file_as_string(p))
	return _acts.get(str(act), {}).get(str(qq), {}).get("frames", [])


## 第 t 帧 (逻辑帧) 的帧; loop = 循环, 否则停在末帧
func _act_frame(act: int, qq: int, t: int, loop: bool) -> Array:
	var fr := ui_act(act, qq)
	if fr.is_empty():
		return []
	var total := 0
	for f in fr:
		total += int(f[1])
	if loop and total > 0:
		t = t % total
	for f in fr:
		t -= int(f[1])
		if t < 0:
			return f
	return fr[fr.size() - 1]


## 0x46ad17 / 0x46a983: 画在 (点 − 锚点), 放大以 (点 − 锚点 × 放大) 为原点
func _draw_act(f: Array, pos: Vector2, scale := 1.0) -> void:
	if f.is_empty():
		return
	var t := tex(str(f[0]))
	if t == null:
		return
	if f.size() > 4 and f[4] is Array:   # 图集格子 (IS / PS)
		var r := Rect2(f[4][0], f[4][1], f[4][2], f[4][3])
		_c.draw_texture_rect_region(t, Rect2(pos - Vector2(f[2], f[3]) * scale, r.size * scale), r)
	else:
		_c.draw_texture_rect(t, Rect2(pos - Vector2(f[2], f[3]) * scale, t.get_size() * scale), false)


func _draw_swim() -> void:
	var s: Dictionary = bt.swim
	if int(s.sub) == 0:
		_draw_act(_act_frame(9331, 0, int(s.t), false), Vector2(380, 480))
	elif int(s.sub) == 1:
		_draw_act(_act_frame(9324, 0, int(s.t), true), Vector2(390, 500))
	var v := maxi(int(s.value), 0)
	var digits := [[v / 1000 % 10, Vector2(460, 100), 1.5], [v / 100 % 10, Vector2(510, 100), 1.5],
		[v / 10 % 10, Vector2(570, 110), 1.2], [v % 10, Vector2(610, 110), 1.2]]
	for d in digits:
		_draw_act(_act_frame(9314, int(d[0]), 0, true), d[1], d[2])


func _draw() -> void:
	if bt == null:
		return
	if not bt.puzzle.is_empty():
		_draw_puzzle()
		return
	_draw_enemy_icons()
	_draw_atb()
	# 0x45108a: [0x4e38a0] ≠ 1 时下方面板、队员栏、自动 / 逃跑按钮都不画 (按钮的鼠标点击也在这段里, 一起失效)
	if bt.hud_panel and spy == null and not bt.end_hide_panel:   # 0x451072: 战斗结束 ([0x9253ac]) 后不画   # 0x451099: 视破面板开着时不画下方队伍栏
		_draw_bottom()
	_draw_target()
	if not _ring.is_empty():
		_draw_ring()
	_band.visible = str(_mg.get("kind", "")) in ["longfan", "suanchi"] or not _gl.is_empty()
	if _band.visible:   # 0x45b5f4 缩放增量: 小游戏 (2.5, 0.9), 护驾清单 (2.5, 0.6); 基础缩放 1
		_band.size = Vector2(256 * 3.5, 256 * (1.6 if not _gl.is_empty() else 1.9))
	if not _mg.is_empty():
		_draw_mg()
	if not _list.is_empty():
		_draw_list()
	_draw_rest()


func _draw_bottom() -> void:
	# 底框
	_img(main(0), Vector2(0, 480))
	_img(main(1), Vector2(0, 430))
	_img(main(0), Vector2(775, 540))
	_img(main(12), Vector2(720, 490))
	_img(main(2), Vector2(0, 565))
	var k := 0
	for u in bt.units:
		if u and u.party and not u.absent and u.actor and not u.summon:   # 护驾没有队员面板
			_draw_panel(u, Vector2(40 + 200 * k, 415) + _slide.get(u, Vector2.ZERO))
			k += 1
	if auto:
		_img(main(37), Vector2(650, 570))
	var m := _c.get_local_mouse_position()
	_img(main(4 if auto or Rect2(723, 570, 20, 20).has_point(m) else 3), Vector2(723, 570))
	# 逃跑按钮: [0x9253d0] = 0 且战斗状态 ∈ {1, 2, 4–12} (指令环 / 清单等, 不含 3 选目标) 时才画 (0x45126e)
	if not bt.no_escape and escape_shown():
		_img(main(7 if want_escape or Rect2(746, 570, 20, 20).has_point(m) else 6), Vector2(746, 570))


func escape_shown() -> bool:
	return (not _ring.is_empty() or not _list.is_empty()) and cursor_unit == null


# ---------------- 视破面板 (0x4515d8, 由战斗绘制 0x4425ac 在 [0x925950] ≠ 0 时画) ----------------
var spy: BattleUnit = null
const SPY_LABEL := Color8(234, 217, 182)   # 调色板 22
const SPY_VALUE := Color8(237, 192, 95)    # 调色板 24
const ELEM_NAMES := ["木", "火", "土", "金", "水"]


func _spy_text(s: String, p: Vector2, col: Color) -> void:
	# 20px 字体 0xa79288, 模式 4 (对白画法: 带阴影); 字顶 + 17 为基线 (同对白框)
	var f := Dialog.talk_font()
	_c.draw_string(f, p + Vector2(1, 18), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0, 0, 0))
	_c.draw_string(f, p + Vector2(0, 17), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, col)


## 原版布局: 黑底 ACT 9301 qq0 (黑图 64×64, 按 CS 放大约 605×399, alpha 100) 画在 (100,105); 九宫格 9008 (100,100,600,400) 只画边框;
## 左列标签 x=150 / 数值 x=220, y = 140 + 30k; 右列标签 x=420 / 数值 x=490 (物品、技能在 x=540)。
## 原版的错位照搬: 「仙攻」行显示的是速度, 「仙防」行是仙攻, 「速度」行是仙防 (0x4515d8 调用顺序 0x437186 / 0x437005 / 0x436fae)
func _draw_spy() -> void:
	var t := spy
	_c.draw_rect(Rect2(100, 105, 605, 399), Color(0, 0, 0, 100 / 255.0))
	Dialog.draw_nine(_c, tex(Dialog.SKIN), Rect2(100, 100, 600, 400), false, false)
	var joy := t.has(Formula.ST_JOY)
	var matk := t.stat("matk") + (t.base_stat("matk") / 5 if joy else 0)
	var mdef := t.stat("mdef")
	var el := "无"
	var e: Array = t.rec.get("elem", [])
	for i in mini(5, e.size()):
		if int(e[i]) > 0:
			el = ELEM_NAMES[i]
			break
	var rows := [["名称", t.name], ["等级", str(t.level)], ["生命", "%d/%d" % [t.hp, t.hp_max]], ["灵力", "%d/%d" % [t.mp, t.mp_max]],
		["体力", "%d/%d" % [t.sp, t.sp_max]], ["攻击", str(t.stat("atk"))], ["防御", str(t.stat("def"))],
		["仙攻", str(t.eff_speed())], ["仙防", str(matk)], ["速度", str(mdef)], ["属性", el]]
	for k in rows.size():
		_spy_text(rows[k][0], Vector2(150, 140 + 30 * k), SPY_LABEL)
		_spy_text(str(rows[k][1]), Vector2(220, 140 + 30 * k), SPY_VALUE)
	var cr: Array = t.rec.get("craft", [0, 0, 0, 0])
	var names := ["冶金", "整备", "制药", "神技"]
	for k in 4:
		_spy_text(names[k], Vector2(420, 260 + 30 * k), SPY_LABEL)
		_spy_text(str(int(cr[k]) if k < cr.size() else 0), Vector2(490, 260 + 30 * k), SPY_VALUE)
	var dr: Array = t.rec.get("drops", [])
	var item := int(dr[1][1]) if dr.size() > 1 else 0
	_spy_text("身上物品", Vector2(420, 410), SPY_LABEL)
	_spy_text(str(Battle.obj(item).get("name", "无")) if item > 0 else "无", Vector2(540, 410), SPY_VALUE)
	var sk := int(t.rec.get("special_skill", 0))
	_spy_text("可学习技能", Vector2(420, 440), SPY_LABEL)
	_spy_text(str(Battle.obj(sk).get("name", "无")) if sk > 0 else "无", Vector2(540, 440), SPY_VALUE)


func _draw_rest() -> void:
	if spy:
		_draw_spy()
	if not _gl.is_empty():
		_draw_guard_list()
	for p in _pops:
		_draw_pop(p)
	_draw_symbols()
	if not _result.is_empty():
		_draw_result()
	if not _wheel.is_empty():
		_draw_wheel()
	# 小游戏画在战斗界面之后 (0x4426b3 界面 → 0x4426c9 小游戏 0x45205a)
	if not bt.swim.is_empty():
		_draw_swim()


## 队员面板 (0x43eb4a), o = 面板原点
func _draw_panel(u: BattleUnit, o: Vector2) -> void:
	match u.member:
		2:
			_img(main(11), o + Vector2(5, 52))
		3:
			_img(main(9), o + Vector2(5, 6))
		_:
			_img(main(10), o + Vector2(0, 55))
	var x := o.x + 105
	var y := o.y + 40
	_img(main(23 if bt.active == u else 22), Vector2(x, y))
	_text(u.name, Vector2(x + 40, y + 3), 16, TEXT_COL, true)
	# 绝技 (蓄劲值) 条: 宽 = 值/2, 满 60 闪烁
	y += 28
	_img(tex("ui/all_sys/0133_9304_战斗绝技bar/000.png"), Vector2(x, y))
	if u.juji > 0:
		var a := 1.0 if u.juji < 60 else 0.55 + 0.45 * absf(sin(_t * 4.0))
		var bar := tex("ui/all_sys/0133_9304_战斗绝技bar/001.png")
		if bar:
			_c.draw_texture_rect_region(bar, Rect2(Vector2(x, y), Vector2(u.juji / 2.0, 6)), Rect2(0, 0, u.juji / 2.0, 6), Color(1, 1, 1, a))
	_text("%3d" % u.juji, Vector2(x + 55, y - 4), 12)
	# 生命 (云狐用橙色) / 灵力 / 体力: 条宽 = 值×80/上限, 有值时至少 2
	var rows := [[u.hp, u.hp_max, 33 if u.member == 1 else 36], [u.mp, u.mp_max, 34], [u.sp, u.sp_max, 35]]
	for r in rows:
		y += 18
		_img(main(32), Vector2(x, y))
		var w := int(r[0]) * 80 / maxi(int(r[1]), 1)
		if w <= 1 and int(r[0]) > 0:
			w = 2
		_img_w(main(int(r[2])), Vector2(x, y), w)
		_text(str(r[0]), Vector2(x + 10, y - 9), 12)
	# 状态图标 (0x43efd8): 从 (x−45, y+10) 起每行 5 个, 间距 30×25; 先法宝 (完璧 9318 qq0 / 挪移 qq2), 再状态 / 增减益
	var icons: Array = []
	if u.wanbi_turns > 0:
		icons.append(tex("ui/all_sys/0021_9318_法宝Icon/000.png"))
	if u.redirect:
		icons.append(tex("ui/all_sys/0021_9318_法宝Icon/002.png"))
	icons.append_array(_status_icons(u))
	for i in icons.size():
		_img(icons[i], Vector2(x - 45 + 30 * (i % 5), y + 10 + 25 * (i / 5)))


## 状态 / 增减益图标: 每个节点自带播放器, 新挂上时从头播 ACT 9319 (状态) / 9321 (增减益) 的 6 帧 × 6 逻辑帧, 停在末帧
func _status_icons(u: BattleUnit) -> Array:
	var out: Array = []
	var now := Time.get_ticks_msec()
	var fr := func(key: Variant) -> int:
		var ms: int = now - int(u.status_born.get(key, 0))
		return mini(int(ms / 1000.0 / Battle.TICK) / 6, 5)
	for i in STATUS_ICON.size():
		if u.status & int(STATUS_ICON[i]):
			out.append(tex("ui/all_sys/0013_9319_状态Icon小/%03d.png" % (6 * i + fr.call(int(STATUS_ICON[i])))))
	for k in BUFF_ICON:
		if u.buffs.has(k):
			var up := int(u.buffs[k][0]) >= 0
			out.append(tex("ui/all_sys/0003_9321_数值Icon小/%03d.png" % (6 * (int(BUFF_ICON[k]) + (0 if up else 1)) + fr.call(k))))
	return out


## 拼图画面 (0x453a5e 绘制顺序): 底图 9332 qq0 (0,0) → 子状态 3 的四行说明 (12px, 调色板 22, 调色板 14 阴影) →
## 计时 "%02d:%02d" (650,50) → 不在手上的图块 (编号 0..11 顺序; ACT 9333 qq 编号, 缩放 0.625, 角度 朝向 × 90°, 画在格子点
## (194+136列, 193+136行)) → 光标光棒 (120+136列, 120+136行, 145×145, alpha 150) → 外框 9332 qq1 (80,90) → 手上的图块 (鼠标 − 抓取偏移)
## 未确定: 图块绘制的锚点 / 旋转中心和旋转方向 (这里按图块中心、顺时针画; 只影响显示, 判定只看朝向是否为 0)
const PZ_LABEL := Color8(234, 217, 182)
const PZ_SHADOW := Color8(89, 63, 32)


func _pz_text(s: String, p: Vector2) -> void:
	var f := Dialog.talk_font()
	_c.draw_string(f, p + Vector2(0, 12 + 2), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, PZ_SHADOW)
	_c.draw_string(f, p + Vector2(0, 12), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, PZ_LABEL)


func _pz_tile(k: int, at: Vector2, rot: int) -> void:
	var f := UiAct.frame(9333, k, 0)
	if f.is_empty() or f.tex == null:
		return
	var s := 256.0 * 0.625
	_c.draw_set_transform(at, deg_to_rad(90.0 * rot), Vector2.ONE)
	_c.draw_texture_rect_region(f.tex, Rect2(Vector2(-s, -s) * 0.5, Vector2(s, s)), Rect2(0, 0, 256, 256))
	_c.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)


func _draw_puzzle() -> void:
	var z: Dictionary = bt.puzzle
	UiAct.draw(_c, 9332, 0, 0, Vector2.ZERO)
	if int(z.sub) == 3:
		_pz_text("重置拼图 : F1", Vector2(25, 25))
		_pz_text("放弃拼图 : F2", Vector2(25, 40))
		_pz_text("旋转图形 : 鼠标右键 或 Shift", Vector2(25, 55))
		_pz_text("选取图形 : 鼠标左键 或 Enter 或 空白键", Vector2(25, 70))
	var secs := int(z.secs)
	_pz_text("%02d:%02d" % [secs / 60, secs % 60], Vector2(650, 50))
	var b: Array = z.board
	var rot: Array = z.rot
	if b.size() == 12:
		for k in 12:
			var i := b.find(k)
			if i >= 0:
				_pz_tile(k, Battle.puzzle_cell_pos(i), int(rot[k]))
	var cur := int(z.cursor)
	if cur >= 0:
		var bar := tex(Dialog.BAR)
		if bar:
			_c.draw_texture_rect(bar, Rect2(120 + 136 * (cur / 3), 120 + 136 * (cur % 3), 145, 145), false, Color(1, 1, 1, 150 / 255.0))
	UiAct.draw(_c, 9332, 1, 0, Vector2(80, 90))
	if int(z.held) >= 0:
		_pz_tile(int(z.held), _c.get_local_mouse_position() - (z.grab as Vector2), int(rot[int(z.held)]))


## 头顶符号 (0x43385c → 每帧 0x4339c5): 生成时取单位 3 号挂点投影到屏幕, 之后屏幕位置固定; 每帧上移 1 像素,
## 2 帧后不透明度每帧 −10, 到 0 删除; 图 = ACT 9007 qq (两帧各 11 逻辑帧循环, CS 1.4)
var _symbols: Array = []   # [{qq, pos, alpha, n, player}]


func symbol_pop(u: BattleUnit, qq: int) -> void:
	var g: Variant = bt.marker_world(u, 3)
	var w: Vector3 = g if g != null else u.actor.global_position
	var pl := UiAct.Player.new()
	pl.battle = true
	pl.set_state(9007, qq)
	_symbols.append({"pos": bt.screen_pos(w), "alpha": 255, "n": 0, "player": pl, "acc": 0.0})


func _draw_symbols() -> void:
	for s in _symbols.duplicate():
		s.acc = float(s.acc) + get_process_delta_time()
		while float(s.acc) >= Battle.TICK:
			s.acc = float(s.acc) - Battle.TICK
			s.n = int(s.n) + 1
			s.pos = (s.pos as Vector2) - Vector2(0, 1)
			if int(s.n) > 2:
				s.alpha = int(s.alpha) - 10
			(s.player as UiAct.Player).ticks += 1
		if int(s.alpha) <= 0:
			_symbols.erase(s)
			continue
		var f: Dictionary = (s.player as UiAct.Player).current()
		var cs := 1.4
		UiAct.draw_frame(_c, f, s.pos, cs, Color(1, 1, 1, int(s.alpha) / 255.0))


## 敌人头顶状态图标 (0x436309, 单位绘制每帧调用): 挂点 3 的 y 夹到 [150, 500] (没有挂点用单位坐标、y = 150), 投影得 (sx, sy);
## 第 i 个图标画在 (sx + 30i, sy − 15 + 25)
func _draw_enemy_icons() -> void:
	for u in bt.units:
		if u == null or u.party or u.dead or u.absent or u.actor == null or not u.actor.visible:
			continue
		var icons := _status_icons(u)
		if icons.is_empty():
			continue
		var g: Variant = bt.marker_pos(u, 3)
		var p: Vector3 = g if g != null else u.pos()
		if g == null:
			p.y = 150
		p.y = clampf(p.y, 150, 500)
		var s: Vector2 = bt.screen_pos(p * 0.01)
		for i in icons.size():
			_img(icons[i], Vector2(s.x + 30 * i, s.y - 15 + 25))


## 行动条 (0x451330 / 0x432135)
func _draw_atb() -> void:
	_img(main(27), Vector2(545, 50))
	_img(main(28), Vector2(545, 50))
	for u in bt.units:
		if u == null or u.absent or u.dead or u.actor == null:
			continue
		var x: float = 548.0 + u.gauge * 155.0 / 1000.0
		if u.party and u.summon:
			# 护驾: 我方一侧的菱形 + 种族图标
			_img(main(29), Vector2(x, 25))
			var sb2 := int(u.rec.get("sub", 110))
			_img(tex(RACE % (9 if sb2 == 120 else clampi(sb2 - 110, 0, 10))), Vector2(x - 2, 33))
		elif u.party:
			_img(main(29), Vector2(x, 25))
			var head := tex(HEADS % (clampi(u.member - 1, 0, 2) + (3 if bt.active == u else 0)))
			_img(head, Vector2(x - 2, 25 - (8 if u.member == 3 else 3)))
		else:
			_img(main(30), Vector2(x, 55))
			# 种族 (0x46df81): 分类码 − 110, 120 → 9
			var sb := int(u.rec.get("sub", 110))
			var race := 9 if sb == 120 else clampi(sb - 110, 0, 10)
			_img(tex(RACE % race), Vector2(x - 2, 63))


## 目标信息 (0x45a1e9): 选目标时的目标, 或场上只剩一个敌人
func _draw_target() -> void:
	var u := target
	if u == null:
		var es: Array = bt.alive(false)
		if es.size() == 1:
			u = es[0]
	if u == null or u.party:
		return
	_img(main(24), Vector2(10, 5))
	_text(u.name, Vector2(86, 12), 16, TEXT_COL, true)
	_img(main(25), Vector2(51, 34))
	_img_w(main(26), Vector2(51, 34), u.hp * 80 / maxi(u.hp_max, 1))


# ---------------- 指令环 ----------------

## 显示一圈指令, 返回选中的下标 (0 上 / 1 下 / 2 左 / 3 右), 取消返回 -1
## labels[k] 为空 = 空格子; enabled[k] = false 画成不可用。sub = 子环 (中心按钮写 center 文字)
func ring(labels: Array, enabled: Array, sub := false, center := "") -> int:
	_drop_clicks()
	var sel := 0
	while sel < 4 and (str(labels[sel]) == "" or not enabled[sel]):
		sel += 1
	sel = sel % 4
	_ring = {"labels": labels, "enabled": enabled, "sub": sub, "center": center, "sel": sel, "t": 0.0}
	if bt.auto_pick():
		await get_tree().create_timer(0.35).timeout
		_ring = {}
		return sel
	while true:
		await get_tree().process_frame
		if bt.auto_pick():   # 等指令时按了自动 (用户反馈: 原版点一下当前这回合就自动普攻; 0x4505c8 开自动时若正在等指令, 立刻收掉指令环): 退回, 由自动重新选
			_ring = {}
			return -1
		_ring.t += get_process_delta_time()
		var r := _ring_hit()
		var click := _clicked()
		var rclick := _rclicked()
		if r >= 0 and r != _ring.sel and _usable(r):
			_ring.sel = r
			Game.play_sound(Game.SFX_UI_SELECT)
		# 方向键直接选对应方向的按钮 (上 / 下 / 左 / 右); Tab 依次轮换
		var dirs := ["ui_up", "ui_down", "ui_left", "ui_right"]
		for d in 4:
			if Input.is_action_just_pressed(dirs[d]) and _usable(d) and _ring.sel != d:
				_ring.sel = d
				Game.play_sound(Game.SFX_UI_SELECT)
		if Input.is_action_just_pressed("ui_focus_next"):
			_ring.sel = _step(_ring.sel, 1)
		elif Input.is_action_just_pressed("ui_accept") or (r >= 0 and click):
			if _usable(_ring.sel):
				var s: int = _ring.sel
				_ring = {}
				Game.play_sound(Game.SFX_UI_OK)
				return s
			Game.play_sound(Game.SFX_UI_ERROR)
		elif Input.is_action_just_pressed("ui_cancel") or rclick:
			_ring = {}
			Game.play_sound(Game.SFX_UI_CANCEL)
			return -1
	return -1


func _usable(k: int) -> bool:
	return str(_ring.labels[k]) != "" and bool(_ring.enabled[k])


func _step(k: int, d: int) -> int:
	for i in 4:
		k = (k + d + 4) % 4
		if _usable(k):
			return k
	return k


func _ring_pos(k: int) -> Vector2:
	var to: Vector2 = (RING_SUB if _ring.sub else RING_MAIN)[k]
	return RING_CENTER.lerp(to, clampf(float(_ring.t) / 0.15, 0.0, 1.0))


func _ring_hit() -> int:
	var m := _c.get_local_mouse_position()
	for k in 4:
		if Rect2(_ring_pos(k), Vector2(66, 66)).has_point(m):
			return k
	return -1


var _lclick := false   # 上次取走之后有没有按过左键 / 右键 (_input)
var _rclick := false
var _pick_wheel := 0             # 选目标时的滚轮 (0x40ec05)
var _pick_mouse := Vector2.ZERO  # 上一帧鼠标: 没动就不按悬停改目标, 否则键盘选的目标会被鼠标顶回去


## 按事件记点击, 不轮询按键状态: 快速点一下时按下和松开会落在同一帧, 轮询看不到
func _clicked() -> bool:
	var c := _lclick
	_lclick = false
	return c


## 开新界面时丢掉之前的点击 (例: 点「攻击」那一下不算确认目标)
func _drop_clicks() -> void:
	_lclick = false
	_rclick = false


func _rclicked() -> bool:
	var c := _rclick
	_rclick = false
	return c


func _draw_ring() -> void:
	_img(main(12), Vector2(500, 150))
	if _ring.sub:
		_img(main(13), RING_CENTER)
		if str(_ring.center) != "":
			_text(str(_ring.center), RING_CENTER + Vector2(11, 22), 20)
	for k in 4:
		var p := _ring_pos(k)
		var lab := str(_ring.labels[k])
		var q: int
		if _ring.sub:
			q = 18 if lab == "" or not _ring.enabled[k] else (17 if k == _ring.sel else 16)
		else:
			q = 14 if k == _ring.sel and _usable(k) else 13
		_img(main(q), p)
		if lab != "":
			_text(lab, p + Vector2(11, 22), 20, TEXT_COL if _ring.enabled[k] else GREY_COL)


# ---------------- 清单 ----------------

## pages: 每页 [{id, name, right, ok, desc}]; tabs: 0 技能页签 / 1 物品页签 / -1 无页签。返回选中条目的 id, 取消 null
# ---------------- 护驾清单 (指令 0x44fe7c 打开, 绘制 0x458aed(500, 150), 逆向确认) ----------------
## 背景带 0x45b5f4(…, 2.5, 0.6, 0, 75); 左边两行页签: 非当前行 9303 qq4 (440, 150+40k), 种族图标 9027 qq n (460, 155+40k)
##   (n = 子类 120 → 9, 否则 子类 − 110, 最多 10; 子类 0 → 叉叉 9023 qq7); 面板 9303 qq2 (500,150); 当前页签 9303 qq3, 当前图标 n+20 (叉叉 qq8)
## 文字调色板 15; 有可召唤的护驾: 名字 20px (530,160), 体力 / 灵力消耗 (16px, 图标 0266 第 3 / 2 帧 + 箭头 0173 第 1 帧),
##   生命上限 (图标第 1 帧), 等级, 攻击 / 防御 / 仙攻 / 仙防 / 速度, 使用仙术一/二/三;
## 已在场: 标题「%s(召唤中)」, 只列攻防 / 仙攻防 / 速度 / 仙术 (记录原始数值); 两者都不是: 「没有护驾」(570,230)。没有变灰状态
var _gl := {}


func guard_list(rows: Array) -> Variant:
	_drop_clicks()
	_gl = {"rows": rows, "sel": 0}
	_band.size = Vector2(256 * 3.5, 256 * 1.6)
	_band.visible = true
	if bt.auto_pick():
		await get_tree().create_timer(0.4).timeout
		var k := -1
		for i in rows.size():
			if not (rows[i] as Dictionary).is_empty():
				k = i
				break
		_gl = {}
		_band.visible = false
		return k if k >= 0 else null
	var was := true
	while true:
		await get_tree().process_frame
		if bt.auto_pick():   # 中途按了自动: 退回指令环, 由自动战斗重新选
			_gl = {}
			_band.visible = false
			return null
		var m := _c.get_local_mouse_position()
		for k in 2:
			if Rect2(440, 150 + 40 * k, 72, 39).has_point(m) and int(_gl.sel) != k:
				_gl.sel = k
				Game.play_sound(0x201)
		if Input.is_action_just_pressed("ui_up") or Input.is_action_just_pressed("ui_down"):
			_gl.sel = 1 - int(_gl.sel)
			Game.play_sound(0x201)
		var click := _clicked()
		var on_tab := Rect2(440, 150 + 40 * int(_gl.sel), 72, 39).has_point(m) or Rect2(500, 150, 258, 203).has_point(m)
		if Input.is_action_just_pressed("ui_accept") or (click and on_tab):
			var k2 := int(_gl.sel)
			_gl = {}
			_band.visible = false
			return k2
		if Input.is_action_just_pressed("ui_cancel") or _rclicked() or Input.is_key_pressed(KEY_CTRL):
			_gl = {}
			_band.visible = false
			return null
	return null


func _gl_icon(sub: int) -> int:
	return 9 if sub == 120 else mini(sub - 110, 10)


func _draw_guard_list() -> void:
	var rows: Array = _gl.rows
	var sel := int(_gl.sel)
	for k in 2:
		if k == sel:
			continue
		UiAct.draw(_c, 9303, 4, 0, Vector2(440, 150 + 40 * k))
		var r: Dictionary = rows[k].get("rec", {}) if k < rows.size() else {}
		var sub := int(r.get("sub", 0))
		if sub != 0:
			UiAct.draw(_c, 9027, _gl_icon(sub), 0, Vector2(460, 155 + 40 * k))
		else:
			UiAct.draw(_c, 9023, 7, 0, Vector2(460, 155 + 40 * k))
	UiAct.draw(_c, 9303, 2, 0, Vector2(500, 150))
	UiAct.draw(_c, 9303, 3, 0, Vector2(440, 150 + 40 * sel))
	var row: Dictionary = rows[sel] if sel < rows.size() else {}
	var rec: Dictionary = row.get("rec", {})
	var sub2 := int(rec.get("sub", 0))
	if sub2 != 0:
		UiAct.draw(_c, 9027, _gl_icon(sub2) + 20, 0, Vector2(460, 155 + 40 * sel))
	else:
		UiAct.draw(_c, 9023, 8, 0, Vector2(460, 155 + 40 * sel))
	if rec.is_empty():
		_text("没有护驾", Vector2(570, 230), 20)
		return
	var out: bool = row.get("out", false)
	if out:
		_text("%s(召唤中)" % str(rec.get("name", "")), Vector2(530, 160), 20)
	else:
		_text(str(rec.get("name", "")), Vector2(530, 160), 20)
		var c: Dictionary = rec.get("cost", {})
		_img(tex("ui/all_sys/0266_000_命灵体/003.png"), Vector2(675, 170))
		_img(tex("ui/all_sys/0173_000_能力变化小图/001.png"), Vector2(680, 155))
		_text("%3d" % int(c.get("sp", 0)), Vector2(700, 162), 16)
		_img(tex("ui/all_sys/0266_000_命灵体/002.png"), Vector2(675, 195))
		_img(tex("ui/all_sys/0173_000_能力变化小图/001.png"), Vector2(680, 180))
		_text("%3d" % int(c.get("mp", 0)), Vector2(700, 187), 16)
		_img(tex("ui/all_sys/0266_000_命灵体/001.png"), Vector2(535, 195))
		_text(":%d" % int(rec.get("hp", 0)), Vector2(542, 187), 16)
		_text("等级:", Vector2(610, 189), 12)
		_text("%d" % int(rec.get("level", 1)), Vector2(645, 187), 16)
	_text("攻击力:          防御力:", Vector2(520, 220), 12)
	_text("%4d             %4d" % [int(rec.get("atk", 0)), int(rec.get("def", 0))], Vector2(575, 220), 12)
	_text("仙  攻:          仙  防:", Vector2(520, 240), 12)
	_text("%4d             %4d" % [int(rec.get("matk", 0)), int(rec.get("mdef", 0))], Vector2(575, 240), 12)
	_text("速  度:", Vector2(520, 260), 12)
	_text("%4d" % int(rec.get("spd", 0)), Vector2(575, 260), 12)
	var sk: Array = rec.get("skills", [])
	for i in 3:
		_text("使用仙术%s:" % ["一", "二", "三"][i], Vector2(520, 285 + 24 * i), 12)
		var sid := int(sk[i]) if i < sk.size() else 0
		if sid > 0:
			_text(str(Battle.obj(sid).get("name", "")), Vector2(604, 283 + 24 * i), 16)


func list(title: String, pages: Array, tabs: int, page := 0) -> Variant:
	_drop_clicks()
	_list = {"title": title, "pages": pages, "tabs": tabs, "page": page, "sel": 0, "top": 0}
	if bt.auto_pick():
		await get_tree().create_timer(0.4).timeout
		_list = {}
		for pg in [page] + range(pages.size()):   # 自动: 当前页没有可用项就看其他页
			for e in pages[pg]:
				if e.ok:
					return e.id
		return null
	while true:
		await get_tree().process_frame
		if bt.auto_pick():   # 中途按了自动: 退回指令环, 由自动战斗重新选
			_list = {}
			return null
		var es: Array = _list.pages[_list.page]
		var m := _c.get_local_mouse_position() - LIST_POS
		var hover := -1
		if m.x >= 0 and m.x < 275 and m.y >= 37:
			hover = _list.top + int((m.y - 37) / 25)
			if hover >= es.size() or hover - _list.top >= LIST_ROWS:
				hover = -1
		if hover >= 0:
			_list.sel = hover
		var tab := -1
		if _list.tabs >= 0 and m.y >= 3 and m.y < 33 and m.x >= 25 and m.x < 25 + 32 * 3:
			tab = int((m.x - 25) / 32)
		var click := _clicked()
		if Input.is_action_just_pressed("ui_down"):
			_list.sel = mini(_list.sel + 1, es.size() - 1)
			Game.play_sound(Game.SFX_UI_SELECT)
		elif Input.is_action_just_pressed("ui_up"):
			_list.sel = maxi(_list.sel - 1, 0)
			Game.play_sound(Game.SFX_UI_SELECT)
		elif _list.tabs >= 0 and (Input.is_action_just_pressed("ui_right") or Input.is_action_just_pressed("ui_left") or (click and tab >= 0)):
			var d := 1 if Input.is_action_just_pressed("ui_right") else -1
			_list.page = tab if click and tab >= 0 else (int(_list.page) + d + pages.size()) % pages.size()
			_list.sel = 0
			_list.top = 0
			Game.play_sound(Game.SFX_UI_PAGE)
		elif (Input.is_action_just_pressed("ui_accept") or (click and hover >= 0)) and es.size():
			var e: Dictionary = es[_list.sel]
			if e.ok:
				_list = {}
				Game.play_sound(Game.SFX_UI_OK)
				return e.id
			Game.play_sound(Game.SFX_UI_ERROR)
		elif Input.is_action_just_pressed("ui_cancel") or _rclicked():
			_list = {}
			Game.play_sound(Game.SFX_UI_CANCEL)
			return null
		if _list.sel < _list.top:
			_list.top = _list.sel
		elif _list.sel >= _list.top + LIST_ROWS:
			_list.top = _list.sel - LIST_ROWS + 1
	return null


func _draw_list() -> void:
	var o := LIST_POS
	_img(tex(LIST % 0), o)
	var title := str(_list.title)
	if _list.tabs >= 0:
		title += ["(攻擊)", "(恢復)", "(輔助)"][int(_list.page)] if _list.tabs == 1 else ["(攻击)", "(恢复)", "(辅助)"][int(_list.page)]
	_text(title.replace("(攻擊)", "(攻击)").replace("(恢復)", "(恢复)").replace("(輔助)", "(辅助)"), o + Vector2(150, 10), 18)
	if _list.tabs >= 0:
		# 页签 9328: 技能 qq0–2 = 0029 第 1/0/2 帧, 物品 qq3–5 = 第 7/6/8 帧; 当前页抬高并放大
		var frames := [1, 0, 2] if _list.tabs == 0 else [7, 6, 8]
		for k in 3:
			var t := tex(TABS % frames[k])
			var p := o + Vector2(25 + 32 * k, 3)
			if k == int(_list.page):
				_c.draw_texture_rect(t, Rect2(p - Vector2(4, 5), Vector2(32, 32)), false)
			else:
				_img(t, p, Color(1, 1, 1, 0.75))
	var es: Array = _list.pages[_list.page]
	# 物品大图标 (0x45811c): 清单左侧 (x−180, y+80)
	if es.size() and int(_list.sel) < es.size() and str(es[_list.sel].get("icon", "")) != "":
		_img(tex(str(es[_list.sel].icon)), o + Vector2(-180, 80))
	for i in LIST_ROWS:
		var k: int = int(_list.top) + i
		if k >= es.size():
			break
		var e: Dictionary = es[k]
		var y := o.y + 45 + 25 * i
		if k == int(_list.sel):
			_c.draw_rect(Rect2(o.x, y - 8, 275, 28), Color(1, 1, 1, 100.0 / 255.0))
		var col := TEXT_COL if e.ok else GREY_COL
		_text(str(e.name), Vector2(o.x + 20, y - 3), 16, col)
		_text(str(e.right), Vector2(o.x + 235, y - 3), 16, col)
	if es.size() and int(_list.sel) < es.size():
		# 功能说明和描述合并显示 (原版战斗列表只有描述), 放不下时截掉描述的尾巴
		var y2 := o.y + 250
		for k2 in ["note", "desc"]:
			var desc := str(es[_list.sel].get(k2, ""))
			while desc != "" and y2 < o.y + 310:
				_text(desc.substr(0, 15), Vector2(o.x + 20, y2), 15, MainMenu.DARK_COL if k2 == "note" else TEXT_COL)
				desc = desc.substr(15)
				y2 += 18


# ---------------- 选目标 ----------------

## 游标 (0228 战斗游标图) 在目标头顶, 左上角显示目标信息; ←→ / 鼠标换目标, 确认 / 点击选定
func pick(pool: Array) -> Variant:
	_drop_clicks()
	var k := 0
	cursor_unit = pool[0]
	target = cursor_unit
	if bt.auto_pick():
		await get_tree().create_timer(0.3).timeout
		cursor_unit = null
		target = null
		return pool[0]
	while true:
		await get_tree().process_frame
		if bt.auto_pick():   # 中途按了自动: 退回指令环, 由自动战斗重新选 (点自动按钮那一下不当成确认目标)
			cursor_unit = null
			target = null
			return null
		# 状态 3 的鼠标 (0x44d708): 左键点哪里都确认当前目标 (0x44dd67); 否则滚轮换目标, 滚轮没动才看鼠标指到谁 (0x44f6c8: 清单里第一个命中的)
		var m := _c.get_local_mouse_position()
		var click := _clicked()
		var wheel := _pick_wheel
		_pick_wheel = 0
		if not click and wheel == 0 and m != _pick_mouse:
			for i in pool.size():
				if _unit_hit(pool[i], m):
					k = i
					break
		_pick_mouse = m
		if wheel != 0:
			k = (k + wheel + pool.size()) % pool.size()
		if Input.is_action_just_pressed("ui_right") or Input.is_action_just_pressed("ui_down"):
			k = (k + 1) % pool.size()
		elif Input.is_action_just_pressed("ui_left") or Input.is_action_just_pressed("ui_up"):
			k = (k - 1 + pool.size()) % pool.size()
		elif Input.is_action_just_pressed("ui_accept") or click:
			cursor_unit = null
			target = null
			return pool[k]
		elif Input.is_action_just_pressed("ui_cancel") or _rclicked():
			cursor_unit = null
			target = null
			return null
		cursor_unit = pool[k]
		target = cursor_unit
	return null


## 鼠标指到单位 (0x4364e1 → 0x41047c): 当前动作包围盒 8 个角投影到屏幕的外接矩形, 矩形中心在画面内
func _unit_hit(u: BattleUnit, m: Vector2) -> bool:
	if u.actor == null:
		return false
	var bb: Array = u.actor.xb()
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for c in 8:
		var w: Vector3 = u.actor.global_transform * (Vector3(bb[3] if c & 1 else bb[0], bb[4] if c & 2 else bb[1], bb[5] if c & 4 else bb[2]) * 0.01)
		if bt.cam3d().is_position_behind(w):
			return false
		var sp: Vector2 = bt.screen_pos(w)
		lo = lo.min(sp)
		hi = hi.max(sp)
	var ctr := (lo + hi) * 0.5
	return ctr.x > 0 and ctr.x < 800 and ctr.y > 0 and ctr.y < 600 and m.x >= lo.x and m.x <= hi.x and m.y >= lo.y and m.y <= hi.y


## 右下按钮: 自动攻击 / 逃跑 (0x451210)
func _input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed:
		_lclick = _lclick or e.button_index == MOUSE_BUTTON_LEFT
		_rclick = _rclick or e.button_index == MOUSE_BUTTON_RIGHT
	if e is InputEventMouseButton and e.pressed and e.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		_pick_wheel = 1 if e.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		var m := _c.get_local_mouse_position()
		if not bt.hud_panel:
			return   # 面板隐藏时按钮的点击处理 (在 0x45104f 里) 也不跑
		if Rect2(723, 570, 20, 20).has_point(m):
			auto = not auto
			get_viewport().set_input_as_handled()
		elif Rect2(746, 570, 20, 20).has_point(m) and not bt.no_escape and escape_shown():
			want_escape = true
			get_viewport().set_input_as_handled()
	elif e is InputEventKey and e.pressed and not e.echo:
		if e.keycode in [KEY_A, Pad.Y]:
			auto = not auto
		elif e.keycode in [KEY_Q, Pad.X] and not bt.no_escape and not _ring.is_empty():   # 逃跑键只在指令环状态 1 / 2 (0x44d0c3)
			want_escape = true


# ---------------- 飘字 ----------------

## kind: "hp" 伤害 (红) / "heal" 生命回复 (浅蓝) / "mp" 灵力 (绿) / "sp" 体力 (蓝) / "money" 金钱 (金, 偷钱 0x245d) / "miss" 失误 / "invalid" 无效
func pop(u: BattleUnit, kind: String, n := 0) -> void:
	if u and u.party:
		bt.hud_panel = true   # 0x433348 / 0x433540 / 0x437320: 我方受击、回复、数值结算时状态栏恢复
	var same := _pops.filter(func(p): return p.unit == u and p.t < 0.3).size()
	_pops.append({"unit": u, "kind": kind, "n": n, "t": 0.0, "off": same * 26})


func _draw_pop(p: Dictionary) -> void:
	var u: BattleUnit = p.unit
	if u.actor == null:
		return
	var base: Vector2 = bt.screen_pos(u.actor.global_position + Vector3(0, 1.5, 0))
	var t: float = p.t
	var y := base.y - 30.0 * minf(t / 0.3, 1.0) - float(p.off)
	var a := 1.0 if t < 0.8 else maxf(0.0, 1.0 - (t - 0.8) / 0.4)
	var mod := Color(1, 1, 1, a)
	if p.kind in ["miss", "invalid"]:
		var mt := tex(MISS)
		if mt:
			_c.draw_texture_rect_region(mt, Rect2(Vector2(base.x - 32, y - 16), Vector2(64, 32)),
				Rect2(0, 0 if p.kind == "miss" else 32, 64, 32), mod)
		return
	if p.kind == "doom":
		# 宣告死亡倒数 0x2461 = ACT 9313: 图集格 32×64, 一行 8 格; 数字 → 格号 0→18 1→0 2→2 3→4 4→6 5→16 6→8 7→10 8→12 9→14;
		# 每位右移 25.6 像素, 前导零不画
		var f := UiAct.frame(9313, 0, 0)
		if f.is_empty() or f.tex == null:
			return
		var cells := [18, 0, 2, 4, 6, 16, 8, 10, 12, 14]
		var ds := str(absi(int(p.n)))
		var x0 := base.x - ds.length() * 12.8
		for i in ds.length():
			var c: int = cells[int(ds[i])]
			_c.draw_texture_rect_region(f.tex, Rect2(Vector2(x0 + i * 25.6, y - 32), Vector2(32, 64)),
				Rect2((c % 8) * 32, (c / 8) * 64, 32, 64), mod)
		return
	# 飘字类型 0x2459.. = ACT 9305..9310, 各自的 AP 指向数字图第几张 (all_sys.act): 9305→0 9306→1 9307→2 9308→3 9309→5 (金钱, 0x245d) 9310→4
	var sheet := tex(DIGITS % {"hp": 0, "heal": 1, "mp": 2, "sp": 3, "money": 5}.get(p.kind, 0))
	if sheet == null:
		return
	var s := str(absi(int(p.n)))
	var x := base.x - s.length() * 9.0
	# 单个数字依次弹起
	for i in s.length():
		var d := int(s[i])
		var cell := (d + 9) % 10
		var bounce := maxf(0.0, 8.0 * sin(clampf((t - i * 0.04) / 0.2, 0.0, 1.0) * PI))
		_c.draw_texture_rect_region(sheet, Rect2(Vector2(x + i * 18.0, y - 12 - bounce), Vector2(24, 24)),
			Rect2((cell % 5) * 24, (cell / 5) * 24, 24, 24), mod)


# ---------------- 战斗结果 (原版状态机 0x455a54, 每战斗拍执行; 逆向见 development.md 2026-11-12) ----------------
## 0x64 设飞入 (0x455bfd) → 0x65 战斗结果卡片 (0x455dc1): 第一次确认开始滚经验 (每拍加 剩余/4, 剩余 < 4 一次加完,
##   每 2 拍音效 0x208), 滚完后第二次确认翻页 → 0x66 / 0x67 升级页 (0x456724, 每升一级一页, 音效 0x2a4;
##   学到法术 / 木甲技术点时第一次确认弹小框 0x457067, 音效 0x2a5) → 0x6e 获得物品页 (0x4571c6): 第一次确认资源一次加入、
##   金钱滚动 (每 2 拍 0x2ac), 第二次确认全屏黑淡出 (0x478c4b, 每拍 +20) → 结束
## 面板飞入 (0x494fe4 模式 3): 剩余距离 d ≥ 速度 时每拍走 d/速度, 否则每拍 1 像素, d ≤ 1 吸附
## 框 = 九宫格 ACT 9008 不填底 (0x465ea4 模式 0) + 背后 ACT 9301 黑图 (alpha 0x64, 缩放 = 自带 (12.5, 9.375) + 增量) 画在 (x, y+5)
## 字: 按原版格子排, 每个半角 11 像素、全角 22 像素; 标签 调色板 22, 数值 24, 标题 7
const SKIN := "ui/all_sys/0139_000_九公格框1/000.png"
const SKIN2 := "ui/all_sys/0251_000_九宫格框2/000.png"   # ACT 9009 (学到招式小框, 填底)
const GOLD_COL := Color8(237, 192, 95)     # 调色板 24
const RES_TITLE := Color8(204, 196, 178)   # 调色板 7
const RES_TICK := 1.0 / 27.0               # 战斗逻辑拍
const RES_FONT := 20
const RES_DARK := Color(0.0, 0.0, 0.0)     # 0x40cd8a 字体 flag 4: (+1,+1) 黑影

var _result: Dictionary = {}


class ResPanel:
	var pos := Vector2.ZERO
	var to := Vector2.ZERO
	var speed := 6.0
	var done := false

	func _init(a: Vector2, b: Vector2, sp: float) -> void:
		pos = a
		to = b
		speed = sp

	func tick() -> void:
		if done:
			return
		var d := to - pos
		var dist := d.length()
		if dist <= 1.0:
			pos = to
			done = true
		elif dist >= speed:
			pos += d / speed
		else:
			pos += d / dist


## data: {cards: [{member, name, lv, exp, gain, art, art_up: [[装备格, 法宝名]]}], levelups: [{member, name, lv, old, new, learned, tech}],
##        money, res: [金属, 木材, 煤炭], items: [{id, name, n, sub}]}
func results(data: Dictionary) -> void:
	var cards: Array = data.get("cards", [])
	var n := clampi(cards.size(), 1, 3)
	var b := Vector2(176, 65)
	# 0x455bfd: 各人数的起止点 (3 人时卡片 0 起点 y 固定 125)
	var title_to: Vector2 = [b + Vector2(0, 130), b + Vector2(0, 60), b][n - 1]
	var title_from: Vector2 = [Vector2(70, 50), Vector2(70, -30), Vector2(70, -100)][n - 1]
	var cy: Array = [[190], [120, 260], [60, 200, 340]][n - 1]
	var panels: Array = []
	for i in cards.size():
		var to := b + Vector2(0, float(cy[mini(i, 2)]))
		var from := Vector2(-800.0 if i % 2 == 0 else 800.0, 125.0 if n == 3 and i == 0 else to.y)
		panels.append(ResPanel.new(from, to, 6.0))
	var rem: Array = cards.map(func(c): return int(c.gain))
	var cur_exp: Array = cards.map(func(c): return int(c.exp))
	_result = {"page": "cards", "cards": cards, "panels": panels, "title": ResPanel.new(title_from, title_to, 4.0),
		"rem": rem, "exp": cur_exp}
	var fly := func():
		for p in panels:
			p.tick()
		_result.title.tick()
	var roll_exp := func(ticks: int) -> bool:   # 滚经验 (0x456128); 返回 true = 还在滚; 99 级不加
		var busy := false
		for i in rem.size():
			var r: int = rem[i]
			if r <= 0 or int(cards[i].lv) >= 99:
				rem[i] = 0
				continue
			var add := r if r < 4 else r / 4
			rem[i] = r - add
			cur_exp[i] = int(cur_exp[i]) + add
			busy = true
		if busy and ticks % 2 == 0:
			Game.play_sound(0x208)
		return busy
	# 第一次确认 (0x44e16a → 0x45abb8): 每人两格法宝里这场升了级的各弹一个单行提示框「法宝【%s】升级」
	# 0x466f7d(400, 卡片 y + 40 + 格·60, …, 时长 100000) + 音效 0x2a5, 翻页时 0x4653e4 一起清掉。
	# 同一函数后半: 天书仙术道场修练完成「%s学到法术【%s】」(battle._victory 算好传进来)
	var art_tips := func():
		var tips: Array = []
		for i in cards.size():
			for a in cards[i].get("art_up", []):
				tips.append(["法宝【%s】升级" % str(a[1]), Vector2(400, b.y + float(cy[mini(i, 2)]) + 40.0 + 60.0 * int(a[0]))])
				Game.play_sound(0x2a5)
		if str(data.get("dojo_tip", "")) != "":   # 仙术道场修练完成 (同一函数后半, 0x45ae38)
			tips.append([str(data.dojo_tip), Vector2(400, 450)])
			Game.play_sound(0x2a5)
		_result.tips = tips
	await _res_page(fly, roll_exp, rem.any(func(x): return int(x) > 0), Callable(), art_tips)
	# 升级页
	for lu in data.get("levelups", []):
		Game.play_sound(0x2a4)
		# 小框文字 (0x456f5b / 0x457067): 缓冲 0x9f144c 先写「获得木甲技术 %d 点」(车芸、旗标 7), 学到法术时被法术名覆盖;
		# 车芸 (档案 0) 用「%s %s」(名字 + 缓冲), 其他人用「%s学到【%s】」。所以车芸学到法术时显示「车芸 法术名」, 没有「学到」
		var learn := ""
		var buf := ""
		if int(lu.get("tech", 0)) > 0:
			buf = "获得木甲技术 %d 点" % int(lu.tech)
		if (lu.learned as Array).size():
			buf = str(lu.learned[-1])
		if buf != "":
			learn = ("%s %s" if int(lu.member) == 1 else "%s学到【%s】") % [lu.name, buf]
		_result = {"page": "levelup", "lu": lu, "box": ResPanel.new(Vector2(-400, 50), Vector2(176, 110), 4.0),
			"face": ResPanel.new(Vector2(800, 105), Vector2(176, 110), 4.0), "learn": ""}
		var fly2 := func():
			_result.box.tick()
			_result.face.tick()
		await _res_page(fly2, Callable(), false, func(): return bool(_result.box.done))
		if learn != "":
			Game.play_sound(0x2a5)
			_result.learn = learn
			await _res_page(Callable(), Callable(), false)
	# 获得物品页 (固定位置, 不飞入)
	var money_rem := int(data.get("money", 0))
	var res: Array = data.get("res", [0, 0, 0])
	_result = {"page": "items", "items": data.get("items", []), "money_rem": money_rem, "res_rem": res.duplicate(),
		"money0": State.money - money_rem, "res0": [State.metal - int(res[0]), State.wood - int(res[1]), State.coal - int(res[2])]}
	var roll_money := func(ticks: int) -> bool:   # 第一次确认: 资源一次加入, 金钱每拍加 剩余/4
		_result.res_rem = [0, 0, 0]
		_result.res0 = [State.metal, State.wood, State.coal]
		var r: int = _result.money_rem
		if r == 0:
			return false
		var add := r if absi(r) < 4 else r / 4
		_result.money_rem = r - add
		_result.money0 = int(_result.money0) + add
		if ticks % 2 == 0:
			Game.play_sound(0x2ac)
		return true
	await _res_page(Callable(), roll_money, money_rem != 0 or res.any(func(x): return int(x) != 0))
	# 0x6e 第二次确认: 黑淡出 (0x478c4b(0,255,0,0,0,20)) → 0x12c 等淡出完 → 收尾
	_result.fade = 0.0
	while float(_result.fade) < 1.0:
		await get_tree().create_timer(RES_TICK).timeout
		_result.fade = minf(float(_result.fade) + 20.0 / 255.0, 1.0)
	_result = {}


## 一页: 每拍执行 anim; 确认 (或自动) 后若有 roll 就开始逐拍滚动, 滚完再等一次确认翻页; ready 返回 false 时确认无效 (面板还在飞)
func _res_page(anim: Callable, roll: Callable, has_roll: bool, ready := Callable(), first := Callable()) -> void:
	_clicked()
	var acc := 0.0
	var rolling := false
	var ticks := 0
	var idle := 0.0
	while true:
		await get_tree().process_frame
		var dt := get_process_delta_time()
		acc += dt
		idle += dt
		while acc >= RES_TICK:
			acc -= RES_TICK
			ticks += 1
			if anim.is_valid():
				anim.call()
			if rolling:
				rolling = roll.call(ticks)
				if not rolling:
					idle = 0.0
		var ok := not ready.is_valid() or bool(ready.call())
		if ok and not rolling and idle > 1.0 and idle - dt <= 1.0:
			await _res_snap()
		var press: bool = Input.is_action_just_pressed("ui_accept") or _clicked() or (bt.auto_pick() and idle > 1.2)
		if not ok or not press or rolling:
			continue
		Game.play_sound(Game.SFX_UI_OK)
		if first.is_valid():
			first.call()
			first = Callable()
		if has_roll:
			has_roll = false
			rolling = true
			idle = 0.0
			continue
		return


var _snap_n := 0


## 调试: --shot-results=前缀 每一页静止下来时 (以及滚完后) 存一张截图
func _res_snap() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot-results="):
			await RenderingServer.frame_post_draw
			_snap_n += 1
			get_viewport().get_texture().get_image().save_png("%s_%02d.png" % [a.substr(15), _snap_n])


## 按原版格子排字: 半角 11、全角 22 像素
func _gtext(s: String, pos: Vector2, col: Color) -> void:
	var x := pos.x
	for ch in s:
		var half := ch.unicode_at(0) < 0x80
		if ch != " ":
			_text(ch, Vector2(x, pos.y - 2), RES_FONT, col, false, RES_DARK)
		x += 11.0 if half else 22.0


static func _gbytes(s: String) -> int:
	var k := 0
	for ch in s:
		k += 1 if ch.unicode_at(0) < 0x80 else 2
	return k


## 框: 背后半透明黑 (ACT 9301, 64×64 × (12.5 + dx, 9.375 + dy), alpha 0x64, 在 (x, y+5)) + 九宫格 9008 不填底
func _res_box(pos: Vector2, size: Vector2, dx: float, dy: float) -> void:
	_c.draw_rect(Rect2(pos + Vector2(0, 5), Vector2(64.0 * (12.5 + dx), 64.0 * (9.375 + dy))), Color(0, 0, 0, 0x64 / 255.0))
	Dialog.draw_nine(_c, tex(SKIN), Rect2(pos, size), false, false)


func _act_img(act: int, qq: int, pos: Vector2) -> void:
	var f := _act_frame(act, qq, 0, true)
	if f.size():
		_img(tex(str(f[0])), pos + Vector2(float(f[2]), float(f[3])))


func _draw_result() -> void:
	match str(_result.get("page", "")):
		"cards":
			_draw_cards()
		"levelup":
			_draw_levelup()
		"items":
			_draw_items()
	if _result.has("fade"):
		_c.draw_rect(Rect2(0, 0, 800, 600), Color(0, 0, 0, float(_result.fade)))


## 战斗结果卡片 (0x455dc1 后半)。原版另有两处不画: 倒下的队员 (档案 +0x48 & 2) 叠 ACT 9012 动作 10 / 11 / 39,
## 但 9012 只有 7 个动作, 播放器越界返回空 (0x41d111), 实际什么都不画; 0x45ae73 按句柄表 [0x9efc80] 移动一个粒子,
## 整个程序没有地方写这张表 (句柄恒为 0), 是没用上的残留。字体对象 0xa79288 在 0x476b37 设成 20 号, 结算四页都用它
func _draw_cards() -> void:
	var tp: Vector2 = _result.title.pos
	_res_box(tp, Vector2(448, 60), -5.45, -8.59)
	_gtext("战斗结果", tp + Vector2(180, 22), SHADOW_COL)
	for i in _result.cards.size():
		var cd: Dictionary = _result.cards[i]
		var o: Vector2 = _result.panels[i].pos
		_res_box(o, Vector2(448, 140), -5.45, -7.3)
		match int(cd.member):
			2:
				_img(main(11), o + Vector2(20, 5))
			3:
				_img(main(39), o + Vector2(20, 5))
			_:
				_img(main(10), o + Vector2(10, 7))
		var x := o.x + 180
		var lv := int(cd.lv)
		var e := int(_result.exp[i])
		var rows := [["等级:", "     %2d" % lv], ["获得经验值:", "             %6d" % int(_result.rem[i])],
			["下一级经验值:", "             %6d" % maxi(State.exp_threshold(lv) - e, 0)],
			["每个法宝经验值:", "             %6d" % int(cd.art)]]
		for k in rows.size():
			_gtext(rows[k][0], Vector2(x, o.y + 20 + 28 * k), SHADOW_COL)
			_gtext(rows[k][1], Vector2(x, o.y + 20 + 28 * k), GOLD_COL)
	for t in _result.get("tips", []):   # 法宝升级提示框 (0x466f7d, 画在最上层)
		Dialog.draw_tip_layout(_c, Dialog.tip_layout(str(t[0]), t[1]))


const LEVELUP_ROWS := [["生命:  ", "hp_max"], ["灵力:  ", "mp_max"], ["体力:  ", "sp_max"], ["攻击力:", "atk"], ["防御力:", "def"],
	["速度:  ", "spd"], ["仙攻:  ", "matk"], ["仙防:  ", "mdef"]]


## 升级页 (0x456724(350,195)): 框 0x9efb70 (176,110) 448×330, 头像跟着锚点 0x9efbb4; 框到位后才画字。
## 标题「%s升第%d級」(380,145) 调色板 7; 每行 x=350 y=195+28k「名称: 旧值」, 新值大于旧值时在同一 x 补 15 个空格画新值 (数值色) +
## 箭头 ACT 9068 qq0 在 (480, y−5)。学到 / 木甲点小框 (0x457067(390,450)): ACT 9009 填底, x = 390 − 6·字节数, 宽 = 字节数/2·26, 高 64, 字 (x+16, 472)
func _draw_levelup() -> void:
	var lu: Dictionary = _result.lu
	var bp: Vector2 = _result.box.pos
	_res_box(bp, Vector2(448, 330), -5.45, -4.3)
	var fp: Vector2 = _result.face.pos
	match int(lu.member):
		2:
			_img(main(11), fp + Vector2(20, 45))
		3:
			_img(main(9), fp + Vector2(20, 10))
		_:
			_img(main(10), fp + Vector2(10, 50))
	if not _result.box.done:
		return
	_gtext("%s升第%d级" % [lu.name, int(lu.lv)], Vector2(380, 145), RES_TITLE)
	for k in LEVELUP_ROWS.size():
		var r: Array = LEVELUP_ROWS[k]
		var y := 195.0 + 28.0 * k
		var a := int(lu.old.get(r[1], 0))
		var b2 := int(lu.new.get(r[1], 0))
		_gtext("%s%4d" % [r[0], a], Vector2(350, y), SHADOW_COL)
		if b2 > a:
			_gtext("               %4d" % b2, Vector2(350, y), GOLD_COL)
			_act_img(9068, 0, Vector2(480, y - 5))
	var learn := str(_result.get("learn", ""))
	if learn != "":
		var nb := _gbytes(learn)
		var x := 390.0 - 6.0 * nb
		Dialog.draw_nine(_c, tex(SKIN2), Rect2(x, 450, (nb / 2) * 26.0, 64), true)
		_gtext(learn, Vector2(x + 16, 472), RES_TITLE)


## 获得物品页 (0x4571c6(176,90)): 上框 (176,90) 448×100 放资源, 下框 (176,190) 448×320 放物品
func _draw_items() -> void:
	_res_box(Vector2(176, 90), Vector2(448, 100), -5.45, -7.9)
	_res_box(Vector2(176, 190), Vector2(448, 320), -5.45, -4.4)
	var rr: Array = _result.res_rem
	var r0: Array = _result.res0
	_res_num(9011, 28, Vector2(226, 120), Vector2(256, 115), int(r0[0]) + 0, int(rr[0]))
	_res_num(9011, 29, Vector2(356, 120), Vector2(386, 115), int(r0[1]), int(rr[1]))
	_res_num(9011, 30, Vector2(486, 120), Vector2(516, 115), int(r0[2]), int(rr[2]))
	if State.test_flag(7):   # 0x4676f5(7): 木甲已开放, 金钱和木甲点一行
		_res_num(9011, 27, Vector2(246, 160), Vector2(276, 155), int(_result.money0), int(_result.money_rem))
		_res_num(9011, 31, Vector2(426, 160), Vector2(456, 155), State.tech, 0)
	else:
		_res_num(9011, 27, Vector2(226, 160), Vector2(256, 155), int(_result.money0), int(_result.money_rem))
	_gtext("获得物品", Vector2(356, 210), SHADOW_COL)
	_gtext("--------------------------", Vector2(256, 228), SHADOW_COL)
	var items: Array = _result.items
	for i in items.size():
		var it: Dictionary = items[i]
		var y := 245.0 + 25.0 * i
		var sb := int(it.sub)
		var q: int = [0, 1, 2, 3, 4, 6, 7, 5][sb - 201] if sb >= 201 and sb <= 208 else 8
		_act_img(9330, q, Vector2(261, y))
		var nm := str(it.name)
		nm += " ".repeat(maxi(16 - _gbytes(nm), 0))
		_gtext("%s X %2d" % [nm, int(it.n)], Vector2(301, y + 5), GOLD_COL)


## 资源数: 有待加量时「%d+」(当前, 标签色) 再在 x + 11·长度 画待加量 (数值色); 没有就只画当前
func _res_num(act: int, qq: int, ip: Vector2, tp: Vector2, cur: int, add: int) -> void:
	_act_img(act, qq, ip)
	if add != 0:
		var s := "%d+" % cur
		_gtext(s, tp, SHADOW_COL)
		_gtext("%d" % add, tp + Vector2(11.0 * s.length(), 0), GOLD_COL)
	else:
		_gtext("%d" % cur, tp, SHADOW_COL)


# ---------------- 常转法轮 (法宝 5215 转轮; 状态 0x19 → 0x453240) ----------------
## 转盘 0002 第 0 帧 (250×233) 从 (−300,180) 滑到 (200,180), 指针第 1 帧在 +(0x71,0x20), 转动的轮 9323 qq10 (0006, 256²) 中心 +(0x7b,0x80);
## 结果栏第 2 帧 (117×181) 从 (970,220) 滑到 (470,220), 七项文字 (+0x16, +0x11+22k), 选中项底色条第 3+k 帧 (+10, +0xe+22k)
## 逐帧 (战斗 27 帧/秒, 逆向 0x43aa49 / 0x453240 / 输入 0x450d67):
##   初始化: 角度 = rand(360); 两块面板缓动 (每帧走剩余量的 1/3, 剩余 < 3 时每帧 1, ≤ 1 吸附), 16 帧到位, 期间转盘不动
##   子状态 1: 每帧 +20°, 没有计时, 等确认键 (左键 / Enter / 空格 / 小键盘 Enter)
##   子状态 2: 每帧先更新速度 (20 → 19 → … → 3, 每帧 −1), 到 3 之后下一帧进入子状态 6; 每帧角度 += 速度
##     (实际增量 19, 18, …, 3, 3 共 18 帧, 多转 190°)
##   子状态 6: 倒数 30 帧, 选中项闪烁 (计数 % 10 < 5 用调色板 14, 否则 16), 到 0 施加效果
##   结果每帧按整数角度判定 (扇区见 WHEEL_SECTORS, 含端点)
const WHEEL_TEXT := ["对方石化", "敌方全灭", "我方全补", "自己石化", "平安即福", "自己衰竭", "对方衰竭"]
const WHEEL_SECTORS := [[0, 121, 143], [1, 37, 45], [2, 218, 232], [3, 46, 68], [3, 144, 165], [3, 233, 254], [3, 330, 351],
	[5, 15, 36], [5, 99, 120], [5, 197, 217], [5, 285, 306], [6, 307, 329]]
const WHEEL_BLINK := [Color8(89, 63, 32), Color8(229, 69, 16)]   # 运行时调色板 [0xa84c7c] / [0xa84c80] = 第 14 / 16 项
var _wheel: Dictionary = {}


static func wheel_result(ang: float) -> int:
	var a := int(ang)
	for s2 in WHEEL_SECTORS:
		if a >= int(s2[1]) and a <= int(s2[2]):
			return int(s2[0])
	return 4


static func _ease(x: float, to: float) -> float:
	var rem := to - x
	if absf(rem) <= 1.0:
		return to
	if absf(rem) < 3.0:
		return x + signf(rem)
	return x + rem / 3.0


func wheel() -> int:
	_wheel = {"ang": float(randi() % 360), "speed": 20, "sub": 0, "p1": -300.0, "p2": 970.0, "cnt": 0, "res": -1}
	_mg_was = true
	var acc := 0.0
	while true:
		await get_tree().process_frame
		var press := mg_pressed(0.05)
		acc += get_process_delta_time()
		while acc >= Battle.TICK:
			acc -= Battle.TICK
			_wheel.res = wheel_result(float(_wheel.ang))
			match int(_wheel.sub):
				0:
					_wheel.p1 = _ease(float(_wheel.p1), 200.0)
					_wheel.p2 = _ease(float(_wheel.p2), 470.0)
					if float(_wheel.p1) == 200.0 and float(_wheel.p2) == 470.0:
						_wheel.sub = 1
				1:
					_wheel.ang = fmod(float(_wheel.ang) + 20.0, 360.0)
					if press:
						press = false
						_wheel.sub = 2
				2:
					if int(_wheel.speed) > 3:
						_wheel.speed = int(_wheel.speed) - 1
					else:
						_wheel.sub = 6
						_wheel.cnt = 30
					_wheel.ang = fmod(float(_wheel.ang) + float(_wheel.speed), 360.0)
				6:
					_wheel.cnt = int(_wheel.cnt) - 1
					if int(_wheel.cnt) <= 0:
						var r: int = wheel_result(float(_wheel.ang))
						_wheel = {}
						return r
	return 4


# ---------------- 法宝小游戏 (0x45205a 逐帧 / 0x450628 输入; 战斗 27 帧/秒) ----------------

var _mg: Dictionary = {}
var _mg_was := false

const DARK := "ui/all_sys/0036_9317_黑色渐层/000.png"
const LF := "ui/all_sys/0039_9315_龙颿介面/%03d.png"
const SC_RULER := "ui/all_sys/0037_9316_九天算尺介面/%03d.png"
const SC_MARK := "ui/all_sys/0038_9316_九天算尺范围/%03d.png"
const DIGIT_BIG := "ui/all_sys/0010_9305_战斗数字系列/006.png"


## 光标 (战斗每帧 0x4426e7): 战斗状态 [0x92522c] = 0 (行动条走动 / 招式演出, 没有要选的东西) → ACT 9109 qq0 沙漏;
## 其他状态 (指令环、选目标、清单、结算…) → qq1 剑; 龙颿 (状态 0x15) 由小游戏自己设 (0x450ed6): 转动中且鼠标在拉杆 (490–530, 223–300) → 手, 否则沙漏
const LEVER := Rect2(490, 223, 40, 77)


func _cursor() -> void:
	var c := Game.cursor
	if c == null:
		return
	c.fps = GameCursor.FPS_BATTLE
	if str(_mg.get("kind", "")) == "longfan":
		var on := int(_mg.st) == 31 and int(_mg.stop) < int(_mg.n) and LEVER.has_point(_c.get_local_mouse_position())
		if on:
			c.set_state(9001, 8)
		else:
			c.set_state(9109, 0)
		return
	if not bt.puzzle.is_empty():   # 0x4426f3: 状态 0x1f 用剑形光标
		c.set_state(9109, 1)
		return
	var idle := _ring.is_empty() and _list.is_empty() and cursor_unit == null and _wheel.is_empty() and _mg.is_empty() \
		and _result.is_empty()
	c.set_state(9109, 0 if idle else 1)


## 确认键「刚按下」(左键 / Enter / 空格 / 手柄确认); 自动战斗时按 auto_rate 随机按
## mouse_rect: 只有鼠标在这块里时左键才算 (龙颿只认拉杆, 0x450f48)
func mg_pressed(auto_rate := 0.06, mouse_rect := Rect2()) -> bool:
	var key := Input.is_action_pressed("ui_accept")
	var click := _clicked() and (mouse_rect.size == Vector2.ZERO or mouse_rect.has_point(_c.get_local_mouse_position()))
	var hit := click or (key and not _mg_was)
	_mg_was = key
	if bt.auto_pick():
		return randf() < auto_rate
	return hit


func _mg_frames() -> int:
	# 逻辑帧计数 (战斗 27 帧/秒 定步长; 以前按 35, 小游戏快了 30%)
	_mg.acc = float(_mg.get("acc", 0.0)) + get_process_delta_time()
	var n := int(float(_mg.acc) / Battle.TICK)
	_mg.acc = float(_mg.acc) - n * Battle.TICK
	return n


## 龙颿 (0x45275c): 拉霸, 每按一下从个位起定住一位; 返回伤害
func longfan(digits: int, maxd: int) -> int:
	_mg = {"kind": "longfan", "st": 0, "d": [], "stop": 0, "n": digits, "max": maxd}
	for i in digits:
		_mg.d.append(randi() % (maxd + 1))
	_mg_was = true
	while true:
		await get_tree().process_frame
		var press := mg_pressed(0.03, LEVER)
		for f in _mg_frames():
			var st := int(_mg.st)
			if st >= 16 and st <= 31:   # 拉下后 / 等按键: 没停的位每帧 +1
				for i in range(int(_mg.stop), int(_mg.n)):
					_mg.d[i] = (int(_mg.d[i]) + 1) % (int(_mg.max) + 1)
			if st == 31:
				if int(_mg.stop) >= int(_mg.n):
					_mg.st = 32
				continue
			_mg.st = st + 1
			if int(_mg.st) >= 47:
				break
		if int(_mg.st) == 31 and press and int(_mg.stop) < int(_mg.n):
			_mg.stop = int(_mg.stop) + 1
			_mg.st = 16
		if int(_mg.st) >= 47:
			break
	var dmg := 0
	for i in int(_mg.n):
		dmg += int(_mg.d[i]) * int(pow(10, i))
	_mg = {}
	return dmg


## 九天算尺 (0x452a20): 游标 0..256 来回, 按键停下, 落在 [c, c+4·p0−4] 内成功
func suanchi(p0: int) -> bool:
	var r := randi() % 200
	var c := r + 4 - r % 4
	r = randi() % 150 + 30
	_mg = {"kind": "suanchi", "st": 0, "s": r + 4 - r % 4, "c": c, "w": 4 * p0, "ok": false}
	_mg_was = true
	while true:
		await get_tree().process_frame
		var press := mg_pressed(0.02)
		if press and int(_mg.st) < 2:
			var sv := int(_mg.s)
			_mg.ok = sv >= c and sv <= c + int(_mg.w) - 4
			_mg.st = 50 if _mg.ok else 10
		for f in _mg_frames():
			match int(_mg.st):
				0:
					_mg.s = int(_mg.s) + 4
					if int(_mg.s) >= 256:
						_mg.st = 1
				1:
					_mg.s = int(_mg.s) - 4
					if int(_mg.s) <= 0:
						_mg.st = 0
				_:
					_mg.st = int(_mg.st) + 1
		if (not _mg.ok and int(_mg.st) >= 26 and int(_mg.st) < 50) or int(_mg.st) >= 66:
			break
	var ok: bool = _mg.ok
	_mg = {}
	return ok


## 鼠槌倒数 (0x45264c): 141 帧 (6 → 1, 每个数字 28 帧), 每按一下调用 on_hit
func shuchui(on_hit: Callable) -> void:
	_mg = {"kind": "shuchui", "t": 140}
	_mg_was = true
	while int(_mg.t) >= 0:
		await get_tree().process_frame
		if mg_pressed(0.25):
			on_hit.call()
		_mg.t = int(_mg.t) - _mg_frames()
	_mg = {}


func _draw_mg() -> void:
	match str(_mg.kind):
		"longfan":
			var st := int(_mg.st)
			if st >= 16 and st <= 30:
				_img(tex(LF % 2), Vector2(490, 265))
			else:
				_img(tex(LF % 1), Vector2(490, 220))
			_img(tex(LF % 0), Vector2(270, 220))
			for i in int(_mg.n):
				_img(tex(LF % (int(_mg.d[i]) + 3)), Vector2(433 - 30 * i, 262))
		"suanchi":
			_img(tex(SC_RULER % 0), Vector2(270, 280))
			_c.draw_rect(Rect2(int(_mg.c) + 275, 283, maxf(int(_mg.w) - 2, 2), 29), Color8(0, 120, 100, 170))
			_img(tex(SC_RULER % 1), Vector2(int(_mg.s) + 268, 262))
			var st2 := int(_mg.st)
			if st2 >= 10 and st2 % 4 >= 2:
				var mt := tex(SC_MARK % 1)
				if mt:
					_c.draw_texture_rect(mt, Rect2(int(_mg.s) + 275, 283, 29, 29), false, Color8(255, 200, 100))
		"shuchui":
			# 倒数数字: 0010 图集 32×64 格 (qqN → 格号), 放大 1.5 倍画在 (550,100)
			var cells := {1: 0, 2: 2, 3: 4, 4: 6, 5: 16, 6: 8}
			var n := clampi(int(_mg.t) / 28 + 1, 1, 6)
			var dt := tex(DIGIT_BIG)
			if dt:
				var k := dt.get_width() / 256.0
				var cell: int = cells[n]
				_c.draw_texture_rect_region(dt, Rect2(550, 100, 48, 96), Rect2((cell % 8) * 32 * k, (cell / 8) * 64 * k, 32 * k, 64 * k))


func _draw_wheel() -> void:
	var o := Vector2(float(_wheel.p1), 180)
	_img(tex("ui/all_sys/0002_9323_常转法轮介面/000.png"), o)
	var disc := tex("ui/all_sys/0006_9323_常转法轮转盘/000.png")
	if disc:
		var c := o + Vector2(0x7b, 0x80)
		_c.draw_set_transform(c, deg_to_rad(float(_wheel.ang)), Vector2.ONE)
		_c.draw_texture(disc, -disc.get_size() / 2.0)
		_c.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	_img(tex("ui/all_sys/0002_9323_常转法轮介面/001.png"), o + Vector2(0x71, 0x20))
	var l := Vector2(float(_wheel.p2), 220)
	_img(tex("ui/all_sys/0002_9323_常转法轮介面/002.png"), l)
	var cur := int(_wheel.res) if int(_wheel.res) >= 0 else wheel_result(float(_wheel.ang))
	for i in 7:
		if i == cur:
			_img(tex("ui/all_sys/0002_9323_常转法轮介面/%03d.png" % (3 + i)), l + Vector2(10, 0xe + 22 * i))
		var col := TEXT_COL
		if i == cur and int(_wheel.sub) == 6:
			col = WHEEL_BLINK[0] if int(_wheel.cnt) % 10 < 5 else WHEEL_BLINK[1]
		_text(WHEEL_TEXT[i], l + Vector2(0x16, 0x11 + 22 * i - 3), 16, col)


## 面板滑入 (0x43fbb4: 从右 / 下 / 左三种之一)
func slide_in() -> void:
	var dirs := [Vector2(960, 0), Vector2(-17, 385), Vector2(-840, 0)]
	for u in bt.units:
		if u and u.party:
			_slide[u] = dirs[randi() % 3]
