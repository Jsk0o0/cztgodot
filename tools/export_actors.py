"""导出角色 ACT (all_char.act) 为 Godot 用的 GLB + 动作表

用法: python export_actors.py <游戏目录> <输出目录> ACT号 [ACT号 ...]
      python export_actors.py <游戏目录> <输出目录> --list 文件   (文件里每行一个 ACT 号)
输出: <输出目录>/act_<号>.json  {"poses": {动作号: {"g": 组, "clip": 动画名, "ticks": 帧数, "marks": [...], "sounds": [...]}},
                                 "groups": [{"glb": 文件名, "files": [PLY...]}]}
      <输出目录>/act_<号>_g<组>.glb  同一网格 (顶点数、部件数相同) 的全部动作, 动画名 pose_<动作号>, 35 帧/秒按 ACT 播放表取帧
ACT 号按类别取文件 (act.ACT_FILES): 角色 0–2999, 道具 3000+, 地图物件 15000+ (出入口箭头、宝箱、门…)。
一个 ACT 的各个动作可能用不同网格 (例如换成道具或另一套模型), 所以按网格签名分组, 运行时切换动作时换用对应组的模型。
已存在且比 all_char.act 新的输出会跳过。
"""
import json
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from act import ACT_FILES, actions, model_file  # noqa: E402
from ply import parse  # noqa: E402
from ply2gltf import export  # noqa: E402

FPS = 35.0


def mesh_sig(m):
    """合组签名: 同组的 PLY 共用第一个文件的网格 / 材质 (ply2gltf 只取各文件的骨骼矩阵和逐帧变形)。
    以前只比顶点数和段数, 贴图不同的也并在一起 (43 组; 例 太一圣殿火盆 15046 动作 2 原版黄火 OTH00122 显示成动作 1 的绿火 OTH00121,
    用户反馈)。现在材质组 (贴图 / 混合 / 索引范围)、索引、基准 UV、顶点色也要相同"""
    uv = np.nan_to_num(m.verts[:, 7:9].astype(np.float64)).round(4)
    return (len(m.verts), len(m.segments), tuple((g.tex, g.flags, g.istart, g.iend) for g in m.groups),
            m.indices.tobytes(), uv.tobytes(), np.asarray(m.colors).tobytes())


def clip_seq(game, gr, v, sig_cache):
    """动作的播放表: [(文件序号, 帧号)]。多段 FR 的动作逐段接起来 (各段网格相同才在同一组里)。
    换网格的段 (已导出角色里 14 个动作) 这里放不进同一个 GLB: 停在前一帧, 时长不变"""
    seq = []
    for fr, ap in zip(v['apf'], v['aps']):
        f = model_file(fr)
        if f not in sig_cache:
            sig_cache[f] = mesh_sig(parse(os.path.join(game, 'Model', f + '.PLY')))
        if sig_cache[f] == gr['sig']:
            if f not in gr['files']:
                gr['files'].append(f)
            seq.append((gr['files'].index(f), ap))
        else:
            seq.append(seq[-1] if seq else (gr['files'].index(v['model']), 0))
    return seq or [(gr['files'].index(v['model']), 0)]


def reexport_multi_fr(game, out):
    """--multi-fr: 重导含多段 FR 动作的模型组; act_<号>.json 只更新 files (其他字段是 export_faces / export_held 补的)"""
    files, sig, n = {}, {}, 0
    for fn in sorted(os.listdir(out)):
        if not (fn.startswith('act_') and fn.endswith('.json')) or fn.endswith('.morph.json'):
            continue
        path = os.path.join(out, fn)
        meta = json.load(open(path, encoding='utf-8'))
        if 'act' not in meta or 'groups' not in meta:
            continue
        a = int(meta['act'])
        k = a // 3000
        if k not in files:
            files[k] = open(os.path.join(game, 'ACT', ACT_FILES[k]), 'rb').read()
        if not any(len(set(v['apf'])) > 1 for v in actions(files[k], a).values()):
            continue
        grs = groups_clips(game, files[k], a, sig)
        for gi, g in enumerate(meta['groups']):
            if gi >= len(grs) or grs[gi]['files'][:1] != g['files'][:1]:
                print('ACT %d 组 %d: 分组对不上, 跳过' % (a, gi))
                continue
            if not any(len({m for m, _ in c[2]}) > 1 for c in grs[gi]['clips']):
                continue
            export(game, grs[gi]['files'], os.path.join(out, g['glb']), fps=FPS, clips=grs[gi]['clips'],
                   sidecar=any(uv_animated(game, f, {}) for f in grs[gi]['files']))
            g['files'] = grs[gi]['files']
            n += 1
        with open(path, 'w', encoding='utf-8') as fp:
            json.dump(meta, fp, ensure_ascii=False)
    print('重导 %d 组' % n)


