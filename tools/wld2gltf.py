"""WLD 场景 -> GLB (含动画) + 标记点 JSON

静态对象按贴图合并为一个图元; 真正会动的对象(逐帧变换 / 顶点变形 / UV 滚动)单独成节点,
带节点 TRS 动画与 morph target, 全部放入一条名为 <场景名> 的动画 —— 帧序列按原版场景动作的 AP 表 (scene_anim.py):
每拍 1/35 秒切一帧、不插值, 一轮 AP 数 + 1 拍 (末帧多停一拍); 只有 AP 0 的场景不动;
MAPS.DAT 第 15 段的贴图滚动写进标记 JSON 的 uv_scroll (地图号 → [{tex, du, dv}], 每拍增量), 32 槽外不滚动的物体用 tex<号>_still 材质; 天空穹顶/远景单独放在 <名>_backdrop 节点, 便于隐藏;
flags bit0 的对象为加法混合特效(光柱/光晕), 放在 <名>_fx 节点, 以 alpha=亮度 的 BLEND 近似;
flags & 0xf == 4 (0x41676c: INVDESTALPHA, INVSRCCOLOR, 关 Z 写; 16 位后台缓冲无 alpha → 结果 = 目标 × (1 − 源色)) 的对象
(路面车辙、贴地阴影) 材质名带 _mul, 由 field.gd unshade 换成专用着色器;
flags & 0xf == 2 (SRCALPHA, INVSRCALPHA, 关 Z 写) 的对象 (水面、地面倒影、窗纸) 材质名带 _blend: 透明度 = 贴图 alpha × 顶点 alpha;
tex=-1 的对象视为标记/触发点, 只输出位置。
用法: python wld2gltf.py <游戏目录> <输出目录> [MAP00001 ...]   (缺省: 全部)
"""
import io
import json
import os
import sys
from multiprocessing import Pool

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(__file__))
from lzo1x import load  # noqa: E402
from ply2gltf import GLB, SCALE, mat_to_trs  # noqa: E402

FPS = 35.0  # 场景动作每拍一帧, 35 拍/秒 (0x4675fb(35))
from render_preview import find_tex  # noqa: E402
from tex2png import decode_tex  # noqa: E402
from wld import parse, world_vertices  # noqa: E402
import scene_anim  # noqa: E402


def is_backdrop(pos, span):
    """天空穹顶/远景环幕: XZ 覆盖场景大部分且有明显高度 (排除地面平板)"""
    s = pos.max(0) - pos.min(0)
    return s[0] > 0.6 * span[0] and s[2] > 0.6 * span[2] and s[1] > 0.2 * min(s[0], s[2])


def material(g, game, tex, additive, cache, still=False, mul=False, blend=False):
    key = (tex, additive, still, mul, blend)
    if key in cache:
        return cache[key]
    mat = {'name': f'tex{tex}' + ('_add' if additive else '') + ('_mul' if mul else '') + ('_blend' if blend else '') + ('_still' if still else ''), 'doubleSided': True,
           'pbrMetallicRoughness': {'metallicFactor': 0, 'roughnessFactor': 1}}
    if tex < 0:   # 无贴图的不透明物体 (黑色环带): 纯黑
        mat['name'] = 'untextured_black'
        mat['pbrMetallicRoughness']['baseColorFactor'] = [0, 0, 0, 1]
        g.g['materials'].append(mat)
        cache[key] = len(g.g['materials']) - 1
        return cache[key]
    tp = find_tex(game, 'MAP', tex)
    if tp:
        img = decode_tex(load(tp)[1])[0]
        # 同一张贴图的 _mul / _blend 变体共用图片: *.tex.json 按 images 顺序对应高清贴图, 不能多出一张
        shared = g.__dict__.setdefault('tex_index', {})
        tex_key = (tex, additive, still)
        if additive:  # glTF 无加法混合: 用亮度作 alpha 近似
            rgb = np.asarray(img.convert('RGB'))
            img = Image.fromarray(np.dstack([rgb, rgb.max(2)]), 'RGBA')
        if tex_key not in shared:
            buf = io.BytesIO()
            img.save(buf, 'PNG')
            g.g['images'].append({'name': os.path.basename(tp), 'mimeType': 'image/png',
                                  'bufferView': g.view(buf.getvalue())})
            g.g['textures'].append({'sampler': 0, 'source': len(g.g['images']) - 1})
            shared[tex_key] = len(g.g['textures']) - 1
        mat['pbrMetallicRoughness']['baseColorTexture'] = {'index': shared[tex_key]}
        if additive:
            mat['alphaMode'] = 'BLEND'
        elif img.mode == 'RGBA':
            mat['alphaMode'] = 'MASK'
    g.g['materials'].append(mat)
    cache[key] = len(g.g['materials']) - 1
    return cache[key]


