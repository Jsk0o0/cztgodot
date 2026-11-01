class_name Autoplay
extends Node
## 自动通关测试 (--autoplay): 地图空闲时挑一个「可能推进剧情」的触发点, 瞬移过去触发, 直到离开序章地图或卡住
##   候选: 当前地图上可对话 / 调查的角色 (_can_talk) 和启用中的事件框 (boxes)
##   依赖: 事件脚本 (含 call_event 转入的) 里判断的旗标 / 角色变量 / 物品 / 金钱; 只有依赖值和上次触发时不同才重试 (结果必然相同)
##   推进 = 持久状态有变化 (旗标 8080 / 8052 是临时旗标, 不算) 或换了地图
##   当前地图没有可试的候选时, 沿出口图 (事件框里的 change_map) 找最近一张还有可试候选的地图, 走过去
##   选项: 先选第一个; 同一触发点依赖没变时依次换第 2、3… 个 (Dialog.auto_choice)
## 参数: --autoplay [--speed=4] [--ap-limit=秒] ; 一般搭配 --auto-battle --auto-advance=0.05 --no-encounter --sd
## 输出: 「AP …」日志行; 结束时打印 AP DONE / AP STUCK 和统计

const PROLOGUE_MAPS := [12403, 12201, 12202, 12412, 12603, 12607, 12602, 12605, 12606, 12609, 12610, 12604, 13029]   # 13029 天书世界 (可随时进出的教学区)
const TEMP_FLAGS := [8080, 8052, 8061]   # 8061 = 下雪天气开着 (field.set_weather, 进出太恒山就切换), 不是剧情状态

var field: Node
var tried := {}            # "键#选项" → {依赖快照的哈希: true} (试过的所有依赖组合)
var seen_states := {}      # 出现过的持久状态哈希 (回到旧状态不算推进, 避免旗标来回切换的死循环)
var blocked_exits := {}    # 出口键 → 当时的状态快照 (走了没换图)
var _deps_cache := {}
var _t0 := 0.0
var _limit := 0.0
var steps := 0
var _came_by := ""
var _var_only := {}   # 候选键 → 连续「只改角色变量」的次数
var _recent_flags := {}   # 旗标 → 第几次推进时新得到的 (只留最近 HOT_SPAN 次推进): 寻路先去依赖这些旗标的事件所在的图
const HOT_SPAN := 6
var _spend_only := {}  # 事件号 → 当时的依赖快照哈希: 某个选项只花了钱, 别的什么都没变 (例 材料大哥 5052 卖 DOMO 材料, 每个选项都是买):
## 依赖不变就整个事件不再触发; 它判断的旗标变了就放开 (例 雍城客栈 807: 平时只是住店花 300 文, 旗标 1619 后是主线「住店 → 第二天出事」)
const VAR_ONLY_MAX := 8   # 上一次让主角换了区域 / 地图的候选键
var _travels_since_progress := 0
var _effective := {}   # 真的起了作用的事件 (触发后有实质变化; 含同一次触发里连带执行的), 终点 events: 用它判断
var _exit_uses := {}   # 出口键 → 没推进期间用过几次 (两张图之间来回跑: 用超过 6 次就当这条路不通)
var progress := 0
var log_lines: Array = []
var _outside := {}
var _cur_zone := ""
var portals := {}      # 事件框键 → true: 触发后把主角送到同一张图的另一块区域
var links := {}        # 地图 → [[触发位置, 落点], ...]: 图内传送 (事件框 / 角色事件触发后换了区域), 跨图寻路也走它
var portal_used := {}  # "全局状态#区域#框键" → true: 本状态下从这个区域用过的传送框
var stale_maps := {}   # 地图 → 全局状态哈希: 到了那张图 (该状态下) 没有可试的候选   # 本轮挑候选时主角所在区域


func _ready() -> void:
	_t0 = Time.get_ticks_msec() / 1000.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--speed="):
			Engine.time_scale = float(a.substr(8))
		elif a.begins_with("--ap-limit="):
			_limit = float(a.substr(11))
	_run()


func _say(s: String) -> void:
	var line := "AP t=%.0f map=%d %s" % [Time.get_ticks_msec() / 1000.0 - _t0, field.map_id, s]
	print(line)
	log_lines.append(line)


# ---------------- 状态 ----------------

func _snapshot() -> Dictionary:
	var fl: Array = State.flags.keys().filter(func(f): return int(f) not in TEMP_FLAGS)
	fl.sort()
	var it := {}
	for k in State.items:
		if int(State.items[k]) != 0:
			it[int(k)] = int(State.items[k])
	return {"flags": fl, "vars": State.actor_vars.duplicate(), "items": it, "money": State.money,
		"trig": State.triggers_off.keys(), "map": field.map_id, "party": State.party.duplicate(), "zone": _zone()}


## 主角所在的可走区域 (泛洪结果里最小的格当代表): 迷宫里机关把人移到另一块区域时, 同样的旗标也算新状态
func _zone() -> String:
	if field.player == null:
		return ""
	_flood()
	var best := Vector3i(1 << 30, 1 << 30, 0)
	for k in _reach:
		if k.x < best.x or (k.x == best.x and k.y < best.y):
			best = k
	return "%d,%d" % [best.x, best.y]


func _diff(a: Dictionary, b: Dictionary) -> String:
	var out: Array = []
	for f in b.flags:
		if f not in a.flags:
			out.append("+F%d" % f)
	for f in a.flags:
		if f not in b.flags:
			out.append("-F%d" % f)
	for k in b.vars:
		if a.vars.get(k) != b.vars[k]:
			out.append("V%s=%s" % [k, b.vars[k]])
	for k in b.items:
		if a.items.get(k, 0) != b.items[k]:
			out.append("I%d:%d" % [k, b.items[k]])
	for k in a.items:
		if not b.items.has(k):
			out.append("I%d:0" % k)
	if a.money != b.money:
		out.append("$%d" % b.money)
	if a.trig.size() != b.trig.size():
		out.append("trig%d" % b.trig.size())
	if a.party != b.party:
		out.append("party%s" % str(b.party))
	if a.map != b.map:
		out.append("→map%d" % b.map)
	elif a.zone != b.zone:
		out.append("→区域%s" % b.zone)
	return " ".join(out)


## 实质变化: 旗标增减 / 队伍变化 / 某个道具变多 / 金钱增加 (花钱、用掉道具、只换图都不算)
func _substantive(a: Dictionary, b: Dictionary) -> bool:
	if a.flags != b.flags or a.party != b.party or b.money > a.money:
		return true
	for k in b.items:
		if int(b.items[k]) > int(a.items.get(k, 0)):
			return true
	return false


## 事件 (含 call_event) 判断的状态键
func _deps(eid: int, seen := {}) -> Array:
	if _deps_cache.has(eid) and seen.is_empty():
		return _deps_cache[eid]
	var out := {}
	seen[eid] = true
	for ins in field.event_code(eid):
		var op: String = ins[1]
		var a: Array = ins.slice(2)
		match op:
			"if_flag_goto", "if_not_flag_goto":
				out["F%d" % int(a[0])] = true
			"if_all_flags_goto", "if_any_flag_goto":
				for f in a[0]:
					out["F%d" % int(f)] = true
			"if_actor_var_ge_goto", "if_actor_var_eq_goto":
				out["V%d:%d" % [int(a[0]), int(a[1])]] = true
			"if_item_goto":
				out["I%d" % int(a[0])] = true
			"if_money_ge_goto":
				out["M"] = true
			"if_has_monster_goto", "if_monster_room_goto":
				out["MON"] = true
			"call_event":
				if not seen.has(int(a[0])):
					for k in _deps(int(a[0]), seen):
						out[k] = true
	for k in TEMP_FLAGS:
		out.erase("F%d" % k)
	var r := out.keys()
	r.sort()
	if seen.size() == 1:
		_deps_cache[eid] = r
	return r


func _val(k: String) -> Variant:
	match k[0]:
		"F":
			return State.test_flag(int(k.substr(1)))
		"V":
			return State.actor_var(int(k.substr(1).get_slice(":", 0)), int(k.get_slice(":", 1)))
		"I":
			return int(State.items.get(int(k.substr(1)), 0))
		"M":
			return State.money
	return State.ts_residents.size()


