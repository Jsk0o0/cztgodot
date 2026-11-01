"""轩辕剑苍之涛 事件脚本反汇编器 (talks1-1~1-4 / talks2 / Talks3)

容器: GLL022 偏移表 (见 extracted/text/README.md)。槽位下标 i 对应事件 ID = i + 1;
各文件负责的事件范围: talks1-1 1–500, talks1-2 501–1000, talks1-3 1001–1500,
talks1-4 1501–2000, talks2 2001–5000, Talks3 5001–7979。空槽指向本文件第一个脚本。
字节码: u16 小端操作码 + 操作数 (见 OPS); 文本内嵌 (Big5, 以 %Q 结束, 可为奇数长度, 之后不再 2 字节对齐)。
相对跳转 (rel32): 目标 = 该 u32 字段自身地址 + 值。
用法: python disasm_script.py <游戏目录> <输出目录>
"""
import json
import os
import re
import struct
import sys
from collections import Counter, defaultdict

try:
    from opencc import OpenCC
    _cc = OpenCC('t2s').convert
except ImportError:  # 无 opencc 时保留繁体
    _cc = lambda s: s  # noqa: E731

TEXT_RE = re.compile(rb'(?:[\xa1-\xf9][\x40-\x7e\xa1-\xfe]|[\x20-\x7e])*?%Q')

