"""核对 export_tianshu.FOOTPRINTS (提取时用的常量) 和从 SWDMD_GB.EXE 逆向读出的一致 (开发机用, 发行版提取不读 EXE)
用法: python test_tianshu_footprints.py <游戏目录 (有 SWDMD_GB.EXE)>"""
import json
import os
import sys

sys.argv = [sys.argv[0], sys.argv[1], '.']
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import export_tianshu as t  # noqa: E402

a = json.loads(json.dumps(t.footprints(), ensure_ascii=False))
b = json.loads(json.dumps(t.footprints_from_exe(sys.argv[1]), ensure_ascii=False))
print('FOOTPRINTS', 'PASS' if a == b else 'FAIL', len(a), '种房舍')
sys.exit(0 if a == b else 1)
