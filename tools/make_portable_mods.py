"""把已打补丁的 czt.pck 里 mod_manager 的 Mod 目录改成便携路径 (改补丁产物, 不用目录联接).

第三方「懒人补丁包」会整体替换 mod_manager.gdc, 其字节码把 Mod 目录写死成常量 user://mods.
本脚本对补丁产物做一次无损往返, 仅替换那一行路径:

    pck 取补丁版 .gdc → GDRE 反编译成 .gd → ROOT 常量改为 Portable.path_in("mods", "user://mods")
                    → GDRE 重编译回 .gdc → 注回 pck (重打整个 pck, 仅替换该文件)

无损性实测 (gdRE v2.7.4, --bytecode=4.7.2): 不改 ROOT 时 反编译→重编译 与原 .gdc 字节完全一致;
脚本每次都会先做这个自检, 不通过就拒绝修改 (gdRE/字节码版本与发行不符时不会悄悄改坏补丁).

Portable.path_in 非便携 (程序旁无 orig/) 时返回原来的 user://mods, 行为与官方一致;
便携时返回 <程序目录>/userdata/mods —— 引擎原生路径, 不需要 mklink 联接.

用法:
    make_portable_mods.py <GDRE目录> <czt.pck> [--check]
        --check: 只做无损自检 (反编译→重编译与原 .gdc 比对), 不写回

依赖: GDRE Tools (gdsdecomp) v2.7+ 解包目录, 与项目 venv 的 zstandard.
"""
import os
import re
import subprocess
import sys
import tempfile

import zstandard

GDC_MAGIC = b"GDSC"
RES_PATH = "res://scripts/mod_manager.gdc"
# 反编译产物里那一行的实际写法 (gdRE 把 := 写成 "var X: = "), 宽松匹配常量/var/类型注解
ROOT_RE = re.compile(r'^(\s*(?:const|var)\s+ROOT\b[^\n=]*=\s*)"user://mods"[\s\S]*?$', re.M)
NEW_ROOT = 'var ROOT: String = Portable.path_in("mods", "user://mods")'

GDRE_DIR = None


def run_gdre(*args, cwd=None):
    exe = os.path.join(GDRE_DIR, "gdre_tools.exe" if os.name == "nt" else "gdre_tools")
    if not os.path.isfile(exe):
        sys.exit(f"找不到 GDRE 可执行文件: {exe}")
    cmd = [exe] + [str(a).replace("\\", "/") for a in args]   # GDRE 拒绝反斜杠形式的选项值
    r = subprocess.run(cmd, capture_output=True, text=True, cwd=cwd,
                       encoding="utf-8", errors="replace")
    for line in (r.stdout or "").splitlines():
        if re.search(r"\bERROR\b|failed", line, re.I) and "godotengine" not in line:
            print("  GDRE:", line)
    if r.returncode != 0:
        sys.exit(f"GDRE 失败 (rc={r.returncode}):\n{r.stdout}\n{r.stderr}")
    return r


def gdc_from_pck(pck_path):
    """GDRE --extract 整个 pck 到临时目录, 返回 scripts/mod_manager.gdc 内容."""
    out = tempfile.mkdtemp(prefix="czt_mm_ex_")
    run_gdre("--headless", f"--extract={pck_path}", f"--output={out}")
    for root, _, files in os.walk(out):
        for f in files:
            if f == "mod_manager.gdc":
                return open(os.path.join(root, f), "rb").read()
    sys.exit(f"pck 里没找到 {RES_PATH}")


def decompile(wd, gdc):
    src = os.path.join(wd, "scripts")
    os.makedirs(src, exist_ok=True)
    open(os.path.join(src, "mod_manager.gdc"), "wb").write(gdc)
    open(os.path.join(wd, "project.godot"), "w").write(
        '[application]\n\nconfig/name="mm"\nconfig/features=PackedStringArray("4.7")\n')
    # 反编译输出落在 cwd (res:// 相对 cwd 解析, --path/--output 都不改变它), 所以 cwd=wd
    run_gdre("--headless", "--path", wd, "--bytecode=4.7.2",
             "--decompile=res://scripts/mod_manager.gdc", cwd=wd)
    gd = os.path.join(wd, "mod_manager.gd")
    if not os.path.isfile(gd):
        sys.exit("反编译未产出 .gd")
    return open(gd, encoding="utf-8").read()


def compile_gd(wd, gdpath, outdir):
    os.makedirs(outdir, exist_ok=True)
    rel_out = os.path.relpath(outdir, wd).replace("\\", "/")   # 输出相对 cwd 解析
    run_gdre("--headless", "--path", wd, "--bytecode=4.7.2",
             f"--compile={os.path.basename(gdpath)}", f"--output={rel_out}", cwd=wd)
    gdc = os.path.join(outdir, os.path.basename(gdpath)[:-3] + ".gdc")
    if not os.path.isfile(gdc):
        sys.exit("重编译未产出 .gdc")
    return open(gdc, "rb").read()


def gdc_from_pck_named(pck_path, fname):
    """同 gdc_from_pck, 但按文件名取任意条目 (merge_pr_items 用)."""
    out = tempfile.mkdtemp(prefix="czt_ex_")
    run_gdre("--headless", f"--extract={pck_path}", f"--output={out}")
    for root, _, files in os.walk(out):
        for f in files:
            if f == fname:
                return open(os.path.join(root, f), "rb").read()
    sys.exit(f"pck 里没找到 {fname}")