# 操作数类型: w=u16  s=i16  d=i32(两个字)  r=rel32 跳转  a=角色 ID (名字 = Name.gll[ID-1])  m=地图 ID  f=旗标
#             i=物品 (ObjDATA)  b=战场编号(1 起)  n=名字编号 (Name.gll[n-1])  e=事件 ID  M=曲目 ID (MAPS.DAT 曲目表)
#             T=内嵌文本  F=ffff 结尾的 u16 列表  R=ffffffff 结尾的 rel32 列表
# 状态: C=从 exe 解释器汇编直接确认  P=汇编能看出做了什么, 具体用途推断
# 全部来自 SWDMD_GB.EXE (简体版, 未加壳) 事件 VM 的逆向: 主循环 0x405fcd, 分发表 0x40bcfb/0x40b9db, 见 README
OPS = {
    0x0000: ('', 'nop', 'C', '空操作，只推进 2 字节（0x00c9、0x4000 也走这个处理函数）'),
    0x00c9: ('', 'nop', 'C', '空操作 (与 0x0000 共用处理函数)'),
    0x0001: ('r', 'goto', 'C', '无条件相对跳转'),
    0x0002: ('fr', 'if_flag_goto', 'C', '旗标被置位（test_flag==1）时跳转，否则跳过本条（8 字节）'),
    0x0003: ('fr', 'if_not_flag_goto', 'C', '旗标未置位（test_flag==0）时跳转，置位时跳过本条'),
    0x0004: ('Fr', 'if_all_flags_goto', 'C', '列表里所有旗标都已置位（AND）才跳转；只要有一个未置位就跳过整条指令（2+列表字节+4）。空列表时不推进、直接返回（边界情况）'),
    0x0005: ('Fr', 'if_any_flag_goto', 'C', '列表里任意一个旗标置位（OR）就跳转；全部未置位时跳过整条指令'),
    0x0006: ('f', 'set_flag', 'C', '置旗标'),
    0x0007: ('f', 'clear_flag', 'C', '清旗标'),
    0x0008: ('ww', 'countdown_timer', 'P', '启动/停止一个全局倒计时（推测为画面上的限时计时器）'),
    0x0009: ('w', 'wait', 'C', '等待指定时间；期间每帧让出。旗标 0x1f4c 置位时立即结束（快进/跳过）'),
    0x000a: ('awwwwwwwwwT', 'text', 'C', '弹出对白/旁白文本窗口（add_talkmsg）；同时带上 0x0b/0x0e/0x0f/0x10 设定的颜色、字距、行距、文字颜色'),
    0x000b: ('wwww', 'window_color', 'C', '设定之后文本窗口的纯色底颜色 ARGB（文本 flags bit1 时使用）'),
    0x000c: ('ww', 'window_skin', 'P', '设置文本窗口皮肤图编号；但事件 VM 的 0x0a 不读这两个值（写死 0x2330），只有 AI 脚本的文本指令（0x401312 把 [0xa84c54] 写 msg+0x22）会用到'),
    0x000d: ('a', 'wait_text', 'C', '等待该角色的文本窗口关闭：角色标志 +0x1a4 的 bit27（字节 +0x1a7 &8，“说话中”）置位时每帧让出；角色不存在则直接跳过'),
    0x000e: ('w', 'text_char_spacing', 'P', '设定之后文本的字符间距（实例：对白 2、旁白 3）。'),
    0x000f: ('w', 'text_line_spacing', 'P', '设定之后文本的行间距（实例几乎都是 5）。'),
    0x0010: ('w', 'text_color', 'P', '设定之后文本的默认文字颜色（文本里的 %Cn 用同一张调色板）'),
    0x0011: ('R', 'menu_switch', 'C', '等待选项菜单出结果（[0xa84cf0]==1，否则每帧让出），然后按选中下标 [0xa84cec] 取表项跳转；目标 = 表项地址 + 值'),
    0x0012: ('a', 'close_text', 'C', '立即关闭该角色当前的文本窗口：从 talkmsg 链表摘除，并清角色的“说话中”位 +0x1a7&8'),
    0x0014: ('aw', 'set_act', 'C', '更换角色的模型/动作组 ACT（错误信息里叫 ACT）：写角色 +0x294，动画控制块 +0x200 整体清零（动作 QQ 归 0），并把 MAPS.DAT 中该 ACT 的 20 字节参数复制到角色结构 +0x00..+0x13。角色不在当前地图时改写常驻角色表 [0xafe958] 记录 +6'),
    0x0015: ('aw', 'set_pose', 'C', '让角色播放指定动作（QQ）；保留 ACT +0x294，重建动画控制块。角色不在当前地图时写常驻表记录 +8'),
    0x0016: ('aw', 'set_anim_speed', 'P', '设定角色动画播放的帧间隔，并让它在切换动作后保持（动画块 +0x7c bit0）'),
    0x0017: ('a', 'reset_anim_speed', 'P', '取消 0x16 的保留帧间隔（清动画块 +0x7c bit0）'),
    0x0018: ('aww', 'set_facing', 'C', '设定角色朝向'),
    0x0019: ('w', 'set_move_speed', 'C', '设定之后 walk_to/move_to/0x1f 生成路径用的移动速度（默认 8.0）'),
    0x001a: ('', 'reset_move_speed', 'C', '把移动速度 [0x4e48c4] 恢复为默认 8.0（0x41000000）。'),
    0x001b: ('addd', 'place_actor', 'C', '把角色瞬移到 (X,Y,Z)：先取消其路径，写位置 +0x1bc/+0x1c0/+0x1c4，再做一次碰撞/贴地修正'),
    0x001c: ('amddd', 'place_actor_map', 'C', '设置角色所在地图及坐标（改常驻角色表）；是当前地图则在场/载入该角色并放置，不是当前地图则把场上的该角色移出（ID 置 0xffff）'),
    0x001d: ('addd', 'walk_to', 'C', '为角色添加一条走到 (X,Y,Z) 的路径（速度取 0x19 设的值，动作取当前 +0x296）；若全局镜头高度 [0x518e50]（由 op 0xab 设）非 0，镜头会跟随，用完清零'),
    0x001e: ('adddw', 'move_to_follow_cam', 'P', '与 walk_to 相同，但路径类型固定为 0xa（bit1）：移动时镜头注视点 [0xa851e0..e8] 每帧跟到角色位置 + (0, 偏移, 0)'),
    0x001f: ('aaw', 'walk_to_actor', 'P', '角色 A 朝角色 B 走，停在 B 跟前（距离按两者半径 +0x210 计算）；已足够近就不动'),
    0x0020: ('a', 'wait_move', 'C', '等待角色走完路径（角色 +0x1a7&0x20 置位时每帧让出）'),
    0x0021: ('a', 'set_actor_flag31', 'P', '置角色标志 +0x1a4 bit31（0x80000000）。对话触发 0x47a4f0/0x47c950、入口提示 0x463079、0x478708 都会检查主控角色的这一位'),
    0x0022: ('a', 'clear_actor_flag31', 'P', '清角色标志 bit31'),
    0x0023: ('a', 'hide_actor', 'C', '隐藏角色：置 +0x1a4 bit0，清占位格 +0x1c8..+0x1d0，同步常驻表 +0x16 bit0；ID 0x46a–0x473 的角色同时从小地图标记里删除。'),
    0x0024: ('a', 'show_actor', 'C', '显示角色：清 +0x1a4 bit0，清占位格并调 0x469a4f 重新放置（贴地/占格），同步常驻表。'),
    0x0025: ('a', 'set_actor_flag3', 'P', '置角色标志 +0x1a4 bit3（0x8），同步常驻表 +0x16，并释放角色身上的特效句柄。exe 里没找到直接测试这一位的代码，具体作用未确认（地图 AI 脚本 0x401828 也能置/清这一位）'),
    0x0026: ('a', 'clear_actor_flag3', 'P', '清角色标志 +0x1a4 bit3，同步常驻表'),
    0x0027: ('a', 'set_leader', 'P', '把该角色设为主控角色：[0xbcd9a8]=下标；旧主控清 0x8000，新主控清 0xe000 后置 0xc000（标志 +0x1a4 bit13–15），并同步常驻表'),
    0x0028: ('a', 'set_role_type_4000', 'P', '清角色 +0x1a4 bit13–15 后置 0x4000（角色类别位；推测是同伴/跟随者）'),
    0x0029: ('a', 'set_role_type_2000', 'P', '清角色 bit13–15 后置 0x2000（角色类别位）'),
    0x002a: ('a', 'clear_role_type', 'P', '清角色 +0x1a4 bit13–15（0xe000）'),
    0x002b: ('aw', 'set_actor_flag5', 'P', '置/清角色标志 +0x1a4 bit5（0x20，“动作由脚本指定”位：0x14/0x15 置位，走路指令清除）'),
    0x002c: ('aw', 'set_actor_flag1', 'P', '置/清角色标志 +0x1a4 bit1（0x2），作用未确认'),
    0x002d: ('aw', 'set_collision', 'P', '开关角色在碰撞网格上的占位。w≠0：清 +0x1a4 bit6（0x40），按当前位置算出网格中心存进 +0x1c8/+0x1cc/+0x1d0；w=0：释放原占位格，置 bit6'),
    0x002e: ('aw', 'set_ghost_move', 'P', '置/清角色标志 +0x1a4 bit2（0x4）：置位后沿路径移动时跳过碰撞和动画步进，直接写坐标'),
    0x002f: ('aa', 'warp_to_actor', 'C', '把角色 A 的坐标设为角色 B 的坐标，再调 0x469a4f 重新放置'),
    0x0030: ('aww', 'add_actor_effect', 'C', '在角色身上挂一个动画特效（add_ani）：取角色当前坐标，记录角色 ID、地图 ID，标志 0x80（推测为跟随角色）'),
    0x0031: ('aww', 'remove_actor_effect', 'C', '移除角色身上与 (ACT,QQ) 匹配的动画特效'),
    0x0032: ('mdddww', 'change_map', 'C', '切换地图：清理文本窗口/路径/角色，载入新地图（0x467ece），把主控角色放到 (X,Y,Z) 并设朝向，再设场景视距'),
    0x0033: ('wwww', 'tint_fade', 'P', '把全局色调（RGB 存在 0xa83cfa/0xa83cf9/0xa83cf8）以固定步长渐变到目标色；每帧调 0x4146bb/0x41474b 应用到渲染器 0xa60370；到达后恢复默认（0x4146bb(0xa84ea8)、0x41474b(-1)）'),
    0x0034: ('www', 'set_screen_color', 'P', '立即设置全屏覆盖色：alpha=0xff，[0xa85194]=0xff<<24|R<<16|G<<8|B（淡入淡出遮罩用的颜色）'),
    0x0035: ('wwwwww', 'fade', 'C', '全屏颜色遮罩淡入淡出：先把遮罩 alpha 设为起始值，每帧向目标值移动「速度」，直到到达后结束本条（执行期间每帧让出）。255→0 = 从黑淡入，0→255 = 淡出到黑'),
    0x0036: ('w', 'set_event_active', 'P', '置位/清除旗标 8052「事件进行中」。该旗标在 0x405c21 启动事件时自动置位，在事件结束(0xffff)和存档前清除；actor 更新 0x468a89/0x469a4f 会读它'),
    0x0037: ('wwsss', 'add_ani', 'C', '在 (x,y) 处添加一个 act/qq 动画对象（不移动）。实际用法全是 add_ani(9200, n, 0,0,0)：显示第 n 张回忆插图/CG，配合 0x5e(1) 黑屏叙事模式和 window_type 3 旁白'),
    0x0038: ('ww', 'del_ani', 'C', '删除动画列表(0xa85480)中 act/qq 匹配的动画；若该动画带淡出标志(0x200)则只打上 0x400 让它淡出。不等待（等待版见 0x60）'),
    0x0039: ('w', 'set_floor', 'C', '设置当前楼层：写 [0x4e48c8]，并调用 0x40bf41(ecx=地图对象 0xa83b30, 当前地图 [0xa84fe0], 楼层)'),
    0x003a: ('w', 'screen_shake', 'C', '画面震动开关：置位/清除 [0xa85188] bit1；开启时地图渲染 0x477d28 与表情渲染 0x46b10d 每帧给视点加 rand()%10 抖动'),
    0x003b: ('w', 'player_free', 'P', '置位/清除 [0xa85188] bit2；置位时还立即清除主角 +0x1a7 的 bit7。VM 每次进入(0x405f77)若该位为 0 就给主角 +0x1a7 置 0x80（事件锁定），所以 1 = 事件期间主角不被锁定'),
    0x003c: ('', 'camera_batch_begin', 'C', '置位旗标 8031(0x1f5f)。镜头指令(0x44–0x47)在非等待模式([0xa851b8]=1)下，只要 8031 置位就不让出帧、直接执行下一条，用来把一组镜头设置放在同一帧完成；带 bit1 的角色路径走完时(0x469f53)也会清除它'),
    0x003d: ('', 'camera_batch_end', 'C', '清除旗标 8031(0x1f5f)，结束 0x3c 开始的同帧镜头设置'),
    0x003e: ('w', 'camera_mode', 'C', '同时设置镜头注视点、角度、距离三项的插值方式（镜头对象 0xa80648 的 +0x20/+0x2c/+0x38），并记录到 [0xa851c0/c4/c8]'),
    0x003f: ('s', 'camera_target_speed', 'C', '设置镜头注视点的移动速度（镜头对象 +0x18 / +0x1c），并记录到 [0xa85200]/[0xa8520c]'),
    0x0040: ('s', 'camera_angle_speed', 'C', '设置镜头角度的变化速度（+0x24=v*0.001，+0x28=v），并记录到 [0xa85204]/[0xa85210]'),
    0x0041: ('s', 'camera_distance_speed', 'C', '设置镜头距离的变化速度（+0x30/+0x34），并记录到 [0xa85208]/[0xa85214]'),
    0x0042: ('', 'camera_nowait', 'C', '[0xa851b8]=1：之后的镜头指令(0x44–0x47)不等镜头到位就往下执行（配合 0x3c 可在同一帧内完成）'),
    0x0043: ('', 'camera_wait', 'C', '[0xa851b8]=0：镜头指令执行后一直让出帧，直到镜头到位才往下执行（默认状态）'),
    0x0044: ('ddd', 'camera_target', 'C', '设置镜头注视目标点 (x,y,z)，按 0x3e 的方式移动；同时记录到 [0xa851e0/e4/e8]。等待模式下每帧检查 |目标-当前|<1 才结束'),
    0x0045: ('ssss', 'camera_angle', 'C', '设置镜头三个角度的目标值，记录到 [0xa851ec/f0/f4]；等待模式下要三个角取整后都等于目标才结束'),
    0x0046: ('s', 'camera_distance', 'C', '设置镜头到注视点的目标距离（镜头对象 +0x8 与 +0xc），记录到 [0xa851f8]/[0xa851fc]；等待模式下要 |目标-当前| 足够小才结束'),
    0x0047: ('waw', 'camera_target_actor', 'C', '镜头注视点设到角色位置 (x, y+偏移, z)。插值方式为 1（瞬间）时立即更新镜头并继续本帧。脚本里全是 (1, 0x0001, 100)：瞬间对准主角，抬高 100'),
    0x0048: ('sss', 'camera_eye_pos', 'P', '直接设置镜头机位（眼睛）坐标，写镜头对象 +0xac..+0xb4，供固定机位模式（0x49 mode 4）使用'),
    0x0049: ('w', 'camera_type', 'C', '设置镜头对象 0xa80648 的工作模式 [+0]。用例 1/4 成对出现（talks2/2459、2463、2464），0x73 在固定镜头地图上也会调用 mode 4'),
    0x004a: ('s', 'camera_eye_speed', 'P', '设置镜头机位的移动速度（镜头 +0x3c 与 +0x40，0x46087c 用 +0x3c 计算每帧位移）'),
    0x004b: ('w', 'camera_target_mode', 'C', '只设置注视点的插值方式（+0x20），记录到 [0xa851c0]'),
    0x004c: ('w', 'camera_angle_mode', 'C', '只设置角度的插值方式（+0x2c），记录到 [0xa851c4]'),
    0x004d: ('w', 'camera_distance_mode', 'C', '只设置距离的插值方式（+0x38），记录到 [0xa851c8]'),
    0x004e: ('w', 'camera_eye_mode', 'P', '设置镜头机位的插值方式（+0x44），记录到 [0xa851cc]'),
    0x004f: ('ew', 'set_trigger', 'C', '启用或禁用某个事件 ID 对应的地图触发区：在第二张位图 0xafe058 里，禁用时置位第 n 位、启用时清除（与普通旗标位图 0xafdc58 是分开的）；同时把当前已载入、+0x30==n 的触发区对象 +0x34 置 1(禁用)或 0'),
    0x0050: ('e', 'call_event', 'C', '结束当前事件，转入事件 w 执行：用系统角色 0xff02 作为发起者重新调用 0x405c21 启动事件 w；[0x518e6c]=1 表示不再覆盖事件开始时保存的镜头状态；并清除当前事件自己的上下文（0x405d87），所以本指令之后的指令一般不会再执行。不是任务、存档点或「进入战斗前」'),
    0x0051: ('b', 'start_battle', 'C', '开始战斗：先清当前对象 +0x1a7 bit2、调用 0x465346，再在旗标 11 未置位时调用 0x43fb05(战场号) 初始化战斗（它会设 [0xa83ce0]=0x14 进入战斗画面），最后 [0xa83cb8]=0，[0x9253d4]=1。旗标 11 在程序和脚本里都没被置位过，像是调试用的「跳过战斗」'),
    0x0052: ('', 'mark_trigger_done', 'P', '把所有 +0x30 == 当前对话号([ebx+0x17e]) 的触发区对象 +0x38 置 1（标记为已触发）'),
    0x0053: ('ff', 'clear_flag_range', 'C', '清除旗标 a..b（含两端）'),
    0x0054: ('w', 'crossfade_speed', 'P', '设置「截屏淡出」效果的 alpha 每帧递减量 [0x4e6790]。先调用的 0x472406 是空函数，开始截屏的标志 [0xc75374] 在程序里从没被置 1，所以这个效果在本版本里实际不起作用'),
    0x0055: ('', 'wait_crossfade', 'C', '等待截屏淡出结束（[0xc75374]==0）才往下执行；因为 0xc75374 从不被置位，实际会立即通过'),
    0x0056: ('wws', 'camera_zoom', 'C', '设置 3D 投影的缩放系数 [0x4e48fc]（0x41a951 里乘到投影比例上，值越大画面越放大）。每帧由 0x46da31 处理：方式 1 立即生效，方式 2 在 N 帧内从当前值插值到目标值。0x73 会把它恢复成事件开始时的值。脚本里几乎都是 (1, 0, 10)，即恢复默认'),
    0x0057: ('aw', 'wait_anim', 'C', '等待角色当前动作播到指定帧或播完，不会播放动作。典型用法是 set_pose 之后接 (角色, 0)'),
    0x0058: ('w', 'camera_control', 'C', '[0x518e5c]=v（只写不读），1 时置位、0 时清除旗标 8051(0x1f73)。8051 =「脚本演出中」：地图更新 0x477d28 在它置位时跳过镜头跟随主角那一大段，0x4422b9 不画 HUD，0x47ca8b 停止 NPC 的自主行动。效果与 0x66/0x65 相同'),
    0x0059: ('R', 'random_goto', 'C', '随机跳转（不是按选项结果跳转，那是 0x11）：统计表项数 n，用 srand([0xa83cf4] 当前时钟)+rand() 取 r=rand()%n，然后跳到第 r 项。第 0 项在全部 339 个用例里都正好指向本指令之后，也就是「不跳、继续往下」这一分支；所以 n 项是等概率的 n 个分支'),
    0x005a: ('T', 'play_video', 'C', '播放过场视频。首次执行时读文件名、调用 0x46c02f 播放、置 [0xa83ce8] bit5，并调用 0x46b7a5；之后一直等，直到旗标 8030(0x1f5e，视频播放中)被清除。如果旗标 8033(0x1f61) 已置位（见 0x63），就清掉它并立即继续，不等待'),
    0x005b: ('sssssssww', 'add_ani_move', 'C', '添加一个从起点飞到终点的动画特效对象（act/qq），按给定速度移动'),
    0x005c: ('sssasww', 'add_ani_to_actor', 'C', '添加一个从固定点飞向某角色的动画特效对象'),
    0x005d: ('aww', 'add_ani_on_actor', 'C', '在角色当前位置添加一个静止的动画特效（起点=终点=角色坐标，速度 0）。例：(1, 5500, 5)、(11, 8140, 0)'),
    0x005e: ('w', 'narration_mode', 'C', '切换画面状态 [0xa83ce0]：v==1 时设为 12，否则设为 0；[0x518e74]=v（只写不读）。状态 12 下主循环 0x46f3b8 改调 0x463580/0x4635c1：只运行对话脚本、清成黑底(800x600)并画动画和对话框，不画地图，只响应少数按键。脚本里 0x5e(1) 后面通常跟 0x37(9200,n) 插图和 window_type 3 旁白。执行前同样清当前对象 +0x1a7 bit2 并调用 0x465346'),
    0x005f: ('ww', 'wait_ani', 'P', '等待 act/qq 动画播完，0x46bad7 返回 1 才往下执行'),
    0x0060: ('ww', 'del_ani_wait', 'C', '删除 act/qq 动画（同 0x38），如果它正在淡出就每帧重试，直到真正删掉才往下执行'),
    0x0061: ('aw', 'wait_actor_flag', 'P', '等到角色 +0x2c0 bit0（动作已播完）置位才往下执行；找不到角色时报错并卡住'),
    0x0062: ('w', 'wait_video_frame', 'P', '等待正在播放的 Bink 视频（0x46c02f 建立的 [0xa85484]）播到指定帧'),
    0x0063: ('', 'video_nowait', 'C', '置位旗标 8033(0x1f61)：下一个 0x5a 开始播放视频后不等待，立即继续'),
    0x0064: ('www', 'set_rgb', 'P', '把 dword [0xa83cfc] 设为 0x00RRGGBB（[0xa83cff]=0），作为某个颜色参数；没找到读它的代码'),
    0x0065: ('', 'cutscene_end', 'C', '清除旗标 8051(0x1f73)，退出演出模式；等同 0x58(0)，只是不写 [0x518e5c]'),
    0x0066: ('', 'cutscene_begin', 'C', '置位旗标 8051(0x1f73)，进入演出模式（镜头不跟随主角、不画 HUD、NPC 停止自主行动）；等同 0x58(1)'),
    0x0067: ('T', 'set_text_buffer', 'P', '把内嵌字符串复制到 0xa859ac，再 strcpy 到 0x4e888c（战斗/FightTalk 代码 0x4405c1、0x45b7bd 会用这两个缓冲区）'),
    0x0068: ('', 'nop_stub', 'C', '调用空函数 0x472406（只有一条 ret），等于什么都不做'),
    0x0069: ('w', 'play_sound', 'C', '播放音效：0x4bec87(id,1)，在旗标 21 未置位时调用音效管理器 0xea6a58 的 0x4befee(0, id, 音量 [0x4e4910], 0, 1, 0)；第二个参数 1 实际没被用到'),
    0x006a: ('w', 'stop_sound', 'P', '停止音效：ecx=0xea6a58，调用 0x4bf117(id)'),
    0x006b: ('w', 'weather_effect', 'P', '全屏粒子特效（雪/雾之类）开关，[0x518e78]=v。v=1：置 [0xa84d22] bit3 和旗标 8061(0x1f7d)，new 0x124 字节对象，用 0x4915af 以注视点为中心、主角 y+1000 处建 500 个粒子(资源 8001=0x1f41)，存到 [0xa8589c]；v=0：清 bit 和旗标，销毁对象。地图标志 [0xa84d22]&8 在载入地图时(0x468452)也会开这个效果'),
    0x006c: ('', 'free_models', 'P', '释放所有动态载入的 .PLY 3D 模型缓存（0x42f1e5(-1)：遍历 16 个桶 0x8b75b8，释放全部节点并扣减内存计数 [0x8f2d1c]）'),
    0x006d: ('', 'unsupported', 'C', '没有专门的处理函数，走默认分支 0x407ed4；0x4bb2e9 对 0x6d 返回 0xffff，会把指针推进 0xffff，所以这个操作码不能用'),
    0x006e: ('awwwww', 'actor_move_to', 'P', '让角色从当前位置直线移动到 (x,y,z)：置 +0x1a7 bit0「移动中」，+0xb4..bc=当前坐标，+0xc4..cc=目标，+0xec=参数，+0xfc=1.0'),
    0x006f: ('a', 'wait_actor_move', 'P', '等到角色 +0x1a7 bit0（0x6e 设的移动中）被清除'),
    0x0070: ('ar', 'if_actor_stopped_goto', 'P', '角色还在移动（+0x1a7 bit0）就继续往下，已经停下就跳转'),
    0x0071: ('aar', 'if_actors_collide_goto', 'P', '0x46926a 检测角色 A 与 B 是否碰撞；碰撞就同时清两者的移动位、把 +0xb4 起 0x6c 字节清零，然后跳转；没碰撞就继续往下'),
    0x0072: ('wwwww', 'set_move_params', 'P', '设置角色移动/碰撞用的一组全局参数（0x468a89 会读）'),
    0x0073: ('', 'camera_restore', 'C', '镜头回到事件开始前的状态：先恢复投影缩放 [0x4e48fc]←[0x4e4904]。固定镜头地图（[0xa85184]&1）：镜头类型设为 4 并恢复机位。普通地图：首次执行时把保存的 0xa85238 复制回 0xa851b8，三项插值方式设为 3（[0x518e68]==1 时设为 1），注视点设为 主角 (x, y+100, z)，角度/距离设回保存值；之后每帧等注视点、角度、距离都到位，再把各项速度和插值方式恢复成保存值'),
    0x0074: ('T', 'add_text_list', 'P', '往 0x9f2860 的 10 项 × 20 字节字符串表追加一项，计数 [0x9f2f94]，到 10 时回绕；内容为 "0" 时清空整张表。0x463be8 会读这张表'),
    0x0075: ('n', 'set_caption', 'C', '设置下一个对话框显示的说话者名字：[0x4e8888]=Name.gll 表 [0x4e8878][w-1]；随后的文字指令 0x0a 把它复制进名字栏（0x4060d1）并清空。找不到时报「找不到第%d號Caption」'),
    0x0076: ('aaw', 'look_at', 'C', '让角色 1 面向角色 2：用两者的 x/z 差算出角度 (0x40be2d/0x40becc，x<0 时取 360-角度)。w=1：角色 +0x1a6 |= 0x0c，目标角度写 +0x1b4，调用 0x46d47d 平滑转身；w=0：+0x1b4 和 +0x1b0 都直接写入。角色 ID 在 0x46a–0x473（1130–1139，地图机关）时还会调用 0x479b26 转动对应的地图物件。最后清 +0x17a'),
    0x0077: ('a', 'wait_turn', 'C', '等到角色 +0x1a6 bit2（0x76 平滑转身时设置的转动中）被清除。用例里 1130–1139 是机关物件'),
    0x0078: ('aww', 'set_expression', 'C', '更换角色 3D 模型的脸部表情：角色 +0x4bc=act，+0x4be=qq，并置 [0x518e70]=1（事件结束时 0x40b70d 据此调用 0x4165ec 清理）。act=0 时清零 +0x428 起 0x114 字节，并把模型的 +0x114 恢复为角色 +0x1f4。实际绘制在 0x46b10d（「角色[%d]更換表情ACT[%d]QQ[%d]有問題」）'),
    0x0079: ('', 'script_begin', 'P', '脚本块开始：置位旗标 8015(0x1f4f)，并调用 0x46782f(0xffff)（[0xa83ce9] |= 0x80，[0xa83cf0]=0xffff）；与 0x7a 成对'),
    0x007a: ('', 'script_end', 'C', '脚本块结束：清旗标 0x1f4f，复位 [0xa83ce8]/[0xa83cf0]，清玩家角色 +0x1a4 的 0x20 与 0x80000000 位'),
    0x0082: ('aw', 'camera_focus_actor', 'P', '镜头移向角色 (按角色位置/朝向计算镜头位置)，等待镜头动作结束后才前进 (可多帧阻塞)'),
    0x0083: ('adw', 'turn_actor_by', 'P', '角色相对转向：重置动作区 +0x200 后把角度增量加到目标角度'),
    0x0084: ('aw', 'set_actor_ai', 'C', '设置角色 AI 脚本号并写入地图角色表 (持久)；0 时同时清动作 +0x296'),
    0x0085: ('ae', 'set_actor_event', 'C', '设置角色被调查时触发的事件号 (写角色 +0x17e 与地图角色表 +0x12)'),
    0x0086: ('w', 'set_camera_fov', 'P', '设置投影参数 [0x4e4900] 并重建视口 (800x600, near 200, far 50000)'),
    0x0087: ('a', 'set_actor_flag_1a8', 'P', '置角色状态字 +0x1a8 的 bit0 (角色不在场时写地图角色表 +4 |=1)；与 0x00aa 相反'),
    0x0088: ('', 'reset_frame_rate', 'P', '清旗标 0x1f4c，镜头参数 [0x4e48b8..c0]=5.0、[0x4e48c4]=8.0，帧时间设为 1000/35 ms'),
    0x0089: ('adddwww', 'actor_path_to', 'C', '给角色添加一条移动路径到 (x,y,z)，速度取 [0x518e50] (由 0x00ab 设置，用后清 0)'),
    0x008a: ('aiww', 'set_weapon_model', 'C', '设置角色手持武器模型 (+0x5d0 武器 ACT, +0x5d2 QQ, +0x184 开关)；开关=1 且未指定时取车芸当前武器 [0xbce01a]'),
    0x008b: ('wddd', 'heal_member', 'C', '恢复/增减队员 HP 等三项数值并夹在 [0,上限]，同时清除 +0x568 的 bit1 (推测为倒下状态)'),
    0x008c: ('', 'set_0073_mode', 'C', '置 [0x518e68]=1，改变紧随其后的 0x0073 指令的行为 (0x0073 执行后清 0)'),
    0x008d: ('aw', 'set_actor_flag_1000', 'P', '设置/清除角色标志字 +0x1a4 的 0x1000 位 (同步到地图角色表)'),
    0x008e: ('awr', 'if_near_actor_goto', 'C', '玩家与该角色的水平距离 ≤ 半径则跳转，否则顺序执行'),
    0x008f: ('www', 'wait_signal_8f', 'P', '首次执行时设置参数并置 [0x518e88]=1，然后阻塞直到 [0x518e84]==1'),
    0x0090: ('MwMww', 'play_music', 'C', '在“剧情音乐组”(组 2) 的两个槽位装入曲目 A/B 并切到该组播放，淡变时间取 [0x518e8c] (0x0093 设置)'),
    0x0091: ('mMwMw', 'set_map_music', 'C', '改写 MAPS.DAT 地图默认音乐表中该地图的记录 (下次进入该地图时生效，随存档保存)'),
    0x0092: ('w', 'music_control', 'C', '恢复地图音乐或停止全部音乐，淡变时间 [0x518e8c]；执行后 [0x518e8c] 清 0'),
    0x0093: ('w', 'set_music_fade', 'C', '设置下一次 0x0090/0x0092 切换音乐的淡入淡出时间 (0x0092 用后清 0)'),
    0x0094: ('', 'wait_music', 'P', '等待音乐流设备就绪 (0xea6570.0x4bec67 返回 1) 后前进'),
    0x0095: ('w', 'set_reg0', 'C', '写全局寄存器 0 ([0xafe858])，供 0x0136 读取'),
    0x0096: ('', 'wait_camera', 'P', '等待脚本镜头动作结束 (三个镜头状态查询均返回 1)'),
    0x0097: ('aw', 'set_actor_flag_80', 'P', '设置/清除角色标志字 +0x1a4 的 0x80 位 (同步到地图角色表)；多用于玩家角色 1 成对开关'),
    0x0099: ('ddd', 'set_effect_offset', 'C', '设置下一次 0x009a 特效的位置偏移 (→[0x518e40..48])'),
    0x009a: ('aw', 'play_effect_at_actor', 'C', '在角色位置 (+偏移) 播放粒子特效，然后清空偏移'),
    0x009b: ('w', 'nop_9b', 'C', '空操作 (跳过 4 字节)'),
    0x009c: ('w', 'nop_9c', 'C', '空操作 (跳过 4 字节)'),
    0x009d: ('awww', 'fade_actor_alpha', 'C', '角色透明度渐变：从起始值渐变到目标值 (到 255 后关闭半透明)'),
    0x009e: ('a', 'wait_actor_fade', 'C', '阻塞直到该角色的透明度渐变 (0x009d) 完成'),
    0x009f: ('w', 'set_self_flag_66d', 'P', '设置当前事件所属角色 (ebx+0x17c) 的 +0x66d 字节标志 (add_talks_proc 也会置 1)'),
    0x00a0: ('a', 'set_actor_flag_200000', 'P', '置角色标志字 +0x1a4 的 0x200000 位 (byte +0x1a6 |= 0x20)'),
    0x00a1: ('wmmmmmmm', 'set_battle_countdown', 'C', '设置「还有 N 场战斗」计数并置旗标 18；切换到不在列表中的地图时计数与旗标 18 自动清除'),
    0x00a2: ('', 'save_view_state', 'C', '保存当前地图 ID、镜头参数、FOV 与玩家位置/角度到 0xbcf060 缓冲 (配合 0x00a3)'),
    0x00a3: ('', 'restore_view_state', 'C', '从 0xbcf060 恢复 0x00a2 保存的地图/镜头/玩家位置并重新载入该地图'),
    0x00a4: ('', 'wait_flag_a83cec', 'C', '阻塞直到 [0xa83cec] 的 bit0 清除 (自改写：首次把操作码改为 0x20a4 让出一帧)'),
    0x00a5: ('ad', 'set_actor_scale', 'P', '设置角色缩放比例 (同步到 gmRoleVar 表)'),
    0x00a6: ('', 'sync_player_angle', 'P', '置 [0xc6e660]=1，并把玩家角色 +0x1b0 (当前角度) 复制到 +0x1ac'),
    0x00a7: ('', 'nop_a7', 'C', '空操作'),
    0x00a8: ('aww', 'play_actor_action', 'P', '清空角色动作区后播放指定动作 (置 +0x1a4 |= 0x20)'),
    0x00a9: ('', 'game_clear_save', 'P', '通关处理：清空 0xc72df8/0xc74318 两块记录区，置 [0xbcf13a]/[0xbcf15a]/[0xbcf15c]=1 并写 fame.dat'),
    0x00aa: ('a', 'clear_actor_flag_1a8', 'P', '清角色状态字 +0x1a8 的 bit0 (与 0x0087 相反；角色不在场时代码走的是 0x0087 的置位路径)'),
    0x00ab: ('ww', 'set_path_speed', 'C', '设置下一次 0x0089 路径移动的速度'),
    0x00ac: ('ww', 'learn_skill', 'C', '队员习得技能 (加入该队员的技能列表并重算)'),
    0x00c7: ('w', 'op_00c7', 'P', '调用 0x462edc(w)：在 [0x9f2688] 链表中找 +0x124==w 的对象并拷贝 0xa83d08 区数据'),
    0x00c8: ('', 'return_to_title', 'P', '调用 0x4709a9(0x10000000,0,0) (重新载入 maps.dat / fame.dat，即回到开始状态) 并置旗标 0x1f73'),
    0x00ca: ('F', 'open_shop', 'C', '打开商店 (「客倌 您要買東西還是賣東西」)，等商店界面关闭后跳过列表'),
    0x00cb: ('', 'open_save_menu', 'P', '清旗标 0x1f74 后打开存档界面 (0x474f9e)'),
    0x00cc: ('', 'open_load_menu', 'P', '打开读档界面 (0x475e78)'),
    0x00cd: ('', 'set_registry_swdonline', 'C', '写注册表 HKLM\\SOFTWARE\\SoftStar\\SwdMD\\TW 的 DWORD 值 swdonline=1'),
    0x00d2: ('', 'wait_state_0f', 'P', '两段等待：先等 [0xafe96c]==0 (操作码改为 0x20d2)，再等 [0xafe980]!=0xf，然后复原操作码前进'),
    0x00d3: ('', 'wait_state_10', 'P', '两段等待：先等 [0xafe96c]==0 (操作码改为 0x20d3)，再等 [0xafe980]!=0x10，然后复原操作码前进'),
    0x00d4: ('', 'wait_state_11', 'P', '两段等待：先等 [0xafe96c]==0 (操作码改为 0x20d4)，再等 [0xafe980]!=0x11，然后复原操作码前进'),
    0x00f9: ('ii', 'replace_item', 'C', '把 1 个旧物品换成新物品：背包里有就扣 1 加新；否则若队员 2 第一装备槽 (+0x58a) 是旧物品就卸下、换成新物品再装备；都没有则直接给新物品'),
    0x00fa: ('dr', 'if_money_ge_goto', 'C', '金钱 ≥ 金额则跳转；不足则顺序执行 (原名方向反了)'),
    0x00fb: ('d', 'add_money', 'C', '金钱 [0xbcec84] += d，结果为负时置 0'),
    0x00fc: ('iw', 'give_item', 'C', '背包 (0xbceca0) 加入物品'),
    0x00fd: ('iw', 'take_item', 'C', '背包移除物品'),
    0x00fe: ('d', 'add_wood', 'C', '木材 [0xbcec88] += d (负数结果置 0)'),
    0x00ff: ('d', 'add_metal', 'C', '金属 [0xbcec8c] += d (负数结果置 0)'),
    0x0100: ('d', 'add_coal', 'C', '煤炭 [0xbcec90] += d (负数结果置 0)'),
    0x0101: ('d', 'sub_money', 'C', '金钱 [0xbcec84] -= d (负数结果置 0)'),
    0x0102: ('d', 'add_tech_points', 'C', '木甲技术点数 [0xbcec94] += d (负数结果置 0)'),
    0x0103: ('wd', 'add_member_magic_def', 'C', '队员「仙防」数值 (结构 +0x5a4, u16) 增减'),
    0x0104: ('ww', 'start_minigame_104', 'P', '进入一种特殊模式：重置镜头，置 [0x518e54]=1 和旗标 0x1f60，清 0x518aa0 状态区 (由 0x0105/0x0107 收尾)'),
    0x0105: ('w', 'wait_minigame_105', 'P', '等待 0x0104 模式达到条件'),
    0x0106: ('', 'clear_flag_518b60', 'C', '清 [0x518b60] 的 0x10 位'),
    0x0107: ('', 'end_minigame_107', 'P', '恢复 0x0104 之前保存的镜头 (0xa804a0→0xa80648, 0xa85238→0xa851b8)，清旗标 0x1f60'),
    0x0113: ('aw', 'set_actor_ai_temp', 'C', '只改当前在场角色的 AI 号 (不写地图角色表，不清动作)'),
    0x0118: ('iwr', 'if_item_goto', 'C', '背包中该物品数量 ≥ n 则跳转；n==1 时已装备在任一队员身上也算'),
    0x0119: ('wr', 'if_money_le_goto', 'C', '金钱 ≤ 金额则跳转'),
    0x0122: ('r', 'if_monster_room_goto', 'C', '妖怪收容容量 > 已有妖怪数则跳转 (还能再收一只)'),
    0x0123: ('w', 'add_monster', 'C', '收入一只妖怪 (加到 [0xea5168] 链表) 并调 0x44c5d7(id,10,0,0) 登记'),
    0x0124: ('w', 'remove_monster', 'P', '移除一只妖怪 (从设施槽位与妖怪链表中删除)'),
    0x0125: ('wr', 'if_has_monster_goto', 'C', '已拥有该妖怪则跳转'),
    0x012c: ('aww', 'set_actor_var', 'C', '设置角色私有变量 (同时写 gmRoleVar 表 [0xafe95c] 持久保存)；槽 1 在脚本中约定为对话次数'),
    0x012d: ('aww', 'add_actor_var', 'C', '角色私有变量 += n (上限 0xffff)，同步 gmRoleVar 表；常用作 NPC 对话计数 +1'),
    0x012e: ('aww', 'sub_actor_var', 'C', '角色私有变量 -= n (下限 0)，同步 gmRoleVar 表'),
    0x012f: ('awwr', 'if_actor_var_ge_goto', 'C', '角色变量 ≥ 比较值则跳转'),
    0x0130: ('awwr', 'if_actor_var_le_goto', 'C', '角色变量 ≤ 比较值则跳转'),
    0x0131: ('awwr', 'if_actor_var_eq_goto', 'C', '角色变量 == 比较值则跳转'),
    0x0136: ('waw', 'reg_to_actor_var', 'C', '把全局寄存器 k 的值写入角色私有变量 (同步 gmRoleVar 表)'),
    0x015e: ('w', 'op_015e', 'P', '由默认分支 0x4bb2e9 处理 (同一函数也被战斗脚本使用)：0x4af1b8(w)：调用 0x4ae3c4 后设置 [0xea4594]=w'),
    0x015f: ('ww', 'op_015f', 'P', '由默认分支 0x4bb2e9 处理 (同一函数也被战斗脚本使用)：0x4bb369(w1,w2) 写 [0xea1c98]/[0xea1c9c] 并置 [0xea1c94]=1，再执行 0x4bb388 插值；完成时长 6 (未完成返回 0 会走「不合法之指令」错误路径)'),
    0x0160: ('ww', 'op_0160', 'P', '由默认分支 0x4bb2e9 处理 (同一函数也被战斗脚本使用)：先调 0x4bb4c7，再同 0x0161'),
    0x0161: ('ww', 'op_0161', 'P', '由默认分支 0x4bb2e9 处理 (同一函数也被战斗脚本使用)：0x4a3781(w1,w2)：[0xdde524]=[0xea4598]=1，[0xea26dc]=w1，[0x4e6c50]=w2'),
    0x20a4: ('', 'wait_flag_a83cec_state', 'C', '0x00a4 的内部第二阶段 (自改写产生，不会出现在文件中)'),
    0x20ca: ('F', 'open_shop_state', 'C', '0x00ca 的内部等待阶段 (自改写产生)'),
    0x20d2: ('', 'wait_state_0f_state', 'C', '0x00d2 的内部第二阶段：等 [0xafe980]!=0xf'),
    0x20d3: ('', 'wait_state_10_state', 'C', '0x00d3 的内部第二阶段：等 [0xafe980]!=0x10'),
    0x20d4: ('', 'wait_state_11_state', 'C', '0x00d4 的内部第二阶段：等 [0xafe980]!=0x11'),
    0x4000: ('', 'nop', 'C', '空操作，与操作码 0x0000 共用处理函数 (原表名 popup_end 只是出现位置的推测)'),
}


