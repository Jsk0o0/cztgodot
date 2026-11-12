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

import numpy as np
from PIL import Image

IMAGE_GLOBS = ['ui/**/*.png', 'effects/sprites/**/*.png']
GLB_GLOBS = ['scenes/*.glb', 'game/actors/*.glb', 'effects/models/*.glb', 'preview/*.glb']
BAD_DIFF = 25    # bad_result 的阈值 (见函数说明)
BATCH = 16       # 发行版每批张数: 每批重开一次 realesrgan
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


PROGRESS = None   # 发行版提取程序 (extractor.py --hd) 设成进度回调: PROGRESS(已完成, 总数, 名称)


def _premul(im):
    """按透明度预乘的 RGB (float32, H×W×3)"""
    a = np.asarray(im.convert('RGBA'), np.float32)
    return a[..., :3] * a[..., 3:] / 255


def bad_result(src_im, out_path):
    """放大结果是不是坏的 (全黑、花屏、别的图的残留、尺寸不对、写了一半)。结果缩回原尺寸后和原图比 (按透明度预乘):
    平均每通道差 > BAD_DIFF; 或原图有起伏 (标准差 ≥ 4) 而结果几乎是平的 (标准差不到原图 0.3 倍) 或和原图不相关 (相关系数 < 0.6)。
    阈值依据 (mac 上正常结果 1026 张: 场景 / 角色贴图 + 界面 + 特效): 平均差中位 3.4、最大 16.4 (噪点最小 35.4);
    相关系数最小 0.833; 标准差比最小 0.585。只看平均差会漏掉暗图变全黑 (2026-11-08 假程序测试漏了 4 张)"""
    try:
        o = Image.open(out_path)
        o.load()
    except Exception:  # noqa: BLE001  写了一半 / 损坏
        return True
    f = o.width // max(src_im.width, 1)
    if f < 2 or o.size != (src_im.width * f, src_im.height * f):   # 尺寸不对
        return True
    a = _premul(src_im).ravel()
    b = _premul(o.convert('RGBA').resize(src_im.size, Image.BOX)).ravel()
    if np.abs(a - b).mean() > BAD_DIFF:
        return True
    sa, sb = a.std(), b.std()
    if sa < 4:
        return False
    return sb < 0.3 * sa or np.corrcoef(a, b)[0, 1] < 0.6


def ref_image(a, k, data):
    """检查放大结果时拿来比的图: 4K (--base) 比它的输入 (2K 结果), 只验这一遍 ×2; 否则比原图。
    阈值是按 ×2 一遍对原图定的; 4K 两遍放大后直接比原图会误判 (2026-11-09 用户 Windows 4K: 草地 / 竹席这类高对比贴图
    平均差 25~26、近白贴图和 70×70 小图相关系数 0.55~0.58, 结果其实正常, DirectML 和 CPU 都被判坏 → 4K 失败;
    同样 4 张比 2K 输入: 平均差 ≤ 19、相关系数 ≥ 0.85)"""
    if a.base:
        b = os.path.join(a.base, k + '.png')
        if os.path.exists(b):
            im = Image.open(b)
            im.load()
            return im
    return Image.open(io.BytesIO(data))


def gpu_score(name):
    """显卡优先级: 独显 3 > 核显 1 > 软件渲染 0。笔记本屏幕通常由核显输出, 拿核显放大会把整个桌面卡死
    (2026-11-07 用户 Windows: 0 号 Intel Iris Xe、1 号 RTX 3070 Ti, realesrgan 默认用 0 号 → 无响应、全黑结果)"""
    n = name.lower()
    if any(x in n for x in ('llvmpipe', 'swiftshader', 'microsoft basic')):
        return 0
    if any(x in n for x in ('nvidia', 'geforce', 'quadro', 'rtx', 'gtx', ' arc')):
        return 3
    if 'radeon' in n or 'amd' in n:
        return 1 if 'radeon(tm) graphics' in n or n.endswith('radeon graphics') else 3   # 「Radeon(TM) Graphics」是 APU 核显
    return 1   # Intel UHD / Iris 等核显, 以及不认识的


