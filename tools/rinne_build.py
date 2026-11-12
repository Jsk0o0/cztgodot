"""轮回篇（同人原创二周目）编译器：godot/rinne/src/*.txt → godot/rinne/rinne.json

输出只含补丁（插在原版事件哪个位置、插什么新指令）和新事件，不含原版剧本：
原版代码在游戏运行时从玩家本机提取的数据读出，再由 ModManager.rinne_apply 拼上补丁。
编译时需要本机的 extracted/game/events/*.json 来把「原版台词片段」换算成位置号，并借用附近原版对白的窗口参数。

用法: python tools/rinne_build.py [--check]
测试（窗口在后台，不抢鼠标）: 用一周目剧情快照 + --rinne 播某个事件
  cd godot && Godot --path . res://scenes/field.tscn -- --rinne --snapshot=../extracted/story/snapshots/<事件>.json --event=<事件>
     --choices=1,0 --skip-battles --no-video --no-music --auto-advance=0.05 --quit-after-event --trace-events --bg --park-mouse
  （--choices 依次选第几个选项，0 起；--skip-battles 剧情战直接算赢；跑完删掉 godot/override.cfg）

源文件格式（一行一条，# 开头是注释）:
  @事件号 after 「原版台词片段」[N]     在第 N 处（默认 1）含该片段的原版对白之后插入（含它后面的 wait_text）
  @事件号 before 「原版台词片段」[N]    在那句对白之前插入（含它前面的 window_color 等设置）
  @事件号 after #位置 / before #位置    按原版指令位置号插入（没有对白可当锚点时用）
  @new 名字                               新建一个独立事件（插叙、新场景），用 [call 名字] 调用；说话人借原版任意事件的对话框
  @事件号 alt 「起」 「止」 if 旗标      旗标成立时用下面的台词代替原版「起」到「止」这几句（不成立照原版）
  @事件号 replace 「起」 「止」          总是用下面的台词代替原版「起」到「止」（中间的动作 / 表情也一起跳过）
  片段在事件里出现不止一处时必须写 [N]
  块内:
    名字：台词                 角色对白（名字要在该事件的原版对白里出现过，借用它的窗口位置）
    字幕：台词                 黑底字幕（序章开场那种），前后要自己 [fadeout] / [fadein]
    [deja] / [deja 秒]         既视感画面效果
    [flag 名] / [unflag 名]    轮回篇旗标（编号见 godot/rinne/flags.json，只增不改）
    [bond 诗 +1]               羁绊 诗 / 桓 / 殷
    [choice 提示 | 选项1 | 选项2 ...]  选项（提示可空，由车芸说），之后 [case 1] … [case 2] … [end]
    [if 旗标] … [else] … [endif]   [ifbond 诗 >= 3] … [endif]   旗标写「原1302」= 原版旗标号
    [goto 「原版台词片段」]    跳到原版那句对白（的设置开头）；[goto end] 跳到本块结尾；[goto #位置] 跳到原版位置号
    [call 名字]                调用 @new 定义的新事件（call_event）
    [fadeout] / [fadein]       渐黑 / 渐亮（原版 fade 10）
    [stop]                     结束这个事件（跳过原版后面的内容；跳过前要自己补上原版会设的旗标 / 道具 / 入队）
    [wait 百分之一秒]
    [op ["指令", 参数...]]     直接写一条原版指令（JSON）
"""
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, 'godot', 'rinne', 'src')
OUT = os.path.join(ROOT, 'godot', 'rinne', 'rinne.json')
FLAGS = os.path.join(ROOT, 'godot', 'rinne', 'flags.json')
EVREG = os.path.join(ROOT, 'godot', 'rinne', 'events.json')   # 新事件名 → 事件号（990001 起，只增不改）
EVENT_BASE = 990000
EVENTS = os.path.join(ROOT, 'extracted', 'game', 'events')
FLAG_BASE = 190000000
NEW_POS = 1000000          # 新指令的位置号从这里起（原版脚本位置都小于 10 万）
BONDS = {'诗': 'shi', '桓': 'huan', '殷': 'yin'}
CARD = [1, 300, 200, 200, 200, 240, 15, 440, 120, 34826]   # 事件 10 开场字幕的窗口参数
CHOICE = [1, 0, 150, 470, 150, 470, 0, 510, 120, 2]       # 事件 258 / 503 选项的窗口参数


def strip(s):
    return re.sub(r'%[A-Z]\d?', '', s).replace('\n', '')


