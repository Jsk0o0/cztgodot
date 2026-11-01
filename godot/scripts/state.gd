extends Node
## 游戏进度 (autoload: State)。对应原版内存里的: 旗标位图 0xafdc58 / 触发区禁用位图 0xafe058 / 角色私有变量 gmRoleVar
## [0xafe95c] / 背包 0xbceca0 / 金钱 [0xbcec84] / 木材·金属·煤炭·技术点 [0xbcec88..94] / 常驻角色表 [0xafe958]
## 任务没有专门的数据: 任务 i (Mission.gll ID 7001+i) 接取 = 旗标 7001+i, 完成 = 旗标 7257+i (0x483e14)

signal flags_changed
signal inventory_changed
signal message(text: String)   # 「任务更新」「得到 X」等 (由事件脚本自己显示, 这里只做通知)

const SAVE_DIR := "user://saves"

var flags := {}              # 旗标号 → true
var triggers_off := {}       # 事件号 → true (set_trigger 禁用)
var actor_vars := {}         # "角色号:槽" → 值
var items := {}              # 物品号 → 数量
var money := 0
var wood := 0
var metal := 0
var coal := 0
var tech := 0                # 木甲技术点数: 可用 ([0xbcec94])
var tech_total := 0          # 木甲技术点数: 累计获得 ([0xbcec98], 只增不减)
var jg_nodes: Array = [10]   # 机关页: 已学的技术节点 (10 = 根节点, 初始就已学)
var jg_granted: Array = []   # 机关页: 已授予的机关板 (板号 0..26)
var mech_lv := {}            # 木甲术等级: 法术号 6024–6027 → 1..3
var regs: Array = [0, 0, 0, 0, 0, 0, 0, 0, 0]   # 全局变量 0xafe858+4n (1 = 连续战斗剩余场数)
var countdown_maps: Array = []   # 连续战斗计数有效的地图 (0xafe860.., 事件 0xa1)
var ts_houses: Array = []    # 天书房舍 [{type, pos:[x,y,z], seq}] (链表 0xea2aa4)
var guard_hp := {}           # 护驾退驾后的剩余生命 (怪物 id → HP; 战斗结束回满时清掉)
var ts_grid: Array = []      # 天书建造格 20×17 (0 不可建 / 1 可建 / 2 已占, 0xdd6720)
var ts_residents: Array = [] # 天书居民 [{id, house}] (链表 0xea5168; house 0 = 闲置)
var party: Array = [1]       # 队伍角色号 (1 车芸 …)
var members := {}            # 角色号 → {"hp","mp","sp","lv","exp", ...} (战斗用, 由 Battle 初始化)
var equip := {}              # 角色号 (1 车芸 / 2 嬴诗 / 3 桓远之) → 装备栏 [武器, 身体, 饰品, 鞋, 法宝…] (物品编号)
var skills := {}             # 角色号 → 已学技能编号
var artifact_exp := {}       # 法宝编号 → 修练值 (战斗经验的 1/10 分给装备着的可修练法宝)
## 常驻角色表: 角色号 → {"map": 地图号, "pos": [x,y,z], "facing": 度, "act": ACT, "pose": 动作, "hidden": bool,
##   "event": 调查事件, "ai": AI 号}。place_actor_map 等指令改写, 进入地图时据此放置 (覆盖 MAPS.DAT 的初始摆放)
var actors := {}
var map_music := {}          # 地图号 → [曲目A, 次数, 曲目B, 次数] (set_map_music)
var map_id := 0
var player_pos := Vector3.ZERO
var player_facing := 0.0
var play_seconds := 0.0
var just_loaded := false   # 刚读档 (field 重进场景时不套用启动调试参数)


func reset() -> void:
	map_floor = 1
	minimap_mode = 0
	flags.clear()
	triggers_off.clear()
	actor_vars.clear()
	items.clear()
	money = 0
	wood = 0
	metal = 0
	coal = 0
	tech = 0
	tech_total = 0
	jg_nodes = [10]
	jg_granted = []
	mech_lv = {}
	regs = [0, 0, 0, 0, 0, 0, 0, 0, 0]
	countdown_maps = []
	ts_houses = []
	ts_grid = []
	guard_hp = {}
	ts_residents = []
	party = [1]
	members.clear()
	equip.clear()
	artifact_exp.clear()
	skills.clear()
	actors.clear()
	map_music.clear()
	map_id = 0
	play_seconds = 0.0


func _process(delta: float) -> void:
	play_seconds += delta


func test_flag(n: int) -> bool:
	return flags.has(n)


func set_flag(n: int, on := true) -> void:
	if on:
		flags[n] = true
	else:
		flags.erase(n)
	flags_changed.emit()


func trigger_enabled(event_id: int) -> bool:
	return not triggers_off.has(event_id)


