class_name AtkRunner
extends Node
## 执行一段 ATK 招式演出 (ATK VM 0x446feb; 步骤由 tools/skill_catalog.steps_of 导出, 语义同技能预览)
## 伤害结算 (0x443cd8): 特效或施术者动作的 'd' 记号 → 对该目标完整结算一次; 'e' 记号 → 只播受击反应;
## ATK 0x16 hit → 对全部目标结算; 整段结束时还没结算过的目标补结算一次 (特效没有 d 记号时原版在特效结束时结算)
## 命中: roll (0x74) 为每个目标判定, if_hit (0x75) 按第一个目标的结果跳转 (闪避时跳过火花等命中特效)

signal finished

static var TICK := 1.0 / 35.0   # 招式脚本 / 动作计时的逻辑帧长, 战斗中 1/27 (见 FieldActor.TICK)

var bt: Node                     # Battle
var caster: BattleUnit
var atk_owner: BattleUnit   # 真正的施术者 (caster 在 0x8e 换执行者期间会临时换成别的单位)
var targets: Array = []          # [BattleUnit]
## false = 只演出不结算 (法宝、起咒、开场演出): 目标照常给镜头 0x2a / 特效「对目标」/ 移动用, 只是 d / e 记号和 hit 不结算、不播受击
## (以前不结算的做法是把目标清空, 0x2a 对准目标失效 —— 火眼金睛的镜头停在开场位置, 车芸本体离镜头不到 2 米, 脸被近裁剪面切掉, 露出后脑勺的头发内侧)
var settle := true
var act: Dictionary = {}         # 动作记录 (武器 / 法术 / 道具)
var crit := false
var steps: Array = []
var results := {}                # 目标 → 命中结果 (1 / 0 / 5)
var settled := {}                # 目标 → 已结算次数
var fx := {}                     # "id_sub" → Fx
## 命中记号按执行者分开记 (ATK 0x70 set_actor_mode: 云狐招式里有一段由车芸本体做动作, 两边的动作和记号各自独立):
##   slot 0 = 施术者本体 (云狐的道具动作等改由车芸本体做时, 记号也取车芸的), slot 1 = 模式 1 下的车芸本体
var _slots := [{"marks": [], "actor": null, "done": {}}, {"marks": [], "actor": null, "done": {}}]
var _offset := [0, 0, 0]


