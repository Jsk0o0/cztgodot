"""标题按钮 (发行版用): 用随包的字形遮罩 godot/data/title_glyphs/masks.bin 合成, 不需要魏碑字体 (Windows 没有)
结果和 make_title_buttons.py 相同 (同一底图上逐像素一致); 遮罩由 make_title_masks.py 从魏碑字体生成
用法: python title_buttons_masks.py <extracted 或高清目录> [<masks.bin>]
"""
import os
import struct
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_title_buttons import INK, ORDER, OUT, SRC, X0  # noqa: E402

ITEMS = [['start', '开始'], ['load', '读取'], ['settings', '设定'], ['quit', '离开'], ['movie', '动画'], ['workshop', '工坊']]


def read_masks(path):
    b = open(path, 'rb').read()
    out, p = {}, 0
    while p + 9 <= len(b):
        cp, sc, w, h = struct.unpack_from('<IBHH', b, p)
        p += 9
        m = Image.frombytes('L', (w, h), b[p:p + w * h])
        halo = Image.frombytes('L', (w, h), b[p + w * h:p + 2 * w * h])
        out[(chr(cp), sc)] = (m, halo)
        p += 2 * w * h
    return out


def build(root, masks):
    d = os.path.join(root, SRC)
    bg = Image.open(os.path.join(d, '000.png')).convert('RGB')
    s = bg.width // 800
    hover0 = np.asarray(Image.open(os.path.join(d, '006.png')).convert('RGB')).astype(int)
    tile0 = np.asarray(bg.crop((480 * s, 299 * s, 690 * s, 344 * s))).astype(int)
    diamond = np.zeros(hover0.shape[:2], bool)
    for x0, x1 in ((42, 59), (139, 156)):
        diamond[:, x0 * s:x1 * s] = np.abs(hover0[:, x0 * s:x1 * s] - tile0[:, x0 * s:x1 * s]).sum(2) > 40
    os.makedirs(os.path.join(root, OUT), exist_ok=True)
    for name, text in ITEMS:
        slot = ORDER.index(name)
        tile = bg.crop((480 * s, (299 + 45 * slot) * s, 690 * s, (344 + 45 * slot) * s))
        for st in 'nhp':
            img = np.asarray(tile).copy()
            if st != 'n':
                img[diamond] = hover0[diamond]
            canvas = Image.fromarray(img.astype(np.uint8))
            for i, ch in enumerate(text[:2]):
                m, halo = masks[(ch, s)]
                x = X0[st][i] * s + (24 * s - m.width) // 2
                y = 15 * s + (23 * s - m.height) // 2
                if st != 'n':
                    canvas.paste(Image.new('RGB', m.size, (255, 255, 255)), (x, y), halo)
                canvas.paste(Image.new('RGB', m.size, INK[st]), (x, y), m)
            canvas.save(os.path.join(root, OUT, 'title_%s_%s.png' % (name, st)))


def main(root, masks_path=None):
    masks_path = masks_path or os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'godot', 'data', 'title_glyphs', 'masks.bin')
    build(root, read_masks(masks_path))
    print('标题按钮 → %s' % os.path.join(root, OUT))


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else None)
