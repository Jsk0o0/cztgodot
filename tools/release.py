"""发布自动更新到 CNB 仓库 corumol/swd (私有; 只在作者本机跑, 写令牌和私钥不进游戏)

两个包, 都用 Git LFS 放在仓库 czt/pkg/ (游戏经 OpenAPI GET /{repo}/-/lfs/{oid}?name= 下载, oid = sha256, 只要 repo-code:r):
  主程序包 czt_<BUILD>.zip   = 发布目录里的 czt.exe / czt.pck / 说明.txt (不含 extractor/ extracted/ packs/ update/)
  提取程序包 czt_extract_<sha前8位>.zip = 作者在 Windows 上打包好的 czt_extract (zip 根目录直接是 czt_extract.exe ...)
  高清放大程序包 czt_esrgan_<sha前8位>.zip = Real-ESRGAN ncnn Vulkan Windows 版 (realesrgan-ncnn-vulkan.exe + vcomp140 + animevideov3 x2 模型 + LICENSE)
      内容没变就沿用 (同名文件已在仓库里)
清单 czt/latest.json + czt/latest.json.sig 推到仓库 main 分支 (游戏用内置只读令牌经 OpenAPI 读)

  python tools/release.py publish --dir out/win_lite --extractor-zip <czt_extract.zip> [--min-build N] [公告参数]
        浅克隆 swd → 包放进 czt/pkg/ 推送 (LFS) → 用读令牌按游戏的方式 (第一跳带令牌、跳转后不带) 下载核对 sha256 →
        清单签名推送 → 读回比对
  python tools/release.py local --dir <发布目录> --extractor-zip <zip> --serve <目录> --base-url <清单所在 URL 前缀> [--dl-base <附件 URL 前缀>] --key <测试私钥>
        本地测试: 包 + 清单 + 签名写到 <目录> (tools/test_update_e2e.py 用)
  公告参数: --notice-title 标题 --notice-file 文本文件 (或 --notice 文本); 公告 id 默认 = BUILD (游戏每个 id 只弹一次)

版本号从 godot/scripts/game.gd 的 BUILD / VERSION 读 (发布前先把 BUILD 加 1)。签名: openssl dgst -sha256 -sign (PKCS#1 v1.5), base64。
令牌: 项目根目录 .cnbkey 的「swd-publish」(推送) / 「swd-read」(核对, 和游戏内置的同一个) 段;
  只放在请求头 / git 的 http.extraHeader 环境变量里, 不打印、不写日志。
CNB 接口 (https://api.cnb.cool/swagger.json): 读文件 GET /{repo}/-/git/raw/{分支}/{路径}; LFS 下载 GET /{slug}/-/lfs/{oid} (302)
"""
import argparse
import base64
import datetime
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request
import zipfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
API = 'https://api.cnb.cool'
WEB = 'https://cnb.cool'
REPO = 'corumol/swd'
MANIFEST_PATH = 'czt/latest.json'   # 同 godot/scripts/updater.gd 的 MANIFEST_URL
PKG_DIR = 'czt/pkg'                 # 更新包 (Git LFS)
APP_FILES_SKIP = {'update', 'extracted', 'packs', 'extractor'}   # 不进主程序包


def version():
    s = open(os.path.join(ROOT, 'godot', 'scripts', 'game.gd'), encoding='utf-8').read()
    return int(re.search(r'^const BUILD := (\d+)', s, re.M).group(1)), re.search(r'^const VERSION := "([^"]+)"', s, re.M).group(1)


def sha256_file(p):
    h = hashlib.sha256()
    with open(p, 'rb') as f:
        for b in iter(lambda: f.read(1 << 20), b''):
            h.update(b)
    return h.hexdigest()


