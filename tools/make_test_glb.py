"""生成创意工坊 M4 测试用的 GLB (纯程序生成, 不含任何原版素材):
身体 (方柱, 高 1.6 米, 底面在 y=0) + 正面的「鼻子」(朝 glTF 惯例的正面 +Z) + 两段动画:
  idle: 身体上下轻微起伏 (2 秒循环)    walk: 身体左右摆动 (1 秒循环)
用法: python tools/make_test_glb.py 输出.glb
"""
import json
import struct
import sys


def box(cx, cy, cz, sx, sy, sz):
    """轴对齐方块: 返回 (顶点, 索引)"""
    x0, x1 = cx - sx / 2, cx + sx / 2
    y0, y1 = cy - sy / 2, cy + sy / 2
    z0, z1 = cz - sz / 2, cz + sz / 2
    v = [(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0), (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)]
    f = [(0, 2, 1), (0, 3, 2), (4, 5, 6), (4, 6, 7), (0, 1, 5), (0, 5, 4), (3, 7, 6), (3, 6, 2), (0, 4, 7), (0, 7, 3), (1, 2, 6), (1, 6, 5)]
    return v, [i for t in f for i in t]


def main(out):
    bv, bi = box(0, 0.8, 0, 0.5, 1.6, 0.35)      # 身体
    nv, ni = box(0, 1.35, 0.3, 0.12, 0.12, 0.3)   # 鼻子, 在 +Z 一侧 (正面)
    buf = bytearray()
    views, accs = [], []

    def add(data, target=None):
        while len(buf) % 4:
            buf.append(0)
        views.append({"buffer": 0, "byteOffset": len(buf), "byteLength": len(data), **({"target": target} if target else {})})
        buf.extend(data)
        return len(views) - 1

    def acc(view, ctype, count, typ, mn=None, mx=None):
        a = {"bufferView": view, "componentType": ctype, "count": count, "type": typ}
        if mn is not None:
            a["min"], a["max"] = mn, mx
        accs.append(a)
        return len(accs) - 1

    meshes = []
    for name, v, idx, col in [("body", bv, bi, [0.85, 0.55, 0.25, 1]), ("nose", nv, ni, [0.9, 0.15, 0.15, 1])]:
        pv = add(b"".join(struct.pack("<3f", *p) for p in v), 34962)
        iv = add(b"".join(struct.pack("<H", i) for i in idx), 34963)
        pa = acc(pv, 5126, len(v), "VEC3", [min(p[k] for p in v) for k in range(3)], [max(p[k] for p in v) for k in range(3)])
        ia = acc(iv, 5123, len(idx), "SCALAR")
        meshes.append({"name": name, "primitives": [{"attributes": {"POSITION": pa}, "indices": ia, "material": len(meshes)}]})
    mats = [{"name": "body", "pbrMetallicRoughness": {"baseColorFactor": [0.85, 0.55, 0.25, 1], "metallicFactor": 0, "roughnessFactor": 1}},
            {"name": "nose", "pbrMetallicRoughness": {"baseColorFactor": [0.9, 0.15, 0.15, 1], "metallicFactor": 0, "roughnessFactor": 1}}]
    nodes = [{"name": "rig", "children": [1, 2]}, {"name": "body", "mesh": 0}, {"name": "nose", "mesh": 1}]

    anims = []
    for name, dur, fn in [("idle", 2.0, lambda t: ("translation", (0, 0.04 * __import__("math").sin(t * 3.14159), 0))),
                          ("walk", 1.0, lambda t: ("rotation", (0, 0, __import__("math").sin(t * 6.28318 * 0.5) * 0.08, 1)))]:
        n = 21
        times = [dur * i / (n - 1) for i in range(n)]
        path = fn(0)[0]
        vals = [fn(t * (1 if name == "idle" else 2))[1] for t in times]
        if path == "rotation":
            import math
            vals = [(0, 0, math.sin(a), math.cos(a)) for a in [math.sin(t / dur * 6.28318) * 0.08 for t in times]]
        tv = add(b"".join(struct.pack("<f", t) for t in times))
        ta = acc(tv, 5126, n, "SCALAR", [0.0], [dur])
        w = 4 if path == "rotation" else 3
        vv = add(b"".join(struct.pack("<%df" % w, *x) for x in vals))
        va = acc(vv, 5126, n, "VEC4" if w == 4 else "VEC3")
        anims.append({"name": name, "samplers": [{"input": ta, "output": va, "interpolation": "LINEAR"}],
                      "channels": [{"sampler": 0, "target": {"node": 0, "path": path}}]})

    gltf = {"asset": {"version": "2.0", "generator": "czt make_test_glb"}, "scene": 0, "scenes": [{"nodes": [0]}],
            "nodes": nodes, "meshes": meshes, "materials": mats, "accessors": accs, "bufferViews": views,
            "buffers": [{"byteLength": len(buf)}], "animations": anims}
    js = json.dumps(gltf, separators=(",", ":")).encode()
    js += b" " * (-len(js) % 4)
    while len(buf) % 4:
        buf.append(0)
    total = 12 + 8 + len(js) + 8 + len(buf)
    with open(out, "wb") as f:
        f.write(struct.pack("<4sII", b"glTF", 2, total))
        f.write(struct.pack("<I4s", len(js), b"JSON") + js)
        f.write(struct.pack("<I4s", len(buf), b"BIN\0") + bytes(buf))


if __name__ == "__main__":
    main(sys.argv[1])