def read_gll(path):
    b = open(path, 'rb').read()
    n = struct.unpack_from('<I', b, 16)[0] // 4
    offs = list(struct.unpack_from('<%dI' % n, b, 16))
    starts = sorted({o + 16 for o in offs if o != 0xFFFFFFFF}) + [len(b)]
    nxt = {s: starts[k + 1] for k, s in enumerate(starts[:-1])}
    return b, offs, nxt


def big5(raw):
    return _cc(raw.decode('big5', 'replace'))


def decode(d):
    """线性扫描; 返回 [(pos, op, end, args)], 状态。
    遇到无法解析的字节时, 以原始数据块 (op=None) 跳到下一个已知跳转目标继续 (状态 resync)。"""
    out, status, p = [], 'ok', 0
    while True:
        part, st, p = _decode_from(d, p, out)
        if st == 'ok' or st == 'eof':
            return out, status if st == 'ok' else 'eof'
        targets = sorted(fld + v for x in out if x[1] is not None for t, v, fld in x[3] if t == 'r')
        nxt = next((t for t in targets if t > p), None)
        if nxt is None or nxt > len(d):
            return out, st
        out.append((p, None, nxt, [('raw', d[p:nxt], p)]))
        status, p = f'resync ({st})', nxt


def _decode_from(d, p, out):
    while p + 2 <= len(d):
        op = struct.unpack_from('<H', d, p)[0]
        if op == 0xFFFF:
            out.append((p, op, p + 2, []))
            p += 2
            if p == len(d):
                return out, 'ok', p
            continue
        spec = OPS.get(op)
        if spec is None:
            return out, f'unknown op 0x{op:04x} @{p}', p
        q, args = p + 2, []
        try:
            for t in spec[0]:
                if t in 'wsafimbneM':
                    args.append((t, struct.unpack_from('<h' if t == 's' else '<H', d, q)[0], q)); q += 2
                elif t in 'dr':
                    args.append((t, struct.unpack_from('<i', d, q)[0], q)); q += 4
                elif t == 'T':
                    m = TEXT_RE.match(d, q)
                    if not m:
                        raise ValueError('text')
                    args.append(('T', m.group()[:-2], q)); q = m.end()
                elif t == 'F':
                    lst = []
                    while struct.unpack_from('<H', d, q)[0] != 0xFFFF:
                        lst.append(struct.unpack_from('<H', d, q)[0]); q += 2
                    q += 2
                    args.append(('F', lst, q))
                elif t == 'R':
                    while True:
                        v = struct.unpack_from('<i', d, q)[0]
                        if v == -1:
                            q += 4
                            break
                        args.append(('r', v, q)); q += 4
        except (struct.error, ValueError):
            return out, f'truncated op 0x{op:04x} @{p}', p
        out.append((p, op, q, args))
        p = q
    return out, 'eof', p


