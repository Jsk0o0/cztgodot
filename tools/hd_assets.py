"""高清素材: 用 Real-ESRGAN (realesrgan-ncnn-vulkan) 放大运行时用到的全部贴图, 输出到与 extracted/ 平行的目录

用法: python hd_assets.py <extracted 目录> <输出目录> --esrgan <realesrgan-ncnn-vulkan 路径>
      [--model realesr-animevideov3] [--scale 2] [--base <×2 放大缓存目录> --no-glb]
  4K: --base 指向 2K 的放大缓存 (<2K 目录>/_cache/out_realesr-animevideov3_x2), 拿 ×2 结果再放大 ×2 = ×4
      (该模型的 ×4 只有参数没有权重, x4plus-anime 会抹平纹理); 缓存目录名按总倍数 (out_…_x4)
      --no-glb: 不写整份 GLB (发行版只用 tex/ 贴图, 由 hd_textures.py 从缓存生成)
处理范围 (与 Godot 运行时读取的一致):
  图片: ui/**/*.png, effects/sprites/**/*.png  → <输出>/<同路径>
  GLB 内嵌贴图: scenes/*.glb, game/actors/*.glb, effects/models/*.glb, preview/*.glb → <输出>/<同路径>
    (只替换图片, 网格/动画/材质不变; 其他文件不复制, 运行时找不到高清版就用原版)
模型选择: realesr-animevideov3 ×2 —— 对比过 realesrgan-x4plus-anime ×4, 后者把纸张/水墨纹理抹平, 前者保留纹理、边缘变清晰;
  游戏窗口 1200×900 是原版 800×600 的 1.5 倍, ×2 已足够, 体积也只有 ×4 的四分之一。
相同的图片 (按内容哈希) 只放大一次, 结果缓存在 <输出>/_cache/ (路径里不能有「.」, realesrgan 会误判为扩展名), 重复运行只处理新增的图片。
运行时界面按原尺寸排版: Godot 端用 ImageTexture.set_size_override 让高清图报告原尺寸 (见 godot/scripts/game.gd)。
"""
import argparse
import glob
import hashlib
import io
import json
import os
import shutil
import struct
import subprocess
import sys

from PIL import Image

IMAGE_GLOBS = ['ui/**/*.png', 'effects/sprites/**/*.png']
GLB_GLOBS = ['scenes/*.glb', 'game/actors/*.glb', 'effects/models/*.glb', 'preview/*.glb']
MIN_SIDE = 16   # 太小的图 (超分模型处理不了) 用 Lanczos 放大


def read_glb(path):
    d = open(path, 'rb').read()
    jl = struct.unpack_from('<I', d, 12)[0]
    g = json.loads(d[20:20 + jl])
    p = 20 + jl
    binl = struct.unpack_from('<I', d, p)[0]
    return g, d[p + 8:p + 8 + binl]


def glb_images(path):
    g, b = read_glb(path)
    out = []
    for im in g.get('images', []):
        bv = g['bufferViews'][im['bufferView']]
        o = bv.get('byteOffset', 0)
        out.append(b[o:o + bv['byteLength']])
    return out


def encode(path, jpeg_ok):
    """放大结果 → (字节, mime): 不透明且允许时存 JPEG 质量 92 (约为 PNG 的 1/4), 否则存压缩过的 PNG"""
    im = Image.open(path)
    bio = io.BytesIO()
    if jpeg_ok and im.mode == 'RGB':
        im.save(bio, 'JPEG', quality=92)
        return bio.getvalue(), 'image/jpeg'
    im.save(bio, 'PNG', optimize=True)
    return bio.getvalue(), 'image/png'


def write_glb(src, dst, new_images):
    """把 src 的图片依次替换为 new_images [(字节, mime)], 重排二进制块后写到 dst"""
    g, b = read_glb(src)
    repl = {}
    for k, (data, mime) in enumerate(new_images):
        g['images'][k]['mimeType'] = mime
        repl[g['images'][k]['bufferView']] = data
    chunks, off = [], 0
    for i, bv in enumerate(g['bufferViews']):
        o = bv.get('byteOffset', 0)
        data = repl.get(i, b[o:o + bv['byteLength']])
        pad = (-off) % 4
        chunks.append(b'\0' * pad)
        off += pad
        bv['byteOffset'] = off
        bv['byteLength'] = len(data)
        chunks.append(data)
        off += len(data)
    blob = b''.join(chunks)
    blob += b'\0' * ((-len(blob)) % 4)
    g['buffers'][0]['byteLength'] = len(blob)
    js = json.dumps(g, ensure_ascii=False, separators=(',', ':')).encode()
    js += b' ' * ((-len(js)) % 4)
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    with open(dst, 'wb') as f:
        f.write(struct.pack('<III', 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(blob)))
        f.write(struct.pack('<I4s', len(js), b'JSON') + js)
        f.write(struct.pack('<I4s', len(blob), b'BIN\0') + blob)