func run() -> void:
	atk_owner = caster
	var pending := 0.0
	var pending_fig := 0.0   # 模式 1 下车芸本体动作的剩余时长: 和施术者本体的动作各自计时, 互不等待
	var i := 0
	while i < steps.size():
		var st: Dictionary = steps[i]
		i += 1
		# 0x8e 换执行者: 动作 / 移动 / 特效由那个单位做 (例 墨衡的机关臂), 结算仍算施术者的
		var eu: BattleUnit = atk_owner
		if st.has("actor") and int(st.actor) < bt.units.size():
			var cand: BattleUnit = bt.units[int(st.actor)]
			if cand and cand.actor and not cand.dead:
				eu = cand
		if eu != caster:
			caster = eu
			_slots[0].actor = caster.actor
		if OS.get_cmdline_user_args().has("--trace-events"):
			print("ATK f=%d %s #%d %s" % [Engine.get_process_frames(), caster.name, i - 1, str(st)])
		match str(st.t):
			"pose":
				# set_pose (0x15 → 0x431787): 只写动作号, 立刻切, 不等上一个动作 (以前等上一个播完才切, 三刀之间拖很长; 用户反馈)
				if st.get("fig", false) and caster.figure:
					_play_fig(int(st.pose))
				else:
					_play(int(st.pose))
			"wait_anim":
				# wait_anim (0x13 → 0x44a060): 参数 0 = 等执行者当前动作播完 (播放器 +0xc0 bit0); 参数 N = 等播到第 N 帧, 然后定格在第 N 帧
				var wa: FieldActor = caster.figure if (st.get("fig", false) and caster.figure) else (_slots[0].actor if is_instance_valid(_slots[0].actor) else caster.actor)
				var fr := int(st.get("frame", 0))
				if wa:
					if fr <= 0:
						while is_instance_valid(wa) and not wa.pose_loop and wa.pose_tick < wa.pose_len - 1:
							await get_tree().process_frame
					else:
						while is_instance_valid(wa) and wa.pose_tick < fr and not (wa.pose_loop and wa.pose_tick >= wa.pose_len - 1):
							await get_tree().process_frame
						if is_instance_valid(wa):
							wa.hold_at(fr)
			"move":
				# 原版移动指令 (0x0e run_to_target 等) 不等前一个动作播完, 直接切动作开始移动 (要等用 wait_anim)
				pending = 0.0
				await _move(st)
			"effect":
				_spawn_fx(st)
				await _wait(TICK)
				pending = maxf(pending - TICK, 0.0)
			"wait_mark":
				var t0 := _now()
				await _wait_mark(str(st.mark), 1 if (st.get("fig", false) and caster.figure) else 0)
				pending = maxf(pending - (_now() - t0), 0.0)
			"wait_fx":
				var t1 := _now()
				var lst: Array = fx.get("%d_%d" % [int(st.id), int(st.sub)], [])
				var f: Variant = lst[0] if lst.size() else null   # 多份副本同一时刻放出, 等第一份就够
				var fr := int(st.frame)
				while is_instance_valid(f) and not (f as Fx).reached(fr):
					await get_tree().process_frame
				pending = maxf(pending - (_now() - t1), 0.0)
			"wait_fx_all":
				var t2 := _now()
				while fx.values().any(func(l): return (l as Array).any(func(x): return is_instance_valid(x) and not (x as Fx).reached(0))):
					await get_tree().process_frame
				pending = maxf(pending - (_now() - t2), 0.0)
			"stop_fx":
				# 0x35: 停掉这个编号的全部副本 (多目标的 to_targets 每个目标一份; 以前只记最后一份, 其余一直放到自己播完 —— 铄雷咒的电光气场)
				var k := "%d_%d" % [int(st.id), int(st.sub)]
				for n in fx.get(k, []):
					if is_instance_valid(n):
						(n as Node).queue_free()
				fx.erase(k)
			"wait":
				var tw := float(st.ms) / 1000.0
				await _wait(tw)
				pending = maxf(pending - tw, 0.0)
			"roll":
				for t in targets:
					results[t] = Formula.roll_hit(caster, t, act, _physical(), 6 if bt._force_hit else int(st.mode))
			"end":
				break
			"branch":
				if _branch_true(st):
					i = int(st.to)
			"if_hit":
				if targets.size() and _result(targets[0]) == int(st.value):
					i = int(st.to)
			"hit":
				for t in targets:
					_settle(t, "d")
			"warp":
				var o: Array = st.offset
				if targets.size():
					caster.actor.set_game_pos(targets[0].pos() + Vector3(float(o[0]), 0, float(o[2]) * _side_sign()), false)
					caster.actor.face_point(targets[0].pos())
			"cam":
				match str(st.op):
					"instant":
						cam_instant = true    # camera_instant_on (0x24): 之后的镜头指令不等到位
					"instant_off":
						cam_instant = false   # camera_instant_off (0x25): 之后的镜头指令等镜头到位再往下
					_:
						bt.cam_op(st, caster, targets)
				if OS.get_cmdline_user_args().has("--trace-cam"):
					print("CAM f=%d %s mode=%s ang=%s angt=%s d=%.0f dt=%.0f" % [Engine.get_process_frames(), str(st.op), str(bt.cam.mode), str(bt.cam.ang.round()), str(bt.cam.angt.round()), bt.cam.d, bt.cam.dt])
				# 等镜头到位: pos / look / zoom 和 0x29 对准施术者 (第二次进入 0x44a80e 才检查到位); 0x2a 不等
				if str(st.op) in ["look", "zoom", "pos", "follow_caster"] and not cam_instant:
					var t0 := _now()
					await bt.cam_wait()
					pending = maxf(pending - (_now() - t0), 0.0)
			"message":
				bt._message(str(st.text))
			"video":
				if bt.field and bt.field.has_method("play_video"):
					await bt.field.play_video(str(st.file))
			"caster_fade":
				var fa: FieldActor = caster.figure if st.get("fig", false) and caster.figure else caster.actor
				if fa:
					var spd2 := float(st.speed)
					var d2 := 0.0 if spd2 >= 255.0 or spd2 <= 0.0 else 255.0 / spd2 * TICK
					if int(st.on):
						_fade_actor(fa, 1.0, 0.0)
						_fade_actor(fa, 0.0, d2)
						_faded.erase(caster)
					else:
						_fade_actor(fa, 1.0, d2)
						_faded[caster] = true
			"transform":
				var tu: BattleUnit = bt.transform_unit(atk_owner, int(st.id))
				if tu:
					atk_owner = tu
					caster = tu
					_slots[0].actor = tu.actor
			"bubble":
				# 0x447c87: 说话者名字 = 单位名; 锚点 = 位置 + 动作包围盒顶 × 缩放 (0x43193a); w1 = 100 (1 秒), w6 = 6, w7 × w8 = 参数 (字 × 行),
				# 标志 0x6078 (按字行计 / 锚在头上 / 用世界坐标 / 显示完才计时 / 不能点 / 无箭头), 内边距 15
				var ca := caster.actor
				var top := 150.0
				var pm: Dictionary = ca.meta.get("poses", {}).get(str(ca.pose), {}) if ca else {}
				if pm.get("bbox", []).size() >= 6:
					top = float(pm.bbox[4])
				if ca and ca._groups.has(ca._cur_g):
					top *= (ca._groups[ca._cur_g] as Node3D).transform.basis.get_scale().y   # × 动作缩放 CS.y
				var head := ca.gpos + Vector3(0, top, 0) if ca else caster.pos()
				bt.dialog.show_text(0x7000 + bt.units.find(caster), [100, 0, 0, 0, 0, 6, int(st.w), int(st.h), 0x6078], str(st.text),
					Color(0, 0, 0, 0), caster.name, 2, 5, bt.to_world(head))
			"wait_bubbles":
				while bt.dialog.windows.keys().any(func(k): return int(k) >= 0x7000 and int(k) < 0x7010):
					await get_tree().process_frame
			"summon":
				var sp: Variant = null
				if st.has("pos"):
					sp = Vector3(float(st.pos[0]), float(st.pos[1]), float(st.pos[2]))
				var nu: BattleUnit = bt.atk_summon(int(st.id), caster, sp)
				if nu:
					# 新单位成为目标 (0x44b7f8): 原目标是施术者自己时换成它, 否则加进目标表
					if targets.is_empty() or targets[0] == caster:
						targets = [nu]
					else:
						targets.append(nu)
				else:
					bt._message("呼唤同伴失败!!")   # [0x4e2810]
			"steal_money":
				for t in targets:
					if t:
						bt.steal_money(t, int(st.amount), atk_owner)
			"flag8051":
				State.set_flag(8051, int(st.on) != 0)
				if int(st.on) == 0:
					await _tick_wait()   # 0x447854: 清除时结束本帧
			"overlay":
				bt.overlay_fx(int(st.sub))
			"target_ghosts":
				for t in targets:
					if t and t.actor:
						bt.target_ghosts(t)
			"variant":
				caster.variant = int(st.v)   # 四首木甲: 头部转盘转到第 v 个头 (0x43dba7)
				if caster.actor:
					caster.actor.set_variant(int(st.v))
			"end_action":
				bt.end_action(atk_owner)
				break
			"reset_facing":
				# 0x448783: 0x431a65(0, 我方 180 / 敌方 0, 0, 0) —— 逐帧转回 (不是立即)
				bt.turn_unit(caster, 180.0 if caster.party else 0.0)
			"play_motion":
				var grp: Array = []
				match int(st.who):
					0:
						grp = targets.duplicate()
					1:
						grp = [caster]
					_:
						grp = bt.alive(false)
				for g in grp:
					if g and g.actor and g.actor.has_pose(int(st.pose)):
						g.actor.play(int(st.pose))
			"reflect":
				caster.reflect = true
			"music":
				if bt.field and bt.field.has_method("play_music_track"):
					bt.field.play_music_track(int(st.track), 0)
			"overlay_a":
				# 0x3ee (呼风唤雨) → 0x445c4b: 建 400 粒子的雨线系统 (0x9259fc), 战斗结束才拆; 旗标 21 未置位时循环播音效 491
				var oa: Array = st.args
				bt.rain_start(int(oa[0]), int(oa[1]))
			"sound_ctl":
				# 0x3f3 (百佌剑气) → 0x4be9fc(4, 1, 0): 音乐播放列表模式清 0, 正在播的曲子淡出步长 = 整个音量 (立刻停)
				Game.stop_music(0.0)
			"shake":
				bt.cam.shake(int(st.on) != 0)
			"anim_pause":
				var pa: FieldActor = caster.figure if (st.get("fig", false) and caster.figure) else caster.actor
				if pa:
					if int(st.on):
						pa.hold_at(int(pa.pose_tick))
					else:
						pa.resume_anim()
			"units_alpha":
				_units_alpha(st)
			"face_target":
				if targets.size() and targets[0].actor and caster.actor:
					caster.actor.face_point(targets[0].actor.gpos)
			"afterimage":
				_afterimage_set(st)
			"trail":
				_trail_set(st)
			"sound":
				Game.play_sound(int(st.id))
			"tint":
				bt.tint_to(st)
			"chant_release":
				caster.chant_atk = int(st.atk)
	caster = atk_owner
	if pending > 0.0:
		await _wait(pending)
	# 补结算
	for t in targets:
		if not settled.has(t):
			_settle(t, "d")
	# 跳回原位
	if caster.actor and caster.actor.gpos.distance_to(caster.home) > 5.0:
		# 默认跳回动作 0x39; 若它不在本体模型组里 (云狐 ACT 11 的 0x39 是法术模型组, 会变成另一种形态) 改用 0x3c
		var back := 0x39
		var ps: Dictionary = caster.actor.meta.get("poses", {})
		var g0 := int(ps.get("0", {}).get("g", 0))
		if not ps.has(str(back)) or int(ps[str(back)].get("g", 0)) != g0:
			back = 0x3c if ps.has("60") and int(ps["60"].get("g", 0)) == g0 else 0
		await _move({"to": "home", "pose": back})
	if caster.actor:
		caster.actor.set_facing(caster.facing)
	finished.emit()


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _wait(t: float) -> void:
	var acc := 0.0
	while acc < t:
		await get_tree().process_frame
		acc += get_process_delta_time()


