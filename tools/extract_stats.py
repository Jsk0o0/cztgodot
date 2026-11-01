"""ObjDATA.GLL / LEVEL.GLL 数值解析 -> extracted/stats/

ObjDATA 条目 = 文本标签 ()# 名称 ,# 描述 -# 附注 *# 大类 .# 子类) + 键值属性区:
  u16 键 + 定长载荷, 以 '2#' + ffff 结尾。同一个键在各大类中载荷长度相同 (见 KEYS)。
  大类(*#): 1 单位(主角/怪物)  2 道具/装备  3 法术/技能  4 天书建筑
游戏里的编号 (脚本、ATK、技能表、掉落、装备、ACT) = ObjDATA 下标 + 1 (read_Item 0x4037b2 读 [表 + N*4 - 4]),
所以输出的「编号 id」一律是游戏编号, 另给「下标 index」; 记录之间的引用都按游戏编号查名字。
未定义的条目在偏移表里都指向 0 号条目的偏移 (占位), 解析时跳过。
数值约定: s16 中 >=10000 表示 +(v-10000)%, <=-10000 表示 -(|v|-10000)%。
用法: python extract_stats.py <游戏目录> <输出目录>
"""
import csv
import json
import os
import struct
import sys
from collections import Counter

sys.path.insert(0, os.path.dirname(__file__))
from extract_text import T2S, big5, read_gll  # noqa: E402

# 键 -> 载荷字节数
KEYS = {
    0x3E9: 14, 0x3EB: 1, 0x3EC: 2, 0x3ED: 2, 0x3EE: 2, 0x3EF: 1, 0x3F0: 4, 0x3F1: 2, 0x3F2: 2,
    0x3F3: 10, 0x3F4: 5, 0x3F5: 14, 0x3F6: 9, 0x3F7: 1, 0x3F8: 2, 0x3F9: 2, 0x3FA: 2, 0x3FB: 4,
    0x3FC: 6, 0x3FD: 2, 0xBB8: 1, 0xBB9: 10, 0xBBA: 6, 0xBBB: 8, 0xBBD: 8, 0xBBE: 10, 0xBBF: 5,
    0xBC0: 4, 0xBC1: 7, 0xC1C: 1, 0xC1D: 5, 0xC1E: 12, 0xC1F: 14, 0xC20: 1, 0xC21: 4, 0xC22: 1,
    0xC23: 1, 0x232B: 2,  # 0x232b = 文本标签 '+#' (等级), 出现在单位属性区内
}
END = b'2#\xff\xff'
TEXT_TAGS = {')': 'name', ',': 'desc', '-': 'note'}
NUM_TAGS = {'*': 'kind', '.': 'sub', '+': 'level'}

STAR = {1: '单位', 2: '道具', 3: '法术', 4: '建筑'}
SUB = {  # 子类码 -> 名称 (依据同类条目名称归纳, 推测)
    101: '主角', 110: '人类', 111: '野兽', 112: '灵兽', 113: '鬼怪', 114: '妖物', 115: '妖魔',
    116: '异兽', 117: '仙灵', 118: '木甲机关', 119: '大型机关/首领', 120: '剧情人物/魔王',
    201: '战斗道具', 202: '恢复药', 203: '辅助道具', 204: '武器', 205: '身体防具', 206: '饰品',
    207: '法宝(可修练)', 208: '鞋', 209: '素材/任务物品',
    301: '攻击', 302: '木甲修复', 305: '特殊', 306: '机关术',
    400: '民居', 401: '武器工房', 402: '铠装工房', 403: '炼丹房', 404: '机关工房', 405: '法宝工房',
    406: '鬼神阵', 407: '仙术道场', 408: '转生台',
}
MAGIC_SUB = {201: '攻击', 202: '恢复', 203: '辅助/状态', 302: '木甲修复', 305: '特殊', 306: '机关术'}
STATUS = {2: '死亡(复活)', 4: '中毒', 8: '昏睡', 16: '石化', 32: '咒封',
          64: '情绪1', 128: '情绪2', 256: '情绪3', 512: '情绪4', 1024: '未明1024', 2048: '未明2048'}
