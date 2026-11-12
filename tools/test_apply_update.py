"""自动更新替换程序的测试: python tools/test_apply_update.py [提取程序 (打包后的 czt_extract, 省略则直接调 extractor.py)]
在临时目录里造一个假安装目录 (czt.exe / czt.pck / extractor/ / extracted/ / packs/), 做几个更新包, 逐项检查:
  成功替换 + 相同文件跳过 + 不碰 zip 以外的文件 + 等游戏进程退出 + 重新启动游戏 (带 --update-result=ok)
  替换途中失败 → 撤销回原样 (+ 启动游戏带 fail)
  路径穿越 (../) / sha256 不符 / 没有 czt.pck → 拒绝, 安装目录不变
  给了打包后的提取程序时: 用它 (从安装目录里的 extractor/ 运行) 做替换, 验证打包后的 --apply-update
输出 AU ok / AU FAIL ..., 最后 AU PASS / AU FAIL
"""
import hashlib
import io
import os
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
EXE = sys.argv[1] if len(sys.argv) > 1 else ''
fails = []


def check(cond, what):
    print('AU %s %s' % ('ok  ' if cond else 'FAIL', what), flush=True)
    if not cond:
        fails.append(what)


def write(p, data):
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, 'wb') as f:
        f.write(data if isinstance(data, bytes) else data.encode('utf-8'))


def read(p):
    with open(p, 'rb') as f:
        return f.read()


def make_zip(path, files):
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, 'w', zipfile.ZIP_DEFLATED) as z:
        for n, d in files.items():
            z.writestr(n, d)
    write(path, buf.getvalue())
    return hashlib.sha256(buf.getvalue()).hexdigest()


def snapshot(root):
    out = {}
    for d, _, fs in os.walk(root):
        for f in fs:
            p = os.path.join(d, f)
            r = os.path.relpath(p, root)
            if r.split(os.sep)[0] != 'update':
                out[r] = read(p)
    return out


def fake_game(launch):
    """假的 czt.exe: 一个 python 脚本, 被重新启动时把参数写进 relaunched.txt
    放在纯英文路径 (launch/): Windows 的 cmd.exe 按本地代码页 (GBK) 读 .cmd, 里面写中文路径会读错"""
    script = os.path.join(launch, 'fake_game.py')
    write(script, 'import sys,os\nopen(os.path.join(os.path.dirname(os.path.abspath(__file__)),"relaunched.txt"),"w",encoding="utf-8").write(" ".join(sys.argv[1:]))\n')
    return script


def setup(root):
    shutil.rmtree(root, ignore_errors=True)
    write(os.path.join(root, 'czt.pck'), b'old pck')
    write(os.path.join(root, '说明.txt'), '旧说明')
    write(os.path.join(root, 'extractor', 'data.bin'), b'same')
    write(os.path.join(root, 'extracted', '.steps', 'complete'), '1\n')
    write(os.path.join(root, 'packs', 'hd2.pck'), b'hd')
    if EXE:
        shutil.copytree(os.path.dirname(os.path.abspath(EXE)), os.path.join(root, 'extractor', 'bin'))


def run(root, zip_path, sha, wait_pid=0):
    launch = os.path.join(os.path.dirname(root), 'launch')
    shutil.rmtree(launch, ignore_errors=True)
    relaunch = [sys.executable, fake_game(launch)]
    if EXE:
        cmd = [os.path.join(root, 'extractor', 'bin', os.path.basename(EXE))]
    else:
        cmd = [sys.executable, os.path.join(HERE, 'extractor.py')]
    # --relaunch 只接受一个程序路径: 用一个包装脚本 (Windows 下 .cmd, 其他 .sh) 调假游戏
    if os.name == 'nt':
        w = os.path.join(launch, 'czt_launch.cmd')
        write(w, '@"%s" "%s" %%*\r\n' % tuple(relaunch))
    else:
        w = os.path.join(launch, 'czt_launch.sh')
        write(w, '#!/bin/sh\nexec "%s" "%s" "$@"\n' % tuple(relaunch))
        os.chmod(w, 0o755)
    cmd += ['--apply-update', zip_path, '--sha256', sha, '--target', root, '--wait-pid', str(wait_pid), '--relaunch', w]
    r = subprocess.run(cmd, capture_output=True, text=True, encoding='utf-8', errors='replace')
    out = os.path.join(launch, 'relaunched.txt')
    for _ in range(100):   # 游戏是脱离进程启动的, 等它写结果
        if os.path.exists(out):
            break
        time.sleep(0.1)
    time.sleep(0.2)
    return r, (read(out).decode('utf-8') if os.path.exists(out) else '')