def load_events():
    ev = {}
    for f in sorted(os.listdir(EVENTS)):
        if not f.endswith('.json'):
            continue
        d = json.load(open(os.path.join(EVENTS, f), encoding='utf-8'))
        first = int(d['first'])
        for e, off in d['events'].items():
            e = int(e)
            # 每个文件只负责自己的事件范围（空槽指向本文件第一个脚本）
            span = 500 if first < 2001 else (3000 if first == 2001 else 2979)
            if off in d['codes'] and first <= e < first + span and e not in ev:
                ev[e] = d['codes'][off]
    return ev


class Err(Exception):
    pass


class Builder:
    def __init__(self, events):
        self.events = events
        self.flags = json.load(open(FLAGS, encoding='utf-8')) if os.path.exists(FLAGS) else {}
        self.evreg = json.load(open(EVREG, encoding='utf-8')) if os.path.exists(EVREG) else {}
        self.new_events = {}
        self.pos = {}       # 事件号 → 下一个新位置
        self.patches = {}
        self.errors = []

    def link_before_entries(self):
        """同一原版位置 P 前面插了 before 块时: 其他补丁里跳到 P 的指令改跳到第一个 before 块的开头
        (运行时 before 块按书写顺序排在 P 前面, 依次落下去); 原版代码自己跳到 P 会绕过插入内容 —— 只能警告"""
        self.warnings = getattr(self, 'warnings', [])
        jump_ops = ('goto', 'if_flag_goto', 'if_not_flag_goto', 'if_bond_ge_goto', 'menu_switch')
        for eid, plist in self.patches.items():
            entry = {}
            for k, p in enumerate(plist):
                if p['mode'] == 'before' and p['code'] and p['at'] not in entry:
                    entry[p['at']] = (k, p['code'][0][0])
            if not entry:
                continue
            orig_targets = set()
            for x in self.events[eid]:
                if x[1] in jump_ops:
                    for a in x[2:]:
                        for t in (a if isinstance(a, list) else [a]):
                            if isinstance(t, int):
                                orig_targets.add(t)
            for at in entry:
                if at in orig_targets:
                    self.warnings.append('事件 %d: 位置 %d 前插入的内容会被原版自己的跳转绕过' % (eid, at))
            for k, p in enumerate(plist):
                for ins in p['code']:
                    if ins[1] not in jump_ops:
                        continue
                    for j in range(2, len(ins)):
                        a = ins[j]
                        fix = lambda t: entry[t][1] if t in entry and entry[t][0] != k and not (p['mode'] == 'before' and p['at'] == t) else t
                        if isinstance(a, list):
                            ins[j] = [fix(t) if isinstance(t, int) else t for t in a]
                        elif isinstance(a, int) and j == len(ins) - 1:
                            ins[j] = fix(a)

    # ---- 辅助 ----
    def newpos(self, eid):
        p = self.pos.get(eid, NEW_POS)
        self.pos[eid] = p + 1
        return p

    def event_no(self, name):
        if name not in self.evreg:
            self.evreg[name] = EVENT_BASE + len(self.evreg) + 1
        return self.evreg[name]

    def flag(self, name):
        m = re.fullmatch(r'原(\d+)', name)   # 原版旗标号 (判断原版剧情进行到哪), 不进轮回篇旗标表
        if m:
            return int(m.group(1))
        if name not in self.flags:
            self.flags[name] = FLAG_BASE + len(self.flags) + 1
        return self.flags[name]

    def find_text(self, eid, frag, nth=None):
        code = self.events[eid]
        hits = [i for i, x in enumerate(code) if x[1] == 'text' and frag in strip(x[-1])]
        if not hits:
            raise Err('事件 %d 找不到原版对白「%s」' % (eid, frag))
        if nth is None:
            if len(hits) > 1:
                raise Err('事件 %d 有 %d 处「%s」，要写 [N] 指明第几处' % (eid, len(hits), frag))
            nth = 1
        if nth > len(hits):
            raise Err('事件 %d 只有 %d 处「%s」' % (eid, len(hits), frag))
        return hits[nth - 1]

    def group_start(self, eid, i):
        code = self.events[eid]
        while i > 0 and code[i - 1][1] in ('window_color', 'text_char_spacing', 'text_line_spacing', 'set_caption'):
            i -= 1
        return i

    def after_index(self, eid, i):
        code = self.events[eid]
        for j in range(i + 1, min(i + 7, len(code))):
            if code[j][1] == 'wait_text':
                return j
            if code[j][1] == 'text':
                break
        return i

    def speaker(self, eid, name, near):
        """名字 → (角色号, 窗口参数)：同一事件里离插入点最近的那人的原版对白"""
        code = self.events[eid]
        best = None
        for i, x in enumerate(code):
            if x[1] == 'text' and ('%C5' + name + '：') in x[-1].replace('%S3', '').replace('%S0', ''):
                if best is None or abs(i - near) < abs(best - near):
                    best = i
        if best is None:
            # 本事件里没有这个人: 借他在别的事件里的底部对话框 (原版对白 1 万多句里绝大多数是 1 号窗口)
            g = self.global_speaker(name)
            if g is None:
                raise Err('原版里找不到「%s」的对白，借不到窗口' % name)
            return g
        x = code[best]
        return x[2], x[3:12]

    def global_speaker(self, name):
        if not hasattr(self, '_gsp'):
            self._gsp = {}
            for e in sorted(self.events):
                for x in self.events[e]:
                    if x[1] == 'text' and x[2] == 1:
                        m = re.match(r'%C5([^：%]{1,12})：', x[-1].replace('%S3', '').replace('%S0', ''))
                        if m and m.group(1) not in self._gsp:
                            self._gsp[m.group(1)] = (1, x[3:12])
        return self._gsp.get(name)

    # ---- 指令 ----
    def text_group(self, eid, actor, params, s, card=False):
        P = lambda *a: [self.newpos(eid)] + list(a)
        if card:
            return [P('window_color', 1, 0, 0, 0), P('text_char_spacing', 3), P('text_line_spacing', 5),
                    P('text', *CARD, s), P('wait_text', 1)]
        return [P('window_color', 150, 10, 10, 10), P('text_char_spacing', 2), P('text_line_spacing', 5),
                P('text', actor, *params, s), P('wait_text', actor)]

    def compile_block(self, eid, lines, near):
        """块内各行 → 指令列表；跳转目标先用 ('L', 名字) 占位，最后回填"""
        out = []
        labels = {}
        P = lambda *a: [self.newpos(eid)] + list(a)
        stack = []
        uid = [0]

        def lab(kind):
            uid[0] += 1
            return '%s%d' % (kind, uid[0])

        end_label = lab('end')
        for ln, raw in lines:
            line = raw.strip()
            try:
                if not line or line.startswith('#'):
                    continue
                m = re.match(r'^\[(\w+)\s*(.*?)\]$', line)
                if m:
                    cmd, arg = m.group(1), m.group(2).strip()
                    if cmd == 'deja':
                        out.append(P('deja', float(arg) if arg else 1.6))
                    elif cmd in ('flag', 'unflag'):
                        out.append(P('set_flag' if cmd == 'flag' else 'clear_flag', self.flag(arg)))
                    elif cmd == 'bond':
                        k, v = arg.split()
                        out.append(P('rinne_bond', BONDS[k], int(v)))
                    elif cmd == 'wait':
                        out.append(P('wait', int(arg)))
                    elif cmd == 'stop':
                        out.append(P('end'))
                    elif cmd == 'fadeout':
                        out.append(P('fade', 10, 0, 0, 0, 0, 255))
                    elif cmd == 'fadein':
                        out.append(P('fade', 10, 0, 0, 0, 255, 0))
                    elif cmd == 'op':
                        out.append(P(*json.loads(arg)))
                    elif cmd == 'call':
                        out.append(P('call_event', self.event_no(arg)))
                    elif cmd == 'goto':
                        if arg.startswith('#'):
                            pos = int(arg[1:])
                            if not any(x[0] == pos for x in self.events[eid]):
                                raise Err('事件 %d 没有位置 %d' % (eid, pos))
                            out.append(P('goto', pos))
                        elif arg == 'end':
                            out.append(P('goto', ('L', end_label)))
                        else:
                            mm = re.match(r'^「(.+?)」(?:\[(\d+)\])?$', arg)
                            if not mm:
                                raise Err('goto 要写成 「片段」 或 「片段」[N]')
                            i = self.group_start(eid, self.find_text(eid, mm.group(1), int(mm.group(2)) if mm.group(2) else None))
                            out.append(P('goto', self.events[eid][i][0]))
                    elif cmd == 'choice':
                        parts = [p.strip() for p in arg.split('|')]
                        prompt, opts = parts[0], parts[1:]
                        s = '%S0%C5车芸：%S3%C0%N' + (prompt + '%N' if prompt else '') + '%S0' + '  '.join('%B' + o + '.' for o in opts)
                        out += [P('window_color', 150, 10, 10, 10), P('text_char_spacing', 2), P('text_line_spacing', 5),
                                P('text', *CHOICE, s), P('wait_text', 1)]
                        st = {'kind': 'choice', 'cases': [lab('case') for _ in opts], 'end': lab('cend')}
                        out.append(P('menu_switch', [('L', c) for c in st['cases']]))
                        stack.append(st)
                    elif cmd == 'case':
                        st = stack[-1]
                        n = int(arg) - 1
                        if n > 0:
                            out.append(P('goto', ('L', st['end'])))
                        labels[st['cases'][n]] = len(out)
                        st.setdefault('seen', set()).add(n)
                    elif cmd == 'end':
                        st = stack.pop()
                        for n, c in enumerate(st['cases']):
                            if n not in st.get('seen', ()):
                                labels[c] = len(out)   # 没写的分支 = 直接接下去
                        labels[st['end']] = len(out)
                    elif cmd in ('if', 'ifbond'):
                        st = {'kind': 'if', 'else': lab('else'), 'end': lab('iend')}
                        if cmd == 'if':
                            neg = arg.startswith('!')
                            f = self.flag(arg.lstrip('!'))
                            out.append(P('if_flag_goto' if neg else 'if_not_flag_goto', f, ('L', st['else'])))
                        else:
                            mm = re.match(r'(\S)\s*>=\s*(-?\d+)', arg)
                            ok = lab('ok')
                            out.append(P('if_bond_ge_goto', BONDS[mm.group(1)], int(mm.group(2)), ('L', ok)))
                            out.append(P('goto', ('L', st['else'])))
                            labels[ok] = len(out)
                        stack.append(st)
                    elif cmd == 'else':
                        st = stack[-1]
                        out.append(P('goto', ('L', st['end'])))
                        labels[st['else']] = len(out)
                        st['has_else'] = True
                    elif cmd == 'endif':
                        st = stack.pop()
                        if not st.get('has_else'):
                            labels[st['else']] = len(out)
                        labels[st['end']] = len(out)
                    else:
                        raise Err('不认识的指令 [%s]' % cmd)
                    continue
                m = re.match(r'^([^：]{1,12})：(.+)$', line)
                if not m:
                    raise Err('看不懂这一行')
                name, body = m.group(1), m.group(2)
                if name == '字幕':
                    out += self.text_group(eid, 0, None, '%S5' + body, card=True)
                else:
                    actor, params = self.speaker(eid, name, near)
                    out += self.text_group(eid, actor, params, '%C5' + name + '：%C0%N' + body)
            except Err as e:
                self.errors.append('第 %d 行: %s' % (ln, e))
            except Exception as e:  # noqa: BLE001
                self.errors.append('第 %d 行: %s（%r）' % (ln, e, raw))
        if stack:
            self.errors.append('事件 %d 的块里 [choice]/[if] 没有收尾' % eid)
        labels[end_label] = len(out)
        # 回填标签: 指向的那条指令的位置；指到块末尾 → 用块后面接着的原版指令（由调用者给出）
        return out, labels

    def resolve(self, out, labels, tail_pos):
        posat = lambda k: out[k][0] if k < len(out) else tail_pos
        for ins in out:
            for j, a in enumerate(ins):
                if isinstance(a, tuple):
                    ins[j] = posat(labels[a[1]])
                elif isinstance(a, list):
                    ins[j] = [posat(labels[b[1]]) if isinstance(b, tuple) else b for b in a]
        return out

    def block(self, eid, head, lines, ln):
        if eid == 'new':
            nid = self.event_no(head)
            if nid in self.new_events:
                raise Err('新事件「%s」重复定义' % head)
            self.events[nid] = []
            out, labels = self.compile_block(nid, lines, 0)
            tail = [self.newpos(nid), 'end']
            self.resolve(out, labels, tail[0])
            self.new_events[nid] = out + [tail]
            return
        code = self.events.get(eid)
        if code is None:
            raise Err('原版没有事件 %d' % eid)
        m = re.match(r'^(after|before)\s+(?:「(.+?)」(?:\[(\d+)\])?|#(\d+))$', head)
        if m:
            if m.group(4):
                hits = [k for k, x in enumerate(code) if x[0] == int(m.group(4))]
                if not hits:
                    raise Err('事件 %d 没有位置 %s' % (eid, m.group(4)))
                i = hits[0]
                if m.group(1) == 'before':
                    mode, at, nxt = 'before', code[i][0], code[i][0]
                    out, labels = self.compile_block(eid, lines, i)
                    self.resolve(out, labels, nxt)
                    self.patches.setdefault(eid, []).append({'mode': mode, 'at': at, 'code': out})
                    return
            else:
                i = self.find_text(eid, m.group(2), int(m.group(3)) if m.group(3) else None)
            if m.group(1) == 'after':
                if not m.group(4):
                    i = self.after_index(eid, i)
                mode, at, nxt = 'after', code[i][0], (code[i + 1][0] if i + 1 < len(code) else None)
            else:
                i = self.group_start(eid, i)
                mode, at, nxt = 'before', code[i][0], code[i][0]
            out, labels = self.compile_block(eid, lines, i)
            if nxt is None:
                nxt_ins = [self.newpos(eid), 'end']
                out.append(nxt_ins)
                nxt = nxt_ins[0]
            self.resolve(out, labels, nxt)
            self.patches.setdefault(eid, []).append({'mode': mode, 'at': at, 'code': out})
            return
        m = re.match(r'^(?:alt|replace)\s+「(.+?)」(?:\[(\d+)\])?\s+「(.+?)」(?:\[(\d+)\])?(?:\s+if\s+(\S+))?$', head)
        if m:
            fa, na, fb, nb, cond = m.group(1), m.group(2), m.group(3), m.group(4), m.group(5)
            a = self.group_start(eid, self.find_text(eid, fa, int(na) if na else None))
            b = self.after_index(eid, self.find_text(eid, fb, int(nb) if nb else None))
            if b < a:
                raise Err('alt 范围倒过来了')
            orig_start, after_b = code[a][0], code[b + 1][0]
            out, labels = self.compile_block(eid, lines, a)
            self.resolve(out, labels, after_b)
            jump = [self.newpos(eid), 'goto', after_b]
            gate = [[self.newpos(eid), 'if_not_flag_goto', self.flag(cond), orig_start]] if cond else []
            self.patches.setdefault(eid, []).append({'mode': 'before', 'at': orig_start, 'code': gate + out + [jump]})
            return
        raise Err('看不懂块头「%s」' % head)

    def build_file(self, path):
        cur = None
        for ln, raw in enumerate(open(path, encoding='utf-8'), 1):
            line = raw.rstrip('\n')
            m = re.match(r'^@(\d+|new)\s+(.+)$', line.strip())
            if m:
                self.flush(cur, path)
                cur = (int(m.group(1)) if m.group(1) != 'new' else 'new', m.group(2).strip(), [], ln)
            elif cur is not None:
                cur[2].append((ln, line))
            elif line.strip() and not line.strip().startswith('#'):
                self.errors.append('%s 第 %d 行: 块外的内容' % (os.path.basename(path), ln))
        self.flush(cur, path)

    def flush(self, cur, path):
        if cur is None:
            return
        eid, head, lines, ln = cur
        n0 = len(self.errors)
        try:
            self.block(eid, head, lines, ln)
        except Err as e:
            self.errors.append('第 %d 行: %s' % (ln, e))
        for k in range(n0, len(self.errors)):
            self.errors[k] = os.path.basename(path) + ' ' + self.errors[k]


