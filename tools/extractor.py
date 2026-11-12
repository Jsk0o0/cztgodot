"""发行版的素材提取程序 (PyInstaller 打包成单个可执行文件, 游戏首次启动时调用; 不分发任何原版素材)

用法: extractor --game <正版安装目录> --out <提取目录> [--only 步骤,...] [--force]
      extractor --selftest      (只检查打包是否完整: 导入全部工具模块、找 masks.bin / ffmpeg)
      extractor --apply-update <zip> --sha256 <hex> --target <安装目录> --wait-pid <pid> --relaunch <czt.exe>
                                (自动更新: 等游戏退出后替换文件再启动游戏, 见 tools/apply_update.py)
      extractor --hd 2|4 --esrgan <realesrgan-ncnn-vulkan> --out <提取目录>
                                (高清素材 → <提取目录>_hd / _4k, 见 run_hd; 进度协议同上)
  按顺序执行下面的步骤, 结果和开发时 make 提取的完全相同 (调用的是同一批 tools/*.py);
  每步完成后写 <out>/.steps/<步骤>.done, 再次运行时跳过 (中断后接着跑); --force 全部重做
  提取规则版本 VERSION: 和 <out>/.steps/version 不同时 (工具更新过) 清掉全部 .done 重新提取;
  全部完成后写 <out>/.steps/complete (内容 = VERSION), 游戏以它判断素材可用 (Game.EXTRACT_VERSION 要一起改)
输出给游戏读的进度 (每行一条, UTF-8):
  STEP <序号> <总数> <步骤名> <说明>     开始一步
  DONE <步骤名> <秒数>                  完成
  SKIP <步骤名>                         之前已完成
  FAIL <步骤名> <错误>                   失败 (进程退出码 1)
  PROG <已完成> <总数> <名称>          步骤内进度 (只有慢的步骤: 角色模型、过场动画; 最多每 0.5 秒一行)
  ALL_DONE <总秒数>
"""
import argparse
import glob
import importlib
import importlib.util
import multiprocessing
import os
import shutil
import sys
import time
import traceback

VERSION = 1

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)


def _argv(*a):
    sys.argv = ['extractor'] + [str(x) for x in a]


def _mod(name, *argv):
    """有的模块在 import 时就读 sys.argv (export_records / export_tianshu), 先设好再 import"""
    _argv(*argv)
    return importlib.import_module(name)


def _masks():
    # 打包后数据文件在 sys._MEIPASS 下
    base = getattr(sys, '_MEIPASS', os.path.join(HERE, '..', 'godot', 'data'))
    for p in (os.path.join(base, 'title_glyphs', 'masks.bin'), os.path.join(HERE, '..', 'godot', 'data', 'title_glyphs', 'masks.bin')):
        if os.path.exists(p):
            return p
    raise FileNotFoundError('masks.bin')


def step_ui(g, o):
    _mod('tsw2png').main(g, os.path.join(o, 'ui'))


def step_title(g, o):
    _mod('title_buttons_masks').main(o, _masks())


def step_text(g, o):
    _mod('extract_text', g, os.path.join(o, 'text')).main()


def step_stats(g, o):
    _mod('extract_stats').main(g, os.path.join(o, 'stats'))


def step_music(g, o):
    _mod('extract_music').main(g, os.path.join(o, 'text', 'music.json'))


def step_scene_map(g, o):
    _mod('match_scenes').main(g, os.path.join(o, 'text', 'maps.json'), os.path.join(o, 'text', 'wld_models.json'),
                              os.path.join(o, 'scene_map.json'))


def step_levels(g, o):
    _mod('build_levels').main(os.path.join(o, 'text', 'maps.json'), os.path.join(o, 'scene_map.json'),
                              os.path.join(o, 'text', 'map_graph.json'), os.path.join(o, 'levels'))


def step_scripts(g, o):
    _mod('disasm_script').main(g, os.path.join(o, 'scripts'))