## 「只花钱」拉黑用的依赖快照: 不含金钱 (花了钱金额就变, 会马上又放开, 例 材料大哥 5052 判断「钱 ≥ 2000」)
func _spend_key(eid: int) -> int:
	var d := _dep_snap(eid)
	d.erase("M")
	return d.hash()


func _dep_snap(eid: int) -> Dictionary:
	var d := {}
	for k in _deps(eid):
		d[k] = _val(k)
	return d


## 事件里最多有几个选项 (%B)
## 选项组合数: 事件里每个选项框 (含 %B 的文本) 各自几项, 组合数 = 乘积 (上限 81)
## 组合序号 c 按混合进制拆成「第 k 个选项框选第几项」(第 0 个框是最低位); c = 0 = 全选第一项
func _menu_sizes(eid: int) -> Array:
	var out: Array = []
	for ins in field.event_code(eid):
		for x in ins:
			if x is String and x.count("%B") > 1:
				out.append(x.count("%B"))
	return out


func _n_choices(eid: int) -> int:
	var n := 1
	for m in _menu_sizes(eid):
		n *= int(m)
		if n >= 81:
			return 81
	return n


func _choice_seq(eid: int, c: int) -> Array:
	var seq: Array = []
	for m in _menu_sizes(eid):
		seq.append(c % int(m))
		c /= int(m)
	return seq


## 出口的落点: [[地图, 位置], ...] (change_map 参数 = 地图, x, y, z, 朝向, 视距)
func _landings(eid: int, seen := {}) -> Array:
	var out: Array = []
	seen[eid] = true
	for ins in field.event_code(eid):
		if ins[1] == "change_map":
			out.append([int(ins[2]), Vector3(float(ins[3]), float(ins[4]), float(ins[5]))])
		elif ins[1] == "call_event" and not seen.has(int(ins[2])):
			out += _landings(int(ins[2]), seen)
	return out


## 位置所在的连通区编号 (该图泛洪探索过的格子里, ±AREA_R 格内最近的那格); 没探索到 → −1
## (传送落点常在可走格边缘外一点, 例 崤山峡谷西口落点 (8201,21744) 离最近可走格四五格)
const AREA_R := 6
## 同一平面格可能有几层 (例 昊天界一重天C 升降台上层 y≈10100、下层 y≈8300): 每格存 [[连通区, 地面 y], ...],
## 只认高差 < COMP_DY 的那层 (y 是 NAN = 旧记忆没存高度, 哪层都认)
const COMP_DY := 400.0
const MERGE_DY := 100.0
func _comp_at(mid: int, pos: Vector3) -> int:
	var ex: Dictionary = _explored.get(mid, {})
	if ex.is_empty():
		return -1
	var c := Vector2i(roundi(pos.x / GRID), roundi(pos.z / GRID))
	var best := -1
	var bd := 1 << 30
	for dx in range(-AREA_R, AREA_R + 1):
		for dz in range(-AREA_R, AREA_R + 1):
			var d2 := dx * dx + dz * dz
			if d2 >= bd:
				continue
			for e in ex.get(c + Vector2i(dx, dz), []):
				if is_nan(float(e[1])) or absf(float(e[1]) - pos.y) < COMP_DY:
					bd = d2
					best = int(e[0])
	return best


## 落点以前在这张图上探索到过没有; 这张图还没探索记录 → 当探索过 (不改变旧行为)
func _explored_at(mid: int, pos: Vector3) -> bool:
	return _explored.get(mid, {}).is_empty() or _comp_at(mid, pos) >= 0


## 两个位置是否在同一块连通区; 有一个不知道 → 当同一块 (不改变旧行为)
func _same_area(mid: int, a: Variant, b: Variant) -> bool:
	if a == null or b == null:
		return true
	var ca := _comp_at(mid, a)
	var cb := _comp_at(mid, b)
	return ca < 0 or cb < 0 or ca == cb


func _dests(eid: int, seen := {}) -> Array:
	var out: Array = []
	seen[eid] = true
	for ins in field.event_code(eid):
		if ins[1] == "change_map":
			out.append(int(ins[2]))
		elif ins[1] == "call_event" and not seen.has(int(ins[2])):
			out += _dests(int(ins[2]), seen)
	return out


# ---------------- 可走范围 ----------------
## 从主角位置按 50 单位网格泛洪 (同 try_move 规则: 地面高差 ≤100、不撞阻挡盒和站着的角色);
## 其它启用中的事件框当墙 (走进去就会触发), 主角当前所在的框除外。结果 _reach = {Vector3i(格 x, 格 z, 层): 地面 y}
const GRID := 50.0
## 不进的地图: 13031 DOMO 工作室 = 原版开发组彩蛋房间 (楚国大地图), 和主线无关; 里面的拼图小游戏
## (战斗 299 / FIGTALK 298 的 reset_minigame / wait_minigame2_goto) 还没逆向实现, 进去会一直等小游戏结束
const AVOID_MAPS := [13031]
var _reach: Dictionary = {}
## 每张地图泛洪探索到过的格子 (地图号 → {Vector2i: true}): 同一张图的不同出口可能落在走不通的两块区域
## (例: 秦国大地图东西两半只经崤山峡谷前段连通 —— 峡谷 7136 回东半边, 7140 到西半边华山入口 7129 那边)
var _explored := {}   # 值 = 连通区编号 (每次泛洪一个新编号; 同一连通区的泛洪会把整块都改成新编号, 所以一块里编号一致)
var _comp_seq := 0
var _walls_dbg: Array = []
var passable := {}   # 事件框键 → {依赖快照哈希: true}: 触发过、状态没变、也没把主角推开 → 当时可以直接走过


func _box_aabb(b: Dictionary) -> AABB:
	var p: Array = b.pos
	var mn: Array = b.min
	var mx: Array = b.max
	return AABB(Vector3(p[0] + mn[0], p[1] + mn[1], p[2] + mn[2]), Vector3(mx[0] - mn[0], mx[1] - mn[1], mx[2] - mn[2]))


func _leader_at(g: Vector3) -> AABB:
	var b: Array = field.leader_box(g)
	return AABB(Vector3(b[0], b[1], b[2]), Vector3(b[3] - b[0], b[4] - b[1], b[5] - b[2]))


var _flood_nowalls := false


## 事件内容只有不改状态的指令 (例 多层迷宫楼梯上的 set_floor 框: 只换小地图楼层图) → 走过去什么都不变, 不当墙
const TRIVIAL_OPS := ["set_floor", "end", "nop", "script_begin", "script_end"]


## 镜头框: 只切镜头 / 把主角挪一点 / 开关别的镜头框 (例 云梦泽迷宫 7681–7698「迷宮鏡頭」9 对): 真人是直接走过去的,
## 剧情状态不变。以前它们每次都开关别的框 (trig 变化) 永远不算「可穿过」, 成了一道道墙, 机器人在两框之间来回踩
const CAMERA_OPS := ["crossfade_speed", "wait_crossfade", "camera_control", "camera_mode", "camera_target", "camera_angle",
	"camera_distance", "place_actor", "set_trigger"]
var _trivial_cache := {}


func _trivial(eid: int, seen := {}) -> bool:
	if _trivial_cache.has(eid):
		return _trivial_cache[eid]
	seen[eid] = true
	var ok := true
	for ins in field.event_code(eid):
		var op := str(ins[1])
		if op in TRIVIAL_OPS:
			continue
		if op == "place_actor" and int(ins[2]) == 1:   # 只挪主角
			continue
		if op == "set_trigger":   # 只开关别的镜头框
			var t := int(ins[2])
			if seen.has(t) or _trivial(t, seen):
				continue
			ok = false
			break
		if op in CAMERA_OPS and op != "place_actor":
			continue
		ok = false
		break
	_trivial_cache[eid] = ok
	return ok


const LAYER_DY := 20.0


