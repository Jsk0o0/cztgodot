"""轩辕剑苍之涛 .PLY 模型解析

文件: [u32 解压大小][u32 压缩大小][LZO1X]，解压后:
  0x00 u32 总大小
  0x04 bbox min xyz, f32 pad, bbox max xyz, f32 pad, center xyz, f32 pad, f32 radius
  0x38 u32 段数 N
  N x {u32 flags, u32 vcount, vstart, vend, u32 tcount, tstart, tend}
       flags: 0x100 = 骨骼段(刚性蒙皮); 0x0X000000 = 挂点/标记 (1 个三角形)
  u32 顶点数 + 顶点[40B] = pos f32x3, f32 0, normal f32x3, uv f32x2 (v 为负), u32 color
  u32 三角数 + u16 索引 x3
  u32 材质组数 + 组[52B] = u32 idxcount, idxstart, idxend, u32 flags, i32 texid, char name[32] (Big5)
  u32 三角数 + i32[三角数] (每三角附加值, 用途未明)
  u32 帧数 F + F x N 个 4x4 矩阵 (行主序, 平移在第 4 列, 每帧绝对变换)
  u32 帧数 F + F x {i32[N] 段内变形顶点偏移(-1 无), u32 n, 顶点[n]} (逐帧顶点变形)
段内顶点处于骨骼局部空间, 世界坐标 = M[frame][seg] @ v
"""
import struct
from dataclasses import dataclass, field

import numpy as np

from lzo1x import load


@dataclass
class Segment:
    flags: int
    vstart: int
    vend: int
    tstart: int
    tend: int


@dataclass
class Group:
    istart: int
    iend: int
    flags: int
    tex: int
    name: str


@dataclass
class Model:
    bbox: tuple
    segments: list
    verts: np.ndarray       # (nv, 10) float32 视图
    colors: np.ndarray      # (nv,) uint32
    indices: np.ndarray     # (nt*3,) uint16
    groups: list
    matrices: np.ndarray    # (frames, N, 4, 4)
    morphs: list = field(default_factory=list)  # 每帧 (offsets[N], verts(n,10)) 或 None

    @property
    def nframes(self):
        return len(self.matrices)


def parse(path):
    _, p = load(path)
    u32 = lambda o: struct.unpack_from('<I', p, o)[0]  # noqa: E731
    bbox = struct.unpack_from('<3f4x3f', p, 4)
    n = u32(0x38)
    o = 0x3C
    segs = []
    for i in range(n):
        f, vc, vs, ve, tc, ts, te = struct.unpack_from('<7I', p, o)
        segs.append(Segment(f, vs, ve, ts, te))
        o += 28
    nv = u32(o); o += 4
    raw = np.frombuffer(p, dtype='<f4', count=nv * 10, offset=o).reshape(nv, 10)
    colors = np.frombuffer(p, dtype='<u4', count=nv * 10, offset=o).reshape(nv, 10)[:, 9].copy()
    o += 40 * nv
    nt = u32(o); o += 4
    idx = np.frombuffer(p, dtype='<u2', count=nt * 3, offset=o).copy()
    o += 6 * nt
    ng = u32(o); o += 4
    groups = []
    for _ in range(ng):
        _, s, e, fl, tex = struct.unpack_from('<4Ii', p, o)
        name = p[o + 20:o + 52].split(b'\0')[0].decode('big5', 'replace')
        groups.append(Group(s, e, fl, tex, name))
        o += 52
    nt2 = u32(o); o += 4 + 4 * nt2
    nf = u32(o); o += 4
    mats = np.frombuffer(p, dtype='<f4', count=nf * n * 16, offset=o).reshape(nf, n, 4, 4).copy()
    o += nf * n * 64
    morphs = []
    nf2 = u32(o); o += 4
    for _ in range(nf2):
        offs = np.frombuffer(p, dtype='<i4', count=n, offset=o).copy(); o += 4 * n
        cnt = u32(o); o += 4
        mv = np.frombuffer(p, dtype='<f4', count=cnt * 10, offset=o).reshape(cnt, 10).copy()
        o += 40 * cnt
        morphs.append((offs, mv) if cnt else None)
    if o != len(p):
        raise ValueError(f'{path}: parsed {o} of {len(p)} bytes')
    return Model(bbox, segs, raw.copy(), colors, idx, groups, mats, morphs)


def vertex_segment(m):
    """每个顶点所属段号"""
    seg = np.zeros(len(m.verts), dtype=np.int32)
    for i, s in enumerate(m.segments):
        seg[s.vstart:s.vend] = i
    return seg


def frame_vertices(m, frame=0):
    """返回某帧世界空间顶点位置/法线 (含顶点变形)"""
    v = m.verts.copy()
    mo = m.morphs[frame] if frame < len(m.morphs) else None
    if mo is not None:
        offs, mv = mo
        for i, s in enumerate(m.segments):
            if offs[i] >= 0:
                k = s.vend - s.vstart
                v[s.vstart:s.vend] = mv[offs[i]:offs[i] + k]
    seg = vertex_segment(m)
    M = m.matrices[min(frame, m.nframes - 1)][seg]
    pos = np.einsum('nij,nj->ni', M[:, :3, :3], v[:, :3]) + M[:, :3, 3]
    nrm = np.einsum('nij,nj->ni', M[:, :3, :3], v[:, 4:7])
    return pos, nrm, v
