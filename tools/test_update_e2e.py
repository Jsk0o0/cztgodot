"""自动更新端到端测试 (本机, 不碰 CNB): python tools/test_update_e2e.py <Godot 可执行文件>
本地 http 服务器模拟 CNB: /api/raw/<文件> 要令牌 (清单); /api/dl/<文件> 要令牌, 302 跳到 /cos/<文件> (模拟对象存储: 带令牌就拒绝)
用 tools/release.py local 打 build 99 的主程序包 + 提取程序包 (里面是调 tools/extractor.py 的包装脚本) + 测试密钥签名的清单
  1. 有旧提取程序 (没记录包版本) 的安装目录: 先自动下载新提取程序, 再下载主程序 → 退出 → 替换 → 重启带 ok
  2. 没有提取程序、也没有素材: 自动下载提取程序装到 extractor/, 接着进入提取流程
  3. 不该更新的: 签名被改、换了公钥、主程序包被换、平台不对、令牌不对、服务器不在
输出 UE ok / UE FAIL ..., 最后 UE PASS / UE FAIL
"""
import http.server
import json
import os
import shutil
import socketserver
import subprocess
import sys
import tempfile
import threading
import time
import zipfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
PY = sys.executable
GODOT = sys.argv[1]
TOKEN = 'test-read-token'
fails = []
hits = {'cos_with_auth': 0, 'api_no_auth': 0, 'head': 0}


def check(cond, what):
    print('UE %s %s' % ('ok  ' if cond else 'FAIL', what), flush=True)
    if not cond:
        fails.append(what)


def write(p, data, mode=0o644):
    os.makedirs(os.path.dirname(p), exist_ok=True)
    open(p, 'wb').write(data if isinstance(data, bytes) else data.encode('utf-8'))
    os.chmod(p, mode)


WRAPPER = '#!/bin/sh\nexec "%s" "%s" "$@"\n' % (PY, os.path.join(ROOT, 'tools', 'extractor.py'))


def serve(d):
    class H(http.server.SimpleHTTPRequestHandler):
        def __init__(self, *a, **k):
            super().__init__(*a, directory=d, **k)

        def log_message(self, *a):
            pass

        def _route(self, head):
            auth = self.headers.get('Authorization', '')
            p = self.path.split('?')[0]
            if p.startswith('/api/'):
                if auth != 'Bearer ' + TOKEN:
                    hits['api_no_auth'] += 1
                    self.send_error(401)
                    return
                if p.startswith('/api/dl/'):
                    self.send_response(302)
                    self.send_header('Location', '/cos/' + p[8:] + '?sig=presigned')
                    self.send_header('Content-Length', '0')
                    self.end_headers()
                    return
                self.path = '/' + p[len('/api/raw/'):]
            elif p.startswith('/cos/'):
                if auth:
                    hits['cos_with_auth'] += 1   # 令牌不该发给对象存储
                    self.send_error(403)
                    return
                self.path = '/' + p[5:]
            else:
                self.send_error(404)
                return
            super().do_HEAD() if head else super().do_GET()

        def do_GET(self):
            self._route(False)

        def do_HEAD(self):   # CNB 的 LFS 接口不支持 HEAD
            hits['head'] += 1
            self.send_error(404)

    s = socketserver.ThreadingTCPServer(('127.0.0.1', 0), H)
    s.daemon_threads = True
    threading.Thread(target=s.serve_forever, daemon=True).start()
    return s


def install(t, with_extractor=True):
    inst = os.path.join(t, '安装 目录')
    shutil.rmtree(inst, ignore_errors=True)
    write(os.path.join(inst, 'czt.pck'), b'old pck')
    write(os.path.join(inst, '说明.txt'), '旧说明')
    write(os.path.join(inst, 'packs', 'hd2.pck'), b'hd')
    if with_extractor:
        write(os.path.join(inst, 'extractor', 'czt_extract'), WRAPPER, 0o755)   # 旧版 (没有 .package_sha256)
    write(os.path.join(inst, 'relaunch.sh'), '#!/bin/sh\necho "$@" > "$(dirname "$0")/relaunched.txt"\n', 0o755)
    return inst


def run_game(inst, url, pub, token=TOKEN, extra=(), wait=40):
    args = [GODOT, '--headless', '--path', os.path.join(ROOT, 'godot'), 'res://scenes/title.tscn', '--',
            '--update-url=' + url, '--update-token=' + token, '--update-pubkey=' + pub, '--update-target=' + inst,
            '--update-relaunch=' + os.path.join(inst, 'relaunch.sh'),
            '--extractor=' + os.path.join(inst, 'extractor', 'czt_extract'), '--update-test', '--update-auto'] + list(extra)
    p = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, encoding='utf-8', errors='replace')
    try:
        out, _ = p.communicate(timeout=wait)
    except subprocess.TimeoutExpired:   # 没有更新时游戏停在标题画面, 不会自己退出
        p.kill()
        out, _ = p.communicate()
    return out


