"""记载 (主菜单第 6 项) 用到的数据 → extracted/game/records.json
用法: python export_records.py <游戏目录> <extracted 目录>
  - 任务 / 已完成任务: Mission.GLL 条目 7000+i, 旗标 7001+i (接受) / 7257+i (完成), i = 0..255  (0x483e14)
  - 历史相关: Mission.GLL 条目 7512+i, 旗标 7513+i, i = 0..8
  - 人 (怪物图鉴): ObjDATA 大类 1, 子类 110..120 (按种族图标分组), 各字段的解锁阈值见 menu_jizai.md §3
  - 物 (道具图鉴): ObjDATA 大类 2, 子类 201..209, 生产需求 0xBBD / 0xBBF / 0xBBE
游戏编号 = ObjDATA 下标 + 1 (read_Item 0x4037b2 读 [表 + N*4 - 4])。
"""
import json
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from extract_stats import load_objdata, s16, u16  # noqa: E402
from extract_text import T2S, big5  # noqa: E402

GAME = sys.argv[1]
OUT = os.path.join(sys.argv[2], 'game', 'records.json')

# 0x4e635c: 种族图标 i -> 子类码 (120 同时包含 119 机关魔王, 0x4621c3/0x462636)
RACES = [110, 111, 112, 113, 114, 115, 116, 117, 118, 120]
RACE_NAMES = ['人类', '动物', '神兽', '鬼', '精怪', '妖灵', '魔兽', '神祇', '机关', '魔王']   # MAPS.DAT seg19 33..42
# 0x4e6370: 物品分类图标 i -> 子类码; ACT 9024 qq i+1 / i+16 -> 0106/0107 帧
ITEM_CATS = [202, 203, 201, 204, 205, 206, 208, 207, 209]
ITEM_CAT_NAMES = ['恢复', '辅助', '攻击', '武器', '防具', '饰品', '足部', '法宝', '剧情']  # seg19 10..18
ITEM_CAT_FRAME = [10, 11, 9, 2, 3, 4, 6, 5, 7]
ELEM = ['木', '火', '土', '金', '水', '无', '无']   # 0x4e6340
# 怪物图鉴: 字段 -> 认识度阈值 (记录 +0x10 >= 阈值 或 记录 +0 == 1, 即曾经 >= 100)
THRESH = {'name': 10, 'level': 15, 'desc': 20, 'hp': 30, 'mp': 35, 'sp': 40, 'atk': 50, 'def': 55, 'matk': 60,
          'mdef': 65, 'spd': 70, 'elem': 80, 'craft': 85, 'steal': 85, 'learn': 100}
ALWAYS_KNOWN = [1097, 1098, 1099, 1100]   # 0x483fb4: 每次打开记载都 0x44c5d7(id,100,0,0); 1097 在列表里被跳过 (0x4857e7)


def mission_entries(path):
    b = open(path, 'rb').read()
    p = b[16:]
    n = struct.unpack_from('<I', p, 0)[0] // 4
    offs = struct.unpack_from('<%dI' % n, p, 0)

    def text(k):
        o = offs[k]
        if o == 0xFFFFFFFF:
            return None, None
        e = p[o:p.index(b'%Q', o)]
        return T2S(big5(e)), o
    return text, offs


