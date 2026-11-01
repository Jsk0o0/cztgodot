"""小地图 (0xa83b30, 逆向见 development.md「小地图」) 的图片表 → extracted/game/minimap.json

地图标志 0x40 (MAPS.DAT 第 5 段) = 有小地图。图 = 场景 ACT ([0xa84fe0], MAP 头 +0x0a) 的第 <楼层> 号动作,
楼层 = [0x4e48c8] (换图时 1, 事件 set_floor 改); 动作 0 是场景本身, 所以楼层从 1 数起。
动作的 FR 即图片: FR // 3000 选 TSW 文件, FR % 3000 是其中的条目号。
输出: {地图号: {楼层: 图片相对路径}}
用法: python3 tools/export_minimap.py <原版目录> <extracted 目录>
"""
import json
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from act import ACT_FILES, read_index  # noqa: E402
from mapsdat import MapsDat  # noqa: E402
from scene_anim import _action_ops  # noqa: E402

TSW = ['all_char', 'all_item', 'all_magic', 'all_sys', 'all_map1', 'all_map2']


def main(game, ext):
    acts = {k: open(os.path.join(game, 'ACT', ACT_FILES[k]), 'rb').read() for k in (4, 5)}
    ui = json.load(open(os.path.join(ext, 'ui', 'index.json'), encoding='utf-8'))
    dirs = {t: {e['index']: e for e in ui[t]} for t in ui}
    out, missing = {}, []
    for mid, info in sorted(MapsDat(game).map_index().items()):
        p = os.path.join(game, 'MAP', 'WLD%05d.MAP' % mid)
        if not info.get('flags', 0) & 0x40 or not os.path.exists(p):
            continue
        with open(p, 'rb') as f:
            act = struct.unpack_from('<H', f.read(0x0c), 0x0a)[0]
        cnt = struct.unpack_from('<H', acts[act // 3000], 0)[0]
        off, _ = read_index(acts[act // 3000])[act % 3000]
        cnt = struct.unpack_from('<H', acts[act // 3000], off)[0]
        floors = {}
        for q in range(1, cnt):
            ops = _action_ops(acts, act, q)
            fr = [x[1][0] for x in ops if x[0] == 'FR']
            if len(fr) != 1:
                continue   # 动作 8–10 是把场景和小地图串起来的合集, 楼层用不到
            e = dirs[TSW[fr[0] // 3000]].get(fr[0] % 3000)
            if e is None or not e['frames'] or 'error' in e['frames'][0]:
                missing.append((mid, q, fr[0]))
                continue
            floors[q] = '%s/000.png' % ('ui/' + e['dir'])
        out[mid] = floors
    with open(os.path.join(ext, 'game', 'minimap.json'), 'w', encoding='utf-8') as f:
        json.dump(out, f, ensure_ascii=False, separators=(',', ':'))
    print('小地图 %d 张地图, %d 个楼层; 缺图 %s' % (len(out), sum(len(v) for v in out.values()), missing))


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
