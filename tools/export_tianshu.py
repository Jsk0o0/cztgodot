"""天书 工房生产 / 建造放置 数据导出 → ts_prod.json  (只读游戏文件)

用法: python export_tianshu.py <游戏目录> <extracted 目录>  → extracted/game/tianshu.json
依据 (详见 menu_tianshu_prod.md):
  * 生产清单 = MAPS.DAT 段 9..13 (运行时指针 0x4e87fc + 4*k, 迭代器 0x405037/0x405060):
      记录 {u16 页签, u16 旗标, u16 n, u16 物品[n]}, 以 ffff 结束; 旗标置位时这 n 个物品才出现。
      k: 0 煉丹房(状态4) 1 武器工房(2) 2 鎧裝工房(3) 3 法寶工房(5) 4 機關工房(6)
  * 配方 = ObjDATA[物品-1]: 0xBBD 金屬/木材/煤炭/金錢 (rec+0xbc..+0xc2), 0xBBF[0..3] 冶金/整備/製藥/神技 (+0xd4..+0xd7),
      0xBBE 5×u16 特殊材料 (+0xca..+0xd3, 每出现一次需要 1 个), '+#' 等级 (+0x9a, ≠0 时清单要求条件全满足才显示)
  * 房舍占地 = 0x4a2b1e 的 4 张跳转表 (朝向 0..3 = 房舍 +0x1b6), 3×3 掩码 +0x14c, 格数 +0x170
  * 可建格 = 0x497fef: 格 (r,c) 测试点 (2017+212(r+c), 6179-212(r-c)) 下方有地面三角形 → 1
"""
import json
import os
import re
import struct
import sys

import capstone
import pefile

TOOLS = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, TOOLS)
from extract_stats import load_objdata  # noqa: E402
from mapsdat import MapsDat, collision  # noqa: E402
import act as ACT  # noqa: E402

GAME = sys.argv[1]
EXT = sys.argv[2]
OUT = os.path.join(EXT, 'game', 'tianshu.json')
UI = os.path.join(EXT, 'ui')
SCRIPTS = os.path.join(EXT, 'scripts')

WORKSHOPS = [  # (MAPS.DAT 段, 列表下标 k, 天书状态, 房舍类型, 名称, 输入, 绘制)
    (9, 0, 4, 6, '煉丹房', '0x4a80fb', '0x4a9054'),
    (10, 1, 2, 4, '武器工房', '0x4bb4e3', '0x4bc42b'),
    (11, 2, 3, 5, '鎧裝工房', '0x498a51', '0x4999b9'),
    (12, 3, 5, 7, '法寶工房', '0x4af1ce', '0x4afea5'),
    (13, 4, 6, 8, '機關工房', '0x4b8a1a', '0x4b9ed2'),
]
HOUSE_NAMES = [None, '茅草屋', '木造屋', '磚瓦屋', '武器工房', '鎧裝工房', '煉丹房', '法寶工房', '機關工房', '鬼神陣',
               '仙術道場', '轉生台']


def u16s(b, n):
    return list(struct.unpack_from('<%dH' % n, b + b'\0' * (2 * n), 0))


def flag_setters():
    """旗标 → 置位它的事件文件 (来自反汇编文本, 仅作参考)"""
    out = {}
    pat = re.compile(r'\bset_flag\s+0x([0-9a-f]{4})')
    for root, _, files in os.walk(SCRIPTS):
        if os.path.basename(root) not in ('talks1-1', 'talks1-2', 'talks1-3', 'talks1-4', 'talks2', 'Talks3'):
            continue
        for f in files:
            if not f.endswith('.txt'):
                continue
            for m in pat.finditer(open(os.path.join(root, f), encoding='utf-8').read()):
                out.setdefault(int(m.group(1), 16), set()).add(os.path.basename(root) + '/' + f[:-4])
    return {k: sorted(v) for k, v in out.items()}


