"""轩辕剑外传·苍之涛 剧情 / 文本浏览页 (本地 HTML, 不随项目分发)

用法: python story_html.py <extracted 目录> [输出目录, 默认 <extracted>/story] [--game 游戏目录]
输入: scripts/events_index.json, scripts/pseudo/*/*.txt (事件伪代码), scripts/battle/FIGTALK/*.txt (战斗对白),
      text/missions.json, text/battlefields.json, stats/*.json
输出: index.html + story.css + story.js + data/*.js (每个分区一个 JS, 直接用 <script> 加载, file:// 下也能打开)

分章: 原版没有章节编号。事件编号按剧情推进分段 (talks1-1~1-4 为主线, 每段对应一个地区), 这里按事件编号和
所在地区划分章节; 2001 以后的 NPC 对话 / 地图事件按所在地图归类。地图依次取自: 触发区; MAPS.DAT 段 2
的 NPC 摆放表 (每条 24 字节: 地图号, 角色号, 0, 模型, 0, 朝向, x, y, z, 调查事件号, …; NPC 对话事件的编号通常
就是角色号); 剧情脚本里 place_actor_map 放置该角色的地图。
"""
import collections
import json
import os
import re
import struct
import sys

CHAPTERS = [
    ('ch01', '序章　令狐国', '车氏采邑 · 木甲工房 · 攻敌密道 · 令狐国牢房', 1, 149),
    ('ch02', '第二段　晋国曲沃', '曲沃城 · 曲沃离宫', 150, 199),
    ('ch03', '第三段　太行三陉', '滏口陉 · 井陉 · 飞狐陉 · 太恒山', 200, 249),
    ('ch04', '第四段　齐国', '临淄城 · 泰山 · 封神台 · 东海滨 · 天书世界', 250, 499),
    ('ch05', '第五段　楚国', '小封神台 · 龙脉 · 郢都 · 云梦泽 · 霍山 · 朱雀结界', 500, 649),
    ('ch06', '第六段　秦国', '太室山 · 雍城 · 秦宫 · 华山', 650, 749),
    ('ch07', '第七段　昆仑界', '陈宝祭庙 · 昆仑界 · 镜中世界', 750, 799),
    ('ch08', '第八段　崤山与周穆王陵', '雍城 · 崤山 · 华山 · 周穆王陵墓', 800, 999),
    ('ch09', '第九段　伏羲宫与昊泽', '伏羲宫 · 昊泽 · 周穆王陵墓', 1000, 1499),
    ('ch10', '终章　昊天界', '昊天界 · 太一迷宫 · 太一圣殿', 1500, 1599),
    ('ch11', '补充　各段补充事件', '编号 1600–2000 的事件（跨章节的补充剧情、回忆等）', 1600, 2000),
]
NOTE_KINDS = {'change_map': '场景', 'start_battle': '战斗', 'play_music': '音乐', 'play_video': '动画',
              'give_item': '得到', 'take_item': '失去', 'add_money': '金钱', 'sub_money': '金钱',
              'call_event': '转入事件', 'heal_member': '回复'}

RE_TALK = re.compile(r'^(\s*)([^\s"(){}][^"(){}]*?): "(.*)"(\s*//\s*选项: (.*))?$')
RE_CALL = re.compile(r'^(\s*)([a-z_]+)\((.*)\)\s*(//.*)?$')
RE_NAME = re.compile(r'<([^<>]*)>')


def short_map(s):
    """12403_室内_令狐国木工房 → 令狐国木工房"""
    return s.split('_', 2)[-1] if s.count('_') >= 2 else s


