"""轩辕剑苍之涛 战斗技能特效: 招式脚本 (ATK) 特效编号 -> 画面

用法: python effects.py <游戏目录> <输出目录> [--skills skills.json[,more.json]] [--fps 35]
输出: <输出目录>/effects.json, models/<PLY名>.glb, sprites/<TSW>/<条目>/<帧>.png

== 链路 (SWDMD_GB.EXE 汇编证据) ==
ATK 0x02/0x03 (id, sub)
  -> 0x448a54 / 0x448d90: 清零 0x1f4 字节特效对象模板 0x926260, +0x94 = id, +0x96 = sub, +0x150 |= 1,
     位置/朝向/目标表/延迟(+0x1e0) 填好后 0x48e5cc 挂入特效链表 [0xc752c8]
  -> 每 tick 0x48e659 / 0x48ec13 调 0x41d1e3 = ACT 动作脚本解释器 (与角色动作同一套):
     0x41cce1/0x41cd27: 类别 = id // 3000, 序号 = id % 3000 -> 0x866d54 稠密索引表
       (0x41cb1e: 6 个文件 all_char/all_item/all_magic/all_sys/all_map1/all_map2.act,
        文件偏移 12*序号-2 处为 (u32 长度, u32 偏移, u32 ACT 号), 共 3000 槽)
     0x41d111: ACT 数据 = u16 动作数 + 动作数 x (u32 偏移, u16 长度), sub = 动作下标
     出错时报 「特效[ACT:%d][QQ:%d]動作資料錯誤!!」(0x48ebf5) —— QQ 即 sub
     注: tools/act.py 的 read_index 只按「条目数」读前 N 槽, 8101 等 ACT 号落在后面的槽里, 所以以前「找不到」。
  -> 动作脚本 = 双字母指令 (文件里的字节序, 括号内为 0x41d3d1 起的比较值):
     PT u8 (0x5450)  +0xfc 类型: 0 = 3D 模型 (0x42ee3a 按 ÷3000 取 Model/MGCxxxxx.PLY, 0x414758 画),
                     1 = 2D 精灵 (0x41ef73 -> all_<类>.tsw 第 id%3000 条, 0x415899 画)
     AT u16          总帧数;  XB 8f 包围盒;  FR u16 模型/精灵号 (清帧计数)
     AP u16 (0x5041) 开始新的一 tick: 显示第 n 帧, 并把颜色复位 0xFFFFFFFF、缩放复位 1 (0x41d87e)
     OC 4×u16        颜色 ARGB (+0x78 = A<<24|R<<16|G<<8|B), 作为模型/精灵的调制色
     CS 3f           缩放;  TR 3×u16 旋转角 (度, +0x8e/+0x90/+0x92);  PD 3f 局部偏移 (先缩放后平移, 0x495177)
     XF u32          绘制标志 (+0x74): 低 4 位 = 混合模式, 0x2000000 = 精灵按世界空间公告板画 (0x4158b5 推测),
                     0x0C000000 = 不随施术者朝向 (0x495180)
     VW u16          播放音效 (+0xbe -> 0x4bec87)
     ER n×(slot, 粒子号, 停止帧)  在模型第 slot+1 号挂点上开粒子发射器 (0x48f4df -> 0x493634 -> Effect.dat)
     IS 6×u16 / PS u16  精灵图集: 区域 x0,y0,x1,y1 + 格子宽高 / 格子号 (0x41da79 算 UV)
     DS u16 停留 n tick;  PL 3×u16 帧循环;  XV 水平翻转;  DE 本 tick 结束;  VO 回到开头循环;  2O 动作结束
     'd\\0' / 'e\\0' (0x64/0x65, 默认分支 0x41de99): 置 +0x83 位 0x80/0x40 -> 0x48eae5 调 0x443cd8 结算命中
  -> 结束 (+0xc0&1) 后因 +0x150&1, 每 tick +0x1de += 10 直到 250 才删除 (0x48e76e): 末帧再停留 25 tick
混合模式 (0x41676c, 值 = PLY 材质组 flags | XF, 取低 4 位):
     0 不透明 (Z 写, 无混合); 1 加法 SRC=SRCALPHA DST=ONE (关 Z 写); 2 普通 SRCALPHA/INVSRCALPHA;
     4 SRC=INVDESTALPHA DST=INVSRCCOLOR; 8 SRC=SRCCOLOR DST=INVSRCCOLOR (后两种关 Z 写)
PLY 段 flags 0x100000 = 公告板段 (0x416a07 构造朝向相机的矩阵); flags>>24 = k 为挂点 k (不画)

== Effect.dat (0x48faaa) ==
  0x18 头 (u16 条目数, u16 最大编号) + 5000×40 字节名字 (Big5) + 5000×0xF8 字节记录; 粒子号 N -> 下标 N-1
  记录字段见 PARTICLE_FIELDS (0x48f810 拷进粒子系统, 0x492377 生成粒子, 0x492cd2 更新, 0x49316b 绘制)
  每个粒子本身又是一个 ACT 特效 (记录 +0xc4/+0xc6 = ACT 号/动作), 颜色 = ARGB(粒子 alpha, 粒子 RGB)
"""
import json
import os
import struct
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ply import parse  # noqa: E402
from ply2gltf import export as gltf_export  # noqa: E402