def key(data):
    return hashlib.sha1(data).hexdigest()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('src')
    ap.add_argument('out')
    ap.add_argument('--esrgan', required=True)
    ap.add_argument('--model', default='realesr-animevideov3')
    ap.add_argument('--scale', type=int, default=2)
    ap.add_argument('--base', help='以这个目录里已放大的结果为输入再放大 (4K = ×2 两遍)')
    ap.add_argument('--no-glb', action='store_true', help='不写整份 GLB')
    ap.add_argument('--keep-cache', action='store_true', help='保留放大结果缓存 (约 2.4 GB), 下次只处理新增图片')
    a = ap.parse_args()
    a.out = os.path.abspath(a.out)   # realesrgan 在它自己的目录下运行 (要读 models/), 路径必须是绝对路径
    cache_in = os.path.join(a.out, '_cache', 'in')
    total = a.scale * (2 if a.base else 1)   # 总倍数 (--base 的输入已是 ×2)
    cache_out = os.path.join(a.out, '_cache', 'out_%s_x%d' % (a.model, total))
    os.makedirs(cache_in, exist_ok=True)
    os.makedirs(cache_out, exist_ok=True)

    images = sorted(f for g in IMAGE_GLOBS for f in glob.glob(os.path.join(a.src, g), recursive=True))
    # 发行版 (--no-glb) 不含 preview/ (只给开发工具用)
    glbs = sorted(f for g in GLB_GLOBS if not (a.no_glb and g.startswith('preview/')) for f in glob.glob(os.path.join(a.src, g)))
    todo = {}
    for f in images:
        data = open(f, 'rb').read()
        todo.setdefault(key(data), data)
    glb_keys = {}
    for f in glbs:
        ks = []
        for data in glb_images(f):
            k = key(data)
            todo.setdefault(k, data)
            ks.append(k)
        glb_keys[f] = ks
    # 1. 待放大的图片 (统一转成 RGB / RGBA PNG); 太小的图直接 Lanczos
    pending = 0
    for k, data in todo.items():
        if os.path.exists(os.path.join(cache_out, k + '.png')):
            continue
        im = Image.open(io.BytesIO(data))
        alpha = im.mode in ('RGBA', 'LA') or 'transparency' in im.info
        im = im.convert('RGBA' if alpha else 'RGB')
        if min(im.size) < MIN_SIDE:
            im.resize((im.width * total, im.height * total), Image.LANCZOS).save(os.path.join(cache_out, k + '.png'))
            continue
        if a.base:
            b = os.path.join(a.base, k + '.png')
            if not os.path.exists(b):
                sys.exit('--base 里没有 %s (先跑 2K: make hd)' % k)
            shutil.copy(b, os.path.join(cache_in, k + '.png'))
        else:
            im.save(os.path.join(cache_in, k + '.png'))
        pending += 1
    print('图片 %d 张, GLB %d 个, 不重复贴图 %d 张, 需要放大 %d 张' % (len(images), len(glbs), len(todo), pending), flush=True)
    # 2. 超分 (文件夹模式, GPU)
    if pending:
        r = subprocess.run([a.esrgan, '-i', cache_in, '-o', cache_out, '-n', a.model, '-s', str(a.scale), '-f', 'png'],
                           cwd=os.path.dirname(os.path.abspath(a.esrgan)), stdout=subprocess.DEVNULL,
                           stderr=subprocess.PIPE, text=True)
        if r.returncode != 0:
            sys.exit('realesrgan 失败: ' + r.stderr[-2000:])
        for f in os.listdir(cache_in):
            os.remove(os.path.join(cache_in, f))
    missing = [k for k in todo if not os.path.exists(os.path.join(cache_out, k + '.png'))]
    if missing:
        sys.exit('有 %d 张没有放大结果' % len(missing))

    def result(k):
        return os.path.join(cache_out, k + '.png')
    # 3. 写出: 图片按原路径, GLB 替换内嵌贴图
    # 界面 / 精灵图按 .png 路径引用, 保持 PNG; GLB 内的不透明贴图改存 JPEG
    enc = {}
    for f in images:
        dst = os.path.join(a.out, os.path.relpath(f, a.src))
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        with open(dst, 'wb') as fp:
            fp.write(encode(result(key(open(f, 'rb').read())), False)[0])
    for f in [] if a.no_glb else glbs:
        dst = os.path.join(a.out, os.path.relpath(f, a.src))
        if os.path.exists(dst) and os.path.getmtime(dst) > os.path.getmtime(f):
            continue
        imgs = []
        for k in glb_keys[f]:
            if k not in enc:
                enc[k] = encode(result(k), True)
            imgs.append(enc[k])
        write_glb(f, dst, imgs)
    if not a.keep_cache:
        shutil.rmtree(os.path.join(a.out, '_cache'))
    print('完成 → %s' % a.out)


if __name__ == '__main__':
    main()
