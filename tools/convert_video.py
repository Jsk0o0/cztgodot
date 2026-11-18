"""过场视频: VIDEO/*.bik → Theora .ogv (Godot 只能播 Ogg Theora)

用法: python convert_video.py <游戏目录> <extracted 目录> [--hd <高清输出目录> (--esrgan <realesrgan-ncnn-vulkan> | --onnx <模型>)] [--uhd]
  --uhd: 4K 版 → <高清输出>/video_4k/<名>.ogv: 去掉做在视频里的上下黑边 (800×600 → 800×450), 连做两次 ×2 放大成 3200×1800;
         每 600 帧一批 (4K PNG 每张约 8MB), 每批编成无损 FFV1 片段, 最后拼接再编 Theora
  标清: <extracted>/video/<名>.ogv;  高清: <高清输出>/video/<名>.ogv (Real-ESRGAN realesr-animevideov3 ×2, 同 hd_assets.py)
工具链: ffmpeg 自带 libtheora 编码器时 (Windows 发行版随提取器带的 ffmpeg) 直接编 Theora (-q:v 与 ffmpeg2theora -v 同一刻度);
  没有时 (Homebrew ffmpeg) 视频 ffmpeg 解 Bink → 无损 FFV1 (level 1, 旧版 libavcodec 能读) 中间文件 → ffmpeg2theora 编 Theora
  ffmpeg / ffprobe / ffmpeg2theora 先找环境变量 CZT_FFMPEG_DIR, 再找提取器程序旁边, 最后找 PATH
  音频 ffmpeg 原生 vorbis 编码器 (ffmpeg2theora 带音频会崩溃) → ffmpeg 无损合流
2 倍高清 (hd_segmented): 每 900 帧一段, 解码 → 放大 (--onnx: onnxruntime 逐帧, Windows 走 DirectML, 不落盘;
  --esrgan: 这一段拆 PNG 给 realesrgan) → 编成 Theora 段; 全部段做完无损拼接 + 原声音。
  分段在 <高清输出>/_video_tmp/h<文件名哈希>/, 中断后已完成的段保留, 全部视频做完才删 (发行版提取程序 --hd-video 用这个)
已存在的输出跳过, 可以中断后重跑。
"""
import argparse
import glob
import hashlib
import os
import shutil
import subprocess
import sys


PROGRESS = None   # 发行版提取程序 (extractor.py) 设成进度回调: PROGRESS(已完成, 总数, 名称)


def _bin(name):
    dirs = [os.environ.get('CZT_FFMPEG_DIR', '')]
    if getattr(sys, 'frozen', False):
        dirs.append(os.path.dirname(sys.executable))
    for d in dirs:
        for f in (name + '.exe', name):
            if d and os.path.isfile(os.path.join(d, f)):
                return os.path.join(d, f)
    return name


def _tool(cmd):
    return [_bin(cmd[0])] + list(cmd[1:]) if cmd and cmd[0] in ('ffmpeg', 'ffprobe', 'ffmpeg2theora') else cmd


_orig_run = subprocess.run


def _sp(cmd, *a, **kw):
    """subprocess.run, 但 ffmpeg 系工具换成找到的路径; Windows 下不弹黑窗口"""
    if os.name == 'nt':
        kw.setdefault('creationflags', 0x08000000)   # CREATE_NO_WINDOW
    return _orig_run(_tool(cmd), *a, **kw)


_LIBTHEORA = None


def libtheora():
    global _LIBTHEORA
    if _LIBTHEORA is None:
        r = _sp(['ffmpeg', '-hide_banner', '-encoders'], capture_output=True, text=True)
        _LIBTHEORA = r.returncode == 0 and ' libtheora ' in r.stdout
    return _LIBTHEORA


def run(cmd, **kw):
    r = _sp(cmd, capture_output=True, text=True, **kw)
    if r.returncode != 0:
        sys.exit('失败: %s\n%s' % (' '.join(cmd[:3]), (r.stderr or r.stdout)[-2000:]))


def has_audio(src):
    r = _sp(['ffprobe', '-v', 'error', '-select_streams', 'a', '-show_entries', 'stream=index',
                        '-of', 'csv=p=0', src], capture_output=True, text=True)
    return bool(r.stdout.strip())