class Names:
    def __init__(self, text_dir):
        def load(n):
            p = os.path.join(text_dir, n)
            return json.load(open(p)) if os.path.exists(p) else None
        maps = load('maps.json') or []
        self.maps = {m['map_id']: m['name_simplified'] for m in maps}
        objs = load('objdata.json') or []
        # 脚本里的物品编号 = ObjDATA 下标 + 1 (read_Item 0x4037b2)
        self.items = {o['index'] + 1: o['name_simplified'] for o in objs if o.get('name_simplified')}
        nm = (load('gll/Name.json') or {}).get('entries', [])
        self.people = {}
        for e in nm:
            r = e
            while 'same_as' in r:
                r = nm[r['same_as']]
            if r.get('text_simplified'):
                self.people[e['index'] + 1] = r['text_simplified']
        self.music = {int(k): v['file'] for k, v in (load('music.json') or {}).get('tracks', {}).items()}
        bfs = (load('battlefields.json') or {}).get('battlefields', [])
        self.bf = {b['index'] + 1: b['name_simplified'] for b in bfs}
        self.triggers = defaultdict(list)
        for m in maps:
            for t in m['portals'] + m['triggers']:
                self.triggers[t['event_id']].append(
                    {'map_id': m['map_id'], 'map': m['name_simplified'],
                     'kind': t.get('kind', 'point'), 'name': t.get('name_simplified')})