func _physical() -> bool:
	return int(act.get("kind", 0)) == 1 or act.get("_normal", false)


func _result(t: BattleUnit) -> int:
	if not results.has(t):
		results[t] = Formula.roll_hit(caster, t, act, _physical(), 1)
	return int(results[t])


## 敌方施术时, 按我方视角编写的偏移 z 取反 (施术者面朝 −Z)
func _side_sign() -> float:
	return 1.0 if caster.party else -1.0


## 招式脚本里的回原位动作在部分角色上不存在 (云狐 ACT 11 没有 0x39 / 58): 改用后空翻 0x3c, 再没有就站立
const POSE_FALLBACK := {0x39: 0x3c, 58: 0x3c}


## 云狐 (带车芸本体 figure 的单位): ACT 11 里有些动作指向别的模型组 —— 23/24/57 狐人 (MGC00275/276/278)、58/61/62 机关鸟 (MGC00270…)。
## 车芸用道具 (动作 23) 等是车芸本人做的, 云狐不能跟着变形: 这类动作只给车芸本体播, 云狐回待机 (移动类退回后空翻 0x3c)
func _off_body(a: FieldActor, pose: int) -> bool:
	if caster.figure == null or a == null or not a.has_pose(pose):
		return false
	var ps: Dictionary = a.meta.get("poses", {})
	return int(ps.get(str(pose), {}).get("g", 0)) != int(ps.get("0", {}).get("g", 0))


