"""主角技能图鉴: 每个技能 → ATK 招式脚本 → 动作序列 (供 Godot 技能预览场景)

链路: magic.json 的「习得」→ 技能的 ATK 编号 (槽位 = 编号-1, 见 disasm_script / ATK README)
      → 解码 ATK 脚本, 沿「命中」分支顺序收集步骤 (移动 / 姿势 / 等待 / 特效 / 结算)
      → 姿势编号查 ACT/all_char.act (act.py) 得到 PLY 动画 → 合成每个角色一个 GLB (同一网格的全部动作)
输出: <输出目录>/skills.json, <输出目录>/<角色>.glb
用法: python skill_catalog.py <游戏目录> <输出目录>   (读取 extracted/stats/{characters,magic}.json)
"""
import json
import os
import struct
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from act import actions  # noqa: E402
from disasm_script import BATTLE_VM, battle_jumps, battle_table, decode_bytes, read_gll  # noqa: E402
from ply import parse  # noqa: E402
from ply2gltf import export  # noqa: E402

# 战斗单位的 ACT 号 = ObjDATA 编号 + 1 (嬴诗 2, 桓远之 3, 云狐 11; act.py 稠密索引; 各自技能用到的姿势全部在该 ACT 内)
# 车芸本人不上场, 她的技能 (续衔/千羽) 由木甲机关云狐施展
HEROES = {2: 2, 3: 3, 11: 11}   # 游戏编号 → ACT (二者相同)
# 手持武器 = 道具 ACT (武器物品号即 ACT 号, all_item.act) 的第 1 号动作 (事件指令 0x8a set_weapon_model 例: 慕容诗 4101 蝉鸣剑, qq 1)
# 挂点: 0x8a 第 4 个参数 n → 角色模型里 flags>>24 == n 的段 (exe 0x419eee); 剧情里为 1 (持剑的手)
# 武器矩阵 = 该段当前帧矩阵, 旋转部分整体取负 (0x419f57 起逐个 fchs), 平移不变 → [-R | t] × 武器自身动画
WEAPONS = {'嬴诗': (4101, 1), '桓远之': (4201, 1)}
TSIZE = {'w': 2, 's': 2, 'c': 1, 'd': 4, 'r': 4}
# 移动类指令 → (目的地, 使用的动作); 动作号来自 battle_vm.json 的说明 (0x38 跑, 0x39 跳, 0x3a/0x3c 冲刺)
# 移动指令 (逆向见 re/move_re.md): op → (目的地, 模式, 播的动作 QQ)
#   进入移动状态时 set_state (0x431aa3 → 0x432030) 把 ATK set_pose 写的动作清 0, 所以播的是各状态的默认动作;
#   以前把状态号 0x38/0x39/0x3a/0x3c 当成动作号 56/57/58/60, 是错的
#   run: 线性, 速度 = 参数 / tick, 目的地 = 目标 + 0x34 偏移再退 100 (0x447214 → 0x433c09), 距离 ≤ 速度 + 5 结束 (0x43b930)
#   arc: 抛物线, 向上初速 = 参数 (0x0f 固定 10), 重力 1 (0x49597a)
#   dash: 线性回原位 (目的地 = 原位退 100), 距离 < 30 吸附到原位 (0x43be2b)
MOVES = {0x000E: ('target', 'run', 0x1C), 0x0051: ('point', 'run', 0x1C), 0x008D: ('point', 'run', 0x1C),
         0x0032: ('target', 'arc', 0x26), 0x000F: ('home', 'arc', 0x27),
         0x0041: ('home', 'dash', 0x1C), 0x0091: ('home', 'dash', 0x39), 0x0092: ('home', 'dash', 0x3A),
         0x007F: ('home', 'dash', 0x1D)}
# 0x02 (exe 0x448a54): 默认对每个目标各放一个, 位置 = 目标 + 偏移 (世界轴); 之前执行过 0x04 时只放一个,
#   位置 = 战场原点 + 偏移 (只有施术者是护驾 +0x19ec / +0x19f0 召唤物时 z 取反, 0x448acb; 我方队员 +0x19f0 = 0), 0x04 用一次即清零。0x03: 施术者 (或 0x4f 挂点) + 偏移, 每个目标一个
EFFECTS = {0x0002: 'targets', 0x0003: 'to_targets', 0x0006: 'targets', 0x0007: 'caster', 0x0008: 'to_targets',
           0x000C: 'caster'}