ELEM = ['木', '火', '土', '金', '水', 'unk_属性5', 'unk_属性6']


def s16(b, n):
    return list(struct.unpack('<%dh' % n, b[:2 * n]))


def u16(b, n):
    return list(struct.unpack('<%dH' % n, b[:2 * n]))


def pct(v):
    """游戏用 10000+x 表示百分比"""
    if v >= 10000:
        return f'+{v - 10000}%'
    if v <= -10000:
        return f'-{-v - 10000}%'
    return v


def status_names(mask):
    return [n for b, n in STATUS.items() if mask & b] + ([f'0x{mask:x}'] if mask & ~0xFFE else [])


def parse_kv(d):
    kv, p = {}, 0
    while d[p:p + 4] != END:
        k = struct.unpack_from('<H', d, p)[0]
        n = KEYS[k]
        kv[k] = d[p + 2:p + 2 + n]
        p += 2 + n
    assert p + 4 == len(d), 'trailing data'
    return kv


def load_objdata(path):
    entries = read_gll(path)
    placeholder = entries[0][1]
    recs = {}
    for i, o, d in entries:
        if d is None or (o == placeholder and i != 0):
            continue
        r, p = {'index': i}, 0
        while p + 1 < len(d) and d[p + 1] == 0x23 and chr(d[p]) in '),-*.+':
            t = chr(d[p])
            p += 2
            if t in TEXT_TAGS:
                q = d.find(b'%Q', p)
                r[TEXT_TAGS[t]] = T2S(big5(d[p:q]))
                p = q + 2
            else:
                r[NUM_TAGS[t]] = struct.unpack_from('<H', d, p)[0]
                p += 2
        r['kv'] = parse_kv(d[p:])
        recs[i] = r
    return recs


# ------------------------------------------------------------ 通用字段解码

def common(r):
    kv = r['kv']
    out = {'编号 id': r['index'] + 1, '下标 index': r['index'], '名称 name': r.get('name', ''),
           '大类 kind': STAR.get(r.get('kind')),
           '子类码 sub': r.get('sub'), '子类 sub_name': SUB.get(r.get('sub')),
           '描述 desc': r.get('desc', ''), '附注 note': r.get('note', '')}
    return out, kv


def stats5(kv):
    a = s16(kv[0xBB9], 5)
    return {'攻击 atk': pct(a[0]), '防御 def': pct(a[1]), '速度 spd': pct(a[2]),
            '仙攻 matk': pct(a[3]), '仙防 mdef': pct(a[4])}


def pool3(kv, prefix=''):
    a = s16(kv[0xBBA], 3)
    return {f'{prefix}生命 hp': a[0], f'{prefix}灵力 mp': a[1], f'{prefix}体力 sp': a[2]}


def rates(kv):
    # 战斗代码 (roll_hit 0x4376eb) 的用法: [0] 回避 [1] 命中 [2] 法术回避 [3] 法术命中
    a = s16(kv[0xBBB], 4)
    return {'回避 eva': a[0], '命中 hit': a[1], '法术回避 meva': a[2], '法术命中 mhit': a[3]}


def elements(kv):
    return {f'属性_{n} elem_{k}': v for k, (n, v) in enumerate(zip(ELEM, s16(kv[0x3E9], 7)))}


def status(kv):
    if 0xC21 not in kv:
        return {}
    mask, op = u16(kv[0xC21], 2)
    rate = kv.get(0x3F2, b'\0\0')
    return {'状态 status': '/'.join(status_names(mask)), '状态位 status_mask': mask,
            '状态操作 status_op': {4096: '解除', 8192: '施加'}.get(op, op),
            '状态命中率 status_rate': rate[0], '能力变化命中率 buff_rate': rate[1],
            '无效对象 immune': '/'.join(n for b, n in ((1, '木甲机关'), (2, '魔王'), (4, 'unk4')) if kv.get(0xC23, b'\0')[0] & b)}