func _flood(start_at: Variant = null) -> void:
	_reach.clear()
	var start: Vector3 = field.player.gpos if start_at == null else start_at
	var walls: Array = []
	var bi := 0
	_walls_dbg.clear()
	for b in field.map_info.get("boxes", []):
		var eid := int(b.event)
		var key := "B%d@%d:%d" % [eid, field.map_id, bi]
		bi += 1
		if State.trigger_enabled(eid) and field.event_code(eid).size():
			if _flood_nowalls or passable.get(key, {}).has(_dep_snap(eid).hash()) or OS.get_cmdline_user_args().has("--ap-nowalls") \
					or _trivial(eid):
				continue
			var bb := _box_aabb(b)
			if not bb.intersects(_leader_at(start)):
				walls.append(bb)
				_walls_dbg.append(key)
	# 起点就和主角重叠的角色 (会走动的 NPC 走到主角身上): 实际移动时两人会被弹开 (0x469790), 泛洪时不当墙
	var overlap: Array = []
	for a in field.actors.values():
		if a != field.player and field.box_overlap(field.actor_box(field.player), field.actor_box(a)):
			overlap.append(a)
	# 分层: 同一平面格可以有几层 (桥 / 多层迷宫: 泰山结界迷宫 x 12950–16600 有上下两层重叠), 高差 < LAYER_DY 算同一层;
	# 键 = Vector3i(格 x, 格 z, 层号)
	var layers := {}   # Vector2i → [y, ...]
	var k0 := Vector3i(roundi(start.x / GRID), roundi(start.z / GRID), 0)
	_reach[k0] = start.y
	layers[Vector2i(k0.x, k0.y)] = [start.y]
	var queue: Array = [k0]
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	while queue.size() and _reach.size() < 60000:
		var k: Vector3i = queue.pop_front()
		var y: float = _reach[k]
		for d in dirs:
			var n2: Vector2i = Vector2i(k.x, k.y) + d
			if n2.x < 0 or n2.y < 0:
				continue
			# 分 4 小步走 (同实际移动: 每步地面高差 ≤100, 连起来陡坡也走得下去)
			var g := Vector3(k.x * GRID, y, k.y * GRID)
			var ok := true
			var sub := 1
			while sub <= 4:
				var gs := Vector3(k.x * GRID + d.x * GRID * sub / 4.0, g.y, k.y * GRID + d.y * GRID * sub / 4.0)
				var fs: Variant = field.floor_at(gs, g.y)
				if fs == null:
					# 碰撞三角形之间没接上的窄缝 (例 昊天界一重天E 1507 平台和上坡之间, 宽约 11~13): 原版每帧只查落脚点
					# (0x468a89 一条竖直线段), 跑步一步 14 单位 (0x47c0bc) 从缝边跨得过去
					# 先贴到缝边 (换方向 / 走路 5 单位一步能挪到边上): 每 1 单位找最后一个有地面的点
					var dv := Vector3(d.x, 0, d.y)
					var e := g
					for t in range(1, int(GRID / 4.0) + 1):
						var fe: Variant = field.floor_at(g + dv * float(t), e.y)
						if fe == null:
							break
						e = g + dv * float(t)
						e.y = fe
					var jq: Vector3 = e + dv * float(field.RUN_SPEED)
					var fj: Variant = field.floor_at(jq, e.y)
					if fj == null:
						ok = false
						break
					jq.y = fj
					if field._blocked_by_box(jq):
						ok = false
						break
					g = jq
					var along: float = (g.x - k.x * GRID) * d.x + (g.z - k.y * GRID) * d.y
					while sub <= 4 and GRID * sub / 4.0 <= along:
						sub += 1
					continue
				gs.y = fs
				g = gs
				sub += 1
			if not ok:
				continue
			if field._blocked_by_box(g) or field.blocked_by_actor_at(g, overlap):
				continue
			var la := _leader_at(g)
			if walls.any(func(w): return (w as AABB).intersects(la)):
				continue
			var ys: Array = layers.get_or_add(n2, [])
			if ys.any(func(yy): return absf(float(yy) - g.y) < LAYER_DY):
				continue
			var n := Vector3i(n2.x, n2.y, ys.size())
			ys.append(g.y)
			_reach[n] = g.y
			queue.append(n)
	# 被事件框围住 (例: 从离宫回曲沃城, 出生点四周都是宫门守卫框 B151, 走进去守卫说句话就把人送到城里那一侧):
	# 可走范围几乎为零时, 当作事件框可通行再算一次, 让主角能走进框里触发它 (触发后换了区域就记成传送框)
	if _reach.size() < 4 and walls.size() and not _flood_nowalls:
		_flood_nowalls = true
		_flood(start_at)
		_flood_nowalls = false
	# 起点对齐到格子后正好落在孤立的一格 (例 周穆王陵墓机关 5708: 剧情把车芸放到 (11648, 8068), 对齐成 (11650, 8050)
	# 四周都走不出去, 可走范围 1 格就报卡住; 往后 130 就连着高台 3987 格): 在附近 3 格内另找起点 —— 从主角实际位置
	# 小步直线走得过去 (每步地面高差 ≤100、不撞阻挡) 的格, 取连出范围最大的
	if _reach.size() < 4 and start_at == null:
		var me: Vector3 = field.player.gpos
		var best: Dictionary = _reach.duplicate()
		for dx in range(-3, 4):
			for dz in range(-3, 4):
				if dx == 0 and dz == 0:
					continue
				var tgt := Vector3(roundi(me.x / GRID + dx) * GRID, me.y, roundi(me.z / GRID + dz) * GRID)
				var p := me
				var ok := true
				var dist := Vector2(tgt.x - me.x, tgt.z - me.z).length()
				var n := maxi(1, ceili(dist / 10.0))
				for st in range(1, n + 1):
					var q := me.lerp(tgt, float(st) / n)
					var fy: Variant = field.floor_at(q, p.y)
					if fy == null or absf(float(fy) - p.y) > 100.0:
						ok = false
						break
					q.y = fy
					if field._blocked_by_box(q):
						ok = false
						break
					p = q
				if not ok:
					continue
				_flood(p)
				if _reach.size() > best.size():
					best = _reach.duplicate()
		_reach = best


## 能走到的、离目标最近的格 (actor: 水平距离 ≤ 118; box: 主角包围盒碰到框) → 位置, 走不到返回 null
func _reach_spot(c: Dictionary) -> Variant:
	var best: Variant = null
	var bd := 1e9
	if c.kind == "I":
		# 道具: 没有位置要求就在原地用; 要求靠近某个角色 (XZ 距离 ≤ 给定值) 就找离它够近的可走格
		if (c.near as Array).is_empty():
			return field.player.gpos
		var na: FieldActor = field.actors.get(int(c.near[0]))
		if na == null or na.hidden:
			return null
		for k in _reach:
			var gi := Vector3(k.x * GRID, _reach[k], k.y * GRID)
			var di := Vector2(gi.x - na.gpos.x, gi.z - na.gpos.z).length()
			if di <= float(c.near[1]) - 10.0 and di < bd:
				bd = di
				best = gi
		return best
	if c.kind == "A":
		var ac := c.actor as FieldActor
		var ap: Vector3 = ac.gpos
		for k in _reach:
			var g := Vector3(k.x * GRID, _reach[k], k.y * GRID)
			var dd := Vector2(g.x - ap.x, g.z - ap.z).length()
			if dd >= bd or dd > 600.0:
				continue
			# 同空格调查 (field.is_investigate_hit, 0x47c770): 面向角色时盒子前推 50 后重叠, 或 3D 距离 ≤ 100
			if field.is_investigate_hit(ac, g, FieldActor.facing_of(ap - g)):
				bd = dd
				best = g
		# 格点 (50 一格) 都差一点够不着: 角色站在可走区域边缘外 (例 霍山结界迷宫的飞行平台 5705–5707, 停在楼层边上、
		# 包围盒 ±140, 最近的格离中心 222, 前推 50 的探测框差几个单位碰不到), 真人会贴着边走过去 —— 从近处的格朝角色
		# 小步 (5) 往前挪, 每步照实际移动查地面 (高差 ≤ 100) 和阻挡, 到能调查为止
		if best == null:
			for k in _reach:
				var g := Vector3(k.x * GRID, _reach[k], k.y * GRID)
				var dd := Vector2(g.x - ap.x, g.z - ap.z).length()
				if dd >= bd + GRID * 3 or dd > 600.0:
					continue
				var dir := Vector3(ap.x - g.x, 0, ap.z - g.z).normalized()
				var p := g
				for st in 30:
					var q := p + dir * 5.0
					var fy: Variant = field.floor_at(q, p.y)
					if fy == null or absf(float(fy) - p.y) > 100.0:
						break
					q.y = fy
					if field._blocked_by_box(q) or field.blocked_by_actor_at(q):
						break
					p = q
					if field.is_investigate_hit(ac, p, FieldActor.facing_of(ap - p)):
						var d2 := Vector2(p.x - ap.x, p.z - ap.z).length()
						if d2 < bd:
							bd = d2
							best = p
						break
	else:
		var bb := _box_aabb(c.box)
		var cen := bb.get_center()
		for k in _reach:
			var g2 := Vector3(k.x * GRID, _reach[k], k.y * GRID)
			# 目标框本身被当成墙排除了: 找框外紧邻的格, 再往框里迈一步
			var dd2 := Vector2(g2.x - cen.x, g2.z - cen.z).length()
			if dd2 < bd and _leader_at(g2).grow(GRID * 1.5).intersects(bb):
				bd = dd2
				best = g2
		if best != null:
			var b3: Vector3 = best
			var inside := Vector3(clampf(cen.x, b3.x - GRID * 1.5, b3.x + GRID * 1.5), b3.y, clampf(cen.z, b3.z - GRID * 1.5, b3.z + GRID * 1.5))
			var fy: Variant = field.floor_at(inside, b3.y)
			if fy != null:
				inside.y = fy
			best = inside
	return best


