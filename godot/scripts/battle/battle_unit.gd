class_name BattleUnit
extends RefCounted
## 战斗单位 (原版 0x908488 + i×0x1c7c; 0..5 我方, 6.. 敌方)
## 模型用 FieldActor (ACT 模型 + 动作), 坐标为战斗场景坐标 (游戏单位)

var index := 0                  # 单位下标 (FIGTALK 的 unitN)
var id := 0                     # 游戏编号 (ObjDATA 下标 + 1)
var rec: Dictionary = {}        # ObjDATA 记录
var party := false
var member := 0                 # 我方: 角色号 1 车芸 / 2 嬴诗 / 3 桓远之
var name := ""
var level := 1
var hp := 0
var hp_max := 1
var mp := 0
var mp_max := 0
var sp := 0
var sp_max := 0
var base := {}                  # atk def spd matk mdef hit eva mhit meva (战斗开始时拷贝, 换装不更新)
var crit := 0
var elem: Array = [0, 0, 0, 0, 0, 0, 0]
var weapon: Dictionary = {}     # 普攻用的记录 (我方 = 武器, 怪物 = 自身)
var accessory: Dictionary = {}  # 饰品 (我方的防御属性来源)
var status := 0
var status_turns := {}          # 状态位 → 剩余轮数 (状态节点 +0x158; 255 = 永久)
var status_prog := {}           # 状态位 → 计时 (+0x150, 每逻辑帧 + 速度/10, 满 1000 算一轮)
var status_born := {}           # 状态位 / 增减益属性 → 挂上的时刻 (毫秒; 节点新建时图标动画从头播)
var buffs := {}                 # 属性 → [值, 剩余轮数, 计时] (增减益也是状态节点, +0x148 = 0)
var poison_dmg := 0             # +0x1980 待结算的毒伤害
var turn_count := 0             # +0x1b74 自己的回合数
var doom := -1                  # +0x1b78 宣告死亡倒数 (−1 = 没有)
var fled := false               # +0x1a08 (与收化共用): 逃离了战场
var nuoyi_turns := 0            # +0x1bf8 挪移剩余回合
var nuoyi_uses := 0             # +0x1bfc 挪移剩余次数
var emo_joy := 0                # +0x1b68 / +0x1b70 / +0x1b6c 自动情绪计数
var emo_mania := 0
var emo_sorrow := 0
var gauge := 0                  # 行动条 0..1000
var knock := 0                  # 击退值 (被打时增加, 先抵消行动条增长)
var defending := false
var defending_cmd := false      # 正在执行「防御」指令本身 (回复 5% HP)
var missed_last := false        # 上一下闪空 → 下一下必中
var juji := 0                   # 蓄劲值 0..100
var dead := false
var absent := false             # 不在场 (FIGTALK set_unit_status 0x10、逃走)
var actions_taken := 0          # 自身行动次数 (AI 用)
var uses := {}                  # 技能槽 → 本场已用次数
var actor: FieldActor           # 模型
var figure: FieldActor          # 车芸本体 (云狐单位的附属, 不参战)
var home := Vector3.ZERO        # 站位 (游戏单位)
var wanbi_turns := 0            # 法宝「完璧」(5202): 剩余回合 (unit+0x1bec)
var wanbi_rate := 1             # 每枚金钱抵多少伤害 (unit+0x1bf0)
var redirect: BattleUnit        # 法宝「挪移」(5214): 打向自己的招式转给这个单位 (unit+0x1bf4..)
var survive_used := false       # 法宝「菩萨发咒」(5209): 本场已免死过
var facing := 0.0
## 吟咒 (unit+0x1960 bit 0x4000; 0x439e52 进入, 0x439f4f 释放, 0x436cba 被击退到 0 时打断)
var chanting := false
var chant_speed := 0            # +0x1b94: 吟咒期间代替速度 (ObjDATA 0x3EB)
var chant_rec: Dictionary = {}  # +0x1b98 吟咒的技能
var chant_atk := 1000           # +0x1b9c 释放 ATK (起咒脚本 ATK 指令 0x82 写入)
var chant_targets: Array = []   # +0x1ba0 (最多 16)
var chant_fx := 0               # 行动条上的光圈: 0 无 / 2 吟咒中 (循环) / 1 被打断 (播一次)
var chant_fx_t := 0.0
## 收伏 / 护驾
var captured := false           # +0x1a08 被收化
var summon := false             # +0x19ec 护驾 (AI 控制的盟友)
var guard_k := -1               # +0x19ca 第几座鬼神阵的护驾
## 机关侦查术
var scan_count := 0             # +0x1be0 被侦查次数
var tech_pool := 0
var reflect := false            # +0x1960 & 0x100000 皓月宝镜: 偷钱反弹 (ATK 0x96)
var variant := 0                # +0x1928 附加层选择 (ATK 0x87, 四首变化); 目前只记录
var money := 0                  # +0x1be8 敌人身上的钱 (0x431269: 等级 × 10, 首领 sub 120 × 50, sub 118 / 119 为 0); 偷钱 0x90 拿一半
var decoy: FieldActor
var moving := false             # FIGTALK move_unit_to 移动中           # 替身状态显示的复制体 (0x432d7e)              # +0x1be4 可挖取的木甲技术存量 (怪物掉落表第 2 组的 u16)


