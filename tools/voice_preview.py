"""四川话配音 mod 的工坊封面 (640×360 preview.png): 宣纸底 + 远山 + 一句真实配音的波形 + 标题 + 「川」字印章。
不用原版美术, 全部程序画。make voice-pod 时调用。
用法: python tools/voice_preview.py <配音目录> <输出 png> [sichuan|minnan]   (要 Pillow / numpy / soundfile; CosyVoice 虚拟环境里有)
"""
import glob
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

W, H = 640, 360
FONTS = '/System/Library/AssetsV2/com_apple_MobileAsset_Font8'
INK = (52, 36, 26)
SEAL = (170, 38, 30)


def font(name, size, index=0):
    for p in glob.glob(os.path.join(FONTS, '*', 'AssetData', name)) + glob.glob('/System/Library/Fonts/Supplemental/' + name):
        return ImageFont.truetype(p, size, index=index)
    return ImageFont.truetype('/System/Library/Fonts/Supplemental/Songti.ttc', size)


def paper():
    y = np.linspace(0, 1, H)[:, None]
    x = np.linspace(0, 1, W)[None, :]
    top, bot = np.array([246, 236, 214]), np.array([226, 205, 168])
    t = (y * 0.8 + x * 0.2)[..., None]
    img = top * (1 - t) + bot * t
    rng = np.random.default_rng(7)
    img += rng.normal(0, 3.0, (H, W, 1))                      # 纸纹
    v = ((x - 0.5) ** 2 + (y - 0.5) ** 2)[..., None]          # 暗角
    img *= 1 - 0.35 * v
    return Image.fromarray(np.clip(img, 0, 255).astype(np.uint8))


def mountains(im):
    layer = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    for k, (base, amp, alpha, seed) in enumerate([(250, 55, 40, 1), (285, 45, 60, 2), (320, 30, 85, 3)]):
        rng = np.random.default_rng(seed)
        ph = rng.uniform(0, 6, 4)
        pts = [(0, H)]
        for x in range(0, W + 1, 4):
            u = x / W
            h = sum(math.sin(u * f * math.pi + p) / f for f, p in zip((2, 5, 11, 23), ph))
            pts.append((x, base - amp * (0.6 + 0.4 * h)))
        pts.append((W, H))
        d.polygon(pts, fill=(60, 70, 66, alpha))
    layer = layer.filter(ImageFilter.GaussianBlur(2.5))
    im.paste(layer, (0, 0), layer)


def waveform(im, ogg, box):
    import soundfile as sf
    w, sr = sf.read(ogg, dtype='float32')
    if w.ndim > 1:
        w = w.mean(axis=1)
    x0, y0, x1, y1 = box
    n = (x1 - x0) // 4
    env = np.array([np.abs(c).max() if len(c) else 0 for c in np.array_split(w, n)])
    env = env / (env.max() or 1)
    d = ImageDraw.Draw(im, 'RGBA')
    mid = (y0 + y1) / 2
    for i, e in enumerate(env):
        x = x0 + i * 4 + 1
        fade = min(1, i / 8, (n - 1 - i) / 8)                 # 两头淡出
        hh = max(1.5, e * (y1 - y0) / 2)
        d.rounded_rectangle((x, mid - hh, x + 2, mid + hh), radius=1, fill=SEAL + (int(200 * fade),))


def seal(im, at, ch, size=58):
    s = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(s)
    d.rounded_rectangle((2, 2, size - 3, size - 3), radius=6, fill=SEAL + (235,))
    d.rounded_rectangle((6, 6, size - 7, size - 7), radius=4, outline=(246, 230, 210, 220), width=2)
    f = font('Kaiti.ttc', int(size * 0.62), 2)
    d.text((size / 2, size / 2 + 1), ch, font=f, fill=(250, 238, 222), anchor='mm')
    s = s.rotate(-6, resample=Image.BICUBIC, expand=True)
    im.paste(s, at, s)


LANGS = {'sichuan': ('四川话配音', '川', '全剧对白 · 原词原句 · 川味腔调'),
         'minnan': ('台湾话配音', '台', '全剧对白 · 原词原句 · 闽南腔调')}


def main(voice_dir, out, lang='sichuan'):
    name, ch, tag = LANGS[lang]
    im = paper().convert('RGBA')
    mountains(im)
    oggs = sorted(glob.glob(os.path.join(voice_dir, '*.ogg')), key=os.path.getsize)
    if oggs:
        waveform(im, oggs[len(oggs) * 3 // 4], (70, 178, 570, 238))   # 挑一句偏长的
    d = ImageDraw.Draw(im)
    title = font('Xingkai.ttc', 76)
    d.text((W / 2 + 2, 104), name, font=title, fill=(255, 250, 240, 160), anchor='mm')
    d.text((W / 2, 102), name, font=title, fill=INK, anchor='mm')
    sub = font('Kaiti.ttc', 22, 2)
    d.text((W / 2, 152), tag, font=sub, fill=(96, 70, 48), anchor='mm')
    seal(im, (W // 2 + 196, 50), ch)
    small = font('Kaiti.ttc', 15, 2)
    d.text((W - 16, H - 14), 'CosyVoice3 合成', font=small, fill=(240, 232, 218), anchor='rs')
    d.rectangle((6, 6, W - 7, H - 7), outline=(169, 128, 79), width=2)
    im.convert('RGB').save(out)
    print('封面 →', out)


if __name__ == '__main__':
    main(*sys.argv[1:4])
