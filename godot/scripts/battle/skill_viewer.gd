class_name SkillViewer
extends CanvasLayer
## 技能观看器 (make preview): 用正式战斗引擎施放任意技能 —— 三人能学的、普通攻击、怪物 / 首领的全部技能
## 左侧列表: ←→ 换分类, ↑↓ 选技能, Enter / 空格 / 点击 施放, R 循环施放, Esc 回标题
## 怪物技能由会这招的怪物来放 (替换敌方 6 号位), 目标是我方; 放完全员复原

var bt: Battle
var cats: Array = []        # [{name, items: [{id, name, caster, sub, info}]}]
var cat := 0
var sel := 0
var top := 0
var busy := false
var looping := false
var _c: Control
var _info := ""
const ROWS := 21
const PANEL := Rect2(4, 4, 236, 592)
const BG := Color(0.08, 0.06, 0.04, 0.82)
const FG := Color(0.95, 0.9, 0.78)
const HI := Color(0.95, 0.7, 0.3)


func _ready() -> void:
	layer = 30
	_c = Control.new()
	_c.size = Vector2(800, 600)
	_c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_c.draw.connect(_draw)
	add_child(_c)
	_build_list()
	for arg in OS.get_cmdline_user_args():   # 调试: --viewer-cast=施放者:技能 (施放者 = 队员号 / −怪物号), 进场 1.5 秒后直接放, 放完再放一次
		if arg == "--viewer-no-ui":   # 录像用: 不画左侧技能表
			_c.visible = false
		if arg.begins_with("--viewer-cast="):
			var kv := arg.substr(14).split(":")
			_debug_cast.call_deferred(int(kv[0]), int(kv[1]))


## 分类: 车芸 / 嬴诗 / 桓远之 (初始 + 升级习得 + 木甲板, 加普通攻击) / 怪物技能 / 其他 (没有人会的)
func _build_list() -> void:
	var db := Battle.db
	var objs: Dictionary = db.objs
	var init: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Game.extracted_dir.path_join("game/new_game.json"))).get("init", {}).get("skills", {})
	var owned := {}
	for m in [1, 2, 3]:
		var ids: Array = []
		for s in init.get(str(m), []):
			ids.append(int(s))
		for row in db.growth.get(str(m), []):
			if int(row[13]):
				ids.append(int(row[13]))
		if m == 1:
			for mech in MenuJiguan.MECHS:
				if int(mech[4]) == 1:
					ids.append(int(mech[3]))
		var items: Array = [{"id": 0, "name": "普通攻击", "caster": m, "info": "普通攻击 (随机出招 / 奋力一击)"}]
		var seen := {}
		for id in ids:
			var r: Dictionary = objs.get(str(id), {})
			if seen.has(id) or r.is_empty() or int(r.get("atk_id", 0)) == 0:
				continue
			seen[id] = true
			owned[id] = true
			items.append({"id": id, "name": str(r.name), "caster": m, "info": _desc(id)})
		cats.append({"name": str(objs[str(m)].name), "items": items})
	var mons: Array = []
	var mon_owner := {}
	var keys: Array = objs.keys()
	keys.sort_custom(func(a, b): return int(a) < int(b))
	for k in keys:
		var o: Dictionary = objs[k]
		if int(o.get("kind", 0)) != 1 or int(k) <= 11:
			continue
		for s in o.get("skills", []):
			var sid := int(s)
			var r: Dictionary = objs.get(str(sid), {})
			if sid == 0 or owned.has(sid) or r.is_empty() or int(r.get("atk_id", 0)) == 0:
				continue
			if not FileAccess.file_exists(Game.asset_path("game/actors/act_%d.json" % int(k))):
				continue
			if not mon_owner.has(sid):
				mon_owner[sid] = int(k)
				mons.append({"id": sid, "name": "%s · %s" % [str(o.name), str(r.name)], "caster": -int(k), "info": _desc(sid)})
	cats.append({"name": "怪物技能", "items": mons})
	var other: Array = []
	for k in keys:
		var r2: Dictionary = objs[k]
		var sid2 := int(k)
		if int(r2.get("kind", 0)) == 3 and int(r2.get("atk_id", 0)) and not owned.has(sid2) and not mon_owner.has(sid2):
			other.append({"id": sid2, "name": str(r2.name), "caster": 1, "info": _desc(sid2) + "\n(没有角色会这招, 由车芸代放)"})
	cats.append({"name": "其他", "items": other})
	var total := 0
	for c in cats:
		total += c.items.size()
	print("SKILLVIEWER %d 招: %s" % [total, str(cats.map(func(c): return "%s %d" % [c.name, c.items.size()]))])