# ---------------- 候选 ----------------

## [{key, eid, kind: "A"/"B", node 或 box, dests, spot}] (只要走得到的)
func _candidates() -> Array:
	_flood()
	var ex: Dictionary = _explored.get_or_add(field.map_id, {})
	_comp_seq += 1
	# 和以前的连通区重叠 = 连通: 那些区整块并进新编号 (只并一部分会让同一块地有两个编号, 例 站在 NPC 中间
	# 泛洪只得到一小块 (角色算墙), 百里宅里百里奚身边那几格被改成另一个编号, 从门口落点看就成了「到不了」)
	# 只和同一层 (高差 < MERGE_DY) 的格子算重叠
	var olds := {}
	for k in _reach:
		for e in ex.get(Vector2i(k.x, k.y), []):
			if is_nan(float(e[1])) or absf(float(e[1]) - float(_reach[k])) < MERGE_DY:
				olds[int(e[0])] = true
	if olds.size():
		for v2 in ex:
			for e in ex[v2]:
				if olds.has(int(e[0])):
					e[0] = _comp_seq
	for k in _reach:
		var es: Array = ex.get_or_add(Vector2i(k.x, k.y), [])
		var y := float(_reach[k])
		var hit := false
		for e in es:
			if int(e[0]) == _comp_seq and (is_nan(float(e[1])) or absf(float(e[1]) - y) < MERGE_DY):
				e[1] = y
				hit = true
				break
		if not hit:
			es.append([_comp_seq, y])
	var out: Array = []
	for c in _candidates_all():
		var sp: Variant = _reach_spot(c)
		if sp != null:
			c.spot = sp
			out.append(c)
	return out


func _candidates_all() -> Array:
	var out: Array = []
	var avoid := func(eid: int) -> bool: return _dests(eid).any(func(d): return int(d) in AVOID_MAPS)
	for a in field.actors.values():
		if a == field.player or not field._can_talk(a) or field.event_code(a.event_id).is_empty():
			continue
		out.append({"key": "A%d:%d" % [a.id, a.event_id], "eid": a.event_id, "kind": "A", "actor": a,
			"dests": _dests(a.event_id)})
	var i := 0
	for b in field.map_info.get("boxes", []):
		var eid := int(b.event)
		if State.trigger_enabled(eid) and field.event_code(eid).size() and not avoid.call(eid) and not _trivial(eid):
			out.append({"key": "B%d@%d:%d" % [eid, field.map_id, i], "eid": eid, "kind": "B", "box": b, "dests": _dests(eid)})
		i += 1
	# 道具菜单里能启动事件的道具 (同 main_menu: 玉蝉 5526–5533 需旗标 1037 → 事件 道具号 − 5001; 土地神符 3902 → 本图 talisman_event)
	var uses: Array = []
	if State.test_flag(1037):
		for iid in range(5526, 5534):
			if State.item_count(iid) > 0:
				uses.append([iid, iid - 5001])
	if State.item_count(3902) > 0 and field.map_info.get("talisman_event") != null:
		uses.append([3902, int(field.map_info.talisman_event)])
	for u in uses:
		if field.event_code(int(u[1])).size():
			out.append({"key": "I%d@%d" % [u[0], field.map_id], "eid": int(u[1]), "kind": "I", "item": int(u[0]),
				"near": _near_actor(int(u[1])), "dests": _dests(int(u[1]))})
	return out


## 事件开头要求站在哪个角色旁边 (第一条 if_near_actor_goto 的角色, 距离): 用道具前先走过去
func _near_actor(eid: int) -> Array:
	for ins in field.event_code(eid):
		if str(ins[1]) == "if_near_actor_goto":
			return [int(ins[2]), float(ins[3])]
	return []


## 这个候选还有没试过的组合 (依赖变了, 或还有没选过的选项) → 返回选项号, 否则 -1
func _fresh_choice(c: Dictionary, zone_aware := true) -> int:
	if _spend_only.get(int(c.eid)) == _spend_key(int(c.eid)):
		return -1
	var snap := _dep_snap(int(c.eid))
	var h: Variant = snap.hash()   # 不分区域
	if zone_aware:
		snap["@zone"] = _cur_zone
		h = snap.hash()
	for ch in _n_choices(int(c.eid)):
		var k := "%s#%d" % [c.key, ch]
		if not tried.has(k) or not tried[k].has(h):
			return ch
	return -1


## 远处地图的候选是否还有可试的 (用 maps.json 的角色 / 事件框 + State 覆盖, 近似)
func _gstate() -> int:
	var s := _snapshot_lite()
	return s.hash()


func _snapshot_lite() -> Dictionary:
	var fl: Array = State.flags.keys().filter(func(f): return int(f) not in TEMP_FLAGS)
	fl.sort()
	return {"flags": fl, "vars": State.actor_vars, "items": State.items, "trig": State.triggers_off.keys(), "party": State.party}


## from = 到达这张图的落点 (给了就只看和落点同一连通区的候选, 见 _same_area)
## hot = 只算依赖「最近新得到的旗标」的候选 (剧情刚解锁的事件, 例 百里奚 708 给 1609 → 陈宝祭庙外 751)
func _map_fresh(mid: int, from: Variant = null, hot := false) -> bool:
	if stale_maps.get(mid) == _gstate():
		return false
	var mi: Dictionary = field.maps.get(str(mid), {})
	var i := -1
	for b in mi.get("boxes", []):
		i += 1
		var eid := int(b.event)
		if not _same_area(mid, from, Vector3(b.pos[0], b.pos[1], b.pos[2])):
			continue
		if State.trigger_enabled(eid) and field.event_code(eid).size() and _dests(eid).is_empty() and (not hot or _is_hot(eid)):
			if _fresh_choice({"key": "B%d@%d:%d" % [eid, mid, i], "eid": eid}, false) >= 0:
				return true
	for r in mi.get("npcs", []):
		var aid := int(r.actor)
		var s: Dictionary = State.actors.get(aid, {})
		if s.has("map") and int(s.map) != mid:
			continue
		var rp: Array = s.get("pos", r.get("pos", []))
		if rp.size() >= 3 and not _same_area(mid, from, Vector3(rp[0], rp[1], rp[2])):
			continue
		if bool(s.get("hidden", int(r.get("flags", 0)) & 0x1)) or not (int(r.get("flags", 0)) & 0x6c00):
			continue
		var eid2 := int(s.get("event", r.event))
		if eid2 > 0 and field.event_code(eid2).size() and (not hot or _is_hot(eid2)):
			if _fresh_choice({"key": "A%d:%d" % [aid, eid2], "eid": eid2}, false) >= 0:
				return true
	return false


