"""场景动画的原版数据 (逆向确认, 逆向笔记见 development.md 2026-10-29):

场景逐帧动画: 地图文件 MAP/WLD<地图号>.MAP 头 +0x0a = (场景 ACT 号, 动作号); 场景 ACT 在 ACT/all_map1.act (号 // 3000 == 4)
  / all_map2.act (== 5) 里, 动作的 FR 指令给出 WLD 名 (MAP%05d % (FR % 3000)), AP 指令序列就是逐拍显示的帧号。
  每拍 (35 拍/秒, 0x4675fb(35)) ACT 播放器 0x41d1e3 执行一个 AP → 场景帧号 word[0xa84fea];
  碰到 VO 那一拍只把读取位置倒回开头、不换帧 → 一轮 = AP 数 + 1 拍, 末帧多停一拍。
  绘制 0x418224 按帧号取每个物体的变换矩阵 (+0x58 + 帧 × 0x40) 和逐帧顶点 (+0x60, 含 UV); 不插值。
  只有 AP 0 的场景 (例 12633 / 12635 / 13016) 永远显示第 0 帧, WLD 里多出来的帧从不显示。
战场: ACT/BattleField.dat 第 N−1 条记录 +0x27a = 场景 ACT, +0x27c = 动作 (0x43fdac; 数据里全为 0);
  同一个播放器 0x41d1e3, 每个战斗逻辑拍 (0x4411fa → 0x4422ad, 27 拍/秒) 推进一次, 规则同上 —— 所以导出的时间轴按 35 拍/秒,
  战斗里播放速度乘 27/35。同一场景在地图和战场的帧序列相同 (scene_frames 里检查)。

贴图滚动: MAPS.DAT 第 15 段 8 字节记录 {u16 地图, u16 贴图号, i16 du, i16 dv}, 读到 u16 0xFFFF 为止 (0x404c48);
  MapIndex (第 5 段) uv_anim == 0 时整套跳过 (0x404c1f / 0x47815f)。每拍对物体全部顶点 u += du × 1e-4, v += dv × 1e-4,
  不取模, 换图时随 WLD 重读复位。贴图号 → 物体 (0x404d0e): 按 WLD 顺序找 tex 相同的物体, 最多 32 槽, 满了的不滚动。
  天空滚动 (第 16 段) 全部数据为空, 没有地图用到。
"""
import os
import struct

from act import ACT_OPS, read_index
from mapsdat import MapsDat
import wld

TICK_HZ = 35.0
BF_REC0 = 0x18 + 40000   # 同 extract_text.py: 文件头 + 名字表, 之后每条 776 字节
BF_STRIDE = 776
UV_SCALE = struct.unpack('<f', struct.pack('<f', 1e-4))[0]   # 0x4cd360


def _f32(x):
    return struct.unpack('<f', struct.pack('<f', x))[0]


