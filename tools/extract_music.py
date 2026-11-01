"""轩辕剑苍之涛 音乐表: 曲目 ID → Music/ 文件名, 以及每张地图的默认音乐

MAPS.DAT 为 MZ 风格头: 偏移 8 处 u16 × 16 = 数据池起点; 池开头是 20 个 u32 段偏移。
  段 4 (池+0x10, 运行时 [0x4e8828]): 文件名列表, 每个以 %Q 结尾, 第 k 个即曲目 ID k (0 = 无音乐), ffff 结束
  段 3 (池+0x0c, 运行时 [0x4e8824]): 地图默认音乐, 每条 5×u16 = (地图 ID, 曲目 A, A 播放次数, 曲目 B, B 播放次数),
        次数 0 = 无限循环, n = 播 n 次后切到另一条; 事件指令 0x0091 可改写, 随存档保存
依据: exe 0x404b1c read_maps_music / 0x46c27f 逐个跳过 %Q 取名; 事件指令 0x0090 play_music 用同一套 ID。
用法: python extract_music.py <游戏目录> <输出.json>
"""
import json
import os
import struct
import sys


def read_music(game):
    b = open(os.path.join(game, 'MAPS.DAT'), 'rb').read()
    pool = b[struct.unpack_from('<H', b, 8)[0] * 16:]
    offs = struct.unpack_from('<20I', pool, 0)
    names, p = [], offs[4]
    while pool[p:p + 2] != b'\xff\xff':
        e = pool.index(b'%Q', p)
        names.append(pool[p:e].decode('latin1'))
        p = e + 2
    recs, p = [], offs[3]
    while struct.unpack_from('<H', pool, p)[0] != 0xFFFF:
        recs.append(struct.unpack_from('<5H', pool, p))
        p += 10
    return names, recs


def main(game, out):
    names, recs = read_music(game)
    have = {f.lower() for f in os.listdir(os.path.join(game, 'Music'))}
    maps_json = os.path.join(os.path.dirname(os.path.abspath(out)), 'maps.json')
    mapname = {m['map_id']: m.get('name_simplified') for m in json.load(open(maps_json))} if os.path.exists(maps_json) else {}
    tracks = {i: {'file': n, 'exists': n.lower() in have} for i, n in enumerate(names) if n}
    maps = [{'map_id': k, 'map': mapname.get(k), 'track_a': a, 'file_a': names[a] if a < len(names) else None,
             'count_a': ca, 'track_b': tb, 'file_b': names[tb] if tb < len(names) else None, 'count_b': cb}
            for k, a, ca, tb, cb in recs]
    json.dump({'tracks': tracks, 'map_default_music': maps}, open(out, 'w'), ensure_ascii=False, indent=1)
    print(len(tracks), 'tracks,', sum(not t['exists'] for t in tracks.values()), 'missing;', len(maps), 'maps')


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
