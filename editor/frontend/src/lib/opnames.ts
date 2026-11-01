// 事件指令的中文名 (只是显示用的称呼; 指令的含义见指令表说明 extracted/scripts/opcodes.md, 由解释器逆向)
export const OP_LABEL: Record<string, string> = {
  text: "对白", window_color: "对话框颜色", text_char_spacing: "字距", text_line_spacing: "行距", wait_text: "等对白结束",
  set_pose: "播放动作", clear_flag: "清旗标", reset_move_speed: "恢复移动速度", set_flag: "设旗标", set_expression: "换表情",
  script_begin: "剧情开始", script_end: "剧情结束", play_sound: "音效", if_flag_goto: "如果旗标→跳转", wait_anim: "等动作播完",
  set_caption: "对话框标题", camera_control: "镜头控制", goto: "跳转", camera_mode: "镜头模式", camera_angle: "镜头角度",
  camera_distance: "镜头距离", fade: "淡入淡出", camera_target: "镜头注视点", hide_actor: "隐藏角色", set_facing: "设朝向",
  if_near_actor_goto: "如果靠近角色→跳转", camera_zoom: "镜头缩放", look_at: "看向角色", wait: "等待", if_actor_var_ge_goto: "如果角色变量≥→跳转",
  place_actor: "放置角色", nop: "空", add_actor_var: "角色变量 +", add_wood: "木材 +", show_actor: "显示角色", give_item: "给道具",
  set_trigger: "启用 / 停用触发", cutscene_begin: "演出开始", cutscene_end: "演出结束", add_metal: "金属 +", camera_angle_speed: "镜头转速",
  camera_distance_speed: "镜头推拉速度", camera_target_speed: "镜头移动速度", place_actor_map: "角色换地图", wait_move: "等走完",
  camera_nowait: "镜头不等待", add_money: "金钱 +", change_map: "切换地图", set_actor_event: "设角色对话事件", random_goto: "随机跳转",
  walk_to: "走到", move_to_follow_cam: "走到（镜头跟随）", camera_restore: "恢复镜头", add_coal: "煤炭 +", heal_member: "恢复队员",
  menu_switch: "选项分支", camera_target_actor: "镜头对准角色", set_act: "换模型", add_ani_on_actor: "角色身上加特效",
  set_weapon_model: "换手持物", set_0073_mode: "恢复地图操作", play_music: "播放音乐", set_collision: "设碰撞", set_floor: "设楼层",
  camera_batch_begin: "镜头批量开始", camera_batch_end: "镜头批量结束", take_item: "收走道具", start_battle: "开战", wait_camera: "等镜头",
  call_event: "转入事件", if_all_flags_goto: "如果旗标都设了→跳转", del_ani_wait: "删特效（等）", if_item_goto: "如果有道具→跳转",
  set_actor_ai: "设角色行为", music_control: "音乐控制", open_save_menu: "打开存档菜单", set_music_fade: "音乐淡出",
  if_not_flag_goto: "如果没设旗标→跳转", if_money_ge_goto: "如果金钱≥→跳转", if_actor_var_eq_goto: "如果角色变量=→跳转", del_ani: "删特效",
  add_ani: "加特效", fade_actor_alpha: "角色淡入淡出", open_shop: "开商店", set_move_speed: "设移动速度", narration_mode: "旁白模式",
  set_map_music: "设地图音乐", wait_actor_fade: "等角色淡完", wait_turn: "等转身", camera_wait: "镜头等待", crossfade_speed: "交叉淡化速度",
  set_actor_var: "设角色变量", end: "结束", data: "数据块（跳过）", if_any_flag_goto: "如果任一旗标→跳转", screen_shake: "画面震动", play_video: "播放视频",
}

/** 操作数类型 → 中文 */
export const OPERAND_LABEL: Record<string, string> = {
  w: "数值", s: "数值", d: "数值", c: "数值", r: "跳到", a: "角色", u: "战斗单位", m: "地图", f: "旗标", i: "物品", b: "战场",
  n: "名字", e: "事件", M: "曲目", T: "文本", F: "列表", R: "跳转表", P: "跳转表",
}