def encode(video_src, audio_src, out, tmp, vq):
    """video_src: ffmpeg 能读的视频 (bik 或 PNG 序列参数表); 输出 out (.ogv)"""
    mkv = os.path.join(tmp, 'v.mkv')
    vogv = os.path.join(tmp, 'v.ogv')
    if libtheora():
        run(['ffmpeg', '-v', 'error', '-y', *video_src, '-an', '-pix_fmt', 'yuv420p', '-c:v', 'libtheora',
             '-q:v', str(vq), vogv])
    else:
        run(['ffmpeg', '-v', 'error', '-y', *video_src, '-an', '-c:v', 'ffv1', '-level', '1', '-pix_fmt', 'yuv420p', mkv])
        # ffmpeg2theora 收尾时偶尔崩溃 (返回码非 0) 但文件已写完, 以 ffprobe 能读为准
        _sp(['ffmpeg2theora', mkv, '--noaudio', '-v', str(vq), '-o', vogv], capture_output=True)
    if _sp(['ffprobe', '-v', 'error', vogv], capture_output=True).returncode:
        sys.exit('Theora 编码失败: ' + out)
    mux(vogv, audio_src, out, tmp)


def mux(vogv, audio_src, out, tmp):
    """只有画面的 vogv + audio_src 的声音 (Vorbis) → out; 先写 .part.ogv 再改名"""
    part = out + '.part.ogv'
    if audio_src and has_audio(audio_src):
        aogg = os.path.join(tmp, 'a.ogg')
        run(['ffmpeg', '-v', 'error', '-y', '-i', audio_src, '-vn', '-c:a', 'vorbis', '-strict', '-2', '-ac', '2',
             '-b:a', '192k', aogg])
        run(['ffmpeg', '-v', 'error', '-y', '-i', vogv, '-i', aogg, '-map', '0:v', '-map', '1:a', '-c', 'copy',
             '-f', 'ogg', part])
    else:
        shutil.copy(vogv, part)
    os.replace(part, out)


def probe(src):
    """(帧数, 宽, 高, 帧率字符串); 帧数要解码整个文件数 (Bink 头里的帧数不一定准)"""
    r = _sp(['ffprobe', '-v', 'error', '-count_frames', '-select_streams', 'v', '-show_entries',
             'stream=nb_read_frames,width,height,r_frame_rate', '-of', 'default=nw=1', src], capture_output=True, text=True)
    kv = dict(l.split('=', 1) for l in r.stdout.splitlines() if '=' in l)
    return int(kv['nb_read_frames']), int(kv['width']), int(kv['height']), kv.get('r_frame_rate', '30/1')


SEG_FRAMES = 900   # 高清分段: 每段 30 秒单独编好存下, 中断后从没做完的那段接着做; 全部做完再无损拼接


def _seg_encoder(w, h, fps, seg_part, tmp):
    """接收 RGB24 原始帧 (stdin) 的编码进程: 有 libtheora 直接编 Theora, 没有 (Homebrew) 先编 FFV1"""
    raw = ['-f', 'rawvideo', '-pix_fmt', 'rgb24', '-s', '%dx%d' % (w, h), '-r', fps, '-i', '-', '-an', '-pix_fmt', 'yuv420p']
    if libtheora():
        cmd = ['ffmpeg', '-v', 'error', '-y', *raw, '-c:v', 'libtheora', '-q:v', '8', '-f', 'ogg', seg_part]
    else:
        cmd = ['ffmpeg', '-v', 'error', '-y', *raw, '-c:v', 'ffv1', '-level', '1', '-f', 'matroska', os.path.join(tmp, 'seg.mkv')]
    kw = {'creationflags': 0x08000000} if os.name == 'nt' else {}
    return subprocess.Popen(_tool(cmd), stdin=subprocess.PIPE, stderr=subprocess.PIPE, **kw)


def _seg_finish(enc, seg_part, tmp):
    enc.stdin.close()
    err = enc.stderr.read().decode('utf-8', 'replace')
    if enc.wait() != 0:
        sys.exit('分段编码失败: ' + err[-1500:])
    if not libtheora():
        mkv = os.path.join(tmp, 'seg.mkv')
        _sp(['ffmpeg2theora', mkv, '--noaudio', '-v', '8', '-o', seg_part], capture_output=True)
        os.remove(mkv)
    if _sp(['ffprobe', '-v', 'error', seg_part], capture_output=True).returncode:
        sys.exit('分段编码失败: ' + seg_part)


