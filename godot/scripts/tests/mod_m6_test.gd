extends Node
## 创意工坊 M6 验收测试 (field 收到 --mod-m6-test 时挂上): --mod=../mods/m6-items --map=12201 --auto-advance=0.05
## 1. mod 物品记录 = 原版草药复制 + 改名 / 说明 / 价格 / 恢复量  2. 对话拿到 2 个  3. 地图上使用: 恢复一半生命、扣 1 个
## 4. 存档 / 读档后还在  5. mod 没启用时显示「失效物品」。结果打印 M6 PASS / M6 FAIL

const MOD_ID := "kp.m6-items"
var field: Node
var fails: Array = []


func _ready() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print("M6 %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		fails.append(what)


func _idle() -> void:
	await get_tree().create_timer(0.5).timeout
	while field.busy or not field.dialog.windows.is_empty():
		await get_tree().process_frame
	await get_tree().create_timer(0.3).timeout


func _run() -> void:
	await get_tree().create_timer(3.0).timeout
	await _idle()
	var iid: int = Mods.item_id(MOD_ID, 1)
	var r := Battle.obj(iid)
	var base := Battle.obj(3001)
	_check(str(r.get("name")) == "熊掌蜜饯" and int(r.get("price")) == 80, "物品 %d = %s 价格 %s" % [iid, r.get("name"), r.get("price")])
	_check(int(r.get("sub")) == int(base.sub) and int(r.get("atk_id")) == int(base.atk_id) and str(r.get("icon")) == str(base.icon),
		"分类 / 使用演出 / 图标照抄草药 (sub %s atk %s)" % [r.get("sub"), r.get("atk_id")])
	_check(int(r.fx1[0]) == 10050, "恢复量 fx1 = %s" % str(r.get("fx1")))
	_check(field.dialog.item_name(iid) == "熊掌蜜饯", "对白物品名 = %s" % field.dialog.item_name(iid))
	# 对话拿物品
	var npc: FieldActor = field.actors.get(Mods.actor_id(MOD_ID, 1))
	State.items.erase(iid)
	field.player.set_game_pos(npc.gpos + Vector3(0, 0, 90))
	field.player.face_point(npc.gpos)
	field._investigate()
	await _idle()
	_check(State.item_count(iid) == 2, "对话后有 %d 个" % State.item_count(iid))
	# 地图上使用
	# 对象用嬴诗 (2): 复制的是人用的回复药 (对象类别 4), 原版不能给车芸用 (0x489a43)
	var d := State.member(2)
	d.hp = 1
	var menu := MainMenu.new()
	menu.field = field
	add_child(menu)
	menu._use_item(iid, 2)
	var want := 1 + int(d.hp_max) * 50 / 100
	_check(int(d.hp) == mini(want, int(d.hp_max)), "使用后生命 1 → %d (上限 %d, 应为 %d)" % [d.hp, d.hp_max, want])
	_check(State.item_count(iid) == 1, "用掉 1 个, 剩 %d" % State.item_count(iid))
	menu.queue_free()
	# 存档 / 读档
	field.save_game(79)
	State.items.erase(iid)
	State.load_slot(79)
	_check(State.item_count(iid) == 1, "读档后还有 %d 个" % State.item_count(iid))
	# mod 没启用
	var gone := Battle.obj(Mods.ITEM_BASE + 9999 * 256 + 7)
	_check(str(gone.get("name")) == "失效物品" and int(gone.get("sellable", 1)) == 0, "未启用 mod 的物品 = %s" % gone.get("name"))
	print("M6 %s" % ("PASS" if fails.is_empty() else "FAIL " + str(fails)))
	get_tree().quit()