func set_trigger(event_id: int, enabled: bool) -> void:
	if enabled:
		triggers_off.erase(event_id)
	else:
		triggers_off[event_id] = true


func actor_var(actor: int, slot: int) -> int:
	return int(actor_vars.get("%d:%d" % [actor, slot], 0))


func set_actor_var(actor: int, slot: int, v: int) -> void:
	actor_vars["%d:%d" % [actor, slot]] = clampi(v, 0, 0xffff)


func give_item(id: int, n: int) -> void:
	if n > 0 and ((id >= 3001 and id <= 4999) or (id >= 5500 and id <= 5999)):
		Fame.add_item(id)   # 道具图鉴: 放进背包时登记 (0x461f55)
	var v: int = int(items.get(id, 0)) + n
	if v <= 0:
		items.erase(id)
	else:
		items[id] = v
	inventory_changed.emit()


func item_count(id: int) -> int:
	return int(items.get(id, 0))


func add_res(kind: String, d: int) -> void:
	set(kind, maxi(int(get(kind)) + d, 0))
	inventory_changed.emit()


## 任务状态: 0 未接, 1 进行中, 2 完成 (Mission.gll ID 7001+i)
func mission_state(mission_id: int) -> int:
	if test_flag(mission_id + 256):
		return 2
	return 1 if test_flag(mission_id) else 0


## 队员 (角色号 1 车芸 / 2 嬴诗 / 3 桓远之): 首次用到时取 ObjDATA 的主角记录 (含初始等级的数值)
func member(m: int) -> Dictionary:
	if not members.has(m):
		Battle.load_db()
		var r := Battle.obj(m)
		var lv := int(r.get("level", 1))
		var d := {"lv": lv, "exp": exp_threshold(lv - 1), "juji": 0,
			"hp_max": int(r.get("hp", 1)), "mp_max": int(r.get("mp", 0)), "sp_max": int(r.get("sp", 0))}
		for k in ["atk", "def", "spd", "matk", "mdef", "hit", "eva", "mhit", "meva", "crit"]:
			d[k] = int(r.get(k, 0))
		d.hp = d.hp_max
		d.mp = d.mp_max
		d.sp = d.sp_max
		members[m] = d
	return members[m]


## 升到 lv+1 级所需的累计经验 (LEVEL.GLL 经验表)
func exp_threshold(lv: int) -> int:
	for row in Battle.db.get("exp", []):
		if int(row[0]) == lv:
			return int(row[1])
	return 0 if lv <= 0 else 1 << 30


## 战斗用属性 = 队员数值 + 装备加成 (穿脱装备 0x461bd8 只加减攻防速仙攻仙防奋力, 命中回避不加)
func member_stats(m: int) -> Dictionary:
	var d := member(m)
	var out := {}
	for k in ["atk", "def", "spd", "matk", "mdef", "hit", "eva", "mhit", "meva", "crit"]:
		out[k] = int(d.get(k, 0))
	for it in equip.get(m, []):
		if int(it) == 0:
			continue
		var r := Battle.obj(int(it))
		for k in ["atk", "def", "spd", "matk", "mdef", "crit"]:
			out[k] += int(r.get(k, 0))
	return out


## 获得经验; 返回升到的各个等级。升级: 加上成长表该级一行 (HP MP SP 攻 防 仙攻 仙防 命中 回避 仙命中 仙回避 速度 习得法术),
## HP/MP/SP 全满, 上限 99 级 (0x403311)
func add_exp(m: int, e: int) -> Array:
	var d := member(m)
	var ups: Array = []
	if int(d.lv) >= 99:
		return ups
	d.exp = int(d.exp) + e
	var rows: Array = Battle.db.growth.get(str(m), [])
	while int(d.lv) < 99 and int(d.exp) >= exp_threshold(int(d.lv)):
		d.lv = int(d.lv) + 1
		for row in rows:
			if int(row[0]) == int(d.lv):
				var keys := ["hp_max", "mp_max", "sp_max", "atk", "def", "matk", "mdef", "hit", "eva", "mhit", "meva", "spd"]
				for i in keys.size():
					d[keys[i]] = int(d.get(keys[i], 0)) + int(row[i + 1])
				if int(row[13]):
					var sk: Array = skills.get(m, [])
					if not sk.has(int(row[13])):
						sk.append(int(row[13]))
						skills[m] = sk
		d.hp = d.hp_max
		d.mp = d.mp_max
		d.sp = d.sp_max
		ups.append(int(d.lv))
		# 车芸升级 (旗标 7 = 机关已开放): 木甲技术点数 += 点数表该级的获得点数 (0x456f68「獲得木甲技術 %d 點」)
		if m == 1 and test_flag(7):
			var g := tech_gain(int(d.lv))
			tech += g
			tech_total += g
	return ups