def pack_app(src, out_zip):
    """发布目录 → 主程序包: 只放根目录下的程序文件和说明 (子目录都不放: extractor/ 单独发, 其余是玩家本机生成的)"""
    if not os.path.isfile(os.path.join(src, 'czt.pck')) or not os.path.isfile(os.path.join(src, 'czt.exe')):
        sys.exit('%s 里没有 czt.exe / czt.pck (先 make win-lite)' % src)
    os.makedirs(os.path.dirname(out_zip), exist_ok=True)
    names = []
    with zipfile.ZipFile(out_zip + '.part', 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for f in sorted(os.listdir(src)):
            p = os.path.join(src, f)
            if os.path.isdir(p) or f == '.DS_Store' or '.czt-old' in f or f.endswith('.czt-new'):
                continue
            z.write(p, f)
            names.append(f)
    os.replace(out_zip + '.part', out_zip)
    print('主程序包 %s: %s, %.1f MB' % (os.path.basename(out_zip), ' '.join(names), os.path.getsize(out_zip) / 1048576))


def check_extractor_zip(p):
    with zipfile.ZipFile(p) as z:
        names = z.namelist()
    if not any(n in ('czt_extract.exe', 'czt_extract') for n in names):
        sys.exit('%s 的根目录里没有 czt_extract.exe (打包时直接压缩 czt_extract 文件夹里面的内容)' % p)
    bad = [n for n in names if n.startswith('/') or '..' in n.split('/') or ':' in n or '\\' in n]
    if bad:
        sys.exit('提取程序包里有不安全的路径: %s' % bad[:3])
    print('提取程序包 %s: %d 个文件, %.1f MB' % (os.path.basename(p), len(names), os.path.getsize(p) / 1048576))


def pkg(path, url):
    return {'url': url, 'size': os.path.getsize(path), 'sha256': sha256_file(path)}


def manifest(a, build, ver, app, ext, esr=None):
    d = {'build': build, 'version': ver, 'min_build': a.min_build, 'platform': a.platform,
         'date': datetime.date.today().isoformat(), 'zip': app}
    if ext:
        d['extractor'] = ext
    if esr:
        d['esrgan'] = esr
    text = a.notice or (open(a.notice_file, encoding='utf-8').read().strip() if a.notice_file else '')
    if text:
        d['notice'] = {'id': a.notice_id or str(build), 'title': a.notice_title, 'text': text}
    if a.page:
        d['page'] = a.page
    return json.dumps(d, ensure_ascii=False, indent=1, sort_keys=True).encode('utf-8')


def sign(data, key):
    with tempfile.TemporaryDirectory() as t:
        p = os.path.join(t, 'm')
        open(p, 'wb').write(data)
        sig = subprocess.run(['openssl', 'dgst', '-sha256', '-sign', key, p], capture_output=True, check=True).stdout
        open(os.path.join(t, 'pub'), 'wb').write(subprocess.run(['openssl', 'rsa', '-in', key, '-pubout'], capture_output=True, check=True).stdout)
        open(os.path.join(t, 's'), 'wb').write(sig)
        if subprocess.run(['openssl', 'dgst', '-sha256', '-verify', os.path.join(t, 'pub'), '-signature', os.path.join(t, 's'), p],
                          capture_output=True).returncode != 0:
            sys.exit('签名自检失败')
    return base64.b64encode(sig) + b'\n'


def cmd_local(a):
    build, ver = version()
    if a.build:   # 测试: 假装是更新的版本
        build, ver = a.build, '%s-test%d' % (ver, a.build)
    os.makedirs(a.serve, exist_ok=True)
    dl = a.dl_base or a.base_url
    z = os.path.join(a.serve, 'czt_%d.zip' % build)
    pack_app(a.dir, z)
    ext = None
    if a.extractor_zip:
        check_extractor_zip(a.extractor_zip)
        e = os.path.join(a.serve, 'czt_extract.zip')
        if os.path.abspath(a.extractor_zip) != os.path.abspath(e):
            open(e, 'wb').write(open(a.extractor_zip, 'rb').read())
        ext = pkg(e, dl + 'czt_extract.zip')
    m = manifest(a, build, ver, pkg(z, dl + os.path.basename(z)), ext)
    open(os.path.join(a.serve, 'latest.json'), 'wb').write(m)
    open(os.path.join(a.serve, 'latest.json.sig'), 'wb').write(sign(m, a.key))
    print('清单 build %d → %s' % (build, os.path.join(a.serve, 'latest.json')))


# ---------------- CNB ----------------

def cnb_token(name):
    """.cnbkey 里某个令牌段的 Token; 不打印"""
    s = open(os.path.join(ROOT, '.cnbkey'), encoding='utf-8').read()
    m = re.search(r'令牌名:\s*%s\b.*?Token:\s*(\S+)' % re.escape(name), s, re.S)
    if not m:
        sys.exit('.cnbkey 里找不到 %s 令牌' % name)
    return m.group(1)


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *a, **k):
        return None


