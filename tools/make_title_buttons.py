"""按原版标题按钮的样式生成新按钮 (平常 / 悬停 / 按下三态), 用于原版没有的菜单项 (例: 工坊) 或简体字版

用法: python make_title_buttons.py <extracted 目录> [<高清目录>] [名字=文字 ...]
  默认生成全套简体: 开始 / 读取 / 设定 / 离开 / 动画 / 工坊 (用户要求全部统一, 不和原版繁体手写字混用)
输出: <extracted>/ui/custom/title_<名字>_{n,h,p}.png (210×45), 高清目录里同路径 (420×90)

样式全部取自原版 0100_000_标题介面800x600 (按钮 = 底图 000.png 在 (480, 299+45k) 处 210×45 的切图再写上字):
  平常: 字色 (164,123,74), 无描边, 两字左缘 x≈72 / 105
  悬停: 字色 (246,74,8) + 1 像素白边, 两字左缘 x≈68 / 108, 两侧菱形 (x 42–58 / 139–155, 从原版「開始」悬停图复制)
  按下: 黑字 + 1 像素白边, 位置同悬停
  字高约 23 像素 (y 15–37); 原版字形是粗楷 / 魏碑一类的毛笔字, 这里用系统的魏碑-简 (Weibei SC Bold), 1 倍图不做抗锯齿 (原版就是硬边)
  新按钮放在第 k 个位置时底图取 (480, 299+45k), 和原版按钮的取法一样, 拼在一起看不出接缝
"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

SRC = 'ui/all_sys/0100_000_标题介面800x600'
OUT = 'ui/custom'
FONT_CANDIDATES = [
    # 魏碑-简在前: 魏碑-繁没有「开」「读」等简体字形
    '/System/Library/AssetsV2/com_apple_MobileAsset_Font8/c745f84f5eb15b1f594d3769dc86146fccee61ff.asset/AssetData/WeibeiSC-Bold.otf',
    '/System/Library/AssetsV2/com_apple_MobileAsset_Font8/c4f5f063cf47a2009786f645b423c09ea75666b8.asset/AssetData/WeibeiTC-Bold.otf',
]
INK = {'n': (178, 119, 72), 'h': (253, 69, 2), 'p': (0, 0, 0)}   # 原版高清按钮字形像素的中位数 (标清偏黄 172,131,82)
X0 = {'n': (72, 105), 'h': (68, 108), 'p': (68, 108)}
ORDER = ['start', 'load', 'workshop', 'settings', 'quit', 'movie']   # 标题菜单顺序; 第 k 项的底图取第 k 格


def font_path():
    for p in FONT_CANDIDATES:
        if os.path.exists(p):
            return p
    import subprocess
    r = subprocess.run(['fc-list', ':family=Weibei SC', 'file'], capture_output=True, text=True).stdout.split(':')[0].strip()
    if r:
        return r
    sys.exit('找不到魏碑字体 (Weibei TC / SC)')


def glyph(ch, scale, box=(24, 23), bold=0.5):
    """单字遮罩: 按原版字框 (约 24×23) 等比缩放, 再加粗 (原版是很粗的毛笔字); 先在 8 倍上画再缩小, 1 倍不抗锯齿"""
    big = 8
    f = ImageFont.truetype(font_path(), 23 * big)
    bb = f.getbbox(ch)
    im = Image.new('L', (bb[2] - bb[0] + 8 * big, bb[3] - bb[1] + 8 * big), 0)
    ImageDraw.Draw(im).text((4 * big - bb[0], 4 * big - bb[1]), ch, font=f, fill=255)
    im = im.filter(ImageFilter.MaxFilter(int(bold * big) // 2 * 2 + 1))   # 加粗 bold 像素 (按 1 倍算)
    im = im.crop(im.getbbox())
    k = min(box[0] / im.width, box[1] / im.height) * scale
    im = im.resize((max(1, round(im.width * k)), max(1, round(im.height * k))), Image.LANCZOS)
    return im   # 原版字边是抗锯齿的 (边缘逐渐变浅), 不做二值化


def build(ext, scale, text, slot):
    d = os.path.join(ext, SRC)
    bg = Image.open(os.path.join(d, '000.png')).convert('RGB')
    s = bg.width // 800
    tile = bg.crop((480 * s, (299 + 45 * slot) * s, 690 * s, (344 + 45 * slot) * s))
    # 菱形: 原版「開始」悬停图减去它自己的底图, 差异处就是菱形像素
    hover0 = np.asarray(Image.open(os.path.join(d, '006.png')).convert('RGB')).astype(int)
    tile0 = np.asarray(bg.crop((480 * s, 299 * s, 690 * s, 344 * s))).astype(int)
    diamond = np.zeros(hover0.shape[:2], bool)
    for x0, x1 in ((42, 59), (139, 156)):
        part = np.abs(hover0[:, x0 * s:x1 * s] - tile0[:, x0 * s:x1 * s]).sum(2) > 40
        diamond[:, x0 * s:x1 * s] = part
    out = {}
    for st in 'nhp':
        img = np.asarray(tile).copy()
        if st != 'n':
            img[diamond] = hover0[diamond]
        canvas = Image.fromarray(img.astype(np.uint8))
        for i, ch in enumerate(text[:2]):
            m = glyph(ch, scale)
            # 原版字框: x 从 X0 起宽 24, y 15–37; 字在框里居中
            x = X0[st][i] * s + (24 * s - m.width) // 2
            y = 15 * s + (23 * s - m.height) // 2
            if st != 'n':
                halo = m.filter(ImageFilter.MaxFilter(3 if scale == 1 else 5)).filter(ImageFilter.GaussianBlur(0.4 * scale))
                canvas.paste(Image.new('RGB', m.size, (255, 255, 255)), (x, y), halo)
            canvas.paste(Image.new('RGB', m.size, INK[st]), (x, y), m)
        out[st] = canvas
    return out


def main():
    ext = sys.argv[1]
    hd = sys.argv[2] if len(sys.argv) > 2 and '=' not in sys.argv[2] else None
    items = [a.split('=', 1) for a in sys.argv[2:] if '=' in a] or [['start', '开始'], ['load', '读取'], ['settings', '设定'], ['quit', '离开'], ['movie', '动画'], ['workshop', '工坊']]
    for name, text in items:
        slot = ORDER.index(name) if name in ORDER else len(ORDER)
        for root, scale in ((ext, 1), (hd, 2)):
            if not root or not os.path.exists(os.path.join(root, SRC, '000.png')):
                continue
            os.makedirs(os.path.join(root, OUT), exist_ok=True)
            for st, im in build(root, scale, text, slot).items():
                im.save(os.path.join(root, OUT, 'title_%s_%s.png' % (name, st)))
        print('生成 %s「%s」(位置 %d)' % (name, text, slot))


if __name__ == '__main__':
    main()
