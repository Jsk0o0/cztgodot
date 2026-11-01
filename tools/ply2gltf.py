"""PLY -> GLB (带贴图、骨骼、动画)

刚性蒙皮: 每个段 = 一个 joint, 顶点权重 1; 顶点本就在骨骼局部空间, 所以 inverseBindMatrix = 单位阵。
多个 PLY 若网格相同(同一角色的不同动作), 可合并成一个 GLB 的多条动画。
用法: python ply2gltf.py <游戏目录> <输出.glb> <模型名> [更多同网格模型名...] [--fps 20]
"""
import io
import json
import os
import struct
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(__file__))
from lzo1x import load  # noqa: E402
from ply import parse, vertex_segment  # noqa: E402
from render_preview import find_tex  # noqa: E402
from tex2png import decode_tex  # noqa: E402

SCALE = 0.01  # 游戏单位≈厘米 -> 米




def alpha_bleed(img):
    """镂空贴图的透明像素 RGB 原本是黑色: 远处缩小 / 双线性过滤时黑色渗进边缘, 细线 (例: 车芸腰间的圆环)
    断成时有时无的闪点。把透明像素填成最近不透明像素的颜色 (alpha 不变)"""
    a = np.asarray(img).copy()
    opaque = a[..., 3] >= 128
    if opaque.all() or not opaque.any():
        return img
    rgb = a[..., :3].astype(np.float32)
    known = opaque.copy()
    for _ in range(16):   # 每轮向外扩一圈
        if known.all():
            break
        acc = np.zeros_like(rgb)
        cnt = np.zeros(known.shape, np.float32)
        for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1), (-1, -1), (-1, 1), (1, -1), (1, 1)):
            k = np.roll(known, (dy, dx), (0, 1))
            acc += np.roll(rgb, (dy, dx), (0, 1)) * k[..., None]
            cnt += k
        grow = (~known) & (cnt > 0)
        rgb[grow] = acc[grow] / cnt[grow][:, None]
        known |= grow
    a[..., :3] = np.clip(rgb, 0, 255).astype(np.uint8)
    return Image.fromarray(a, 'RGBA')

def dedup_tris(idx, pos, uv):
    """去掉位置和贴图坐标都相同的重复三角形 (原模型双面的面常常正反各存一份; 已经 doubleSided,
    两份共面会深度打架, 远处看就是一闪一闪的光点; 305 个角色模型里 128 个有, 共约 5600 个面)"""
    tri = idx.reshape(-1, 3)
    seen = set()
    keep = []
    for t in tri:
        k = tuple(sorted((tuple(np.round(pos[v], 2)), tuple(np.round(uv[v], 3))) for v in t))
        if k in seen:
            continue
        seen.add(k)
        keep.append(t)
    return np.asarray(keep, idx.dtype).reshape(-1) if keep else idx[:0]

def mat_to_trs(M):
    t = M[:3, 3].astype(np.float64)
    A = M[:3, :3].astype(np.float64)
    s = np.linalg.norm(A, axis=0)
    s[s < 1e-12] = 1e-12
    if np.linalg.det(A) < 0:
        s[0] = -s[0]
    R = A / s
    U, _, Vt = np.linalg.svd(R)  # 正交化, 去除数值噪声
    R = U @ Vt
    if np.linalg.det(R) < 0:  # 退化矩阵(缩放为 0)正交化后可能成为反射
        R[:, 0] = -R[:, 0]
        s[0] = -s[0]
    tr = np.trace(R)
    if tr > 0:
        k = np.sqrt(tr + 1) * 2
        q = [(R[2, 1] - R[1, 2]) / k, (R[0, 2] - R[2, 0]) / k, (R[1, 0] - R[0, 1]) / k, k / 4]
    elif R[0, 0] > R[1, 1] and R[0, 0] > R[2, 2]:
        k = np.sqrt(1 + R[0, 0] - R[1, 1] - R[2, 2]) * 2
        q = [k / 4, (R[0, 1] + R[1, 0]) / k, (R[0, 2] + R[2, 0]) / k, (R[2, 1] - R[1, 2]) / k]
    elif R[1, 1] > R[2, 2]:
        k = np.sqrt(1 + R[1, 1] - R[0, 0] - R[2, 2]) * 2
        q = [(R[0, 1] + R[1, 0]) / k, k / 4, (R[1, 2] + R[2, 1]) / k, (R[0, 2] - R[2, 0]) / k]
    else:
        k = np.sqrt(1 + R[2, 2] - R[0, 0] - R[1, 1]) * 2
        q = [(R[0, 2] + R[2, 0]) / k, (R[1, 2] + R[2, 1]) / k, k / 4, (R[1, 0] - R[0, 1]) / k]
    q = np.array(q)
    return t, q / np.linalg.norm(q), s


