"""组装关卡: 地图(MAP) 触发区 -> 场景(WLD) 世界坐标
输出 extracted/levels/<map_id>.json 与 levels_index.json
坐标: world = MAP 坐标 + 场景 bbox 最小角 (游戏单位); 另给出 glTF 坐标 (x0.01 米, 与 scenes/*.glb 一致)
用法: python build_levels.py <maps.json> <scene_map.json> <map_graph.json> <输出目录>
"""
import json
import os
import sys

SCALE = 0.01


def main(maps_json, scene_map_json, graph_json, out):
    maps = {m['map_id']: m for m in json.load(open(maps_json))}
    smap = {s['map_id']: s for s in json.load(open(scene_map_json))}
    edges = json.load(open(graph_json))['edges']
    os.makedirs(out, exist_ok=True)
    index = []
    for mid, m in sorted(maps.items()):
        s = smap.get(mid)
        off = s['offset'] if s and s['offset'] else [0, 0, 0]
        trig = []
        for t in m['portals'] + m['triggers']:
            w = [t['pos'][i] + off[i] for i in range(3)]
            name = t.get('name_simplified')
            e = next((e for e in edges if e['from'] == mid and e.get('event_id') == t['event_id']
                      and e.get('portal') == name), None) if name else None
            trig.append({'kind': t.get('kind', 'point'), 'name': name, 'event_id': t['event_id'],
                         'world': [round(v, 2) for v in w],
                         'gltf': [round(v * SCALE, 4) for v in w],
                         'box_min': t.get('box_min'), 'box_max': t.get('box_max'),
                         'target_map': e['to'] if e else None})
        lv = {'map_id': mid, 'name': m['name_simplified'], 'scene_id': m['scene_id'],
              'scene_glb': f"scenes/{s['wld']}.glb" if s and s['wld'] else None,
              'scene_match': s['confidence'] if s else None,
              'world_size': m['world_size'], 'offset': off, 'triggers': trig}
        with open(os.path.join(out, f'{mid}.json'), 'w') as f:
            json.dump(lv, f, ensure_ascii=False, indent=1)
        index.append({k: lv[k] for k in ('map_id', 'name', 'scene_glb', 'scene_match')}
                     | {'portals': sum(t['kind'] == 'portal' for t in trig), 'events': sum(t['kind'] == 'event' for t in trig),
                        'points': sum(t['kind'] == 'point' for t in trig)})
    with open(os.path.join(out, 'levels_index.json'), 'w') as f:
        json.dump(index, f, ensure_ascii=False, indent=1)
    print(len(index), 'levels')


if __name__ == '__main__':
    main(*sys.argv[1:5])