ACT_FILES = ['all_char.act', 'all_item.act', 'all_magic.act', 'all_sys.act', 'all_map1.act', 'all_map2.act']
TSW_FILES = ['all_char.tsw', 'all_item.tsw', 'all_magic.tsw', 'all_sys.tsw', 'all_map1.tsw', 'all_map2.tsw']
PREFIX = ['CHR', 'ITM', 'MGC', 'SYS', 'MAP', 'OTH']
LINGER_TICKS = 25

# 操作数格式 (struct)
OPS = {b'PT': 'B', b'AT': 'H', b'XB': '8f', b'FR': 'H', b'AP': 'H', b'OC': '4H', b'CS': '3f', b'TR': '3H',
       b'VW': 'H', b'XF': 'I', b'PL': '3H', b'DS': 'H', b'IS': '6H', b'PS': 'H', b'XT': 'I3H', b'XV': '',
       b'PD': '3f', b'PC': '3f', b'AC': '3fB', b'DC': '3fB', b'DE': '', b'VO': '', b'2O': ''}
BLEND = {0: 'opaque', 1: 'add', 2: 'alpha', 4: 'invdestalpha_invsrccolor', 8: 'srccolor_invsrccolor'}


class Game:
    def __init__(self, root):
        self.root = root
        self._act = {}
        self._ply = {}
        eff = open(os.path.join(root, 'ACT', 'Effect.dat'), 'rb').read()
        self.eff = eff
        self.eff_count, self.eff_max = struct.unpack_from('<2H', eff, 0)

    # ---- ACT ----
    def act_blob(self, act_id):
        cat, slot = divmod(act_id, 3000)
        if cat not in self._act:
            self._act[cat] = open(os.path.join(self.root, 'ACT', ACT_FILES[cat]), 'rb').read()
        d = self._act[cat]
        if slot < 1 or 12 * slot + 10 > len(d):
            return None
        size, off, _ = struct.unpack_from('<3I', d, 12 * slot - 2)
        return d[off:off + size] if size else None

    def action(self, act_id, sub):
        b = self.act_blob(act_id)
        if b is None:
            return None
        n = struct.unpack_from('<H', b, 0)[0]
        if sub >= n:
            return None
        o, ln = struct.unpack_from('<IH', b, 2 + 6 * sub)
        return b[o:o + ln] if ln else None

    def ply(self, name):
        if name not in self._ply:
            p = os.path.join(self.root, 'Model', name + '.PLY')
            self._ply[name] = parse(p) if os.path.exists(p) else None
        return self._ply[name]

    # ---- Effect.dat ----
    def particle_record(self, pid):
        i = pid - 1
        b = self.eff[0x30D58 + i * 0xF8:0x30D58 + (i + 1) * 0xF8]
        name = self.eff[0x18 + i * 40:0x18 + i * 40 + 40].split(b'\0')[0].decode('big5', 'replace')
        return name, b