def morph_targets(g, m, models, nrm_v, uv_v):
    """PLY 逐帧顶点变形 -> glTF morph targets (相同帧去重)。
    返回 (targets, 每个模型每帧对应的 target 下标或 -1)"""
    seen, arrays, frame_target = {}, [], []
    for mo in models:
        ft = []
        for f in range(mo.nframes):
            mm = mo.morphs[f] if f < len(mo.morphs) else None
            if mm is None:
                ft.append(-1)
                continue
            offs, mv = mm
            v = m.verts.copy()
            for i, s in enumerate(m.segments):
                k = s.vend - s.vstart
                if offs[i] >= 0 and k:
                    # 个别模型的变形数据比网格段短 (例: 15048、2004), 只覆盖有数据的顶点, 其余保持静止
                    n = max(0, min(k, len(mv) - offs[i]))
                    v[s.vstart:s.vstart + n] = mv[offs[i]:offs[i] + n]
            key = v.tobytes()
            if key not in seen:
                seen[key] = len(arrays)
                arrays.append(v)
            ft.append(seen[key])
        frame_target.append(ft)
    targets = []
    for v in arrays:
        # 不带 NORMAL: 原数据法线不可靠 (见 geometric_normals), 变形时沿用基础法线
        dp = np.nan_to_num(v[:, :3] - m.verts[:, :3]).astype(np.float32)
        duv = (np.nan_to_num(v[:, 7:9]) - uv_v).astype(np.float32)
        targets.append({'POSITION': g.accessor(dp, 'VEC3', 34962, True),
                        'TEXCOORD_0': g.accessor(duv, 'VEC2', 34962)})
    return targets, frame_target, arrays


class GLB:
    def __init__(self):
        self.bin = bytearray()
        self.g = {'asset': {'version': '2.0', 'generator': 'czt ply2gltf'},
                  'buffers': [], 'bufferViews': [], 'accessors': [], 'nodes': [], 'meshes': [],
                  'materials': [], 'textures': [], 'images': [], 'samplers': [{}], 'skins': [],
                  'animations': [], 'scenes': [{'nodes': [0]}], 'scene': 0}

    def view(self, data, target=None):
        while len(self.bin) % 4:
            self.bin.append(0)
        bv = {'buffer': 0, 'byteOffset': len(self.bin), 'byteLength': len(data)}
        if target:
            bv['target'] = target
        self.bin += data
        self.g['bufferViews'].append(bv)
        return len(self.g['bufferViews']) - 1

    def accessor(self, arr, atype, target=None, minmax=False):
        ctype = {np.float32: 5126, np.uint16: 5123, np.uint32: 5125, np.uint8: 5121}[arr.dtype.type]
        acc = {'bufferView': self.view(np.ascontiguousarray(arr).tobytes(), target),
               'componentType': ctype, 'count': len(arr), 'type': atype}
        if minmax:
            a = arr.reshape(len(arr), -1)
            acc['min'] = a.min(0).tolist()
            acc['max'] = a.max(0).tolist()
        self.g['accessors'].append(acc)
        return len(self.g['accessors']) - 1

    def save(self, path):
        self.g['buffers'] = [{'byteLength': len(self.bin)}]
        for k in [k for k, v in self.g.items() if v == []]:
            del self.g[k]
        js = json.dumps(self.g, ensure_ascii=False).encode()
        js += b' ' * (-len(js) % 4)
        bn = bytes(self.bin) + b'\0' * (-len(self.bin) % 4)
        with open(path, 'wb') as f:
            f.write(struct.pack('<III', 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(bn)))
            f.write(struct.pack('<II', len(js), 0x4E4F534A) + js)
            f.write(struct.pack('<II', len(bn), 0x004E4942) + bn)