HITS = {0x0016, 0x008B}
FPS = 35.0  # 游戏逻辑帧率 (事件指令 0x88: 帧时间 1000/35 ms), ACT 播放表每项一帧


def operands(d, p, types):
    out, k = [], p + 2
    for t in types:
        if t not in TSIZE:
            break
        fmt = {'w': '<H', 's': '<h', 'c': '<B', 'd': '<i', 'r': '<i'}[t]
        out.append(struct.unpack_from(fmt, d, k)[0])
        k += TSIZE[t]
    return out


# 原版镜头 (对象 0x908228, 逆向见 godot/scripts/skill_preview.gd 的「原版镜头」一节):
#   通道 A = 注视点, B = 角度, C = 距离; 模式 1 瞬切 / 2 匀速 / 3 指数缓动
CAMERA_OPS = {0x001E: 'reset_follow', 0x001F: 'release', 0x0020: 'mode_ab', 0x0021: 'speed_a', 0x0022: 'speed_b',
              0x0023: 'speed_c', 0x0024: 'instant', 0x0025: 'instant_off', 0x0026: 'pos', 0x0027: 'look',
              0x0028: 'zoom', 0x0029: 'follow_caster', 0x002A: 'follow_target', 0x002C: 'mode_a', 0x002D: 'mode_b',
              0x002E: 'mode_c', 0x003E: 'restore'}


