"""过场视频: VIDEO/*.bik → Theora .ogv (Godot 只能播 Ogg Theora)

用法: python convert_video.py <游戏目录> <extracted 目录> [--hd <高清输出目录> --esrgan <realesrgan-ncnn-vulkan>] [--uhd]
  --uhd: 4K 版 → <高清输出>/video_4k/<名>.ogv: 去掉做在视频里的上下黑边 (800×600 → 800×450), 连做两次 ×2 放大成 3200×1800;
         每 600 帧一批 (4K PNG 每张约 8MB), 每批编成无损 FFV1 片段, 最后拼接再编 Theora
  标清: <extracted>/video/<名>.ogv;  高清: <高清输出>/video/<名>.ogv (Real-ESRGAN realesr-animevideov3 ×2, 同 hd_assets.py)
工具链 (Homebrew ffmpeg 没有 libtheora 编码器):
  视频 ffmpeg 解 Bink → 无损 FFV1 (level 1, 旧版 libavcodec 能读) 中间文件 → ffmpeg2theora 编 Theora
  音频 ffmpeg 原生 vorbis 编码器 (ffmpeg2theora 带音频会崩溃) → ffmpeg 无损合流
高清版逐帧放大: 拆 PNG → realesrgan 整个目录放大 → 合成 FFV1 → Theora; 中间文件在 <高清输出>/_video_tmp, 每个视频做完即删
已存在的输出跳过, 可以中断后重跑。
"""
import argparse
import glob
import os
import shutil
import subprocess
import sys


def run(cmd, **kw):
    r = subprocess.run(cmd, capture_output=True, text=True, **kw)
    if r.returncode != 0:
        sys.exit('失败: %s\n%s' % (' '.join(cmd[:3]), (r.stderr or r.stdout)[-2000:]))


def has_audio(src):
    r = subprocess.run(['ffprobe', '-v', 'error', '-select_streams', 'a', '-show_entries', 'stream=index',
                        '-of', 'csv=p=0', src], capture_output=True, text=True)
    return bool(r.stdout.strip())


def encode(video_src, audio_src, out, tmp, vq):
    """video_src: ffmpeg 能读的视频 (bik 或 PNG 序列参数表); 输出 out (.ogv)"""
    mkv = os.path.join(tmp, 'v.mkv')
    vogv = os.path.join(tmp, 'v.ogv')
    run(['ffmpeg', '-v', 'error', '-y', *video_src, '-an', '-c:v', 'ffv1', '-level', '1', '-pix_fmt', 'yuv420p', mkv])
    # ffmpeg2theora 收尾时偶尔崩溃 (返回码非 0) 但文件已写完, 以 ffprobe 能读为准
    subprocess.run(['ffmpeg2theora', mkv, '--noaudio', '-v', str(vq), '-o', vogv], capture_output=True)
    if subprocess.run(['ffprobe', '-v', 'error', vogv], capture_output=True).returncode:
        sys.exit('ffmpeg2theora 失败: ' + out)
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


def frame_count(src):
    r = subprocess.run(['ffprobe', '-v', 'error', '-count_frames', '-select_streams', 'v', '-show_entries',
                        'stream=nb_read_frames,height', '-of', 'csv=p=0', src], capture_output=True, text=True)
    h, n = r.stdout.strip().split(',')[:2]
    return int(n), int(h)


def letterboxed(src):
    """800×600 的视频里是否做了上下黑边 (cropdetect 在几个位置取样, 内容高度都 ≤ 460)"""
    dur = float(subprocess.run(['ffprobe', '-v', 'error', '-show_entries', 'format=duration', '-of', 'csv=p=0', src],
                               capture_output=True, text=True).stdout)
    hs = []
    for t in (0.3, 0.5, 0.7):
        r = subprocess.run(['ffmpeg', '-ss', '%.2f' % (dur * t), '-t', '2', '-i', src, '-vf', 'cropdetect=24:2:0',
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


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('game')
    ap.add_argument('ext')
    ap.add_argument('--hd')
    ap.add_argument('--esrgan')
    ap.add_argument('--only', help='只转这些 (逗号分隔的文件名, 不含扩展名)')
    ap.add_argument('--uhd', action='store_true', help='4K 版 (两次 ×2), 需要 --hd 和 --esrgan')
    a = ap.parse_args()
    srcs = sorted(glob.glob(os.path.join(a.game, 'VIDEO', '*.bik')))
    if a.only:
        keep = set(a.only.split(','))
        srcs = [s for s in srcs if os.path.splitext(os.path.basename(s))[0] in keep]
    out_dir = os.path.join(os.path.abspath(a.hd or a.ext), 'video_4k' if a.uhd else 'video')
    os.makedirs(out_dir, exist_ok=True)
    tmp_root = os.path.join(os.path.abspath(a.hd or a.ext), '_video_tmp')
    for i, src in enumerate(srcs):
        name = os.path.splitext(os.path.basename(src))[0]
        out = os.path.join(out_dir, name + '.ogv')
        if os.path.exists(out):
            continue
        tmp = os.path.join(tmp_root, 'v%d' % i)   # 路径里不能有「.」 (realesrgan 会误判为扩展名)
        shutil.rmtree(tmp, ignore_errors=True)
        os.makedirs(tmp)
        print('[%d/%d] %s' % (i + 1, len(srcs), name), flush=True)
        if a.uhd:
            uhd(src, a.esrgan, out, tmp)
        elif not a.hd:
            encode(['-i', src], src, out, tmp, 8)
        else:
            fin, fout = os.path.join(tmp, 'in'), os.path.join(tmp, 'out')
            os.makedirs(fin)
            os.makedirs(fout)
            run(['ffmpeg', '-v', 'error', '-i', src, '-an', os.path.join(fin, '%06d.png')])
            run([a.esrgan, '-i', fin, '-o', fout, '-n', 'realesr-animevideov3', '-s', '2', '-f', 'png'],
                cwd=os.path.dirname(os.path.abspath(a.esrgan)))
            shutil.rmtree(fin)
            encode(['-framerate', '30', '-i', os.path.join(fout, '%06d.png')], src, out, tmp, 8)
        shutil.rmtree(tmp, ignore_errors=True)
        print('  →', out, '%.1fMB' % (os.path.getsize(out) / 1e6), flush=True)
    shutil.rmtree(tmp_root, ignore_errors=True)


if __name__ == '__main__':
    main()
