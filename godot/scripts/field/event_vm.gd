class_name EventVM
extends RefCounted
## 原版事件脚本解释器 (talks*.gll; exe 主循环 0x405fcd)。指令语义见 tools/disasm_script.py 的 OPS 表 (每条有处理函数地址)
## 代码来自 extracted/game/events/*.json (tools/export_game.py): [位置, 指令名, 操作数...], 跳转已换算成脚本内位置
## 坐标为地图 MAP 坐标 (游戏单位); 时间: wait 与 text 的显示时间单位 10 毫秒; 动作 / 移动 / 镜头按 35 帧/秒

const SYSTEM_ACTOR := 0xff02
## 对复刻没有可见效果的指令 (字距 / 行距、碰撞占位格、内部标志位等)
const IGNORED := ["nop", "set_anim_speed", "reset_anim_speed", "text_color",
	"script_begin", "script_end", "set_actor_flag_1a8", "set_actor_flag_1000",
	"set_self_flag_66d", "crossfade_speed", "window_skin", "reset_frame_rate"]

var field: Node
var eid := 0
var owner := SYSTEM_ACTOR
var code: Array = []
var at := {}                     # 位置 → 下标
var pc := 0
var caption := ""
var win_color := Color(10 / 255.0, 10 / 255.0, 10 / 255.0, 150 / 255.0)
var move_speed := 8.0
var cam_nowait := false
var cam_batch := false
var restore_snap := false        # 0x8c: 下一条 0x73 瞬间恢复
var music_fade := 0
var next_event := -1             # call_event 转入的事件
var stopped := false
var trace := false
var _steps := 0


func _init(f: Node, event_id: int, owner_actor := SYSTEM_ACTOR) -> void:
	field = f
	eid = event_id
	owner = owner_actor
	code = field.event_code(event_id)
	for i in code.size():
		at[int(code[i][0])] = i
	trace = OS.get_cmdline_user_args().has("--trace-events")


func _jump(pos: int) -> void:
	if at.has(pos):
		pc = at[pos]
	else:
		push_warning("事件 %d 跳转目标 %d 不在指令边界" % [eid, pos])
		stopped = true


func _wait_until(cond: Callable, timeout := 60.0) -> void:
	var t0 := Time.get_ticks_msec()
	while not stopped and is_instance_valid(field) and not field.aborted and not cond.call():
		if field.fast_forward():
			return
		await field.get_tree().process_frame
		if Time.get_ticks_msec() - t0 > timeout * 1000.0:
			push_warning("事件 %d @%d 等待超时" % [eid, int(code[pc - 1][0])])
			return


var wait_info := ""   # 自动通关看门狗诊断: 当前在等什么


func _sleep(sec: float) -> void:
	var t := 0.0
	while t < sec and not stopped and not field.fast_forward():
		await field.get_tree().process_frame
		t += field.get_process_delta_time()
		wait_info = "sleep t=%.2f/%.2f dt=%.4f in_tree=%s" % [t, sec, field.get_process_delta_time(), field.is_inside_tree()]
	wait_info = ""


func _actor(id: int) -> FieldActor:
	return field.actor(id)


func _cam_wait() -> void:
	if cam_nowait:
		if not cam_batch:
			await field.get_tree().process_frame
		return
	await _wait_until(func(): return field.cam.arrived(), 15.0)


func run() -> void:
	while not stopped and pc < code.size():
		var ins: Array = code[pc]
		pc += 1
		_steps += 1
		if _steps % 400 == 0:
			await field.get_tree().process_frame
		if trace:
			print("EV %d @%d t=%.1f %s" % [eid, int(ins[0]), Time.get_ticks_msec() / 1000.0, str(ins.slice(1))])
		await _exec(ins)
		if not is_instance_valid(field) or field.aborted or not field.is_inside_tree():
			stopped = true


