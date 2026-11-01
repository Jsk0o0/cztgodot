extends Node
## 创意工坊 M1 验收测试 (field 收到 --mod-m1-test 时挂上): 需同时给 --mod=../mods/cheyun-gold --map=12201 --auto-advance=0.05
## 1. mod 的 NPC 出现在令狐国东城  2. 空格调查对话 → 金钱 +9999、mod 旗标置位  3. 再对话 → 金钱不变 (已领过)
## 4. 存档 / 读档后旗标仍在  5. 名字取 mod 里的显示名。结果打印 M1 PASS / M1 FAIL

var MOD_ID := "kp.cheyun-gold"   # --mod-test-id=别的 id: 只跑对话 + 金钱检查 (检查用户自己做的 mod)
var field: Node
var fails: Array = []


func _ready() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print("M1 %s %s" % ["ok  " if ok else "FAIL", what])
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
	field.cam.set_target(npc.gpos + Vector3(0, 100, 45))   # 镜头对准两人 (截图检查用)
	field.cam.snap()
	print("M1 debug hit=%s event=%d code=%d busy=%s player=%s npc=%s flags=0x%x" % [field.is_investigate_hit(npc, field.player.gpos, field.player.facing),
		npc.event_id, field.event_code(npc.event_id).size(), field.busy, field.player.gpos, npc.gpos, npc.flags])
	field._investigate()
	await _idle()


func _run() -> void:
	await get_tree().create_timer(3.0).timeout
	await _idle()
	var quick := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--mod-test-id="):
			MOD_ID = a.substr(14)
			quick = true
	var aid: int = Mods.actor_id(MOD_ID, 1)
	var flag: int = Mods.flag_id(MOD_ID, 1)
	var npc: FieldActor = field.actors.get(aid)
	_check(npc != null and not npc.hidden, "NPC %d 出现在地图 %d" % [aid, field.map_id])
	if npc == null:
		_done()
		return
	if quick:
		var talks := 1   # --mod-test-talks=N: 连续对话 N 次 (检查「只给一次」之类)
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--mod-test-talks="):
				talks = int(a.substr(17))
		for i in talks:
			var q0: int = State.money
			await _talk(npc)
			print("M1 quick 第 %d 次对话: 金钱 %d → %d" % [i + 1, q0, State.money])
		_done()
		return
	_check(field.person_name(aid) == "送盘缠的老伯", "人名 = %s" % field.person_name(aid))
	State.set_flag(flag, false)
	var m0: int = State.money
	await _talk(npc)
	_check(State.money == m0 + 9999, "第一次对话 金钱 %d → %d" % [m0, State.money])
	_check(State.test_flag(flag), "mod 旗标 %d 已置位" % flag)
	var m1: int = State.money
	await _talk(npc)
	_check(State.money == m1, "第二次对话 金钱不变 (%d)" % State.money)
	field.save_game(79)
	State.set_flag(flag, false)
	State.load_slot(79)
	_check(State.test_flag(flag), "存档 / 读档后旗标仍在")
	_done()


func _done() -> void:
	print("M1 %s" % ("PASS" if fails.is_empty() else "FAIL " + str(fails)))
	get_tree().quit()
