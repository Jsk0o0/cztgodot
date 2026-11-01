"""轩辕剑苍之涛 战斗 AI 脚本 (AI.GLL) → 人话

来源: SWDMD_GB.EXE 的两个 AI 解释器 (0x40110c 地图 NPC AI, 0x401ae0 战斗 AI) 的逆向; 操作数长度和跳转全部取自汇编。
槽位: 怪物 ObjDATA 键 0x3EC 的 AI 编号 N 使用 GLL 槽位 N-1 (0x401b5d: [pool + N*4 - 4])。
模型: 0x65 开始一次决策; 0x190 设目标阵营、0x19a/0x19c/0x7d4/0x7d5 设目标规则; 0x193 尝试行动
(1 普攻 2 休息 3-7 技能槽 1-5 8 逃跑), 成功即结束本回合, 失败 (无目标/次数用尽/咒封) 继续下一条;
0x1f4 按 (百分比, 跳转) 表随机分支; 0x1f5 若目标存在则以 p% 概率跳转。
用法: python decompile_ai.py <游戏目录> <输出目录>   (读取 extracted/stats/monsters.json、magic.json)
"""
import json
import os
import struct
import sys
from collections import defaultdict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from disasm_script import read_gll  # noqa: E402

# op -> (kind, operand_bytes, jumps)
#   kind: 'fix' 固定长度; 'R' ffffffff 结尾的 rel32 列表; 'P' (u32 权重, rel32) 对列表, ffffffff 结尾;
#         'T20' 20 字节 + %Q 结尾文本; 'T' %Q 结尾文本
#   jumps: [(字段偏移, 基准)]  基准 'op' = 相对指令起点, 'fld' = 相对字段自身地址
ASM = {
    # ---- 两个解释器共有 ----
    0x0000: ('fix', 0, []),
    0x000a: ('fix', 4, [(2, 'op')]),
    0x000b: ('fix', 4, [(4, 'op')]),   # 汇编只前进 6, rel32 的高半字 00 00 落成 op 0 (nop)
    0x000c: ('fix', 4, [(4, 'op')]),
    0x000d: ('fix', 2, []),
    0x000e: ('fix', 2, []),
    0x0012: ('fix', 8, []),
    0x0013: ('fix', 4, []),
    0x0015: ('fix', 2, []),
    0x0032: ('R', 0, []),
    0x0063: ('fix', 0, []),
    0x4000: ('fix', 0, []),
    0x8000: ('fix', 0, []),
    # ---- 仅地图 NPC AI (0x40110c) ----
    0x0010: ('fix', 2, []),
    0x0011: ('T20', 20, []),
    0x0014: ('fix', 0, []),
    0x0016: ('fix', 2, []),
    0x0017: ('fix', 2, []),
    0x0018: ('fix', 0, []),
    0x0019: ('fix', 2, []),
    0x001a: ('fix', 2, []),
    0x001b: ('fix', 0, []),
    0x001c: ('fix', 6, []),
    0x001d: ('fix', 6, []),
    0x001e: ('fix', 0, []),
    0x001f: ('fix', 2, []),
    0x0020: ('fix', 2, []),
    0x0021: ('fix', 0, []),
    0x0022: ('fix', 0, []),
    0x0023: ('fix', 0, []),
    0x0024: ('fix', 0, []),
    0x0025: ('fix', 8, []),
    0x0026: ('fix', 12, []),
    0x0027: ('fix', 4, []),
    # ---- 仅战斗 AI (0x401ae0) ----
    0x0065: ('fix', 0, []),
    0x0066: ('fix', 0, []),
    0x0190: ('fix', 2, []),
    0x0191: ('fix', 2, []),
    0x0193: ('fix', 2, []),
    0x019a: ('fix', 2, []),
    0x019c: ('fix', 0, []),
    0x019d: ('fix', 2, []),
    0x019f: ('fix', 0, []),
    0x01a1: ('fix', 0, []),
    0x01f4: ('P', 0, []),
    0x01f5: ('fix', 6, [(4, 'fld')]),
    0x01f6: ('fix', 6, [(4, 'fld')]),
    0x03e8: ('fix', 2, []),
    0x03e9: ('fix', 2, []),
    0x03ea: ('fix', 6, [(4, 'fld')]),
    0x03eb: ('fix', 2, []),
    0x03ec: ('fix', 2, []),
    0x03ed: ('fix', 8, [(6, 'fld')]),
    0x03ee: ('fix', 8, []),
    0x03ef: ('fix', 0, []),
    0x03f0: ('fix', 6, []),
    0x03f1: ('fix', 0, []),
    0x03f2: ('T', 0, []),
    0x07d0: ('fix', 8, [(6, 'fld')]),
    0x07d2: ('fix', 2, []),
    0x07d3: ('fix', 2, []),
    0x07d4: ('fix', 2, []),
    0x07d5: ('fix', 2, []),
    0x07d6: ('fix', 8, [(6, 'fld')]),
    0x07d7: ('fix', 6, [(4, 'fld')]),
    0x07d8: ('fix', 2, []),
    0x07d9: ('fix', 4, [(2, 'fld')]),
}


