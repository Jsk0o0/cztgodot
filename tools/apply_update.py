"""自动更新的替换程序: 游戏下载好更新包 (zip) 后启动它, 自己退出; 这里等游戏退出, 把新文件换进安装目录, 再启动游戏

由发行版的提取程序执行 (extractor/czt_extract.exe --apply-update ...), 因为 Windows 下游戏运行时 czt.exe / czt.pck 不能覆盖。
  extractor --apply-update <zip> --sha256 <hex> --target <安装目录> --wait-pid <游戏进程号> --relaunch <czt.exe>
流程:
  1. 等游戏进程退出 (最多 60 秒)
  2. 核对 zip 的 sha256 (游戏已按签名过的清单核对过, 这里再核一次, 防止中间被换); 检查条目路径 (不许绝对路径 / ..)
  3. 先整个解压到 <安装目录>/update/staging/, 解压失败不碰安装目录
  4. 逐个替换: 内容相同的跳过; 旧文件改名为 <名>.czt-old (运行中的 exe / dll 不能删, 但能改名, 提取程序替换自己也靠这个), 新文件移进去
     任何一步失败 → 按相反顺序撤销 (删掉新放进去的, 旧文件改回原名), 安装目录回到更新前
  5. 删得掉的 .czt-old 当场删, 删不掉的 (自己正在运行的文件) 记到 update/cleanup.txt, 游戏下次启动时删
  6. 启动游戏: czt.exe -- --update-result=ok|fail:<原因>, 游戏据此显示结果
只替换 zip 里有的文件: 提取结果 (extracted/)、素材包 (packs/)、存档 (用户数据目录) 都不碰。
日志: <安装目录>/update/apply.log
"""
import hashlib
import os
import shutil
import subprocess
import sys
import time
import zipfile

OLD = '.czt-old'


class Log:
    def __init__(self, path):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        self.f = open(path, 'a', encoding='utf-8')

    def __call__(self, *a):
        s = time.strftime('%Y-%m-%d %H:%M:%S ') + ' '.join(str(x) for x in a)
        self.f.write(s + '\n')
        self.f.flush()
        print(*a, flush=True)


def sha256_file(p):
    h = hashlib.sha256()
    with open(p, 'rb') as f:
        for b in iter(lambda: f.read(1 << 20), b''):
            h.update(b)
    return h.hexdigest()


def wait_pid(pid, timeout=60.0):
    """等进程退出; 返回 True = 已退出"""
    if pid <= 0:
        return True
    if os.name == 'nt':
        import ctypes
        k = ctypes.windll.kernel32
        h = k.OpenProcess(0x00100000, False, pid)   # SYNCHRONIZE
        if not h:
            return True   # 已经没有这个进程
        try:
            return k.WaitForSingleObject(h, int(timeout * 1000)) == 0
        finally:
            k.CloseHandle(h)
    t = time.time() + timeout
    while time.time() < t:
        try:
            os.kill(pid, 0)
        except OSError:
            return True
        time.sleep(0.2)
    return False


def safe_names(z):
    """zip 条目 → 相对路径列表 (只要文件); 有绝对路径 / .. / 盘符的直接拒绝"""
    out = []
    for i in z.infolist():
        n = i.filename.replace('\\', '/')
        if n.endswith('/'):
            continue
        parts = n.split('/')
        if n.startswith('/') or ':' in parts[0] or any(p in ('', '.', '..') for p in parts):
            raise ValueError('更新包里有不安全的路径: %r' % i.filename)
        if parts[-1].endswith(OLD):
            raise ValueError('更新包里有保留的文件名: %r' % i.filename)
        out.append((i, os.path.join(*parts)))
    return out


def _aside(dst):
    """旧文件改名让位; 之前留下的同名 .czt-old 先删, 删不掉就换个名字"""
    for k in range(100):
        old = dst + OLD + ('' if k == 0 else str(k))
        if os.path.exists(old):
            try:
                os.remove(old)
            except OSError:
                continue
        os.rename(dst, old)
        return old
    raise OSError('无法给旧文件改名: ' + dst)