## 出口图上最近的「还有可试候选」的地图 → 当前地图上该走的出口候选
## 3 = 从没进过的地图 (大地图也算: 剧情往前走一般是去新地方, 例 楚国驿站 → 楚国大地图 → 郢都);
## 2 = 进过、还有可试候选的普通地图; 1 = 同样的大地图 —— 以前没有 3, 楚国驿站坐驿车回晋国驿站 (还有没试完的
## 材料老爹, 2 分) 压过了走出驿站去楚国大地图 (1 分), 一路倒退回晋国卡住
func _exit_score(c: Dictionary) -> int:
	var best := 0
	# 目的地里的「当前这张图」不算 (例 春之岛回程传送 5610 按旗标分两支: 进岛 → 12623、离岛 → 12628; 在岛上时
	# 把 12623 算进去, 它就因为「本岛还有没试的」得 2 分, 压过拿节令石 757 (只去 12628), 没拿石头就走了)
	var dests: Array = c.get("dests", []).filter(func(d): return int(d) != field.map_id)
	for d in dests:
		if not _outside.has(int(d)):
			return 3
	for l in _landings(int(c.eid)):   # 去过的图, 但落点在没探索过的另一块区域 → 同没去过
		if int(l[0]) != field.map_id and not _explored_at(int(l[0]), l[1]):
			return 3
	for d in dests:
		var world := int(field.maps.get(str(d), {}).get("flags", 0)) & 0x80 != 0
		if _map_fresh(int(d)):
			best = maxi(best, 1 if world else 2)
	return best


## 事件依赖最近新得到的旗标
func _is_hot(eid: int) -> bool:
	for k in _deps(eid):
		if str(k).begins_with("F") and _recent_flags.has(int(str(k).substr(1))):
			return true
	return false


func _route(cands: Array) -> Variant:
	# 先找刚被剧情解锁的事件所在的图 (以前只找最近的「还有没试过的」图, 第六段拿到 1609 后被驿站 / 别国的支线吸走, 没去陈宝祭庙)
	if not _recent_flags.is_empty():
		var h: Variant = _route_bfs(cands, true, true)
		if h != null:
			return h
	# 再只找普通地图; 大地图 (标志 0x80) 上总有些看起来没试过的地点, 当目的地会一直被它吸走, 只当通道
	var r: Variant = _route_bfs(cands, false)
	return r if r != null else _route_bfs(cands, true)


## 出口在当前状态下走不通: 同一张图上挂同一个事件的框算同一个出口 (事件一样, 走不通的分支也一样;
## 例 秦宫前大道 704 挂在 3 / 4 / 5 号框, 旗标 1609 时只是守卫挡路 (L_0d60), 3 号试过后 4 / 5 号不能再当去 13030 / 12430 的路)
func _exit_blocked(key: String) -> bool:
	var g := _gstate()
	if blocked_exits.get(key) == g:
		return true
	var pre := key.get_slice(":", 0) + ":"
	for k in blocked_exits:
		if str(k).begins_with(pre) and blocked_exits[k] == g:
			return true
	return false


func _route_bfs(cands: Array, allow_world: bool, hot := false) -> Variant:
	# 节点 = (地图, 落点所在连通区): 同一张图走不通的两块要分开算 (例 秦国大地图东西两半只经崤山峡谷连通,
	# 峡谷 7136 回东半边、7140 到西半边的陈宝祭庙入口; 以前按地图算, 选了第一个通往 12004 的 7136)
	var queue: Array = []   # [地图, 落点 (Vector3 或 null), 第一步出口候选]
	var seen := {_node_key(field.map_id, field.player.gpos): true}
	for c in cands:
		if c.kind != "B" or c.dests.is_empty() or _exit_blocked(c.key):
			continue
		for l in _landings(int(c.eid)):
			queue.append([int(l[0]), l[1], c])
	# 本图的图内传送当第一步 (例 在昊天界一重天C 下层, 要坐升降台 1519 回上层才走得到去第二岛的出口)
	for c in cands:
		for l in links.get(field.map_id, []):
			if str(l[2]) == c.key and not _exit_blocked(c.key):
				queue.append([field.map_id, l[1], c])
	while queue.size():
		var e: Array = queue.pop_front()
		var m: int = e[0]
		var nk := _node_key(m, e[1])
		if seen.has(nk):
			continue
		seen[nk] = true
		var is_world := int(field.maps.get(str(m), {}).get("flags", 0)) & 0x80 != 0
		if (allow_world or not is_world) and _map_fresh(m, e[1], hot):
			return e[2]
		var mi: Dictionary = field.maps.get(str(m), {})
		var bi := -1
		for b in mi.get("boxes", []):
			bi += 1
			var eid := int(b.event)
			if _exit_blocked("B%d@%d:%d" % [eid, m, bi]) or not State.trigger_enabled(eid):
				continue
			if not _same_area(m, e[1], Vector3(b.pos[0], b.pos[1], b.pos[2])):
				continue
			for l in _landings(eid):
				if not seen.has(_node_key(int(l[0]), l[1])):
					queue.append([int(l[0]), l[1], e[2]])
		# 图内传送 (例 昊天界一重天C 升降台 1518 / 1519 连通上下两层): 从这块区域能用的, 落点那块也算到得了
		for l in links.get(m, []):
			if _same_area(m, e[1], l[0]) and not seen.has(_node_key(m, l[1])):
				queue.append([m, l[1], e[2]])
	return null


## 寻路节点键: 地图 + 连通区 (不知道连通区的只按地图)
func _node_key(m: int, pos: Variant) -> String:
	var c := _comp_at(m, pos) if pos != null else -1
	return "%d:%d" % [m, c]


# ---------------- 主循环 ----------------

func _idle() -> bool:
	if field.busy or not field.dialog.windows.is_empty() or field.player == null:
		return false
	for ch in field.get_children():
		if ch is Battle or ch is Loading or ch is MainMenu or ch is Shop:
			return false
	return true


## 看门狗: 连续 WATCHDOG 秒 (真实时间) 不空闲 = 卡在事件 / 对话 / 战斗里, 打印当时在等什么后按 STUCK 结束
const WATCHDOG := 120.0
var _busy_since := -1.0
var _was_fighting := false


func _process(_dt: float) -> void:
	if field == null:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if _idle():
		_busy_since = -1.0
		return
	# 战斗单独计时 (上限 WATCHDOG×5): 战斗结束后事件那边重新计时, 否则连输重打几场后, 两场之间那一帧没有战斗节点就会误报
	var fighting := field.get_children().any(func(c): return c is Battle)
	if fighting != _was_fighting:
		_was_fighting = fighting
		if _busy_since != INF:
			_busy_since = now
	if _busy_since < 0:
		_busy_since = now
	elif now - _busy_since > (WATCHDOG * 5 if fighting else WATCHDOG):
		_busy_since = INF
		_say("WATCHDOG %d 秒不空闲: busy=%s 事件=%s" % [int(WATCHDOG), field.busy,
			str(field.vms.map(func(v): return "ev%d 执行中=%s 等待=%s" % [v.eid, str(v.code[v.pc - 1]) if v.pc > 0 else "-", v.wait_info]))])
		_say("  time_scale=%s paused=%s field_in_tree=%s 帧时间=%.4f" % [Engine.time_scale, get_tree().paused, field.is_inside_tree(), field.get_process_delta_time()])
		for k in field.dialog.windows:
			var w = field.dialog.windows[k]
			_say("  对话框 %s: %s 选项=%s" % [str(k), str(w.pages).left(200), str(w.options)])
		for ch in field.get_children():
			if ch is Battle or ch is Loading or ch is MainMenu or ch is Shop:
				_say("  打开的界面 %s" % ch.get_class() + " " + str(ch.name))
		_finish("STUCK (看门狗)")