def vertex_rgba(v):
    """顶点色 (u32 ARGB, 顶点第 10 个字) → (n, 4) RGBA 0..1"""
    c = np.ascontiguousarray(v[:, 9]).view(np.uint32)
    return np.stack([(c >> 16) & 0xff, (c >> 8) & 0xff, c & 0xff, (c >> 24) & 0xff], 1).astype(np.float32) / 255.0


def vertex_color(g, rgba):
    """场景顶点色 (逆向确认): 原版场景用 TL 顶点 (FVF 0x1c4) 自己变换, diffuse 直接拷模型顶点的第 10 个字
    (0x416cd8 / 0x418628 / 0x4190bc, 不另乘系数); 全程没设 TEXTUREMAPBLEND / 纹理阶段状态 → DX6 默认 MODULATE = 贴图 × 顶点色。
    暗场景 (太一迷宫顶点色中位数 44/255、太一圣殿 58、秦宫 94) 的明暗就烘在顶点色里; 以前不透明物体只导 alpha, 全按贴图原亮度画, 偏亮 (用户反馈)。
    加法物体同理: 颜色 = 贴图 × 顶点 RGB, 亮度再乘顶点 alpha (例 MAP00078 地面光斑 alpha 0x26)"""
    return g.accessor(np.ascontiguousarray(rgba, np.float32), 'VEC4', 34962)


def build_mesh(g, game, mname, by_tex, additive, cache):
    prims = []
    for (tex, still, mul, blend), parts in sorted(by_tex.items()):
        P, N, U, I, A, off = [], [], [], [], [], 0
        for pos, nrm, uv, idx, alpha in parts:
            P.append(pos); N.append(nrm); U.append(uv); I.append(idx + off); A.append(alpha)
            off += len(pos)
        P = np.concatenate(P).astype(np.float32)
        N = np.concatenate(N).astype(np.float32)
        ln = np.linalg.norm(N, axis=1)
        N[~(ln > 1e-6)] = [0, 1, 0]
        N /= np.linalg.norm(N, axis=1, keepdims=True)
        U = np.concatenate(U).astype(np.float32)
        U[~np.isfinite(U)] = 0  # 原数据中个别 UV 为 NaN
        I = np.concatenate(I)
        I = I.astype(np.uint16 if off < 65536 else np.uint32)
        prims.append({'attributes': {'POSITION': g.accessor(P, 'VEC3', 34962, True),
                                     'NORMAL': g.accessor(N, 'VEC3', 34962),
                                     'TEXCOORD_0': g.accessor(U, 'VEC2', 34962)},
                      'indices': g.accessor(I, 'SCALAR', 34963),
                      'material': material(g, game, tex, additive, cache, still, mul, blend)})
        prims[-1]['attributes']['COLOR_0'] = vertex_color(g, np.concatenate(A))
    g.g['meshes'].append({'name': mname, 'primitives': prims})
    return len(g.g['meshes']) - 1


def is_animated(ob, aps=None):
    """aps = 场景动作逐拍显示的帧号; 只比较会显示到的帧 (帧号不超过物体帧数, export 里检查)"""
    used = sorted({f for f in aps if f < len(ob.frames)}) if aps is not None else range(len(ob.frames))
    if len(used) > 1:
        F = np.array([ob.frames[f] for f in used])
        if np.abs(F - F[0]).max() > 1e-4:
            return True
    if ob.morph is not None:
        m = ob.morph[[f for f in used if f < len(ob.morph)]] if aps is not None else ob.morph
        with np.errstate(invalid='ignore'):  # 原数据中有 NaN
            d = np.nan_to_num(np.abs(m - m[0]))
        if d[:, :, :3].max() > 1e-3 or d[:, :, 4:9].max() > 1e-5:
            return True
    return False


