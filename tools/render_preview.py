"""PLY 软件渲染预览 (带贴图, 正交前视 + 侧视)
用法: python render_preview.py <游戏目录> <输出png> <模型名...> [--frame N]
"""
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(__file__))
from lzo1x import load  # noqa: E402
from ply import frame_vertices, parse  # noqa: E402
from tex2png import decode_tex  # noqa: E402

TEX_DIRS = ['CHR', 'ITM', 'MGC', 'OTH', 'MAP', 'SYS']


def find_tex(game, kind, tex_id):
    for d in [kind] + TEX_DIRS:
        p = os.path.join(game, 'Tex', d, f'ALL{tex_id:05d}.TEX')
        if os.path.exists(p):
            return p
    return None


def tex_array(game, kind, tex_id, cache={}):
    key = (kind, tex_id)
    if key not in cache:
        p = find_tex(game, kind, tex_id) if tex_id >= 0 else None
        cache[key] = np.asarray(decode_tex(load(p)[1])[0].convert('RGBA')) if p else None
    return cache[key]


def render(game, name, frame=0, size=360, yaw=0.0):
    m = parse(os.path.join(game, 'Model', name + '.PLY'))
    kind = name[:3]
    pos, nrm, v = frame_vertices(m, frame)
    c, s = np.cos(yaw), np.sin(yaw)
    R = np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])
    pos = pos @ R.T
    nrm = nrm @ R.T
    lo, hi = pos.min(0), pos.max(0)
    scale = (size * 0.9) / max(hi[0] - lo[0], hi[1] - lo[1], 1e-6)
    sx = (pos[:, 0] - (lo[0] + hi[0]) / 2) * scale + size / 2
    sy = size / 2 - (pos[:, 1] - (lo[1] + hi[1]) / 2) * scale
    z = pos[:, 2]
    img = np.full((size, size, 3), 235, np.uint8)
    zb = np.full((size, size), -np.inf)
    uv = v[:, 7:9]  # 原样使用, 采样时取小数部分 (wrap)
    for g in m.groups:
        if g.tex < 0:
            continue  # 挂点标记
        tex = tex_array(game, kind, g.tex)
        for t in range(g.istart // 3, g.iend // 3):
            a, b, cc = m.indices[3 * t:3 * t + 3]
            xs, ys = sx[[a, b, cc]], sy[[a, b, cc]]
            x0, x1 = int(max(xs.min(), 0)), int(min(xs.max() + 1, size))
            y0, y1 = int(max(ys.min(), 0)), int(min(ys.max() + 1, size))
            if x0 >= x1 or y0 >= y1:
                continue
            det = (ys[1] - ys[2]) * (xs[0] - xs[2]) + (xs[2] - xs[1]) * (ys[0] - ys[2])
            if abs(det) < 1e-9:
                continue
            X, Y = np.meshgrid(np.arange(x0, x1) + .5, np.arange(y0, y1) + .5)
            l0 = ((ys[1] - ys[2]) * (X - xs[2]) + (xs[2] - xs[1]) * (Y - ys[2])) / det
            l1 = ((ys[2] - ys[0]) * (X - xs[2]) + (xs[0] - xs[2]) * (Y - ys[2])) / det
            l2 = 1 - l0 - l1
            inside = (l0 >= 0) & (l1 >= 0) & (l2 >= 0)
            zz = l0 * z[a] + l1 * z[b] + l2 * z[cc]
            sub = zb[y0:y1, x0:x1]
            vis = inside & (zz > sub)
            if not vis.any():
                continue
            n = nrm[a] + nrm[b] + nrm[cc]
            shade = 0.55 + 0.45 * abs(n[2] / (np.linalg.norm(n) + 1e-9))
            if tex is not None:
                u = l0 * uv[a, 0] + l1 * uv[b, 0] + l2 * uv[cc, 0]
                w = l0 * uv[a, 1] + l1 * uv[b, 1] + l2 * uv[cc, 1]
                th, tw = tex.shape[:2]
                tx = (np.mod(u, 1) * tw).astype(int) % tw
                ty = (np.mod(w, 1) * th).astype(int) % th
                col = tex[ty, tx]
                vis &= col[..., 3] > 0
                rgb = col[..., :3] * shade
            else:
                rgb = np.full(X.shape + (3,), 180 * shade)
            sub[vis] = zz[vis]
            img[y0:y1, x0:x1][vis] = rgb[vis].astype(np.uint8)
    return Image.fromarray(img)


if __name__ == '__main__':
    args = sys.argv[1:]
    frame = 0
    if '--frame' in args:
        i = args.index('--frame')
        frame = int(args[i + 1])
        del args[i:i + 2]
    game, out, names = args[0], args[1], args[2:]
    tiles = []
    for nm in names:
        tiles.append(render(game, nm, frame))
        tiles.append(render(game, nm, frame, yaw=np.pi / 2))
    S = tiles[0].size[0]
    sheet = Image.new('RGB', (S * len(tiles), S), 'white')
    for i, t in enumerate(tiles):
        sheet.paste(t, (i * S, 0))
    sheet.save(out)