def _frames(src, start, count, w, h):
    """解码 src 的第 start 帧起 count 帧, 逐帧给出 RGB24 (h, w, 3) uint8 数组"""
    import numpy as np
    kw = {'creationflags': 0x08000000} if os.name == 'nt' else {}
    dec = subprocess.Popen(_tool(['ffmpeg', '-v', 'error', '-i', src, '-an', '-vf',
                                  'select=between(n\\,%d\\,%d)' % (start, start + count - 1), '-vsync', '0',
                                  '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-']),
                           stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, **kw)
    size = w * h * 3
    try:
        while True:
            b = dec.stdout.read(size)
            if len(b) < size:
                break
            yield np.frombuffer(b, np.uint8).reshape(h, w, 3)
    finally:
        dec.stdout.close()
        dec.wait()


class OnnxUp:
    """Real-ESRGAN ×2 的 ONNX 版 (同 hd_assets: Windows 用 DirectML, 不行用 CPU); 整帧推理, 每帧检查, 坏的用 CPU 重做"""

    def __init__(self, model):
        import hd_assets
        self.ha = hd_assets
        self.model = model
        self.sess, self.how = hd_assets.onnx_session(model)
        self.cpu = self.sess if self.how == 'CPU' else None
        print('放大: %s (%s)' % (self.how, model), flush=True)

    def _run(self, sess, f):
        import numpy as np
        x = np.ascontiguousarray((f.astype(np.float32) / 255).transpose(2, 0, 1)[None])
        r = sess.run(None, {'data': x})[0][0].transpose(1, 2, 0)
        return np.clip(r * 255 + 0.5, 0, 255).astype(np.uint8)

    def bad(self, f, r):
        """结果缩回原尺寸和原帧比: 尺寸不对、平均差太大 (花屏 / 全黑), 或原帧有起伏而结果几乎是平的"""
        import numpy as np
        h, w, _ = f.shape
        if r.shape != (h * 2, w * 2, 3):
            return True
        small = r.reshape(h, 2, w, 2, 3).astype(np.float32).mean((1, 3))
        a = f.astype(np.float32)
        if np.abs(a - small).mean() > self.ha.BAD_DIFF:
            return True
        sa = a.std()
        return sa >= 4 and small.std() < 0.3 * sa

    def up(self, f):
        try:
            r = self._run(self.sess, f)
            if not self.bad(f, r):
                return r
        except Exception as e:  # noqa: BLE001
            print('放大出错: %s' % e, flush=True)
        if self.cpu is None:
            print('结果不对, 之后坏帧改用 CPU 重做', flush=True)
            self.cpu, _ = self.ha.onnx_session(self.model, cpu=True)
        r = self._run(self.cpu, f)
        if self.bad(f, r):
            sys.exit('放大结果不对 (CPU 也不对)')
        return r


def hd_segmented(src, out, tmp, up, esrgan, sub=None):
    """2 倍高清 (发行版提取程序): 每 SEG_FRAMES 帧一段, 解码 → 放大 → 编成 Theora 段存在 tmp (中断后已完成的段保留);
    全部段做完无损拼接 + 原声音 → out。up = OnnxUp (逐帧, 不落盘) 或 None (用 esrgan 程序放大这一段的 PNG)"""
    n, w, h, fps = probe(src)
    os.makedirs(tmp, exist_ok=True)
    segs = []
    for b, start in enumerate(range(0, n, SEG_FRAMES)):
        cnt = min(SEG_FRAMES, n - start)
        seg = os.path.join(tmp, 'seg%04d.ogv' % b)
        segs.append(seg)
        if os.path.exists(seg):
            continue
        part = seg + '.part'
        if up is not None:
            enc = _seg_encoder(w * 2, h * 2, fps, part, tmp)
            k = 0
            try:
                for k, f in enumerate(_frames(src, start, cnt, w, h), 1):
                    enc.stdin.write(up.up(f).tobytes())
                    if sub and k % 10 == 0:
                        sub((start + k) / n)
            except BrokenPipeError:
                pass
            _seg_finish(enc, part, tmp)
            if k != cnt:
                sys.exit('第 %d 段只解出 %d / %d 帧' % (b + 1, k, cnt))
        else:
            from PIL import Image
            d0, d1 = os.path.join(tmp, 'f0'), os.path.join(tmp, 'f1')
            for d in (d0, d1):
                shutil.rmtree(d, ignore_errors=True)
                os.makedirs(d)
            for k, f in enumerate(_frames(src, start, cnt, w, h)):
                Image.fromarray(f).save(os.path.join(d0, '%06d.png' % k), compress_level=1)
            run([esrgan, '-i', d0, '-o', d1, '-n', 'realesr-animevideov3', '-s', '2', '-f', 'png'],
                cwd=os.path.dirname(os.path.abspath(esrgan)))
            enc = _seg_encoder(w * 2, h * 2, fps, part, tmp)
            import numpy as np
            for k in range(cnt):
                enc.stdin.write(np.asarray(Image.open(os.path.join(d1, '%06d.png' % k)).convert('RGB')).tobytes())
            _seg_finish(enc, part, tmp)
            shutil.rmtree(d0)
            shutil.rmtree(d1)
        os.replace(part, seg)
        print('  段 %d: 帧 %d–%d / %d' % (b + 1, start, start + cnt - 1, n), flush=True)
        if sub:
            sub((start + cnt) / n)
    lst = os.path.join(tmp, 'segs.txt')
    with open(lst, 'w', encoding='utf-8') as fo:
        fo.writelines("file '%s'\n" % os.path.basename(x) for x in segs)
    vogv = os.path.join(tmp, 'v.ogv')
    run(['ffmpeg', '-v', 'error', '-y', '-f', 'concat', '-safe', '0', '-i', lst, '-c', 'copy', '-f', 'ogg', vogv])
    got = probe(vogv)[0]
    if got != n:
        sys.exit('拼接后帧数不对: %d / %d' % (got, n))
    mux(vogv, src, out, tmp)


