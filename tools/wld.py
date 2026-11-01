"""轩辕剑苍之涛 .WLD 场景解析

文件头 0x9c 字节, 0x94: [u32 解压大小][u32 压缩大小], 0x9c 起 LZO1X。
解压结果与"逻辑文件"偏移一一对应 (前 0x9c 字节为 0), 所有偏移都是逻辑文件内的绝对偏移。
逻辑文件:
  0x9c  u32 纹理名表偏移 ...
  0xbc  场景 bbox min/max (vec4), center (vec4), f32 radius
  0xf0  u32 对象数 N
  0xf4  N x {u32 size, u32 相对偏移}, 相对于对象区起点 (= 0xf4 + 8N)
  对象: u32 size, bbox min vec4, bbox max vec4, center vec4, f32 radius, u32 flags(位标志, 用途未全明),
        u32 texid (-1 = 标记/触发点, 无贴图), u32 nv, 顶点[nv] (40B, 同 PLY),
        u32 nidx, u16 索引[nidx] (pad 到 4),
        u32 帧数 K, K x 64B (3x4 行主序矩阵 + vec4; 局部 Z 朝上 -> 世界 Y 朝上),
        [可选: u32 K + K x nv 个顶点 (逐帧顶点变形), 此时尾部 32B; 否则尾部 36B (未明)]
"""
import struct
from dataclasses import dataclass

import numpy as np

from lzo1x import lzo1x


@dataclass
class WObject:
    tex: int
    verts: np.ndarray       # (nv, 10)
    indices: np.ndarray     # (nidx,)
    frames: list            # 每帧 3x4 矩阵 (静态物体 1 帧)
    morph: np.ndarray       # (K, nv, 10) 或 None
    kind: int
    bbox: tuple


def load_logical(path):
    b = open(path, 'rb').read()
    assert b[:4] == b'WLD\0', 'not WLD'
    u, c = struct.unpack_from('<II', b, 0x94)
    o = lzo1x(b[0x9C:0x9C + c])
    assert len(o) == u
    return o


def parse(path):
    o = load_logical(path)
    n = struct.unpack_from('<I', o, 0xF0)[0]
    base = 0xF4 + 8 * n
    objs = []
    for i in range(n):
        size, rel = struct.unpack_from('<II', o, 0xF4 + 8 * i)
        p = base + rel
        assert struct.unpack_from('<I', o, p)[0] == size, f'obj {i} size mismatch'
        mn = struct.unpack_from('<3f', o, p + 4)
        mx = struct.unpack_from('<3f', o, p + 20)
        kind, tex, nv = struct.unpack_from('<IiI', o, p + 0x38)
        q = p + 0x44
        verts = np.frombuffer(o, dtype='<f4', count=nv * 10, offset=q).reshape(nv, 10).copy()
        q += 40 * nv
        ni = struct.unpack_from('<I', o, q)[0]
        q += 4
        idx = np.frombuffer(o, dtype='<u2', count=ni, offset=q).copy()
        q += 2 * ni
        # 索引后是否有 2 字节补齐、是否带逐帧顶点变形, 由对象大小唯一确定
        end = p + size
        for pad in (0, 2):
            k = struct.unpack_from('<I', o, q + pad)[0]
            rest = end - (q + pad + 4 + 64 * k + 36)
            if rest in (0, 40 * k * nv):
                break
        else:
            raise ValueError(f'obj {i}: unknown layout (type {kind})')
        q += pad + 4
        frames = [np.frombuffer(o, dtype='<f4', count=12, offset=q + 64 * j).reshape(3, 4).copy()
                  for j in range(k)]
        q += 64 * k
        morph = None
        if rest:  # u32 帧数 + 各帧顶点, 之后尾部为 32B
            assert struct.unpack_from('<I', o, q)[0] == k
            morph = np.frombuffer(o, dtype='<f4', count=k * nv * 10, offset=q + 4).reshape(k, nv, 10).copy()
            q += 4 + 40 * k * nv + 32
        else:
            q += 36
        assert q == p + size, f'obj {i}: parsed {q - p} of {size}'
        objs.append(WObject(tex, verts, idx, frames, morph, kind, (mn, mx)))
    return objs, o


def world_vertices(obj, frame=0):
    M = obj.frames[frame]
    v = obj.morph[frame] if obj.morph is not None else obj.verts
    return v[:, :3] @ M[:, :3].T + M[:, 3]