def item_icon(act_data, item_id):
    """ts_draw_act(物品id, 0, x, y): ACT = 物品 id (all_item.act), 动作 0 的首帧 → PNG"""
    try:
        a = ACT.actions(act_data, item_id)[0]
    except Exception:
        return None
    fr, ap = a['fr'], (a['aps'] or [0])[0]
    sub = ['all_char', 'all_item', 'all_magic', 'all_sys', 'all_map1', 'all_map2'][fr // 3000]
    pre = '%04d_' % (fr % 3000)
    d = [x for x in os.listdir(os.path.join(UI, sub)) if x.startswith(pre)]
    return '%s/%s/%03d.png' % (sub, d[0], ap) if d else None


def recipes(game):
    md = MapsDat(game)
    recs = load_objdata(os.path.join(game, 'ObjDATA.GLL'))
    act_data = open(os.path.join(game, 'ACT', 'all_item.act'), 'rb').read()
    setters = flag_setters()
    out = []
    for seg, k, state, htype, name, fin, fdraw in WORKSHOPS:
        s, p, groups = md.seg(seg), 0, []
        while p + 2 <= len(s):
            tab = struct.unpack_from('<H', s, p)[0]
            if tab == 0xFFFF:
                break
            flag, n = struct.unpack_from('<HH', s, p + 2)
            ids = struct.unpack_from('<%dH' % n, s, p + 6)
            p += 6 + 2 * n
            items = []
            for g in ids:
                r = recs.get(g - 1, {})
                kv = r.get('kv', {})
                cost = u16s(kv.get(0xBBD, b''), 4)
                craft = list(kv.get(0xBBF, b'\0\0\0\0')[:4])
                mats = [m for m in u16s(kv.get(0xBBE, b''), 5) if m]
                items.append({
                    'id': g, 'name': r.get('name', ''), 'level_9a': r.get('level') or 0, 'kind': r.get('kind'),
                    'sub': r.get('sub'),
                    'cost': {'金屬': cost[0], '木材': cost[1], '煤炭': cost[2], '金錢': cost[3]},
                    'skill_req': dict(zip(['冶金', '整備', '製藥', '神技'], craft)),
                    'special': [{'id': m, 'name': recs.get(m - 1, {}).get('name', '')} for m in mats],
                    'info_0x102': r.get('note', ''), 'help_0x142': r.get('desc', ''),
                    'icon_png': item_icon(act_data, g),
                })
            groups.append({'tab': tab, 'flag': flag, 'flag_set_by': setters.get(flag, []), 'items': items})
        out.append({'workshop': name, 'house_type': htype, 'tianshu_state': state, 'list_index': k,
                    'mapsdat_seg': seg, 'input_fn': fin, 'draw_fn': fdraw, 'groups': groups})
    return out


def footprints(game):
    """0x4a2b1e: 朝向 o 用跳转表 T[o][类型-1]; 每个分支写 +0x14c..+0x16c (=1) 与 +0x170 (格数)"""
    pe = pefile.PE(os.path.join(game, 'SWDMD_GB.EXE'))
    ib = pe.OPTIONAL_HEADER.ImageBase
    img = pe.get_memory_mapped_image()
    md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_32)
    tables = [0x4a3092, 0x4a30be, 0x4a30ea, 0x4a3116]
    stops = {0x4a2c92, 0x4a2de0, 0x4a2f3b, 0x4a308d}
    regs = {'eax': 1, 'ecx': 3, 'ebp': 9}
    res = {}
    for t in range(1, 12):
        res[HOUSE_NAMES[t]] = {}
        for o, tb in enumerate(tables):
            va = struct.unpack_from('<I', img, tb + 4 * (t - 1) - ib)[0]
            mask, count, steps = [0] * 9, None, 0
            while steps < 60:
                ins = next(md.disasm(img[va - ib:va - ib + 16], va))
                steps += 1
                op = ins.op_str
                if ins.mnemonic == 'mov' and op == 'dword ptr [esi], eax':
                    mask[0] = 1
                m = re.match(r'dword ptr \[edx \+ 0x([0-9a-f]+)\], (\w+)', op)
                if ins.mnemonic == 'mov' and m:
                    off = int(m.group(1), 16)
                    if 0x14c <= off < 0x170:
                        mask[(off - 0x14c) // 4] = 1
                    elif off == 0x170:
                        v = m.group(2)
                        count = int(v, 16) if v.startswith('0x') else (int(v) if v.isdigit() else regs[v])
                if ins.mnemonic == 'jmp':
                    tgt = int(op, 16)
                    if tgt in stops:
                        break
                    va = tgt
                    continue
                va += ins.size
                if va in stops:
                    break
            cells = [[i // 3, i % 3] for i in range(9) if mask[i]]
            res[HOUSE_NAMES[t]][o] = {'cells_rc': cells, 'count': count, 'count_matches': count == len(cells)}
    return res


def build_grid(game):
    """0x497fef: 可建 = 1; 初始房舍占用 = 2 (0x49815d 写死的 10 个格)"""
    _, tris, _ = collision(game, 'MAP00025')   # 地图 14997 测試_天書新世界

    def has_floor(x, z):
        for t in tris:
            ax, ay, az, bx, by, bz, cx, cy, cz = t
            d = (bz - cz) * (ax - cx) + (cx - bx) * (az - cz)
            if abs(d) < 1e-9:
                continue
            l1 = ((bz - cz) * (x - cx) + (cx - bx) * (z - cz)) / d
            l2 = ((cz - az) * (x - cx) + (ax - cx) * (z - cz)) / d
            l3 = 1 - l1 - l2
            if min(l1, l2, l3) >= -1e-4:
                y = l1 * ay + l2 * by + l3 * cy
                if y <= 2100:
                    return True
        return False

    g = [[1 if has_floor(2017 + 212 * (r + c), 6179 - 212 * (r - c)) else 0 for c in range(17)] for r in range(20)]
    for r, c in [(7, 7), (7, 8), (6, 4), (6, 5), (6, 6), (7, 4), (7, 5), (7, 6), (8, 4), (8, 5)]:
        g[r][c] = 2
    return g


def main():
    data = {
        'note': '由 ts_prod_extract.py 生成; 说明见 menu_tianshu_prod.md。C/P 标注在 md 里。',
        'workshops': recipes(GAME),
        'footprints': footprints(GAME),
        'house_pos_offset': {
            'formula': 'x = 2632 + 212*(row+col) + dx ; z = 6550 - 212*(row-col) + dz ; y = 1000 (放置预览时 2000)',
            'evidence': '0x4a27de / 0x49c4df; 2632 = 5600-2968, 6550 = [0x4e6ad8]',
            'dx_dz': {
                '茅草屋 (朝向角/90 为偶数)': [-23, -146], '茅草屋 (奇数)': [119, -220],
                '法寶工房 (偶数)': [6, 35], '法寶工房 (奇数)': [159, -26],
                '類型 8..11': [109, 83], '其他 (2..6)': [17, -78]},
        },
        'grid': {
            'rows': 20, 'cols': 17, 'step': 212,
            'cell_center': 'x = 2022 + 212*(row+col), z = 6179 - 212*(row-col), y = 1000',
            'floor_test_point': 'x = 2017 + 212*(row+col), z = 6179 - 212*(row-col)',
            'values': '0 不可建 / 1 可建 / 2 已占用',
            'initial_P': build_grid(GAME),
        },
    }
    with open(OUT, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=1)
    print('->', OUT)


if __name__ == '__main__':
    main()