def decode(a):
    """动作脚本 -> [(op, 操作数)]"""
    p, out = 0, []
    while p + 2 <= len(a):
        op = a[p:p + 2]
        p += 2
        if op == b'ER':
            n = struct.unpack_from('<H', a, p)[0]
            p += 2
            out.append(('ER', [struct.unpack_from('<3H', a, p + 6 * i) for i in range(n)]))
            p += 6 * n
        elif op in OPS:
            f = '<' + OPS[op]
            out.append((op.decode(), struct.unpack_from(f, a, p)))
            p += struct.calcsize(f)
            if op == b'2O':
                break
        elif op[1] == 0 and 0x64 <= op[0] <= 0x68:
            out.append(('HIT', (chr(op[0]),)))
        else:
            out.append(('?' + op.hex(), ()))
    return out


def model_name(fr):
    cat, n = divmod(fr, 3000)
    return '%s%05d' % (PREFIX[cat], n) if cat < len(PREFIX) else None


def simulate(ops):
    """按 0x41d1e3 语义逐 tick 展开: 返回 (ticks, events, loop, head)"""
    st = {'frame': 0, 'color': [255, 255, 255, 255], 'scale': [1.0, 1.0, 1.0], 'rot': [0, 0, 0],
          'offset': [0.0, 0.0, 0.0], 'xf': 0, 'fr': None, 'cell': 0, 'flip': False}
    head = {'type': 0, 'frames': 0, 'bbox': None, 'atlas': None}
    ticks, events, loop = [], [], False
    pending = []

    def emit_tick():
        t = len(ticks)
        ticks.append({k: (list(v) if isinstance(v, list) else v) for k, v in st.items()})
        for e in pending:
            e['tick'] = t
            events.append(e)
        pending.clear()

    for op, v in ops:
        if op == 'PT':
            head['type'] = v[0]
        elif op == 'AT':
            head['frames'] = v[0]
        elif op == 'XB':
            head['bbox'] = [round(x, 3) for x in (v[0], v[1], v[2], v[4], v[5], v[6])]
        elif op == 'FR':
            st['fr'] = v[0]
        elif op == 'AP':
            st['frame'] = v[0]
            st['color'] = [255, 255, 255, 255]
            st['scale'] = [1.0, 1.0, 1.0]
        elif op == 'OC':
            st['color'] = list(v)
        elif op == 'CS':
            st['scale'] = [round(x, 4) for x in v]
        elif op == 'TR':
            st['rot'] = list(v)
        elif op == 'PD':
            st['offset'] = [round(x, 3) for x in v]
        elif op == 'XF':
            st['xf'] = v[0]
        elif op == 'IS':
            head['atlas'] = list(v)
        elif op == 'PS':
            st['cell'] = v[0]
        elif op == 'XV':
            st['flip'] = not st['flip']
        elif op == 'VW':
            pending.append({'type': 'sound', 'id': v[0]})
        elif op == 'HIT':
            pending.append({'type': 'hit', 'kind': v[0]})
        elif op == 'ER':
            for slot, pid, stop in v:
                pending.append({'type': 'emit', 'slot': slot, 'particle': pid, 'stop_frame': stop})
        elif op == 'DS':
            for _ in range(v[0]):
                emit_tick()
        elif op == 'DE':
            emit_tick()
        elif op in ('2O', 'VO'):
            emit_tick()
            loop = op == 'VO'
            break
        # PL / PC / AC / DC / XT: 本批数据未用到, 不展开
    return ticks, events, loop, head


def track(ticks, key, ndig=None):
    """逐 tick 值 -> 变化表 [[tick, 值], ...] (阶梯插值)"""
    out, last = [], object()
    for t, s in enumerate(ticks):
        v = s[key]
        if v != last:
            out.append([t, v])
            last = v
    return out


def ply_has_morph(game, name):
    m = parse(os.path.join(game, 'Model', name + '.PLY'))
    return any(x is not None for x in m.morphs)