## 木甲技术点数表 (LEVEL.GLL 条目 20): 该级获得点数 (0x40360c) / 1..lv 累计 (0x403631)
func tech_gain(lv: int) -> int:
	for row in Battle.db.get("techpts", []):
		if int(row[0]) == lv:
			return int(row[1])
	return 0


func tech_sum(lv: int) -> int:
	var t := 0
	for k in range(1, lv + 1):
		t += tech_gain(k)
	return t


## 法宝修练等级 (LEVEL.GLL 修练表: 修练值达到第 k 级所需值即为 k 级) 与该级参数
func artifact_level(id: int) -> int:
	var rows: Array = Battle.db.get("refine", {}).get(str(id), [])
	var lv := 1
	for k in rows.size():
		if rows[k].size() and int(artifact_exp.get(id, 0)) >= int(rows[k][0]):
			lv = k + 1
	return lv


func artifact_params(id: int) -> Array:
	var rows: Array = Battle.db.get("refine", {}).get(str(id), [])
	if rows.is_empty():
		return []
	return (rows[artifact_level(id) - 1] as Array).slice(1)


## 可修练 = 修练表里有升级门槛
func artifact_refinable(id: int) -> bool:
	var rows: Array = Battle.db.get("refine", {}).get(str(id), [])
	return rows.size() > 1 and rows[1].size() > 0 and int(rows[1][0]) > 0


## heal_member (0x8b, 0x40b0ee): 队员 id 只接受 1–4 (数据里只用 1/2/3; 以前「0 = 全队」是推测, 删掉);
## 档案 +0x48 清第 2 位 (倒下: 结算经验 0x455dc1 跳过、复活道具 0x488ffa 也清它);
## HP += 并夹在 [0, 上限]; MP += 并夹在 [0, 上限]; 体力 += 只夹上限 (原版没有夹 0)
func heal_member(id: int, hp: int, mp: int, sp: int) -> void:
	var m: Dictionary = members.get(id, members.get(str(id), {}))
	if id < 1 or id > 4 or m.is_empty():
		return
	m.hp = clampi(int(m.get("hp", 0)) + hp, 0, int(m.get("hp_max", 1)))
	m.mp = clampi(int(m.get("mp", 0)) + mp, 0, int(m.get("mp_max", 0)))
	m.sp = mini(int(m.get("sp", 0)) + sp, int(m.get("sp_max", 0)))
	m.down = false


func actor_rec(id: int) -> Dictionary:
	if not actors.has(id):
		actors[id] = {}
	return actors[id]


# ---------------- 存档 ----------------

var cam := {}   # 存档 / 读档时的地图镜头 (OrigCamera.to_save), 进图恢复后清空
var map_floor := 1      # 小地图楼层 [0x4e48c8], 存档保存
var minimap_mode := 0   # 小地图三态 [0xafe894] (存档块 0xafe858): 0 不透明, 1 半透明, 2 隐藏

func to_dict() -> Dictionary:
	return {"flags": flags.keys(), "triggers_off": triggers_off.keys(), "actor_vars": actor_vars, "items": items,
		"equip": equip, "skills": skills, "money": money, "wood": wood, "metal": metal, "coal": coal, "tech": tech, "tech_total": tech_total, "jg_nodes": jg_nodes, "jg_granted": jg_granted,
		"mech_lv": mech_lv, "regs": regs, "countdown_maps": countdown_maps, "ts_houses": ts_houses, "ts_grid": ts_grid, "ts_residents": ts_residents, "party": party, "members": members,
		"artifact_exp": artifact_exp, "actors": actors, "map_music": map_music, "map_id": map_id,
		"player_pos": [player_pos.x, player_pos.y, player_pos.z], "player_facing": player_facing, "cam": cam, "map_floor": map_floor, "minimap_mode": minimap_mode,
		"play_seconds": play_seconds, "saved_at": Time.get_datetime_string_from_system(), "mods": Mods.active_list()}