def frame_count(src):
    r = _sp(['ffprobe', '-v', 'error', '-count_frames', '-select_streams', 'v', '-show_entries',
                        'stream=nb_read_frames,height', '-of', 'csv=p=0', src], capture_output=True, text=True)
    h, n = r.stdout.strip().split(',')[:2]
    return int(n), int(h)


def letterboxed(src):
    """800×600 的视频里是否做了上下黑边 (cropdetect 在几个位置取样, 内容高度都 ≤ 460)"""
    dur = float(_sp(['ffprobe', '-v', 'error', '-show_entries', 'format=duration', '-of', 'csv=p=0', src],
                               capture_output=True, text=True).stdout)
    hs = []
    for t in (0.3, 0.5, 0.7):
        r = _sp(['ffmpeg', '-ss', '%.2f' % (dur * t), '-t', '2', '-i', src, '-vf', 'cropdetect=24:2:0',
                            '-f', 'null', '-'], capture_output=True, text=True)
        c = [l.split('crop=')[1].split()[0] for l in r.stderr.splitlines() if 'crop=' in l]
        if c:
            hs.append(int(c[-1].split(':')[1]))
    return bool(hs) and max(hs) <= 460


def uhd(src, esrgan, out, tmp, batch=600):
    n, h = frame_count(src)
    crop = h == 600 and letterboxed(src)   # 黑边做在视频里的那些 (OP 等): 只放大中间 16:9 画面
    cwd = os.path.dirname(os.path.abspath(esrgan))
    segs = []
    for b, start in enumerate(range(0, n, batch)):
        d0, d1, d2 = (os.path.join(tmp, x) for x in ('f0', 'f1', 'f2'))
        for d in (d0, d1, d2):
            shutil.rmtree(d, ignore_errors=True)
            os.makedirs(d)
        # 按帧号取这一批 (select 精确到帧, 不受关键帧影响)
        run(['ffmpeg', '-v', 'error', '-i', src, '-an', '-vf',
             ('crop=800:450:0:75,' if crop else '') + 'select=between(n\\,%d\\,%d)' % (start, start + batch - 1),
             '-vsync', '0', '-start_number', '0', os.path.join(d0, '%06d.png')])
        run([esrgan, '-i', d0, '-o', d1, '-n', 'realesr-animevideov3', '-s', '2', '-f', 'png'], cwd=cwd)
        shutil.rmtree(d0)
        run([esrgan, '-i', d1, '-o', d2, '-n', 'realesr-animevideov3', '-s', '2', '-f', 'png'], cwd=cwd)
        shutil.rmtree(d1)
        seg = os.path.join(tmp, 'seg%04d.mkv' % b)
        run(['ffmpeg', '-v', 'error', '-y', '-framerate', '30', '-i', os.path.join(d2, '%06d.png'), '-c:v', 'ffv1',
             '-level', '1', '-pix_fmt', 'yuv420p', seg])
        shutil.rmtree(d2)
        segs.append(seg)
        print('  批 %d: 帧 %d–%d / %d' % (b + 1, start, min(start + batch, n) - 1, n), flush=True)
    lst = os.path.join(tmp, 'segs.txt')
    with open(lst, 'w') as f:
        f.writelines("file '%s'\n" % s for s in segs)
    encode(['-f', 'concat', '-safe', '0', '-i', lst], src, out, tmp, 8)