def pick_gpu(esrgan):
    """跑一张小图, 从 realesrgan 启动时打印的 [序号 名字] 里挑显卡; 返回 (序号 或 None, 名字, 优先级)"""
    import re
    import tempfile
    kw = {'creationflags': 0x08000000} if os.name == 'nt' else {}
    with tempfile.TemporaryDirectory() as t:
        Image.new('RGB', (32, 32), (128, 64, 32)).save(os.path.join(t, 'probe.png'))
        r = subprocess.run([esrgan, '-i', os.path.join(t, 'probe.png'), '-o', os.path.join(t, 'out.png'), '-n', 'realesr-animevideov3', '-s', '2'],
                           cwd=os.path.dirname(os.path.abspath(esrgan)), capture_output=True, text=True, errors='replace', timeout=120, **kw)
    gpus = {}
    for line in r.stderr.splitlines():
        m = re.match(r'\[(\d+) (.+?)\]\s', line)
        if m:
            gpus[int(m.group(1))] = m.group(2)
    if not gpus:
        return None, '', 1
    best = max(gpus, key=lambda i: (gpu_score(gpus[i]), -i))
    print('显卡: %s → 用 %d 号 %s' % ('; '.join('%d %s' % kv for kv in sorted(gpus.items())), best, gpus[best]), file=sys.stderr, flush=True)
    return (best if len(gpus) > 1 else None), gpus[best], gpu_score(gpus[best])


def _esrgan(a, cache_in, cache_out, gentle, done, pending):
    """超分一个文件夹 (GPU); 跑的时候数输出目录里的文件报进度"""
    import threading
    import time
    # Windows: 不弹窗口 + 低于正常优先级
    kw = {'creationflags': 0x08000000 | 0x00004000} if os.name == 'nt' else {}   # CREATE_NO_WINDOW | BELOW_NORMAL_PRIORITY_CLASS
    before = len(os.listdir(cache_out))
    p = subprocess.Popen([a.esrgan, '-i', cache_in, '-o', cache_out, '-n', a.model, '-s', str(a.scale), '-f', 'png'] + gentle,
                         cwd=os.path.dirname(os.path.abspath(a.esrgan)), stdout=subprocess.DEVNULL,
                         stderr=subprocess.PIPE, text=True, errors='replace', **kw)
    err = []

    def pump():   # stderr 要读掉, 否则写满会卡住; 除了刷屏的百分比行, 实时写进日志 (显卡信息、报错)
        for line in p.stderr:
            err.append(line)
            if not line.strip().endswith('%'):
                print('[realesrgan]', line.rstrip(), file=sys.stderr, flush=True)
    t = threading.Thread(target=pump, daemon=True)
    t.start()
    while p.poll() is None:
        if PROGRESS:
            PROGRESS(done + len(os.listdir(cache_out)) - before, pending, '放大中')
        time.sleep(1)
    t.join(5)
    return p.returncode, ''.join(x for x in err if not x.strip().endswith('%'))[-2000:]


ONNX_TILE, ONNX_PAD = 256, 10   # 分块推理 (4K 那遍输入可到 2048, 整张推理显存不够); 块边多算 10 像素再裁掉, 和整张推理差 < 0.01/255


def onnx_session(model, cpu=False):
    """onnxruntime 会话: DirectML (D3D12, 选高性能显卡) → 不行再用 CPU。返回 (会话, 说明)"""
    import onnxruntime as ort
    if not cpu and 'DmlExecutionProvider' in ort.get_available_providers():
        for opt in ({'performance_preference': 'high_performance'}, {}):
            try:
                return ort.InferenceSession(model, providers=[('DmlExecutionProvider', opt), 'CPUExecutionProvider']), 'DirectML'
            except Exception as e:  # noqa: BLE001
                print('DirectML 选项 %s 不可用: %s' % (opt, e), file=sys.stderr, flush=True)
    return ort.InferenceSession(model, providers=['CPUExecutionProvider']), 'CPU'