def step_scenes(g, o):
    _mod('wld2gltf').run(g, os.path.join(o, 'scenes'))


def step_models(g, o):
    # 运行时只用到战斗的选择标记 SYS00017 (battle_hud.gd MARK_GLB)
    out = os.path.join(o, 'models', 'SYS', 'SYS00017.glb')
    os.makedirs(os.path.dirname(out), exist_ok=True)
    _mod('ply2gltf').export(g, ['SYS00017'], out)


def step_preview(g, o):
    _mod('skill_catalog').main(g, os.path.join(o, 'preview'))


def step_game(g, o):
    _mod('export_game').main(g, o)
    _mod('export_battle').main(g, o)
    _mod('game_lists').main(o)
    _mod('export_records', g, o).main()
    _mod('export_tianshu', g, o).main()
    _mod('export_minimap').main(g, o)   # 用 ui/index.json (ui 步骤) 找小地图图片


def step_actors(g, o):
    lst = os.path.join(o, 'game', 'actors_needed.txt')
    ids = [int(x) for x in open(lst).read().split() if x.strip()]
    m = _mod('export_actors')
    m.PROGRESS = progress
    m.main(g, os.path.join(o, 'game', 'actors'), ids)
    _mod('export_held').main(g, o)
    _mod('export_faces').main(g, o)
    _mod('export_ui_acts').main(g, o)


def step_effects(g, o):
    sk = ','.join(os.path.join(o, *p) for p in (('preview', 'skills.json'), ('game', 'battle_fx_src.json'), ('game', 'field_fx_src.json')))
    _mod('effects').main([g, os.path.join(o, 'effects'), '--skills', sk, '--extra', '7042:0-1,8139:0-7,8117:0', '--particles', '2095,2023'])


def step_audio(g, o):
    # 原版音乐 / 音效复制到 audio/ (游戏 Game.audio_path 优先读这里, 运行时不再碰原版目录)
    dst = os.path.join(o, 'audio')
    os.makedirs(os.path.join(dst, 'Music'), exist_ok=True)
    os.makedirs(os.path.join(dst, 'ACT'), exist_ok=True)
    pairs = [(os.path.join(g, 'Music', f), os.path.join(dst, 'Music', f))
             for f in os.listdir(os.path.join(g, 'Music')) if os.path.isfile(os.path.join(g, 'Music', f))]
    pairs.append((os.path.join(g, 'ACT', 'all.snd'), os.path.join(dst, 'ACT', 'all.snd')))
    for src, d in pairs:
        _copy(src, d)


def _copy(src, dst):
    # 只复制内容: copy2 会带上原版文件的属性 (网络盘上 chflags 报 Operation not permitted; Windows 只读属性会让下次覆盖失败)
    # 大小相同视为已复制 (中断后续跑不重复); 先写 .part 再改名, 中断不会留下半个文件
    if os.path.isfile(dst) and os.path.getsize(dst) == os.path.getsize(src):
        return
    shutil.copyfile(src, dst + '.part')
    os.replace(dst + '.part', dst)


def step_video(g, o):
    # 过场动画 VIDEO/*.bik → video/*.ogv (同 make video; 已转好的跳过)
    m = _mod('convert_video')
    m.PROGRESS = progress
    m.main([g, o])


# 顺序同 Makefile (ui → text → stats → music → scene-map → levels → disasm → scenes → preview → game-data)
STEPS = [
    ('ui', '界面图片', step_ui),
    ('title', '标题按钮', step_title),
    ('text', '文本', step_text),
    ('stats', '数值', step_stats),
    ('music', '音乐表', step_music),
    ('scene_map', '地图与场景配对', step_scene_map),
    ('levels', '关卡触发区', step_levels),
    ('scripts', '剧情脚本', step_scripts),
    ('scenes', '场景模型', step_scenes),
    ('models', '战斗标记模型', step_models),
    ('preview', '技能数据', step_preview),
    ('game', '游戏数据', step_game),
    ('actors', '角色模型', step_actors),
    ('effects', '技能特效', step_effects),
    ('audio', '音乐与音效', step_audio),
    ('video', '过场动画', step_video),
]

