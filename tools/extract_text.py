#!/usr/bin/env python3
"""轩辕剑外传·苍之涛 文本/关卡数据导出。

用法: python extract_text.py <游戏目录> <输出目录>
产出: GLL 文本 JSON、对白 txt、maps.json / map_graph.json / map_graph.dot、
      battlefields.json、missions.json、objdata.json、level.json、wld_models.json
"""
import json
import os
import re
import struct
import sys

import opencc

T2S = opencc.OpenCC('t2s').convert

# Big5 双字节 或 可打印 ASCII，直到 %Q 结束
TEXT_RE = re.compile(rb'(?:[\xa1-\xf9][\x40-\x7e\xa1-\xfe]|[\x20-\x7e])+?%Q')


def big5(b):
    return b.decode('big5', 'replace')


def cstr(b):
    return big5(b.split(b'\0')[0])


def dump(path, obj):
    with open(path, 'w', encoding='utf-8') as f:
        json.dump(obj, f, ensure_ascii=False, indent=1)


# ---------------------------------------------------------------- GLL022

def read_gll(path):
    """返回 [(index, offset, bytes|None)]。

    结构: 'GLL022' + 10 字节 0 → 16 字节头；之后是 u32 偏移表，
    偏移相对于文件第 16 字节；表长 = 第一个 u32 / 4（即表的字节长度）。
    0xffffffff = 空项。条目长度 = 到下一个不同偏移为止。
    """
    b = open(path, 'rb').read()
    assert b[:6] == b'GLL022', path
    first = struct.unpack_from('<I', b, 16)[0]
    offs = list(struct.unpack_from('<%dI' % (first // 4), b, 16))
    starts = sorted({o + 16 for o in offs if o != 0xffffffff}) + [len(b)]
    nxt = {s: starts[i + 1] for i, s in enumerate(starts[:-1])}
    out = []
    for i, o in enumerate(offs):
        if o == 0xffffffff:
            out.append((i, None, None))
        else:
            out.append((i, o, b[o + 16:nxt[o + 16]]))
    return out


def gll_strings(data):
    return [big5(m.group()[:-2]) for m in TEXT_RE.finditer(data)]


def gll_to_json(path):
    seen = {}
    entries = []
    for i, o, d in read_gll(path):
        if d is None:
            continue
        if o in seen:
            entries.append({'index': i, 'same_as': seen[o]})
            continue
        seen[o] = i
        strs = gll_strings(d)
        e = {'index': i, 'offset': o + 16, 'size': len(d)}
        if strs:
            txt = '\n'.join(strs)
            e['text_big5_decoded'] = txt
            e['text_simplified'] = T2S(txt)
        entries.append(e)
    return entries


CTRL_RE = re.compile(r'%[SC]\d')


def readable(s):
    """控制码: %N 换行, %Cn 颜色, %Sn 字号/速度, %Q 结束, %d 数值占位。"""
    s = CTRL_RE.sub('', s).replace('%Q', '')
    parts = s.split('%N')
    head = parts[0].strip()
    if len(parts) > 1 and head.endswith('：'):
        return '【%s】%s' % (head[:-1], ''.join(parts[1:]).strip())
    return '\n'.join(p.rstrip() for p in parts).strip()


def dialogue_txt(path, entries):
    lines = []
    for e in entries:
        if 'text_simplified' not in e:
            continue
        lines.append('==== 条目 %d (0x%x) ====' % (e['index'], e['offset']))
        for s in e['text_simplified'].split('\n'):
            r = readable(s)
            if r:
                lines.append(r)
        lines.append('')
    with open(path, 'w', encoding='utf-8') as f:
        f.write('\n'.join(lines))


# ---------------------------------------------------------------- ObjDATA

OBJ_TEXT_TAGS = {')': 'name', ',': 'desc', '-': 'note'}
OBJ_NUM_TAGS = {'*': 'tag_star', '.': 'tag_dot', '+': 'tag_plus'}


def parse_objdata(path):
    recs = []
    seen = {}
    for i, o, d in read_gll(path):
        if d is None:
            continue
        if o in seen:
            recs.append({'index': i, 'same_as': seen[o]})
            continue
        seen[o] = i
        r = {'index': i}
        p = 0
        while p + 1 < len(d) and d[p + 1] == 0x23 and chr(d[p]) in '),-*.+':
            t = chr(d[p])
            p += 2
            if t in OBJ_TEXT_TAGS:
                q = d.find(b'%Q', p)
                s = big5(d[p:q])
                r[OBJ_TEXT_TAGS[t]] = s
                r[OBJ_TEXT_TAGS[t] + '_simplified'] = T2S(s)
                p = q + 2
            else:
                r[OBJ_NUM_TAGS[t]] = struct.unpack_from('<H', d, p)[0]
                p += 2
        r['stats_raw_hex'] = d[p:].hex()
        recs.append(r)
    return recs


# ---------------------------------------------------------------- LEVEL

def parse_level(path):
    out = []
    for i, o, d in read_gll(path):
        if d is None:
            continue
        body = d[:-4] if d.endswith(b'\xb1\x26\xff\xff') else d  # 结束标记 0xffff26b1
        e = {'index': i, 'size': len(d)}
        if i <= 2:
            n = len(body) // 32
            e['guess'] = '角色每级成长表: 每行16个u16, 第1个=等级'
            e['rows'] = [list(struct.unpack_from('<16H', body, 32 * k)) for k in range(n)]
        elif i == 3:
            n = len(body) // 8
            e['guess'] = '经验表: (等级, 所需经验) u32对'
            e['rows'] = [list(struct.unpack_from('<2I', body, 8 * k)) for k in range(n)]
        elif i == 20:
            n = len(body) // 6
            e['guess'] = 'u16 三元组 (等级, a, b)'
            e['rows'] = [list(struct.unpack_from('<3H', body, 6 * k)) for k in range(n)]
        else:
            e['guess'] = '首个u32为表ID(5201+), 其后 1..5 级数值 (i32)'
            e['u32'] = list(struct.unpack_from('<%di' % (len(body) // 4), body))
        out.append(e)
    return out


def parse_ai(path):
    seen = {}
    out = []
    for i, o, d in read_gll(path):
        if d is None:
            continue
        if o in seen:
            continue
        seen[o] = i
        out.append({'index': i, 'u16': list(struct.unpack_from('<%dH' % (len(d) // 2), d))})
    return out


# ---------------------------------------------------------------- MAP

def parse_map(path):
    b = open(path, 'rb').read()
    assert b[:4] == b'MAP\0'
    mid, scene = struct.unpack_from('<HH', b, 8)
    m = {
        'file': os.path.basename(path),
        'map_id': mid,
        'scene_id': scene,  # 共用场景几何时与 map_id 不同
        'cell_size': struct.unpack_from('<3f', b, 0x26),
        'world_size': struct.unpack_from('<3f', b, 0x3e),
        'grid': struct.unpack_from('<3I', b, 0x4a),
        'unk_f6a': round(struct.unpack_from('<f', b, 0x6a)[0], 4),
        'name': cstr(b[0x72:0x92]),
    }
    m['name_simplified'] = T2S(m['name'])
    parts = m['name'].split('_', 2)
    m['type'] = T2S(parts[1]) if len(parts) == 3 else ''
    m['short_name'] = parts[2] if len(parts) == 3 else m['name']
    n = struct.unpack_from('<H', b, 0x92)[0]
    portals = []
    for i in range(n):
        r = 0x94 + 84 * i
        bmin = struct.unpack_from('<3f', b, r + 2)
        bmax = struct.unpack_from('<3f', b, r + 18)
        pos = struct.unpack_from('<3f', b, r + 34)
        ev, unk = struct.unpack_from('<HH', b, r + 50)
        name = cstr(b[r + 54:r + 84])
        portals.append({
            'kind': 'portal' if target_of(name) else 'event',
            'flag': struct.unpack_from('<H', b, r)[0],
            'name': name, 'name_simplified': T2S(name),
            'pos': [round(x, 2) for x in pos],
            'box_min': [round(x, 2) for x in bmin],
            'box_max': [round(x, 2) for x in bmax],
            'event_id': ev, 'unk': unk,
        })
    m['portals'] = portals
    t = 0x94 + 84 * n
    cnt = struct.unpack_from('<I', b, t + 2)[0]
    trig = []
    for k in range(cnt):
        ev = struct.unpack_from('<I', b, t + 6 + 16 * k)[0]
        pos = struct.unpack_from('<3f', b, t + 10 + 16 * k)
        trig.append({'event_id': ev, 'pos': [round(x, 2) for x in pos]})
    m['triggers'] = trig
    assert t + 6 + 16 * cnt == len(b), path
    return m


def target_of(portal_name):
    for sep in ('-->', '->', '-》', '－>'):
        if sep in portal_name:
            return portal_name.split(sep, 1)[1].strip()
    return None


# 传送点名称与地图名不一致、自动匹配会出错的情况（人工核对，简体名 → map_id）
ALIASES = {
    '第一岛': 12631, '第二岛': 12632, '第三岛': 12633, '第四岛': 12634, '第五岛': 12635,
    '秦王宫': 12428, '秦王宫寝房': 12429, '秦王宫后院': 12430,
    '临淄木工房': 12413, '曲沃大殿': 13002,
    '滏口陉前段': 12611, '滏口陉后段': 12612,
    '密道入口A': 12609, '密道入口B': 12609, '密道入口C': 12609,  # 由 12609 的反向传送推断
    '崤山峡谷入口': 13027, '崤山峡谷出口': 13028, '崤山峡谷后段': 13028,
}


def _norm(x):
    return T2S(x).replace(' ', '').replace('市集', '').replace('城', '')


def lcs(a, b):
    best = 0
    for i in range(len(a)):
        for j in range(i + best + 1, len(a) + 1):
            if a[i:j] in b:
                best = j - i
            else:
                break
    return best


def resolve(target, maps):
    """按地图短名匹配传送目标，返回 (map_id, 匹配方式)。"""
    if not target:
        return None, None
    alias = ALIASES.get(T2S(target))
    if alias:
        return alias, 'alias'
    exact = [m for m in maps if m['short_name'] == target]
    if exact:
        return exact[0]['map_id'], 'exact'
    norm = [m for m in maps if _norm(m['short_name']) == _norm(target)]
    if norm:
        return norm[0]['map_id'], 'normalized'
    cands = [m for m in maps if target in m['short_name'] or m['short_name'] in target]
    if cands:
        cands.sort(key=lambda m: abs(len(m['short_name']) - len(target)))
        return cands[0]['map_id'], 'contains'
    scored = sorted(((lcs(target, m['short_name']), m) for m in maps), key=lambda x: -x[0])
    if scored and scored[0][0] >= 3:
        return scored[0][1]['map_id'], 'fuzzy'
    return None, None


def map_graph(maps):
    nodes = [{'id': m['map_id'], 'name': m['name_simplified'], 'type': m['type'],
              'scene_id': m['scene_id']} for m in maps]
    edges = []
    for m in maps:
        for p in m['portals']:
            if p['kind'] != 'portal':
                continue
            tgt = target_of(p['name'])
            to, how = resolve(tgt, maps)
            edges.append({'from': m['map_id'], 'to': to, 'match': how,
                          'target_name': T2S(tgt),
                          'portal': p['name_simplified'], 'event_id': p['event_id']})
    return {'nodes': nodes, 'edges': edges}


def graph_dot(g):
    out = ['digraph czt {', '  rankdir=LR; node [shape=box, fontname="PingFang SC"];']
    for n in g['nodes']:
        out.append('  m%d [label="%d\\n%s"];' % (n['id'], n['id'], n['name']))
    done = set()
    for e in g['edges']:
        if e['to'] is None:
            key = (e['from'], e['target_name'])
            if key in done:
                continue
            done.add(key)
            ext = 'x_%d_%d' % (e['from'], len(done))
            out.append('  %s [label="%s?", style=dashed];' % (ext, e['target_name'] or e['portal']))
            out.append('  m%d -> %s [style=dashed];' % (e['from'], ext))
        else:
            key = (e['from'], e['to'])
            if key in done:
                continue
            done.add(key)
            out.append('  m%d -> m%d%s;' % (key + (' [style=dotted]' if e['match'] == 'fuzzy' else '',)))
    out.append('}')
    return '\n'.join(out)


# ---------------------------------------------------------------- WLD index

def parse_wld_idx(path):
    b = open(path, 'rb').read()
    assert b[:7] == b'IDX_WLD'
    n = struct.unpack_from('<I', b, 0x68)[0]
    nums = struct.unpack_from('<%dI' % n, b, 0x80)
    out = []
    for i, num in enumerate(nums):
        if not num:
            continue
        usz, csz = struct.unpack_from('<2I', b, 0x2f60 + 8 * i)
        name = cstr(b[0x8d20 + 32 * i:0x8d20 + 32 * i + 32])
        out.append({'slot': i, 'file': 'Model/MAP%05d.WLD' % num, 'name': name,
                    'name_simplified': T2S(name), 'unpacked_size': usz, 'packed_size': csz})
    return out


# ---------------------------------------------------------------- BattleField

BF_REC0 = 0x18 + 40000   # 文件头 0x18 + 名字表 40000 字节, 之后 300 条 × 776 字节 (exe load_field 0x44c51d)
BF_STRIDE = 776


def parse_battlefield(path, objnames):
    b = open(path, 'rb').read()
    used, slots = struct.unpack_from('<HH', b, 0)
    out = []
    for i in range(slots):
        name = cstr(b[0x18 + 40 * i:0x18 + 40 * i + 40])
        # 战场 N (事件 start_battle N) = 第 N-1 条记录 (0x43fb05): +0x18 敌人坐标 vec4×32, +0x218 朝向 f32×32,
        # +0x27a 战斗场景 ACT (如 12804), +0x282 敌人数, +0x284 敌人编号 (游戏编号) ×24
        r0 = BF_REC0 + BF_STRIDE * i
        scene = struct.unpack_from('<H', b, r0 + 0x27a)[0]
        cnt = struct.unpack_from('<H', b, r0 + 0x282)[0]
        ids = [x for x in struct.unpack_from('<24H', b, r0 + 0x284) if x]
        alt = [x for x in struct.unpack_from('<24H', b, r0 + 0x2b4) if x]
        pos = [[round(v, 1) for v in struct.unpack_from('<3f', b, r0 + 0x18 + 16 * k)]
               for k in range(min(cnt, 24))]
        facing = [round(v, 1) for v in struct.unpack_from('<%df' % min(cnt, 24), b, r0 + 0x218)]
        if not name and not ids:
            continue
        out.append({
            'index': i, 'name': name, 'name_simplified': T2S(name),
            'scene_act': scene,
            'enemy_count': cnt,
            'enemy_ids': ids, 'enemies': [objnames.get(x, '?') for x in ids],
            'alt_enemy_ids': alt, 'enemy_pos': pos, 'enemy_facing': facing,
            # 记录开头 6 个 float = 战场雾 (0x44c51d 读入 0x924c90, 0x43fda7 → 0x4146bb; 第 5 个 ≤ 0 不开雾)
            'fog': [round(v, 4) for v in struct.unpack_from('<6f', b, r0)],
        })
    return {'header': {'used': used, 'slots': slots}, 'battlefields': out}


# ---------------------------------------------------------------- main

def main():
    G, O = sys.argv[1], sys.argv[2]
    os.makedirs(os.path.join(O, 'gll'), exist_ok=True)
    os.makedirs(os.path.join(O, 'dialogue'), exist_ok=True)

    glls = sorted(f for f in os.listdir(G) if f.lower().endswith('.gll'))
    for f in glls:
        p = os.path.join(G, f)
        stem = os.path.splitext(f)[0]
        if f.upper() == 'LEVEL.GLL':
            dump(os.path.join(O, 'level.json'), parse_level(p))
            continue
        if f.upper() == 'AI.GLL':
            dump(os.path.join(O, 'ai_bytecode.json'), parse_ai(p))
            continue
        entries = gll_to_json(p)
        dump(os.path.join(O, 'gll', stem + '.json'),
             {'file': f, 'entry_count': len(entries), 'entries': entries})
        if stem.lower().startswith(('talks', 'figtalk', 'atk')):
            dialogue_txt(os.path.join(O, 'dialogue', stem + '.txt'), entries)
        print('gll', f, len(entries))

    obj = parse_objdata(os.path.join(G, 'ObjDATA.GLL'))
    dump(os.path.join(O, 'objdata.json'), obj)
    objnames = {}
    for r in obj:
        src = r if 'same_as' not in r else next(x for x in obj if x['index'] == r['same_as'])
        if 'name_simplified' in src:
            objnames[r['index'] + 1] = src['name_simplified']   # 游戏编号 = ObjDATA 下标 + 1

    missions = []
    for e in gll_to_json(os.path.join(G, 'Mission.GLL')):
        if 'text_big5_decoded' not in e:
            continue
        t = e['text_simplified']
        kind = '主线' if t.startswith('★') else '支线' if t.startswith('☆') else '其他'
        missions.append({'mission_id': e['index'], 'kind': kind,
                         'text': t.lstrip('★☆').strip(), 'text_big5': e['text_big5_decoded']})
    dump(os.path.join(O, 'missions.json'), missions)

    maps = [parse_map(os.path.join(G, 'MAP', f))
            for f in sorted(os.listdir(os.path.join(G, 'MAP'))) if f.upper().endswith('.MAP')]
    dump(os.path.join(O, 'maps.json'), maps)
    g = map_graph(maps)
    dump(os.path.join(O, 'map_graph.json'), g)
    with open(os.path.join(O, 'map_graph.dot'), 'w', encoding='utf-8') as f:
        f.write(graph_dot(g))

    dump(os.path.join(O, 'wld_models.json'), parse_wld_idx(os.path.join(G, 'Model', 'ALL_MAP.IDX')))
    dump(os.path.join(O, 'battlefields.json'),
         parse_battlefield(os.path.join(G, 'ACT', 'BattleField.dat'), objnames))
    print('maps', len(maps), 'portal edges', len(g['edges']),
          'match', {k: sum(1 for e in g['edges'] if e['match'] == k)
                    for k in ('exact', 'alias', 'normalized', 'contains', 'fuzzy', None)},
          'missions', len(missions))


if __name__ == '__main__':
    main()
