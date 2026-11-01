extends Node
## 创意工坊 E4 验收测试 (field 收到 --mod-e4-test 时挂上): --mod=../mods/e4-chars --map=12201 (新游戏)
## 1. 车芸改名「小芸」(人名表 / 战斗记录)、5 级开局、HP 999  2. 成长表: 升到 6 级习得 6401、属性按这一行加
## 3. 地图模型换成 ACT 110  4. 开局金钱 5000、物品、嬴诗开局在队 (旗标 2)  5. 嬴诗没改的照原版。结果打印 E4 PASS / E4 FAIL

var field: Node
var fails: Array = []


func _ready() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print("E4 %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		fails.append(what)


func _run() -> void:
	await get_tree().create_timer(3.0).timeout
	var m1: Dictionary = State.member(1)
	_check(field.person_name(1) == "小芸" and str(Battle.obj(1).name) == "小芸", "车芸改名: 人名表「%s」、战斗记录「%s」" % [field.person_name(1), str(Battle.obj(1).name)])
	_check(int(m1.lv) == 5 and int(m1.hp_max) == 999, "开局 %d 级、HP 上限 %d" % [int(m1.lv), int(m1.hp_max)])
	_check(field.player != null and field.player.act == 110, "地图模型 ACT %d" % (field.player.act if field.player else -1))
	_check(State.money == 5000 and State.item_count(3001) == 2 and State.item_count(3005) == 1, "开局金钱 %d、草药 %d" % [State.money, State.item_count(3001)])
	_check(State.test_flag(1) and State.test_flag(2) and not State.test_flag(3), "开局在队: 车芸、嬴诗")
	var hp0 := int(m1.hp_max)
	var row: Array = []
	for r in Battle.db.growth["1"]:
		if int(r[0]) == 6:
			row = r
	State.add_exp(1, State.exp_threshold(5) - int(m1.exp))
	var sid: int = Mods.skill_id("kp.e4-chars", 1)
	_check(int(m1.lv) == 6 and int(m1.hp_max) == hp0 + int(row[1]) and (State.skills.get(1, []) as Array).has(sid),
		"升到 6 级: HP +%d、习得新技能 %d (%s)" % [int(row[1]), sid, str(State.skills.get(1, []))])
	# E5 技能
	var s1: Dictionary = Battle.obj(sid)
	var hx: Dictionary = Mods._orig.get("obj:6701", {})
	_check(str(s1.get("name")) == "恨心诀·改" and int(s1.power) == 4600 and int(s1.cost.sp) == 30 and int(s1.atk_id) == 6401 and int(s1.scope) == 1 and int(s1.sub) == 201,
		"新技能 = 恨心诀复制: 威力 4600、体力 30、演出 / 范围 / 分类照抄")
	_check(int(Battle.obj(6701).power) == 5000 and int(hx.get("power", 0)) == 3500 and str(Battle.obj(6701).name) == "魑魅拳", "改原版魑魅拳: 威力 3500 → 5000, 其余不变")
	_check((State.skills.get(2, []) as Array).has(sid), "嬴诗开局就会新技能")
	var m2: Dictionary = State.member(2)
	_check(int(m2.lv) == 8 and str(Battle.obj(2).name) == "嬴诗", "嬴诗没改: %d 级「%s」" % [int(m2.lv), str(Battle.obj(2).name)])
	print("E4 %s" % ("PASS" if fails.is_empty() else "FAIL " + str(fails)))
	get_tree().quit()