def main():
    text, offs = mission_entries(os.path.join(GAME, 'Mission.GLL'))
    placeholder = offs[0]
    quests = []
    for i in range(256):
        t, o = text(7000 + i)
        if t is None or (o == placeholder and i != 0):
            continue
        quests.append({'i': i, 'gll_entry': 7000 + i, 'flag_accept': 7001 + i, 'flag_done': 7257 + i,
                       'main': t.startswith('★'), 'text': t})
    history = []
    for i in range(9):
        t, o = text(7512 + i)
        history.append({'i': i, 'gll_entry': 7512 + i, 'flag': 7513 + i, 'title': t.split('%N')[0], 'text': t})

    recs = load_objdata(os.path.join(GAME, 'ObjDATA.GLL'))
    name = {i + 1: r.get('name', '') for i, r in recs.items()}

    beasts = []
    for i, r in sorted(recs.items()):
        if r.get('kind') != 1 or r.get('sub') not in RACES + [119]:
            continue
        kv = r['kv']
        g = i + 1
        hp, mp, sp = u16(kv[0xBBA], 3) if 0xBBA in kv else (0, 0, 0)
        st = s16(kv[0xBB9], 5) if 0xBB9 in kv else [0] * 5
        el = s16(kv[0x3E9], 7) if 0x3E9 in kv else [0] * 7
        elem = next((ELEM[k] for k in range(7) if el[k] > 0), '无')
        craft = list(kv[0xBBF][:4]) if 0xBBF in kv else [0, 0, 0, 0]
        steal = struct.unpack_from('<BH', kv[0x3F6], 3)[1] if 0x3F6 in kv else 0
        learn = u16(kv[0x3F8], 1)[0] if 0x3F8 in kv else 0
        sub = r['sub']
        race = RACES.index(120 if sub == 119 else sub)
        beasts.append({
            'id': g, 'race_tab': race, 'race': RACE_NAMES[race], 'sub': sub,
            'unique_3f7': kv[0x3F7][0] if 0x3F7 in kv else 0,
            'hidden_in_list': g == 1097, 'always_known': g in ALWAYS_KNOWN,
            'name': r.get('name', ''), 'level': r.get('level') or (u16(kv[0x232B], 1)[0] if 0x232B in kv else 0), 'desc': r.get('desc', ''),
            'hp': hp, 'mp': mp, 'sp': sp, 'atk': st[0], 'def': st[1], 'spd': st[2], 'matk': st[3], 'mdef': st[4],
            'elem': elem, 'craft': dict(zip(['冶金', '整备', '制药', '神技'], craft)),
            'steal_id': steal, 'steal': name.get(steal, '') if steal else '',
            'learn_id': learn, 'learn': name.get(learn, '') if learn else '',
            'model_act': g, 'model_action': 0x50,
        })

    items = []
    for i, r in sorted(recs.items()):
        if r.get('kind') != 2 or r.get('sub') not in ITEM_CATS:
            continue
        kv = r['kv']
        cost = u16(kv[0xBBD], 4) if 0xBBD in kv else [0, 0, 0, 0]
        craft = list(kv[0xBBF][:4]) if 0xBBF in kv else [0, 0, 0, 0]
        mats = [m for m in (u16(kv[0xBBE], 5)[:3] if 0xBBE in kv else []) if m]
        c = ITEM_CATS.index(r['sub'])
        items.append({
            'id': i + 1, 'cat_tab': c, 'cat': ITEM_CAT_NAMES[c], 'sub': r['sub'], 'icon_frame': ITEM_CAT_FRAME[c],
            'unique_3f7': kv[0x3F7][0] if 0x3F7 in kv else 0,
            'name': r.get('name', ''), 'desc': r.get('desc', ''),
            '金钱': cost[3], '金属': cost[0], '木材': cost[1], '煤炭': cost[2],
            '冶金': craft[0], '整备': craft[1], '制药': craft[2], '神技': craft[3],
            'special': [name.get(m, str(m)) for m in mats],
            'knowledge_type': 1 if 5201 <= i + 1 < 5300 else 2,
        })

    # 天书建筑 (ObjDATA 9501–9526, 费用 0xBBD = 金属/木材/煤炭/金钱)
    houses = {}
    for g in range(9501, 9527):
        r = recs.get(g - 1)
        if not r:
            continue
        kv = r['kv']
        cost = u16(kv[0xBBD], 4) if 0xBBD in kv else (0, 0, 0, 0)
        houses[str(g)] = {'name': r.get('name', ''), 'desc': r.get('desc', ''),
                          '金属': cost[0], '木材': cost[1], '煤炭': cost[2], '金钱': cost[3]}

    out = {'quests': quests, 'history': history, 'bestiary': beasts, 'items': items, 'houses': houses,
           'thresholds': THRESH, 'races': RACE_NAMES, 'item_cats': ITEM_CAT_NAMES}
    with open(OUT, 'w', encoding='utf-8') as f:
        json.dump(out, f, ensure_ascii=False, indent=1)
    pc = [q['text'] for q in quests + history if '%C' in q['text']]
    print('quests', len(quests), 'history', len(history), 'bestiary', len(beasts), 'items', len(items),
          'texts with %C:', len(pc), '->', OUT)


if __name__ == '__main__':
    main()