# ---------------- 高清 (--hd 2|4): Real-ESRGAN 放大, 同 make hd / make hd4 (发行版只要贴图 tex/ 和界面图, 不写整份 GLB) ----------------
HD_CACHE = os.path.join('_cache', 'out_realesr-animevideov3_x2')
HD_VERSION = 3   # 高清规则版本: 和结果目录 .steps/hdversion 不同时整个目录删掉重做
#   3 = Windows 改用 DirectML (Vulkan 版在部分笔记本上花屏) + 更严的坏图检查; 2 = 检查黑图; 1 生成的可能有全黑贴图
HD_ONNX = os.path.join('models', 'realesr-animevideov3-x2.onnx')   # 高清放大程序包里 (和 realesrgan 同一个模型, tools/ncnn2onnx.py 转)


def hd_steps(ext, scale, esrgan):
    """[(步骤名, 说明, 函数, 结果目录)]; 4K = 2K 的放大结果再 ×2, 所以先做 2K (2K 也能用)"""
    d2, d4 = ext.rstrip('/\\') + '_hd', ext.rstrip('/\\') + '_4k'
    onnx = os.path.join(os.path.dirname(esrgan), HD_ONNX)
    # Windows: onnxruntime DirectML (显卡不行自动用 CPU); 2026-11-08 用户笔记本 Vulkan (realesrgan) 每批设备丢失、结果花屏
    eng = ['--onnx', onnx] if os.name == 'nt' and os.path.isfile(onnx) else []

    def up2(g, o):
        m = _mod('hd_assets')
        m.PROGRESS = progress
        m.main([ext, d2, '--esrgan', esrgan, '--no-glb', '--keep-cache', '--tile', '128'] + eng)

    def tex2(g, o):
        _mod('hd_textures').main(ext, d2, 2)

    def up4(g, o):
        m = _mod('hd_assets')
        m.PROGRESS = progress
        m.main([ext, d4, '--esrgan', esrgan, '--base', os.path.join(d2, HD_CACHE), '--no-glb', '--keep-cache', '--tile', '128'] + eng)

    def tex4(g, o):
        _mod('hd_textures').main(ext, d4, 4)
    steps = [('hd2', '2K 放大贴图', up2, d2), ('hd2tex', '2K 整理贴图', tex2, d2)]
    if scale == 4:
        steps += [('hd4', '4K 放大贴图', up4, d4), ('hd4tex', '4K 整理贴图', tex4, d4)]
    return steps