func _play(pose: int) -> float:
	var a := caster.actor
	var fig_pose := pose
	if _off_body(a, pose):
		pose = 0x3c if pose in [0x39, 58] else 14
	if a and not a.has_pose(pose):
		var fb: int = POSE_FALLBACK.get(pose, 0)
		pose = fb if a.has_pose(fb) else 0
	if a == null or not a.has_pose(pose):
		return 0.0
	a.play(pose)
	# 车芸本体是独立的单位 (ObjDATA #11), 原版 set_pose (0x431787) 只写执行者自己的 +0x19be, 移动状态的默认动作也只给移动的单位:
	# 云狐的动作本体不跟 —— 以前每个动作都给本体也播一份, 云狐冲刺 / 跑回 (28 / 29, 循环) 后只有云狐回待机,
	# 本体一直原地跑 (用户反馈)。只有云狐做不了、改由本体做的动作 (道具 23 等, 见 _off_body) 才给本体播
	if fig_pose != pose and caster.figure and caster.figure.has_pose(fig_pose):
		caster.figure.play(fig_pose)
	var length := 0.0 if a.pose_loop else float(a.pose_len) * TICK
	var sl: Dictionary = _slots[0]
	sl.marks = a.meta.poses[str(pose)].get("marks", [])
	sl.actor = a
	if fig_pose != pose and caster.figure and caster.figure.has_pose(fig_pose):
		# 动作由车芸本体做: 命中时刻 / 时长按本体的动作
		sl.marks = caster.figure.meta.poses[str(fig_pose)].get("marks", [])
		sl.actor = caster.figure
		length = float(caster.figure.pose_len) * TICK
	sl.done = {}
	return length


## 模式 1 (set_actor_mode 1) 的动作: 只给车芸本体播, 不打断云狐正在做的动作和它的命中记号
## (例: 云狐普攻 1101 — 云狐播 17 咬两口, 同时车芸本体播 14 备战)
func _play_fig(pose: int) -> float:
	var f := caster.figure
	if not f.has_pose(pose):
		return 0.0
	f.play(pose)
	var sl: Dictionary = _slots[1]
	sl.marks = f.meta.poses[str(pose)].get("marks", [])
	sl.actor = f
	sl.done = {}
	return float(f.pose_len) * TICK


## ATK 0x37 / 0x7d / 0x84 / 0x85: 大招时把旁观的单位淡出 (结束时脚本自己淡入; 漏了的在招式结束时补回)
var _faded := {}


func _units_alpha(st: Dictionary) -> void:
	# set_units_alpha (0x37, exe 0x44ab88) 各组 (逆向确认; 已倒的单位都跳过):
	#   1 = 除目标外全部        2 = 除施术者外全部 (目标也淡)    3 = 除施术者和目标外全部
	#   4 = 目标对面那一方 (除施术者)    5 = 施术者对面那一方    6 = 第一个目标对面那一方    7 = 施术者对面那一方 (除目标)
	#   我方的护驾 (AI 召唤物): 4–7 组不动; 1 / 3 组淡入时不动 (护驾平时只在行动时现身, +0x19f0 = 0)
	#   车芸本体: 云狐是施术者或目标时跟着云狐 (不单独淡)
	var on := int(st.on) != 0
	var g := str(st.group)
	var t0: BattleUnit = targets[0] if targets.size() else null
	var yunhu_in := caster.figure != null or targets.any(func(t): return t and t.figure != null)
	var sel: Array = []
	for u in bt.units:
		# 0x84 / 0x85 (0x448508) 只看槽位有没有单位 (0x43a305: +0x1968 ≠ 0), 倒下的也算; 其他分组按 0x44ab88 的条件跳过
		if u == null or u.actor == null or (u.dead and g != "type"):
			continue
		var is_fig: bool = u.absent   # 车芸本体 (不参战的附属单位, 在我方槽位)
		if is_fig and yunhu_in:
			continue
		var party: bool = u.party or is_fig
		var ok := false
		match g:
			"targets":   # 0x7d: 每个目标
				ok = targets.has(u)
			"type":      # 0x84 / 0x85: 该类型的全部单位
				ok = u.id == int(st.type) or (int(st.type) == 11 and party and u.member == 1 and not u.summon)
			"1":
				ok = not targets.has(u) and not (party and u.summon and not on)
			"2":
				ok = u != caster
			"3":
				ok = u != caster and not targets.has(u) and not (party and u.summon and not on)
			"4":
				ok = t0 != null and party != t0.party and u != caster and not (party and u.summon)
			"5":
				ok = party != caster.party and not (party and u.summon)
			"6":
				ok = t0 != null and party != t0.party and not (party and u.summon)
			"7":
				ok = party != caster.party and not targets.has(u) and not (party and u.summon)
		if ok:
			sel.append(u)
	# 0x434947: 淡出 = 透明度每 tick 减「速度」到 0 后保持隐藏; 淡入 = 从全透明开始每 tick 加「速度」到 255; 255 = 瞬间
	var spd := float(st.speed)
	var dur := 0.0 if spd >= 255.0 or spd <= 0.0 else ceilf(255.0 / spd) * TICK
	for u in sel:
		if on:
			_fade_actor(u.actor, 1.0, dur)
			_faded[u] = true
		else:
			_fade_actor(u.actor, 1.0, 0.0)
			_fade_actor(u.actor, 0.0, dur)
			_faded.erase(u)


