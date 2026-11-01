"""轩辕剑苍之涛 .TEX -> PNG

TEX = [u32 解压大小][u32 压缩大小][LZO1X 数据]
解压后:
  u16 0xFFFF, u16 宽, u16 高, u16 flags (0x0010 不透明 / 0x8010 带透明)
  逐行: u16 行头 = (0x8000 若行首为不透明段) | 行总字节数(含行头)
        [若 0x8000: u16 n + n 个像素]
        重复: u16 0xC000|透明跳过数, u16 n, n 个像素
  像素为 RGB555 (u16)
用法: python tex2png.py <游戏目录> <输出目录>
"""
import os
import struct
import sys
from multiprocessing import Pool

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(__file__))
from lzo1x import load  # noqa: E402


def decode_tex(t):
    magic, w, h, flags = struct.unpack_from('<4H', t, 0)
    assert magic == 0xFFFF, 'bad magic'
    px = np.zeros((h, w), dtype=np.uint16)
    alpha = np.zeros((h, w), dtype=np.uint8)
    p = 8
    for y in range(h):
        head = struct.unpack_from('<H', t, p)[0]
        end = p + (head & 0x3FFF)
        q = p + 2
        x = 0

        def run(q, x):
            n = struct.unpack_from('<H', t, q)[0]
            q += 2
            px[y, x:x + n] = np.frombuffer(t, dtype='<u2', count=n, offset=q)
            alpha[y, x:x + n] = 255
            return q + 2 * n, x + n

        if head & 0x8000:
            q, x = run(q, x)
        while q < end:
            tok = struct.unpack_from('<H', t, q)[0]
            q += 2
            if tok & 0xC000 != 0xC000:
                break
            x += tok & 0x3FFF
            q, x = run(q, x)
        p = end
    a = px.astype(np.uint32)
    rgb = np.dstack([(a >> 10) & 31, (a >> 5) & 31, a & 31]) * 255 // 31
    if flags & 0x8000 or (alpha == 0).any():  # 部分 0x0010 贴图行内也有跳过段
        return Image.fromarray(np.dstack([rgb, alpha]).astype(np.uint8), 'RGBA'), flags
    return Image.fromarray(rgb.astype(np.uint8), 'RGB'), flags


def convert(job):
    src, dst = job
    try:
        _, t = load(src)
        img, flags = decode_tex(t)
        img.save(dst)
        return src, 'ok', flags, img.size
    except Exception as e:  # 记录失败但不中断批处理
        return src, 'err', repr(e), None


def main(game, out):
    jobs = []
    root = os.path.join(game, 'Tex')
    for cat in sorted(os.listdir(root)):
        d = os.path.join(root, cat)
        if not os.path.isdir(d):
            continue
        os.makedirs(os.path.join(out, cat), exist_ok=True)
        for f in sorted(os.listdir(d)):
            if f.upper().endswith('.TEX'):
                jobs.append((os.path.join(d, f), os.path.join(out, cat, f[:-4] + '.png')))
    ok = err = 0
    flags_seen = {}
    with Pool() as pool:
        for src, st, info, size in pool.imap_unordered(convert, jobs, chunksize=8):
            if st == 'ok':
                ok += 1
                flags_seen[hex(info)] = flags_seen.get(hex(info), 0) + 1
            else:
                err += 1
                print('FAIL', src, info)
    print(f'done: {ok} ok, {err} failed; flags: {flags_seen}')


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