def run_hd(ext, scale, esrgan):
    """高清素材 → <提取目录>_hd (2K) / <提取目录>_4k (4K); 每步完成写 <结果目录>/.steps/<步>.done, 中断后接着做;
    全部完成写 <结果目录>/.steps/complete (游戏只认有 complete 的), 删掉放大缓存"""
    if not os.path.isfile(os.path.join(ext, '.steps', 'complete')):
        emit('FAIL check 素材还没有提取完')
        return 1
    if not os.path.isfile(esrgan):
        emit('FAIL check 找不到放大程序 ' + esrgan)
        return 1
    steps = hd_steps(ext, scale, esrgan)
    for d in {x[3] for x in steps}:
        vf = os.path.join(d, '.steps', 'hdversion')
        if os.path.isdir(d) and (not os.path.exists(vf) or open(vf).read().strip() != str(HD_VERSION)):
            # 旧规则生成的 (可能有坏图): 整个重做; 删不掉的 (别的程序开着, 例 旧版游戏把日志写在这里) 跳过, 不影响重做
            shutil.rmtree(d, ignore_errors=True)
            for sub in ('.steps', 'tex'):   # 这两处一定要清掉: 留下 complete / 旧黑图会被当成已完成 / 已有
                shutil.rmtree(os.path.join(d, sub), ignore_errors=True)
        os.makedirs(os.path.join(d, '.steps'), exist_ok=True)
        open(vf, 'w').write('%d\n' % HD_VERSION)
    t_all = time.time()
    for k, (name, desc, fn, d) in enumerate(steps):
        marks = os.path.join(d, '.steps')
        os.makedirs(marks, exist_ok=True)
        mark = os.path.join(marks, name + '.done')
        if os.path.exists(mark):
            emit('SKIP', name)
            continue
        emit('STEP', k + 1, len(steps), name, desc)
        t0 = time.time()
        real = sys.stdout
        sys.stdout = sys.stderr
        try:
            fn(None, None)
        except (Exception, SystemExit) as e:  # noqa: BLE001
            traceback.print_exc()
            emit('FAIL', name, (str(e) if isinstance(e, SystemExit) else repr(e))[:300].replace('\n', ' '))
            return 1
        finally:
            sys.stdout = real
        open(mark, 'w').write('%.1f\n' % (time.time() - t0))
        emit('DONE', name, '%.1f' % (time.time() - t0))
        if name in ('hd2tex', 'hd4tex'):
            open(os.path.join(marks, 'complete'), 'w').write('%d\n' % (2 if name == 'hd2tex' else 4))
    for d in {x[3] for x in steps}:   # 放大缓存 (2K 约 2.4GB) 用完删掉; 4K 要用 2K 的缓存, 所以最后一起删
        shutil.rmtree(os.path.join(d, '_cache'), ignore_errors=True)
    emit('ALL_DONE', '%.1f' % (time.time() - t_all))
    return 0


# 版本变化时删掉的提取结果 (不含 audio / video)
WIPE = ['ui', 'text', 'stats', 'scene_map.json', 'levels', 'scripts', 'scenes', 'models', 'preview', 'game', 'effects']

MODULES = ['tsw2png', 'title_buttons_masks', 'extract_text', 'extract_stats', 'extract_music', 'match_scenes',
           'build_levels', 'disasm_script', 'wld2gltf', 'ply2gltf', 'skill_catalog', 'export_game', 'export_battle',
           'game_lists', 'export_records', 'export_tianshu', 'export_actors', 'export_held', 'export_faces',
           'export_ui_acts', 'effects', 'convert_video', 'export_minimap', 'apply_update', 'hd_assets', 'hd_textures']


# 提取工具用到的第三方库 (tools/ 下全部模块的 import 扫出来的; 新加依赖要同时加到 extractor.spec 和打包脚本的 pip 列表)
THIRD_PARTY = ['numpy', 'PIL', 'opencc', 'pefile', 'capstone', 'onnxruntime']