def u16(d, p): return struct.unpack_from('<H', d, p)[0]
def s16(d, p): return struct.unpack_from('<h', d, p)[0]
def u32(d, p): return struct.unpack_from('<I', d, p)[0]
def i32(d, p): return struct.unpack_from('<i', d, p)[0]


def decode(d):
    """返回 [(pos, op, end, jumps)], status。jumps = [目标偏移]"""
    p, out = 0, []
    while p + 2 <= len(d):
        op = u16(d, p)
        if op == 0xFFFF:
            out.append((p, op, p + 2, []))
            p += 2
            if p == len(d):
                return out, 'ok'
            continue
        spec = ASM.get(op)
        if spec is None:
            return out, f'unknown op 0x{op:04x} @{p}'
        kind, n, jl = spec
        tg = []
        if kind == 'fix':
            q = p + 2 + n
            for fo, base in jl:
                v = i32(d, p + fo)
                tg.append((p if base == 'op' else p + fo) + v)
        elif kind == 'R':
            q = p + 2
            while u32(d, q) != 0xFFFFFFFF:
                tg.append(q + i32(d, q)); q += 4
            q += 4
        elif kind == 'P':
            q = p + 2
            while u32(d, q) != 0xFFFFFFFF:
                tg.append(q + 4 + i32(d, q + 4)); q += 8
            q += 4
        elif kind in ('T', 'T20'):
            q = p + 2 + n
            while d[q:q + 2] != b'%Q':
                q += 1
            q += 2
        if q > len(d):
            return out, f'truncated 0x{op:04x} @{p}'
        out.append((p, op, q, tg))
        p = q
    return out, 'eof'


# ---------------- 人话翻译 ----------------
SIDE = {1: '对方阵营', 2: '己方阵营', 3: '自己'}
STATUS = {0: '中毒', 1: '昏睡', 2: '石化', 3: '咒封', 4: '状态效果0x1000', 5: '状态效果0x1000000',
          6: '状态位0x800', 7: '状态效果0x10000', 8: '状态效果0x10000000', 9: '状态效果0x20000',
          10: '状态效果0x20000000', 11: '状态效果0x2000', 12: '状态效果0x2000000', 13: '状态效果0x4000',
          14: '状态效果0x4000000'}


def action_name(w, skills, magic):
    if w == 1: return '普通攻击'
    if w == 2: return '休息一回合(回复最大生命 1/10)'
    if 3 <= w <= 7:
        k = w - 3
        if skills is not None:
            if k < len(skills):
                sid = skills[k]
                return f'技能槽{k + 1}「{magic.get(sid, sid)}」({sid})'
            return f'技能槽{k + 1}(该怪物没有此技能!)'
        return f'技能槽{k + 1}'
    if w == 8: return '逃跑'
    return f'行动{w}'


