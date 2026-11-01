class_name Formula
extends RefCounted
## 战斗数值公式 (SWDMD_GB.EXE 逆向, 见 scratchpad/re/battle_formula_re.md 的整理):
##   命中 roll_hit 0x4376eb, 伤害 0x437858 (物理 0x438301 / 法术 0x437c36 / 公共修正 0x43820d), 属性 0x438aa6,
##   暴击 0x438c86, 消耗 0x4346e5, 状态 0x435935, 增减益 0x434b2b
## 整数运算都按 C 语义截断

const ST_LOWHP := 0x1
const ST_DEAD := 0x2
const ST_POISON := 0x4
const ST_SLEEP := 0x8
const ST_STONE := 0x10
const ST_SEAL := 0x20
const ST_JOY := 0x40      # 心喜
const ST_RAGE := 0x80     # 爆怒
const ST_SORROW := 0x100  # 悲哀
const ST_MANIA := 0x200   # 狂乐
const ST_DECOY := 0x400   # 替身
const ST_CHAOS := 0x800   # 混沌
const STATUS_NAMES := {0x4: "毒发", 0x8: "昏睡", 0x10: "石化", 0x20: "咒封", 0x40: "心喜", 0x80: "爆怒",
	0x100: "悲哀", 0x200: "狂乐", 0x400: "替身", 0x800: "混沌"}


static func rnd(n: int) -> int:
	return randi() % maxi(n, 1)


## 数值编码 (§3c): v > 20000 → (v−20000)×max; 10000 < v ≤ 20000 → max×(v−10000)%; 负数对称; 其余为平值
static func amount(v: int, mx: int) -> int:
	if v > 20000:
		return (v - 20000) * mx
	if v > 10000:
		var p := v - 10000
		return mx if p >= 99 else mx * p / 100
	if v < -20000:
		return (v + 20000) * mx
	if v < -10000:
		var q := -v - 10000
		return -mx if q >= 99 else -mx * q / 100
	return v


## 命中判定 (§2): 返回 1 命中 / 0 闪避 / 5 无效
static func roll_hit(att: BattleUnit, tgt: BattleUnit, act: Dictionary, physical: bool, mode: int) -> int:
	if tgt.absent:
		return 5
	if mode == 6 or att.defending_cmd:
		return 1
	if mode != 1:
		return mode
	if int(act.get("sub", 0)) in [202, 305, 302]:   # 恢复 / 特殊 / 木甲修复 必中
		return 1
	if not class_ok(tgt, int(act.get("target_class", 0))):   # 0xC22 目标类别过滤 (0x43a27b) → 无效
		return 5
	var thr: int
	if physical:
		if tgt.defending:
			return 1
		thr = 100 - att.stat("hit") + tgt.stat("eva")
	else:
		if int(act.get("kind", 0)) == 1:
			thr = 100 - att.stat("hit") + tgt.stat("eva")
		elif tgt.defending:
			return 1
		else:
			thr = 100 - att.stat("mhit") + tgt.stat("meva")
	var roll := rnd(500) % 100
	if att.missed_last:
		att.missed_last = false
		thr = 0
	if roll >= thr:
		return 1
	att.missed_last = true
	return 0


## 属性修正 E (§4): 木 0 火 1 土 2 金 3 水 4 (相生吸收 / 被克抵抗 / 相克弱点), 物理 5/6
static func elem_mod(a: Array, t: Array) -> int:
	for i in 5:
		if int(a[i]) != 0:
			if int(t[(i + 1) % 5]) > 0:
				return -200 - int(a[i]) - int(t[(i + 1) % 5])
			if int(t[(i + 3) % 5]) > 0:
				return -(int(a[i]) + int(t[(i + 3) % 5]))
			if int(t[(i + 2) % 5]) > 0:
				return int(a[i]) + int(t[(i + 2) % 5])
			return 0
	for i in [5, 6]:
		if int(a[i]) != 0:
			return int(a[i]) - int(t[i])
	return -int(t[5])