func _exec(ins: Array) -> void:
	var op: String = ins[1]
	var a := ins.slice(2)
	if op not in ["end", "goto", "if_bond_ge_goto", "rinne_bond", "if_flag_goto", "if_not_flag_goto", "if_all_flags_goto", "if_any_flag_goto", "set_flag",
			"clear_flag", "if_actor_var_ge_goto", "if_actor_var_eq_goto", "if_item_goto", "if_money_ge_goto", "call_event"]:
		field.event_took_control = true   # 真正的演出 / 操作 (只做判断跳转的事件不打断主角动作)
	if op == "script_end" and eid == 7294 and int(ins[0]) == 178:
		# 原版 script_end (0x407974) 不结束脚本, 取指继续往下 (2126 等 9 个支线靠这个从前情接到选项)
		# 唯一例外: 7294 进曲沃城的分支后面紧跟「不能离开」分支, 落下去会把主角往离宫入口的坐标走
		# 原版字节里没找到停在这里的机制, 这一处是有意偏离, 未与原版对照
		stopped = true
		return
	if op in IGNORED:
		return
	match op:
		"data":
			_jump(int(a[0]))
		"end":
			stopped = true
		"goto":
			_jump(int(a[0]))
		"if_flag_goto":
			if State.test_flag(int(a[0])):
				_jump(int(a[1]))
		"if_not_flag_goto":
			if not State.test_flag(int(a[0])):
				_jump(int(a[1]))
		"if_all_flags_goto":
			if (a[0] as Array).all(func(f): return State.test_flag(int(f))):
				_jump(int(a[1]))
		"if_any_flag_goto":
			if (a[0] as Array).any(func(f): return State.test_flag(int(f))):
				_jump(int(a[1]))
		"set_flag":
			State.set_flag(int(a[0]), true)
		"clear_flag":
			State.set_flag(int(a[0]), false)
		"wait":
			await _sleep(int(a[0]) * 0.01)
		"window_color":
			win_color = Color(a[1] / 255.0, a[2] / 255.0, a[3] / 255.0, a[0] / 255.0)
		"set_caption":
			caption = field.person_name(int(a[0]))
		"text_char_spacing":
			Dialog.char_spacing = int(a[0])
		"text_line_spacing":
			Dialog.line_spacing = int(a[0])
		"text":
			field.dialog.show_text(int(a[0]) if int(a[0]) != 0 else 0xff01, a.slice(1, 10), str(a[10]), win_color, caption,
				Dialog.char_spacing, Dialog.line_spacing)
			caption = ""
		"wait_text":
			var who := int(a[0]) if int(a[0]) != 0 else 0xff01
			await _wait_until(func(): return not field.dialog.is_open(who), 3600.0)
		"close_text":
			field.dialog.close(int(a[0]))
		"menu_switch":
			var tg: Array = a[0]
			await _wait_until(func(): return field.dialog.windows.is_empty(), 3600.0)
			_jump(int(tg[clampi(field.dialog.last_choice, 0, tg.size() - 1)]))
		"random_goto":
			var tg2: Array = a[0]
			_jump(int(tg2[randi() % tg2.size()]))
		"set_act":
			var ac := _actor(int(a[0]))
			if ac:
				ac.set_act(int(a[1]))
			State.actor_rec(int(a[0])).act = int(a[1])
		"set_pose":
			var ac2 := _actor(int(a[0]))
			if ac2:
				ac2.clear_er()   # set_pose 先停掉挂点粒子 (0x4083cf → 0x46e16a)
				ac2.play(int(a[1]))
			State.actor_rec(int(a[0])).pose = int(a[1])
		"wait_anim":
			var ac3 := _actor(int(a[0]))
			if ac3:
				var fr := int(a[1])
				await _wait_until(func(): return ac3.anim_reached(fr), 30.0)
		"set_facing":
			var ac4 := _actor(int(a[0]))
			if ac4:
				ac4.set_facing(float(a[1]))
			State.actor_rec(int(a[0])).facing = float(a[1])
		"look_at":
			var ac5 := _actor(int(a[0]))
			var ac6 := _actor(int(a[1]))
			if ac5 and ac6:
				ac5.face_point(ac6.gpos)
		"set_move_speed":
			move_speed = float(a[0])
		"reset_move_speed":
			move_speed = 8.0
		"place_actor":
			field.place_actor(int(a[0]), Vector3(a[1], a[2], a[3]))
		"place_actor_map":
			field.place_actor_map(int(a[0]), int(a[1]), Vector3(a[2], a[3], a[4]))
		"walk_to":
			var ac7 := _actor(int(a[0]))
			if ac7:
				ac7.walk_to(Vector3(a[1], a[2], a[3]), move_speed)
		"move_to_follow_cam":
			var ac8 := _actor(int(a[0]))
			if ac8:
				ac8.walk_to(Vector3(a[1], a[2], a[3]), move_speed)
				field.cam.set_follow(ac8, Vector3(0, a[4], 0))
		"wait_move":
			var ac9 := _actor(int(a[0]))
			if ac9:
				await _wait_until(func(): return not ac9.is_moving(), 60.0)
				if field.cam.follow == ac9 and field.cutscene:
					field.cam.follow = null
		"hide_actor":
			field.set_actor_hidden(int(a[0]), true)
		"show_actor":
			field.set_actor_hidden(int(a[0]), false)
		"fade_actor_alpha":
			var ac10 := _actor(int(a[0]))
			if ac10:
				ac10.fade_alpha(int(a[1]), int(a[2]), int(a[3]))
		"wait_actor_fade":
			var ac11 := _actor(int(a[0]))
			if ac11:
				await _wait_until(func(): return not ac11.fading(), 20.0)
		"set_actor_event":
			var ac12 := _actor(int(a[0]))
			if ac12:
				ac12.event_id = int(a[1])
			State.actor_rec(int(a[0])).event = int(a[1])
		"set_actor_ai":
			var ac13 := _actor(int(a[0]))
			if ac13:
				ac13.ai = int(a[1])
			State.actor_rec(int(a[0])).ai = int(a[1])
		"change_map":
			if int(a[5]) > 0:
				field.cam.view_dist = float(a[5])   # 第 6 个参数 = 视距 [0x4e4900]
			await field.change_map(int(a[0]), Vector3(a[1], a[2], a[3]), float(a[4]))
			field.minimap.set_floor(1)   # 0x406e41: 换图后回到第 1 层
		"set_floor":
			field.minimap.set_floor(int(a[0]))
		"fade":
			await field.fade(int(a[0]), Color(a[1] / 255.0, a[2] / 255.0, a[3] / 255.0), int(a[4]), int(a[5]))
		"camera_control":
			field.cutscene = int(a[0]) == 1
			State.set_flag(8051, field.cutscene)
		"cutscene_begin":
			field.cutscene = true
			State.set_flag(8051, true)
		"cutscene_end":
			field.cutscene = false
			State.set_flag(8051, false)
		"camera_batch_begin":
			cam_batch = true
		"camera_batch_end":
			cam_batch = false
		"camera_mode":
			for ch in 3:
				field.cam.set_mode(ch, int(a[0]))
		"camera_target_speed":
			field.cam.set_speed(0, float(a[0]))
		"camera_angle_speed":
			field.cam.set_speed(1, float(a[0]))
		"camera_distance_speed":
			field.cam.set_speed(2, float(a[0]))
		"camera_nowait":
			cam_nowait = true
		"camera_wait":
			cam_nowait = false
		"camera_target":
			field.cam.set_target(Vector3(a[0], a[1], a[2]))
			await _cam_wait()
		"camera_angle":
			field.cam.set_angles(float(a[0]), float(a[1]), float(a[2]), int(a[3]))
			await _cam_wait()
		"camera_distance":
			field.cam.set_distance(float(a[0]))
			await _cam_wait()
		"camera_target_actor":
			var ac14 := _actor(int(a[1]))
			if ac14:
				field.cam.set_mode(0, int(a[0]))
				field.cam.set_target(ac14.gpos + Vector3(0, a[2], 0))
		"camera_zoom":
			field.cam.zoom_kt = maxf(float(a[2]), 1.0)
			if int(a[0]) == 1:
				field.cam.zoom_k = field.cam.zoom_kt
		"wait_camera":
			await _wait_until(func(): return field.cam.arrived(), 15.0)
		"camera_restore":
			await field.camera_restore(restore_snap)
			restore_snap = false
		"set_0073_mode":
			restore_snap = true
		"play_video", "video_nowait":
			if op == "play_video":
				await field.play_video(str(a[0]))
		"play_music":
			field.play_music_track(int(a[0]), music_fade)
		"set_map_music":
			State.map_music[int(a[0])] = [int(a[1]), int(a[2]), int(a[3]), int(a[4])]
		"music_control":
			if int(a[0]) == 1:
				field.play_map_music(music_fade)
			else:
				Game.stop_music(maxf(music_fade * 0.01, 0.3))
			music_fade = 0
		"set_music_fade":
			music_fade = int(a[0])
		"play_sound":
			Game.play_sound(int(a[0]))
		"set_expression":
			var ae := _actor(int(a[0]))
			if ae:
				ae.set_expression(int(a[1]), int(a[2]))
		"set_weapon_model":
			field.set_weapon(int(a[0]), int(a[1]), int(a[2]), int(a[3]))
		"add_ani":
			field.add_ani(int(a[0]), int(a[1]), Vector3(a[2], a[3], a[4]))
		"add_ani_on_actor", "add_actor_effect":
			var aa: FieldActor = _actor(int(a[0])) if int(a[0]) != 0xff01 else field.player
			if aa:
				field.add_ani(int(a[1]), int(a[2]), aa.gpos, null, 0.0, aa if op == "add_actor_effect" else null)
		"add_ani_move":
			field.add_ani(int(a[7]), int(a[8]), Vector3(a[0], a[1], a[2]), Vector3(a[3], a[4], a[5]), float(a[6]))
		"add_ani_to_actor":
			var at := _actor(int(a[3]))
			field.add_ani(int(a[5]), int(a[6]), Vector3(a[0], a[1], a[2]), at, float(a[4]))
		"del_ani":
			field.del_ani(int(a[0]), int(a[1]))
		"del_ani_wait":
			await field.del_ani(int(a[0]), int(a[1]), true)
		"wait_ani":
			await _wait_until(func(): return field.ani_done(int(a[0]), int(a[1])))
		"narration_mode":
			field.narration_mode(int(a[0]) == 1)
		"screen_shake":
			field.shake = int(a[0]) != 0
		"call_event":
			next_event = int(a[0])
			stopped = true
		"start_battle":
			await field.start_battle(int(a[0]), true)
		"if_near_actor_goto":
			var ac15 := _actor(int(a[0]))
			if ac15 and field.player and Vector2(ac15.gpos.x - field.player.gpos.x, ac15.gpos.z - field.player.gpos.z).length() <= float(a[1]):
				_jump(int(a[2]))
		"set_trigger":
			State.set_trigger(int(a[0]), int(a[1]) != 0)  # 0 = 禁用 (事件常用 set_trigger(自己, 0) 只触发一次)
		"heal_member":
			field.heal_member(int(a[0]), int(a[1]), int(a[2]), int(a[3]))
		"add_money":
			State.add_res("money", int(a[0]))
		"if_money_ge_goto":
			if State.money >= int(a[0]):
				_jump(int(a[1]))
		"give_item":
			State.give_item(int(a[0]), int(a[1]))
		"take_item":
			State.give_item(int(a[0]), -int(a[1]))
		"if_item_goto":
			if State.item_count(int(a[0])) >= int(a[1]):
				_jump(int(a[2]))
		"add_wood":
			State.add_res("wood", int(a[0]))
		"add_metal":
			State.add_res("metal", int(a[0]))
		"add_coal":
			State.add_res("coal", int(a[0]))
		"add_tech_points":
			State.add_res("tech", int(a[0]))
		"set_actor_var":
			State.set_actor_var(int(a[0]), int(a[1]), int(a[2]))
		"add_actor_var":
			State.set_actor_var(int(a[0]), int(a[1]), State.actor_var(int(a[0]), int(a[1])) + int(a[2]))
		"if_actor_var_ge_goto":
			if State.actor_var(int(a[0]), int(a[1])) >= int(a[2]):
				_jump(int(a[3]))
		"if_actor_var_eq_goto":   # 0x131: 角色变量 == 比较值则跳转
			if State.actor_var(int(a[0]), int(a[1])) == int(a[2]):
				_jump(int(a[3]))
		"clear_actor_flag3":   # 0x26: 清标志 0x8 → 重新画出模型
			var ac3 := _actor(int(a[0]))
			if ac3:
				ac3.flags &= ~0x8
		"set_actor_flag3":   # 0x25: 置角色标志 0x8 (不画模型, 0x477fda), 同时释放角色身上的特效
			var af := _actor(int(a[0]))
			if af:
				af.flags |= 0x8
				af.clear_er()   # 0x40667b → 0x46e16a
			field.clear_actor_anis(int(a[0]))
		"set_collision":   # 0x2d (0x406a11, 逆向确认): w = 0 → 置 0x40 (移动不贴地面、不查阻挡, 0x468a89), 否则清 0x40
			# (另把网格格子中心记进实例, 只在事件框触发时用到; 格子占用表从没写入过, 是死代码)
			var ac := _actor(int(a[0]))
			if ac:
				ac.flags = (ac.flags | 0x40) if int(a[1]) == 0 else (ac.flags & ~0x40)
		"set_actor_flag_80":   # 0x97 (0x408ca2): 置 / 清标志 0x80 (和 0x40 一起时不打地面下射线, 见 field._map_move)
			var a80 := _actor(int(a[0]))
			if a80:
				a80.flags = (a80.flags | 0x80) if int(a[1]) else (a80.flags & ~0x80)
		"set_ghost_move":   # 0x2e: 沿路径移动时不做碰撞 (我们的路径移动本来就不碰撞), 记下标志
			var ag := _actor(int(a[0]))
			if ag:
				ag.flags = (ag.flags | 0x4) if int(a[1]) else (ag.flags & ~0x4)
		"actor_path_to":   # 0x89: 给角色加一段走到 (x,y,z) 的路径
			var ap := _actor(int(a[0]))
			if ap:
				ap.walk_to(Vector3(a[1], a[2], a[3]), move_speed)
		"wait_crossfade":   # 0x55: 原版等待的标志从不置位, 立即通过
			pass
		"camera_type":   # 0x49 (0x45faf9): 1 普通跟随 / 4 固定机位 (见 OrigCamera.set_type)
			field.cam.set_type(int(a[0]))
		"free_models":   # 0x6c: 释放模型缓存
			Game.clear_glb_cache()
			Game._glb_order.clear()
		"set_event_active":   # 0x36: 旗标 8052「事件进行中」
			if int(a[0]):
				State.set_flag(8052)
			else:
				State.set_flag(8052, false)
		"remove_actor_effect":   # 0x31: 移除角色身上 (ACT,QQ) 的特效
			field.clear_actor_anis(int(a[0]), "%d_%d" % [int(a[1]), int(a[2])])
		"sub_money":   # 0x101
			State.money = maxi(State.money - int(a[0]), 0)
		"add_member_magic_def":   # 0x103: 第 n 个队员的仙防增减
			var mi := int(a[0])
			var mm: int = int(State.party[mi]) if mi < State.party.size() else mi + 1
			State.member(mm).mdef = maxi(int(State.member(mm).mdef) + int(a[1]), 0)
		"if_monster_room_goto":   # 0x122 (0x407c05 → 0x4b1017): 天书住房容量 > 居民数 才跳 (没开过天书 = 没有住房 = 没空位)
			if MenuTianshu.capacity_of(State.ts_houses) > State.ts_residents.size():
				_jump(int(a[0]))
		"add_monster":   # 0x123 (0x40b54d): add_resident — 插到天书居民链表头 (闲置) + 图鉴认识度 +10
			State.ts_residents.push_front({"id": int(a[0]), "house": 0})
			Fame.add_monster(int(a[0]), 10)
		"if_has_monster_goto":   # 0x125 (0x4b11c8): 居民链表里有这个 ID (不含流放名单)
			if State.ts_residents.any(func(r): return int(r.id) == int(a[0])):
				_jump(int(a[1]))
		"set_registry_swdonline":   # 0xcd: 原版写注册表, 不需要
			pass
		"wait_turn":   # 0x77: 等平滑转身结束 (我们的转身是立即的)
			pass
		"learn_skill":   # 0xac: 队员习得技能
			var sk: Array = State.skills.get(int(a[0]), [])
			if not sk.has(int(a[1])):
				sk.append(int(a[1]))
			State.skills[int(a[0])] = sk
		"replace_item":   # 0xf9: 背包有旧物品就换成新的; 否则嬴诗的武器是旧物品就换装; 都没有就直接给新物品
			var old := int(a[0])
			var nw := int(a[1])
			var eq2: Array = State.equip.get(2, [])
			if int(State.items.get(old, 0)) > 0:
				State.give_item(old, -1)
				State.give_item(nw, 1)
			elif eq2.size() and int(eq2[0]) == old:
				eq2[0] = nw
			else:
				State.give_item(nw, 1)
		"weather_effect":   # 0x6b: 全屏粒子 (雪 / 雾, 资源 8001)
			field.set_weather(int(a[0]) != 0)
		"game_clear_save", "return_to_title":
			if op == "game_clear_save":
				State.save_carry()   # 轮回篇: 记下要继承的进度 (原版此处写 fame.dat、置通关旗标)
			field.abort_to_title()
			stopped = true
		# ---- 轮回篇 (同人原创指令, 只在 res://rinne 的补丁里用) ----
		"rinne_bond":   # [羁绊 shi/huan/yin, 加减]
			State.add_bond(str(a[0]), int(a[1]))
		"if_bond_ge_goto":   # [羁绊, 值, 目标]
			if State.bond(str(a[0])) >= int(a[1]):
				_jump(int(a[2]))
		"deja":   # 既视感: 画面褪色 + 白光闪一下 [秒数]
			await field.deja_vu(float(a[0]) if a.size() else 1.6)
		"open_shop":
			await field.open_shop(a[0])
		"open_save_menu":
			await field.open_save_menu()
		"set_battle_countdown":   # 0xa1 (0x4091c7): 连续战斗剩余场数 → 全局变量 1, 7 个有效地图, 旗标 18
			State.regs[1] = int(a[0])
			State.countdown_maps = a.slice(1, 8).map(func(x): return int(x))
			State.set_flag(18)
		_:
			if not field.warned_ops.has(op):
				field.warned_ops[op] = true
				push_warning("事件指令未实现: %s (事件 %d)" % [op, eid])