def export_act(game, act_data, act_id, out, sig_cache):
    meta_path = os.path.join(out, 'act_%d.json' % act_id)
    src = os.path.join(game, 'ACT', ACT_FILES[act_id // 3000])
    if os.path.exists(meta_path) and os.path.getmtime(meta_path) > os.path.getmtime(src):
        return 'skip'
    try:
        poses = actions(act_data, act_id)
    except (KeyError, IndexError):
        return 'no act'
    groups, meta = [], {}
    for q, v in sorted(poses.items()):
        f = v['model']
        path = os.path.join(game, 'Model', f + '.PLY')
        if not os.path.exists(path):
            continue
        if f not in sig_cache:
            try:
                sig_cache[f] = mesh_sig(parse(path))
            except Exception:  # noqa: BLE001 (个别 PLY 损坏)
                sig_cache[f] = None
        sig = sig_cache[f]
        if sig is None:
            continue
        g = next((k for k, gr in enumerate(groups) if gr['sig'] == sig), None)
        if g is None:
            groups.append({'sig': sig, 'files': [], 'clips': []})
            g = len(groups) - 1
        gr = groups[g]
        if f not in gr['files']:
            gr['files'].append(f)
        gr['clips'].append(('pose_%d' % q, gr['files'].index(f), clip_seq(game, gr, v, sig_cache)))
        meta[q] = {'g': g, 'clip': 'pose_%d' % q, 'ticks': len(v['aps'] or [0]), 'loop': v['loop'],
                   'marks': v['marks'], 'sounds': v['sounds']}
        if v.get('xform'):
            meta[q]['xform'] = v['xform']
        if v.get('bbox'):
            meta[q]['bbox'] = v['bbox']
        if v.get('er'):   # ER: 挂点粒子 [[slot, 粒子号, 停止帧]] (地图角色 0x46e05c); 停止帧和当前模型帧 (AP 值) 比较, 所以带上 AP 序列
            meta[q]['er'] = v['er']
            meta[q]['aps'] = v['aps']
    for k, gr in enumerate(groups):
        name = 'act_%d_g%d.glb' % (act_id, k)
        export(game, gr['files'], os.path.join(out, name), fps=FPS, clips=gr['clips'],
               sidecar=any(uv_animated(game, f, {}) for f in gr['files']))   # 只给有 UV 动画的组
        gr['glb'] = name
    with open(meta_path, 'w', encoding='utf-8') as fp:
        json.dump({'act': act_id, 'poses': meta, 'groups': [{'glb': gr['glb'], 'files': gr['files']} for gr in groups]},
                  fp, ensure_ascii=False)
    return '%d 个动作, %d 组' % (len(meta), len(groups))


def groups_clips(game, act_data, act_id, sig_cache):
    """同 export_act 的分组: [{'files': [...], 'clips': [(动画名, 文件序号, 播放表)]}]"""
    groups = []
    for q, v in sorted(actions(act_data, act_id).items()):
        f = v['model']
        path = os.path.join(game, 'Model', f + '.PLY')
        if not os.path.exists(path):
            continue
        if f not in sig_cache:
            try:
                sig_cache[f] = mesh_sig(parse(path))
            except Exception:  # noqa: BLE001
                sig_cache[f] = None
        sig = sig_cache[f]
        if sig is None:
            continue
        g = next((k for k, gr in enumerate(groups) if gr['sig'] == sig), None)
        if g is None:
            groups.append({'sig': sig, 'files': [], 'clips': []})
            g = len(groups) - 1
        gr = groups[g]
        if f not in gr['files']:
            gr['files'].append(f)
        gr['clips'].append(('pose_%d' % q, gr['files'].index(f), clip_seq(game, gr, v, sig_cache)))
    return groups


def uv_animated(game, f, cache):
    """PLY 逐帧变形里 UV 有变化 (光效流动等): glTF 的 UV morph Godot 不认, 要 sidecar"""
    if f not in cache:
        r = False
        try:
            m = parse(os.path.join(game, 'Model', f + '.PLY'))
            base = np.nan_to_num(m.verts[:, 7:9])
            for mo in m.morphs:
                if mo is None:
                    continue
                offs, mv = mo
                for i, sg in enumerate(m.segments):
                    k = sg.vend - sg.vstart
                    if offs[i] >= 0 and np.abs(np.nan_to_num(mv[offs[i]:offs[i] + k, 7:9]) - base[sg.vstart:sg.vend]).max() > 1e-4:
                        r = True
                if r:
                    break
        except Exception:  # noqa: BLE001
            pass
        cache[f] = r
    return cache[f]


def tinted(game, f, cache):
    """顶点色不是全白 (地图物件常有烘好的明暗): 原版画 PLY 时 diffuse = 顶点色, 贴图 × 顶点色 (0x416cd8)"""
    if f not in cache:
        try:
            c = np.asarray(parse(os.path.join(game, 'Model', f + '.PLY')).colors, np.uint32)
            cache[f] = bool(((c & 0xffffff) != 0xffffff).any())
        except Exception:  # noqa: BLE001
            cache[f] = False
    return cache[f]


def glb_has_color(path):
    import struct
    d = open(path, 'rb').read()
    jl = struct.unpack_from('<I', d, 12)[0]
    g = json.loads(d[20:20 + jl])
    return any('COLOR_0' in p['attributes'] for m in g['meshes'] for p in m['primitives'])


def add_sidecars(game, out):
    """--sidecar: 有 UV 动画、还没有 <glb>.morph.json 的模型组重导 GLB 并写 sidecar (例 解封轩辕剑 4115 剑身光流);
    act_<号>.json 不动 (里面有 export_faces / export_held 补的字段)"""
    files, sig, uvc, tc, n = {}, {}, {}, {}, 0
    for fn in sorted(os.listdir(out)):
        if not (fn.startswith('act_') and fn.endswith('.json')):
            continue
        meta = json.load(open(os.path.join(out, fn), encoding='utf-8'))
        if 'act' not in meta or 'groups' not in meta:
            continue   # 不是 export_act 写的 (没有分组信息)
        a = int(meta['act'])
        todo = [k for k, g in enumerate(meta['groups'])
                if (not os.path.exists(os.path.join(out, g['glb'] + '.morph.json')) and any(uv_animated(game, f, uvc) for f in g['files']))
                or (any(tinted(game, f, tc) for f in g['files']) and not glb_has_color(os.path.join(out, g['glb'])))]
        if not todo:
            continue
        k = a // 3000
        if k not in files:
            files[k] = open(os.path.join(game, 'ACT', ACT_FILES[k]), 'rb').read()
        grs = groups_clips(game, files[k], a, sig)
        for gi in todo:
            g = meta['groups'][gi]
            if gi >= len(grs) or grs[gi]['files'] != g['files']:
                print('ACT %d 组 %d: 分组和已导出的对不上, 跳过' % (a, gi))
                continue
            # sidecar 只给有 UV 动画的组 (位置变形 Godot 的 blend shape 本来就能播; 多余的 sidecar 会让引擎逐帧换网格, 帧数多时卡住读取)
            export(game, g['files'], os.path.join(out, g['glb']), fps=FPS, clips=grs[gi]['clips'],
                   sidecar=any(uv_animated(game, f, uvc) for f in g['files']))
            n += 1
    print('补 sidecar %d 组' % n)


def update_meta(game, out):
    """--meta-only: 不重新导出 GLB, 只按 ACT 重新解析已有 act_<号>.json 的记号 / 音效 / 每帧变换 (xform)"""
    files, n = {}, 0
    for fn in sorted(os.listdir(out)):
        if not (fn.startswith('act_') and fn.endswith('.json')) or fn.endswith('.morph.json'):
            continue
        path = os.path.join(out, fn)
        m = json.load(open(path, encoding='utf-8'))
        a = int(m['act'])
        k = a // 3000
        if k not in files:
            files[k] = open(os.path.join(game, 'ACT', ACT_FILES[k]), 'rb').read()
        try:
            poses = actions(files[k], a)
        except (KeyError, IndexError):
            continue
        for q, pm in m['poses'].items():
            v = poses.get(int(q))
            if not v:
                continue
            pm['marks'] = v['marks']
            if v.get('bbox'):
                pm['bbox'] = v['bbox']
            pm['sounds'] = v['sounds']
            if v.get('xform'):
                pm['xform'] = v['xform']
            else:
                pm.pop('xform', None)
            if v.get('er'):
                pm['er'] = v['er']
                pm['aps'] = v['aps']
            else:
                pm.pop('er', None)
                pm.pop('aps', None)
        with open(path, 'w', encoding='utf-8') as fp:
            json.dump(m, fp, ensure_ascii=False)
        n += 1
    print('更新 %d 个动作表' % n)


def main(game, out, ids):
    os.makedirs(out, exist_ok=True)
    files = {}
    cache = {}
    for a in ids:
        k = a // 3000   # ACT 类别 = 文件 (all_char / all_item / all_magic / all_sys / all_map1 / all_map2)
        if k not in files:
            files[k] = open(os.path.join(game, 'ACT', ACT_FILES[k]), 'rb').read()
        print('ACT %d: %s' % (a, export_act(game, files[k], a, out, cache)), flush=True)


if __name__ == '__main__':
    if '--multi-fr' in sys.argv:
        reexport_multi_fr(sys.argv[1], sys.argv[2])
        sys.exit(0)
    if '--sidecar' in sys.argv:
        add_sidecars(sys.argv[1], sys.argv[2])
        sys.exit(0)
    if '--meta-only' in sys.argv:
        update_meta(sys.argv[1], sys.argv[2])
        sys.exit(0)
    g, o, rest = sys.argv[1], sys.argv[2], sys.argv[3:]
    if rest and rest[0] == '--list':
        ids = [int(x) for x in open(rest[1]).read().split() if x.strip()]
    else:
        ids = [int(x) for x in rest]
    main(g, o, ids)