def pretty_cond(s):
    s = re.sub(r'flag\[0x[0-9a-f]+ (任务接取|任务完成):([^\]]*)\]', r'「\2」\1', s)
    s = re.sub(r'flag\[0x[0-9a-f]+ ([^\]]*)\]', r'\1', s)
    s = re.sub(r'flag\[0x([0-9a-f]+)\]', lambda m: '旗标 %d' % int(m.group(1), 16), s)
    s = re.sub(r'\bnot all\((.*)\)$', r'并非全部 (\1)', s)
    s = re.sub(r'\ball\((.*)\)$', r'全部 (\1)', s)
    s = re.sub(r'\bany\((.*)\)$', r'任一 (\1)', s)
    s = re.sub(r'^not ', '未 ', s)
    return s


def note_of(fn, args):
    names = [short_map(x) for x in RE_NAME.findall(args)]
    if fn == 'change_map':
        return names[0] if names else args
    if fn == 'start_battle':
        m = re.match(r'(\d+)', args)
        return (names[0] if names else args), int(m.group(1)) if m else None
    if fn == 'play_music':
        return names[0] if names else args
    if fn == 'play_video':
        return args.strip('"')
    if fn in ('give_item', 'take_item'):
        n = re.search(r',\s*(-?\d+)\s*$', args)
        return '%s ×%s' % (names[0] if names else args, n.group(1) if n else 1)
    if fn in ('add_money', 'sub_money'):
        v = re.match(r'(-?\d+)', args)
        return ('+' if fn == 'add_money' else '−') + (v.group(1) if v else args)
    if fn == 'call_event':
        return int(re.match(r'(\d+)', args).group(1)) if re.match(r'(\d+)', args) else args
    if fn == 'heal_member':
        return '全员' if not names else '、'.join(names)
    return args


def parse_pseudo(text):
    """伪代码 → [缩进, 类型, ...] 列表
    类型: t 台词 (说话者, 文本) / n 旁白 / p 选项提示 (说话者, 文本, 选项) / c 分支项 / i 条件 / e 否则 /
          r 随机 / x 注记 (种类, 内容[, 链接]) / f 任务 (接取|完成, 名称) / k 其他指令 (原文)"""
    out = []
    for raw in text.splitlines():
        if raw.startswith('//') or not raw.strip():
            continue
        ind = (len(raw) - len(raw.lstrip(' '))) // 2
        s = raw.strip()
        m = RE_TALK.match(raw)
        if m and not s.startswith(('if ', 'case ')):
            who, txt, opts = m.group(2), m.group(3), m.group(5)
            if opts:
                out.append([ind, 'p', who, txt, opts])
            elif who == 'narrate':
                out.append([ind, 'n', txt])
            else:
                out.append([ind, 't', who, txt])
            continue
        if s.startswith('switch choice'):
            out.append([ind, 'k', s])
            continue
        mc = re.match(r'case (\d+)(?: "(.*)")?:', s)
        if mc:
            out.append([ind, 'c', ('选「%s」' % mc.group(2)) if mc.group(2) is not None else ('第 %d 种' % (int(mc.group(1)) + 1))])
            continue
        if s == 'default:':
            out.append([ind, 'c', '其他情况'])
            continue
        if s.startswith('random'):
            out.append([ind, 'r', s.split('//', 1)[1].strip() if '//' in s else '随机'])
            continue
        mi = re.match(r'if (.*?) \{$', s)
        if mi:
            out.append([ind, 'i', pretty_cond(mi.group(1))])
            continue
        if s in ('} else {',):
            out.append([ind, 'e'])
            continue
        if s in ('}', 'break', 'return') or re.match(r'^L_[0-9a-f]+:$', s):
            out.append([ind, 'k', s])
            continue
        mf = re.match(r'set_flag\(flag\[0x[0-9a-f]+ (任务接取|任务完成):(.*)\]\)$', s)
        if mf:
            out.append([ind, 'f', mf.group(1)[2:], mf.group(2)])
            continue
        mcall = RE_CALL.match(raw)
        if mcall and mcall.group(2) in NOTE_KINDS:
            fn, args = mcall.group(2), mcall.group(3)
            v = note_of(fn, args)
            if fn == 'start_battle':
                out.append([ind, 'x', NOTE_KINDS[fn], v[0], v[1]])
            elif fn == 'call_event':
                out.append([ind, 'x', NOTE_KINDS[fn], '事件 %s' % v, v])
            else:
                out.append([ind, 'x', NOTE_KINDS[fn], v])
            continue
        out.append([ind, 'k', s])
    return prune(out)


