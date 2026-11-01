"""批量导出所有 PLY -> GLB
同网格(顶点/索引/贴图一致)的 PLY 视为同一模型的不同动作, 合并为一个 GLB 的多条动画。
输出: <out>/<类别>/<首个文件名>.glb 以及 <out>/models_index.json
用法: python batch_export.py <游戏目录> <输出目录> [类别过滤如 CHR,ITM]
"""
import hashlib
import json
import os
import sys
from multiprocessing import Pool

sys.path.insert(0, os.path.dirname(__file__))
from ply import parse  # noqa: E402
from ply2gltf import export  # noqa: E402

GAME = OUT = None


def signature(name):
    try:
        m = parse(os.path.join(GAME, 'Model', name + '.PLY'))
    except Exception as e:
        return name, None, repr(e)
    h = hashlib.sha1(m.verts.tobytes() + m.indices.tobytes()
                     + repr([(g.tex, g.istart, g.iend) for g in m.groups]).encode()).hexdigest()
    info = {'verts': len(m.verts), 'tris': len(m.indices) // 3, 'segments': len(m.segments),
            'frames': m.nframes, 'morph_frames': sum(x is not None for x in m.morphs),
            'textures': sorted({g.tex for g in m.groups if g.tex >= 0}),
            'material_names': sorted({g.name for g in m.groups if g.name})}
    return name, h, info


def do_export(group):
    names = group['files']
    out = os.path.join(OUT, names[0][:3], names[0] + '.glb')
    os.makedirs(os.path.dirname(out), exist_ok=True)
    try:
        export(GAME, names, out)
        return names[0], None
    except Exception as e:
        return names[0], repr(e)


def init(g, o):
    global GAME, OUT
    GAME, OUT = g, o


def main(game, out, kinds=None):
    names = sorted(f[:-4] for f in os.listdir(os.path.join(game, 'Model')) if f.upper().endswith('.PLY'))
    if kinds:
        names = [n for n in names if n[:3] in kinds]
    groups, fails = {}, []
    with Pool(initializer=init, initargs=(game, out)) as pool:
        for name, h, info in pool.imap(signature, names, chunksize=4):
            if h is None:
                fails.append((name, info))
                continue
            grp = groups.setdefault(h, dict(info, files=[], frames_per_file=[]))
            grp['files'].append(name)
            grp['frames_per_file'].append(info['frames'])
        index = sorted(groups.values(), key=lambda g: g['files'][0])
        print(f'{len(names)} PLY -> {len(index)} 个模型, 解析失败 {len(fails)}')
        for g in index:
            del g['frames']
        for name, err in pool.imap_unordered(do_export, index):
            if err:
                fails.append((name, err))
                print('FAIL', name, err)
    for g in index:
        g['glb'] = f"{g['files'][0][:3]}/{g['files'][0]}.glb"
    with open(os.path.join(out, 'models_index.json'), 'w') as f:
        json.dump({'models': index, 'failures': fails}, f, ensure_ascii=False, indent=1)
    print('失败:', len(fails))


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2], sys.argv[3].split(',') if len(sys.argv) > 3 else None)
