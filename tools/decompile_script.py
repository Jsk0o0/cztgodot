"""轩辕剑苍之涛 事件脚本 → 结构化伪代码

在 disasm_script.py 的线性反汇编之上做控制流结构化:
  条件跳转 → if / else, 选项跳转 (menu_switch) → switch, 随机跳转 (random_goto) → random,
  向后跳转 → loop (do-while), ffff → return; 其余无法结构化的跳转保留为 goto + 标签 (语义不丢)。
窗口参数 + 文本 + 等待 合并为一行「说话者: "台词"」; 旗标按任务表/已知含义命名。
用法: python decompile_script.py <游戏目录> <输出目录>   (名称解析读取 extracted/text/)
"""
import json
import os
import re
import sys
from collections import defaultdict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from disasm_script import FILES, OPS, Names, big5, decode, fmt_arg, read_gll  # noqa: E402

END = 0xFFFF
GOTO = 0x0001
MENU = 0x0011
RANDOM = 0x0059
TEXT = 0x000A
# 文本前的窗口设置 / 文本后的等待: 合并进 say
TEXT_PRE = {0x000B, 0x000E, 0x000F, 0x0010}
CAPTION = 0x0075  # 设置下一个对话框的说话者名字 (Name.gll)
TEXT_POST = {0x000D}


def build_flag_names(text_dir):
    """旗标编号 → 名称 (任务: 接取=任务 ID, 完成=任务 ID+256; 见 README)"""
    names = {0x1F90: '事件进行中'}
    p = os.path.join(text_dir, 'missions.json')
    if os.path.exists(p):
        for m in json.load(open(p)):
            i, t = m['mission_id'], re.sub(r'%[A-Z]\d?', '', m['text'])[:24]
            if 7001 <= i <= 7256:
                names[i] = f'任务接取:{t}'
                names[i + 256] = f'任务完成:{t}'
            elif 7513 <= i <= 7521:
                names[i] = f'史料:{t}'
    return names


class Ctx:
    def __init__(self, names, flags):
        self.names, self.flags = names, flags

    def flag(self, v):
        n = self.flags.get(v)
        return f'flag[0x{v:04x}' + (f' {n}]' if n else ']')

    def arg(self, t, v):
        if t == 'f':
            return self.flag(v)
        return fmt_arg(t, v, self.names, {})


# 条件跳转: op → (跳转条件的字符串生成函数); 参数为非 r 的操作数列表
COND = {
    0x0002: lambda c, a: c.flag(a[0][1]),
    0x0003: lambda c, a: f'not {c.flag(a[0][1])}',
    0x0004: lambda c, a: 'all(' + ', '.join(c.flag(x) for x in a[0][1]) + ')',
    0x0005: lambda c, a: 'any(' + ', '.join(c.flag(x) for x in a[0][1]) + ')',
    0x0070: lambda c, a: f'actor_stopped({c.arg(*a[0][:2])})',
    0x0071: lambda c, a: f'collide({c.arg(*a[0][:2])}, {c.arg(*a[1][:2])})',
    0x008E: lambda c, a: f'distance(player, {c.arg(*a[0][:2])}) <= {a[1][1]}',
    0x00FA: lambda c, a: f'money >= {a[0][1]}',
    0x0118: lambda c, a: f'item_count({c.arg(*a[0][:2])}) >= {a[1][1]}',
    0x0119: lambda c, a: f'money <= {a[0][1]}',
    0x0122: lambda c, a: 'monster_room_free()',
    0x0125: lambda c, a: f'has_monster({a[0][1]})',
    0x012F: lambda c, a: f'var({c.arg(*a[0][:2])}, {a[1][1]}) >= {a[2][1]}',
    0x0130: lambda c, a: f'var({c.arg(*a[0][:2])}, {a[1][1]}) <= {a[2][1]}',
    0x0131: lambda c, a: f'var({c.arg(*a[0][:2])}, {a[1][1]}) == {a[2][1]}',
}
NEG = {'==': '!=', '>=': '<', '<=': '>', '<': '>=', '>': '<='}



def negate(s):
    if s.startswith('not '):
        return s[4:]
    for k, v in NEG.items():
        if f' {k} ' in s and s.count(' ') <= 6:
            return s.replace(f' {k} ', f' {v} ', 1)
    return f'not {s}'


