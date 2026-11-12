# PyInstaller 配置: 发行版素材提取程序 (tools/extractor.py) → dist/czt_extract/czt_extract.exe (onedir)
# 用法 (在 Windows 上, 仓库根目录): pyinstaller --noconfirm tools/extractor.spec
#   .github/workflows/extractor.yml 自动打包; ffmpeg.exe / ffprobe.exe 之后复制进 dist/czt_extract/ (convert_video._bin 在程序旁边找)
# X utf8: 各工具的 open() 没写 encoding, Windows 默认 GBK 会读坏 / 写坏 UTF-8 的 JSON, 开 UTF-8 模式和 mac / Linux 一致
import os
from PyInstaller.utils.hooks import collect_data_files, collect_dynamic_libs

ROOT = os.path.abspath(os.path.join(SPECPATH, '..'))
T = os.path.join(ROOT, 'tools')

# extractor.py 用 importlib 按名字导入, PyInstaller 静态分析看不到, 逐个列出 (同 extractor.MODULES, 加上它们的依赖)
hidden = ['tsw2png', 'title_buttons_masks', 'extract_text', 'extract_stats', 'extract_music', 'match_scenes',
          'build_levels', 'disasm_script', 'wld2gltf', 'ply2gltf', 'skill_catalog', 'export_game', 'export_battle',
          'game_lists', 'export_records', 'export_tianshu', 'export_actors', 'export_held', 'export_faces',
          'export_ui_acts', 'effects', 'convert_video', 'export_minimap', 'apply_update', 'hd_assets', 'hd_textures',
          'act', 'ply', 'wld', 'mapsdat', 'tex2png', 'lzo1x', 'scene_anim', 'render_preview', 'make_title_buttons',
          'pefile', 'opencc', 'capstone',   # capstone: export_tianshu 顶层导入 (带原生库, 下面 binaries 收)
          'onnxruntime']   # hd_assets 高清放大 (Windows: onnxruntime-directml, 带 DirectML.dll)

# onnxruntime 要 VC++ 运行库 (MSVCP140 等); 玩家刚装的系统可能没有 (2026-11-08 用户重装系统后 DLL load failed), 随程序带上
# (微软允许随程序分发); 从打包机的 System32 取, 放在程序根目录 (PyInstaller 把它加进 DLL 搜索路径)
VC = [(os.path.join(os.environ.get('SystemRoot', r'C:\Windows'), 'System32', n), '.')
      for n in ('msvcp140.dll', 'msvcp140_1.dll', 'msvcp140_2.dll', 'vcruntime140.dll', 'vcruntime140_1.dll')]
VC = [v for v in VC if os.name == 'nt' and os.path.isfile(v[0])]

a = Analysis(
    [os.path.join(T, 'extractor.py')],
    pathex=[T],
    datas=[
        (os.path.join(T, 'battle_vm.json'), '.'),   # disasm_script 从自己所在目录读
        (os.path.join(ROOT, 'godot', 'data', 'title_glyphs', 'masks.bin'), 'title_glyphs'),   # extractor._masks
    ] + collect_data_files('opencc') + collect_data_files('capstone'),
    binaries=collect_dynamic_libs('capstone') + collect_dynamic_libs('onnxruntime') + VC,
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