def game_get(url, token):
    """按游戏的方式下载: 第一跳带令牌、不跟随跳转; 跳转地址不带令牌"""
    op = urllib.request.build_opener(_NoRedirect)
    req = urllib.request.Request(url, headers={'Authorization': 'Bearer ' + token})
    try:
        with op.open(req, timeout=600) as r:
            return r.read()
    except urllib.error.HTTPError as e:
        if e.code not in (301, 302, 303, 307, 308):
            raise RuntimeError('下载 %s → HTTP %d %s' % (url.split('?')[0], e.code, e.read()[:200]))
        loc = urllib.parse.urljoin(url, e.headers['Location'])
    with urllib.request.urlopen(urllib.request.Request(loc), timeout=600) as r:
        return r.read()


def lfs_url(sha, name):
    """LFS 对象的下载地址 (oid = 文件的 sha256): GET /{repo}/-/lfs/{oid}?name=, 要令牌 repo-code:r, 302 到预签名地址"""
    return '%s/%s/-/lfs/%s?name=%s' % (API, REPO, sha, urllib.parse.quote(name))


class Repo:
    """swd 仓库的浅克隆; 令牌只放在 git / git-lfs 的 http.extraHeader 环境变量里"""
    def __init__(self, token, tmp):
        self.env = dict(os.environ, GIT_CONFIG_COUNT='1', GIT_CONFIG_KEY_0='http.extraHeader',
                        GIT_CONFIG_VALUE_0='Authorization: Basic ' + base64.b64encode(('cnb:' + token).encode()).decode(),
                        GIT_TERMINAL_PROMPT='0', GIT_LFS_SKIP_SMUDGE='1')   # 不下载已有的 LFS 文件 (旧版本的包)
        self.dir = os.path.join(tmp, 'r')
        self.git('clone', '--depth', '1', '--branch', 'main', '%s/%s.git' % (WEB, REPO), self.dir, cwd=tmp)
        self.git('lfs', 'install', '--local')

    def git(self, *a, cwd=None):
        r = subprocess.run(['git'] + list(a), cwd=cwd or self.dir, env=self.env, capture_output=True, text=True)
        if r.returncode != 0:
            raise RuntimeError('git %s 失败: %s' % (a[0], (r.stderr or r.stdout)[-300:]))
        return r.stdout

    def write(self, rel, data):
        p = os.path.join(self.dir, rel)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        open(p, 'wb').write(data)

    def commit_push(self, paths, msg):
        self.git('add', *paths)
        if not self.git('status', '--porcelain'):
            print('没有变化, 不提交:', msg)
            return
        self.git('-c', 'user.name=czt-release', '-c', 'user.email=release@localhost', 'commit', '-m', msg)
        self.git('push', 'origin', 'main')
        print('已推送:', msg)


def previous_manifest(read):
    try:
        return json.loads(game_get('%s/%s/-/git/raw/main/%s' % (API, REPO, MANIFEST_PATH), read))
    except Exception:  # noqa: BLE001  第一次发布还没有
        return {}


