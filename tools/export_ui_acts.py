"""导出 all_sys.act 里界面用的 2D ACT 动画 (光标、界面元件动画、表情等) → extracted/ui/acts.json

用法: python export_ui_acts.py <游戏目录> <extracted 目录>
输出: {"9001": {"0": {"frames": [[图片相对路径, 停留逻辑帧数, 锚点x, 锚点y], ...], "loop": true}, ...}, ...}

ACT 播放器 0x41d1e3 的帧时序 (逆向确认):
  * 动作开始时整个播放结构清零 (0x41d2f0 memset 0x114), 所以锚点 PC (+0x50/+0x54) 和停留值 (+0xaa) 都从 0 开始
  * 函数入口: 倒数 +0xac 不为 0 → 减一并返回 (这一帧继续显示)
  * 解析每个标签前都把倒数 +0xac 设成停留值 +0xaa (0x41d426); DS n (0x41dac3) 把 +0xaa 和 +0xac 都设成 n,
    n = 0xffff 时两者清 0。DS 的值一直保留, 后面的帧不再写 DS 也沿用
  * DE 结束这一帧 → 每帧显示 (停留值 + 1) 个逻辑帧; VO 回到开头循环 (+0xec 清 0, 停留值保留), 2O 停在末帧
  * PC (x, y, z) 写 +0x50..; 2D 绘制 0x46ad17 画在 (点 x − PC.x, 点 y − PC.y)
  * 图集 (0x41da23 / 0x41da79): IS = (x0, y0, x1, y1, 格宽, 格高), PS = 格号 k; 列数 = (x1 − x0) / 格宽,
    取图矩形 = ((k % 列数) × 格宽, (k / 列数) × 格高, 格宽, 格高) —— 不加 x0 / y0 (原版就是这样)
  输出帧的第 5 项是这个矩形 [x, y, w, h] (没有图集时为 null)
  第 6 项 (可选) 是这一帧的变换 {cs: [x, y] 缩放, oc: [a, r, g, b] 颜色, pd: [x, y] 偏移, xf: 混合}; AP 时颜色 / 缩放复位 (0x41d87e),
  PD / XF 一直沿用到下次写入
  逻辑帧: 地图 / 菜单 35 帧/秒, 战斗 27 帧/秒 (同一个播放器每帧调用一次)
"""
import json
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from act import ACT_FILES, read_index  # noqa: E402

TSW = ['all_char', 'all_item', 'all_magic', 'all_sys', 'all_map1', 'all_map2']
SIZE = {b'PT': 1, b'AT': 2, b'XB': 32, b'FR': 2, b'AP': 2, b'DE': 0, b'DS': 2, b'IS': 12, b'PS': 2, b'XF': 4,
        b'CS': 12, b'OC': 8, b'XV': 0, b'VO': 0, b'2O': 0, b'PC': 12, b'PD': 12, b'TR': 6, b'VW': 2}


def tokens(s):
    i = 0
    while i + 2 <= len(s):
        t = s[i:i + 2]
        n = SIZE.get(t)
        if n is None:
            return
        yield t, s[i + 2:i + 2 + n]
        i += 2 + n
        if t in (b'VO', b'2O'):
            return


def rect(a, k):
    cols = max((a[2] - a[0]) // a[4], 1) if a[4] else 1
    return [(k % cols) * a[4], (k // cols) * a[5], a[4], a[5]]


def anim(blob, dirs):
    """一个动作 → (帧表, 是否循环); 帧 = [图片, 停留逻辑帧数, 锚点 x, 锚点 y]"""
    frames, fr, hold, pc, loop = [], None, 0, (0.0, 0.0), False
    cur = None
    atlas, cell = None, 0
    xf_state = {}   # PD / XF: 沿用
    for t, v in tokens(blob):
        if t == b'FR':
            fr = struct.unpack('<H', v)[0]
        elif t == b'AP' and fr is not None:
            dr = dirs.get(TSW[fr // 3000], {}).get(fr % 3000)
            cur = [os.path.join('ui', dr, '%03d.png' % struct.unpack('<H', v)[0]) if dr else None, 0, pc[0], pc[1], None, dict(xf_state)]
            if atlas:
                cur[4] = rect(atlas, cell)
        elif t == b'IS':
            atlas = struct.unpack('<6H', v)
            if cur:
                cur[4] = rect(atlas, cell)
        elif t == b'PS':
            cell = struct.unpack('<H', v)[0]
            if cur and atlas:
                cur[4] = rect(atlas, cell)
        elif t in (b'CS', b'OC', b'PD', b'XF'):
            if t == b'CS':
                x, y, _ = struct.unpack('<3f', v); val = {'cs': [round(x, 4), round(y, 4)]}
            elif t == b'OC':
                val = {'oc': list(struct.unpack('<4H', v))}
            elif t == b'PD':
                x, y, _ = struct.unpack('<3f', v); val = {'pd': [round(x, 2), round(y, 2)]}; xf_state.update(val)
            else:
                val = {'xf': struct.unpack('<I', v)[0]}; xf_state.update(val)
            if cur:
                cur[5].update(val)
        elif t == b'PC':
            x, y, _ = struct.unpack('<3f', v)
            pc = (x, y)
            if cur:
                cur[2], cur[3] = x, y
        elif t == b'DS':
            n = struct.unpack('<H', v)[0]
            hold = 0 if n == 0xffff else n
        elif t == b'DE':
            if cur and cur[0]:
                cur[1] = hold + 1
                frames.append(cur)
            cur = None
        elif t in (b'VO', b'2O'):
            if cur and cur[0]:   # 最后一帧没有 DE 时, 2O / VO 之前的那一帧同样停 (停留值 + 1)
                cur[1] = hold + 1
                frames.append(cur)
            loop = t == b'VO'
    return frames, loop


def main(game, ext):
    ui = json.load(open(os.path.join(ext, 'ui', 'index.json')))
    dirs = {k: {int(e['index']): e['dir'] for e in (v if isinstance(v, list) else v.values())} for k, v in ui.items()}
    d = open(os.path.join(game, 'ACT', ACT_FILES[3]), 'rb').read()
    out = {}
    for slot, (off, size) in read_index(d).items():
        a = d[off:off + size]
        cnt = struct.unpack_from('<H', a, 0)[0]
        qqs = {}
        for q in range(cnt):
            o, ln = struct.unpack_from('<IH', a, 2 + 6 * q)
            if not ln:
                continue
            frames, loop = anim(a[o:o + ln], dirs)
            if frames:
                qqs[str(q)] = {'frames': [[f[0], f[1], round(f[2], 2), round(f[3], 2), f[4]] + ([f[5]] if f[5] else []) for f in frames], 'loop': loop}
        if qqs:
            out[str(9000 + slot)] = qqs
    p = os.path.join(ext, 'ui', 'acts.json')
    json.dump(out, open(p, 'w', encoding='utf-8'), ensure_ascii=False)
    print('界面 ACT %d 个 → %s' % (len(out), p))


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