func _wait_idle() -> void:
	var calm := 0.0
	while calm < 0.4:
		await get_tree().process_frame
		calm = calm + get_process_delta_time() / maxf(Engine.time_scale, 0.01) if _idle() else 0.0


func _run() -> void:
	await get_tree().create_timer(2.0).timeout
	await _wait_idle()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ap-probe="):   # 调试: 泛洪后报告离 (x,z) 最近的可走格
			var xz := a.substr(11).split(",")
			var tgt := Vector2(float(xz[0]), float(xz[1]))
			for a2 in OS.get_cmdline_user_args():   # --ap-probe-from=x,y,z: 先把主角放到这里再泛洪
				if a2.begins_with("--ap-probe-from="):
					var p3 := a2.substr(16).split(",")
					field.player.set_game_pos(Vector3(float(p3[0]), float(p3[1]), float(p3[2])))
			_flood()
			var best := Vector3i.ZERO
			var bd := 1e9
			for k in _reach:
				var dd := Vector2(k.x * GRID, k.y * GRID).distance_to(tgt)
				if xz.size() > 2 and absf(_reach[k] - float(xz[2])) > 150.0:   # 给了第三个数 = 只看这个高度附近的层
					continue
				if dd < bd:
					bd = dd
					best = k
			for a3 in OS.get_cmdline_user_args():   # --ap-probe-line=x1,z1,x2,z2,y: 沿线每 25 打印地面高度 / 是否被阻挡盒挡住
				if a3.begins_with("--ap-probe-line="):
					var v := Array(a3.substr(16).split(",")).map(func(t): return float(t))
					var py: float = v[4]
					for i in int(Vector2(v[2] - v[0], v[3] - v[1]).length() / 25.0) + 1:
						var t := float(i) * 25.0 / Vector2(v[2] - v[0], v[3] - v[1]).length()
						var q := Vector3(lerpf(v[0], v[2], t), py, lerpf(v[1], v[3], t))
						var fy: Variant = field.floor_at(q, py, 400.0)
						if fy != null:
							py = fy
							q.y = fy
						var sp3: PhysicsDirectSpaceState3D = field._world.get_world_3d().direct_space_state
						var rq := PhysicsRayQueryParameters3D.create(field.to_world(Vector3(q.x, py + 300.0, q.z)), field.to_world(Vector3(q.x, py - 3000.0, q.z)), 2)
						rq.hit_back_faces = true
						var vh: Dictionary = sp3.intersect_ray(rq)
						var who: Array = field.actors.values().filter(func(ac): return ac != field.player and not ac.hidden and field.blocked_by_actor_at(q, []) and field.box_overlap(field.actor_box(field.player, q - field.player.gpos), field.actor_box(ac))).map(func(ac): return ac.id)
						print("LINE %d,%d floor=%s blocked=%s actor=%s visual=%s" % [int(q.x), int(q.z), str(fy), field._blocked_by_box(q) if fy != null else "-", str(who),
							str(field.to_game(vh.position).y) if not vh.is_empty() else "-"])
			for a3 in OS.get_cmdline_user_args():   # --ap-probe-dump=文件: 可走格写成 [[x, z, y], ...] (调试连通性)
				if a3.begins_with("--ap-probe-dump="):
					var fo := FileAccess.open(a3.substr(16), FileAccess.WRITE)
					fo.store_string(JSON.stringify(_reach.keys().map(func(k): return [k.x * GRID, k.y * GRID, _reach[k]])))
			print("PROBE cells=%d nearest=%s y=%.0f dist=%.0f walls=%s" % [_reach.size(), Vector2(best.x, best.y) * GRID, _reach.get(best, NAN), bd, str(_walls_dbg)])
			get_tree().quit()
			return
	seen_states[_snapshot().hash()] = true
	_load_mem()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ap-debug-fresh="):
			var dm := int(a.substr(17))
			_say("DEBUG map %d fresh=%s stale=%s" % [dm, _map_fresh(dm), stale_maps.get(dm) == _gstate()])
			for r in field.maps.get(str(dm), {}).get("npcs", []):
				var s2: Dictionary = State.actors.get(int(r.actor), {})
				_say("  npc %d flags=0x%x ev=%s state=%s" % [int(r.actor), int(r.get("flags", 0)), str(r.event), str(s2)])
	while true:
		await _wait_idle()
		if _travels_since_progress > 40:   # 来回跑图 40 次都没推进: 当成卡住
			_finish("STUCK (来回跑图没有推进)")
			return
		if _limit > 0 and Time.get_ticks_msec() / 1000.0 - _t0 > _limit:
			_finish("LIMIT")
			return
		# 终点: 默认 = 序章结束 (到达第二段的曲沃: 曲沃城 12203 / 曲沃民房、店 12406–12411 / 离宫 13001、13002、12616);
		# --ap-goal=flag:旗标 (例 第一章 = flag:7305 取得盛放龟甲之木盒) / map:地图
		if _goal_reached():
			_finish("DONE (%s)" % _goal_text())
			return
		if not _outside.has(field.map_id):
			_outside[field.map_id] = true
			_say("进入地图 %s" % str(field.maps.get(str(field.map_id), {}).get("name", "")))
		_cur_zone = _zone()
		var cands := _candidates()
		# 刚把主角带到这块区域的候选 (浮台 / 传送) 放到最后试, 免得刚坐过来就坐回去 (泰山结界迷宫三段浮台要依次换乘)
		cands.sort_custom(func(x, y): return int(x.key == _came_by) < int(y.key == _came_by))
		cands = cands.filter(func(c): return int(_var_only.get(c.key, 0)) < VAR_ONLY_MAX)
		# 先试不换图的, 再试出口
		var pick: Dictionary = {}
		var choice := -1
		# 出口按「通往还有东西可试的普通地图」优先排 (例: 北狄聚落先进北狄室内找酋长, 而不是先出大地图)
		var exits_sorted := cands.duplicate()
		# 同分时没执行过的事件优先 (昆仑界春之岛: 节令石 757 拿到后会把队伍送回一重天, 和回程传送 5610 一样算「去 12628 的出口」;
		# 以前先挑了刚用过的 5610, 没拿节令石就走了, 这座岛之后再也不回来), 再是地图上的出口 (B) 先于找人换图
		# (A, 例 驿夫收钱送去别国驿站): 剧情往前一般是走出去
		# 「去过的图上没探索过的落点」(3 分里不是没去过的图的那种) 和普通 2 分同级, 同级里没执行过的事件优先, 再看落点新不新:
		# 例 春之岛回程传送 5610 落在一重天没去过的外圈 (18390, 15015), 3 分压过拿节令石 757 (2 分, 没执行过), 没拿石头就走
		var major := func(c: Dictionary) -> int:
			var sc := _exit_score(c)
			if sc == 3 and c.get("dests", []).all(func(d): return int(d) == field.map_id or _outside.has(int(d))):
				return 2
			return sc
		exits_sorted.sort_custom(func(x, y):
			var mx: int = major.call(x)
			var my: int = major.call(y)
			if mx != my:
				return mx > my
			var nx: bool = not field.events_run.has(int(x.eid))
			var ny: bool = not field.events_run.has(int(y.eid))
			if nx != ny:
				return nx
			var sx := _exit_score(x)
			var sy := _exit_score(y)
			if sx != sy:
				return sx > sy
			return x.kind == "B" and y.kind != "B")
		if "--ap-debug-exits" in OS.get_cmdline_user_args():
			var all_keys := _candidates_all().filter(func(c): return c.dests.size() > 0).map(func(c): return c.key)
			_say("DEBUG 出口候选(可走到) %s / 全部 %s" % [str(exits_sorted.filter(func(c): return c.dests.size() > 0).map(
				func(c): return "%s→%s 分%d 新%d" % [c.key, str(c.dests), _exit_score(c), _fresh_choice(c)])), str(all_keys)])
		# 第 3 轮才试刚把主角带来的那个 (浮台): 霍山结界迷宫的飞行平台 5705–5707 每坐一次就翻转自己的旗标 (6027–6029),
		# 坐回去永远算「新状态」, 排在出口前面会在两块区域间来回坐, 永远轮不到大殿入口 611
		var travel := false
		for pass_i in 3:
			var pass_exit := pass_i == 1
			# 本图没有可试的了: 剧情刚解锁的事件 (依赖最近新得到的旗标) 在别的图 → 先往那边走, 不试别的没走过的出口
			# (第六段 百里奚 708 给 1609 后, 先试了崤山峡谷 / 华山的出口, 一路被支线带去别国, 没去陈宝祭庙 751)
			if pass_exit and not _recent_flags.is_empty():
				# 本图已没有可试的 (第 1 轮没挑到): 先记成「这个状态下没东西」再寻路, 不然别处寻路又会把这里当成剧情刚解锁的图
				# (第八段雍城客栈 807 后: 客栈老板 807 依赖新旗标 1620, 在雍城算「最近的热门图」, 客栈 ↔ 雍城来回 7 趟, 轮不到百里宅 852)
				stale_maps[field.map_id] = _gstate()
				var hr: Variant = _route_bfs(cands, true, true)
				if hr != null:
					pick = hr
					choice = 0
					travel = true
					break
			for c in (exits_sorted if pass_exit else cands):
				if (c.dests.size() > 0) != pass_exit or (pass_i == 0 and c.key == _came_by and _came_by != ""):
					continue
				var ch := _fresh_choice(c)
				if ch >= 0:
					pick = c
					choice = ch
					break
			if pick.size():
				break
		if pick.is_empty():
			# 本图别的区域还有没试过的候选 → 先用图内传送框换区域
			var pt: Variant = _portal(cands)
			if pt != null:
				await _trigger(pt, 0, true)
				continue
			stale_maps[field.map_id] = _gstate()
			var r: Variant = _route(cands)
			if r == null:
				_finish("STUCK")
				return
			pick = r
			choice = 0
			travel = true
		await _trigger(pick, choice, travel)


