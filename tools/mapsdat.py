"""MAPS.DAT 与地图 (MAP/WLD) 的解析 —— 依据 SWDMD_GB.EXE 地图系统逆向 (加载 0x40406c, 进地图 0x467ece, 移动 0x468a89)

MAPS.DAT: u16@8 ×16 = 数据池起点; 池开头 24 个 u32 段偏移 (相对池)。用到的段:
  1 新游戏初始化 (0x4047cb): 命令流 u16 cmd: 1 金钱 i16; 2 道具列表; 3/4/5 角色 1/2/3 装备; 7/8/9 角色 1/2/3 技能 (列表以 ffff 结尾)
  2 常驻角色表 (0x4041bd, 运行时即 [0xafe958], 随存档保存), 每条 24 字节:
      地图, 角色, 状态字 (+0x1a8), ACT, 动作, 朝向(度), x, y(i16), z, 调查事件, AI 脚本, 标志 (+0x1a4 低 16 位)
      标志: 0x1 隐藏, 0x4 不挡路, 0x10 碰到就触发, 0x400/0x800 调查型, 0x1000 不转身, 0x2000/0x4000 可对话, 0x8000 主控
  5 地图索引 (10 字节): 地图, 遇敌开关, 地图标志 (0x20 禁止转镜头, 0x80 世界地图, 0x100/0x200 镜头), UV 动画, 天空 UV
  6 遇敌概率组: 4 × (步数, 百分比), 依次累加
  7 遇敌区域 (20 字节): 地图, 概率组, 最小 xyz, 最大 xyz, u32 战场列表偏移 (→ u16 n, u16 战场[n], 重复即权重)
  21 地图显示名
MAP/WLD<id>.MAP: +0x0a 场景 ACT (12000–14999 在 all_map1.act, 15000+ 在 all_map2.act), +0x0c 动作;
  该动作的 FR = 模型号, 场景 = Model/MAP<FR % 3000>.WLD。
  +0x92 u32 事件框数, +0x96 起每条 0x54 字节: vec4 最小, vec4 最大 (相对), vec4 位置, u32 事件, char[32] 名字;
  事件框之后的第二组 (16 字节) 是环境粒子, 不是触发区。
WLD: 逻辑文件 0xbc = 包围盒最小角; 地图坐标 = 渲染顶点 − 最小角。段 0x10000 地面三角形 (13 个 f32: 三顶点 + 平面),
  段 0x80000 阻挡盒 (vec4 最小, vec4 最大)。坐标都是地图坐标 (碰撞地面比渲染地面高 1 单位)。
"""
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from act import read_index  # noqa: E402
from wld import load_logical  # noqa: E402


class MapsDat:
    def __init__(self, game):
        self.game = game
        b = open(os.path.join(game, 'MAPS.DAT'), 'rb').read()
        base = struct.unpack_from('<H', b, 8)[0] * 16
        self.pool = b[base:]
        self.offs = struct.unpack_from('<24I', self.pool, 0)

    def seg(self, i):
        o = self.offs[i]
        nxt = min([x for x in self.offs if x > o] + [len(self.pool)])
        return self.pool[o:nxt]

    def _u16list(self, s, p):
        out = []
        while struct.unpack_from('<H', s, p)[0] != 0xFFFF:
            out.append(struct.unpack_from('<H', s, p)[0])
            p += 2
        return out, p + 2

    def new_game(self):
        s, p = self.seg(1), 0
        out = {'money': 0, 'items': [], 'equip': {}, 'skills': {}}
        while p + 2 <= len(s):
            cmd = struct.unpack_from('<H', s, p)[0]
            p += 2
            if cmd == 0xFFFF:
                break
            if cmd == 1:
                out['money'] = struct.unpack_from('<h', s, p)[0]
                p += 2
            elif cmd == 2:
                out['items'], p = self._u16list(s, p)
            elif cmd in (3, 4, 5):
                out['equip'][cmd - 2], p = self._u16list(s, p)
            elif cmd in (7, 8, 9):
                out['skills'][cmd - 6], p = self._u16list(s, p)
        return out

    def actors(self):
        s, p, out = self.seg(2), 0, []
        while p + 24 <= len(s) and struct.unpack_from('<H', s, p)[0] != 0xFFFF:
            r = struct.unpack_from('<6Hh5H', s, p)
            out.append({'map': r[0], 'actor': r[1], 'state': r[2], 'act': r[3], 'pose': r[4], 'facing': r[5],
                        'pos': [r[6], r[7], r[8]], 'event': r[9], 'ai': r[10], 'flags': r[11]})
            p += 24
        return out

    def talisman_events(self):
        """第 17 段: 土地神符 (道具 3902) 的事件表 (0x405142, 逆向确认)。
        记录 = Big5 地区名 + "%Q", u16 事件号, u16 地图号列表 (0xFFFF 结尾); 0xFFFF 开头的记录结束整段。
        当前地图在哪条记录的列表里就启动那条的事件, 都不在则「現在無法使用!!」。返回 {地图号: 事件号}"""
        s, p, out = self.seg(17), 0, {}
        while struct.unpack_from('<H', s, p)[0] != 0xFFFF:
            q = s.find(b'%Q', p)
            p = q + 2
            ev = struct.unpack_from('<H', s, p)[0]
            p += 2
            while True:
                w = struct.unpack_from('<H', s, p)[0]
                p += 2
                if w == 0xFFFF:
                    break
                out.setdefault(w, ev)
        return out

    def map_index(self):
        s, p, out = self.seg(5), 0, {}
        while struct.unpack_from('<H', s, p)[0] != 0xFFFF:
            r = struct.unpack_from('<5H', s, p)
            out[r[0]] = {'encounters': r[1], 'flags': r[2], 'uv_anim': r[3], 'sky_uv': r[4]}
            p += 10
        return out

    def encounter_groups(self):
        s, p, out = self.seg(6), 0, []
        while struct.unpack_from('<H', s, p)[0] != 0xFFFF:
            r = struct.unpack_from('<8H', s, p)
            out.append([[r[2 * i], r[2 * i + 1]] for i in range(4)])
            p += 16
        return out

    def encounter_zones(self):
        s, p, out = self.seg(7), 0, []
        while struct.unpack_from('<H', s, p)[0] != 0xFFFF:
            r = struct.unpack_from('<8HI', s, p)
            q = r[8] - self.offs[7]
            n = struct.unpack_from('<H', s, q)[0]
            out.append({'map': r[0], 'group': r[1], 'min': list(r[2:5]), 'max': list(r[5:8]),
                        'battlefields': list(struct.unpack_from('<%dH' % n, s, q + 2))})
            p += 20
        return out

    def map_names(self):
        s, p, out = self.seg(21), 0, {}
        while struct.unpack_from('<H', s, p)[0] != 0xFFFF:
            k = struct.unpack_from('<H', s, p)[0]
            e = s.index(b'%Q', p + 2)
            out[k] = s[p + 2:e].decode('big5', 'replace')
            p = e + 2
        return out