def geometric_normals(m):
    """按三角形几何重算平滑法线 (面积加权), 再换回各段局部坐标。
    原数据存的法线约 30% 指向模型内侧 (例: 嬴诗脸部), 光照下发黑; 三角形绕序则 85% 以上朝外, 可信。"""
    seg = vertex_segment(m)
    M = m.matrices[0][seg]
    R = M[:, :3, :3].astype(np.float64)
    pos = np.einsum('nij,nj->ni', R, m.verts[:, :3]) + M[:, :3, 3]
    tri = m.indices.reshape(-1, 3)
    fn = np.cross(pos[tri[:, 1]] - pos[tri[:, 0]], pos[tri[:, 2]] - pos[tri[:, 0]])
    fn = np.nan_to_num(fn)
    n = np.zeros_like(pos)
    for k in range(3):
        np.add.at(n, tri[:, k], fn)
    # 世界 → 局部: 乘以旋转部分的逆 (矩阵可能带缩放, 用正交化的转置)
    U, _, Vt = np.linalg.svd(R)
    Rot = U @ Vt
    local = np.einsum('nji,nj->ni', Rot, n)
    ln = np.linalg.norm(local, axis=1)
    old = m.verts[:, 4:7].astype(np.float64)
    bad = ~(ln > 1e-9)
    local[bad] = np.nan_to_num(old[bad])
    ln = np.linalg.norm(local, axis=1)
    local[~(ln > 1e-9)] = [0, 1, 0]
    return (local / np.linalg.norm(local, axis=1, keepdims=True)).astype(np.float32)


def unmirror(models):
    """原始矩阵大多带镜像 (行列式 < 0)。直接分解会让每根骨骼都带负缩放, Blender 等工具处理不好。
    对多数帧为镜像的部件: 顶点/法线 X 取反, 骨骼矩阵右乘 diag(-1,1,1) 抵消, 最终位置不变。"""
    m = models[0]
    D = np.diag([-1.0, 1.0, 1.0, 1.0]).astype(m.matrices.dtype)
    det = np.concatenate([np.linalg.det(mo.matrices[:, :, :3, :3].astype(np.float64)) for mo in models])
    flip = [(det[:, i] < -1e-9).sum() > (det[:, i] > 1e-9).sum() for i in range(len(m.segments))]
    for mo in models:
        for i, s in enumerate(mo.segments):
            if not flip[i]:
                continue
            mo.matrices[:, i] = mo.matrices[:, i] @ D
            mo.verts[s.vstart:s.vend, [0, 4]] *= -1
            k = s.vend - s.vstart
            for mm in mo.morphs:
                if mm is not None and mm[0][i] >= 0 and k:
                    mm[1][mm[0][i]:mm[0][i] + k, [0, 4]] *= -1