## 我方的等级系数 L (§3b): clamp(1 + 0.05×(攻方等级 − 守方等级), 1, 2)
static func level_factor(att: BattleUnit, tgt: BattleUnit) -> float:
	return clampf(1.0 + 0.05 * (att.level - tgt.level), 1.0, 2.0)


## 公共修正 (§3d)
static func common_mod(dmg: int, att: BattleUnit, tgt: BattleUnit, party_physical: bool) -> int:
	if tgt.has(ST_STONE):
		dmg /= 5
	if att.has(ST_SORROW):
		dmg /= 2
	if tgt.has(ST_SORROW):
		dmg /= 2
	if att.has(ST_MANIA):
		dmg *= 2
	if tgt.has(ST_MANIA):
		dmg *= 2
	if att.has(ST_CHAOS):
		dmg /= 3
		if party_physical:
			dmg = maxi(dmg, 1)
	if tgt.has(ST_CHAOS):
		dmg *= 2
	if tgt.defending:
		var half := dmg / 2
		dmg = half if half != 0 else (1 if dmg > 0 else -1)
	if dmg < 0:
		dmg = mini(dmg / 5, -1)
	return dmg


## 结算一次 (0x437858): 返回 {"hp": 伤害(负=治疗), "mp": 回复, "sp": 回复, "crit": bool, "miss": bool, "text": 提示}
static func settle(att: BattleUnit, tgt: BattleUnit, act: Dictionary, hit_result: int, crit: bool) -> Dictionary:
	var r := {"hp": 0, "mp": 0, "sp": 0, "crit": crit, "miss": false, "text": ""}
	if hit_result == 0:
		r.miss = true
		return r
	if hit_result == 5:
		r.text = "无效"
		return r
	var rn := rnd(11) - 5
	# 防御指令 (§3a): 回复 5% HP、3% MP/SP
	if att.defending_cmd:
		r.hp = -(5 * att.hp_max / 100)
		r.mp = 3 * att.mp_max / 100
		r.sp = 3 * att.sp_max / 100
		return r
	var kind := int(act.get("kind", 0))
	if kind == 1 or act.get("_normal", false):
		# 普通攻击 / 奋力一击 (§3b)
		if tgt.has(ST_DECOY):
			tgt.clear_status(ST_DECOY)
			r.text = "替身"
			return r
		if tgt.has(ST_SLEEP):
			tgt.clear_status(ST_SLEEP)
		var base := maxi(1, att.stat("atk") - tgt.stat("def"))
		var e := elem_mod(att.attack_elem(), tgt.defense_elem())
		var dmg: int
		if att.party:
			dmg = base + base * (int(e * level_factor(att, tgt)) + rn) / 100
			if crit:
				dmg *= 2 if rnd(90) < 60 else 3
		else:
			dmg = base + base * (e + rn) / 100
			dmg += att.level if dmg > 0 else -att.level
			if crit:
				dmg *= 2
		dmg = common_mod(dmg, att, tgt, att.party)
		r.hp = dmg
		tgt.knock += 500 if (crit and att.party) else (333 if crit else int(act.get("knock", 0)))
		apply_status(tgt, act, r)
		return r
	# 法术 / 道具 (§3c): 先数值效果 (以目标上限为底, 不看施法者)
	var fx1: Array = act.get("fx1", [0, 0, 0, 0, 0, 0])
	var fx2: Array = act.get("fx2", [0, 0, 0, 0, 0, 0, 0])
	r.hp = -amount(int(fx1[0]), tgt.hp_max)
	r.sp = amount(int(fx1[1]), tgt.sp_max)
	r.mp = amount(int(fx2[0]), tgt.mp_max)
	if int(act.get("juji_gain", 0)) > 0 and tgt.party:
		tgt.juji = mini(100, tgt.juji + int(act.juji_gain))
	apply_status(tgt, act, r)
	apply_buffs(tgt, act)
	tgt.knock += int(act.get("knock", 0))
	var sub := int(act.get("sub", 0))
	if sub in [203, 302, 202]:
		return r
	if kind == 2 and sub != 201:
		return r
	if tgt.has(ST_DECOY):
		tgt.clear_status(ST_DECOY)
		r.text = "替身"
		return r
	if kind == 3 or (kind == 2 and sub == 201):
		var power := int(act.get("power", 0))
		if power > 0:
			var base := maxi(1, (att.stat("matk") * power - tgt.stat("mdef") * 1000) / 10 / 100)
			var e := elem_mod(act.get("elem", [0, 0, 0, 0, 0, 0, 0]), tgt.defense_elem())
			var dmg: int
			if att.party:
				dmg = base + base * (int(e * level_factor(att, tgt)) + rn) / 100
			else:
				dmg = base + base * (e + rn) / 100
				dmg += att.level if dmg > 0 else -att.level
			r.hp += common_mod(dmg, att, tgt, false)
	return r