def scene_of(game, map_id):
    """MAP 头 +0x0a 场景 ACT → 该 ACT 动作 0 的 FR → WLD 文件名 (MAPxxxxx)"""
    b = open(os.path.join(game, 'MAP', 'WLD%d.MAP' % map_id), 'rb').read()
    act, action = struct.unpack_from('<HH', b, 0x0a)
    return wld_of_act(game, act, action)


def wld_of_act(game, act, action=0):
    fn = {4: 'all_map1.act', 5: 'all_map2.act'}.get(act // 3000)
    if fn is None:
        return None
    d = open(os.path.join(game, 'ACT', fn), 'rb').read()
    idx = read_index(d)
    if act % 3000 not in idx:
        return None
    off, size = idx[act % 3000]
    a = d[off:off + size]
    cnt = struct.unpack_from('<H', a, 0)[0]
    if action >= cnt:
        return None
    o, ln = struct.unpack_from('<IH', a, 2 + 6 * action)
    s = a[o:o + ln]
    p = s.find(b'FR')
    if p < 0:
        return None
    fr = struct.unpack_from('<H', s, p + 2)[0]
    return 'MAP%05d' % (fr % 3000)


def map_boxes(game, map_id):
    """MAP 文件的事件框 (传送与剧情事件同一种记录)"""
    b = open(os.path.join(game, 'MAP', 'WLD%d.MAP' % map_id), 'rb').read()
    n = struct.unpack_from('<I', b, 0x92)[0]
    out = []
    for i in range(n):
        o = 0x96 + 0x54 * i
        mn = struct.unpack_from('<3f', b, o)
        mx = struct.unpack_from('<3f', b, o + 16)
        pos = struct.unpack_from('<3f', b, o + 32)
        ev = struct.unpack_from('<I', b, o + 48)[0]
        name = b[o + 52:o + 84].split(b'\0')[0].decode('big5', 'replace')
        out.append({'event': ev, 'pos': [round(x, 2) for x in pos], 'min': [round(x, 2) for x in mn],
                    'max': [round(x, 2) for x in mx], 'name': name})
    return out


def collision(game, wld_name):
    """→ (包围盒最小角, 地面三角形 [n×9], 阻挡盒 [m×6]), 均为地图坐标"""
    path = os.path.join(game, 'Model', wld_name + '.WLD')
    o = load_logical(path)
    raw = open(path, 'rb').read()
    n = struct.unpack_from('<I', raw, 8)[0]
    secs = {struct.unpack_from('<I', raw, 0xc + 8 * i)[0]: struct.unpack_from('<I', raw, 0x10 + 8 * i)[0] + 0x9c
            for i in range(n)}
    bmin = struct.unpack_from('<3f', o, 0xbc)
    tris, boxes = [], []
    if 0x10000 in secs:
        p = secs[0x10000]
        nt = struct.unpack_from('<I', o, p + 0x20)[0]
        for k in range(nt):
            tris.append(struct.unpack_from('<9f', o, p + 0x28 + 52 * k))
    if 0x80000 in secs:
        r = secs[0x80000]
        nb = struct.unpack_from('<I', o, r + 4)[0]
        for k in range(nb):
            v = struct.unpack_from('<8f', o, r + 8 + 32 * k)
            boxes.append(v[0:3] + v[4:7])
    return bmin, tris, boxes
