"""高清贴图单独存放 (发行版 2K / 4K 包只放贴图, 不重复存网格 / 动画)

用法: python hd_textures.py <extracted 目录> <高清目录> [放大倍数, 默认 2; 4K 填 4]
输出 (都在高清目录下):
  tex/<sha1>.jpg|png      放大后的贴图; sha1 是原版 (标清) 贴图字节的 SHA-1, 同一张贴图不论被多少模型用只存一份
  <模型路径>.tex.json      {"tex": [第 k 张贴图对应的文件名 或 null]}, 和标清 GLB 的 images 顺序一一对应
运行时 (godot/scripts/hd_textures.gd): 读标清 GLB, 解析到第 k 张贴图时换成 tex/ 里的高清图。
高清图来源: hd_assets.py 生成的完整高清 GLB 里同位置的图片 (比标清 GLB 新时才用); 否则从放大缓存 _cache 重新编码 (同 hd_assets.encode)
"""
import glob
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))   # make 用 python -I 运行, 不会自动加脚本目录
from hd_assets import GLB_GLOBS, encode, glb_images, key

# preview/ 只给开发工具用, 不进发行版
GLOBS = [g for g in GLB_GLOBS if not g.startswith('preview/')]
EXT = {'image/jpeg': '.jpg', 'image/png': '.png'}


def sniff(data):
    return '.jpg' if data[:3] == b'\xff\xd8\xff' else '.png'


def main(src, hd, scale=2):
    cache = os.path.join(hd, '_cache', 'out_realesr-animevideov3_x%d' % scale)
    tex_dir = os.path.join(hd, 'tex')
    os.makedirs(tex_dir, exist_ok=True)
    have = {os.path.splitext(f)[0]: f for f in os.listdir(tex_dir)}
    n_glb = n_new = n_missing = 0
    for f in sorted(p for g in GLOBS for p in glob.glob(os.path.join(src, g))):
        rel = os.path.relpath(f, src)
        sd = glb_images(f)
        if not sd:
            continue
        old = os.path.join(hd, rel)
        fresh = os.path.exists(old) and os.path.getmtime(old) >= os.path.getmtime(f)
        hd_imgs = glb_images(old) if fresh else []
        if len(hd_imgs) != len(sd):
            hd_imgs = []
        names = []
        for i, data in enumerate(sd):
            k = key(data)
            if k not in have:
                if hd_imgs and hd_imgs[i] != data:
                    out, ext = hd_imgs[i], sniff(hd_imgs[i])
                elif os.path.exists(os.path.join(cache, k + '.png')):
                    out, mime = encode(os.path.join(cache, k + '.png'), True)
                    ext = EXT[mime]
                else:
                    names.append(None)   # 没放大过 (太小或新增), 用标清
                    n_missing += 1
                    continue
                open(os.path.join(tex_dir, k + ext), 'wb').write(out)
                have[k] = k + ext
                n_new += 1
            names.append(have[k])
        idx = os.path.join(hd, rel + '.tex.json')
        os.makedirs(os.path.dirname(idx), exist_ok=True)
        json.dump({'tex': names}, open(idx, 'w'), separators=(',', ':'))
        n_glb += 1
    size = sum(os.path.getsize(os.path.join(tex_dir, v)) for v in have.values())
    print('模型 %d 个, 贴图 %d 张 (新写 %d, %.0f MB), 没有高清版 %d 处' % (n_glb, len(have), n_new, size / 1048576, n_missing))


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2], *map(int, sys.argv[3:4]))