def main():
    check = '--check' in sys.argv
    b = Builder(load_events())
    for f in sorted(os.listdir(SRC)):
        if f.endswith('.txt'):
            b.build_file(os.path.join(SRC, f))
    if b.errors:
        print('\n'.join('✗ ' + e for e in b.errors))
        sys.exit(1)
    # 同一事件多个补丁：按原版位置从后往前套也行，这里保持书写顺序（各补丁锚点互不重叠）
    b.link_before_entries()
    for w in b.warnings:
        print('! ' + w)
    data = {'events': {str(k): v for k, v in sorted(b.new_events.items())}, 'patches': {str(k): v for k, v in sorted(b.patches.items())}, 'flags': b.flags}
    n = sum(len(p['code']) for v in b.patches.values() for p in v)
    print('补丁: %d 个事件, %d 处, %d 条新指令; 旗标 %d 个' % (len(b.patches), sum(len(v) for v in b.patches.values()), n, len(b.flags)))
    if check:
        return
    json.dump(data, open(OUT, 'w', encoding='utf-8'), ensure_ascii=False, separators=(',', ':'))
    json.dump(b.flags, open(FLAGS, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
    json.dump(b.evreg, open(EVREG, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
    print('写出', os.path.relpath(OUT, ROOT))


if __name__ == '__main__':
    main()