def selftest():
    """打包检查: 模块都能导入 (export_records / export_tianshu 在 import 时读 argv, 跳过)、数据文件在、ffmpeg 有 Theora"""
    bad = []
    for m in MODULES:
        if m in ('export_records', 'export_tianshu'):
            if importlib.util.find_spec(m) is None:
                bad.append(m)
            continue
        try:
            _mod(m)
        except Exception as e:  # noqa: BLE001
            bad.append('%s: %r' % (m, e))
    # 第三方库要真的导入 (上面跳过的 export_tianshu 顶层就 import capstone / pefile; 2026-11-07 打包漏了 capstone, 提取到天书一步才报错)
    for m in THIRD_PARTY:
        try:
            importlib.import_module(m)
        except Exception as e:  # noqa: BLE001
            bad.append('第三方库 %s: %r' % (m, e))
    try:   # capstone 带原生库, 实际反汇编一条指令
        import capstone
        ins = list(capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_32).disasm(b'\x55', 0))
        emit('capstone', ins[0].mnemonic if ins else '?')
        if not ins or ins[0].mnemonic != 'push':
            bad.append('capstone 反汇编结果不对')
    except Exception as e:  # noqa: BLE001
        bad.append('capstone: %r' % e)
    try:   # onnxruntime 带原生库 (+ VC++ 运行库); Windows 要有 DirectML
        import onnxruntime as ort
        emit('onnxruntime', ort.__version__, ','.join(ort.get_available_providers()))
        if os.name == 'nt' and 'DmlExecutionProvider' not in ort.get_available_providers():
            bad.append('onnxruntime 没有 DirectML (要装 onnxruntime-directml)')
    except Exception as e:  # noqa: BLE001
        bad.append('onnxruntime: %r' % e)
    try:
        emit('masks', _masks())
    except Exception as e:  # noqa: BLE001
        bad.append('masks.bin: %r' % e)
    emit('utf8_mode', sys.flags.utf8_mode)
    if getattr(sys, 'frozen', False) and os.name == 'nt' and not sys.flags.utf8_mode:
        bad.append('没有开 UTF-8 模式 (extractor.spec 的 X utf8)')
    cv = importlib.import_module('convert_video')
    emit('ffmpeg', cv._bin('ffmpeg'), 'libtheora' if cv.libtheora() else '无 libtheora')
    if not cv.libtheora() and cv._bin('ffmpeg2theora') == 'ffmpeg2theora' and not shutil.which('ffmpeg2theora'):
        bad.append('ffmpeg 没有 libtheora 编码器, 也找不到 ffmpeg2theora')
    else:   # 实际编一段: 1 秒测试画面 + 正弦音 → .ogv (同过场动画的编码流程)
        import tempfile
        tmp = tempfile.mkdtemp(prefix='czt_selftest_')
        try:
            src = os.path.join(tmp, 'src.mkv')
            cv.run(['ffmpeg', '-v', 'error', '-y', '-f', 'lavfi', '-i', 'testsrc=size=320x240:rate=15:duration=1',
                    '-f', 'lavfi', '-i', 'sine=duration=1', '-c:v', 'ffv1', '-c:a', 'flac', src])
            out = os.path.join(tmp, 'out.ogv')
            cv.encode(['-i', src], src, out, tmp, 8)
            r = cv._sp(['ffprobe', '-v', 'error', '-show_entries', 'stream=codec_name', '-of', 'csv=p=0', out],
                       capture_output=True, text=True)
            codecs = sorted(r.stdout.split())
            emit('encode', ','.join(codecs))
            if codecs != ['theora', 'vorbis']:
                bad.append('Theora 编码结果不对: %s' % codecs)
        except (Exception, SystemExit) as e:  # noqa: BLE001
            bad.append('Theora 编码失败: %s' % e)
        finally:
            shutil.rmtree(tmp, ignore_errors=True)
    for b in bad:
        emit('BAD', b)
    emit('SELFTEST', 'OK' if not bad else 'FAIL')
    return 1 if bad else 0


def emit(*a):
    print(*a, flush=True)


_prog_t = 0.0