def render(d, ins, skills=None, magic=None, objname=None):
    magic = magic or {}
    objname = objname or {}
    targets = sorted({t for x in ins for t in x[3]})
    lab = {t: f'L{t}' for t in targets}
    lines = []
    side, rule = None, None
    for p, op, q, tg in ins:
        pre = (lab[p] + ':') if p in lab else ''
        a = d[p + 2:q]
        s = None
        if op == 0x65: s = '开始(清空目标/行动选择)'; side = rule = None
        elif op == 0x66: s = '结束(走到这里说明前面都没选出行动, 引擎报错)'
        elif op == 0xffff: s = '(返回)'
        elif op == 0x190: side = u16(d, p + 2); s = f'目标阵营 = {SIDE.get(side, side)}'
        elif op == 0x191: rule = u16(d, p + 2); s = f'目标规则 = {rule}'
        elif op == 0x19a: rule = f'生命 < {u16(d, p + 2)}% 中生命比例最低者'; s = f'目标规则: {rule}'
        elif op == 0x19c: rule = '仅剩唯一存活者'; s = '目标规则: 仅剩唯一存活者'
        elif op == 0x19f: s = '条件: 全局计数[0x925340]≠0'; rule = 'cond'
        elif op == 0x1a1: s = '条件: 自己属于玩家阵营(+0x19ec==1, 被收编/友军)'; rule = 'cond'
        elif op == 0x7d2: rule = f'值[0x1be4]/[区块+0xc8] ≤ {u16(d, p + 2)}%'; s = '目标规则: ' + rule
        elif op == 0x7d3: rule = '主角 车芸/嬴诗/云狐?' if u16(d, p + 2) == 0 else '主角 桓远之?'; s = '目标规则: ' + rule
        elif op == 0x7d4: rule = f'身上有「{STATUS.get(u16(d, p + 2))}」'; s = '目标规则: ' + rule
        elif op == 0x7d5: rule = f'身上没有「{STATUS.get(u16(d, p + 2))}」'; s = '目标规则: ' + rule
        elif op == 0x7d8: s = f'强制目标 = 单位下标 {u16(d, p + 2)}'
        elif op == 0x193:
            w = u16(d, p + 2)
            who = SIDE.get(side, side) if side is not None else '(沿用上一次判定时的阵营范围)'
            r = f'中{rule}的' if rule and rule != 'cond' else '中随机一个'
            if side == 3: r = ''
            s = f'尝试 对{who}{r}单位 {action_name(w, skills, magic)}; 成功则本回合结束, 失败(无目标/次数用尽/被咒封)继续往下'
            side = rule = None
        elif op == 0x19d:
            w = u16(d, p + 2)
            s = f'尝试 召唤援军 {objname.get(w, "")}({w}); 成功则本回合结束'
            side = rule = None
        elif op == 0x1f4:
            parts = []
            for i in range((q - p - 6) // 8):
                parts.append(f'{u32(d, p + 2 + 8 * i)}% → {lab[tg[i]]}')
            s = '按概率分支: ' + ', '.join(parts)
        elif op == 0x32:
            s = '等概率随机跳到: ' + ', '.join(lab[t] for t in tg)
        elif op == 0x1f5:
            pc = u16(d, p + 2)
            if side is not None or rule is not None:
                s = f'若上面设定的目标存在, 则 {pc}% 概率跳到 {lab[tg[0]]}'
            else:
                s = f'{pc}% 概率跳到 {lab[tg[0]]}'
            side = rule = None
        elif op == 0x1f6: s = f'若敌方阵营(怪物方)存活数 ≥ {u16(d, p + 2)} 跳到 {lab[tg[0]]}'
        elif op == 0x7d0:
            m, n = u16(d, p + 2), u16(d, p + 4)
            s = (f'若 自身行动次数 == {n} 跳到 {lab[tg[0]]}' if m == 0 else
                 f'若 自身行动次数 是 {n} 的倍数 跳到 {lab[tg[0]]}')
        elif op == 0x7d6:
            sd, n = u16(d, p + 2), u16(d, p + 4)
            s = f'若 {"对方" if sd == 1 else "己方"}阵营存活数 ≥ {n} 跳到 {lab[tg[0]]}'
        elif op == 0x7d7:
            w = u16(d, p + 2)
            s = (f'若 旗标{w} 已设 跳到 {lab[tg[0]]}' if w in (1, 2, 3) else
                 f'若 场上有存活的 {objname.get(w, "")}({w}) 跳到 {lab[tg[0]]}')
        elif op == 0x7d9: s = f'若 当前行动单位属于玩家阵营 跳到 {lab[tg[0]]}'
        elif op == 0x3e8: s = f'战斗变量[{u16(d, p + 2)}] = 1'
        elif op == 0x3e9: s = f'战斗变量[{u16(d, p + 2)}] = 0'
        elif op == 0x3ea: s = f'若 战斗变量[{u16(d, p + 2)}] == 1 跳到 {lab[tg[0]]}'
        elif op == 0x3eb: s = f'战斗计数器[{u16(d, p + 2)}] += 1'
        elif op == 0x3ec: s = f'战斗计数器[{u16(d, p + 2)}] = 0'
        elif op == 0x3ed: s = f'若 战斗计数器[{u16(d, p + 2)}] ≥ {u16(d, p + 4)} 跳到 {lab[tg[0]]}'
        elif op == 0x0a: s = f'跳到 {lab[tg[0]]}'
        elif op == 0x0b: s = f'若 旗标{u16(d, p + 2)} 已设 跳到 {lab[tg[0]]}'
        elif op == 0x0c: s = f'若 旗标{u16(d, p + 2)} 未设 跳到 {lab[tg[0]]}'
        elif op == 0x0d: s = f'设旗标 {u16(d, p + 2)}'
        elif op == 0x0e: s = f'清旗标 {u16(d, p + 2)}'
        elif op == 0x63: s = '停止(脚本指针清零, 下次从头执行)'
        elif op == 0x8000: s = '挂起(以后每次调用都直接返回)'
        elif op == 0x00: s = 'nop'
        elif op == 0x10: s = f'等待 {u16(d, p + 2) * 10} ms'
        elif op == 0x16: s = f'切换动作 {u16(d, p + 2)}'
        elif op == 0x19: s = f'朝向 = {u16(d, p + 2)} 度 (+0x1b0)'
        elif op == 0x1a: s = f'走路速度 = {u16(d, p + 2)} (全局 0x4d1140, 所有 NPC 共用)'
        elif op == 0x1d: s = f'走到 ({s16(d, p + 2)}, {s16(d, p + 4)}, {s16(d, p + 6)})'
        elif op == 0x1e: s = '等待走路结束'
        if s is None:
            s = f'op_{op:04x} ' + a.hex(' ')
        lines.append(f'  {pre:<6s}{p:5d}  {s}')
    return lines


def main(game, out):
    d0 = os.path.abspath(out)
    while not os.path.exists(os.path.join(d0, 'stats', 'monsters.json')) and os.path.dirname(d0) != d0:
        d0 = os.path.dirname(d0)
    stats_dir = os.path.join(d0, 'stats')
    mons = json.load(open(os.path.join(stats_dir, 'monsters.json')))
    mp = os.path.join(stats_dir, 'magic.json')
    magic = {m.get('编号 id'): m.get('名称 name') for m in json.load(open(mp))} if os.path.exists(mp) else {}
    objname = {m['编号 id']: m['名称 name'] for m in mons}
    users = defaultdict(list)
    for m in mons:
        if m['AI脚本 ai_id(AI.GLL)']:
            users[m['AI脚本 ai_id(AI.GLL)'] - 1].append(m)
    b, offs, nxt = read_gll(os.path.join(game, 'AI.GLL'))
    owners = defaultdict(list)
    for k, o in enumerate(offs):
        if o != 0xFFFFFFFF:
            owners[o].append(k)
    os.makedirs(out, exist_ok=True)
    ok = 0
    for o, ks in sorted(owners.items()):
        s = o + 16
        d = b[s:nxt[s]]
        ins, st = decode(d)
        ok += st == 'ok'
        us = [m for k in ks for m in users.get(k, [])]
        kind = '战斗 AI' if any(x[1] == 0x65 for x in ins) else '地图 NPC AI'
        head = [f'; AI.GLL 槽位 {ks[:12]}{" ..." if len(ks) > 12 else ""}  (AI 编号 {[k + 1 for k in ks[:12]]})  {kind}  size {len(d)}  parse {st}']
        for m in us[:8]:
            head.append(f';   使用者: {m["编号 id"]} {m["名称 name"]}  技能 '
                        + str([(x["id"], x["name"], x["每场可用次数 uses"]) for x in m["技能 skills"]]))
        sk = [x['id'] for x in us[0]['技能 skills']] if us else None
        mg = dict(magic)
        if us:
            mg.update({x['id']: x['name'] for x in us[0]['技能 skills']})
        with open(os.path.join(out, f'{ks[0]:04d}.txt'), 'w') as f:
            f.write('\n'.join(head + render(d, ins, sk, mg, objname)) + '\n')
    print('AI', ok, '/', len(owners))
    return {'ok': ok, 'entries': len(owners)}


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