def prune(lines):
    """结构行 (条件 / 分支 / 随机 / 否则) 所辖范围里没有剧情内容时, 降为 k (默认隐藏)"""
    story = {'t', 'n', 'p', 'x', 'f'}
    for i, ln in enumerate(lines):
        if ln[1] not in ('i', 'c', 'r', 'e'):
            continue
        has = False
        for nx in lines[i + 1:]:
            if nx[0] <= ln[0] and not (ln[1] in ('c',) and nx[0] > ln[0] - 1 and False):
                if nx[0] < ln[0] or nx[1] in ('c', 'e', 'i', 'r') or (nx[1] == 'k' and nx[2] == '}'):
                    break
            if nx[1] in story:
                has = True
                break
        if not has:
            lines[i] = [ln[0], 'k', {'i': 'if %s' % ln[2] if len(ln) > 2 else 'if', 'c': 'case %s' % (ln[2] if len(ln) > 2 else ''),
                                     'r': 'random', 'e': 'else'}[ln[1]]]
    return lines


def parse_figtalk(path):
    """战斗对白 (反汇编) → [(说话者, 文本)]"""
    out, who = [], ''
    for raw in open(path, encoding='utf-8'):
        m = re.match(r'\s*\d+\s+speaker_name\s+\d+, "(.*)"', raw)
        if m:
            who = m.group(1)
            continue
        m = re.match(r'\s*\d+\s+(text|system_message)\s+.*?"(.*)"\s*$', raw)
        if m:
            t = re.sub(r'%[A-Z]\d*', '', m.group(2)).replace('``', '').strip()
            if t:
                out.append([who if m.group(1) == 'text' else '', t])
    return out


def clean_text(s):
    return re.sub(r'%C\d', '', s.replace('%N', '\n')).strip()


def npc_table(game, map_ids):
    """MAPS.DAT 段 2 (NPC 摆放): {事件号或角色号: Counter(地图号)}"""
    p = os.path.join(game or '', 'MAPS.DAT')
    res = collections.defaultdict(collections.Counter)
    if not game or not os.path.exists(p):
        return res
    d = open(p, 'rb').read()
    base = struct.unpack_from('<H', d, 8)[0] * 16
    segs = struct.unpack_from('<20I', d, base)
    lo = base + segs[2]
    hi = min([base + x for x in segs if base + x > lo] + [len(d)])
    i = lo
    while i + 24 <= hi:
        m, a = struct.unpack_from('<HH', d, i)
        if m in map_ids and 1 <= a < 10000:
            ev = struct.unpack_from('<H', d, i + 18)[0]
            res[a][m] += 1
            if ev and ev != a:
                res[ev][m] += 1
            i += 24
        else:
            i += 2
    return res


