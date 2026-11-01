"""标题按钮的字形遮罩 (随游戏分发, 不含原版像素): 发行版在玩家机器上把遮罩贴到原版底图上合成按钮 (godot/scripts/extract/title_buttons.gd)
用法: python make_title_masks.py <输出目录>   (默认 godot/data/title_glyphs)
输出: masks.bin —— 依次 (u32 字的码位, u8 倍率, u16 宽, u16 高, 宽×高 字形遮罩, 宽×高 光晕遮罩); 小端
      (不用 PNG: 放在 res:// 里会被 Godot 导入成纹理, 导出后读不到原始像素)
字形 / 位置 / 光晕和 make_title_buttons.py 完全相同 (直接调用它的 glyph())
"""
import struct
import os
import sys

from PIL import ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_title_buttons import glyph  # noqa: E402

CHARS = '开始读取设定离开动画工坊'


def main(out):
    os.makedirs(out, exist_ok=True)
    buf = bytearray()
    n = 0
    for ch in sorted(set(CHARS)):
        for scale in (1, 2, 4):
            m = glyph(ch, scale)
            halo = m.filter(ImageFilter.MaxFilter(3 if scale == 1 else 5)).filter(ImageFilter.GaussianBlur(0.4 * scale))
            buf += struct.pack('<IBHH', ord(ch), scale, m.width, m.height) + m.tobytes() + halo.tobytes()
            n += 1
    open(os.path.join(out, 'masks.bin'), 'wb').write(buf)
    print('字形遮罩 %d 个 → %s' % (n, out))


if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), '..', 'godot', 'data', 'title_glyphs'))
