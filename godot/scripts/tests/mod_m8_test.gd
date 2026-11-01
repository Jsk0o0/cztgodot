extends Node
## 创意工坊 M8 验收测试 (field 收到 --mod-m8-test 时挂上): --mod=../mods/m8-battle --map=12201 --auto-battle --auto-advance=0.05
## 1. mod 怪物 = 原版熊复制 + 改名 / 数值 / 经验 / 金钱 / 掉落, 模型 / AI / 技能照抄  2. mod 战场 = 原版战场 74 复制、敌人换掉
## 3. 对话开战 → 打赢 → 经验 / 金钱 / 掉落按记录结算  4. 图鉴出现「山贼熊」 5. 打完后再对话不再开战。结果打印 M8 PASS / M8 FAIL

const MOD_ID := "kp.m8-battle"
const HERB := 3001
var field: Node
var fails: Array = []
var _battle: Battle
var _seen_units: Array = []
var _result := ""
var _rewards := {}


func _ready() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print("M8 %s %s" % ["ok  " if ok else "FAIL", what])
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


## 战斗挂到 field 上时记下单位和结算 (战斗结束后节点就释放了)
func _on_child(n: Node) -> void:
	if n is Battle:
		_battle = n
		_battle.finished.connect(func(r: String):
			_result = r
			_rewards = _battle.rewards.duplicate(true))
		await get_tree().create_timer(1.0).timeout
		if is_instance_valid(_battle):
			_seen_units = _battle.units.filter(func(u): return u != null and not u.party and not u.absent).map(func(u):
				return {"id": u.id, "name": u.name, "hp": u.hp_max, "level": u.level, "act": u.actor.act if u.actor else -1})


func _run() -> void:
	await get_tree().create_timer(3.0).timeout
	await _idle()
	var mid: int = Mods.monster_id(MOD_ID, 1)
	var bid: int = Mods.battle_id(MOD_ID, 1)
	var bear: Dictionary = Battle.obj(1017)
	var rec: Dictionary = Battle.obj(mid)
	_check(str(rec.get("name")) == "山贼熊" and int(rec.level) == 12 and int(rec.hp) == 600 and int(rec.atk) == 360,
		"怪物 %d = 山贼熊 12 级 HP 600 攻击 360" % mid)
	_check(rec.ai == bear.ai and rec.skills == bear.skills and rec.atk_id == bear.atk_id and rec.elem == bear.elem and int(rec.def) == int(bear.def),
		"AI / 技能 / 普攻 / 抗性 / 防御照抄原版熊 (ai %s)" % str(rec.ai))
	_check(int(rec.reward.exp) == 120 and int(rec.reward.money) == 150 and rec.drops[0] == [100, HERB] and rec.drops[1] == bear.drops[1],
		"经验 120 金钱 150 掉落 [100%, 草药], 偷窃物照抄")
	var bf: Dictionary = Battle.db.battlefields.get(str(bid), {})
	var b74: Dictionary = Battle.db.battlefields["74"]
	_check(bf.get("scene") == b74.scene and bf.get("figtalk") == b74.figtalk and bf.enemies.size() == 2
		and int(bf.enemies[0].id) == mid and bf.enemies[0].pos == b74.enemies[0].pos and int(bf.enemies[1].id) == 1034 and bf.enemies[1].pos == b74.enemies[1].pos,
		"战场 %d = 原版 74 的场景 / 脚本 / 站位, 敌人 山贼熊 + 强盗" % bid)
	field.child_entered_tree.connect(_on_child)
	for m in State.party:   # 练到 40 级保证打得赢
		var md := State.member(int(m))
		State.add_exp(int(m), State.exp_threshold(40) - int(md.exp))
		md.hp = md.hp_max
	State.items.erase(HERB)
	var money0: int = State.money
	var npc: FieldActor = field.actors.get(Mods.actor_id(MOD_ID, 1))
	await _talk(npc)
	_check(_seen_units.size() == 2 and str(_seen_units[0].name) == "山贼熊" and int(_seen_units[0].hp) == 600 and int(_seen_units[0].act) == 1017,
		"战斗里的敌人: %s" % str(_seen_units))
	_check(_result == "win", "打赢了 (%s)" % _result)
	var bandit: Dictionary = Battle.obj(1034)
	_check(int(_rewards.get("exp", 0)) == 120 + int(bandit.reward.exp), "经验 = 120 + 强盗 %d = %d" % [int(bandit.reward.exp), int(_rewards.get("exp", 0))])
	# 结算金钱看战后结算; 背包差值可能更少 —— 强盗有原版的偷钱招 (ATK 0x90)
	_check(int(_rewards.get("money", 0)) == 150 + int(bandit.reward.money) and State.money - money0 <= int(_rewards.get("money", 0)),
		"战后金钱 %d (应为 150 + %d), 背包 +%d" % [int(_rewards.get("money", 0)), int(bandit.reward.money), State.money - money0])
	_check(State.item_count(HERB) >= 1 and (_rewards.get("items", []) as Array).has(HERB), "掉落草药 (背包 %d)" % State.item_count(HERB))
	_check(State.test_flag(Mods.flag_id(MOD_ID, 1)), "战后剧情继续: 旗标置位")
	_check(Fame.monsters().has(mid), "认识度记下了山贼熊")
	var mj := MenuJizai.new(MainMenu.new())
	mj.focus = 1
	mj.race = int(Mods.bestiary[0].race_tab) if Mods.bestiary.size() else 0
	var names: Array = mj.entries().map(func(b): return str(b.name))
	_check(names.has("山贼熊") and int(Mods.bestiary[0].hp) == 600 and int(Mods.bestiary[0].model_act) == 1017, "记载「人」页有山贼熊: %s" % str(names))
	_result = ""
	await _talk(npc)
	_check(_result == "", "打完后再对话不再开战")
	print("M8 %s" % ("PASS" if fails.is_empty() else "FAIL " + str(fails)))
	get_tree().quit()
