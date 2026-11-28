"""比对两个 pck 的文件级差异 (打补丁前后): 列出内容不同的条目 → 即补丁器实际替换的清单.
用法: cmp_pck.py <GDRE目录> <pck_A> <pck_B>"""
import hashlib
import os
import sys
import tempfile

import make_portable_mods as mpm


def extract_all(gdre, pck):
    out = tempfile.mkdtemp(prefix="czt_ex_")
    mpm.run_gdre("--headless", f"--extract={pck}", f"--output={out}", cwd=None)
    files = {}
    for root, _, fs in os.walk(out):
        for f in fs:
            p = os.path.join(root, f)
            rel = os.path.relpath(p, out).replace("\\", "/")
            files[rel] = hashlib.sha256(open(p, "rb").read()).hexdigest()[:12]
    return files


def main():
    gdre, a, b = sys.argv[1], os.path.abspath(sys.argv[2]), os.path.abspath(sys.argv[3])
    mpm.GDRE_DIR = gdre
    fa, fb = extract_all(gdre, a), extract_all(gdre, b)
    diff = [k for k in fa if k in fb and fa[k] != fb[k]]
    only_a = [k for k in fa if k not in fb]
    only_b = [k for k in fb if k not in fa]
    print(f"共 {len(fa)} / {len(fb)} 条目; 内容不同 {len(diff)}, 仅A {len(only_a)}, 仅B {len(only_b)}")
    for k in sorted(diff):
        print("DIFF", k)
    for k in sorted(only_a):
        print("ONLY_A", k)
    for k in sorted(only_b):
        print("ONLY_B", k)


if __name__ == "__main__":
    main()