def onnx_upscale(sess, im):
    """×2 (realesr-animevideov3 x2 的 ONNX 版, tools/ncnn2onnx.py 从 ncnn 权重转): RGB 走模型, 透明度双三次放大
    (同 realesrgan-ncnn-vulkan)。2026-11-08 和 mac 上 realesrgan 对比 38 张: RGB 平均差 ≤ 0.7/255"""
    rgba = im.mode == 'RGBA'
    x = np.asarray(im.convert('RGB'), np.float32) / 255
    h, w, _ = x.shape
    out = np.zeros((h * 2, w * 2, 3), np.float32)
    T, P = ONNX_TILE, ONNX_PAD
    for y in range(0, h, T):
        for x0 in range(0, w, T):
            ya, xa, yb, xb = max(y - P, 0), max(x0 - P, 0), min(y + T + P, h), min(x0 + T + P, w)
            r = sess.run(None, {'data': np.ascontiguousarray(x[ya:yb, xa:xb].transpose(2, 0, 1)[None])})[0][0].transpose(1, 2, 0)
            th, tw = min(T, h - y), min(T, w - x0)
            out[y * 2:(y + th) * 2, x0 * 2:(x0 + tw) * 2] = r[(y - ya) * 2:(y - ya + th) * 2, (x0 - xa) * 2:(x0 - xa + tw) * 2]
    res = Image.fromarray(np.clip(out * 255 + 0.5, 0, 255).astype(np.uint8))
    if rgba:
        res.putalpha(im.getchannel('A').resize(res.size, Image.BICUBIC))
    return res


def _upscale_onnx(a, cache_in, cache_out, todo, pending):
    """Windows 发行版: onnxruntime DirectML 逐张放大, 每张马上检查, 坏的用 CPU 重做一次
    (2026-11-08 用户笔记本 RTX 3070 Ti: Vulkan 计算每批都 VK_ERROR_DEVICE_LOST、结果花屏; DirectML 300 张全对、桌面不卡)"""
    sess, how = onnx_session(a.onnx)
    print('放大: %s (%s)' % (how, a.onnx), file=sys.stderr, flush=True)
    cpu = sess if how == 'CPU' else None
    fails = []
    queued = sorted(f[:-4] for f in os.listdir(cache_in) if f.endswith('.png'))
    for n, k in enumerate(queued):
        if PROGRESS:
            PROGRESS(n, pending, '放大中 (%s)' % how)
        im = Image.open(os.path.join(cache_in, k + '.png'))
        im.load()
        r = os.path.join(cache_out, k + '.png')
        src = ref_image(a, k, todo[k])
        for attempt in range(2):
            try:
                onnx_upscale(sess if attempt == 0 else cpu, im).save(r)
            except Exception as e:  # noqa: BLE001
                print('%s 放大出错: %s' % (k, e), file=sys.stderr, flush=True)
                if os.path.exists(r):
                    os.remove(r)
            if os.path.exists(r) and not bad_result(src, r):
                break
            if os.path.exists(r):
                os.remove(r)
            if attempt == 0:
                if cpu is None:
                    cpu, _ = onnx_session(a.onnx, cpu=True)
                print('%s 结果不对, 改用 CPU 重做' % k, file=sys.stderr, flush=True)
        else:
            fails.append(k)
            continue
        os.remove(os.path.join(cache_in, k + '.png'))
    if fails:
        sys.exit('放大结果有 %d 张不对 (已放好的会保留, 再运行只做剩下的)' % len(fails))