def effects(kv):
    out = {}
    if 0xC1E in kv:
        a = s16(kv[0xC1E], 6)
        for n, v in zip(['生命 hp', '体力 sp', '攻击 atk', '防御 def', 'unk_c1e_4', 'unk_c1e_5'], a):
            out['效果_' + n] = pct(v)
    if 0xC1F in kv:
        a = s16(kv[0xC1F], 7)
        for n, v in zip(['灵力 mp', '仙攻 matk', '仙防 mdef', 'unk_c1f_3', 'unk_c1f_4', '速度 spd', 'unk_c1f_6'], a):
            out['效果_' + n] = pct(v)
    return out


def costs(kv):
    b = kv[0xBC1]
    sp, mp = struct.unpack_from('<HH', b, 2)
    return {'体力消耗 sp_cost': pct(sp), '灵力消耗 mp_cost': pct(mp), 'unk_bc1': f'{b[0]},{b[1]},{b[6]}'}


def unknowns(kv, used):
    return {f'unk_0x{k:x}': kv[k].hex() for k in sorted(kv) if k not in used and any(kv[k])}


# ------------------------------------------------------------ 各类记录

def unit(r, names, battles):
    out, kv = common(r)
    out['等级 level'] = u16(kv[0x232B], 1)[0] if 0x232B in kv else r.get('level')
    out['特殊单位标志 unique_flag(推测)'] = kv[0x3F7][0]
    out.update(pool3(kv))
    out.update(stats5(kv))
    out.update(rates(kv))
    out['奋力机率 crit_rate'] = kv[0x3EF][0]
    out.update(elements(kv))
    skills = [s for s in u16(kv[0x3F3], 5)]
    probs = list(kv[0x3F4])
    out['技能 skills'] = [{'id': s, 'name': names.get(s, ''), '每场可用次数 uses': p} for s, p in zip(skills, probs) if s]
    # 奖励 0x3F5 (战斗结算): [0] 金钱 → 0xbcec84; 经验 = [4] + [5]<<16; [1..3] 为金属/木材/煤炭 (顺序推测)
    rw = u16(kv[0x3F5], 7)
    out.update({'金钱 money': rw[0], '金属 metal(推测)': rw[1], '木材 wood(推测)': rw[2], '煤炭 coal(推测)': rw[3],
                '经验 exp': rw[4] | (rw[5] << 16), 'unk_reward6': rw[6]})
    drops = []
    for k in range(3):
        rate, iid = struct.unpack_from('<BH', kv[0x3F6], 3 * k)
        if iid:
            drops.append({'id': iid, 'name': names.get(iid, ''), '机率 rate': rate})
    out['掉落 drops'] = drops
    w = u16(kv[0x3F1], 1)[0]
    out['普攻武器 weapon_id'] = w or None
    out['普攻武器名 weapon_name'] = names.get(w, '(未定义条目)' if w else '')
    sp = u16(kv[0x3F8], 1)[0]
    out['特殊技能 special_skill'] = {'id': sp, 'name': names.get(sp, '')} if sp else None
    st = status(kv)
    if st.get('状态位 status_mask'):
        out['普攻附加 on_hit'] = st
    prod = list(kv[0xBBF])
    out.update({'生产_武器 craft_weapon': prod[0], '生产_铠装 craft_armor': prod[1], '生产_炼丹 craft_alchemy': prod[2],
                '生产_法宝 craft_artifact': prod[3], 'unk_bbf_4': prod[4]})
    out['AI脚本 ai_id(AI.GLL)'] = u16(kv[0x3EC], 1)[0]
    out['动作脚本 action_id(ATK.GLL)'] = u16(kv[0x3ED], 1)[0]
    out['副动作脚本 action2_id(ATK.GLL,推测)'] = u16(kv[0x3EE], 1)[0]
    out['unk_bc1_u16@2(=等级x15)'] = struct.unpack_from('<H', kv[0xBC1], 2)[0]
    out['unk_3fc'] = s16(kv[0x3FC], 3)
    out['unk_3fb'] = u16(kv[0x3FB], 2)
    out['unk_3f0'] = u16(kv[0x3F0], 2)
    out['unk_3fd'] = u16(kv[0x3FD], 1)[0]
    out.update(unknowns(kv, {0x232B, 0x3F7, 0xBBA, 0xBB9, 0xBBB, 0x3EF, 0x3E9, 0x3F3, 0x3F4, 0x3F5, 0x3F6,
                             0x3F1, 0x3F8, 0xC21, 0x3F2, 0xC23, 0xBBF, 0x3EC, 0x3ED, 0x3EE, 0xBC1, 0x3FC,
                             0x3FB, 0x3F0, 0x3FD}))
    if battles is not None:
        bl = battles.get(r['index'] + 1, [])
        out['出现战场 battlefields'] = bl
        out['首次出现战场序号 first_battle'] = bl[0]['index'] if bl else None
    return out