def cmd_publish(a):
    build, ver = version()
    write, read = cnb_token('swd-publish'), cnb_token('swd-read')
    out = os.path.join(ROOT, 'out', 'release', str(build))
    app_zip = os.path.join(out, 'czt_%d.zip' % build)
    pack_app(a.dir, app_zip)
    check_extractor_zip(a.extractor_zip)
    prev = previous_manifest(read)
    if prev.get('build', 0) >= build:
        sys.exit('仓库里已经是 build %s, 先把 game.gd 的 BUILD 加 1' % prev.get('build'))
    app_sha, ext_sha = sha256_file(app_zip), sha256_file(a.extractor_zip)
    app_name, ext_name = os.path.basename(app_zip), 'czt_extract_%s.zip' % ext_sha[:8]
    with tempfile.TemporaryDirectory() as t:
        repo = Repo(write, t)
        # 1. 两个包进 czt/pkg/ (LFS); 主程序包只留最近 3 个版本的文件 (LFS 对象本身还在, 旧清单指向的地址仍可下载)
        attr = os.path.join(repo.dir, '.gitattributes')
        rule = PKG_DIR + '/*.zip filter=lfs diff=lfs merge=lfs -text\n'
        old_attr = open(attr, encoding='utf-8').read() if os.path.exists(attr) else ''
        if rule not in old_attr:
            repo.write('.gitattributes', (old_attr + ('' if old_attr.endswith('\n') or not old_attr else '\n') + rule).encode('utf-8'))
        repo.write(PKG_DIR + '/' + app_name, open(app_zip, 'rb').read())
        if not os.path.exists(os.path.join(repo.dir, PKG_DIR, ext_name)):
            repo.write(PKG_DIR + '/' + ext_name, open(a.extractor_zip, 'rb').read())
        # 高清放大程序包 (Real-ESRGAN ncnn Vulkan): 给了就用新的, 没给沿用上一版清单里的
        esr = prev.get('esrgan')
        if a.esrgan_zip:
            es = sha256_file(a.esrgan_zip)
            es_name = 'czt_esrgan_%s.zip' % es[:8]
            if not os.path.exists(os.path.join(repo.dir, PKG_DIR, es_name)):
                repo.write(PKG_DIR + '/' + es_name, open(a.esrgan_zip, 'rb').read())
            esr = {'url': lfs_url(es, es_name), 'size': os.path.getsize(a.esrgan_zip), 'sha256': es}
        apps = sorted((f for f in os.listdir(os.path.join(repo.dir, PKG_DIR)) if re.fullmatch(r'czt_\d+\.zip', f)),
                      key=lambda f: int(f[4:-4]))
        for f in apps[:-3]:
            repo.git('rm', '-q', PKG_DIR + '/' + f)
        keep_esr = 'czt_esrgan_%s.zip' % esr['sha256'][:8] if esr else ''
        exts = [f for f in os.listdir(os.path.join(repo.dir, PKG_DIR))
                if f.startswith('czt_extract_') and f != ext_name or f.startswith('czt_esrgan_') and f != keep_esr]
        for f in exts:
            repo.git('rm', '-q', PKG_DIR + '/' + f)
        repo.commit_push(['.gitattributes', PKG_DIR], '更新包 build %d' % build)
        # 2. 用读令牌按游戏的方式下载核对 (清单之前: 不会发布指向不存在文件的清单)
        app = {'url': lfs_url(app_sha, app_name), 'size': os.path.getsize(app_zip), 'sha256': app_sha}
        ext = {'url': lfs_url(ext_sha, ext_name), 'size': os.path.getsize(a.extractor_zip), 'sha256': ext_sha}
        for p in [app, ext] + ([esr] if esr else []):
            if hashlib.sha256(game_get(p['url'], read)).hexdigest() != p['sha256']:
                sys.exit('用读令牌下载 %s 的 sha256 不符' % p['url'])
            print('读令牌下载核对通过', p['url'].split('?')[0])
        # 3. 清单 + 签名
        m = manifest(a, build, ver, app, ext, esr)
        sig = sign(m, a.key)
        open(os.path.join(out, 'latest.json'), 'wb').write(m)
        open(os.path.join(out, 'latest.json.sig'), 'wb').write(sig)
        repo.write(MANIFEST_PATH, m)
        repo.write(MANIFEST_PATH + '.sig', sig)
        repo.commit_push([MANIFEST_PATH, MANIFEST_PATH + '.sig'], '更新清单 build %d (%s)' % (build, ver))
    raw = '%s/%s/-/git/raw/main/%s' % (API, REPO, MANIFEST_PATH)
    if game_get(raw, read) != m or game_get(raw + '.sig', read) != sig:
        sys.exit('读回来的清单和刚推的不一样 (可能有缓存, 稍后再查)')
    print('发布完成 build %d (%s)' % (build, ver))


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest='cmd', required=True)
    for name in ('local', 'publish'):
        p = sub.add_parser(name)
        p.add_argument('--dir', default=os.path.join(ROOT, 'out', 'win_lite'))
        p.add_argument('--extractor-zip', default='', required=(name == 'publish'))
        p.add_argument('--esrgan-zip', default='', help='高清放大程序包 (out/release/czt_esrgan.zip); 不给就沿用上一版')
        p.add_argument('--key', default=os.path.expanduser('~/.config/czt-pod/author.pem'))
        p.add_argument('--min-build', type=int, default=0)
        p.add_argument('--platform', default='Windows')
        p.add_argument('--notice', default='')
        p.add_argument('--notice-file', default='')
        p.add_argument('--notice-title', default='公告')
        p.add_argument('--notice-id', default='')
        p.add_argument('--page', default='', help='手动下载页 (装在没有写入权限的目录时给玩家看)')
    lp = sub.choices['local']
    lp.add_argument('--serve', required=True)
    lp.add_argument('--base-url', required=True)
    lp.add_argument('--dl-base', default='')
    lp.add_argument('--build', type=int, default=0, help='测试用: 覆盖 game.gd 的 BUILD')
    a = ap.parse_args()
    cmd_local(a) if a.cmd == 'local' else cmd_publish(a)


if __name__ == '__main__':
    main()