def export(game, names, out, fps=20.0, clips=None, sidecar=False):
    """names: 同一网格的若干 PLY (每个 = 一条动画)。
    clips: 可选 [(动画名, names 中的下标, 帧号列表)], 按 ACT 播放表 (AP 序列) 重新取帧, 每帧 1/fps 秒;
           省略时每个 PLY 按原帧顺序导出一条同名动画。
    sidecar: 有逐帧顶点变形时另写 <out>.morph.json —— 每个 morph target 的完整顶点位置和 UV、各动画每帧用哪个 target。
             glTF 的 UV morph 符合规范, 但 Godot/Blender 只认位置和法线, UV 动画 (特效、流水) 会丢失; 引擎端可据此逐帧换 UV。"""
    models = [parse(os.path.join(game, 'Model', n + '.PLY')) for n in names]
    m = models[0]
    for n, o in zip(names[1:], models[1:]):
        if len(o.verts) != len(m.verts) or len(o.segments) != len(m.segments):
            raise ValueError(f'{n} 与 {names[0]} 网格不一致, 不能合并')
    unmirror(models)
    kind = names[0][:3]
    g = GLB()
    nseg = len(m.segments)
    # 节点: 0 = root(缩放), 1..nseg = joints, nseg+1 = mesh (蒙皮网格须在场景根)
    g.g['nodes'].append({'name': names[0], 'scale': [SCALE] * 3,
                         'children': list(range(1, nseg + 1))})
    g.g['scenes'][0]['nodes'].append(nseg + 1)
    for i, s in enumerate(m.segments):
        t, q, sc = mat_to_trs(m.matrices[0, i])
        kind_s = 'bone' if s.flags & 0x100 else f'marker{s.flags >> 24}'
        g.g['nodes'].append({'name': f'{kind_s}_{i:02d}', 'translation': t.tolist(),
                             'rotation': q.tolist(), 'scale': sc.tolist()})

    seg_of = np.zeros(len(m.verts), np.uint16)
    for i, s in enumerate(m.segments):
        seg_of[s.vstart:s.vend] = i
    pos = g.accessor(m.verts[:, :3].astype(np.float32), 'VEC3', 34962, True)
    nrm_v = geometric_normals(m)
    nrm = g.accessor(nrm_v, 'VEC3', 34962)
    # UV 原样使用: 原数据 v 多为负数, D3D 在 wrap 寻址下取小数部分 (v=-0.22 → 0.78);
    # 取反 (-v) 会把贴图上下颠倒 (嬴诗的脸会采到头发区域而发黑)
    uv_v = m.verts[:, 7:9].astype(np.float32)
    uv_v[~np.isfinite(uv_v)] = 0  # 原数据中个别 UV 为 NaN
    uv = g.accessor(uv_v, 'VEC2', 34962)
    targets, frame_target, target_arrays = morph_targets(g, m, models, nrm_v, uv_v)
    joints = np.zeros((len(m.verts), 4), np.uint16)
    joints[:, 0] = seg_of
    weights = np.zeros((len(m.verts), 4), np.float32)
    weights[:, 0] = 1
    jacc = g.accessor(joints, 'VEC4', 34962)
    wacc = g.accessor(weights, 'VEC4', 34962)

    mat_of_tex = {}
    prims = []
    vidx = None
    if sidecar and target_arrays:
        # TEXCOORD_1.x = 顶点原始下标 / 65535: 引擎端按它把 glTF 顶点对回 morph.json 的顶点 (以前按 (位置, UV) 对, 重叠的顶点会对错)
        vidx = g.accessor(np.stack([np.arange(len(m.verts)) / 65535.0, np.zeros(len(m.verts))], 1).astype(np.float32),
                          'VEC2', 34962)
    col = None   # 顶点色 (u32 ARGB): 只给没有贴图的材质组用 (例: 地图出入口箭头 OTH00038 靠顶点色显示黄橙色)
    marker_vert = np.array([m.segments[s].flags >> 24 != 0 for s in seg_of])
    for grp in m.groups:
        idx = m.indices[grp.istart:grp.iend].astype(np.uint16)
        if len(idx) == 0 or marker_vert[idx].all():
            continue  # 挂点标记三角形不导出
        if grp.flags & 0xFF000000:
            continue  # 材质组 flags 高字节非 0 = 挂点标记组, 原版绘制循环直接跳过 (0x4172e0 / 0x417edf: test flags, 0xff000000)
        if not target_arrays:
            # 有逐帧变形的模型不去重: 变形特效的多份几何在基准帧常常完全重叠 (例 破命 MGC00273 的 18 道地光), 去重会把它们删掉
            idx = dedup_tris(idx, m.verts[:, :3], uv_v)
        additive = bool(grp.flags & 1)  # bit0 = 加法混合(光效)
        key = (grp.tex, additive)
        if key not in mat_of_tex:
            mat = {'name': (grp.name or f'tex{grp.tex}') + ('_add' if additive else ''), 'doubleSided': True,
                   'pbrMetallicRoughness': {'metallicFactor': 0, 'roughnessFactor': 1}}
            tp = find_tex(game, kind, grp.tex) if grp.tex >= 0 else None
            if tp:
                img = decode_tex(load(tp)[1])[0]
                if kind == 'MGC' and not additive:
                    # 特效贴图的纯黑 (0x0000) = 透明 (原版色键; 特效贴图平均 30% 是纯黑底, 角色贴图只有 1%)。
                    # 以前没处理: 千羽的箭、顶击等普通混合层带着一块黑底 (用户反馈)
                    rgba = np.asarray(img.convert('RGBA')).copy()
                    rgba[(rgba[..., :3].max(2) == 0), 3] = 0
                    img = Image.fromarray(rgba, 'RGBA')
                if img.mode == 'RGBA' and not additive:
                    img = alpha_bleed(img)
                if additive:  # glTF 无加法混合: 用亮度作 alpha 近似
                    rgb = np.asarray(img.convert('RGB'))
                    img = Image.fromarray(np.dstack([rgb, rgb.max(2)]), 'RGBA')
                buf = io.BytesIO()
                img.save(buf, 'PNG')
                g.g['images'].append({'name': os.path.basename(tp), 'mimeType': 'image/png',
                                      'bufferView': g.view(buf.getvalue())})
                g.g['textures'].append({'sampler': 0, 'source': len(g.g['images']) - 1})
                mat['pbrMetallicRoughness']['baseColorTexture'] = {'index': len(g.g['textures']) - 1}
                if additive:
                    mat['alphaMode'] = 'BLEND'
                elif img.mode == 'RGBA':
                    mat['alphaMode'] = 'MASK'
            g.g['materials'].append(mat)
            mat_of_tex[key] = len(g.g['materials']) - 1
        prim = {'attributes': {'POSITION': pos, 'NORMAL': nrm, 'TEXCOORD_0': uv,
                               'JOINTS_0': jacc, 'WEIGHTS_0': wacc},
                'indices': g.accessor(idx, 'SCALAR', 34963), 'material': mat_of_tex[key]}
        if vidx is not None:
            prim['attributes']['TEXCOORD_1'] = vidx
        # 顶点色: 无贴图的面靠它上色; 有贴图的面 (特效) 原版 D3D 是 贴图 × 顶点色, 顶点 alpha 决定加法层亮度
        # (例 五雷咒 MGC00172 alpha 101 / 178 = 40% / 70%; 以前丢掉, 特效亮成一片白; 295 个特效模型里 257 个有)
        if m.colors is not None and (grp.tex < 0 or bool((np.asarray(m.colors, np.uint32) != 0xffffffff).any())):
            if col is None:
                c = np.asarray(m.colors, np.uint32)
                rgba = np.stack([(c >> 16) & 0xff, (c >> 8) & 0xff, c & 0xff,
                                 (c >> 24) & 0xff if grp.tex >= 0 else np.full_like(c, 0xff)], 1)
                col = g.accessor((rgba / 255.0).astype(np.float32), 'VEC4', 34962)
            prim['attributes']['COLOR_0'] = col
        if targets:
            prim['targets'] = targets
        prims.append(prim)
    ibm = g.accessor(np.tile(np.eye(4, dtype=np.float32).reshape(1, 16), (nseg, 1)), 'MAT4')
    g.g['skins'].append({'joints': list(range(1, nseg + 1)), 'inverseBindMatrices': ibm, 'skeleton': 0})
    if prims:
        mesh = {'name': names[0], 'primitives': prims}
        if targets:
            mesh['weights'] = [0.0] * len(targets)
            mesh['extras'] = {'targetNames': [f'morph_{i:03d}' for i in range(len(targets))]}
        g.g['meshes'].append(mesh)
        g.g['nodes'].append({'name': names[0] + '_mesh', 'mesh': 0, 'skin': 0})
    else:  # 只有挂点, 没有可见几何
        g.g['nodes'].append({'name': names[0] + '_empty'})
        targets = []

    if clips is None:
        clips = [(n, k, list(range(mo.nframes))) for k, (n, mo) in enumerate(zip(names, models))]
    if sidecar and target_arrays:
        r = lambda a, nd: np.round(np.nan_to_num(a), nd).tolist()  # noqa: E731
        side = {'base_pos': r(m.verts[:, :3], 3), 'base_uv': r(uv_v, 5),
                'targets': [{'pos': r(a[:, :3], 3), 'uv': r(a[:, 7:9], 5)} for a in target_arrays],
                'frames': {}}
        for name, mi, frames in clips:
            seq = [f if isinstance(f, tuple) else (mi, f) for f in frames]
            side['frames'][name] = [frame_target[k][min(max(int(f), 0), len(frame_target[k]) - 1)] for k, f in seq]
        with open(out + '.morph.json', 'w') as f:
            json.dump(side, f, separators=(',', ':'))
    for name, mi, frames in clips:
        # 播放表的一项 = 帧号, 或 (文件序号, 帧号): 一个动作可以跨同网格的多个 PLY
        seq = [f if isinstance(f, tuple) else (mi, f) for f in frames] or [(mi, 0)]
        seq = [(k, min(max(int(f), 0), models[k].nframes - 1)) for k, f in seq]
        ft = [frame_target[k][f] for k, f in seq]
        nf = len(seq)
        times = g.accessor((np.arange(nf) / fps).astype(np.float32), 'SCALAR', None, True)
        trs = [[mat_to_trs(models[k].matrices[f, i]) for k, f in seq] for i in range(nseg)]
        samplers, channels, times1 = [], [], None
        for i in range(nseg):
            for k, path, typ in [(0, 'translation', 'VEC3'), (1, 'rotation', 'VEC4'), (2, 'scale', 'VEC3')]:
                vals = np.array([x[k] for x in trs[i]], np.float32)
                if k == 1:  # 保持四元数连续, 避免插值翻转
                    for f in range(1, nf):
                        if np.dot(vals[f], vals[f - 1]) < 0:
                            vals[f] = -vals[f]
                # 每条动画都写全部骨骼的通道: 引擎切换动画时不会把骨骼复位到静止姿势 (Godot 即如此),
                # 缺通道的骨骼会停在上一条动画的姿势 (例: 嬴诗跳回原位后腿保持跳跃姿势而变形)。
                # 整段不变的通道只写 1 个关键帧, 体积几乎不增加。
                if np.allclose(vals, vals[0], atol=1e-5):
                    if times1 is None:
                        times1 = g.accessor(np.zeros(1, np.float32), 'SCALAR', None, True)
                    samplers.append({'input': times1, 'output': g.accessor(vals[:1], typ), 'interpolation': 'STEP'})
                else:
                    samplers.append({'input': times, 'output': g.accessor(vals, typ), 'interpolation': 'LINEAR'})
                channels.append({'sampler': len(samplers) - 1, 'target': {'node': i + 1, 'path': path}})
        if targets:  # 逐帧切换顶点变形 (STEP); 没用到变形的动画也写全 0 权重, 否则引擎会沿用上一条动画的变形
            w = np.zeros((nf, len(targets)), np.float32)
            for f, t in enumerate(ft):
                if t >= 0:
                    w[f, t] = 1
            samplers.append({'input': times, 'output': g.accessor(w.reshape(-1), 'SCALAR'),
                             'interpolation': 'STEP'})
            channels.append({'sampler': len(samplers) - 1, 'target': {'node': nseg + 1, 'path': 'weights'}})
        if channels:
            g.g['animations'].append({'name': name, 'samplers': samplers, 'channels': channels})
    g.save(out)
    return m


if __name__ == '__main__':
    args = sys.argv[1:]
    fps = 20.0
    if '--fps' in args:
        i = args.index('--fps')
        fps = float(args[i + 1])
        del args[i:i + 2]
    export(args[0], args[2:], args[1], fps)
