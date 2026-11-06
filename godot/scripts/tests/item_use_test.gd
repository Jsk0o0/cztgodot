extends Node
## 地图菜单使用道具测试 (field 收到 --item-use-test 时挂上): 原版 0x488af9 可用判断 + 0x48982f / 0x488ffa 效果
## 结果打印 IU PASS / IU FAIL

var field: Node
var fails: Array = []
var menu: MainMenu


func _ready() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print("IU %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		fails.append(what)


func _run() -> void:
	await get_tree().create_timer(1.0).timeout
	menu = MainMenu.new()
	menu.field = field
	add_child(menu)
	menu._members = [1, 2, 3]
	# 可用判断: 子类 202 / 203 且 field_use 1 / 2
	for id in [3001, 3701, 3705, 3708, 3709]:
		_check(menu._usable(id), "%d %s 可以使用" % [id, Battle.obj(id).name])
	for id in [3601, 3401, 3803, 3903]:
		_check(not menu._usable(id), "%d %s 不能在地图上用" % [id, Battle.obj(id).name])
	# 舍利子 3701: 仙防 +10
	var d2 := State.member(2)
	var mdef := int(d2.mdef)
	_use(3701, 2)
	_check(int(d2.mdef) == mdef + 10 and State.item_count(3701) == 0, "舍利子: 嬴诗仙防 %d → %d, 扣掉" % [mdef, d2.mdef])
	# 活骨灵药 3705: 体力上限 +50, 当前体力不变
	var d1 := State.member(1)
	var spm := int(d1.sp_max)
	var sp := int(d1.sp)
	_use(3705, 1)
	_check(int(d1.sp_max) == spm + 50 and int(d1.sp) == sp, "活骨灵药: 车芸体力上限 %d → %d, 当前 %d" % [spm, d1.sp_max, d1.sp])
	# 七合龙爪花 3708: 攻防仙攻仙防各 +5
	var d3 := State.member(3)
	var b := [int(d3.atk), int(d3.def), int(d3.matk), int(d3.mdef)]
	_use(3708, 3)
	_check([int(d3.atk), int(d3.def), int(d3.matk), int(d3.mdef)] == [b[0] + 5, b[1] + 5, b[2] + 5, b[3] + 5], "七合龙爪花: 桓远之 %s → %s" % [b, [d3.atk, d3.def, d3.matk, d3.mdef]])
	# 草药 3001 对象类别 4: 车芸不能用, 不扣
	d1.hp = 1
	_use(3001, 1)
	_check(int(d1.hp) == 1 and State.item_count(3001) == 1, "草药不能给车芸用 (生命 %d, 剩 %d)" % [d1.hp, State.item_count(3001)])
	# 草药给满血的嬴诗: 目前不需要恢复, 不扣
	d2.hp = d2.hp_max
	State.items.erase(3001)
	_use(3001, 2)
	_check(State.item_count(3001) == 1, "满血用草药不扣 (剩 %d)" % State.item_count(3001))
	# 鹿茸膏 3004 全体 +600, 类别 4 跳过车芸
	d1.hp = 1
	d2.hp = 1
	d3.hp = 1
	_use(3004, 2)
	_check(int(d1.hp) == 1 and int(d2.hp) == mini(601, int(d2.hp_max)) and int(d3.hp) == mini(601, int(d3.hp_max)) and State.item_count(3004) == 0,
		"鹿茸膏全体: 车芸 %d 嬴诗 %d 桓远之 %d" % [d1.hp, d2.hp, d3.hp])
	# 倒下的人: 草药无效; 九命猫脑浆 3802 全体复活全满
	d2.hp = 0
	State.items.erase(3001)
	_use(3001, 2)
	_check(int(d2.hp) == 0 and State.item_count(3001) == 1, "草药救不了倒下的嬴诗")
	State.items.erase(3001)
	_use(3802, 2)
	_check(int(d2.hp) == int(d2.hp_max) and int(d1.hp) == int(d1.hp_max), "九命猫脑浆: 嬴诗 %d/%d 车芸 %d/%d" % [d2.hp, d2.hp_max, d1.hp, d1.hp_max])
	print("IU %s" % ("PASS" if fails.is_empty() else "FAIL " + str(fails)))
	get_tree().quit()


func _use(id: int, m: int) -> void:
	State.items.erase(id)
	State.give_item(id, 1)
	menu._use_item(id, m)