def steps_of(d, ins, start=0):
    """从偏移 start 起线性展开到 end (0xFFFF); 条件跳转 (if_hit_result_goto 等) 按「命中」走下去"""
    ops = BATTLE_VM['ATK.GLL']['ops']
    steps = []
    offset = [0, 0, 0]  # 0x34 set_offset 设定的特效偏移 (游戏单位)
    single = False      # 0x04: 下一条 0x02 只放一个, 位置按战场原点 (exe 0x448a9c, 用后清零)
    rotate = False      # 0x73: 0x03 的偏移是否按施术者朝向旋转 (exe 0x448ec0)
    origin = 0          # 0x4f: 下一条 0x03 的起点改为施术者挂点 (v+1) 的世界坐标 (exe 0x436563 / 0x448ea7)
    face = False        # 0x4c: 下一条 0x02/0x03 按施术者→目标方向定朝向
    at_step = {}        # 指令位置 → 该位置之后第一个步骤的下标 (解析 if_hit 的跳转目标)
    fig = False         # 0x70 set_actor_mode 1: 施术者是云狐时, 之后的指令以车芸本体为执行者 ([0x907964], [0x925b48])
    jumps = []
    actor = None        # 0x8e / 0x8f: 换执行者 ([0x907964]=2, [0x925b48]=槽)
    for p, op, q in ins:
        if p < start:
            continue
        at_step[p] = len(steps)
        if op == 0xFFFF:
            # 结束; 后面若还有指令 (条件跳转的另一段, 例 攻击云狐的版本), 继续展开, 跳转才找得到
            if all(tp <= p for _, tp in jumps):
                break
            steps.append({'t': 'end'})
            continue
        e = ops.get('0x%04x' % op, {})
        a = operands(d, p, e.get('types', ''))
        if op == 0x0070:
            fig = bool(a[0])
            continue
        if op == 0x008E:
            actor = a[0]   # set_actor_unit: 之后的执行者换成 b 号槽的单位 (例 墨衡的机关臂 7 号槽抡锤)
            continue
        if op == 0x008F:
            actor = None   # reset_actor: 执行者恢复为施术者
            continue
        n0 = len(steps)
        if op == 0x0082:
            steps.append({'t': 'chant_release', 'atk': a[0]})  # 起咒脚本写入吟咒释放时的 ATK (caster+0x1b9c, 0x44c4a1)
            continue
        if op == 0x0074:
            steps.append({'t': 'roll', 'mode': a[0]})  # roll_hit: 1 按命中/回避判定, 6 必中
            continue
        if op == 0x0075:
            # if_hit_result_goto: 第一个目标的判定结果等于 v 时跳转 (0 = 闪避 → 跳过火花等命中特效)
            tgt = [t for _, t in battle_jumps(d, p, q, e)]
            steps.append({'t': 'if_hit', 'value': a[0], 'to': None})
            jumps.append((steps[-1], tgt[0] if tgt else q))
            continue
        if op in (0x0071, 0x0094):
            # 0x71: 目标表里有未倒的云狐 (+0x196a==0xb) 就跳转 (攻击云狐另有一段, 位置偏移不同)
            # 0x94 (谁, 条件): 谁 0 = 施术者 / 1 = 第一个目标; 条件 0 = 我方 (+0x19c0 bit0) / 1 = 护驾 (+0x19ec) / 2 = 云狐; 真则跳转
            # (exe 0x44bda2 / 0x448704; 以前没处理, 两段都按顺序执行或只走第一段)
            tgt = [t for _, t in battle_jumps(d, p, q, e)]
            if op == 0x0071:
                st = {'t': 'branch', 'who': 'targets', 'cond': 'yunhu', 'to': None}
            else:
                st = {'t': 'branch', 'who': 'caster' if a[0] == 0 else 'target',
                      'cond': {0: 'party', 1: 'summon', 2: 'yunhu'}.get(a[1], 'none'), 'to': None}
            steps.append(st)
            jumps.append((st, tgt[0] if tgt else q))
            continue
        if op == 0x0015:
            steps.append({'t': 'pose', 'pose': a[0]})
        elif op in MOVES:
            to, mode, pose = MOVES[op]
            st = {'t': 'move', 'to': to, 'mode': mode, 'pose': pose, 'kind': e.get('name', '')}
            if op == 0x000F:
                st['speed'] = 10   # 0x44a191: fld [0x4cd3a4] = 10.0
            elif a and 'speed' not in st:
                st['speed'] = a[0]
            if op in (0x000E, 0x0032):
                st['offset'] = list(offset)   # 停点 = 目标 + 0x34 偏移 (世界轴), 再朝施术者退 100 (exe 0x447214 / 0x433f44)
            if op in (0x000E, 0x0032, 0x0051) and a:
                st['speed'] = a[0]  # 跑: 每帧移动的游戏单位 (exe 0x433e9b: 速度 = 参数 × 朝向)
            steps.append(st)
        elif op == 0x0013:
            steps.append({'t': 'wait_anim', 'frame': a[0]})
        elif op == 0x0019:
            # 0x449fb4: 参数 ×10 与毫秒计时器比较 → 单位 10 毫秒
            steps.append({'t': 'wait', 'ms': a[0] * 10})
        elif op == 0x0034:
            offset = list(a[:3])
        elif op == 0x0004:
            single = True
        elif op == 0x0073:
            rotate = bool(a[0])
        elif op == 0x004F:
            origin = a[0] + 1  # 0x419e3d 按 (v+1)<<24 找挂点段
        elif op == 0x004C:
            face = True
        elif op in EFFECTS:
            at = EFFECTS[op]
            st = {'t': 'effect', 'id': a[0], 'sub': a[1] if len(a) > 1 else 0, 'at': at, 'offset': offset}
            if op == 0x0002 and single:
                st['at'] = 'field'
                single = False
            if op == 0x0002 and face and st['at'] == 'targets':
                st['offset'] = [0, 0, 0]  # 0x448cf5: 带 0x4c 时偏移清零, 朝向改为施术者→目标
            if op == 0x0003:
                st['rotate'] = rotate
                if origin:
                    st['origin_marker'] = origin
                origin = 0
            if face:
                st['face'] = True
                face = False
            steps.append(st)
        elif op == 0x0035:
            steps.append({'t': 'stop_fx', 'id': a[0], 'sub': a[1]})
        elif op == 0x003B:
            # 武器拖尾 (a, R, G, B, n): a=0 关闭
            steps.append({'t': 'trail', 'on': a[0] != 0, 'alpha': a[0], 'rgb': a[1:4], 'len': a[4]})
        elif op == 0x0036:
            # 残影 (开关, 间隔?, 个数?, A, R, G, B) —— exe 0x434a32, 参数含义为推测
            steps.append({'t': 'afterimage', 'on': a[0] == 1, 'args': a[1:3], 'argb': a[3:7]})
        elif op == 0x003A:
            # 画面环境色: 从 (R,G,B) 以每 tick 约「参数」的 RGB 距离逼近 (R2,G2,B2) (exe 0x44b3cc / 0x478e10)
            steps.append({'t': 'tint', 'speed': a[0], 'from': a[1:4], 'to': a[4:7]})
        elif op == 0x006D:
            steps.append({'t': 'warp', 'offset': a[:3]})  # 瞬移到第一个目标 + 偏移
        elif op in CAMERA_OPS:
            steps.append({'t': 'cam', 'op': CAMERA_OPS[op], 'args': a})
        elif op in (0x0076, 0x0077):
            # 0x76 等 g (播放器标志 0x10000000), 0x77 等 e (0x40000000); 读到即清 (0x43d752), 换动作时全部清零 (0x41d2c0 memset)
            steps.append({'t': 'wait_mark', 'mark': 'g' if op == 0x0076 else 'e'})
        elif op == 0x0053:
            steps.append({'t': 'wait_fx', 'id': a[0], 'sub': a[1], 'frame': a[2]})
        elif op == 0x0005:
            steps.append({'t': 'wait_fx', 'id': a[0], 'sub': a[1], 'frame': 0})
        elif op == 0x0031:
            # 0x44a8ac → 0x48f7e4: 等全屏图层 (12 块贴图 + 逐帧递减透明度, 0x48f689) 的标志 [0xc75374] 清零;
            # 整个程序里没有任何指令把它置位 (只有 0x48f7ac 清零), 所以永远立即通过 —— 不生成步骤
            # (以前当成「等所有特效播完」, 是推测, 会让这 12 段招式多等)
            continue
        elif op in HITS:
            steps.append({'t': 'hit'})
        elif op == 0x003F:
            steps.append({'t': 'sound', 'id': a[0]})
        elif op == 0x0037:
            # set_units_alpha (on, 组, 速度) exe 0x44ab88 → 0x434947: on 1 淡出 / 0 淡入; 速度 255 = 瞬间, 否则每 tick 改变的透明度
            # 组 3 = 除施术者和目标外的全部单位; 4 = 施术者那一方的其他单位; 1 / 2 / 5..7 (少见) 未细分, 按 3 处理
            steps.append({'t': 'units_alpha', 'on': a[0], 'group': a[1], 'speed': a[2]})
        elif op == 0x007D:
            steps.append({'t': 'units_alpha', 'on': 0, 'group': 'targets', 'speed': a[0]})
        elif op in (0x0084, 0x0085):
            steps.append({'t': 'units_alpha', 'on': 1 if op == 0x0084 else 0, 'group': 'type', 'type': a[0], 'speed': a[1]})
        elif op == 0x0064:
            # play_video: 播放 Bink 过场 (车芸 狐人 / 万剐 / 伏兵 / 火砲 / 穿云), 文件名是 0 结尾的字串
            steps.append({'t': 'video', 'file': d[p + 2:q].split(b'\0')[0].split(b'.bik')[0].decode('latin-1') + '.bik'})
        elif op == 0x0081:
            # show_message: 画面上方的系统提示 (例 嬴诗普攻二连击「二连斩」); Big5 字串
            from disasm_script import big5
            steps.append({'t': 'message', 'text': big5(d[p + 2:q].split(b'\0')[0].split(b'%Q')[0])})
        elif op == 0x006C:
            # 施术者淡出 / 淡入 (exe 0x4349a7, 绘制 0x43e06d): on 0 = 按速度淡出后隐藏, 1 = 从透明淡入; 速度 = 每 tick 透明度变化
            steps.append({'t': 'caster_fade', 'on': a[0], 'speed': a[1]})
        elif op == 0x0046:
            steps.append({'t': 'summon', 'id': a[0]})   # 召唤一个单位 (exe 0x44b7d8): 新单位成为目标
        elif op == 0x0080:
            steps.append({'t': 'summon', 'id': a[0], 'pos': list(a[1:4])})   # 在指定坐标召唤
        elif op == 0x0090:
            steps.append({'t': 'steal_money', 'amount': a[0]})   # 每个目标 80% 机率增减队伍金钱 (0x43b173)
        elif op == 0x0086:
            steps.append({'t': 'transform', 'id': a[0]})   # 变身: 施术者换成另一个 ObjDATA 记录 (保留当前 HP / MP, 换模型; exe 0x43b05e)
        elif op == 0x0078:
            from disasm_script import big5
            # 执行者头上的台词气泡 (exe 0x447c87 → add_talkmsg): 参数 = 宽 (字数) w7, 高 (行数) w8; 文本保留 %N 等控制码
            steps.append({'t': 'bubble', 'w': a[0], 'h': a[1], 'text': big5(d[p + 6:q].split(b'\0')[0].split(b'%Q')[0]) + '%Q'})
        elif op == 0x007B:
            steps.append({'t': 'wait_bubbles'})   # 等所有台词气泡关掉 ([0xa84c4c] == 0)
        elif op == 0x0049:
            # 镜头震动 (exe 0x44b920, 每帧 0x4414a2): 1 = 开始 (幅度 10, 每 3 帧换向, 每帧 −1 到 0 为止), 0 = 停止; 加在镜头注视点 y 上
            steps.append({'t': 'shake', 'on': a[0]})
        elif op == 0x0033:
            # 执行者动画暂停 / 恢复 (0x434a03 / 0x439c15: +0xd4 bit4 = ACT 播放器不前进); 脚本里 1008 处是「恢复」, 8 处冻结
            steps.append({'t': 'anim_pause', 'on': a[0]})
        elif op == 0x003D:
            # 旗标 8051 (0x447854): 1 = 置位, 0 = 清除并结束本帧 (多等 1 tick); 战斗画面在旗标清除时叠一层 alpha 8/255 的黑 (0x44232b)
            steps.append({'t': 'flag8051', 'on': a[0]})
        elif op == 0x0098:
            # 全屏覆盖闪光 (0x448819 → 0x925a28 播放器, 每帧 0x442619 用 0x46a983 画成 (2.1+1)×(1.35+1) 倍 = 800×600 的 2D 精灵):
            # ACT 7042 QQ v (0 一次 10 帧, 1 循环); 0xffff = 清除
            steps.append({'t': 'overlay', 'sub': a[0] if a[0] != 0xFFFF else -1})
        elif op == 0x004A:
            # 每个目标生成 3 个本体虚影 (0x436911): 当前动作定格, 从目标位置升到挂点 2 + 200 高, 各 20 / 25 / 30 帧淡出 (破胆 / 裂心 / 震慑 / 威吓 / 雷霆威吓)
            steps.append({'t': 'target_ghosts'})
        elif op == 0x0087:
            steps.append({'t': 'variant', 'v': a[0]})   # 施术者 +0x1928 (四首变化: 选用哪一套附加层)
        elif op == 0x0088:
            steps.append({'t': 'end_action'})   # 0x44c060: 结束施术者行动 (自爆 / 神兽召唤)
        elif op == 0x0097:
            steps.append({'t': 'reset_facing'})   # 0x448783: 执行者朝向复位 (我方 180 / 敌方 0)
        elif op == 0x007E:
            steps.append({'t': 'play_motion', 'who': a[1], 'pose': a[0]})   # 0x448365: who 0 目标 / 1 施术者 / 2 全部敌人 播动作
        elif op == 0x0096:
            steps.append({'t': 'reflect'})   # 0x448771: 施术者 +0x1960 |= 0x100000 (皓月宝镜 反弹)
        elif op == 0x03F4:
            steps.append({'t': 'music', 'track': a[0]})   # 播地图音乐表第 n 轨 (百佌剑气 86)
        elif op == 0x03EE:
            steps.append({'t': 'overlay_a', 'args': list(a)})   # 0x445c4b: 400 粒子的雨线系统 (呼风唤雨), 见 battle.gd RainLines
        elif op == 0x03F3:
            steps.append({'t': 'sound_ctl', 'v': 4})   # 0x4be9fc(4,1,0): 音乐列表模式清 0, 当前曲子立刻停 (百佌剑气)
        elif op == 0x0072:
            steps.append({'t': 'face_target'})   # 执行者转向第一个目标 (0x4331f8)
        if fig:
            for st in steps[n0:]:
                st['fig'] = True
        if actor is not None:
            for st in steps[n0:]:
                st['actor'] = actor
    for st, tp in jumps:
        later = [k for k in sorted(at_step) if k >= tp]
        st['to'] = at_step[later[0]] if later else len(steps)
    return steps


