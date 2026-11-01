extends Node
## 创意工坊 M7 验收测试 (field 收到 --mod-m7-test 时挂上): --mod=../mods/m7-quest --map=12201 --auto-advance=0.05
## 对话接任务 → 记载「未完成任务」有它 → 草药不够不收 → 凑够 3 株交任务 (收草药、+500 金) → 「已完成任务」有它 → 再对话不变
## 结果打印 M7 PASS / M7 FAIL

const MOD_ID := "kp.m7-quest"
const HERB := 3001
var field: Node
var fails: Array = []


func _ready() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print("M7 %s %s" % ["ok  " if ok else "FAIL", what])
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


func _book(sub: int) -> Array:
	var mj := MenuJizai.new(MainMenu.new())
	mj.focus = 0
	mj.sub = sub
	return mj.entries().map(func(q): return str(q.text))


func _run() -> void:
	await get_tree().create_timer(3.0).timeout
	await _idle()
	var npc: FieldActor = field.actors.get(Mods.actor_id(MOD_ID, 1))
	var fa: int = Mods.flag_id(MOD_ID, 901)
	var fd: int = Mods.flag_id(MOD_ID, 951)
	const TITLE := "☆带 3 株草药给熊掌柜"
	_check(Mods.quests.size() == 1 and str(Mods.quests[0].text) == TITLE, "mod 任务已加载: %s" % str(Mods.quests.map(func(q): return q.text)))
	State.items.erase(HERB)
	_check(not _book(0).has(TITLE), "接任务前记载里没有")
	await _talk(npc)
	_check(State.test_flag(fa) and not State.test_flag(fd), "第一次对话: 接受了任务")
	_check(_book(0).has(TITLE) and not _book(1).has(TITLE), "记载「未完成任务」里有它")
	State.give_item(HERB, 1)
	var m0: int = State.money
	await _talk(npc)
	_check(State.item_count(HERB) == 1 and State.money == m0 and not State.test_flag(fd), "草药不够: 不收、不给钱、没完成")
	State.give_item(HERB, 3)
	await _talk(npc)
	_check(State.item_count(HERB) == 1, "交任务: 收走 3 株, 剩 %d" % State.item_count(HERB))
	_check(State.money == m0 + 500, "得到 500 金 (%d → %d)" % [m0, State.money])
	_check(State.test_flag(fd), "任务完成旗标置位")
	_check(_book(1).has(TITLE) and not _book(0).has(TITLE), "记载「已完成任务」里有它")
	var m1: int = State.money
	await _talk(npc)
	_check(State.money == m1 and State.item_count(HERB) == 1, "完成后再对话不变")
	print("M7 %s" % ("PASS" if fails.is_empty() else "FAIL " + str(fails)))
	get_tree().quit()
