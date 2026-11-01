"""发行版的素材提取程序 (PyInstaller 打包成单个可执行文件, 游戏首次启动时调用; 不分发任何原版素材)

用法: extractor --game <正版安装目录> --out <提取目录> [--only 步骤,...] [--force]
  按顺序执行下面的步骤, 结果和开发时 make 提取的完全相同 (调用的是同一批 tools/*.py);
  每步完成后写 <out>/.steps/<步骤>.done, 再次运行时跳过 (中断后接着跑); --force 全部重做
输出给游戏读的进度 (每行一条, UTF-8):
  STEP <序号> <总数> <步骤名> <说明>     开始一步
  DONE <步骤名> <秒数>                  完成
  SKIP <步骤名>                         之前已完成
  FAIL <步骤名> <错误>                   失败 (进程退出码 1)
  ALL_DONE <总秒数>
"""
import argparse
import importlib
import multiprocessing
import os
import shutil
import sys
import time
import traceback

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


def step_actors(g, o):
    lst = os.path.join(o, 'game', 'actors_needed.txt')
    ids = [int(x) for x in open(lst).read().split() if x.strip()]
    _mod('export_actors').main(g, os.path.join(o, 'game', 'actors'), ids)
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
    for f in os.listdir(os.path.join(g, 'Music')):
        shutil.copy2(os.path.join(g, 'Music', f), os.path.join(dst, 'Music', f))
    shutil.copy2(os.path.join(g, 'ACT', 'all.snd'), os.path.join(dst, 'ACT', 'all.snd'))


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
]


def emit(*a):
    print(*a, flush=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--game', required=True)
    ap.add_argument('--out', required=True)
    ap.add_argument('--only', default='')
    ap.add_argument('--force', action='store_true')
    a = ap.parse_args()
    game, out = os.path.abspath(a.game), os.path.abspath(a.out)
    if not os.path.isdir(os.path.join(game, 'Model')) or not os.path.isfile(os.path.join(game, 'ACT', 'all.snd')):
        emit('FAIL check 不是《轩辕剑外传·苍之涛》的安装目录（缺少 Model 或 ACT/all.snd）')
        return 1
    only = set(x for x in a.only.split(',') if x)
    marks = os.path.join(out, '.steps')
    os.makedirs(marks, exist_ok=True)
    t_all = time.time()
    todo = [s for s in STEPS if not only or s[0] in only]
    for k, (name, desc, fn) in enumerate(todo):
        mark = os.path.join(marks, name + '.done')
        if os.path.exists(mark) and not a.force:
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
        except Exception as e:  # noqa: BLE001
            traceback.print_exc()
            emit('FAIL', name, repr(e)[:200].replace('\n', ' '))
            return 1
        open(mark, 'w').write('%.1f\n' % (time.time() - t0))
        emit('DONE', name, '%.1f' % (time.time() - t0))
    emit('ALL_DONE', '%.1f' % (time.time() - t_all))
    return 0


if __name__ == '__main__':
    multiprocessing.freeze_support()   # 打包后多进程 (场景导出) 的子进程从这里进入
    if hasattr(sys.stdout, 'reconfigure'):
        sys.stdout.reconfigure(encoding='utf-8')
        sys.stderr.reconfigure(encoding='utf-8', errors='replace')
    sys.exit(main())
