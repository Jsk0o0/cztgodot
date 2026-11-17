"""导出按 ACT 换贴图表 (MAPS.DAT 第 18 段) → godot/data/tex_swaps.json

用法: python export_tex_swaps.py <游戏目录> <extracted 目录> <输出 json>
原版 (逆向确认):
  MAPS.DAT 池偏移表第 18 项 (0x404138 → [0x4e884c]): 每条 0x14 字节 = u16 ACT, 再 3 组 (材质格, 贴图 ACT, QQ), ACT = 0xffff 结束。
  0x40518e(ACT, 结构): 查到就把 3 组写进模型的换贴图结构 (+2.. 材质格, +8.. ACT, +0xe.. QQ, +0 置 1)。
  战斗单位建好后按自己的 ACT 查 (0x431182 / 0x43152a), 地图角色同理 (0x408350 / 0x408838)。
  绘制时 (战斗 0x43273e, 地图 0x46b2b9) 每组 ACT ≠ 0 就取该 ACT 该 QQ 当前帧的图换掉模型材质表第「材质格」格的贴图;
  表情 (事件 0x78) 用的是同一个结构。
  例: 晋兵甲 / 乙 / 队长 1007–1009 第 4 / 5 格换成 ACT 10801 QQ 0–5 (红 / 青绿 / 另一套配色), 以前一律显示模型自带的红色那套。
贴图帧取自 faces.json (all_sys.act 10001+ 已解成图片); 引用别的 ACT 文件 (161, 16007) 的两条取不到图片帧, 跳过。
输出: {ACT: [[[第 0 组材质名, 第 1 组材质名, …], 图片相对 extracted 的路径], …]}; 材质名同 ply2gltf (贴图组名或 tex<贴图号>), 该组没有这一格时为 ""
"""
import json
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mapsdat import MapsDat  # noqa: E402
from ply import parse  # noqa: E402


def table(game):
    s = MapsDat(game).seg(18)
    out = []
    p = 0
    while p + 0x14 <= len(s):
        r = struct.unpack_from('<10H', s, p)
        if r[0] == 0xFFFF:
            break
        out.append((r[0], [r[1 + 3 * k:4 + 3 * k] for k in range(3)]))
        p += 0x14
    return out


def main(game, ext, dst):
    faces = json.load(open(os.path.join(ext, 'game', 'faces.json'), encoding='utf-8'))
    cache = {}
    out = {}
    skipped = []
    for act, ents in table(game):
        p = os.path.join(ext, 'game', 'actors', 'act_%d.json' % act)
        if not os.path.exists(p):
            continue
        groups = json.load(open(p, encoding='utf-8'))['groups']
        rows = []
        for slot, sa, q in ents:
            if sa == 0:
                continue
            e = faces.get(str(sa), {}).get(str(q))
            if not e or not e['frames']:
                skipped.append((act, slot, sa, q))
                continue
            names = []
            for g in groups:
                f = g['files'][0]
                if f not in cache:
                    try:
                        cache[f] = parse(os.path.join(game, 'Model', f + '.PLY')).groups
                    except Exception:  # noqa: BLE001
                        cache[f] = []
                grs = cache[f]
                names.append((grs[slot].name or 'tex%d' % grs[slot].tex) if slot < len(grs) and grs[slot].tex >= 0 else '')
            rows.append([names, e['frames'][0][0]])
        if rows:
            out[str(act)] = rows
    os.makedirs(os.path.dirname(os.path.abspath(dst)), exist_ok=True)
    json.dump(out, open(dst, 'w', encoding='utf-8'), ensure_ascii=False, indent=0)
    print('换贴图: %d 个 ACT; 跳过 (取不到图片帧) %s' % (len(out), skipped))


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2], sys.argv[3])