def fmt_arg(t, v, names, labels):
    if t == 'r':
        return labels.get(v, f'rel{v:+d}')
    if t == 'T':
        return '"' + big5(v) + '"'
    if t == 'm':
        return f'{v}' + (f'<{names.maps[v]}>' if v in names.maps else '')
    if t == 'i':
        return f'{v}' + (f'<{names.items[v]}>' if v in names.items else '')
    if t == 'M':
        return f'{v}' + (f'<{names.music[v]}>' if v in names.music else '')
    if t == 'b':
        return f'{v}' + (f'<{names.bf[v]}>' if v in names.bf else '')
    if t == 'F':
        return '[' + ', '.join('0x%04x' % x for x in v) + ']'
    if t in 'an':
        return '0x%04x' % v + (f'<{names.people[v]}>' if v in names.people else '')
    if t == 'f':
        return '0x%04x' % v
    return str(v)


def disasm_text(d, ins, names):
    targets = {}
    for p, op, q, args in ins:
        for t, v, fld in args:
            if t == 'r' and op is not None:
                targets[fld + v] = None
    labels_at = {pos: f'L_{pos:04x}' for pos in sorted(targets)}
    lines = []
    for p, op, q, args in ins:
        if p in labels_at:
            lines.append(f'{labels_at[p]}:')
        if op == 0xFFFF:
            lines.append(f'  {p:5d}  end')
            continue
        if op is None:
            lines.append(f'  {p:5d}  .data                  ' + args[0][1].hex(' ') + '   ; 无法解析, 跳到下一个跳转目标')
            continue
        spec = OPS[op]
        shown = []
        for t, v, fld in args:
            if t == 'r':
                shown.append(labels_at.get(fld + v, f'@{fld + v}'))
            else:
                s = fmt_arg(t, v, names, {})
                if s is not None:
                    shown.append(s)
        lines.append(f'  {p:5d}  {spec[1]:<22s} ' + ', '.join(shown))
    bad = [pos for pos in targets if pos not in {x[0] for x in ins} and pos != len(d)]
    return lines, bad


