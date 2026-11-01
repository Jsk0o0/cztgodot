"""轩辕剑苍之涛 ACT/*.tsw (2D 界面 / 立绘 / 图标图库) -> PNG

TSW 文件:
  0x00  24 字节 (全 0) + u32
  0x1c  条目表, 每条 44 字节: name[20] (Big5, 0 结尾), u32 大小, u32 文件偏移, u32 条目号 (0 = 空位)
        表一直延续到最小的条目数据偏移处
条目数据 (偏移为条目起点):
  0x00  u32 数据长度, u32 ?, u16 ?, u16 ?
  0x0c  帧表, 每帧 36 字节: u32 帧数据偏移, u32 压缩大小, u32 解压大小, s16 ?, s16 ?, 4×u32 ?, u16 宽, u16 高
        帧数 = (第一帧数据偏移 - 12) / 36
  每帧数据 = LZO1X 压缩的 TEX 图像 (解压后 FFFF, 宽, 高, flags + 逐行 RLE, RGB555; 见 tex2png.py)
依据: 标题画面 (exe 0x470660) 用 ACT 9003 的背景、按钮; 「000_標題介面800x600」解出即原版标题图。
用法: python tsw2png.py <游戏目录> <输出目录> [文件名 ...]   (默认全部 6 个 .tsw)
输出: <输出目录>/<tsw 名>/<条目号>_<名字>/<帧号>.png, 以及 index.json
"""
import json
import os
import re
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lzo1x import lzo1x  # noqa: E402
from tex2png import decode_tex  # noqa: E402

try:
    from opencc import OpenCC
    _cc = OpenCC('t2s').convert
except ImportError:
    _cc = lambda s: s  # noqa: E731

FILES = ['all_sys.tsw', 'all_char.tsw', 'all_item.tsw', 'all_magic.tsw', 'all_map1.tsw', 'all_map2.tsw']


def read_table(f):
    f.seek(0)
    head = f.read(0x100000)
    recs, q, data_start = [], 0x1C, None
    while q + 44 <= len(head) and (data_start is None or q < data_start):
        size, off, idx = struct.unpack_from('<3I', head, q + 20)
        if idx:
            name = head[q:q + 20].split(b'\0')[0].decode('big5', 'replace')
            recs.append({'index': idx, 'name': name, 'size': size, 'offset': off})
            data_start = off if data_start is None else min(data_start, off)
        q += 44
    return recs


def frames(blob):
    first = struct.unpack_from('<I', blob, 12)[0]
    n = (first - 12) // 36
    out = []
    for k in range(n):
        off, csize, usize = struct.unpack_from('<3I', blob, 12 + k * 36)
        w, h = struct.unpack_from('<2H', blob, 12 + k * 36 + 32)
        out.append((off, csize, usize, w, h))
    return out


def _safe_frames(blob):
    try:
        return frames(blob)
    except struct.error:
        return []


def decode_frame(blob, off, csize):
    return decode_tex(lzo1x(blob[off:off + csize + 8]))[0]


def safe(s):
    return re.sub(r'[\\/:*?"<>|\s]+', '_', s).strip('_')


def main(game, out, names=None):
    index = {}
    for fn in names or FILES:
        path = os.path.join(game, 'ACT', fn)
        if not os.path.exists(path):
            continue
        stem = os.path.splitext(fn)[0]
        items, ok, bad = [], 0, 0
        with open(path, 'rb') as f:
            for r in read_table(f):
                f.seek(r['offset'])
                blob = f.read(r['size'])
                # 目录表的大小可能偏小 (all_map1 第 2/26/35 条、all_sys 第 149 条), 以帧表为准
                need = max([o + c + 8 for o, c, *_ in _safe_frames(blob)], default=0)
                if need > len(blob):
                    f.seek(r['offset'])
                    blob = f.read(need)
                d = os.path.join(out, stem, f'{r["index"]:04d}_{safe(_cc(r["name"]))}')
                os.makedirs(d, exist_ok=True)
                fr = []
                try:
                    lst = frames(blob)
                except struct.error:
                    lst = []
                for k, (off, csize, usize, w, h) in enumerate(lst):
                    try:
                        im = decode_frame(blob, off, csize)
                        im.save(os.path.join(d, f'{k:03d}.png'))
                        fr.append({'frame': k, 'w': im.size[0], 'h': im.size[1]})
                        ok += 1
                    except Exception as e:  # 记录失败但不中断
                        fr.append({'frame': k, 'error': repr(e)[:80]})
                        bad += 1
                items.append({'index': r['index'], 'name': r['name'], 'name_simplified': _cc(r['name']),
                              'dir': os.path.relpath(d, out), 'frames': fr})
        index[stem] = items
        print(fn, len(items), 'entries,', ok, 'frames ok,', bad, 'failed')
    with open(os.path.join(out, 'index.json'), 'w') as f:
        json.dump(index, f, ensure_ascii=False, indent=1)


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2], sys.argv[3:] or None)