def ply_info(game, name):
    m = game.ply(name)
    if m is None:
        return None
    mats = []
    for g in m.groups:
        if g.flags >> 24:
            continue
        idx = m.indices[g.istart:g.iend]
        a = (m.colors[idx] >> 24) & 0xFF if len(idx) else np.array([255])
        mats.append({'name': g.name or f'tex{g.tex}', 'tex': g.tex, 'flags': g.flags,
                     'blend': BLEND.get(g.flags & 0xF, f'mode{g.flags & 0xF}'),
                     'vertex_alpha': [int(a.min()), int(a.max())]})
    markers = {}
    billboard = []
    for i, s in enumerate(m.segments):
        k = s.flags >> 24
        if k:
            v = m.verts[s.vstart, :3] if s.vend > s.vstart else np.zeros(3)
            markers[str(k)] = {'node': f'marker{k}_{i:02d}', 'local': [round(float(x), 3) for x in v]}
        elif s.flags & 0x100000:
            billboard.append(f'{"bone" if s.flags & 0x100 else "marker0"}_{i:02d}')
    return {'ply': name, 'frames': m.nframes, 'materials': mats, 'markers': markers, 'billboard_nodes': billboard}


# 粒子记录字段 (偏移, 格式, 名字, 说明)
PARTICLE_FIELDS = [
    (0x00, '3f', 'color_start', 'RGB 0-255 (+0x28 起点)'),
    (0x10, '3f', 'color_end', 'RGB 0-255, 寿命内线性插值到此 (0x49259c)'),
    (0x20, '3f', 'color_random', '起点 RGB 加 rand[0,1)*此值, 再夹到 0-255'),
    (0x30, 'f', 'spawn_box_x', '出生点 x = 发射点 x + (rand-0.5)*此值 (0x49267c)'),
    (0x34, 'f', 'spawn_box_z', '出生点 z 抖动宽度'),
    (0x38, 'f', 'spawn_box_y', '出生点 y 抖动宽度'),
    (0x3c, 'f', 'floor_y', '非 0: 粒子 y 低于此值时停在地面并反弹 (0x492e0c)'),
    (0x40, 'f', 'life', '寿命 (秒) 基值'),
    (0x44, 'f', 'life_random', '寿命 += rand*此值'),
    (0x48, 'f', 'gravity_start', 'g 起点 (x9.8); 每秒 vy += g*(-9.8) (0x492e9b)'),
    (0x4c, 'f', 'gravity_random', 'g 起点 += rand*此值'),
    (0x50, 'f', 'gravity_end', '寿命末 g (x9.8)'),
    (0x54, 'f', 'spread_deg', '方向表全 0 时: 随机方向的俯仰范围 (度, 180=全向)'),
    (0x58, '6f', 'dir_box', '方向范围 xmin,xmax,ymin,ymax,zmin,zmax; 全 0 则用 spread_deg 随机'),
    (0x70, 'f', 'size_start', '粒子尺寸 (加到粒子 ACT 的 CS 缩放上, 0x4933c2)'),
    (0x74, 'f', 'size_end', '寿命末尺寸 (>0 才插值)'),
    (0x78, 'f', 'size_random', '起点尺寸 += rand*此值'),
    (0x7c, 'f', 'alpha_start', '不透明度 0-255'),
    (0x80, 'f', 'alpha_end', '寿命末不透明度'),
    (0x84, 'f', 'alpha_random', '起点 alpha += rand*此值'),
    (0x88, 'f', 'rate', '持续发射时每秒生成个数 (0x492cff)'),
    (0x98, 'f', 'size_end_random', '寿命末尺寸 += rand*此值'),
    (0xc2, 'H', 'count', '粒子池大小 = 同时存在的最大个数'),
    (0xc4, 'H', 'visual_act', '每个粒子播放的 ACT 号 (0 = 画线段)'),
    (0xc6, 'H', 'visual_sub', '该 ACT 的动作下标'),
    (0xc8, 'H', 'max_total', '累计最多生成个数 (0 = 不限)'),
    (0xca, 'H', 'speed', '初速度 (单位/秒) 基值'),
    (0xcc, 'H', 'speed_random', '初速度 += rand*此值'),
    (0xd8, 'B', 'attract', '1 = 每秒朝发射点加速 500 (0x492ec5)'),
    (0xd9, 'B', 'attract_flat', '1 = 吸引时忽略 y'),
    (0xda, 'B', 'flag_f7', '与 attract 同时为 1 时出生点 y 不抖动、取发射点高度 (0x492377)'),
    (0xdb, 'B', 'spin', '1 = 粒子按 -speed 度/秒自转, 模型朝飞行方向 (0x492b5a/0x49307d)'),
    (0xe0, 'I', 'continuous', '0 = 一次性喷发 count 个 (0x491531); 1 = 按 rate 持续发射'),
]