## 目标类别规则 (0x43a27b; 0xC22 命中过滤 / 0xC23 状态无效对象共用): 怪物 sub 118 木甲机关 / 119 大型机关·首领 / 120 剧情人物·魔王
## 怪物目标: bit1 → 对 118/119 无效, bit2 → 对 119/120 无效, bit8 → 只对 118/119 有效
## 我方目标: bit4 → 对木甲 (云狐单位, 0x196a = 0xb) 无效, bit8 → 只对木甲有效
static func class_ok(tgt: BattleUnit, cls: int) -> bool:
	if cls == 0:
		return true
	if tgt.party:
		var mech := tgt.member == 1 and not tgt.summon
		if cls & 4 and mech:
			return false
		if cls & 8 and not mech:
			return false
		return true
	var sb := int(tgt.rec.get("sub", 0))
	if cls & 1 and sb in [118, 119]:
		return false
	if cls & 2 and sb in [119, 120]:
		return false
	if cls & 8 and sb not in [118, 119]:
		return false
	return true


## 状态互斥表 0x4cdb7c (行 = 已有状态, 列 = 新状态; 下标 = 位号: 濒死 死亡 毒 睡 石 封 喜 怒 哀 乐 替 混);
## 2 / 3 = 允许 (3 先移除该旧状态), 0 / 1 = 不允许
const STATUS_CONFLICT := [[0, 3, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2], [1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0],
	[2, 3, 0, 2, 2, 2, 2, 2, 2, 2, 2, 3], [2, 3, 2, 0, 3, 2, 2, 2, 2, 2, 1, 3], [2, 3, 2, 3, 0, 2, 2, 2, 2, 2, 1, 3],
	[2, 3, 2, 2, 2, 0, 2, 2, 2, 2, 1, 3], [2, 3, 2, 2, 2, 2, 0, 3, 3, 3, 2, 3], [2, 3, 2, 2, 2, 2, 3, 0, 3, 3, 2, 3],
	[2, 3, 2, 2, 2, 2, 3, 3, 0, 3, 2, 3], [2, 3, 2, 2, 2, 2, 3, 3, 3, 0, 2, 3], [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 3],
	[2, 3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]]


## 施加状态 0x4397e5(位, −1, 轮数): 已有同一位 → 不变 (不刷新); 没有任何状态 → 允许; 否则任一已有状态那一行允许就行。
## 允许时**先清掉全部已有状态**再挂新的 —— 同一时间只有一种状态。返回是否挂上
## (死亡 / 濒死两位走伤害路径, 由调用方处理; 这里只管 0x4–0x800)
static func try_status(tgt: BattleUnit, bit: int, turns: int) -> bool:
	if tgt.status & bit:
		return false
	var col := 0
	while (1 << col) < bit:
		col += 1
	var cur := tgt.status & 0xFFC
	var ok := cur == 0
	for r in 12:
		if cur & (1 << r) and int(STATUS_CONFLICT[r][col]) >= 2:
			ok = true
	if not ok:
		return false
	for b in STATUS_NAMES:
		if tgt.status & b:
			tgt.clear_status(b)
	tgt.add_status(bit, turns)
	return true


