extends Node
## 隐藏调查点测试 (field 收到 --hidden-spot-test 时挂上): 需同时给 --map=12201 --auto-advance=0.05 --no-encounter
## 令狐国古井 2060 (ACT 16002 动作 8 无网格, 记录标志 0x1481 = 开局隐藏):
## 1. 乞丐 2006 的事件 2059 说出古井秘密并 show_actor(2060)  2. 井能被调查到
## 3. 调查第 21 次得一百钱 (事件 2060: 计数 < 20 只加计数)  4. 再调查 11 次得【恩居图二】5554, 井隐藏
## 另: 发光点 5204 的挂点粒子 (生成 / 第 89 帧停止 / 循环重生 / 隐藏清除)
## 结果打印 HS PASS / HS FAIL

var field: Node
var fails: Array = []


func _ready() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print("HS %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		fails.append(what)


func _idle() -> void:
	await get_tree().create_timer(0.2).timeout
	while field.busy or not field.dialog.windows.is_empty():
		await get_tree().process_frame
	await get_tree().create_timer(0.1).timeout


func _probe(a: FieldActor) -> void:
	field.player.set_game_pos(a.gpos + Vector3(0, 0, 90))
	field.player.face_point(a.gpos)
	field._investigate()
	await _idle()


func _run() -> void:
	await get_tree().create_timer(3.0).timeout
	while field.busy:
		await get_tree().process_frame
	await _glow_check()
	var well: FieldActor = field.actor(2060)
	var beggar: FieldActor = field.actor(2006)
	_check(well != null, "古井 2060 已生成")
	_check(beggar != null, "乞丐 2006 已生成")
	if well == null or beggar == null:
		_done()
		return
	_check(well.hidden and well.flags & 0x1, "古井开局隐藏")
	beggar.event_id = 2059
	await _probe(beggar)
	_check(not well.hidden and not (well.flags & 0x1), "乞丐说完后古井显示, 标志 0x1 已清")
	var m0: int = State.money
	for i in 20:
		await _probe(well)
	_check(State.money == m0, "前 20 次只加计数 (钱 %d → %d)" % [m0, State.money])
	await _probe(well)
	_check(State.money == m0 + 100, "第 21 次得一百钱 (钱 %d → %d)" % [m0, State.money])
	_check(well.event_id == 2061, "事件换成 2061")
	for i in 11:
		await _probe(well)
	_check(State.item_count(5554) == 1, "得到恩居图二 5554 (数量 %d)" % State.item_count(5554))
	_check(well.hidden, "拿完后古井隐藏")
	_done()


## 发光点 5204 (ACT 16002 动作 5, ER 挂点 1 粒子 2038「秘密寶箱」, 停止帧 89, 90 帧循环)
func _glow_check() -> void:
	var g: FieldActor = field.actor(5204)
	_check(g != null and g.pose == 5, "发光点 5204 已生成 (动作 5)")
	if g == null:
		return
	_check(g._er_ems.has(1) and is_instance_valid(g._er_ems[1][0]), "挂点 1 生成了粒子 2038")
	if not g._er_ems.has(1):
		return
	var em1: FxEmitter = g._er_ems[1][0]
	while int(g.pose_tick) < 89:
		await get_tree().process_frame
	await get_tree().create_timer(0.05).timeout
	_check(is_instance_valid(em1) and not em1.emitting, "第 89 帧停止发射")
	while int(g.pose_tick) != 1:
		await get_tree().process_frame
	_check(g._er_ems.has(1) and g._er_ems[1][0] != em1 and (g._er_ems[1][0] as FxEmitter).emitting, "循环回开头后重新生成")
	var em2: FxEmitter = g._er_ems[1][0]
	field.set_actor_hidden(5204, true)
	_check(g._er_ems.is_empty() and not em2.emitting, "隐藏后停止并丢弃")
	field.set_actor_hidden(5204, false)


func _done() -> void:
	print("HS %s" % ("PASS" if fails.is_empty() else "FAIL " + str(fails)))
	get_tree().quit()
