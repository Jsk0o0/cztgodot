"""导出表情 (事件指令 0x78 set_expression) → extracted/game/faces.json, 并给角色模型组标出脸部材质

用法: python export_faces.py <游戏目录> <extracted 目录>
原版 (0x40ab14 / 应用在 0x46b10d): 表情 = all_sys.act 的 ACT 10001+ (10001 车芸, 10002 慕容诗, 10003 桓远之, 10004+ 其他人物);
  每帧解析该 ACT 的动作 QQ, 拿当前帧的 256×256 头部贴图 (FR 图像号 → TSW 条目, 已解成 extracted/ui/<tsw>/NNNN_*/frame.png)
  换掉模型材质表第 slot 格的贴图; slot 默认 5, 角色当前 ACT 为 4/5/0x22/0x23 时 6, 为 10/0x28/0x2b 时 4。ACT 为 0 恢复原脸。
ACT 播放 (0x41d1e3): 每个 AP 是一帧, 帧后的 DS n = 这一帧再多停 n 个逻辑帧 (0x41dac3 写倒数, 0x41de07 每帧减一), VO 循环, 2O 停在末帧
输出: faces.json {ACT: {QQ: {"frames": [[png 相对 extracted, 停留帧数], ...], "loop": bool}}}
      game/actors/act_*.json 每组补 "face_mats": {slot: 材质名} (材质名同 ply2gltf: 贴图组名或 tex<贴图号>)
"""
import glob
import json
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from act import ACT_FILES, read_index
from export_ui_acts import anim  # noqa: E402
from ply import parse  # noqa: E402

TSW = ['all_char', 'all_item', 'all_magic', 'all_sys', 'all_map1', 'all_map2']
SLOTS = (4, 5, 6)


def tokens(s):
    """ACT 动作的标签流 (TAGLEN 同 ui 逆向笔记)"""
    size = {b'PT': 1, b'AT': 2, b'XB': 32, b'FR': 2, b'AP': 2, b'DE': 0, b'DS': 2, b'IS': 12, b'PS': 2, b'XF': 4,
            b'CS': 12, b'OC': 8, b'XV': 0, b'VO': 0, b'2O': 0, b'PC': 12}
    i = 0
    while i + 2 <= len(s):
        t = s[i:i + 2]
        n = size.get(t)
        if n is None:
            return
        v = struct.unpack_from('<H', s, i + 2)[0] if n == 2 else None
        yield t, v
        i += 2 + n
        if t in (b'VO', b'2O'):
            return


def main(game, ext):
    ui = json.load(open(os.path.join(ext, 'ui', 'index.json')))
    dirs = {k: {int(e['index']): e['dir'] for e in (v if isinstance(v, list) else v.values())} for k, v in ui.items()}
    d = open(os.path.join(game, 'ACT', ACT_FILES[3]), 'rb').read()
    out = {}
    for slot, (off, size) in read_index(d).items():
        act = 9000 + slot
        if act < 10001:
            continue
        a = d[off:off + size]
        cnt = struct.unpack_from('<H', a, 0)[0]
        qqs = {}
        for q in range(cnt):
            o, ln = struct.unpack_from('<IH', a, 2 + 6 * q)
            if not ln:
                continue
            # 帧时序与界面 ACT 共用 (export_ui_acts.anim, 0x41d1e3 逆向确认): DS 设定的停留值一直沿用到下一个 DS,
            # 以前只加在 DS 所在那一帧, 后续帧都按 1 帧算 (例 10001 qq2 / 51 / 93 眨眼偏快)
            fa, loop = anim(a[o:o + ln], dirs)
            frames = [[f[0], f[1]] for f in fa]
            if frames:
                qqs[q] = {'frames': frames, 'loop': loop}
        if qqs:
            out[act] = qqs
    json.dump(out, open(os.path.join(ext, 'game', 'faces.json'), 'w', encoding='utf-8'), ensure_ascii=False)
    # 脸部材质: 模型材质组第 slot 格 → GLB 材质名
    cache = {}
    k = 0
    for p in glob.glob(os.path.join(ext, 'game', 'actors', 'act_*.json')):
        if p.endswith('.morph.json'):
            continue   # 模型逐帧变形 sidecar, 不是角色表
        m = json.load(open(p))
        if all('face_mats' in g for g in m['groups']):
            continue
        for g in m['groups']:
            f = g['files'][0]
            if f not in cache:
                try:
                    cache[f] = parse(os.path.join(game, 'Model', f + '.PLY')).groups
                except Exception:  # noqa: BLE001
                    cache[f] = []
            grs = cache[f]
            g['face_mats'] = {s: (grs[s].name or 'tex%d' % grs[s].tex) for s in SLOTS
                              if s < len(grs) and grs[s].tex >= 0}
        json.dump(m, open(p, 'w', encoding='utf-8'), ensure_ascii=False)
        k += 1
    print('表情 ACT %d 个, 角色脸部材质 %d 个' % (len(out), k))


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