## 状态 (§5): 施加 0x2000 / 随机施加一个 0x8000, 解除 0x1000 / 0x4000; 成功率 rand(200)%100 ≤ rate
static func apply_status(tgt: BattleUnit, act: Dictionary, r: Dictionary) -> void:
	var mask := int(act.get("status", 0))
	var op := int(act.get("status_op", 0))
	if mask == 0:
		return
	if not class_ok(tgt, int(act.get("immune", 0))):   # 0xC23 状态无效对象 (例: 招魂即死对木甲机关 / 魔王无效)
		return
	if op in [0x2000, 0x8000]:
		var rate := 100 if mask & ST_DECOY else int(act.get("status_rate", 0))
		if rate == 0 or rnd(200) % 100 > rate:
			return
		var bits: Array = []
		for b in STATUS_NAMES:
			if mask & b:
				bits.append(b)
		if mask & ST_DEAD:
			r.hp = maxi(int(r.hp), tgt.hp)   # 施加「死亡」= 等于当前 HP 的伤害
		if op == 0x8000 and bits.size():
			bits = [bits[rnd(bits.size())]]
		for b in bits:
			try_status(tgt, b, maxi(int(act.get("turns", 3)), 1))
	elif op in [0x1000, 0x4000]:
		for b in STATUS_NAMES:
			if mask & b:
				tgt.clear_status(b)
		if mask & ST_DEAD and tgt.dead:
			tgt.revive()


## 增减益 (§5): fx1[2..5] 攻 防 命中 回避, fx2[1..5] 仙攻 仙防 仙命中 仙回避 速度; 以基础值为底; 成功率 rand(100) ≤ buff_rate
static func apply_buffs(tgt: BattleUnit, act: Dictionary) -> void:
	var rate := int(act.get("buff_rate", 0))
	if rate == 0 or rnd(100) > rate:
		return
	var fx1: Array = act.get("fx1", [0, 0, 0, 0, 0, 0])
	var fx2: Array = act.get("fx2", [0, 0, 0, 0, 0, 0, 0])
	var turns := maxi(int(act.get("turns", 3)), 1)
	var pairs := [["atk", fx1[2]], ["def", fx1[3]], ["hit", fx1[4]], ["eva", fx1[5]],
		["matk", fx2[1]], ["mdef", fx2[2]], ["mhit", fx2[3]], ["meva", fx2[4]], ["spd", fx2[5]]]
	for pr in pairs:
		if int(pr[1]) != 0:
			tgt.add_buff(str(pr[0]), amount(int(pr[1]), tgt.base_stat(str(pr[0]))), turns)


## 暴击 (§3e): 我方 rand(700)%100 < crit, 怪物同样; 爆怒 +30, 悲哀 → 0
static func roll_crit(att: BattleUnit) -> bool:
	var c := att.crit
	if att.has(ST_RAGE):
		c += 30
	if att.has(ST_SORROW):
		c = 0
	return rnd(700) % 100 < c


## 消耗 (§3f): > 10000 按 (v−10000)% × 自身上限, 否则平值
static func cost_of(v: int, mx: int) -> int:
	return (v - 10000) * mx / 100 if v > 10000 else v


## 我方逃跑 (§8): rand(200)%100 < 我方平均速度 − 敌方平均速度 + 70
static func escape_ok(party: Array, enemies: Array) -> bool:
	var avg := func(us: Array) -> float:
		var n := 0
		var s := 0
		for u in us:
			if not u.has(ST_STONE) and not u.dead and not u.absent:
				n += 1
				s += u.eff_speed()
		return float(s) / maxf(n, 1)
	return rnd(200) % 100 < int(avg.call(party) - avg.call(enemies) + 70)