def _upscale_all(a, cache_in, cache_out, todo, pending):
    """开发机: 整个文件夹一次跑完。发行版 (--tile): 每批 BATCH 张重开一次 realesrgan, 每批跑完马上检查,
    坏的放回去, 换一个新进程重做 (2026-11-08 用户 Windows 更新驱动后: 前面的结果正常, 越往后越花屏)"""
    queued = sorted(f[:-4] for f in os.listdir(cache_in) if f.endswith('.png'))
    gentle, batch = [], len(queued)
    if a.tile:   # 发行版: 选显卡; 读 / 算 / 写都只用 1 个线程, 同一时间只算一张
        gpu, _, score = pick_gpu(a.esrgan)
        gentle = (['-g', str(gpu)] if gpu is not None else []) + ['-t', str(256 if score >= 3 else a.tile), '-j', '1:1:1']
        batch = BATCH
    print('realesrgan:', a.esrgan, '-n', a.model, '-s', a.scale, *gentle, '每批', batch, '张', file=sys.stderr, flush=True)
    bdir = os.path.join(os.path.dirname(cache_in), 'batch')
    shutil.rmtree(bdir, ignore_errors=True)
    tries = {}
    done, fails = 0, []
    while queued:
        cur, queued = queued[:batch], queued[batch:]
        os.makedirs(bdir, exist_ok=True)
        for k in cur:
            shutil.copy(os.path.join(cache_in, k + '.png'), os.path.join(bdir, k + '.png'))
        rc, err = _esrgan(a, bdir, cache_out, gentle, done, pending)
        shutil.rmtree(bdir, ignore_errors=True)
        bad = []
        for k in cur:
            r = os.path.join(cache_out, k + '.png')
            if not os.path.exists(r) or bad_result(ref_image(a, k, todo[k]), r):
                if os.path.exists(r):
                    os.remove(r)   # 不留在缓存里
                bad.append(k)
        if rc != 0 and len(bad) == len(cur) and not done:
            sys.exit('realesrgan 失败 (需要支持 Vulkan 的显卡): ' + err)
        if bad:
            print('这一批 %d 张里 %d 张结果不对 (返回码 %d), 换新进程重做' % (len(cur), len(bad), rc), file=sys.stderr, flush=True)
        for k in bad:
            tries[k] = tries.get(k, 0) + 1
            (fails if tries[k] > 2 else queued).append(k)   # 每张最多重做 2 次
        done += len(cur) - len(bad)
        for k in cur:
            if k not in bad:
                os.remove(os.path.join(cache_in, k + '.png'))
    if fails:
        sys.exit('放大结果有 %d 张重做 2 次仍然不对 (黑图 / 花屏; 显卡驱动问题, 请更新显卡驱动后重试, '
                 '已放好的会保留, 再运行只做剩下的; 日志里 [realesrgan] 开头的行是显卡信息)' % len(fails))


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument('src')
    ap.add_argument('out')
    ap.add_argument('--esrgan', required=True)
    ap.add_argument('--model', default='realesr-animevideov3')
    ap.add_argument('--scale', type=int, default=2)
    ap.add_argument('--base', help='以这个目录里已放大的结果为输入再放大 (4K = ×2 两遍)')
    ap.add_argument('--no-glb', action='store_true', help='不写整份 GLB')
    ap.add_argument('--keep-cache', action='store_true', help='保留放大结果缓存 (约 2.4 GB), 下次只处理新增图片')
    ap.add_argument('--onnx', default='', help='用 onnxruntime (Windows: DirectML) 和这个 ONNX 模型放大, 不用 realesrgan (只支持 ×2 模型)')
    ap.add_argument('--tile', type=int, default=0, help='realesrgan 图块大小 (发行版 128: 不让显卡被占满卡住桌面; 0 = 自动, 开发机)')
    a = ap.parse_args(argv)
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
    redo = 0
    for n, (k, data) in enumerate(todo.items()):
        if PROGRESS and n % 200 == 0:
            PROGRESS(n, len(todo), '检查')
        res = os.path.join(cache_out, k + '.png')
        if os.path.exists(res):
            if not bad_result(ref_image(a, k, data), res):
                continue
            os.remove(res)   # 以前放大坏了的黑图: 重做
            redo += 1
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
    print('图片 %d 张, GLB %d 个, 不重复贴图 %d 张, 需要放大 %d 张 (其中缓存里的黑图重做 %d 张)' % (len(images), len(glbs), len(todo), pending, redo), flush=True)
    # 2. 超分 (文件夹模式, GPU)
    if pending:
        (_upscale_onnx if a.onnx else _upscale_all)(a, cache_in, cache_out, todo, pending)
    missing = [k for k in todo if not os.path.exists(os.path.join(cache_out, k + '.png'))]
    if missing:
        sys.exit('有 %d 张没有放大结果' % len(missing))

    def result(k):
        return os.path.join(cache_out, k + '.png')
    # 3. 写出: 图片按原路径, GLB 替换内嵌贴图
    # 界面 / 精灵图按 .png 路径引用, 保持 PNG; GLB 内的不透明贴图改存 JPEG
    enc = {}
    for n, f in enumerate(images):
        if PROGRESS and n % 50 == 0:
            PROGRESS(n, len(images), '写界面图')
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