func _fade_actor(a: Node3D, tr: float, dur: float) -> void:
	for mi in a.find_children("*", "GeometryInstance3D", true, false):
		var g := mi as GeometryInstance3D
		if dur <= 0.0:
			g.transparency = tr
		else:
			bt.create_tween().tween_property(g, "transparency", tr, dur)


func _restore_faded() -> void:
	for u in _faded:
		if is_instance_valid(u.actor) and not u.dead:
			_fade_actor(u.actor, 0.0, 0.2)
	_faded.clear()


## ATK 0x71 / 0x94 条件跳转
func _branch_true(st: Dictionary) -> bool:
	var who: Array
	match str(st.who):
		"caster":
			who = [caster]
		"target":
			who = targets.slice(0, 1)
		_:
			who = targets.filter(func(t): return not t.dead)
	for u in who:
		if u == null:
			continue
		match str(st.cond):
			"party":
				if u.party:
					return true
			"summon":
				if u.summon:
					return true
			"yunhu":
				if u.party and u.member == 1 and not u.summon:
					return true
	return false


var cam_instant := false   # [0x907df4]: 0 = 镜头指令等到位 (默认)


# ---------------- 残影 (ATK 0x36) / 武器拖尾 (ATK 0x3b) ----------------


## 残影 (0x36 set_afterimage → 0x434a32, 生成 0x43e757, 绘制 / 淡出 0x48fde0, 逆向确认):
##   参数 (开, 间隔 N, 衰减 D, A, R, G, B) 存在单位上 (招式结束不清; 关 = 全部清 0, 不再生成, 已有的照常淡完)。
##   当前动作帧号 % N == 0 的帧复制一个定格分身 (动作状态、位置、朝向); 分身用原贴图 × (R,G,B), 半透明 (混合 2), alpha 从 A 起每帧 −D, ≤ 0 删除
func _afterimage_set(st: Dictionary) -> void:
	var ai: Afterimage = bt.afterimages.get(caster)
	if ai == null:
		ai = Afterimage.new()
		ai.unit = caster
		ai.bt = bt
		bt.afterimages[caster] = ai
		bt.world_node().add_child(ai)
	var g: Array = st.args
	var c: Array = st.argb
	if st.on:
		ai.every = int(g[0])
		ai.fade = int(g[1])
		ai.col = Color8(int(c[1]), int(c[2]), int(c[3]), int(c[0]))
	else:
		ai.every = 0
		ai.fade = 0


class Afterimage extends Node:
	var unit: BattleUnit
	var bt: Battle
	var every := 0
	var fade := 0
	var col := Color.WHITE
	var _acc := 0.0
	var _ghosts: Array = []   # [节点, 材质表, alpha (0..255), 每帧衰减]

	func _process(delta: float) -> void:
		_acc += delta
		while _acc >= AtkRunner.TICK:
			_acc -= AtkRunner.TICK
			var a: FieldActor = unit.actor if unit else null
			# 帧号 = 播放器 +0xb0 (每读一个帧记录 +1, 到最后一帧就不再加, 0x41d85d / 0x41d872); 不循环的动作播完后停在最后一帧
			var fr := int(a.pose_tick) if a else 0
			if a and not a.pose_loop and a.pose_len > 0:
				fr = mini(fr, a.pose_len - 1)
			if every > 0 and a and fr % every == 0:
				_spawn(a)
			# 绘制 / 衰减 0x48fde0 不是每帧一次: 它在单位绘制 0x43258e → 0x43e757 末尾调用, 每帧按单位列表 (0x908468, 共 [0x925250] 个)
			# 每个单位调一次 (空槽、ACT 类型 ≠ 0 的跳过)。每次调用把全部残影用当前 alpha 画一遍 (混合 2), 再减衰减值, ≤ 0 删除。
			# 所以一帧里每个分身叠画 K 次、衰减 K 次 (K = 单位数); 叠画后的透明度 = 1 − Π(1 − aᵢ)
			var k_units := bt.afterimage_units()
			var keep: Array = []
			for gh in _ghosts:
				if int(gh[2]) <= 0:   # 上一帧最后一次调用减到 ≤ 0: 那一帧已经画过, 现在删
					(gh[0] as Node).queue_free()
					continue
				var aa := int(gh[2])
				var t := 1.0
				for _k in k_units:
					if aa <= 0:
						break
					t *= 1.0 - float(aa) / 255.0
					aa -= int(gh[3])   # 衰减值在生成时复制进分身 (0x43e757 → 分身 +0x134), 之后「关」掉残影不影响已有分身
				gh[2] = aa
				for m in gh[1]:
					(m as StandardMaterial3D).albedo_color.a = 1.0 - t
				keep.append(gh)
			_ghosts = keep

	func _spawn(a: FieldActor) -> void:
		var r: Array = AtkRunner.bake_ghost(a, bt.world_node(), col)
		var ghost: Node3D = r[0]
		var mats: Array = r[1]
		_ghosts.append([ghost, mats, int(col.a8), fade])


