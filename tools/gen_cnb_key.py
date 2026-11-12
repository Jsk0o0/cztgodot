"""生成 godot/scripts/cnb_read_key.gd: 游戏内置的 CNB 只读令牌 (自动更新读私有仓库 corumol/swd 的清单和附件)
取项目根目录 .cnbkey 里「令牌名:swd-read」段的 Token; 不打印令牌。生成的文件在 .gitignore 里, 不进公开仓库
注意: 打进 czt.pck 的令牌谁都能拆出来 → 只给只读权限 (repo-code:r + repo-release:r), 只授权这一个仓库; 防伪靠清单签名
"""
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
src = os.path.join(ROOT, '.cnbkey')
if not os.path.exists(src):
    sys.exit('没有 .cnbkey')
m = re.search(r'令牌名:\s*swd-read\b.*?Token:\s*(\S+)', open(src, encoding='utf-8').read(), re.S)
if not m:
    sys.exit('.cnbkey 里找不到 swd-read 令牌')
tok = m.group(1)
half = len(tok) // 2
out = os.path.join(ROOT, 'godot', 'scripts', 'cnb_read_key.gd')
body = ('extends RefCounted\n## make cnb-key 生成 (tools/gen_cnb_key.py), 不进仓库: CNB 只读令牌 (自动更新)\n'
        'const TOKEN := "%s" + "%s"\n' % (tok[:half], tok[half:]))
if not os.path.exists(out) or open(out, encoding='utf-8').read() != body:
    open(out, 'w', encoding='utf-8').write(body)
    print('已生成', os.path.relpath(out, ROOT))
else:
    print('没变', os.path.relpath(out, ROOT))