EQUIP_SLOT = {204: '武器', 205: '身体', 206: '饰品', 207: '法宝', 208: '鞋'}


def item(r, names):
    out, kv = common(r)
    if r.get('sub') in EQUIP_SLOT:
        out['部位 slot'] = EQUIP_SLOT[r['sub']]
    who = kv[0xBB8][0]
    out['可用角色 users'] = '/'.join(n for b, n in ((1, '车芸'), (2, '嬴诗'), (4, '桓远之')) if who & b)
    out['可用角色码 users_mask'] = who
    flag, price = struct.unpack_from('<BH', kv[0xC1D], 0)
    out['售价 price'] = price
    out['unk_c1d'] = f'{flag},{struct.unpack_from("<H", kv[0xC1D], 3)[0]}'
    out.update(stats5(kv))
    out.update(pool3(kv, '上限_'))
    out.update(rates(kv))
    out['奋力机率 crit_rate'] = kv[0x3EF][0]
    out.update(elements(kv))
    out.update(effects(kv))
    out.update(status(kv))
    bc0 = list(kv[0xBC0])
    out['目标阵营 side'] = {1: '我方', 2: '敌方'}.get(bc0[0], bc0[0])
    out['范围 scope'] = {0: '单体', 1: '全体'}.get(bc0[1], bc0[1])
    out['unk_bc0'] = bc0[2:]
    out['目标类别 target_class(推测)'] = kv[0xC22][0]
    out['威力 power(攻击道具)'] = u16(kv[0x3F1], 1)[0]
    cost = u16(kv[0xBBD], 4)
    out.update({'生产_金属 cost_metal': cost[0], '生产_木材 cost_wood': cost[1], '生产_煤炭 cost_coal': cost[2],
                '生产_金钱 cost_money': cost[3]})
    mats = [m for m in u16(kv[0xBBE], 5) if m]
    out['合成材料 materials(推测)'] = [{'id': m, 'name': names.get(m, '')} for m in mats]
    req = list(kv[0xBBF])
    out.update({'需求_武器 req_weapon': req[0], '需求_铠装 req_armor': req[1], '需求_炼丹 req_alchemy': req[2],
                '需求_法宝 req_artifact': req[3]})
    out['动作脚本 action_id(ATK.GLL)'] = u16(kv[0x3ED], 1)[0]
    if r.get('sub') == 207:
        out['修练表 refine_table(LEVEL.GLL)'] = out['动作脚本 action_id(ATK.GLL)']
    out.update(costs(kv))
    out['特殊装备标志 special_flag(推测)'] = kv[0xC1C][0]
    out['unk_3f0'] = u16(kv[0x3F0], 2)
    out.update(unknowns(kv, {0xBB8, 0xC1D, 0xBB9, 0xBBA, 0xBBB, 0x3EF, 0x3E9, 0xC1E, 0xC1F, 0xC21, 0x3F2, 0xC23,
                             0xBC0, 0xC22, 0x3F1, 0xBBD, 0xBBE, 0xBBF, 0x3ED, 0xBC1, 0xC1C, 0x3F0}))
    return out