def fix_uv(v):
    """原数据里个别顶点的 UV 是垃圾值 (例 MAP00017 茅屋墙 u = 7.3e23、v = 1.6e-42, 共 26 个场景 1.4 万个顶点):
    插值后整片三角形的贴图被拉成细条纹。改用同一物体里位置最近的正常顶点的 UV (NaN 同样处理)"""
    U = v[:, 7:9].astype(np.float64)
    bad = ~np.isfinite(U).all(1) | (np.abs(np.nan_to_num(U)) > 1000).any(1)
    if bad.any():
        good = np.where(~bad)[0]
        if len(good):
            P = np.nan_to_num(v[:, :3])
            for i in np.where(bad)[0]:
                j = good[np.argmin(((P[good] - P[i]) ** 2).sum(1))]
                U[i] = U[j]
        else:
            U[bad] = 0
    return U.astype(np.float32)


def clean_attrs(v):
    """顶点 (n,10) -> 位置/法线/UV, 修复原数据中的零/NaN 法线与 NaN UV"""
    P = np.nan_to_num(v[:, :3]).astype(np.float32)
    N = v[:, 4:7].astype(np.float32)
    ln = np.linalg.norm(N, axis=1)
    N[~(ln > 1e-6)] = [0, 1, 0]
    N /= np.linalg.norm(N, axis=1, keepdims=True)
    U = fix_uv(v)  # UV 原样使用 (wrap 寻址, 见 ply2gltf), 只修垃圾值
    return P, N, U


def add_animated(g, game, ob, idx, parent, additive, cache, anim, aps=None, still=False, mul=False, blend=False):
    """动画对象: 局部网格 + 节点 TRS 动画 + morph target。
    aps = 场景动作逐拍帧号: 第 i 拍 (i/35 秒) 显示帧 aps[i], VO 那拍停在末帧, 第 len+1 拍回到开头; 全部 STEP 不插值。
    aps 为 None (没有地图用到这个场景, 原版播放方式不明) 时按 WLD 帧顺序逐拍播放"""
    base = ob.morph[0] if ob.morph is not None else ob.verts
    P, N, U = clean_attrs(base)
    I = ob.indices.astype(np.uint16)
    prim = {'attributes': {'POSITION': g.accessor(P, 'VEC3', 34962, True),
                           'NORMAL': g.accessor(N, 'VEC3', 34962),
                           'TEXCOORD_0': g.accessor(U, 'VEC2', 34962)},
            'indices': g.accessor(I, 'SCALAR', 34963), 'material': material(g, game, ob.tex, additive, cache, still, mul, blend)}
    prim['attributes']['COLOR_0'] = vertex_color(g, vertex_rgba(base))
    K = len(ob.frames)
    seq = list(aps) if aps is not None else list(range(K))
    seq = seq + [seq[-1], seq[0]]   # VO 那拍停在末帧; 最后一个键在 (n+1)/35 秒 = 一轮的长度, 值同开头 (循环接缝)
    T = len(seq)
    times = None

    def t_input():
        nonlocal times
        if times is None:
            times = g.accessor((np.arange(T) / FPS).astype(np.float32), 'SCALAR', None, True)
        return times

    mesh = {'name': f'obj{idx}', 'primitives': [prim]}
    frame_t = None
    uv_scroll = None
    if ob.morph is not None:
        # 整张贴图平移 (瀑布 / 河水): 每帧所有顶点 UV 变化相同 → 只记每帧偏移 (glTF 的 UV morph 引擎不支持), morph 只留位置/法线
        with np.errstate(invalid='ignore'):
            du = np.nan_to_num(ob.morph[:, :, 7:9] - ob.morph[0:1, :, 7:9])
        mean = du.mean(axis=1)
        # 容差 0.005: 翻页火焰 (例 太一迷宫 MAP00121 的 40 个黄火, 贴图 22719, 4×2 格) 各格宽度略有出入 (0.243 / 0.239),
        # 顶点间平移量差 0.002 (256 宽贴图上半个像素); 以前容差 1e-4 认不出, UV 留在 Godot 不认的 morph 里, 火焰静止 (用户反馈)
        if np.abs(du - mean[:, None, :]).max() < 5e-3 and np.abs(mean).max() > 1e-5:
            uv_scroll = mean.round(5).tolist()
            UV_ANIM[f'obj{idx}_tex{ob.tex}'] = {'fps': FPS, 'frames': [uv_scroll[f] for f in seq[:-1]]}
        seen, uniq, frame_t = {}, [], []
        for f in range(K):
            mf = ob.morph[f].copy()
            if uv_scroll is not None:
                mf[:, 7:9] = ob.morph[0][:, 7:9]
            key = mf.tobytes()
            if key not in seen:
                seen[key] = len(uniq)
                uniq.append(mf)
            frame_t.append(seen[key])
        if len({frame_t[f] for f in seq}) > 1:
            targets = []
            for v in uniq:
                p2, n2, u2 = clean_attrs(v)
                targets.append({'POSITION': g.accessor(p2 - P, 'VEC3', 34962, True),
                                'NORMAL': g.accessor(n2 - N, 'VEC3', 34962),
                                'TEXCOORD_0': g.accessor(u2 - U, 'VEC2', 34962)})
            prim['targets'] = targets
            mesh['weights'] = [1.0] + [0.0] * (len(targets) - 1)
        else:
            frame_t = None
    g.g['meshes'].append(mesh)
    M4 = [np.vstack([fr, [0, 0, 0, 1]]) for fr in ob.frames]
    t, q, sc = mat_to_trs(M4[0])
    node = {'name': f'obj{idx}_tex{ob.tex}', 'mesh': len(g.g['meshes']) - 1,
            'translation': t.tolist(), 'rotation': q.tolist(), 'scale': sc.tolist()}
    g.g['nodes'].append(node)
    ni = len(g.g['nodes']) - 1
    g.g['nodes'][parent]['children'].append(ni)
    F = np.array(ob.frames)
    if K > 1 and np.abs(F[seq] - F[seq[0]]).max() > 1e-4:
        trs = [mat_to_trs(M4[f]) for f in seq]
        for k, path, typ in [(0, 'translation', 'VEC3'), (1, 'rotation', 'VEC4'), (2, 'scale', 'VEC3')]:
            vals = np.array([x[k] for x in trs], np.float32)
            if np.allclose(vals, vals[0], atol=1e-5):
                continue
            anim['samplers'].append({'input': t_input(), 'output': g.accessor(vals, typ), 'interpolation': 'STEP'})
            anim['channels'].append({'sampler': len(anim['samplers']) - 1, 'target': {'node': ni, 'path': path}})
    if frame_t is not None:
        w = np.zeros((T, len(prim['targets'])), np.float32)
        w[np.arange(T), [frame_t[f] for f in seq]] = 1
        anim['samplers'].append({'input': t_input(), 'output': g.accessor(w.reshape(-1), 'SCALAR'),
                                 'interpolation': 'STEP'})
        anim['channels'].append({'sampler': len(anim['samplers']) - 1, 'target': {'node': ni, 'path': 'weights'}})