func has(bit: int) -> bool:
	return status & bit != 0


## 直接挂上一个状态 (不检查互斥; 一般走 Formula.try_status = 0x4397e5)
func add_status(bit: int, turns: int) -> void:
	status |= bit
	status_turns[bit] = turns if turns >= 0 else 255
	status_prog[bit] = 0
	status_born[bit] = Time.get_ticks_msec()


func clear_status(bit: int) -> void:
	status &= ~bit
	status_turns.erase(bit)
	status_prog.erase(bit)


## 我方濒死位 (+0x1964 第 0 位, 行动结束 0x436d72 按 HP ≤ 上限/4 更新; 敌方记录上不设)
func low_hp() -> bool:
	return party and not summon and hp * 4 <= hp_max


## 状态计时速度 (0x435d1e): (吟咒中取吟咒速度, 否则基础速度) + 增益; 悲哀 −1, 否则狂乐 ×2; 濒死再 ×2; 最后 /10
func status_rate() -> int:
	var t := (chant_speed if chanting else base_stat("spd")) + (stat("spd") - base_stat("spd"))
	if has(Formula.ST_SORROW):
		t -= 1
	elif has(Formula.ST_MANIA):
		t *= 2
	if low_hp():
		t *= 2
	return t / 10


## 每个逻辑帧 (0x435d1e): 所有状态 / 增减益节点计时 + 速度, 满 1000 清零并把剩余轮数 −1 (255 永久不减);
## 毒满一轮时记下待结算伤害 = 当前 HP × 5 / 100。之后移除轮数 ≤ 0 的节点: 状态 → 返回解除提示, 增减益静默删除
func status_tick() -> Array:
	var msgs: Array = []
	var t := status_rate()
	for b in status_turns.keys():
		status_prog[b] = int(status_prog.get(b, 0)) + t
		if int(status_prog[b]) >= 1000:
			status_prog[b] = 0
			var n := int(status_turns[b])
			if n > 0 and n < 255:
				status_turns[b] = n - 1
			if b == Formula.ST_POISON:
				poison_dmg = hp * 5 / 100
	for k in buffs.keys():
		var e: Array = buffs[k]
		if e.size() < 3:
			e.append(0)
		e[2] = int(e[2]) + t
		if int(e[2]) >= 1000:
			e[2] = 0
			if int(e[1]) > 0 and int(e[1]) < 255:
				e[1] = int(e[1]) - 1
	for b in status_turns.keys():
		if int(status_turns[b]) <= 0:
			clear_status(b)
			msgs.append("解除%s状态" % Formula.STATUS_NAMES.get(b, ""))
	for k in buffs.keys():
		if int(buffs[k][1]) <= 0:
			buffs.erase(k)
	return msgs


func revive() -> void:
	dead = false
	status &= ~Formula.ST_DEAD
	hp = maxi(hp, 1)


func base_stat(k: String) -> int:
	return int(base.get(k, 0))


## 属性 = 基础值 + 增益, 再加状态修正 (0x436f6f 等)
func stat(k: String) -> int:
	var v := base_stat(k)
	if buffs.has(k):
		v += int(buffs[k][0])
	if k == "mdef" and has(Formula.ST_JOY):
		v += base_stat(k) / 5
	if k == "eva":
		if has(Formula.ST_JOY):
			v += 20
		if has(Formula.ST_RAGE):
			v -= 30
	return v


## 有效速度 (0x437186): 基础 + 增益, 狂乐 +¼, 悲哀 −¼, 濒死 ×1.5, 昏睡 / 石化 / 死亡 = 0
func eff_speed() -> int:
	if dead or absent or has(Formula.ST_SLEEP) or has(Formula.ST_STONE):
		return 0
	var b := chant_speed if chanting else base_stat("spd")   # 吟咒期间基础速度换成吟咒速度 (0x437186)
	var v := b + stat("spd") - base_stat("spd")
	if has(Formula.ST_MANIA):
		v += b / 4
	if has(Formula.ST_SORROW):
		v -= b / 4
	if hp * 4 <= hp_max:
		v = v * 3 / 2
	return maxi(v, 0)


func add_buff(k: String, v: int, turns: int) -> void:
	buffs[k] = [v, turns, 0]
	status_born[k] = Time.get_ticks_msec()


## 攻击属性: 普攻取武器 (怪物取自身 0x3F1 武器) 的属性
func attack_elem() -> Array:
	return weapon.get("elem", elem)


## 防御属性: 我方取饰品, 怪物取自身
func defense_elem() -> Array:
	if party:
		return accessory.get("elem", [0, 0, 0, 0, 0, 0, 0])
	return elem


func pos() -> Vector3:
	return actor.gpos if actor else home