## 武器拖尾 (0x3b weapon_trail → 0x434aed, 绘制 0x43e27c → 0x49019c / 0x490223 / 0x49028e, 逆向确认):
##   参数 (强度 A, R, G, B, 衰减 L) 存在单位上 (+0x19d8 = 1 后一直生效, 招式结束也不清); 每帧从武器挂点 21 / 22 (和 23 / 24) 取两点加一节,
##   这一节 alpha = A; 每帧画的时候每一节 alpha −= L, 超出 1..255 就删 —— L 是每帧减的透明度, 不是长度。相邻两节之间画四边形,
##   整节同一个 alpha, 无贴图, 加法混合。「关」= A 为 0: 新节一出现就被删, 旧节照常淡完
func _trail_set(st: Dictionary) -> void:
	var tr: WeaponTrail = bt.trails.get(caster)
	if tr == null:
		tr = WeaponTrail.new()
		tr.unit = caster
		bt.trails[caster] = tr
		bt.world_node().add_child(tr)
	var c: Array = st.rgb
	tr.col = Color(c[0] / 255.0, c[1] / 255.0, c[2] / 255.0)
	tr.a = int(st.alpha)
	tr.fade = int(st.len)
	tr.on = true


## 把角色当前姿势烘成一份静态分身 (残影 0x43e757 / 目标虚影 0x436911 共用): 贴图 × col, 半透明, 不写深度
static func bake_ghost(a: FieldActor, parent: Node, col: Color) -> Array:
	var ghost := Node3D.new()
	parent.add_child(ghost)
	var mats: Array = []
	for mi in a.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if not m.is_visible_in_tree() or m.mesh == null:
			continue
		var baked: Mesh = null
		if m.skin and m.get_node_or_null(m.skeleton) is Skeleton3D:
			baked = m.bake_mesh_from_current_skeleton_pose()
		if baked == null:
			baked = m.mesh
		var g := MeshInstance3D.new()
		g.mesh = baked
		ghost.add_child(g)
		g.global_transform = m.global_transform
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for si in baked.get_surface_count():
			var src := m.get_active_material(si) as StandardMaterial3D
			var gm := StandardMaterial3D.new()
			gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			gm.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
			gm.cull_mode = BaseMaterial3D.CULL_DISABLED
			if src:
				gm.albedo_texture = src.albedo_texture
			gm.albedo_color = col
			g.set_surface_override_material(si, gm)
			mats.append(gm)
	return [ghost, mats]


class WeaponTrail extends MeshInstance3D:
	var unit: BattleUnit
	var on := false
	var col := Color.WHITE
	var a := 0
	var fade := 0
	var nodes: Array = []   # [点 1, 点 2, alpha]
	var _acc := 0.0
	var _im := ImmediateMesh.new()

	func _ready() -> void:
		mesh = _im
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.vertex_color_use_as_albedo = true
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		material_override = m

	func _process(delta: float) -> void:
		_acc += delta
		while _acc >= AtkRunner.TICK:
			_acc -= AtkRunner.TICK
			if on and unit and unit.actor:
				for pair in AtkRunner.weapon_ends(unit.actor):
					nodes.append([pair[0], pair[1], a])
					if OS.get_cmdline_user_args().has("--trace-trail"):
						print("TRAIL unit=%s gpos=%s p1=%s p2=%s held=%s" % [unit.name, str(unit.actor.gpos.round()), str((pair[0] * 100.0).round()), str((pair[1] * 100.0).round()), str(unit.actor._held_node.get_path()) if is_instance_valid(unit.actor._held_node) else "-"])
			_im.clear_surfaces()
			if nodes.size() >= 2:
				_im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
				for k in range(1, nodes.size()):
					var n0: Array = nodes[k - 1]
					var n1: Array = nodes[k]
					var c := Color(col.r, col.g, col.b, clampf(float(n1[2]) / 255.0, 0.0, 1.0))
					for v in [n0[0], n0[1], n1[0], n0[1], n1[1], n1[0]]:
						_im.surface_set_color(c)
						_im.surface_add_vertex(v)
				_im.surface_end()
			var keep: Array = []
			for n in nodes:
				n[2] = int(n[2]) - fade
				if int(n[2]) > 0 and int(n[2]) <= 255:
					keep.append(n)
			nodes = keep


## 手持武器模型上的挂点对 (21, 22) 和 (23, 24) 的世界坐标 (0x419e3d: 段标志高字节 == 编号 + 1; 拖尾传 20/21、22/23)
static func weapon_ends(a: FieldActor) -> Array:
	if a == null or not is_instance_valid(a._held_node):
		return []
	var out: Array = []
	for pr in [["marker21_", "marker22_"], ["marker23_", "marker24_"]]:
		var pts: Array = []
		for nm in pr:
			var found: Vector3 = Vector3.INF
			for sk in a._held_node.find_children("*", "Skeleton3D", true, false):
				var s2 := sk as Skeleton3D
				for bi in s2.get_bone_count():
					if s2.get_bone_name(bi).begins_with(nm):
						found = s2.global_transform * s2.get_bone_global_pose(bi).origin
			if found == Vector3.INF:
				for nd in a._held_node.find_children(nm + "*", "Node3D", true, false):
					found = (nd as Node3D).global_position
			if found != Vector3.INF:
				pts.append(found)
		if pts.size() == 2:
			out.append(pts)
	return out