def _action_ops(acts, act, action):
    d = acts[act // 3000]
    off, size = read_index(d)[act % 3000]
    a = d[off:off + size]
    o, ln = struct.unpack_from('<IH', a, 2 + 6 * action)
    s, q, ops = a[o:o + ln], 0, []
    while q + 2 <= len(s):
        c = s[q:q + 2]
        if c in ACT_OPS:
            f = '<' + ACT_OPS[c]
            n = struct.calcsize(f)
            ops.append((c.decode(), struct.unpack_from(f, s, q + 2) if n else ()))
            q += 2 + n
        else:
            q += 2
    return ops


def scene_frames(game):
    """WLD 名 → {'maps': [地图号], 'aps': [逐拍帧号]} (同一场景被多张图用到时要求帧序列相同, 否则报错)"""
    acts = {4: open(os.path.join(game, 'ACT', 'all_map1.act'), 'rb').read(),
            5: open(os.path.join(game, 'ACT', 'all_map2.act'), 'rb').read()}
    out = {}
    mdir = os.path.join(game, 'MAP')
    for fn in sorted(os.listdir(mdir)):
        u = fn.upper()
        if not (u.startswith('WLD') and u.endswith('.MAP')):
            continue
        mid = int(u[3:-4])
        b = open(os.path.join(mdir, fn), 'rb').read()
        act, action = struct.unpack_from('<HH', b, 0x0a)
        try:
            ops = _action_ops(acts, act, action)
        except (KeyError, IndexError, struct.error):
            continue
        fr = [x[1][0] for x in ops if x[0] == 'FR']
        if not fr:
            continue
        name = 'MAP%05d' % (fr[0] % 3000)
        aps = [x[1][0] for x in ops if x[0] == 'AP']
        e = out.setdefault(name, {'maps': [], 'aps': aps})
        if e['aps'] != aps:
            raise ValueError(f'{name}: 地图 {mid} 的场景帧序列和 {e["maps"]} 不同')
        e['maps'].append(mid)
    bf = open(os.path.join(game, 'ACT', 'BattleField.dat'), 'rb').read()
    for i in range(struct.unpack_from('<H', bf, 2)[0]):
        r0 = BF_REC0 + BF_STRIDE * i
        act, action = struct.unpack_from('<HH', bf, r0 + 0x27a)
        if not act:
            continue
        ops = _action_ops(acts, act, action)
        fr = [x[1][0] for x in ops if x[0] == 'FR']
        if not fr:
            continue
        name = 'MAP%05d' % (fr[0] % 3000)
        aps = [x[1][0] for x in ops if x[0] == 'AP']
        e = out.setdefault(name, {'maps': [], 'aps': aps})
        if e['aps'] != aps:
            raise ValueError(f'{name}: 战场 {i + 1} 的场景帧序列和地图 / 其他战场不同')
        e.setdefault('battlefields', []).append(i + 1)
    return out


def uv_records(game):
    """地图号 → [(贴图号, du 原值, dv 原值)] (MapIndex uv_anim 为 0 的地图不算)"""
    m = MapsDat(game)
    mi = m.map_index()
    pool, p, out = m.pool, m.offs[15], {}
    while struct.unpack_from('<H', pool, p)[0] != 0xFFFF:
        mid, tex, du, dv = struct.unpack_from('<HHhh', pool, p)
        p += 8
        if mi.get(mid, {}).get('uv_anim', 0):
            out.setdefault(mid, []).append((tex, du, dv))
    return out


def resolve(objs, recs):
    """0x404d0e: 贴图号 → 物体槽 (最多 32)。返回 ([(物体号, du, dv)], [没分到槽的物体号])"""
    slot, du, dv = [0] * 32, [0.0] * 32, [0.0] * 32
    for k, (tex, a, b) in enumerate(recs[:32]):
        slot[k], du[k], dv[k] = tex, _f32(a * UV_SCALE), _f32(b * UV_SCALE)
    lost = []
    for k in range(32):
        bx = slot[k]
        if bx == 0 or bx <= 10000:
            break
        found = False
        for i, ob in enumerate(objs):
            if ob.tex != bx:
                continue
            j = k
            while j < 32 and not (slot[j] == 0 or slot[j] == bx):
                j += 1
            if j >= 32:
                lost.append(i)
                continue
            if found:
                du[j], dv[j] = du[k], dv[k]
            slot[j] = i
            found = True
        if not found:
            slot[k] = 0
            break
    ent = []
    for k in range(32):
        if slot[k] == 0:
            break
        ent.append((slot[k], du[k], dv[k]))
    return ent, lost


def scene_uv(game, frames=None):
    """WLD 名 → {'maps': {地图号: [{tex, du, dv} 每拍增量]}, 'still': [贴图被滚动、但没分到槽的物体号]}"""
    frames = frames or scene_frames(game)
    by_map = {mid: name for name, e in frames.items() for mid in e['maps']}
    out = {}
    for mid, recs in uv_records(game).items():
        name = by_map.get(mid)
        if name is None:
            continue
        objs, _ = wld.parse(os.path.join(game, 'Model', name + '.WLD'))
        ent, lost = resolve(objs, recs)
        e = out.setdefault(name, {'maps': {}, 'still': []})
        texs = {}
        for i, a, b in ent:
            texs.setdefault(objs[i].tex, (a, b))
        e['maps'][mid] = [{'tex': t, 'du': a, 'dv': b} for t, (a, b) in texs.items()]
        e['still'] = sorted(set(e['still']) | set(lost))
    return out