FILES = [('talks1-1.gll', 1, 500), ('talks1-2.gll', 501, 1000), ('talks1-3.gll', 1001, 1500),
         ('talks1-4.gll', 1501, 2000), ('talks2.gll', 2001, 5000), ('Talks3.GLL', 5001, 7979)]


def summarize(ins, names):
    s = defaultdict(list)
    for p, op, q, args in ins:
        if op is None:
            continue
        a = [v for t, v, _ in args]
        if op == 0x0032:
            s['change_map'].append({'map_id': a[0], 'map': names.maps.get(a[0]), 'pos': a[1:4]})
        elif op == 0x0051:
            s['battles'].append({'battlefield': a[0], 'name': names.bf.get(a[0])})
        elif op == 0x005a:
            s['videos'].append(big5(a[0]))
        elif op == 0x00fc:
            s['give_items'].append({'item': a[0], 'name': names.items.get(a[0]), 'count': a[1]})
        elif op == 0x00fd:
            s['take_items'].append({'item': a[0], 'name': names.items.get(a[0]), 'count': a[1]})
        elif op == 0x00fb:
            s['money'].append(a[0])
        elif op in (0x00fe, 0x00ff, 0x0100, 0x0102):
            s[OPS[op][1]].append(a[0])
        elif op == 0x0006:
            s['set_flags'].append(a[0])
            if 7001 <= a[0] <= 7256:
                s['mission_accept'].append(a[0])
            elif 7257 <= a[0] <= 7512:
                s['mission_complete'].append(a[0] - 256)
        elif op == 0x0090:
            s['music'].append({'track': a[0], 'file': names.music.get(a[0]), 'then': a[2], 'then_file': names.music.get(a[2])})
        elif op == 0x0050:
            s['call_event'].append(a[0])
        elif op == 0x0101:
            s['money'].append(-a[0])
        elif op == 0x0039:
            s['set_floor'].append(a[0])
        elif op == 0x000a and len(s['lines']) < 3:
            t = re.sub(r'%[A-Z]\d?', '', big5(a[-1])).replace('%N', ' ').strip('`')
            s['lines'].append(t)
    if 'set_flags' in s:
        s['set_flags'] = sorted(set(s['set_flags']) - {0x1F90})
        if not s['set_flags']:
            del s['set_flags']
    return dict(s)