def clean_text(raw):
    """去控制码; 返回 (说话者, 台词, 选项列表)"""
    s = big5(raw)
    opts = [o.strip(' .') for o in re.findall(r'%B([^%]*)', s)]
    s = re.sub(r'%B[^%]*', '', s)
    s = re.sub(r'%[SC]\d|%T\d+\.|%Q', '', s).replace('%N', ' ').replace('%d', '#').strip(' `')
    m = re.match(r'^([^：:]{1,16})[：:]\s*(.*)$', s)
    if m:
        return m.group(1).strip(), m.group(2).strip(), opts
    return None, s, opts


class Decompiler:
    def __init__(self, d, ins, ctx):
        self.d, self.ins, self.ctx = d, ins, ctx
        self.pos2i = {x[0]: k for k, x in enumerate(ins)}
        self.pos2i[len(d)] = len(ins)
        self.consumed = set()      # 已被结构吸收的跳转指令下标
        self.case_pos = {}
        self.caption = None
        self.last_options = {}     # menu_switch 下标 → 最近一次文本的选项
        self.inlined = {}          # 内联的独立块: 起点下标 → 终点下标 (不含)
        self.refs = defaultdict(int)
        for k in range(len(ins)):
            for t in self.tgt(k):
                if t is not None:
                    self.refs[t] += 1
        # 入口: 开头, 以及紧跟在 return/goto 之后、又没有任何跳转引用的位置 (由引擎回调进入, 如 NPC 对话)
        self.entries = [0] + [k for k in range(1, len(ins))
                              if ins[k - 1][1] in (END, GOTO) and not self.refs[k]]
        opts = None
        for k, x in enumerate(ins):
            if x[1] == TEXT:
                o = clean_text(x[3][-1][1])[2]
                opts = o or opts
            elif x[1] == MENU:
                self.last_options[k] = opts or []
                opts = None

    def tgt(self, k):
        """下标 k 的指令的跳转目标下标列表 (按操作数顺序)"""
        x = self.ins[k]
        if x[1] is None:
            return []
        return [self.pos2i.get(fld + v) for t, v, fld in x[3] if t == 'r']

    def is_tail(self, t):
        """t 起是否为不含跳转/文本的直线代码, 以 return 结束 (多处共用的收尾块)"""
        for k in range(t, min(t + 40, len(self.ins))):
            op = self.ins[k][1]
            if op == END:
                return True
            if op is None or op == TEXT or self.tgt(k):
                return False
        return False

    def detached(self, s):
        """s 是只被一处跳转引用、且前一条是 return/goto 的独立块起点"""
        return 0 < s < len(self.ins) and self.refs[s] == 1 and self.ins[s - 1][1] in (END, GOTO)

    def block_end(self, s):
        """独立块的范围: 到第一条 return/goto 为止, 但要包住块内向前跳转 (跳到别的独立块的除外)"""
        reach, k = s, s
        stop = next((e for e in self.entries if e > s), len(self.ins))
        while k < stop:
            for t in self.tgt(k):
                if t is not None and t > k and not self.detached(t):
                    reach = max(reach, t)
            if self.ins[k][1] in (END, GOTO) and k + 1 >= reach:
                return k + 1
            k += 1
        return stop

    # ---- 结构化: 生成树 ----
    def region(self, lo, hi):
        out, k = [], lo
        while k < hi:
            if k in self.inlined and k != lo:
                k = self.inlined[k]
                continue
            x = self.ins[k]
            op = x[1]
            ts = self.tgt(k)
            if op in COND and ts and ts[-1] is not None:
                t = ts[-1]
                if k < t <= hi:
                    last = t - 1
                    if (last > k and self.ins[last][1] == GOTO and self.tgt(last)[0] is not None
                            and t < self.tgt(last)[0] <= hi):
                        u = self.tgt(last)[0]
                        self.consumed |= {k, last}
                        out.append(('if', k, self.region(k + 1, last), self.region(t, u)))
                        k = u
                        continue
                    self.consumed.add(k)
                    out.append(('if', k, self.region(k + 1, t), None))
                    k = t
                    continue
                if t > hi and self.detached(t) and t not in self.inlined:
                    e = self.block_end(t)
                    self.inlined[t] = e
                    self.consumed.add(k)
                    out.append(('if', k, self.region(t, e), None, True))
                    k += 1
                    continue
                if lo <= t <= k:  # 向后条件跳转: do { ... } while (cond)
                    out = self._loop(out, t, k, lo)
                    k += 1
                    continue
            if op == GOTO and ts and ts[0] is not None and lo <= ts[0] <= k:
                out = self._loop(out, ts[0], k, lo)
                k += 1
                continue
            if op in (MENU, RANDOM) and ts and all(t is not None and k < t <= hi for t in ts):
                k = self._switch(out, k, ts, hi)
                continue
            if op in (MENU, RANDOM) and ts and all(
                    t is not None and (t == k + 1 or (t > k and t not in self.inlined and self.ins[t - 1][1] in (END, GOTO)
                                                      and self.refs[t] == ts.count(t))) for t in ts):
                # 各分支都是独立块 (前一条是 return/goto, 只被本指令引用): 内联为 case, 之后顺序执行的代码即 default
                cases = []
                for t in sorted(set(ts)):
                    idxs = [n for n, x in enumerate(ts) if x == t]
                    if t == k + 1:
                        cases.append((idxs, [], True))
                        continue
                    e = self.block_end(t)
                    self.inlined[t] = e
                    self.case_pos[(k, tuple(idxs))] = self.ins[t][0]
                    cases.append((idxs, self.region(t, e), False))
                self.consumed.add(k)
                out.append(('switch2', k, cases))
                k += 1
                continue
            out.append(('stmt', k))
            k += 1
        return out

    def _loop(self, out, t, k, lo):
        """把 out 中从下标 t 起的语句收进循环体 (仅当 t 恰好是 out 中某条语句的起点)"""
        starts = [self._first(n) for n in out]
        if t not in starts:
            out.append(('stmt', k))
            return out
        j = starts.index(t)
        self.consumed.add(k)
        return out[:j] + [('loop', k, out[j:])]

    def _first(self, n):
        return n[1] if n[0] in ('stmt', 'if', 'switch', 'switch2') else self._first(n[2][0]) if n[2] else n[1]

    def _switch(self, out, k, ts, hi):
        uniq = sorted(set(ts))
        first = uniq[0]
        # 各分支结尾若都 goto 同一个点 m, 则 m 为汇合点; 否则最后一个分支延伸到 hi
        bounds = uniq + [hi]
        ends = []
        for a, b in zip(bounds, bounds[1:]):
            if b - 1 >= a and self.ins[b - 1][1] == GOTO and self.tgt(b - 1)[0] is not None:
                ends.append(self.tgt(b - 1)[0])
        if k + 1 < first and self.ins[first - 1][1] == GOTO and self.tgt(first - 1)[0] is not None:
            ends.append(self.tgt(first - 1)[0])
        m = max(set(ends), key=ends.count) if ends else hi
        if not (uniq[-1] < m <= hi):
            m = hi
        self.consumed.add(k)
        cases = []
        for a, b in zip(uniq, uniq[1:] + [m]):
            idxs = [n for n, t in enumerate(ts) if t == a]
            body_hi = b
            if b - 1 >= a and self.ins[b - 1][1] == GOTO and self.tgt(b - 1)[0] == m:
                self.consumed.add(b - 1)
                body_hi = b - 1
            self.case_pos[(k, tuple(idxs))] = self.ins[a][0]
            cases.append((idxs, self.region(a, body_hi)))
        dflt_hi = first
        if first - 1 > k and self.ins[first - 1][1] == GOTO and self.tgt(first - 1)[0] == m:
            self.consumed.add(first - 1)
            dflt_hi = first - 1
        out.append(('switch', k, self.region(k + 1, dflt_hi), cases))
        return m

    # ---- 渲染 ----
    def render(self):
        bounds = self.entries + [len(self.ins)]
        trees = [(a, self.region(a, b)) for a, b in zip(bounds, bounds[1:])]
        need = set()
        for k, x in enumerate(self.ins):
            if k not in self.consumed:
                for t in self.tgt(k):
                    if t is not None:
                        need.add(t)
        # 由 loop 吸收的向后跳转目标不需要标签; 由 if/switch 吸收的目标若仍被别处引用则保留
        self.need = need
        lines = []
        for a, tree in trees:
            if a:
                lines.append('')
                lines.append(f'// ---- 入口 @{self.ins[a][0]}: 没有跳转引用, 由引擎回调进入 (如 NPC 对话) ----')
            self._emit(tree, 0, lines)
        if len(self.ins) in need:
            lines.append(f'L_{len(self.d):04x}:')
        return lines

    def _label(self, k, lines, ind):
        if k in self.need:
            lines.append('  ' * max(ind - 1, 0) + f'L_{self.ins[k][0]:04x}:')

    def _emit(self, nodes, ind, lines):
        pad = '  ' * ind
        skip = set()
        flat = [n for n in nodes]
        for j, n in enumerate(flat):
            kind, k = n[0], n[1]
            self._label(k, lines, ind + 1)
            if kind == 'stmt':
                if k in skip:
                    continue
                s = self.stmt(k, flat, j, skip)
                if s is not None:
                    lines.append(pad + s)
            elif kind == 'if':
                x = self.ins[k]
                cond = COND[x[1]](self.ctx, [a for a in x[3] if a[0] != 'r'])
                if len(n) < 5:  # 普通 if: 跳转条件不成立时执行 body; 内联块: 条件成立时执行
                    cond = negate(cond)
                lines.append(pad + f'if {cond} {{')
                self._emit(n[2], ind + 1, lines)
                if n[3] is not None:
                    lines.append(pad + '} else {')
                    self._emit(n[3], ind + 1, lines)
                lines.append(pad + '}')
            elif kind == 'loop':
                x = self.ins[k]
                lines.append(pad + 'loop {')
                self._emit(n[2], ind + 1, lines)
                if x[1] == GOTO:
                    lines.append(pad + '}')
                else:
                    cond = COND[x[1]](self.ctx, [a for a in x[3] if a[0] != 'r'])
                    lines.append(pad + f'}} while {cond}')
            elif kind == 'switch2':
                x = self.ins[k]
                opts = self.last_options.get(k, []) if x[1] == MENU else []
                lines.append(pad + ('switch choice {' if x[1] == MENU else f'random {{  // {len(self.tgt(k))} 项等概率随机'))
                for idxs, body, falls in n[2]:
                    lab = ', '.join(f'{i}' + (f' "{opts[i]}"' if i < len(opts) else '') for i in idxs)
                    if falls:
                        lines.append(pad + f'case {lab}:  // 继续执行 }} 之后的代码')
                        continue
                    lines.append(pad + f'case {lab}:')
                    self._emit(body, ind + 1, lines)
                lines.append(pad + ('}  // 其余 (取消/未命中): 继续往下' if x[1] == MENU else '}'))
            elif kind == 'switch':
                x = self.ins[k]
                if x[1] == MENU:
                    opts = self.last_options.get(k, [])
                    lines.append(pad + 'switch choice {')
                else:
                    opts = []
                    entries = list(x[3])
                    lines.append(pad + f'random {{  // {len(entries)} 项等概率随机')
                for idxs, body in n[3]:
                    if x[1] == MENU:
                        lab = ', '.join(f'{i}' + (f' "{opts[i]}"' if i < len(opts) else '') for i in idxs)
                    else:
                        lab = ', '.join(str(e) for e, a in enumerate(entries)
                                        if a[0] == 'r' and a[2] + a[1] == self.case_pos[(k, tuple(idxs))])
                    lines.append(pad + f'case {lab}:')
                    self._emit(body, ind + 1, lines)
                    if body and not self._terminates(body[-1]):
                        lines.append(pad + '  break')
                lines.append(pad + ('default:  // 取消 / 未命中' if x[1] == MENU else 'default:'))
                self._emit(n[2], ind + 1, lines)
                lines.append(pad + '}')

    def _terminates(self, n):
        if n[0] == 'stmt':
            op = self.ins[n[1]][1]
            return op in (END, GOTO)
        if n[0] == 'if' and n[3] is not None:
            return bool(n[2]) and bool(n[3]) and self._terminates(n[2][-1]) and self._terminates(n[3][-1])
        return False

    def stmt(self, k, flat, j, skip):
        x = self.ins[k]
        p, op, q, args = x
        if op is None:
            return f'.data {args[0][1].hex(" ")}  // 无法解析'
        if op == END:
            return 'return'
        if op in TEXT_PRE:
            # 后面若干条内有 text 则并入 (只吞掉 text 前的窗口设置)
            for jj in range(j + 1, min(j + 4, len(flat))):
                n = flat[jj]
                if n[0] != 'stmt' or self.ins[n[1]][0] in {self.ins[t][0] for t in self.need}:
                    break
                o = self.ins[n[1]][1]
                if o == TEXT:
                    return None
                if o not in TEXT_PRE:
                    break
        if op == CAPTION:
            self.caption = self.ctx.names.people.get(args[0][1], f'名字#{args[0][1]}')
            return None
        if op == TEXT:
            who, line, opts = clean_text(args[-1][1])
            actor = args[0][1]
            if not who:
                who = self.caption or (self.ctx.names.people.get(actor) if actor not in (0, 0xFF01) else None)
            self.caption = None
            if j + 1 < len(flat) and flat[j + 1][0] == 'stmt' and self.ins[flat[j + 1][1]][1] in TEXT_POST \
                    and flat[j + 1][1] not in self.need:
                skip.add(flat[j + 1][1])
            s = (f'{who}: ' if who else 'narrate: ') + json.dumps(line, ensure_ascii=False)
            if opts:
                s += '  // 选项: ' + ' / '.join(opts)
            return s
        if op == GOTO:
            t = self.tgt(k)[0]
            if t is None or t >= len(self.ins):
                return f'goto L_{len(self.d):04x}'
            return f'goto L_{self.ins[t][0]:04x}' + ('  // 公共收尾块: 清理后 return' if self.is_tail(t) else '')
        if op in COND:
            cond = COND[op](self.ctx, [a for a in args if a[0] != 'r'])
            t = self.tgt(k)[-1]
            lab = f'L_{self.ins[t][0]:04x}' if t is not None and t < len(self.ins) else f'L_{len(self.d):04x}'
            return f'if {cond} goto {lab}'
        name = OPS[op][1]
        shown = []
        for t, v, fld in args:
            if t == 'r':
                tt = self.pos2i.get(fld + v)
                shown.append(f'L_{fld + v:04x}' if tt is not None else f'@{fld + v}')
            elif t == 'L':
                continue
            else:
                shown.append(self.ctx.arg(t, v))
        return f'{name}(' + ', '.join(shown) + ')'