func _desc(id: int) -> String:
	var r: Dictionary = Battle.db.objs.get(str(id), {})
	var side: String = {1: "我方", 2: "敌方"}.get(int(r.get("side", 2)), "任意")
	var scope: String = {0: "单体", 1: "全体", 2: "自身"}.get(int(r.get("scope", 0)), "")
	var c: Dictionary = r.get("cost", {})
	var cost := ""
	for k in [["mp", "灵力"], ["sp", "体力"], ["hp", "生命"]]:
		if int(c.get(k[0], 0)):
			cost += "%s%d " % [k[1], int(c[k[0]])]
	return "%s  目标: %s%s  威力 %d  %s\nATK %d    %s" % [str(r.get("name", "")), side, scope, int(r.get("power", 0)),
		cost, int(r.get("atk_id", 0)), str(r.get("note", r.get("desc", "")))]


func _items() -> Array:
	return cats[cat].items


func _input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo:
		var k := (e as InputEventKey).keycode
		get_viewport().set_input_as_handled()
		match k:
			KEY_LEFT, KEY_RIGHT:
				cat = wrapi(cat + (1 if k == KEY_RIGHT else -1), 0, cats.size())
				sel = 0
				top = 0
			KEY_UP:
				sel = maxi(sel - 1, 0)
			KEY_DOWN:
				sel = mini(sel + 1, _items().size() - 1)
			KEY_PAGEUP:
				sel = maxi(sel - ROWS, 0)
			KEY_PAGEDOWN:
				sel = mini(sel + ROWS, _items().size() - 1)
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				cast()
			KEY_R:
				looping = not looping
				if looping:
					cast()
			KEY_ESCAPE:
				get_tree().change_scene_to_file("res://scenes/title.tscn")
		top = clampi(top, sel - ROWS + 1, sel)
		_c.queue_redraw()
	elif e is InputEventMouseButton and e.pressed:
		var mb := e as InputEventMouseButton
		var m := _c.get_local_mouse_position()
		if not PANEL.has_point(m):
			return
		get_viewport().set_input_as_handled()
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			top = maxi(top - 3, 0)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			top = clampi(top + 3, 0, maxi(_items().size() - ROWS, 0))
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if m.y < 40:
				cat = wrapi(cat + (1 if m.x > PANEL.get_center().x else -1), 0, cats.size())
				sel = 0
				top = 0
			else:
				var i := top + int((m.y - 44) / 24)
				if i >= 0 and i < _items().size():
					if i == sel:
						cast()
					sel = i
		_c.queue_redraw()


func _debug_cast(caster: int, id: int) -> void:
	await get_tree().create_timer(1.5).timeout
	for k in 2:
		busy = true
		await bt.viewer_cast(caster, id)
		busy = false
		print("VIEWER_CAST_DONE %d" % k)
		await get_tree().create_timer(1.0).timeout


func cast() -> void:
	if busy or _items().is_empty():
		return
	busy = true
	var it: Dictionary = _items()[sel]
	_info = str(it.info)
	_c.queue_redraw()
	await bt.viewer_cast(int(it.caster), int(it.id))
	busy = false
	_c.queue_redraw()
	if looping:
		await get_tree().create_timer(0.6).timeout
		cast()


func _draw() -> void:
	var f: Font = Game.font_body
	_c.draw_rect(PANEL, BG)
	_c.draw_string(f, Vector2(14, 28), "◀  %s  (%d)  ▶" % [cats[cat].name, _items().size()], HORIZONTAL_ALIGNMENT_CENTER, 220, 18, HI)
	var items := _items()
	for r in ROWS:
		var i := top + r
		if i >= items.size():
			break
		var y := 44 + r * 24
		if i == sel:
			_c.draw_rect(Rect2(8, y, 228, 23), Color(0.6, 0.4, 0.15, 0.6))
		_c.draw_string(f, Vector2(14, y + 17), str(items[i].name), HORIZONTAL_ALIGNMENT_LEFT, 218, 15, FG if i != sel else Color.WHITE)
	var hint := "←→分类 ↑↓选择 Enter施放 R循环%s Esc退出" % ("中" if looping else "")
	_c.draw_string(f, Vector2(10, 588), hint, HORIZONTAL_ALIGNMENT_LEFT, 228, 11, Color(FG, 0.75))
	if _info != "":   # 技能说明: 画面上方
		_c.draw_rect(Rect2(244, 4, 552, 46), BG)
		var lines := _info.split("\n")
		for li in mini(lines.size(), 2):
			_c.draw_string(f, Vector2(252, 22 + li * 20), lines[li], HORIZONTAL_ALIGNMENT_LEFT, 540, 14, FG)