def wait_file(p, t=30):
    for _ in range(int(t * 10)):
        if os.path.exists(p):
            time.sleep(0.2)
            return True
        time.sleep(0.1)
    return False


def keypair(t, name):
    k = os.path.join(t, name + '.pem')
    subprocess.run(['openssl', 'genrsa', '-out', k, '2048'], check=True, capture_output=True)
    pub = k + '.pub'
    open(pub, 'wb').write(subprocess.run(['openssl', 'rsa', '-in', k, '-pubout'], check=True, capture_output=True).stdout)
    return k, pub


def main():
    t = tempfile.mkdtemp(prefix='czt_ue_')
    try:
        key, pub = keypair(t, 'test')
        _, other_pub = keypair(t, 'other')
        new = os.path.join(t, 'new')   # 新版本的发布目录 (相当于 out/win_lite)
        write(os.path.join(new, 'czt.exe'), b'new exe')
        write(os.path.join(new, 'czt.pck'), b'new pck')
        write(os.path.join(new, '说明.txt'), '新说明')
        write(os.path.join(new, 'extractor', 'czt_extract'), WRAPPER, 0o755)   # 不该进主程序包
        write(os.path.join(new, 'packs', 'hd2.pck'), b'should not ship')
        ext_zip = os.path.join(t, 'czt_extract.zip')
        with zipfile.ZipFile(ext_zip, 'w') as z:
            z.writestr('czt_extract', WRAPPER)
            z.writestr('_internal/marker.txt', 'new extractor')
        srv_dir = os.path.join(t, 'srv')
        s = serve(srv_dir)
        host = 'http://127.0.0.1:%d' % s.server_address[1]
        plat = {'darwin': 'macOS', 'win32': 'Windows'}.get(sys.platform, 'Linux')

        def release(platform=plat):
            r = subprocess.run([PY, os.path.join(ROOT, 'tools', 'release.py'), 'local', '--dir', new, '--extractor-zip', ext_zip,
                                '--serve', srv_dir, '--base-url', host + '/api/raw/', '--dl-base', host + '/api/dl/',
                                '--key', key, '--build', '99', '--platform', platform, '--notice', '测试公告'], capture_output=True, text=True)
            if r.returncode:
                print(r.stdout, r.stderr)
        release()
        url = host + '/api/raw/latest.json'
        m = json.load(open(os.path.join(srv_dir, 'latest.json'), encoding='utf-8'))
        check(m['build'] == 99 and m['zip']['url'].startswith(host + '/api/dl/') and 'extractor' in m, '清单: build / 下载地址 / 提取程序包')
        names = zipfile.ZipFile(os.path.join(srv_dir, 'czt_99.zip')).namelist()
        check(sorted(names) == ['czt.exe', 'czt.pck', '说明.txt'], '主程序包只有 czt.exe / czt.pck / 说明 (%s)' % names)

        # 1. 有旧提取程序: 先换提取程序, 再更新主程序
        inst = install(t)
        out = run_game(inst, url, pub)
        check('UPD checked build=99 newer=true required=false manual=false extractor_needed=true' in out, '读清单 (带令牌) + 验签')
        check('UPD downloaded extractor ok=true' in out, '先下载并装好新提取程序')
        check(open(os.path.join(inst, 'extractor', '_internal', 'marker.txt')).read() == 'new extractor', 'extractor/ 换成新的')
        check(open(os.path.join(inst, 'extractor', '.package_sha256')).read().strip() == m['extractor']['sha256'], '记下提取程序包版本')
        check('UPD downloaded app ok=true' in out, '再下载主程序包 (302 后不带令牌)')
        rel = os.path.join(inst, 'relaunched.txt')
        check(wait_file(rel) and '--update-result=ok' in open(rel).read(), '替换后重启, 带 ok')
        check(open(os.path.join(inst, 'czt.pck'), 'rb').read() == b'new pck', 'czt.pck 换成新版')
        check(open(os.path.join(inst, 'czt.exe'), 'rb').read() == b'new exe', 'czt.exe 换成新版')
        check(open(os.path.join(inst, 'packs', 'hd2.pck'), 'rb').read() == b'hd', 'packs/ 没被动')
        check(not os.path.exists(os.path.join(inst, 'update', 'czt_99.zip')), '更新包用完删掉')
        check(hits['cos_with_auth'] == 0, '令牌没有发给跳转后的地址 (对象存储)')
        check(hits['head'] == 0, '不发 HEAD (直接 GET)')

        # 1b. 没有提取程序 + 有新版本 (发行版第一次运行就遇到更新): 不能变成「手动下载」, 先下载提取程序再更新
        inst = install(t, with_extractor=False)
        out = run_game(inst, url, pub)
        check('UPD checked build=99 newer=true required=false manual=false extractor_needed=true' in out, '没有提取程序 + 新版本 → 可以自动更新 (manual=false)')
        check('UPD downloaded extractor ok=true' in out and 'UPD downloaded app ok=true' in out, '先装提取程序, 再下载主程序')
        rel = os.path.join(inst, 'relaunched.txt')
        check(wait_file(rel) and '--update-result=ok' in open(rel).read() and open(os.path.join(inst, 'czt.pck'), 'rb').read() == b'new pck',
              '替换后重启, czt.pck 是新版')

        # 2. 没有提取程序、没有素材 (游戏已是最新): 自动下载提取程序, 接着进入提取流程
        release()
        inst = install(t, with_extractor=False)
        empty = os.path.join(t, 'empty_extracted')
        os.makedirs(empty, exist_ok=True)
        # 当前版本也当成 99 (不出主程序更新): 用 --update-url 指向同一清单, build 99 > 1 会出更新, 所以单独签一份 build 1 的
        r = subprocess.run([PY, os.path.join(ROOT, 'tools', 'release.py'), 'local', '--dir', new, '--extractor-zip', ext_zip,
                            '--serve', srv_dir, '--base-url', host + '/api/raw/', '--dl-base', host + '/api/dl/',
                            '--key', key, '--build', '1', '--platform', plat], capture_output=True, text=True)
        out = run_game(inst, url, pub, extra=['--extracted=' + empty, '--no-music'], wait=25)
        check('UPD checked build=1 newer=false' in out and 'extractor_needed=true' in out, '没有提取程序 → 需要下载')
        check('UPD downloaded extractor ok=true' in out and os.path.exists(os.path.join(inst, 'extractor', 'czt_extract')),
              '自动下载提取程序装到 extractor/')
        check(os.access(os.path.join(inst, 'extractor', 'czt_extract'), os.X_OK), '提取程序可执行')
        check(open(os.path.join(inst, 'czt.pck'), 'rb').read() == b'old pck', '主程序不动')

        # 3. 不该更新的情况
        release()
        sig_path = os.path.join(srv_dir, 'latest.json.sig')
        good_sig = open(sig_path, 'rb').read()
        zip_path = os.path.join(srv_dir, 'czt_99.zip')
        good_zip = open(zip_path, 'rb').read()
        cases = [
            ('签名被改', lambda: open(sig_path, 'wb').write(good_sig[:10] + (b'A' if good_sig[10:11] != b'A' else b'B') + good_sig[11:]), pub, TOKEN, 'UPD checked none'),
            ('换了公钥', lambda: None, other_pub, TOKEN, 'UPD checked none'),
            ('令牌不对', lambda: None, pub, 'wrong', 'UPD checked none'),
            ('主程序包被换', lambda: open(zip_path, 'wb').write(good_zip[:-1] + bytes([good_zip[-1] ^ 1])), pub, TOKEN, 'UPD downloaded app ok=false 下载的文件校验失败'),
        ]
        for name, tamper, key_pub, tok, expect in cases:
            open(sig_path, 'wb').write(good_sig)
            open(zip_path, 'wb').write(good_zip)
            tamper()
            inst = install(t)
            out = run_game(inst, url, key_pub, token=tok)
            check(expect in out and open(os.path.join(inst, 'czt.pck'), 'rb').read() == b'old pck', '%s → 不更新 (%s)' % (name, expect))
        open(sig_path, 'wb').write(good_sig)
        open(zip_path, 'wb').write(good_zip)
        release('Plan9')
        inst = install(t)
        out = run_game(inst, url, pub)
        check('UPD checked none' in out, '平台不对 → 不更新')
        s.shutdown()
        s.server_close()
        inst = install(t)
        out = run_game(inst, url, pub)
        check('UPD checked none' in out, '服务器不在 → 不影响 (照常停在标题)')
    finally:
        shutil.rmtree(t, ignore_errors=True)
    print('UE', 'PASS' if not fails else 'FAIL %d' % len(fails))
    return 1 if fails else 0


if __name__ == '__main__':
    sys.exit(main())