func from_dict(d: Dictionary) -> void:
	reset()
	cam = d.get("cam", {})   # 旧存档没有: 进图后用默认镜头
	map_floor = int(d.get("map_floor", 1))
	minimap_mode = int(d.get("minimap_mode", 0))
	for n in d.get("flags", []):
		flags[int(n)] = true
	for n in d.get("triggers_off", []):
		triggers_off[int(n)] = true
	actor_vars = d.get("actor_vars", {})
	for k in d.get("items", {}):
		items[int(k)] = int(d.items[k])
	money = int(d.get("money", 0))
	wood = int(d.get("wood", 0))
	metal = int(d.get("metal", 0))
	coal = int(d.get("coal", 0))
	tech = int(d.get("tech", 0))
	tech_total = int(d.get("tech_total", tech))
	jg_nodes = Array(d.get("jg_nodes", [10])).map(func(x): return int(x))
	jg_granted = Array(d.get("jg_granted", [])).map(func(x): return int(x))
	ts_houses = d.get("ts_houses", [])
	regs = Array(d.get("regs", [0, 0, 0, 0, 0, 0, 0, 0, 0])).map(func(x): return int(x))
	countdown_maps = Array(d.get("countdown_maps", [])).map(func(x): return int(x))
	ts_grid = Array(d.get("ts_grid", [])).map(func(x): return int(x))
	ts_residents = d.get("ts_residents", [])
	mech_lv = {}
	for k in d.get("mech_lv", {}):
		mech_lv[int(k)] = int(d.mech_lv[k])
	party = d.get("party", [1]).map(func(x): return int(x))
	for k in d.get("equip", {}):
		equip[int(k)] = d.equip[k]
	for k in d.get("skills", {}):
		skills[int(k)] = d.skills[k]
	for k in d.get("artifact_exp", {}):
		artifact_exp[int(k)] = int(d.artifact_exp[k])
	members = {}
	for k in d.get("members", {}):
		members[int(k)] = d.members[k]
	for k in d.get("actors", {}):
		actors[int(k)] = d.actors[k]
	for k in d.get("map_music", {}):
		map_music[int(k)] = d.map_music[k]
	map_id = int(d.get("map_id", 0))
	var p: Array = d.get("player_pos", [0, 0, 0])
	player_pos = Vector3(p[0], p[1], p[2])
	player_facing = float(d.get("player_facing", 0))
	play_seconds = float(d.get("play_seconds", 0))


## 存档文件 (原版 Save\NN.sav): NN.json = 全部数据, NN.meta.json = 列表用的头信息 (0x473e36), NN.png = 缩略图 160×120
func _save_path(slot: int, ext: String) -> String:
	return SAVE_DIR.path_join("%02d.%s" % [slot, ext])


func save_slot(slot: int, thumb: Image = null, map_name := "") -> bool:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var f := FileAccess.open(_save_path(slot, "json"), FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(to_dict()))
	f.close()
	var t := Time.get_datetime_dict_from_system()
	var head := {"saved_at": "%04d%02d%02d%02d%02d%02d" % [t.year, t.month, t.day, t.hour, t.minute, t.second],
		"date": [t.year, t.month, t.day], "play_seconds": int(play_seconds), "map_id": map_id, "map_name": map_name,
		"party": [1 if test_flag(1) else 0, 2 if test_flag(2) else 0, 3 if test_flag(3) else 0],
		"levels": [int(member(1).lv), int(member(2).lv), int(member(3).lv)],
		"money": money, "metal": metal, "wood": wood, "coal": coal, "tech": tech}
	var h := FileAccess.open(_save_path(slot, "meta.json"), FileAccess.WRITE)
	if h:
		h.store_string(JSON.stringify(head))
	if thumb:
		var im := thumb.duplicate() as Image
		im.resize(160, 120, Image.INTERPOLATE_BILINEAR)
		im.save_png(_save_path(slot, "png"))
	elif FileAccess.file_exists(_save_path(slot, "png")):
		DirAccess.remove_absolute(_save_path(slot, "png"))
	return true


## 读剧情快照 (--snapshot=路径, 格式见 field._snapshot: state 字段同存档); 编辑器「播放预览」用
func load_snapshot(path: String) -> bool:
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not d is Dictionary or not (d as Dictionary).has("state"):
		return false
	from_dict(d.state)
	return true


## 读档 (0x47544f): 恢复后清掉临时旗标 8012、8015、8052–8054、8042、8080、8101–8108 (0x476343)
func load_slot(slot: int) -> bool:
	var f := FileAccess.open(_save_path(slot, "json"), FileAccess.READ)
	if f == null:
		return false
	var d: Variant = JSON.parse_string(f.get_as_text())
	if not d is Dictionary:
		return false
	from_dict(d)
	just_loaded = true
	var have: Array = Mods.active_list().map(func(m): return m.id)
	for m in d.get("mods", []):   # 存档时启用、现在没有的 mod: 只提示, 它的 NPC 不会出现
		if not (m.id in have):
			push_warning("存档用到的 mod %s %s 没有启用" % [m.id, m.version])
	for n in [8012, 8015, 8052, 8053, 8054, 8042, 8080, 8101, 8102, 8103, 8104, 8105, 8106, 8107, 8108]:
		flags.erase(n)
	return true


func slot_header(slot: int) -> Dictionary:
	var f := FileAccess.open(_save_path(slot, "meta.json"), FileAccess.READ)
	if f == null:
		return {}
	var d: Variant = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


func slot_thumb(slot: int) -> Image:
	var p := _save_path(slot, "png")
	return Image.load_from_file(p) if FileAccess.file_exists(p) else null