def apply(zip_path, sha, target, log, pending):
    """换文件; 成功返回 (替换数, 跳过数), 失败抛异常 (安装目录已撤销回原样); 删不掉的旧文件加进 pending"""
    if sha and sha256_file(zip_path).lower() != sha.lower():
        raise ValueError('更新包校验失败 (sha256 不符)')
    staging = os.path.join(target, 'update', 'staging')
    shutil.rmtree(staging, ignore_errors=True)
    with zipfile.ZipFile(zip_path) as z:
        names = safe_names(z)
        if not any(rel == 'czt.pck' for _, rel in names):
            raise ValueError('更新包里没有 czt.pck, 不像是本游戏的更新包')
        for info, rel in names:
            p = os.path.join(staging, rel)
            os.makedirs(os.path.dirname(p), exist_ok=True)
            with z.open(info) as src, open(p, 'wb') as dst:
                shutil.copyfileobj(src, dst, 1 << 20)
    done = []   # (目标, 旧文件改名后的路径 或 None)
    skipped = 0
    try:
        for _, rel in names:
            new, dst = os.path.join(staging, rel), os.path.join(target, rel)
            if os.path.isfile(dst) and os.path.getsize(dst) == os.path.getsize(new) and sha256_file(dst) == sha256_file(new):
                skipped += 1
                continue
            if os.path.isdir(dst):
                raise ValueError('安装目录里同名的是文件夹, 不替换: ' + rel)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            old = _aside(dst) if os.path.exists(dst) else None
            done.append((dst, old))
            os.replace(new, dst)
    except Exception:
        log('替换失败, 撤销已换的 %d 个文件' % len(done))
        for dst, old in reversed(done):
            try:
                if os.path.exists(dst):   # 新放进去的 (删不掉就改名让位, 下面清理)
                    try:
                        os.remove(dst)
                    except OSError:
                        os.replace(dst, dst + '.czt-new')
                        pending.append(dst + '.czt-new')
                if old is not None:
                    os.replace(old, dst)
            except OSError as e:
                log('撤销出错', dst, e)
        raise
    finally:
        shutil.rmtree(staging, ignore_errors=True)
    for dst, old in done:
        if old is None:
            continue
        try:
            os.remove(old)
        except OSError:
            pending.append(old)   # 正在运行的文件 (提取程序自己), 游戏下次启动时删
    return len(done), skipped


def _note_cleanup(target, pending):
    if pending:
        with open(os.path.join(target, 'update', 'cleanup.txt'), 'a', encoding='utf-8') as f:
            f.writelines(os.path.relpath(p, target) + '\n' for p in pending)


def relaunch(exe, target, result, log):
    if not exe:
        return
    args = [exe, '--', '--update-result=' + result]
    log('启动游戏', args)
    kw = {'cwd': target, 'close_fds': True}
    if os.name == 'nt':
        kw['creationflags'] = 0x00000008 | 0x00000200   # DETACHED_PROCESS | CREATE_NEW_PROCESS_GROUP
    try:
        subprocess.Popen(args, **kw)
    except OSError as e:
        log('启动游戏失败', e)


def main(a):
    target = os.path.abspath(a.target)
    log = Log(os.path.join(target, 'update', 'apply.log'))
    log('开始更新', a.apply_update, '→', target)
    if not wait_pid(a.wait_pid):
        log('FAIL 游戏 60 秒内没有退出')
        relaunch(a.relaunch, target, 'fail:游戏没有退出', log)
        return 1
    pending = []
    try:
        n, skipped = apply(a.apply_update, a.sha256, target, log, pending)
    except Exception as e:  # noqa: BLE001
        log('FAIL', repr(e))
        _note_cleanup(target, pending)
        relaunch(a.relaunch, target, 'fail:' + str(e)[:200], log)
        return 1
    _note_cleanup(target, pending)
    try:
        os.remove(a.apply_update)
    except OSError:
        pass
    log('OK 替换 %d 个, 相同跳过 %d 个, 待删旧文件 %d 个' % (n, skipped, len(pending)))
    relaunch(a.relaunch, target, 'ok', log)
    return 0