UV_ANIM = {}   # 节点名 → {fps, frames: [[du, dv], ...]} (当前场景)


def export(game, name, out_dir, aps=None, uv=None):
    """aps: 场景动作逐拍帧号 (None = 没有地图用到); uv: scene_anim.scene_uv 里这个场景的条目"""
    UV_ANIM.clear()
    objs, _ = parse(os.path.join(game, 'Model', name + '.WLD'))
    if aps is not None:
        bad = [i for i, ob in enumerate(objs) if len(ob.verts) and max(aps) >= len(ob.frames)]
        if bad:   # 0x418248 只检查物体 0 (超出则整个场景不画); 其他物体超出时原版读到的数据不明
            print(f'WARN {name}: 场景帧号 {max(aps)} 超出物体 {bad[:8]} 的帧数')
    still = set((uv or {}).get('still', []))
    visible = [(i, ob, world_vertices(ob, 0)) for i, ob in enumerate(objs)
               if len(ob.verts) and len(ob.indices)]
    allp = np.concatenate([p for _, ob, p in visible if ob.tex >= 0])
    span = allp.max(0) - allp.min(0)
    layers = {'scene': {}, 'backdrop': {}, 'fx': {}}
    moving = {'scene': [], 'backdrop': [], 'fx': []}
    markers = []
    for i, ob, pos in visible:
        if ob.tex < 0:
            markers.append({'object': i, 'center': pos.mean(0).round(2).tolist(),
                            'min': pos.min(0).round(2).tolist(), 'max': pos.max(0).round(2).tolist(),
                            'frames': len(ob.frames)})
            # 原版不按 tex −1 跳过 (0x415de6 只是不绑贴图): 不透明 (flags & 0xf == 0) 且顶点色是黑的物体照样画出来 —
            # 例: 研究石室 MAP00024 物体 1, 贴在地板外缘的黑色环带 (verify_scene.md §1.4)。
            # 白色的 (多是撑大包围盒的远角小方片) 不画, 免得出现白块
            c = np.ascontiguousarray(ob.verts[:, 9]).view(np.uint32)
            rgb = np.stack([(c >> 16) & 0xff, (c >> 8) & 0xff, c & 0xff], 1)
            if (ob.kind & 0xf) == 0 and rgb.max() < 16 and not is_animated(ob, aps):
                M = ob.frames[0][:, :3]
                v = ob.morph[0] if ob.morph is not None else ob.verts
                layers['scene'].setdefault((-1, False, False, False), []).append(
                    (pos, v[:, 4:7] @ M.T, np.zeros((len(v), 2)), ob.indices.astype(np.uint32), vertex_rgba(v)))
            continue
        M = ob.frames[0][:, :3]
        v = ob.morph[0] if ob.morph is not None else ob.verts
        nrm = v[:, 4:7] @ M.T
        layer = 'fx' if ob.kind & 1 else 'backdrop' if is_backdrop(pos, span) else 'scene'
        if is_animated(ob, aps):
            moving[layer].append((i, ob))
            continue
        if layer == 'fx' and pos[:, 1].max() - pos[:, 1].min() < 1.0:
            # 平铺在地面上的加法层 (光斑 / 地面纹样) 与地面共面: 原版后画、深度相等照样通过; 这里深度插值有误差会闪烁 (Z-fighting),
            # 抬高 2 单位 (2 厘米)
            pos = pos.copy()
            pos[:, 1] += 2.0
        layers[layer].setdefault((ob.tex, i in still, (ob.kind & 0xf) == 4, (ob.kind & 0xf) == 2), []).append(
            (pos, nrm, fix_uv(v), ob.indices.astype(np.uint32), vertex_rgba(v)))

    g = GLB()
    g.g['nodes'].append({'name': name, 'scale': [SCALE] * 3, 'children': []})
    cache = {}
    anim = {'name': name, 'samplers': [], 'channels': []}
    for layer, by_tex in layers.items():
        if not by_tex and not moving[layer]:
            continue
        node = {'name': f'{name}_{layer}', 'children': []}
        if by_tex:
            node['mesh'] = build_mesh(g, game, f'{name}_{layer}', by_tex, layer == 'fx', cache)
        g.g['nodes'].append(node)
        li = len(g.g['nodes']) - 1
        g.g['nodes'][0]['children'].append(li)
        for i, ob in moving[layer]:
            add_animated(g, game, ob, i, li, layer == 'fx', cache, anim, aps, i in still, (ob.kind & 0xf) == 4, (ob.kind & 0xf) == 2)
        if not node['children']:
            del node['children']
    if anim['channels']:
        g.g['animations'].append(anim)
    os.makedirs(out_dir, exist_ok=True)
    g.save(os.path.join(out_dir, name + '.glb'))
    animated = sum(len(v) for v in moving.values())
    info = {'scene': name, 'objects': len(objs), 'textures': len(cache), 'animated_objects': animated,
            'backdrop_textures': sorted({k[0] for k in layers['backdrop']}), 'markers': markers, 'uv_anim': dict(UV_ANIM),
            'frames': aps, 'uv_scroll': {str(k): v for k, v in (uv or {}).get('maps', {}).items()}}
    with open(os.path.join(out_dir, name + '.markers.json'), 'w') as f:
        json.dump(info, f, ensure_ascii=False, indent=1)
    return name, len(objs), animated


def _job(a):
    try:
        return export(*a)
    except Exception as e:
        return a[1], 'ERR', repr(e)


def run(game, out, names=None):
    """导出全部 (或指定) 场景; 多进程的任务函数 _job 在本模块里, 打包成单个程序 (PyInstaller) 后子进程也能找到"""
    names = names or sorted(f[:-4] for f in os.listdir(os.path.join(game, 'Model')) if f.upper().endswith('.WLD'))
    frames = scene_anim.scene_frames(game)
    uv = scene_anim.scene_uv(game, frames)
    with Pool() as pool:
        for r in pool.imap_unordered(_job, [(game, n, out, frames.get(n, {}).get('aps'), uv.get(n)) for n in names]):
            if r[1] == 'ERR':
                print('FAIL', r)
    print('done', len(names))


if __name__ == '__main__':
    run(sys.argv[1], sys.argv[2], sys.argv[3:] or None)