def magic(r, names, learned):
    out, kv = common(r)
    out['子类 sub_name'] = MAGIC_SUB.get(r.get('sub'), out['子类 sub_name'])
    bc0 = list(kv[0xBC0])
    out['目标阵营 side'] = {1: '我方', 2: '敌方'}.get(bc0[0], bc0[0])
    out['范围 scope'] = {0: '单体', 1: '全体'}.get(bc0[1], bc0[1])
    out['unk_bc0'] = bc0[2:]
    out['威力 power'] = u16(kv[0x3F1], 1)[0]
    out.update(costs(kv))
    out.update(elements(kv))
    out.update(effects(kv))
    out.update(status(kv))
    out['奋力机率加成 crit_bonus'] = kv[0x3EF][0]
    out['目标类别 target_class(推测)'] = kv[0xC22][0]
    out['动作脚本 action_id(ATK.GLL)'] = u16(kv[0x3ED], 1)[0]
    out['unk_3f9(学习费用?)'] = u16(kv[0x3F9], 1)[0]
    out['unk_3fa'] = u16(kv[0x3FA], 1)[0]
    out['unk_3eb'] = kv[0x3EB][0]
    out['unk_c20'] = kv[0xC20][0]
    out['unk_3f0'] = u16(kv[0x3F0], 2)
    out['习得 learned_by'] = learned.get(r['index'] + 1, [])
    out.update(unknowns(kv, {0xBC0, 0x3F1, 0xBC1, 0x3E9, 0xC1E, 0xC1F, 0xC21, 0x3F2, 0xC23, 0x3EF, 0xC22, 0x3ED,
                             0x3F9, 0x3FA, 0x3EB, 0xC20, 0x3F0}))
    return out


def building(r):
    out, kv = common(r)
    cost = u16(kv[0xBBD], 4)
    out.update({'建造_金属 cost_metal': cost[0], '建造_木材 cost_wood': cost[1], '建造_煤炭 cost_coal': cost[2],
                '建造_金钱 cost_money': cost[3]})
    out.update(unknowns(kv, {0xBBD}))
    return out


# ------------------------------------------------------------ LEVEL.GLL

GROWTH_COLS = ['等级 level', '生命 hp', '灵力 mp', '体力 sp', '攻击 atk', '防御 def', '仙攻 matk', '仙防 mdef',
               '命中 hit', '回避 eva', '法术命中 mhit', '法术回避 meva', '速度 spd', '习得法术 learn_skill', 'unk_14', 'unk_15']