def main(game, out):
    text_dir = os.path.join(os.path.dirname(os.path.abspath(out)), 'text')
    names = Names(text_dir)
    os.makedirs(out, exist_ok=True)
    index, stats = {}, Counter()
    opfreq = Counter()
    for fname, lo, hi in FILES:
        b, offs, nxt = read_gll(os.path.join(game, fname))
        stem = os.path.splitext(fname)[0]
        os.makedirs(os.path.join(out, stem), exist_ok=True)
        default = offs[lo - 1]
        owners = defaultdict(list)
        for slot, o in enumerate(offs):
            if o != 0xFFFFFFFF and (o != default or slot == lo - 1):
                owners[o].append(slot)
        for o, slots in sorted(owners.items()):
            s = o + 16
            d = b[s:nxt[s]]
            ins, st = decode(d)
            stats['entries'] += 1
            stats[st.split(' ')[0] if st != 'ok' else 'ok'] += 1
            for x in ins:
                opfreq[x[1]] += 1
            lines, bad = disasm_text(d, ins, names)
            stats['bad_targets'] += len(bad)
            events = [sl + 1 for sl in slots]
            head = [f'; {fname}  slots {slots}  events {events}  offset 0x{s:x}  size {len(d)}  parse: {st}']
            for e in events:
                for t in names.triggers.get(e, []):
                    head.append(f';   trigger: map {t["map_id"]} {t["map"]}  [{t["kind"]}] {t["name"] or ""}')
            if st != 'ok':
                p = ins[-1][2] if ins else 0
                head.append(f';   未解析余下 {len(d) - p} 字节: ' + d[p:p + 64].hex(' '))
            with open(os.path.join(out, stem, f'{events[0]:04d}.txt'), 'w') as f:
                f.write('\n'.join(head + lines) + '\n')
            summ = summarize(ins, names)
            for e in events:
                index[e] = {'file': fname, 'slot': e - 1, 'disasm': f'{stem}/{events[0]:04d}.txt',
                            'shared_with': [x for x in events if x != e], 'parse': st,
                            'triggers': names.triggers.get(e, []), **summ}
    # 触发区引用但没有自己脚本的事件
    missing = sorted(e for e in names.triggers if e not in index)
    covered = sorted(e for e in names.triggers if e in index)
    with open(os.path.join(out, 'events_index.json'), 'w') as f:
        json.dump({'events': {str(k): v for k, v in sorted(index.items())},
                   'trigger_events_without_script': {str(e): names.triggers[e] for e in missing}},
                  f, ensure_ascii=False, indent=1)
    with open(os.path.join(out, 'opcodes.json'), 'w') as f:
        json.dump({'%04x' % op: {'operands': v[0], 'name': v[1], 'status': v[2], 'note': v[3],
                                 'count': opfreq.get(op, 0)} for op, v in sorted(OPS.items())},
                  f, ensure_ascii=False, indent=1)
    print('events', dict(stats), 'trigger events with script', len(covered), 'without', len(missing))
    write_opcode_doc(os.path.join(out, 'opcodes.md'), opfreq)
    objnames = {o['index']: o.get('name_simplified') for o in
                (json.load(open(os.path.join(text_dir, 'objdata.json'))) if os.path.exists(os.path.join(text_dir, 'objdata.json')) else [])}
    bstats = battle_main(game, out, names, objnames)
    print('battle', bstats)
    with open(os.path.join(out, 'coverage.json'), 'w') as f:
        json.dump({'event_scripts': dict(stats), 'battle_scripts': bstats,
                   'trigger_events_with_script': len(covered), 'trigger_events_without_script': len(missing)},
                  f, ensure_ascii=False, indent=1)


TYPE_DOC = {'w': 'u16', 's': 'i16', 'd': 'i32', 'r': '跳转', 'a': '角色', 'u': '战斗单位槽', 'm': '地图', 'f': '旗标',
            'i': '物品', 'b': '战场', 'n': '名字号', 'e': '事件', 'M': '曲目', 'c': 'u8', 'T': '文本',
            'F': 'u16 列表', 'R': '跳转表', 'P': '(百分比,跳转)表'}


def write_opcode_doc(path, opfreq):
    """由 OPS / battle_vm.json 生成指令表文档"""
    def esc(x):
        return x.replace('|', '\\|')
    out = ['# 脚本指令表（自动生成，勿手改）', '',
           '由 `tools/disasm_script.py` 根据代码里的指令表生成。指令表全部来自 SWDMD_GB.EXE 解释器的逆向；',
           '状态 **C** = 汇编直接确认，**P** = 汇编能看出做了什么，具体用途是推断。', '',
           '## 事件脚本 (talks*.gll)', '', '| 操作码 | 助记符 | 操作数 | 状态 | 出现次数 | 说明 |', '|---|---|---|---|---|---|']
    for op, (fmt, name, st, note) in sorted(OPS.items()):
        out.append(f'| `{op:04x}` | {name} | {", ".join(TYPE_DOC.get(t, t) for t in fmt) or "—"} | {st} | {opfreq.get(op, 0)} | {esc(note)} |')
    for fname, vm in BATTLE_VM.items():
        if not vm:
            continue
        out += ['', f'## {fname}', '', f'解释器：{vm.get("source", "")}；{vm.get("slot", "")}', '',
                '| 操作码 | 助记符 | 操作数 | 长度 | 状态 | 说明 |', '|---|---|---|---|---|---|']
        for k, e in sorted(vm['ops'].items(), key=lambda kv: int(kv[0], 16)):
            ln = e['len'] if isinstance(e['len'], str) else (f'2+{e["len"][0]}' + (f'+{e["len"][1]} 段文本' if e['len'][1] else '')
                                                            if e['len'][0] != 'ffl' else 'u16 列表+跳转')
            out.append(f'| `{int(k, 16):04x}` | {e["name"]} | {", ".join(TYPE_DOC.get(t, t) for t in e.get("types", "")) or "—"} '
                       f'| {ln} | {e["status"]} | {esc(e.get("note", ""))} |')
    out += ['', '## AI.GLL', '', '由 `tools/decompile_ai.py` 直接翻译成人话，指令表见该文件的 `ASM`。']
    with open(path, 'w') as f:
        f.write('\n'.join(out) + '\n')


