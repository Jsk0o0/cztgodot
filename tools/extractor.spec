# PyInstaller 配置: 发行版素材提取程序 (tools/extractor.py) → dist/czt_extract/czt_extract.exe (onedir)
# 用法 (在 Windows 上, 仓库根目录): pyinstaller --noconfirm tools/extractor.spec
#   .github/workflows/extractor.yml 自动打包; ffmpeg.exe / ffprobe.exe 之后复制进 dist/czt_extract/ (convert_video._bin 在程序旁边找)
# X utf8: 各工具的 open() 没写 encoding, Windows 默认 GBK 会读坏 / 写坏 UTF-8 的 JSON, 开 UTF-8 模式和 mac / Linux 一致
import os
from PyInstaller.utils.hooks import collect_data_files

ROOT = os.path.abspath(os.path.join(SPECPATH, '..'))
T = os.path.join(ROOT, 'tools')

# extractor.py 用 importlib 按名字导入, PyInstaller 静态分析看不到, 逐个列出 (同 extractor.MODULES, 加上它们的依赖)
hidden = ['tsw2png', 'title_buttons_masks', 'extract_text', 'extract_stats', 'extract_music', 'match_scenes',
          'build_levels', 'disasm_script', 'wld2gltf', 'ply2gltf', 'skill_catalog', 'export_game', 'export_battle',
          'game_lists', 'export_records', 'export_tianshu', 'export_actors', 'export_held', 'export_faces',
          'export_ui_acts', 'effects', 'convert_video',
          'act', 'ply', 'wld', 'mapsdat', 'tex2png', 'lzo1x', 'scene_anim', 'render_preview', 'make_title_buttons',
          'pefile', 'opencc']

a = Analysis(
    [os.path.join(T, 'extractor.py')],
    pathex=[T],
    datas=[
        (os.path.join(T, 'battle_vm.json'), '.'),   # disasm_script 从自己所在目录读
        (os.path.join(ROOT, 'godot', 'data', 'title_glyphs', 'masks.bin'), 'title_glyphs'),   # extractor._masks
    ] + collect_data_files('opencc'),
    hiddenimports=hidden,
    excludes=['tkinter', 'matplotlib', 'IPython', 'pytest'],
    noarchive=False,
)
pyz = PYZ(a.pure)
exe = EXE(
    pyz,
    a.scripts,
    [('X utf8', None, 'OPTION')],
    exclude_binaries=True,
    name='czt_extract',
    console=True,   # 控制台程序 stdout 才可靠 (无控制台时 sys.stdout 可能是 None); 游戏用管道启动不弹窗口, 多进程子进程继承同一个隐藏控制台
    upx=False,
)
coll = COLLECT(exe, a.binaries, a.datas, name='czt_extract', upx=False)