def main():
    tmp = tempfile.mkdtemp(prefix='czt_au_')
    root = os.path.join(tmp, '安装 目录')   # 中文 + 空格
    try:
        # 1. 正常更新; 等一个还在跑的进程退出
        setup(root)
        before = snapshot(root)
        files = {'czt.pck': b'new pck', '说明.txt': '新说明'.encode('utf-8'), 'extractor/data.bin': b'same', 'extractor/new.txt': b'n'}
        sha = make_zip(os.path.join(root, 'update', 'u1.zip'), files)
        sleeper = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(2)'])
        threading.Thread(target=sleeper.wait, daemon=True).start()   # 及时回收, 否则退出后成了僵尸进程, 看起来还在
        t0 = time.time()
        r, rel = run(root, os.path.join(root, 'update', 'u1.zip'), sha, sleeper.pid)
        check(r.returncode == 0, '正常更新退出码 0 (%d) %s' % (r.returncode, (r.stdout + r.stderr)[-300:].replace('\n', ' | ')))
        check(time.time() - t0 >= 1.5, '等游戏进程退出才替换')
        check(read(os.path.join(root, 'czt.pck')) == b'new pck', 'czt.pck 已替换')
        check(read(os.path.join(root, '说明.txt')).decode('utf-8') == '新说明', '中文文件名已替换')
        check(os.path.exists(os.path.join(root, 'extractor', 'new.txt')), '新增文件')
        check(read(os.path.join(root, 'packs', 'hd2.pck')) == b'hd' and os.path.exists(os.path.join(root, 'extracted', '.steps', 'complete')), '不碰 zip 以外的文件 (packs / extracted)')
        check('--update-result=ok' in rel, '重新启动游戏并带 ok (%r)' % rel)
        check(not os.path.exists(os.path.join(root, 'update', 'u1.zip')), '更新包用完删掉')
        check(not os.path.exists(os.path.join(root, 'czt.pck.czt-old')), '旧文件删掉')
        log = read(os.path.join(root, 'update', 'apply.log')).decode('utf-8')
        check('相同跳过 1' in log or '相同跳过' in log, '日志记下替换 / 跳过数')

        # 2. 替换途中失败 → 撤销 (目标位置是个目录, 新文件放不进去)
        setup(root)
        os.makedirs(os.path.join(root, 'zzz_dir'))
        write(os.path.join(root, 'zzz_dir', 'keep'), b'k')
        before = snapshot(root)
        sha = make_zip(os.path.join(root, 'update', 'u2.zip'), {'czt.pck': b'new pck', '说明.txt': b'x', 'zzz_dir': b'file over dir'})
        r, rel = run(root, os.path.join(root, 'update', 'u2.zip'), sha)
        check(r.returncode == 1, '替换失败退出码 1')
        after = snapshot(root)
        check(after == before, '失败后撤销, 安装目录和更新前完全一样 %s' % sorted(k for k in set(before) | set(after) if before.get(k) != after.get(k)))
        check('--update-result=fail:' in rel, '失败也重新启动游戏, 带 fail (%r)' % rel[:80])

        # 3. 拒绝: 路径穿越 / sha 不符 / 没有 czt.pck
        for name, files, bad_sha in [('路径穿越', {'czt.pck': b'p', '../evil.txt': b'e'}, False),
                                     ('sha256 不符', {'czt.pck': b'p'}, True),
                                     ('没有 czt.pck', {'other.txt': b'o'}, False)]:
            setup(root)
            before = snapshot(root)
            sha = make_zip(os.path.join(root, 'update', 'u3.zip'), files)
            r, rel = run(root, os.path.join(root, 'update', 'u3.zip'), '0' * 64 if bad_sha else sha)
            after = snapshot(root)
            diff = sorted(k for k in set(before) | set(after) if before.get(k) != after.get(k))
            check(r.returncode == 1 and not diff and not os.path.exists(os.path.join(tmp, 'evil.txt')),
                  '拒绝%s, 安装目录不变 (退出码 %d, 变化 %s)' % (name, r.returncode, diff))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    for f in fails:
        print('AU 失败项:', f)
    print('AU', 'PASS' if not fails else 'FAIL %d' % len(fails))
    return 1 if fails else 0


if __name__ == '__main__':
    if hasattr(sys.stdout, 'reconfigure'):
        sys.stdout.reconfigure(encoding='utf-8')
    sys.exit(main())