def level_tables(path, names):
    out = {'growth': {}, 'exp_table': [], 'refine_tables': [], 'table20': []}
    chars = {0: '车芸', 1: '嬴诗', 2: '桓远之'}
    for i, o, d in read_gll(path):
        if d is None:
            continue
        body = d[:-4] if d.endswith(b'\xb1\x26\xff\xff') else d
        if i <= 2:
            rows = [struct.unpack_from('<16H', body, 32 * k) for k in range(len(body) // 32)]
            out['growth'][chars[i]] = [dict(zip(GROWTH_COLS, r)) for r in rows]
            for row in out['growth'][chars[i]]:
                s = row['习得法术 learn_skill']
                if s:
                    row['习得法术名 learn_skill_name'] = names.get(s, '')
        elif i == 3:
            for k in range(len(body) // 8):
                lv, xp = struct.unpack_from('<2I', body, 8 * k)
                out['exp_table'].append({'等级 level': lv, '升级所需经验 exp_to_next(推测)': xp})
        elif i == 20:
            for k in range(len(body) // 6):
                out['table20'].append(dict(zip(['等级 level', 'unk_a', 'unk_b'], struct.unpack_from('<3H', body, 6 * k))))
        else:
            v = list(struct.unpack('<%di' % (len(body) // 4), body))
            tid, rest = v[0], v[1:]
            per = len(rest) // 5
            levels = []
            for k in range(5):
                g = rest[k * per:(k + 1) * per]
                levels.append({'修练等级 level': g[0], '所需修练值 refine_req': g[1],
                               '效果参数 params': [pct(x) for x in g[2:]]})
            out['refine_tables'].append({'表ID table_id': tid, '法宝 item_id': tid,
                                         '法宝名 item_name': names.get(tid, ''), 'levels': levels})
    out['_说明'] = {
        'growth': '每升一级的属性增量; 1 级行为 0。列顺序经战斗代码确认 (第 5 列防御、第 6 列仙攻, 8–11 列命中/回避/法术命中/法术回避)',
        'exp_table': '(等级, 经验值) 对',
        'refine_tables': 'LEVEL 条目 4-19, 表ID = 法宝的游戏编号 (= 法宝 0x3ED 字段)',
        'table20': 'LEVEL 条目 20, 含义未明',
    }
    return out


# ------------------------------------------------------------ 输出

def flat(v):
    if isinstance(v, list):
        return '; '.join(flat(x) for x in v)
    if isinstance(v, dict):
        return ' '.join(f'{k}={flat(x)}' for k, x in v.items())
    return '' if v is None else str(v)


def write(out_dir, name, rows):
    with open(os.path.join(out_dir, name + '.json'), 'w', encoding='utf-8') as f:
        json.dump(rows, f, ensure_ascii=False, indent=1)
    if not rows or not isinstance(rows, list):
        return
    cols = []
    for r in rows:
        for k in r:
            if k not in cols:
                cols.append(k)
    with open(os.path.join(out_dir, name + '.csv'), 'w', encoding='utf-8-sig', newline='') as f:
        w = csv.writer(f)
        w.writerow(cols)
        for r in rows:
            w.writerow([flat(r.get(c)) for c in cols])


def battles_by_enemy(game, out_dir):
    # 文本提取的输出 (同一个提取目录下的 text/); 以前写死读仓库里的 extracted/text, 换输出目录 / 打包后就读不到
    path = os.path.join(os.path.dirname(os.path.abspath(out_dir)), 'text', 'battlefields.json')
    if not os.path.exists(path):
        return None
    out = {}
    for b in json.load(open(path, encoding='utf-8'))['battlefields']:
        for e in sorted(set(b['enemy_ids'][:b['enemy_count']])):
            out.setdefault(e, []).append({'index': b['index'], 'name': b['name_simplified']})
    return out


def main(game, out_dir):
    os.makedirs(out_dir, exist_ok=True)
    recs = load_objdata(os.path.join(game, 'ObjDATA.GLL'))
    names = {i + 1: r.get('name', '') for i, r in recs.items()}   # 游戏编号 → 名称
    lv = level_tables(os.path.join(game, 'LEVEL.GLL'), names)
    learned = {}
    for who, rows in lv['growth'].items():
        for row in rows:
            if row['习得法术 learn_skill']:
                learned.setdefault(row['习得法术 learn_skill'], []).append(f"{who} Lv{row['等级 level']}")
    battles = battles_by_enemy(game, out_dir)
    chars, mons, items, equips, mags, blds = [], [], [], [], [], []
    for i, r in sorted(recs.items()):
        k = r.get('kind')
        if k == 1:
            u = unit(r, names, None if i < 100 else battles)
            (chars if i < 100 else mons).append(u)
            if i < 100:
                for s in u['技能 skills']:
                    learned.setdefault(s['id'], []).append(f"{u['名称 name']} 初始")
        elif k == 2:
            (equips if r.get('sub') in EQUIP_SLOT else items).append(item(r, names))
        elif k == 3:
            mags.append(r)
        elif k == 4:
            blds.append(building(r))
    mags = [magic(r, names, learned) for r in mags]
    for name, rows in [('characters', chars), ('monsters', mons), ('items', items), ('equipment', equips),
                       ('magic', mags), ('buildings', blds)]:
        write(out_dir, name, rows)
    with open(os.path.join(out_dir, 'level_growth.json'), 'w', encoding='utf-8') as f:
        json.dump(lv, f, ensure_ascii=False, indent=1)
    for who, rows in lv['growth'].items():
        write(out_dir, f'level_growth_{who}', rows)
    write(out_dir, 'exp_table', lv['exp_table'])
    print(Counter({'characters': len(chars), 'monsters': len(mons), 'items': len(items), 'equipment': len(equips),
                   'magic': len(mags), 'buildings': len(blds)}))


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
