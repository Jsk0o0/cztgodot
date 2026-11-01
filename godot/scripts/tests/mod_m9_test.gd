extends Node
## 创意工坊 M9 验收测试 (field 收到 --mod-m9-test 时挂上): --mod=../mods/m9-model --map=12201 --auto-battle --auto-advance=0.05
## 怪物「飞天山贼」= 原版熊复制 + 自定义战斗模型 (mon440): 1. 动作表照抄熊的 ACT (帧数 / 命中记号 / 音效), 动画换成 mod 指定的
## 2. 战斗里用自定义模型, 普攻播 handatk01、动画拉伸到原版帧数 3. 命中照常结算, 打赢 4. 图鉴显示自定义模型。结果打印 M9 PASS / M9 FAIL

const MOD_ID := "kp.m9-model"
var field: Node
var fails: Array = []
var _played := {}      # 动作号 → 实际播放的动画名
var _fit17 := 0.0
var _result := ""
var _enemy_act := -1
var _hurt_seen := false


func _ready() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print("M9 %s %s" % ["ok  " if ok else "FAIL", what])
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


func _process(_dt: float) -> void:
	for b in field.get_children():
		if not b is Battle:
			continue
		var u: BattleUnit = b.units[6] if b.units.size() > 6 else null
		if u == null or u.actor == null:
			continue
		_enemy_act = u.actor.act
		var ap: AnimationPlayer = u.actor._ap
		if ap and ap.current_animation != "":
			_played[u.actor.pose] = ap.current_animation
			if u.actor.pose == 17:
				_fit17 = u.actor._fit
		if u.hp < u.hp_max:
			_hurt_seen = true


func _run() -> void:
	await get_tree().create_timer(3.0).timeout
	await _idle()
	var mid: int = Mods.monster_id(MOD_ID, 1)
	var rec: Dictionary = Battle.obj(mid)
	var bear: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Game.extracted_dir.path_join("game/actors/act_1017.json")))
	_check(int(rec.get("act", 0)) == mid and Mods.has_model(mid), "怪物 %d 的战斗模型 = 虚拟 ACT %d" % [mid, int(rec.get("act", 0))])
	var meta: Dictionary = Mods.model_meta(mid)
	var p17: Dictionary = meta.poses.get("17", {})
	_check(str(p17.get("clip")) == "mon440_handatk01" and int(p17.ticks) == int(bear.poses["17"].ticks) and p17.marks == bear.poses["17"].marks and p17.sounds == bear.poses["17"].sounds and p17.fit,
		"普攻 17: 动画 handatk01, 帧数 %d / 命中记号 %s / 音效照抄熊" % [int(p17.get("ticks", 0)), str(p17.get("marks"))])
	_check(meta.poses.size() == bear.poses.size() and str(meta.poses["80"].clip) == "mon440_stand01" and not meta.poses["14"].fit,
		"熊的 %d 个动作都在, 没指定的用待机动画, 循环动作不拉伸" % bear.poses.size())
	for m in State.party:
		var md := State.member(int(m))
		State.add_exp(int(m), State.exp_threshold(40) - int(md.exp))
		md.hp = md.hp_max
	rec.hp = 6000   # 血厚一点, 保证它出手几次 (普攻 / 受伤动作都看得到)
	var npc: FieldActor = field.actors.get(Mods.actor_id(MOD_ID, 1))
	field.child_entered_tree.connect(func(n: Node):
		if n is Battle:
			(n as Battle).finished.connect(func(r: String): _result = r))
	await _talk(npc)
	_check(_enemy_act == mid, "战斗里的敌人用自定义模型 (ACT %d)" % _enemy_act)
	_check(_played.get(14) == "mon440_stand01", "待机播 stand01 (%s)" % str(_played.get(14)))
	_check(_played.get(17) == "mon440_handatk01" and _fit17 > 0.0, "普攻播 handatk01, 拉伸系数 %.2f" % _fit17)
	_check(_played.get(25) == "mon440_hurt" and _hurt_seen, "受伤播 hurt (%s)" % str(_played.get(25)))
	_check(_result == "win", "打赢了 (%s)" % _result)
	print("M9 动作 → 动画: %s" % str(_played))
	print("M9 %s" % ("PASS" if fails.is_empty() else "FAIL " + str(fails)))
	get_tree().quit()