def main(game, out):
    d = os.path.abspath(out)  # 向上找 extracted/text
    while not os.path.exists(os.path.join(d, 'text', 'maps.json')) and os.path.dirname(d) != d:
        d = os.path.dirname(d)
    text_dir = os.path.join(d, 'text')
    names = Names(text_dir)
    ctx = Ctx(names, build_flag_names(text_dir))
    stats = defaultdict(int)
    for fname, lo, hi in FILES:
        b, offs, nxt = read_gll(os.path.join(game, fname))
        stem = os.path.splitext(fname)[0]
        os.makedirs(os.path.join(out, stem), exist_ok=True)
        default = offs[lo - 1]
        owners = defaultdict(list)
        for slot, o in enumerate(offs):
            if o != 0xFFFFFFFF and (o != default or slot == lo - 1):
                owners[o].append(slot)
        for o, slots in sorted(owners.items()):
            s = o + 16
            d = b[s:nxt[s]]
            ins, st = decode(d)
            dc = Decompiler(d, ins, ctx)
            lines = dc.render()
            events = [sl + 1 for sl in slots]
            n_jumps = sum(1 for k in range(len(ins)) if dc.tgt(k))
            n_goto = sum(1 for ln in lines if re.search(r'\bgoto L_', ln) and '公共收尾块' not in ln)
            stats['gotos_to_tail'] += sum(1 for ln in lines if '公共收尾块' in ln)
            stats['entries'] += 1
            stats['jumps'] += n_jumps
            stats['gotos_left'] += n_goto
            stats['fully_structured'] += n_goto == 0
            head = [f'// {fname}  events {events}  parse: {st}  跳转 {n_jumps} 处, 未结构化 goto {n_goto} 处']
            for e in events:
                for t in names.triggers.get(e, []):
                    head.append(f'//   trigger: map {t["map_id"]} {t["map"]}  [{t["kind"]}] {t["name"] or ""}')
            with open(os.path.join(out, stem, f'{events[0]:04d}.txt'), 'w') as f:
                f.write('\n'.join(head + lines) + '\n')
    print(dict(stats))
    return dict(stats)


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