func _portal(cands: Array) -> Variant:
	var reach_keys := {}
	for c in cands:
		reach_keys[c.key] = true
	var others: Array = []
	for c in _candidates_all():
		# 会换图的事件框一般是出口, 不算; 但从没执行过的剧情事件 (例 太恒山山顶 217, 演完换到齐国大地图) 要算, 否则不会再走传送框去那块区域
		var story: bool = c.kind == "B" and not c.dests.is_empty() and not field.events_run.has(int(c.eid)) and int(c.eid) < 7000
		if not reach_keys.has(c.key) and (c.kind == "A" or c.dests.is_empty() or story) and _fresh_choice(c, false) >= 0:
			others.append(c.key)
	var pk: Array = cands.filter(func(c): return portals.has(c.key)).map(func(c): return c.key)
	_say("区域内无可试候选; 别处待试 %s; 可用传送框 %s" % [str(others.slice(0, 6)), str(pk)])
	for pkey in passable:
		if str(pkey).contains("@%d:" % field.map_id):
			_say("  可穿过 %s %s 当前依赖哈希 %d" % [pkey, str(passable[pkey].keys()), _dep_snap(int(str(pkey).substr(1).get_slice("@", 0))).hash()])
	for a in field.actors.values():
		if a != field.player and not a.hidden and others.has("A%d:%d" % [a.id, a.event_id]):
			var bd := 1e9
			var bk := Vector3i.ZERO
			for k in _reach:
				var dd := Vector2(k.x * GRID - a.gpos.x, k.y * GRID - a.gpos.z).length()
				if dd < bd:
					bd = dd
					bk = k
			_say("  角色 %d 在 %s, 最近可走格 %s y=%.0f 距 %.0f; 可走格数 %d" % [a.id, a.gpos.round(), Vector2(bk.x, bk.y) * GRID, _reach.get(bk, 0.0), bd, _reach.size()])
	_say("  墙: %s" % str(_walls_dbg))
	if others.is_empty():
		return null
	var g := _gstate()
	for c in cands:
		if portals.has(c.key):
			var k := "%d#%s#%s" % [g, _cur_zone, c.key]
			if not portal_used.has(k):
				portal_used[k] = true
				return c
	return null


func _trigger(c: Dictionary, choice: int, travel: bool) -> void:
	# 先瞬移到触发位置, 再记「之前」的状态 (瞬移本身不算区域变化)
	var pos0: Vector3 = field.player.gpos
	field.player.set_game_pos(c.spot)
	var before := _snapshot()
	var ran0: Dictionary = field.events_run.duplicate()
	var dsnap := _dep_snap(int(c.eid))
	var dsnap_nz := dsnap.hash()
	dsnap["@zone"] = _cur_zone
	field.dialog.auto_choice = choice
	field.dialog.auto_seq = _choice_seq(int(c.eid), choice)
	field.dialog._auto_menu_i = 0
	steps += 1
	var where := ""
	if c.kind == "I":
		where = "用道具 %d" % int(c.item)
		field.player.set_game_pos(c.spot)
		if int(c.item) == 3902:
			State.give_item(3902, -1)   # 土地神符由菜单扣 (玉蝉由脚本 take_item 扣)
		field.run_event(int(c.eid), field.player.id)
	elif c.kind == "A":
		var a: FieldActor = c.actor
		where = "%s(%d)" % [field.person_name(a.id) if a.id < 0xff00 else "", a.id]
		field.player.set_game_pos(c.spot)
		field.player.face_point(a.gpos)
		field._start_npc_event(a)
	else:
		var sp: Vector3 = c.spot
		where = "box@%d,%d,%d" % [int(sp.x), int(sp.y), int(sp.z)]
		field.player.set_game_pos(sp)
		field.run_event(int(c.eid), 0xff01)
	await _wait_idle()
	field.dialog.auto_choice = 0
	field.dialog.auto_seq = []
	# 和角色说完话、事件没把主角移走: 瞬移回说话前的位置 —— 对话点挨着角色, 会走动的 NPC 围过来就会把主角夹住 (真人是走过去的, 不会站进去)
	if c.kind == "A" and field.map_id == int(before.map) and field.player.gpos.distance_to(c.spot) < 30.0:
		field.player.set_game_pos(pos0)
	var after := _snapshot()
	if _substantive(before, after):
		for e in field.events_run:
			if not ran0.has(e):
				_effective[e] = true
		_effective[int(c.eid)] = true
	if after.map != before.map or after.zone != before.zone:
		_came_by = c.key
	# 角色事件也算 (例 昊天界一重天C 升降台 1518 下 / 1519 上: 坐了 1519 回上层后要能再坐 1518 下去触发 1503)
	if c.kind in ["B", "A"] and after.map == before.map and after.zone != before.zone:
		portals[c.key] = true
		var lk: Array = links.get_or_add(field.map_id, [])
		if not lk.any(func(l): return (l[0] as Vector3).distance_to(c.spot) < 1.0):
			lk.append([c.spot, field.player.gpos, c.key])
	if c.kind == "B" and after.map == before.map and _diff(before, after) == "" \
			and field.player.gpos.distance_to(c.spot) < 30.0:
		passable.get_or_add(c.key, {})[dsnap_nz] = true
	elif c.kind == "B" and after.map == before.map:
		_say("  非穿过 %s diff=[%s] 移动=%.0f" % [c.key, _diff(before, after), field.player.gpos.distance_to(c.spot)])
	var d := _diff(before, after)
	if travel:
		if after.map == before.map and after.zone == before.zone:
			blocked_exits[c.key] = _gstate()
		_travels_since_progress += 1
		_exit_uses[c.key] = int(_exit_uses.get(c.key, 0)) + 1
		if int(_exit_uses[c.key]) > 6:
			blocked_exits[c.key] = _gstate()
		_say("TRAVEL %s ev%d %s %s" % [c.key, c.eid, where, d])
		return
	tried.get_or_add("%s#%d" % [c.key, choice], {})[dsnap.hash()] = true
	tried["%s#%d" % [c.key, choice]][dsnap_nz] = true
	# 换了图但没有实质变化 (旗标 / 队伍 / 得到道具 / 金钱增加), 例 驿夫收钱送到别国驿站: 算跑图, 不算剧情推进
	if after.map != before.map and not _substantive(before, after):
		_travels_since_progress += 1
		_exit_uses[c.key] = int(_exit_uses.get(c.key, 0)) + 1
		seen_states[after.hash()] = true
		_say("TRAVEL %s ev%d ch%d %s %s (换图无剧情变化)" % [c.key, c.eid, choice, where, d])
		return
	# 只花了钱: 不算推进 (钱留给剧情要买的东西, 例 木匠 2317 浮空奇石 500 文)
	if d != "" and Array(d.split(" ")).all(func(t): return t.begins_with("$")) and after.money < before.money:
		_spend_only[int(c.eid)] = _spend_key(int(c.eid))
		_say("spend %s ev%d ch%d %s %s (只花了钱, 依赖不变就不再触发)" % [c.key, c.eid, choice, where, d])
		return
	var h := after.hash()
	var new_state := not seen_states.has(h)
	seen_states[h] = true
	if d != "" and not new_state:
		_say("loop %s ev%d ch%d %s %s (回到出现过的状态)" % [c.key, c.eid, choice, where, d])
	elif d != "":
		# 只改了角色变量 (计数器, 例 临淄城抓公鸡 2329 / 2331: 公鸡永远逃掉, 计数一直涨) 的不算推进;
		# 同一候选这样连着 VAR_ONLY_MAX 次就先不试, 直到别处有实质推进
		var var_only: bool = Array(d.split(" ")).all(func(t): return t.begins_with("V") or t.begins_with("trig") or t.begins_with("→区域"))
		if var_only:
			_var_only[c.key] = int(_var_only.get(c.key, 0)) + 1
		else:
			_var_only.clear()
		progress += 1
		for f in after.flags:
			if f not in before.flags:
				_recent_flags[int(f)] = progress
		for f in _recent_flags.keys():
			if progress - int(_recent_flags[f]) >= HOT_SPAN:
				_recent_flags.erase(f)
		_travels_since_progress = 0
		_exit_uses.clear()
		_say("PROGRESS %s ev%d ch%d %s %s" % [c.key, c.eid, choice, where, d])
	else:
		_say("try %s ev%d ch%d %s (无变化)" % [c.key, c.eid, choice, where])