def decompile_named(wd, gdc, name):
    """同 decompile, 但文件名任意 (输出也按输入名落在 cwd)."""
    src = os.path.join(wd, "scripts")
    os.makedirs(src, exist_ok=True)
    open(os.path.join(src, name + ".gdc"), "wb").write(gdc)
    open(os.path.join(wd, "project.godot"), "w").write(
        '[application]\n\nconfig/name="mm"\nconfig/features=PackedStringArray("4.7")\n')
    run_gdre("--headless", "--path", wd, "--bytecode=4.7.2",
             f"--decompile=res://scripts/{name}.gdc", cwd=wd)
    gd = os.path.join(wd, name + ".gd")
    if not os.path.isfile(gd):
        sys.exit("反编译未产出 .gd")
    return open(gd, encoding="utf-8").read()


def write_gd_named(wd, text, name):
    p = os.path.join(wd, name + ".gd")
    open(p, "w", encoding="utf-8").write(text)
    return p


def inject_named(pck_path, res_path, new_gdc, tag):
    tmp = os.path.join(tempfile.gettempdir(), f"czt_{tag}_new.gdc")
    open(tmp, "wb").write(new_gdc)
    head = open(pck_path, "rb").read(16)
    ver, minor = int.from_bytes(head[4:8], "little"), int.from_bytes(head[8:12], "little")
    ev = f"{ver}.{minor}.0"
    out = pck_path + ".new"
    run_gdre("--headless", f"--pck-patch={pck_path}",
             f"--patch-file={tmp}={res_path}", f"--pck-version={ver}",
             f"--pck-engine-version={ev}", f"--output={out}")
    if not os.path.isfile(out):
        sys.exit("pck-patch 未产出新 pck")
    os.replace(out, pck_path)
    print("已写回:", pck_path)


def plain(gdc):
    assert gdc[:4] == GDC_MAGIC, "不是 GDSC 字节码"
    return zstandard.ZstdDecompressor().decompressobj().decompress(gdc[12:])


def inject(pck_path, new_gdc):
    """重打整个 pck: 其余条目原样保留 (含补丁替换的 14 个 .gdc), 仅替换 mod_manager."""
    tmp = os.path.join(tempfile.gettempdir(), "czt_mm_new.gdc")
    open(tmp, "wb").write(new_gdc)
    head = open(pck_path, "rb").read(16)
    ver, minor = int.from_bytes(head[4:8], "little"), int.from_bytes(head[8:12], "little")
    ev = f"{ver}.{minor}.0"   # 索引带 v4.5+ 的 sha256 字段, 必须 4.5+ 引擎写回 (gdRE 内置 4.8)
    out = pck_path + ".new"
    run_gdre("--headless", f"--pck-patch={pck_path}",
             f"--patch-file={tmp}={RES_PATH}", f"--pck-version={ver}",
             f"--pck-engine-version={ev}", f"--output={out}")
    if not os.path.isfile(out):
        sys.exit("pck-patch 未产出新 pck")
    os.replace(out, pck_path)
    print("已写回:", pck_path)


def main():
    global GDRE_DIR
    args = [a for a in sys.argv[1:] if a != "--check"]
    check_only = "--check" in sys.argv[1:]
    if len(args) < 2:
        sys.exit(__doc__)
    GDRE_DIR, pck = os.path.abspath(args[0]), os.path.abspath(args[1])
    orig = gdc_from_pck(pck)
    with tempfile.TemporaryDirectory(prefix="czt_mm_w_") as wd:
        # 1) 无损自检: 原样往返必须字节一致
        gd0 = decompile(wd, orig)
        rt = compile_gd(wd, write_gd(wd, gd0), os.path.join(wd, "rt"))
        if rt != orig:
            n = sum(1 for i in range(min(len(rt), len(orig))) if rt[i] != orig[i])
            sys.exit(f"无损自检失败: 往返与原 .gdc 不一致 (差异 {n} 字节); "
                     "gdRE 版本/字节码可能与该发行补丁不符, 拒绝修改")
        print("无损自检通过: 反编译→重编译与原 .gdc 字节一致")
        if check_only:
            return
        # 2) ROOT 改便携路径 → 重编译
        m = ROOT_RE.search(gd0)
        if not m:
            sys.exit("没找到 ROOT = \"user://mods\" 行; 补丁版结构可能已变, 请人工核对")
        newgdc = compile_gd(wd, write_gd(wd, ROOT_RE.sub(NEW_ROOT, gd0, count=1)),
                            os.path.join(wd, "fin"))
        p = plain(newgdc)
        assert p.count(b"user://mods") >= 1, "回退常量丢失"
        assert len(newgdc) > len(orig), "尺寸未变, 改动可能没编进去"
        inject(pck, newgdc)
        print(f"完成: mod_manager Mod 目录已改 Portable.path_in (gdc {len(orig)}→{len(newgdc)}B); "
              "便携下 Mod 直接扫 <程序目录>/userdata/mods, 非便携行为不变.")


def write_gd(wd, text):
    p = os.path.join(wd, "mod_manager.gd")
    open(p, "w", encoding="utf-8").write(text)
    return p


if __name__ == "__main__":
    main()