func _exit_tree() -> void:
	# 原版招式结束时不会把淡出的单位补回 (以前这里 0.2 秒补回, 是推测, 已删); 淡出状态只由 0x434947 / 单位重置 0x433ff0 改变
	_faded.clear()


## 施术者动作的 'd' / 'e' 记号 = 命中结算时刻
func _process(_delta: float) -> void:
	if caster == null or caster.actor == null:
		return
	for sl in _slots:
		var who: FieldActor = sl.actor if is_instance_valid(sl.actor) else null
		if who == null:
			continue
		for k in sl.marks.size():
			var m: Array = sl.marks[k]
			if str(m[1]) == "g" or sl.done.has(k):
				continue
			if who.pose_tick >= float(m[0]):
				sl.done[k] = true
				for t in targets:
					_settle(t, str(m[1]))


## ATK 0x76: 等施术者动作播到下一个 g 记号 (之后放特效); 没有记号就不等
func _wait_mark(mark: String, slot := 0) -> void:
	var sl: Dictionary = _slots[slot]
	var who: FieldActor = sl.actor if is_instance_valid(sl.actor) else caster.actor
	var target := -1.0
	for k in sl.marks.size():
		var m: Array = sl.marks[k]
		if str(m[1]) == mark and not sl.done.has("w%d" % k):
			sl.done["w%d" % k] = true
			target = float(m[0])
			break
	while target >= 0.0 and is_instance_valid(who) and who.pose_tick < target:
		await get_tree().process_frame


func _settle(t: BattleUnit, kind: String) -> void:
	if not settle:
		return
	if kind == "e":
		bt.hurt(t)
		return
	settled[t] = int(settled.get(t, 0)) + 1
	bt.apply_settle(atk_owner, t, act, _result(t), crit)
	# 多目标结算: 第一个目标沿用脚本的判定, 后面的目标重新判定 (0x437858 的怪癖)
	results.erase(t)


## 移动 (同技能预览): 跑 = 水平匀速 speed 单位/帧, 其余在动作时长内到达
func _move(st: Dictionary) -> void:
	# 原版移动 (逆向见 re/move_re.md, 每 tick 1/35 秒):
	#   run  (0x0E): 播 28, 目的地 = 目标 + 0x34 偏移 (世界轴, y = 施术者 y) 再沿移动方向退 100; 每 tick 前进「速度」(逐轴夹到目的地),
	#                移动前水平距离 ≤ 速度 + 5 就结束, 停在原地 (0x43b930)
	#   arc  (0x32 / 0x0F): 抛物线, 向上初速 v (0x32 = 参数, 0x0F = 10), 重力 1; T = 2v + (起点y − 终点y)/v;
	#                水平按 t/T 线性插值, y += v, v −= 1 (0x49597a)。0x32 起点 = 原位、终点同 run; 0x0F 起点 = 当前位置、终点 = 原位,
	#                落地后朝向 180 (我方) / 0 (敌方) (0x43bc91)
	#   dash (0x41 / 0x7F / 0x91 / 0x92): 回原位, 目的地 = 原位退 100, 每 tick 前进速度; 移动前距离 < 30 → 吸附到原位 (0x43be2b)
	#   播的动作是各移动状态的默认动作 (st.pose: 28 / 38 / 39 / 29 / 57 / 58), 不是 ATK set_pose 设的 (进入移动状态时被清掉)
	var fig: bool = st.get("fig", false) and caster.figure != null
	var a := caster.figure if fig else caster.actor
	if a == null:
		return
	var home: Vector3 = Battle.FIGURE_POS if fig else caster.home
	var mode := str(st.get("mode", "run"))
	var spd := float(st.get("speed", 40.0))
	var q := int(st.pose)
	var from := a.gpos
	var dest := home
	if str(st.to) == "target" and targets.size():
		var tp: Vector3 = targets[0].pos()
		var o: Array = st.get("offset", [0, 0, 0])
		var p := Vector3(tp.x + float(o[0]), from.y, tp.z + float(o[2]))
		var dir := Vector3(p.x - from.x, 0, p.z - from.z)
		if dir.length() > 0.001:
			a.face_point(p)
			dest = p - dir.normalized() * 100.0
		else:
			dest = p
	elif mode == "dash":
		var dir2 := Vector3(home.x - from.x, 0, home.z - from.z)
		if dir2.length() > 0.001:
			a.face_point(home)
			dest = home - dir2.normalized() * 100.0
	if mode == "run" and not fig:
		bt.aura_fade(caster, false, 20)   # 0x44709c: 跑动时首领光环以每帧 20 淡出
	if fig:
		_play_fig(q)
	elif a.has_pose(q):
		_play(q)
	elif a.has_pose(12):
		a.play(12)   # 没有这个默认动作的角色 (原版这种单位不会移动, 脚本会卡住): 用地图跑步动作代替, 不卡
	if mode == "arc":
		var start := home if str(st.to) == "target" else from
		var end := dest if str(st.to) == "target" else home
		var v := spd
		var tt := 2.0 * v + (start.y - end.y) / v
		var t := 0.0
		var y := start.y
		while true:
			await _tick_wait()
			var h := start.lerp(end, minf(t / tt, 1.0))
			y += v
			v -= 1.0
			t += 1.0
			if t >= tt and y <= end.y:
				a.set_game_pos(end, false)
				break
			if t > tt:
				t = tt
			a.set_game_pos(Vector3(h.x, y, h.z), false)
		if str(st.to) == "home":
			a.set_game_pos(home, false)
			a.set_facing(180.0 if (fig or caster.party) else 0.0)
		_move_done(a)
		return
	while true:
		var d := Vector2(dest.x - a.gpos.x, dest.z - a.gpos.z).length()
		if mode == "dash" and d < 30.0:
			a.set_game_pos(home, false)
			_move_done(a)
			return
		if mode != "dash" and d <= spd + 5.0:
			_move_done(a)
			return
		await _tick_wait()
		var step := Vector3(dest.x - a.gpos.x, 0, dest.z - a.gpos.z).normalized() * spd
		var np := a.gpos
		np.x = minf(np.x + step.x, dest.x) if step.x >= 0.0 else maxf(np.x + step.x, dest.x)
		np.z = minf(np.z + step.z, dest.z) if step.z >= 0.0 else maxf(np.z + step.z, dest.z)
		a.set_game_pos(np, false)


