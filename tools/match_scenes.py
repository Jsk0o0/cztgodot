"""MAP(关卡) <-> WLD(场景模型) 自动配对
依据: MAP.world_size == WLD 头部 bbox 跨度 (无精确匹配时放宽为 XZ 相差 2% 以内); 世界坐标 = MAP 坐标 + WLD bbox 最小角;
多个候选时, 以触发区落点离场景几何(XZ)的距离打分, 分数接近(1.5 倍内)的再按名称用字重合度挑选。
游戏内权威映射表未找到(exe 加壳), 结果为推断, 见 confidence 字段。
输出 extracted/scene_map.json
用法: python match_scenes.py <游戏目录> <maps.json> <wld_models.json> <输出.json>
"""
import json
import os
import struct
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from wld import parse, world_vertices  # noqa: E402


GENERIC = set('室内迷宫城镇户外剧情地图战斗前后段日夜景用之国')


def name_overlap(a, b):
    return len((set(a) - GENERIC) & set(b))


def main(game, maps_json, wld_json, out):
    maps = json.load(open(maps_json))
    names = {os.path.basename(w['file'])[:-4]: w['name_simplified'] for w in json.load(open(wld_json))}
    scenes = {}
    for f in sorted(os.listdir(os.path.join(game, 'Model'))):
        if not f.upper().endswith('.WLD'):
            continue
        objs, o = parse(os.path.join(game, 'Model', f))
        hmin = np.array(struct.unpack_from('<3f', o, 0xBC))
        hmax = np.array(struct.unpack_from('<3f', o, 0xCC))
        pts = [world_vertices(ob, 0) for ob in objs if len(ob.verts) and ob.tex >= 0]
        P = np.concatenate(pts)[:, [0, 2]] if pts else np.zeros((0, 2))
        scenes[f[:-4]] = (hmin, hmax - hmin, P[::5])
    result = []
    for m in maps:
        ws = np.array(m['world_size'])
        cands = [k for k, (_, span, _) in scenes.items() if np.allclose(span, ws, atol=1)]
        loose = not cands
        if loose:
            cands = [k for k, (_, span, _) in scenes.items()
                     if np.allclose(span[[0, 2]], ws[[0, 2]], rtol=0.02, atol=1)]  # 只比 XZ
        trig = np.array([t['pos'] for t in m['portals'] + m['triggers']] or np.zeros((0, 3)))
        scored = []
        for k in cands:
            hmin, _, P = scenes[k]
            if len(trig) and len(P):
                W = (trig + hmin)[:, [0, 2]]
                d = np.sqrt(((W[:, None] - P[None]) ** 2).sum(-1)).min(1)
                scored.append((float(np.median(d)), k))
            else:
                scored.append((float('inf'), k))
        scored.sort()
        if len(scored) > 1:
            near = [x for x in scored if x[0] <= scored[0][0] * 1.5 + 1e-6] if np.isfinite(scored[0][0]) else scored
            sim = lambda k: name_overlap(m['short_name'], names.get(k, ''))  # noqa: E731
            pick = max(near, key=lambda x: (sim(x[1]), -x[0]))
            scored.remove(pick)
            scored.insert(0, pick)
        best = scored[0][1] if scored else None
        conf = ('unique' if len(cands) == 1 else 'scored') if best else 'none'
        if loose and best:
            conf = 'loose_' + conf
        if best and scored[0][0] > 400 and len(trig):
            conf += '_weak'
        result.append({'map_id': m['map_id'], 'scene_id': m['scene_id'], 'map_name': m['name_simplified'],
                       'wld': best, 'wld_name': names.get(best), 'confidence': conf,
                       'median_trigger_dist': round(scored[0][0], 1) if scored else None,
                       'candidates': [k for _, k in scored],
                       'offset': scenes[best][0].tolist() if best else None})
    json.dump(result, open(out, 'w'), ensure_ascii=False, indent=1)
    from collections import Counter
    print(Counter(r['confidence'] for r in result))


if __name__ == '__main__':
    main(*sys.argv[1:5])