def _name(src):
    return os.path.splitext(os.path.basename(src))[0]


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument('game')
    ap.add_argument('ext')
    ap.add_argument('--hd')
    ap.add_argument('--esrgan')
    ap.add_argument('--onnx', help='高清用 ONNX 模型放大 (onnxruntime; Windows 走 DirectML), 不用 --esrgan 程序')
    ap.add_argument('--only', help='只转这些 (逗号分隔的文件名, 不含扩展名)')
    ap.add_argument('--uhd', action='store_true', help='4K 版 (两次 ×2), 需要 --hd 和 --esrgan')
    ap.add_argument('--jobs', type=int, default=0, help='标清同时转几个 (默认 CPU 核数 / 2, 最多 4)')
    a = ap.parse_args(argv)
    if a.hd and not a.uhd and not (a.onnx or a.esrgan):
        ap.error('--hd 需要 --onnx 或 --esrgan')
    up = OnnxUp(a.onnx) if a.hd and not a.uhd and a.onnx else None
    srcs = sorted(glob.glob(os.path.join(a.game, 'VIDEO', '*.bik')))
    if a.only:
        keep = set(a.only.split(','))
        srcs = [s for s in srcs if os.path.splitext(os.path.basename(s))[0] in keep]
    out_dir = os.path.join(os.path.abspath(a.hd or a.ext), 'video_4k' if a.uhd else 'video')
    os.makedirs(out_dir, exist_ok=True)
    tmp_root = os.path.join(os.path.abspath(a.hd or a.ext), '_video_tmp')
    sizes = [os.path.getsize(s) for s in srcs]   # 进度按源文件字节算 (最大 127MB、最小 1MB, 按个数算很不均匀)
    total = sum(sizes)
    todo = [i for i, src in enumerate(srcs) if not os.path.exists(os.path.join(out_dir, _name(src) + '.ogv'))]
    done = total - sum(sizes[i] for i in todo)
    if PROGRESS:
        PROGRESS(done, total, '')

    def one(i):
        src = srcs[i]
        name = _name(src)
        out = os.path.join(out_dir, name + '.ogv')
        # 每个文件自己的临时目录; 路径里不能有「.」 (realesrgan 会误判为扩展名)。
        # 2 倍高清: 目录名按文件名取 (不随列表顺序变), 不清空: 里面已完成的分段下次接着用
        seg_mode = a.hd and not a.uhd
        tmp = os.path.join(tmp_root, ('h' + hashlib.md5(name.encode('utf-8')).hexdigest()[:10]) if seg_mode else 'v%d' % i)
        if not seg_mode:
            shutil.rmtree(tmp, ignore_errors=True)
        os.makedirs(tmp, exist_ok=True)
        print('[%d/%d] %s' % (i + 1, len(srcs), name), flush=True)
        if PROGRESS:
            PROGRESS(done, total, name)   # 开始转哪个 (大文件要转好几分钟)
        if a.uhd:
            uhd(src, a.esrgan, out, tmp)
        elif not a.hd:
            encode(['-i', src], src, out, tmp, 8)
        else:
            sub = (lambda fr: PROGRESS(done + sizes[i] * fr, total, name)) if PROGRESS else None
            hd_segmented(src, out, tmp, up, a.esrgan, sub)
        shutil.rmtree(tmp, ignore_errors=True)
        print('  →', out, '%.1fMB' % (os.path.getsize(out) / 1e6), flush=True)
        return i

    # 标清: 几个文件同时转 (bink 解码和 Theora 编码基本是单线程, 各开一个 ffmpeg); 大文件先转, 免得最后剩一个大的拖着
    # 高清 / 4K 要用显卡跑 realesrgan, 一个一个来
    jobs = 1 if (a.hd or a.uhd) else (a.jobs or max(1, min(4, (os.cpu_count() or 2) // 2)))
    todo.sort(key=lambda i: -sizes[i])
    if jobs <= 1:
        for i in todo:
            one(i)
            done += sizes[i]
            if PROGRESS:
                PROGRESS(done, total, _name(srcs[i]))
    else:
        from concurrent.futures import ThreadPoolExecutor, as_completed
        with ThreadPoolExecutor(jobs) as ex:
            for f in as_completed([ex.submit(one, i) for i in todo]):
                i = f.result()   # 有一个失败就抛出 (其余的跑完才退出 with)
                done += sizes[i]
                if PROGRESS:
                    PROGRESS(done, total, _name(srcs[i]))
    shutil.rmtree(tmp_root, ignore_errors=True)   # 全部做完才删 (2 倍高清中断时留着已完成的分段)


if __name__ == '__main__':
    main()