## 移动结束 (0x43bc1d / 0x43c01e / 0x43bc91): 状态归 0、+0x19be 清 0 → 显示待机动作 14 (跑步 28 是循环动作, 不切回会一直原地跑;
## 跑向目标后脚本紧接着的 set_pose 会在同一帧换掉它)
func _move_done(a: FieldActor) -> void:
	if a.has_pose(Battle.IDLE_POSE):
		a.play(Battle.IDLE_POSE)
	elif a.has_pose(0):
		a.play(0)
	if caster.figure and a == caster.figure:
		# 车芸本体移动结束 (0x43c01e / 0x43be04: +0x196a == 1 → 0x43203e): 朝向复位 (我方 180, 敌方 0), 动作 14
		a.set_facing(180.0 if caster.party else 0.0)


## 等一个原版 tick (1/35 秒)
var _tick_acc := 0.0


func _tick_wait() -> void:
	while _tick_acc < TICK:
		await get_tree().process_frame
		_tick_acc += get_process_delta_time()
	_tick_acc -= TICK


## 放特效 (同技能预览, 坐标为战斗场景坐标): 0x02 每个目标一个 / 0x04 后战场原点 / 0x03 施术者(挂点)→每个目标
func _spawn_fx(st: Dictionary) -> void:
	var key := "%d_%d" % [int(st.id), int(st.sub)]
	var off: Array = st.get("offset", [0, 0, 0])
	var o := Vector3(off[0], off[1], off[2])
	var sgn := _side_sign()
	var places: Array = []   # [位置 (游戏单位), 结算目标或 null]
	match str(st.at):
		"to_targets":
			var base := caster.pos()
			if st.has("origin_marker"):
				var mp: Variant = bt.marker_pos(caster, int(st.origin_marker))
				if mp != null:
					base = mp
			for t in (targets if targets.size() else [null]):
				var tp: Vector3 = t.pos() if t else base + Vector3(0, 0, 300 * sgn)
				var local := o
				if st.get("rotate", true):
					var f := (tp - caster.pos()) * Vector3(1, 0, 1)
					f = f.normalized() if f.length() > 0.01 else Vector3(0, 0, sgn)
					local = Vector3(f.z, 0, -f.x) * o.x + Vector3.UP * o.y + f * o.z
				else:
					local = Vector3(o.x, o.y, o.z * sgn)
				places.append([base + local, t])
		"field":
			# 0x04 + 0x02 (exe 0x448a54 → 0x448acb): 位置 = 战场原点 + 偏移 (世界轴); 只有施术者是护驾 (+0x19ec) 或 +0x19f0 置位的
			# 召唤物时 z 取反 (我方队员 +0x19f0 = 0, 0x430bd7), 敌人和我方都不翻转 (例 五雷咒 z = −375 劈我方那一侧)。
			# 整个目标表交给这一个特效 (0x9263cc), 特效里的 e / d 记号对每个目标生效, 不是只对第一个
			places.append([Vector3(o.x, o.y, -o.z if caster.summon else o.z), null])
		"caster":
			places.append([caster.pos() + Vector3(o.x, o.y, o.z * sgn), null])
		_:
			for t in targets:
				places.append([t.pos() + Vector3(o.x, o.y, o.z * sgn), t])
	for pl in places:
		var t: BattleUnit = pl[1]
		var cb := Callable()
		if t:
			cb = func(kind: String): _settle(t, kind)
		elif targets.size():
			cb = func(kind: String):
				for x in targets:
					_settle(x, kind)
		var basis := Basis() if caster.party else Basis(Vector3.UP, PI)
		if st.get("face", false) and t:
			# 0x4c: 特效按施术者 → 目标的方向摆 (默认是按阵营固定朝 ±Z; 斜着打时特效会歪, 例 顶击)
			var d := (t.pos() - caster.pos()) * Vector3(1, 0, 1)
			if d.length() > 1.0:
				basis = Basis(Vector3.UP, atan2(d.x, d.z))
		if not Fx.has(key) and bt.skill_testing:
			print("FXMISS %s atk=%d" % [key, int(act.get("atk_id", 0))])
		var node: Variant = Fx.spawn(bt.world_node(), key, bt.to_world(pl[0]), basis, bt.cam3d(), cb) if Fx.has(key) else null
		if node:
			if not fx.has(key):
				fx[key] = []
			fx[key].append(node)