def main(ext, out, game=None):
    E = json.load(open(os.path.join(ext, 'scripts', 'events_index.json')))['events']
    missions = json.load(open(os.path.join(ext, 'text', 'missions.json')))
    pseudo_dir = os.path.join(ext, 'scripts', 'pseudo')

    # 每个事件的伪代码 (共享脚本的事件指向同一份)
    lines_of, raw_of = {}, {}
    actor_maps = collections.defaultdict(collections.Counter)
    actor_event = {}
    for d in sorted(os.listdir(pseudo_dir)):
        dp = os.path.join(pseudo_dir, d)
        if not os.path.isdir(dp):
            continue
        for f in sorted(os.listdir(dp)):
            txt = open(os.path.join(dp, f), encoding='utf-8').read()
            head = txt.splitlines()[0] if txt else ''
            ids = [int(x) for x in re.findall(r'\d+', head.split('events', 1)[1].split(']')[0])] if 'events' in head else [int(f[:4])]
            parsed = parse_pseudo(txt)
            for i in ids:
                lines_of[i] = parsed
                raw_of[i] = '%s/%s' % (d, f)
            for m in re.finditer(r'place_actor_map\(0x([0-9a-f]+)<[^>]*>, \d+<([^>]*)>', txt):
                actor_maps[int(m.group(1), 16)][short_map(m.group(2))] += 1
            for m in re.finditer(r'set_actor_event\(0x([0-9a-f]+)<[^>]*>, (\d+)\)', txt):
                actor_event.setdefault(int(m.group(2)), int(m.group(1), 16))

    maps = json.load(open(os.path.join(ext, 'text', 'maps.json')))
    map_name = {m['map_id']: short_map(m.get('name_simplified', m['name'])) for m in maps}
    npc = npc_table(game, set(map_name))
    map_id = {v: k for k, v in sorted(map_name.items(), reverse=True)}

    def where_of(eid):
        e = E.get(str(eid), {})
        t = [x for x in e.get('triggers', [])]
        if t:
            return short_map(t[0]['map']), t[0].get('name', '')
        cm = e.get('change_map', [])
        if eid <= 2000 and cm:  # 剧情事件: 取事件里第一次切换到的场景
            return short_map(cm[0]['map']), ''
        actor = actor_event.get(eid, eid)
        for k in (eid, actor):
            if npc.get(k):
                return map_name[npc[k].most_common(1)[0][0]], ''
        if actor_maps.get(actor):
            return actor_maps[actor].most_common(1)[0][0], ''
        return '', ''

    mission_name = {m['mission_id']: m['text'] for m in missions}
    battles_used = collections.defaultdict(list)

    def event_record(eid):
        e = E.get(str(eid), {})
        ls = lines_of.get(eid, [])
        mp, trig = where_of(eid)
        for ln in ls:
            if ln[1] == 'x' and ln[2] == '战斗' and ln[4] is not None:
                battles_used[ln[4]].append(eid)
        talk = sum(1 for ln in ls if ln[1] in ('t', 'n', 'p'))
        return {'id': eid, 'src': raw_of.get(eid, e.get('disasm', '')), 'map': mp, 'mid': map_id.get(mp, 99999), 'trig': trig,
                'acc': [mission_name.get(m, str(m)) for m in dict.fromkeys(e.get('mission_accept', []))],
                'comp': [mission_name.get(m, str(m)) for m in dict.fromkeys(e.get('mission_complete', []))],
                'talk': talk, 'lines': ls}

    all_ids = sorted(int(k) for k in E)
    sections = []
    for key, title, sub, lo, hi in CHAPTERS:
        evs = [event_record(i) for i in all_ids if lo <= i <= hi]
        sections.append({'key': key, 'group': '剧情', 'title': title, 'sub': sub, 'events': evs})
    for key, title, lo, hi, sub in (('npc', '城镇与 NPC 对话', 2001, 5000, '编号 2001–5000，按所在地图归类'),
                                    ('map', '地图事件与支线', 5001, 9999, '编号 5001 以后，按所在地图归类')):
        evs = [event_record(i) for i in all_ids if lo <= i <= hi]
        evs.sort(key=lambda r: (r['mid'], r['map'], r['id']))  # 地图按编号 (大致是到访先后)
        sections.append({'key': key, 'group': '其他对话', 'title': title, 'sub': sub, 'events': evs, 'by_map': True})

    # 任务: 接取 / 完成事件
    acc, comp = collections.defaultdict(list), collections.defaultdict(list)
    for k, e in E.items():
        for m in e.get('mission_accept', []):
            acc[m].append(int(k))
        for m in e.get('mission_complete', []):
            comp[m].append(int(k))
    mission_rows = [{'id': m['mission_id'], 'kind': m['kind'], 'text': clean_text(m['text']),
                     'acc': sorted(set(acc.get(m['mission_id'], []))), 'comp': sorted(set(comp.get(m['mission_id'], [])))}
                    for m in missions]

    # 战斗对白
    fig_dir = os.path.join(ext, 'scripts', 'battle', 'FIGTALK')
    battles = []
    for f in sorted(os.listdir(fig_dir)):
        path = os.path.join(fig_dir, f)
        head = open(path, encoding='utf-8').readline()
        m = re.search(r'\(战场 (\d+) ([^)]*)\)', head)
        if not m:
            continue
        bid, name = int(m.group(1)), m.group(2)
        talk = parse_figtalk(path)
        battles.append({'id': bid, 'name': re.sub(r'_\d+$', '', name), 'lines': talk,
                        'events': sorted(set(battles_used.get(bid, [])))})

    # 图鉴
    codex = []
    for fn, title in (('characters', '主角'), ('monsters', '怪物与敌人'), ('items', '道具'), ('equipment', '装备'),
                      ('magic', '法术与技能'), ('buildings', '建筑')):
        p = os.path.join(ext, 'stats', fn + '.json')
        if not os.path.exists(p):
            continue
        rows = []
        for r in json.load(open(p)):
            name = r.get('名称 name', '')
            if not name:
                continue
            extra = []
            for k in ('子类 sub_name', '部位 slot', '可用角色 users', '目标阵营 side', '范围 scope', '等级 level'):
                if r.get(k):
                    extra.append('%s：%s' % (k.split(' ')[0], r[k]))
            rows.append({'id': r.get('编号 id'), 'name': name, 'desc': clean_text(r.get('描述 desc', '') or ''),
                         'note': clean_text(r.get('附注 note', '') or ''), 'extra': '　'.join(extra)})
        codex.append({'title': title, 'rows': rows})

    os.makedirs(os.path.join(out, 'data'), exist_ok=True)
    meta = {'sections': [{'key': s['key'], 'group': s['group'], 'title': s['title'], 'sub': s['sub'],
                          'count': len(s['events']), 'talk': sum(1 for e in s['events'] if e['talk'])} for s in sections]}
    scripts = []

    def dump(name, var, obj):
        with open(os.path.join(out, 'data', name + '.js'), 'w', encoding='utf-8') as fp:
            fp.write('STORY[%s]=' % json.dumps(var, ensure_ascii=False))
            json.dump(obj, fp, ensure_ascii=False, separators=(',', ':'))
            fp.write(';\n')
        scripts.append('data/%s.js' % name)

    dump('meta', 'meta', meta)
    for s in sections:
        dump(s['key'], s['key'], s)
    dump('missions', 'missions', mission_rows)
    dump('battles', 'battles', battles)
    dump('codex', 'codex', codex)

    here = os.path.dirname(os.path.abspath(__file__))
    for asset in ('story.css', 'story.js'):
        with open(os.path.join(here, 'story_assets', asset), encoding='utf-8') as src, \
                open(os.path.join(out, asset), 'w', encoding='utf-8') as dst:
            dst.write(src.read())
    html = open(os.path.join(here, 'story_assets', 'index.html'), encoding='utf-8').read()
    html = html.replace('<!--DATA-->', '\n'.join('<script src="%s"></script>' % s for s in scripts))
    open(os.path.join(out, 'index.html'), 'w', encoding='utf-8').write(html)
    n_ev = sum(len(s['events']) for s in sections)
    n_talk = sum(e['talk'] for s in sections for e in s['events'])
    print('%d 个分区, %d 个事件, %d 句台词/旁白, %d 个任务, %d 个战场 (%d 个有对白) → %s' % (
        len(sections), n_ev, n_talk, len(mission_rows), len(battles), sum(1 for b in battles if b['lines']),
        os.path.join(out, 'index.html')))


if __name__ == '__main__':
    args = sys.argv[1:]
    game = None
    if '--game' in args:
        i = args.index('--game')
        game = args[i + 1]
        del args[i:i + 2]
    main(args[0], args[1] if len(args) > 1 else os.path.join(args[0], 'story'), game)