def particle(game, pid):
    name, b = game.particle_record(pid)
    out = {'id': pid, 'name': name}
    for off, fmt, key, _ in PARTICLE_FIELDS:
        v = struct.unpack_from('<' + fmt, b, off)
        v = [round(x, 4) if isinstance(x, float) else x for x in v]
        out[key] = v if len(v) > 1 else v[0]
    va, vs = out['visual_act'], out['visual_sub']
    out['visual'] = f'{va}_{vs}' if va else None
    return out


def build_effect(game, act_id, sub):
    a = game.action(act_id, sub)
    if a is None:
        return None
    ops = decode(a)
    ticks, events, loop, head = simulate(ops)
    kind = 'model' if head['type'] == 0 else 'sprite'
    frs = sorted({s['fr'] for s in ticks if s['fr'] is not None})
    e = {'act': act_id, 'sub': sub, 'kind': kind, 'ticks': len(ticks), 'declared_frames': head['frames'],
         'loop': loop, 'linger_ticks': 0 if loop else LINGER_TICKS, 'bbox': head['bbox'],
         'unknown_ops': sorted({o for o, _ in ops if o.startswith('?')})}
    if kind == 'model':
        e['models'] = {}
        for fr in frs:
            nm = model_name(fr)
            info = ply_info(game, nm) if nm else None
            e['models'][str(fr)] = info and dict(info, glb=f'models/{nm}.glb')
    else:
        e['sprites'] = {str(fr): {'tsw': TSW_FILES[fr // 3000], 'entry': fr % 3000} for fr in frs}
        e['atlas'] = head['atlas']
    e['tracks'] = {k: track(ticks, k) for k in ('fr', 'frame', 'color', 'scale', 'rot', 'offset', 'xf')}
    if kind == 'sprite':
        e['tracks']['cell'] = track(ticks, 'cell')
        e['tracks']['flip'] = track(ticks, 'flip')
    e['events'] = events
    # 混合模式汇总: 材质 flags | XF
    xfs = {s['xf'] for s in ticks}
    e['blend_override'] = sorted({BLEND.get(x & 0xF, f'mode{x & 0xF}') for x in xfs if x & 0xF})
    e['billboard_world'] = any(x & 0x2000000 for x in xfs)
    e['ignore_facing'] = any(x & 0x0C000000 for x in xfs)
    return e


def export_sprites(game, out, tsw, entry):
    from tsw2png import decode_frame, frames, read_table
    d = os.path.join(out, 'sprites', os.path.splitext(tsw)[0], f'{entry:04d}')
    res = []
    with open(os.path.join(game.root, 'ACT', tsw), 'rb') as f:
        recs = [r for r in read_table(f) if r['index'] == entry]
        if not recs:
            return None
        r = recs[0]
        f.seek(r['offset'])
        blob = f.read(r['size'])
    os.makedirs(d, exist_ok=True)
    for k, (off, csize, _, w, h) in enumerate(frames(blob)):
        p = os.path.join(d, f'{k:03d}.png')
        if not os.path.exists(p):
            decode_frame(blob, off, csize).save(p)
        res.append(os.path.relpath(p, out))
    return {'name': r['name'], 'frames': res, 'size': [w, h]}


def collect_combos(skills_path):
    """skills_path: 一个或多个 (逗号分隔) JSON, 收集其中所有 {'t': 'effect'} 步骤"""
    d = [json.load(open(p)) for p in skills_path.split(',')]
    combos, fps, used = set(), None, {}

    def walk(o):
        nonlocal fps
        if isinstance(o, dict):
            if fps is None and isinstance(o.get('fps'), (int, float)):
                fps = float(o['fps'])
            if o.get('t') == 'effect':
                key = (o['id'], o['sub'])
                combos.add(key)
                used.setdefault(key, set()).add(o.get('at'))
            for v in o.values():
                walk(v)
        elif isinstance(o, list):
            for v in o:
                walk(v)
    walk(d)
    return sorted(combos), fps, used


def main(argv):
    args = list(argv)
    skills = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'extracted', 'preview', 'skills.json')
    fps = None
    if '--skills' in args:
        i = args.index('--skills'); skills = args[i + 1]; del args[i:i + 2]
    if '--fps' in args:
        i = args.index('--fps'); fps = float(args[i + 1]); del args[i:i + 2]
    extra = []   # --extra ACT:QQ,ACT:QQ-QQ,...: 不在招式脚本的 effect 指令里、由别的指令引用的特效 (0x98 覆盖闪光 7042, 首领光环 8139, 敌人死亡 8117 (0x1fb5))
    if '--extra' in args:
        i = args.index('--extra')
        for item in args[i + 1].split(','):
            act, qq = item.split(':')
            lo, _, hi = qq.partition('-')
            for q in range(int(lo), int(hi or lo) + 1):
                extra.append((int(act), q))
        del args[i:i + 2]
    extra_particles = []   # --particles ID,ID: 程序直接创建的粒子系统 (0x48fc7b, 例 天书建成 0x82f = 2095)
    if '--particles' in args:
        i = args.index('--particles')
        extra_particles = [int(x) for x in args[i + 1].split(',')]
        del args[i:i + 2]
    root, out = args[0], args[1]
    # 地图角色动作的 ER 挂点粒子 (export_actors 写进 act_<号>.json 的 poses[*].er, 地图角色 0x46e05c 生成)
    act_dir = os.path.join(os.path.dirname(os.path.abspath(out)), 'game', 'actors')
    if os.path.isdir(act_dir):
        for fn in sorted(os.listdir(act_dir)):
            if fn.startswith('act_') and fn.endswith('.json') and not fn.endswith('.morph.json'):
                for pm in json.load(open(os.path.join(act_dir, fn), encoding='utf-8')).get('poses', {}).values():
                    for _slot, pid, _stop in pm.get('er', []):
                        if pid not in extra_particles:
                            extra_particles.append(pid)
    game = Game(root)
    combos, sk_fps, used = collect_combos(skills)
    fps = fps or sk_fps or 35.0
    os.makedirs(out, exist_ok=True)

    effects, particles, missing = {}, {}, []
    todo = [(i, s, 'skill') for i, s in combos] + [(i, s, 'overlay') for i, s in extra]
    seen = set()
    while todo:
        i, s, role = todo.pop(0)
        key = f'{i}_{s}'
        if key in seen:
            if role not in effects.get(key, {}).get('roles', [role]):
                effects[key]['roles'].append(role)
            continue
        seen.add(key)
        e = build_effect(game, i, s)
        if e is None:
            missing.append(key)
            continue
        e['roles'] = [role]
        if role == 'skill':
            e['used_as'] = sorted(x for x in used.get((i, s), ()) if x)
        effects[key] = e
        for ev in e['events']:
            if ev['type'] == 'emit' and str(ev['particle']) not in particles:
                p = particle(game, ev['particle'])
                particles[str(ev['particle'])] = p
                if p['visual']:
                    todo.append((p['visual_act'], p['visual_sub'], 'particle_visual'))

    for pid in extra_particles:
        if str(pid) not in particles:
            pp = particle(game, pid)
            particles[str(pid)] = pp
            if pp['visual']:
                todo.append((pp['visual_act'], pp['visual_sub'], 'particle_visual'))
    while todo:
        i, s, role = todo.pop(0)
        key = f'{i}_{s}'
        if key in seen:
            continue
        seen.add(key)
        e = build_effect(game, i, s)
        if e is None:
            missing.append(key)
            continue
        e['roles'] = [role]
        effects[key] = e

    # 资源导出
    plys = sorted({m['ply'] for e in effects.values() for m in (e.get('models') or {}).values() if m})
    os.makedirs(os.path.join(out, 'models'), exist_ok=True)
    for nm in plys:
        p = os.path.join(out, 'models', nm + '.glb')
        if not os.path.exists(p) or not os.path.exists(p + '.morph.json') and ply_has_morph(root, nm):
            gltf_export(root, [nm], p, fps=fps, sidecar=True)
    sprite_cache = {}
    for e in effects.values():
        for k, sp in (e.get('sprites') or {}).items():
            ck = (sp['tsw'], sp['entry'])
            if ck not in sprite_cache:
                sprite_cache[ck] = export_sprites(game, out, *ck)
            info = sprite_cache[ck]
            if info:
                sp.update(info)
                a = e.get('atlas')
                if a:  # 精灵世界尺寸: 格子宽高 x CS 缩放 (XB 包围盒与之吻合, 例 8137_0: 128*0.33=42.24)
                    sp['cell_size'] = [a[4], a[5]]

    meta = {
        'fps': fps,
        'units': '游戏单位 (≈厘米); GLB 根节点已乘 0.01, 粒子参数仍为游戏单位, Godot 中需 x0.01',
        'tick': '每 tick = 1/fps 秒; tracks 是 [起始 tick, 值] 变化表, 值保持到下一项 (阶梯)',
        'model_frame': 'GLB 动画名 = PLY 名, 第 n 帧在 n/fps 秒; 每 tick 按 tracks.frame 定格 (seek, 不插值)',
        'color': 'ARGB 0-255, 乘到贴图色上 (含 alpha); AP 每 tick 复位为白色',
        'scale_rot_offset': '世界矩阵 = 缩放(scale) -> 平移(offset*scale) -> 旋转(rot x,y+朝向,z 度) -> 平移(位置) (0x495177)',
        'blend': {str(k): v for k, v in BLEND.items()},
        'blend_rule': '材质 blend = (PLY 材质组 flags | XF) & 0xF; add = 加法 (SRCALPHA, ONE), 关 Z 写, 无光照',
        'billboard_nodes': '这些骨骼节点在原版每帧被替换为朝向相机的矩阵 (段 flags 0x100000)',
        'markers': 'ER 发射器 slot k 挂在 markers[k+1] 节点: 发射点 = 节点全局变换 x local (首顶点)',
        'linger_ticks': '动作结束后末帧继续画 25 tick 再删除 (+0x150&1, 0x48e76e)',
        'events': 'sound=音效号; hit=命中结算点 (d/e, 0x443cd8); emit=开粒子发射器, 模型帧到 stop_frame 时停发 (0=随特效删除才停)',
        'placement': {'caster': 'ATK 0x02: 施术者位置 + set_offset; 0x04 后改为每个目标各一个',
                      'to_targets': 'ATK 0x03: 每个有效目标各一个, 位置 = 施术者 + 按施术者朝向旋转的偏移, '
                                    '朝向 = 施术者->目标; 第 k 个目标延迟 k*step tick (0x40 设 step, 写 +0x1e0)'},
        'particle_fields': {k: d for _, _, k, d in PARTICLE_FIELDS},
        'particle_sim': ('dt 秒; 每粒子 (0x492377): 出生于发射点+spawn_box 抖动; 方向: dir_box 全 0 时 A=(r1-r2)/32767*2π, '
                         'B=(r3-r4)/32767*spread*π/180, dir=(cosA·sinB, cosB, sinA·sinB) (极轴 +Y); 否则 [min,max] 均匀取值不归一化; 世界坐标; '
                         'v=dir*(speed+rand*speed_random); 每帧 pos+=v*dt, vy+=g*9.8*(-9.8)*dt, '
                         'g/size/alpha/color 在寿命内线性插值; 寿命到即重生 (持续模式且仍在发射); '
                         '粒子画法 = 其 visual ACT 当前帧, 颜色 ARGB(alpha,R,G,B), 缩放 = CS + size'),
        'missing': missing,
    }
    res = {'_meta': meta, '_particles': particles}
    res.update(effects)
    with open(os.path.join(out, 'effects.json'), 'w') as f:
        json.dump(res, f, ensure_ascii=False, indent=1)
    nsk = sum('skill' in e['roles'] for e in effects.values())
    print(f'{nsk}/{len(combos)} skill effects, {len(effects) - nsk} particle visuals, '
          f'{len(particles)} particle systems, {len(plys)} GLB, {len(sprite_cache)} sprite sets, missing={missing}')


if __name__ == '__main__':
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)
    main(sys.argv[1:])