func _goal_reached() -> bool:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ap-goal=flag:"):
			return State.test_flag(int(a.substr(15)))
		if a.begins_with("--ap-goal=map:"):
			return field.map_id == int(a.substr(14))
		if a.begins_with("--ap-goal=event:"):   # 某个事件已执行
			return field.events_run.has(int(a.substr(16)))
		if a.begins_with("--ap-goal=events:"):   # 列表里任一事件真的起了作用 (下一段的全部剧情事件, 见 tools/autoplay_chapters.sh);
			# 只是执行过不算: 例 郢都触发框 651 条件 (旗标 1050) 不满足就直接结束, 以前被当成到了下一段
			for e in a.substr(17).split(","):
				if _effective.has(int(e)):
					return true
			return false
	return field.map_id in [12203, 12406, 12407, 12408, 12409, 12410, 12411, 13001, 13002, 12616]


func _goal_text() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ap-goal="):
			return "达到终点 %s, 地图 %s" % [a.substr(10), str(field.maps.get(str(field.map_id), {}).get("name", ""))]
	return "到达第二段地图 %s" % str(field.maps.get(str(field.map_id), {}).get("name", ""))


## 机器人自己的记忆 (去过哪些地图), 跟存档档位走: 下一段 --load 同一档位时接着用
## (不然从存档开始时所有地图都算「没去过」, 出口同分乱选, 例 楚国大地图上去了驿站而不是云梦泽)
func _mem_path(slot: int) -> String:
	return "user://ap_memory_%d.json" % slot


func _save_mem(slot: int) -> void:
	var f := FileAccess.open(_mem_path(slot), FileAccess.WRITE)
	if f:
		var ex := {}   # 探索过的格子按连通区存: 地图 → {连通区: [x, z, y, x, z, y, ...]}
		for mid in _explored:
			var by := {}
			for k in _explored[mid]:
				for e in _explored[mid][k]:
					(by.get_or_add(str(e[0]), []) as Array).append_array([k.x, k.y, null if is_nan(float(e[1])) else e[1]])
			ex[str(mid)] = by
		var lk := {}
		for mid in links:
			lk[str(mid)] = (links[mid] as Array).map(func(l): return [l[0].x, l[0].y, l[0].z, l[1].x, l[1].y, l[1].z, l[2]])
		f.store_string(JSON.stringify({"outside": _outside.keys(), "explored3": ex, "comp_seq": _comp_seq, "links": lk}))


func _load_mem() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--load="):
			var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(_mem_path(int(a.substr(7)))))
			if j is Dictionary:
				for mid in j.get("outside", []):
					_outside[int(mid)] = true
				for mid in j.get("explored3", {}):
					var ex: Dictionary = _explored.get_or_add(int(mid), {})
					for comp in j.explored3[mid]:
						var xs: Array = j.explored3[mid][comp]
						for q in range(0, xs.size() - 2, 3):
							(ex.get_or_add(Vector2i(int(xs[q]), int(xs[q + 1])), []) as Array).append([int(comp), NAN if xs[q + 2] == null else float(xs[q + 2])])
				for mid in j.get("explored", {}):   # 旧格式: 没存高度
					var ex: Dictionary = _explored.get_or_add(int(mid), {})
					for comp in j.explored[mid]:
						var xs: Array = j.explored[mid][comp]
						for q in range(0, xs.size() - 1, 2):
							(ex.get_or_add(Vector2i(int(xs[q]), int(xs[q + 1])), []) as Array).append([int(comp), NAN])
				_comp_seq = maxi(_comp_seq, int(j.get("comp_seq", 0)))
				for mid in j.get("links", {}):
					links[int(mid)] = (j.links[mid] as Array).map(func(v): return [Vector3(v[0], v[1], v[2]), Vector3(v[3], v[4], v[5]), str(v[6]) if v.size() > 6 else ""])
				_say("接着用存档 %s 的机器人记忆: 去过 %d 张地图" % [a.substr(7), _outside.size()])


func _finish(why: String) -> void:
	for a in OS.get_cmdline_user_args():   # --ap-save=档位: 到终点时存档 (下一段测试从这里 --load 开始)
		if a.begins_with("--ap-save-any="):   # 卡住 / 超时也存档 (分析用)
			field.save_game(int(a.substr(14)))
			_save_mem(int(a.substr(14)))
			_say("已存档到 %s" % a.substr(14))
		if a.begins_with("--ap-save=") and why.begins_with("DONE"):
			field.save_game(int(a.substr(10)))
			_save_mem(int(a.substr(10)))
			_say("已存档到 %s" % a.substr(10))
	var main: Array = field.events_run.keys().filter(func(e): return e < 150)
	main.sort()
	_say("%s steps=%d progress=%d flags=%d party=%s 主线事件=%s" % [why, steps, progress, State.flags.size(), str(State.party), str(main)])
	if why.begins_with("STUCK"):
		_flood()
		_say("  可走格数 %d" % _reach.size())
		_say("  主角 %s inst=%d actors1=%s" % [str(field.player.gpos.round()), field.player.get_instance_id(), str(field.actors.get(1).get_instance_id()) if field.actors.has(1) else "-"])
		for ac in field.actors.values():
			if ac != field.player and not ac.hidden and (ac.gpos - field.player.gpos).length() < 300:
				_say("  附近角色 %d act=%d pos=%s flags=0x%x" % [ac.id, ac.act, str(ac.gpos.round()), ac.flags])
		for c in _candidates_all():
			_say("  候选 %s ev%d deps=%s dests=%s 走得到=%s" % [c.key, c.eid, str(_deps(int(c.eid))), str(c.dests), str(_reach_spot(c) != null)])
	var f := FileAccess.open("user://autoplay_report.txt", FileAccess.WRITE)
	if f:
		f.store_string("\n".join(log_lines))
	get_tree().quit()
