extends Node
## 创意工坊 M10 验收测试 (field 收到 --mod-m10-test 时挂上): --mod=../mods/m10-encounter --map=12201 --auto-battle --auto-advance=0.05
## 1. 晋国大地图 (12001) 每个遇敌区域的战场列表里加了 mod 战斗 ×20 (原版条目不变)
## 2. 遇敌战 (非剧情战) 打赢: 两只山贼熊各给变量 +1 3. mod 怪物收化几率 = 不能收 4. 熊掌柜: 不够两只不给, 够了给 300 金一次
## 结果打印 M10 PASS / M10 FAIL

const MOD_ID := "kp.m10-encounter"
var field: Node
var fails: Array = []
var _result := ""
var _story := true
var _no_capture := false


func _ready() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print("M10 %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		fails.append(what)


func _idle() -> void:
	await get_tree().create_timer(0.5).timeout
	while field.busy or not field.dialog.windows.is_empty():
		await get_tree().process_frame
	await get_tree().create_timer(0.3).timeout


func _talk(npc: FieldActor) -> void:
	field.player.set_game_pos(npc.gpos + Vector3(0, 0, 90))
	field.player.face_point(npc.gpos)
	field._investigate()
	await _idle()


func _run() -> void:
	await get_tree().create_timer(3.0).timeout
	await _idle()
	var bid: int = Mods.battle_id(MOD_ID, 1)
	var mid: int = Mods.monster_id(MOD_ID, 1)
	var who: int = Mods.actor_id(MOD_ID, 0)
	var orig: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Game.extracted_dir.path_join("game/maps.json")))
	var zones: Array = field.maps["12001"].zones
	var ok := zones.size() == (orig["12001"].zones as Array).size()
	for zi in zones.size():
		var bl: Array = zones[zi].battlefields
		var ob: Array = orig["12001"].zones[zi].battlefields
		ok = ok and bl.slice(0, ob.size()) == ob and bl.count(bid) == 20 and bl.size() == ob.size() + 20
	_check(ok, "晋国大地图 %d 个遇敌区域都加了 mod 战斗 ×20, 原版条目不变" % zones.size())
	_check(Battle.obj(mid).get("kill_var") == [who, 1], "山贼熊被打倒时给变量 1 +1 (%s)" % str(Battle.obj(mid).get("kill_var")))
	var npc: FieldActor = field.actors.get(Mods.actor_id(MOD_ID, 1))
	var m0: int = State.money
	await _talk(npc)
	_check(State.money == m0 and State.actor_var(who, 1) == 0, "还没打: 熊掌柜不给钱")
	for m in State.party:
		var md := State.member(int(m))
		State.add_exp(int(m), State.exp_threshold(40) - int(md.exp))
		md.hp = md.hp_max
	field.child_entered_tree.connect(func(n: Node):
		if n is Battle:
			var b := n as Battle
			b.finished.connect(func(r: String): _result = r)
			await get_tree().create_timer(1.0).timeout
			if is_instance_valid(b):
				_story = b.story
				var bear: BattleUnit = b.units[6]
				var bandit: BattleUnit = b.units[7]
				var me := BattleUnit.new()
				me.level = 99   # 等级差 > 10: 原版怪物必定收得到 (0x432e84)
				_no_capture = bear != null and b.capture_odds(me, bear) == -1 and bandit != null and b.capture_odds(me, bandit) == 99)
	await field._encounter(bid)   # 遇敌战 (同 _check_encounter 选中这场)
	await _idle()
	_check(_result == "win" and not _story, "遇敌战打赢 (非剧情战: %s)" % str(not _story))
	_check(State.actor_var(who, 1) == 2, "打倒两只山贼熊, 变量 = %d" % State.actor_var(who, 1))
	_check(_no_capture, "收化几率: 山贼熊 不能收, 同场的原版强盗 99")
	var m1: int = State.money   # 战斗奖励之后
	await _talk(npc)
	_check(State.money == m1 + 300 and State.test_flag(Mods.flag_id(MOD_ID, 1)), "够两只: 给 300 金 (%d → %d)" % [m1, State.money])
	await _talk(npc)
	_check(State.money == m1 + 300, "领过以后不再给")
	print("M10 %s" % ("PASS" if fails.is_empty() else "FAIL " + str(fails)))
	get_tree().quit()