def progress(done, total, label=''):
    """步骤内进度 (慢的步骤: 角色模型按个数、过场动画按字节): PROG <已完成> <总数> <名称>; 最多每 0.5 秒一行, 完成时必出"""
    global _prog_t
    now = time.time()
    if done < total and now - _prog_t < 0.5:
        return
    _prog_t = now
    # 步骤运行时 sys.stdout 换成了 stderr (工具日志), 进度行要写到真正的 stdout
    print('PROG', int(done), int(total), str(label).replace('\n', ' '), file=sys.__stdout__, flush=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--game')
    ap.add_argument('--out')
    ap.add_argument('--selftest', action='store_true')
    ap.add_argument('--only', default='')
    ap.add_argument('--force', action='store_true')
    ap.add_argument('--hd', type=int, choices=(2, 4), help='高清素材: 放大 --out (提取目录) 里的贴图, 要 --esrgan')
    ap.add_argument('--esrgan', default='')
    ap.add_argument('--apply-update', help='自动更新: 替换安装目录里的文件 (见 tools/apply_update.py)')
    ap.add_argument('--sha256', default='')
    ap.add_argument('--target')
    ap.add_argument('--wait-pid', type=int, default=0)
    ap.add_argument('--relaunch', default='')
    a = ap.parse_args()
    if a.apply_update:
        if not a.target:
            ap.error('--apply-update 需要 --target')
        return _mod('apply_update').main(a)
    if a.selftest:
        return selftest()
    if a.hd:
        if not a.out or not a.esrgan:
            ap.error('--hd 需要 --out (提取目录) 和 --esrgan')
        return run_hd(os.path.abspath(a.out), a.hd, os.path.abspath(a.esrgan))
    if not a.game or not a.out:
        ap.error('需要 --game 和 --out')
    game, out = os.path.abspath(a.game), os.path.abspath(a.out)
    if not os.path.isdir(os.path.join(game, 'Model')) or not os.path.isfile(os.path.join(game, 'ACT', 'all.snd')):
        emit('FAIL check 不是《轩辕剑外传·苍之涛》的安装目录（缺少 Model 或 ACT/all.snd）')
        return 1
    only = set(x for x in a.only.split(',') if x)
    marks = os.path.join(out, '.steps')
    os.makedirs(marks, exist_ok=True)
    vf = os.path.join(marks, 'version')
    old = open(vf).read().strip() if os.path.exists(vf) else ''
    if old != str(VERSION) or a.force:
        # 提取规则变了: 旧结果整个删掉重做 (有的工具按修改时间跳过已有文件, 只删 .done 不够);
        # 视频 (转一次很慢, 规则很少变) 和音频 (原样复制) 保留, 它们的步骤照样重跑, 已有文件跳过
        for f in glob.glob(os.path.join(marks, '*.done')) + glob.glob(os.path.join(marks, 'complete')):
            os.remove(f)   # 全新目录里还没有 complete, 用 glob 只删存在的
        for d in WIPE if old or a.force else []:   # 只清提取器自己建过的目录 (有 version), 不碰开发用的 extracted/
            p = os.path.join(out, d)
            if os.path.isdir(p):
                shutil.rmtree(p)
            elif os.path.exists(p):
                os.remove(p)
        open(vf, 'w').write('%d\n' % VERSION)
    t_all = time.time()
    todo = [s for s in STEPS if not only or s[0] in only]
    for k, (name, desc, fn) in enumerate(todo):
        mark = os.path.join(marks, name + '.done')
        if os.path.exists(mark):
            emit('SKIP', name)
            continue
        emit('STEP', k + 1, len(todo), name, desc)
        t0 = time.time()
        cwd = os.getcwd()
        try:
            # 各工具的日志打到 stderr, stdout 只留进度行
            real = sys.stdout
            sys.stdout = sys.stderr
            try:
                fn(game, out)
            finally:
                sys.stdout = real
                os.chdir(cwd)
        except (Exception, SystemExit) as e:  # noqa: BLE001  工具里有 sys.exit('原因')
            traceback.print_exc()
            msg = str(e) if isinstance(e, SystemExit) else repr(e)
            emit('FAIL', name, msg[:300].replace('\n', ' '))
            return 1
        open(mark, 'w').write('%.1f\n' % (time.time() - t0))
        emit('DONE', name, '%.1f' % (time.time() - t0))
    if not only:
        open(os.path.join(marks, 'complete'), 'w').write('%d\n' % VERSION)
    emit('ALL_DONE', '%.1f' % (time.time() - t_all))
    return 0


if __name__ == '__main__':
    multiprocessing.freeze_support()   # 打包后多进程 (场景导出) 的子进程从这里进入
    if hasattr(sys.stdout, 'reconfigure'):
        sys.stdout.reconfigure(encoding='utf-8')
        sys.stderr.reconfigure(encoding='utf-8', errors='replace')
    sys.exit(main())