def variants_of(d, ins):
    """开头是 random_jump (0x3c) 时: 原版 rand() % 项数 选一项, 返回 [(权重, 起点偏移)]"""
    if not ins or ins[0][1] != 0x003C:
        return None
    p, _, q = ins[0]
    cnt = {}
    for fld in range(p + 2, q - 4, 4):
        tgt = fld + struct.unpack_from('<i', d, fld)[0]
        cnt[tgt] = cnt.get(tgt, 0) + 1
    return sorted(cnt.items(), key=lambda x: x[0])


def main(game, out):
    root = os.path.abspath(out)
    while not os.path.exists(os.path.join(root, 'stats', 'characters.json')) and os.path.dirname(root) != root:
        root = os.path.dirname(root)
    chars = json.load(open(os.path.join(root, 'stats', 'characters.json')))
    magic = {m['编号 id']: m for m in json.load(open(os.path.join(root, 'stats', 'magic.json')))}
    act_data = open(os.path.join(game, 'ACT', 'all_char.act'), 'rb').read()
    b, offs, nxt = read_gll(os.path.join(game, 'ATK.GLL'))
    table = battle_table('ATK.GLL')
    os.makedirs(out, exist_ok=True)
    result = []
    for c in chars:
        if c['编号 id'] not in HEROES:
            continue
        name = c['名称 name']
        poses = actions(act_data, HEROES[c['编号 id']])
        skills = [{'id': 0, 'name': '普通攻击', 'desc': '以手中兵器攻击单一敌人。', 'side': '敌方', 'scope': '单体',
                   'sp': 0, 'mp': 0, 'learned': '初始', 'atk': c['动作脚本 action_id(ATK.GLL)']}]
        learners = {name} | ({'车芸'} if name == '云狐' else set())
        for mid, m in sorted(magic.items()):
            lv = [x.split(' ', 1)[1] for x in m.get('习得 learned_by', []) if x.split(' ')[0] in learners]
            if lv and m['名称 name'] != '战斗重新开始':
                skills.append({'id': mid, 'name': m['名称 name'], 'desc': m.get('描述 desc', ''), 'side': m.get('目标阵营 side'),
                               'scope': m.get('范围 scope'), 'sp': m.get('体力消耗 sp_cost', 0), 'mp': m.get('灵力消耗 mp_cost', 0),
                               'learned': lv[0], 'atk': m.get('动作脚本 action_id(ATK.GLL)')})
        used = set()
        for s in skills:
            slot = (s['atk'] or 0) - 1
            o = offs[slot] if 0 <= slot < len(offs) else 0xFFFFFFFF
            if o == 0xFFFFFFFF:
                s['steps'] = []
                continue
            d = b[o + 16:nxt[o + 16]]
            ins, _ = decode_bytes(d, table)
            vs = variants_of(d, ins)
            if vs:
                s['variants'] = [{'weight': w, 'steps': steps_of(d, ins, start)} for start, w in vs]
                s['steps'] = s['variants'][0]['steps']
            else:
                s['steps'] = steps_of(d, ins)
            for st in [x for v in s.get('variants', [{'steps': s['steps']}]) for x in v['steps']]:
                if 'pose' in st:
                    used.add(st['pose'])
        # 角色 GLB: 与 0 号动作同网格的动作, 每个动作按 ACT 播放表 (AP 序列) 导出为 pose_<号>, 35 帧/秒
        base = parse(os.path.join(game, 'Model', poses[0]['model'] + '.PLY'))
        files, mesh_ok, clips = [], {}, []
        for q in sorted({0, 0x38, 0x39, 0x3A, 0x3C} | used):
            v = poses.get(q)
            if not v:
                continue
            f = v['model']
            if f not in mesh_ok:
                path = os.path.join(game, 'Model', f + '.PLY')
                ok = os.path.exists(path)
                if ok:
                    m = parse(path)
                    ok = len(m.verts) == len(base.verts) and len(m.segments) == len(base.segments)
                mesh_ok[f] = ok
                if ok:
                    files.append(f)
            if mesh_ok[f]:
                clips.append((f'pose_{q}', files.index(f), v['aps'] or [0]))
        glb = f'{name}.glb'
        export(game, files, os.path.join(out, glb), fps=FPS, clips=clips)
        weapon, weapons = None, []
        if name in WEAPONS:
            item, marker = WEAPONS[name]
            items = open(os.path.join(game, 'ACT', 'all_item.act'), 'rb').read()
            eqs = json.load(open(os.path.join(root, 'stats', 'equipment.json')))
            eq = {e['编号 id']: e['名称 name'] for e in eqs}
            # 该角色可用的全部武器 (装备表「可用角色」), 有手持模型的才列入; 同一模型只导出一次
            done = {}
            for e in eqs:
                if e.get('部位 slot') != '武器' or name not in e.get('可用角色 users', ''):
                    continue
                try:
                    h = actions(items, e['编号 id']).get(1)
                except (KeyError, IndexError):
                    h = None
                if not h or not os.path.exists(os.path.join(game, 'Model', h['model'] + '.PLY')):
                    continue
                if h['model'] not in done:
                    done[h['model']] = f'{name}_武器_{h["model"]}.glb'
                    export(game, [h['model']], os.path.join(out, done[h['model']]), fps=FPS, clips=[('held', 0, h['aps'] or [0])])
                weapons.append({'item': e['编号 id'], 'name': e['名称 name'], 'glb': done[h['model']], 'model': h['model']})
            held = actions(items, item).get(1)
            if held and held['model'] in done:
                wglb = done[held['model']]
                # 导出角色 GLB 时 (ply2gltf.unmirror) 该挂点骨骼若被 X 翻转, 武器相对骨骼的基 = diag(1,-1,-1), 否则 diag(-1,-1,-1)
                seg = [i for i, sg in enumerate(base.segments) if sg.flags >> 24 == marker]
                dets = np.concatenate([np.linalg.det(parse(os.path.join(game, 'Model', f + '.PLY')).matrices[:, seg[0], :3, :3].astype(float))
                                       for f in files]) if seg else np.zeros(0)
                flipped = bool((dets < -1e-9).sum() > (dets > 1e-9).sum())
                weapon = {'item': item, 'name': eq.get(item, ''), 'glb': wglb, 'anim': 'held', 'marker': marker,
                          'model': held['model'], 'basis': [1, -1, -1] if flipped else [-1, -1, -1],
                          'trail_markers': [21, 22]}
        pose_map = {c[0][5:]: {'anim': c[0], 'ticks': len(c[2]), 'model': files[c[1]],
                               'sounds': poses[int(c[0][5:])]['sounds'], 'marks': poses[int(c[0][5:])]['marks']} for c in clips}
        missing = sorted({x['pose'] for s in skills for x in s['steps'] if 'pose' in x} - {int(k) for k in pose_map})
        result.append({'id': c['编号 id'], 'name': name, 'desc': c.get('描述 desc', ''), 'glb': glb, 'idle_pose': 0, 'fps': FPS,
                       'weapon': weapon, 'weapons': weapons,
                       'poses': pose_map, 'missing_poses': missing, 'skills': skills})
        print(name, len(skills), 'skills,', len(files), 'animations, missing poses', missing)
    json.dump({'characters': result}, open(os.path.join(out, 'skills.json'), 'w'), ensure_ascii=False, indent=1)


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
