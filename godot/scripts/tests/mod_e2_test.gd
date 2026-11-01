extends Node
## 创意工坊 E2 验收测试 (field 收到 --mod-e2-test 时挂上): --mod=../mods/e2-override --map=12201 --auto-advance=0.05
## 方案覆盖原版: 1. 老伯 (2016) 的原版对话事件被整段替换 (第一句台词改了、多设一个旗标)  2. 讲古老人 (2005) 改用方案的新事件
## 3. 猪肉大夫 (2011) 挪位置、改名  4. 小胖猪 (2009) 删掉  5. 没改的 NPC (娥氏 2004) 照旧。结果打印 E2 PASS / E2 FAIL

const MOD_ID := "kp.e2-override"
var field: Node
var fails: Array = []
var _seen: Array = []   # 对话框里出现过的文字


func _ready() -> void:
	_run.call_deferred()


func _process(_dt: float) -> void:
	for k in field.dialog.windows:   # 每页 = [行...], 行 = [[字符, 颜色, 速度]...] → 拼回文字
		var t := ""
		for pg in field.dialog.windows[k].pages:
			for ln in pg:
				for ch in ln:
					t += str(ch[0])
		if not _seen.has(t):
			_seen.append(t)


func _check(ok: bool, what: String) -> void:
	print("E2 %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		fails.append(what)


func _idle() -> void:
	await get_tree().create_timer(0.5).timeout
	while field.busy or not field.dialog.windows.is_empty():
		await get_tree().process_frame
	await get_tree().create_timer(0.3).timeout


func _talk(npc: FieldActor) -> void:
	# 站到 NPC 旁边 (四个方向里第一个能调查到它的; 有的 NPC 一侧贴着墙, 主角放不过去)
	for off in [Vector3(0, 0, 90), Vector3(0, 0, -90), Vector3(90, 0, 0), Vector3(-90, 0, 0)]:
		field.player.set_game_pos(npc.gpos + off)
		field.player.face_point(npc.gpos)
		if field.is_investigate_hit(npc, field.player.gpos, field.player.facing):
			break
	field._investigate()
	await _idle()


func _said(s: String) -> bool:
	return _seen.any(func(t): return (t as String).contains(s))


func _run() -> void:
	await get_tree().create_timer(3.0).timeout
	await _idle()
	_check(Mods.has_override(2016) and not Mods.has_override(2004), "方案改了原版事件 2016, 没改 2004")
	_check(not field.actors.has(2009), "小胖猪 (2009) 删掉了")
	var pig: FieldActor = field.actors.get(2011)
	_check(pig != null and absf(pig.gpos.x - 22573) < 1.0 and field.person_name(2011) == "猪肉西施", "猪肉大夫挪到 x=%s, 名字「%s」" % [str(pig.gpos.x if pig else -1), field.person_name(2011)])
	var story: FieldActor = field.actors.get(2005)
	_check(story != null and story.event_id == Mods.event_id(MOD_ID, 1), "讲古老人的对话事件 = 方案事件 %d" % (story.event_id if story else -1))
	await _talk(field.actors.get(2016))
	_check(_said("（方案改过的台词）") and State.test_flag(Mods.flag_id(MOD_ID, 1)), "和老伯说话: 改过的台词、旗标都有")
	await _talk(story)
	_check(_said("老朽的故事讲完啦") and State.test_flag(Mods.flag_id(MOD_ID, 2)), "和讲古老人说话: 走方案的新事件")
	_seen.clear()
	await _talk(field.actors.get(2004))
	_check(_said("这个小娥"), "娥氏照旧说原版台词")
	print("E2 %s" % ("PASS" if fails.is_empty() else "FAIL " + str(fails)))
	get_tree().quit()