# ---------------- 战斗脚本 (FIGTALK / ATK) ----------------
# 指令表来自 exe 逆向, 存于 battle_vm.json: op -> {len, types, name, status, note, jumps, list}
#   len: [参数字节数, 内嵌文本个数] | 'u32l' (ffffffff 结尾 u32 列表) | ['ffl', 前置字节, 后置字节] (ffff 结尾 u16 列表)
#   jumps: [[字段相对指令起点的偏移, 'fld' (目标=字段地址+值) | 'op' (目标=指令起点+值)]]
#   list: 'self' (列表每项是相对自身的 rel32) | 'after_ffff' (ffff 列表之后的 rel32)
# AI.GLL 由 decompile_ai.py 直接翻译成人话。
BATTLE_VM = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'battle_vm.json'), encoding='utf-8'))
BATTLE_FILES = [(f, 'battlefield' if f == 'FIGTALK.GLL' else 'objdata') for f in BATTLE_VM if BATTLE_VM[f]]
TSIZE = {'w': 2, 's': 2, 'u': 2, 'f': 2, 'i': 2, 'b': 2, 'a': 2, 'm': 2, 'n': 2, 'e': 2, 'c': 1, 'd': 4, 'r': 4}


def battle_table(fname):
    return {int(k, 16): (v['len'] if isinstance(v['len'], str) else tuple(v['len'])) for k, v in BATTLE_VM[fname]['ops'].items()}


def decode_bytes(d, table):
    p, out = 0, []
    while p + 2 <= len(d):
        op = d[p] | (d[p + 1] << 8)
        if op == 0xFFFF:
            out.append((p, op, p + 2))
            p += 2
            if p == len(d):
                return out, 'ok'
            continue
        spec = table.get(op)
        if spec is None:
            return out, f'unknown op 0x{op:04x} @{p}'
        if spec == 'u32l':
            q = p + 2
            while q + 4 <= len(d) and d[q:q + 4] != b'\xff\xff\xff\xff':
                q += 4
            q += 4
        elif spec[0] == 'ffl':
            q = p + 2 + spec[1]
            while q + 2 <= len(d) and d[q:q + 2] != b'\xff\xff':
                q += 2
            q += 2 + spec[2]
        else:
            q = p + 2 + spec[0]
            for _ in range(spec[1]):
                m = TEXT_RE.match(d, q)
                if not m:
                    return out, f'bad text op 0x{op:04x} @{p}'
                q = m.end()
        if q > len(d):
            return out, f'truncated op 0x{op:04x} @{p}'
        out.append((p, op, q))
        p = q
    return out, 'eof'


def battle_jumps(d, p, q, e):
    """返回 [(字段地址, 目标)]"""
    res = []
    for off, base in e.get('jumps', []):
        fld = p + off
        if fld + 4 <= len(d):
            res.append((fld, (fld if base == 'fld' else p) + struct.unpack_from('<i', d, fld)[0]))
    if e.get('list') == 'self':
        for fld in range(p + 2, q - 4, 4):
            res.append((fld, fld + struct.unpack_from('<i', d, fld)[0]))
    elif e.get('list') == 'after_ffff':
        fld = q - 4
        res.append((fld, fld + struct.unpack_from('<i', d, fld)[0]))
    return res


def battle_operands(d, p, q, types, labels, names):
    """按操作数类型解码; 类型与长度对不上时返回 None (改为显示原始字节)"""
    k, out = p + 2, []
    try:
        for t in types:
            if t == 'T':
                m = TEXT_RE.match(d, k)
                out.append('"' + big5(m.group()[:-2]) + '"')
                k = m.end()
            elif t == 'F':
                lst = []
                while d[k:k + 2] != b'\xff\xff':
                    lst.append(struct.unpack_from('<H', d, k)[0]); k += 2
                k += 2
                out.append('[' + ', '.join('0x%04x' % x for x in lst) + ']')
            elif t == 'R':
                lst = []
                while d[k:k + 4] != b'\xff\xff\xff\xff':
                    lst.append(labels.get(k, '?')); k += 4
                k += 4
                out.append('[' + ', '.join(lst) + ']')
            elif t == 'r':
                out.append(labels.get(k, '?')); k += 4
            elif t == 'c':
                out.append(str(d[k])); k += 1
            elif t == 'd':
                out.append(str(struct.unpack_from('<i', d, k)[0])); k += 4
            elif t == 's':
                out.append(str(struct.unpack_from('<h', d, k)[0])); k += 2
            elif t == 'u':
                v = struct.unpack_from('<H', d, k)[0]; k += 2
                out.append(f'unit{v}' if v < 0x100 else '0x%04x' % v)
            else:
                v = struct.unpack_from('<H', d, k)[0]; k += 2
                out.append(fmt_arg(t, v, names, {}))
    except (struct.error, AttributeError):
        return None
    return out if k == q else None


def render_battle(fname, d, ins, names):
    ops = BATTLE_VM[fname]['ops']
    jt, lab = {}, {}
    for p, op, q in ins:
        e = ops.get('0x%04x' % op)
        if e:
            for fld, t in battle_jumps(d, p, q, e):
                jt[fld] = t
    starts = {p for p, _, _ in ins}
    for fld, t in jt.items():
        lab[fld] = f'L_{t:04x}' if t in starts or t == len(d) else f'@{t}?'
    targets = set(jt.values())
    lines = []
    for p, op, q in ins:
        if p in targets:
            lines.append(f'L_{p:04x}:')
        if op == 0xFFFF:
            lines.append(f'  {p:5d}  end')
            continue
        e = ops.get('0x%04x' % op, {})
        args = battle_operands(d, p, q, e.get('types', ''), lab, names)
        if args is None:
            args = [d[p + 2:q].hex(' ')]
        lines.append(f'  {p:5d}  {e.get("name", "op_%04x" % op):<24s} ' + ', '.join(args))
    if len(d) in targets:
        lines.append(f'L_{len(d):04x}:')
    bad = sum(1 for t in targets if t not in starts and t != len(d))
    return lines, bad


def battle_main(game, out, names, objnames):
    stats = {}
    for fname, kind in BATTLE_FILES:
        b, offs, nxt = read_gll(os.path.join(game, fname))
        table = battle_table(fname)
        stem = os.path.splitext(fname)[0]
        os.makedirs(os.path.join(out, 'battle', stem), exist_ok=True)
        owners = defaultdict(list)
        for slot, o in enumerate(offs):
            if o != 0xFFFFFFFF:
                owners[o].append(slot)
        st_c = Counter()
        atk_users = defaultdict(list)  # ATK 编号 -> 使用它的对象 (stats 里的 0x3ED 字段)
        stats_dir = os.path.join(os.path.dirname(os.path.abspath(out)), 'stats')
        for fn in sorted(os.listdir(stats_dir)) if os.path.isdir(stats_dir) else []:
            if fn.endswith('.json'):
                recs = json.load(open(os.path.join(stats_dir, fn)))
                for r in recs if isinstance(recs, list) else []:
                    if isinstance(r, dict) and r.get('动作脚本 action_id(ATK.GLL)'):
                        atk_users[r['动作脚本 action_id(ATK.GLL)']].append(f"{r.get('编号 id')} {r.get('名称 name')}")
        for o, slots in sorted(owners.items()):
            s = o + 16
            d = b[s:nxt[s]]
            ins, st = decode_bytes(d, table)
            st_c['ok' if st == 'ok' else 'fail'] += 1
            first = slots[0]
            if kind == 'battlefield':
                desc = f'战场 {first} {names.bf.get(first, "")}'
            else:  # ATK: 槽位 k = ATK 编号 k+1
                us = [u for sl in slots for u in atk_users.get(sl + 1, [])]
                desc = f'ATK 编号 {[sl + 1 for sl in slots[:8]]}' + (f'  使用者: {", ".join(us[:6])}' if us else '')
            lines, bad = render_battle(fname, d, ins, names)
            st_c['bad_targets'] += bad
            head = [f'; {fname}  slots {slots[:20]}{" ..." if len(slots) > 20 else ""}  ({desc})  size {len(d)}  parse: {st}']
            if st != 'ok':
                p = ins[-1][2] if ins else 0
                lines.append(f'  {p:5d}  .data  ' + d[p:].hex(' ') + '   ; 未解析')
            with open(os.path.join(out, 'battle', stem, f'{first:04d}.txt'), 'w') as f:
                f.write('\n'.join(head + lines) + '\n')
        stats[fname] = dict(st_c)
    return stats


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
