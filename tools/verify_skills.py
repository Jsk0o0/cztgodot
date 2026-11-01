"""技能验证: 读战斗的技能测试日志 (--skill-test, SKILLTEST / SETTLEJ 行), 按逆向笔记里的原版公式独立复算, 对照引擎的结果.

用法: .venv/bin/python -I tools/verify_skills.py 日志 [skills.json 输出]
公式来源 (不读引擎代码): re/battle_formula_re.md
  §3c 法术伤害 0x437c36: base = max(1, (MATK*power - MDEF*1000) / 10 / 100); E = elem_mod;
      我方 dmg = base + base*(trunc(E*L)+rnd)/100, L = clamp(1+0.05*(LV攻-LV守), 1, 2), rnd ∈ [-5, 5]
      怪物 dmg = base + base*(E+rnd)/100, 再 ±LV
  §3c 第 1 步 数值效果 (HP/SP/MP, 以目标上限为底), sub 202/203/302 不造成伤害
  §3d 公共修正 (石化 /5, 悲哀 /2, 狂乐 ×2, 混沌, 防御 /2, 负值 /5)
  §4 elem_mod
"""
import json
import sys


def tdiv(a, b):
    """C 的整数除法 (向零取整)"""
    q = abs(a) // abs(b)
    return q if (a >= 0) == (b > 0) else -q


def amount(v, mx):
    if v > 20000:
        return (v - 20000) * mx
    if v > 10000:
        p = v - 10000
        return mx * (100 if p == 99 else p) // 100
    if v < -20000:
        return (v + 20000) * mx
    if v < -10000:
        p = -v - 10000
        return -(mx * (100 if p == 99 else p) // 100)
    return v


def elem_mod(A, T):
    A = list(A) + [0] * (7 - len(A))
    T = list(T) + [0] * (7 - len(T))
    i = next((k for k in range(5) if A[k]), None)
    if i is not None:
        if T[(i + 1) % 5] > 0:
            return -200 - A[i] - T[(i + 1) % 5]
        if T[(i + 3) % 5] > 0:
            return -(A[i] + T[(i + 3) % 5])
        if T[(i + 2) % 5] > 0:
            return A[i] + T[(i + 2) % 5]
        return 0
    i = next((k for k in (5, 6) if A[k]), None)
    if i is not None:
        return A[i] - T[i]
    return -T[5]


def common_mod(d, j):
    att, tgt = j['att_status'], j['t_status']
    if tgt & 0x10:
        d = tdiv(d, 5)
    if att & 0x100:
        d = tdiv(d, 2)
    if tgt & 0x100:
        d = tdiv(d, 2)
    if att & 0x200:
        d *= 2
    if tgt & 0x200:
        d *= 2
    if att & 0x800:
        d = tdiv(d, 3)
    if tgt & 0x800:
        d *= 2
    if j['t_defending']:
        h = tdiv(d, 2)
        d = h if h != 0 else (1 if d > 0 else -1 if d < 0 else 0)
    if d < 0:
        d = min(tdiv(d, 5), -1)
    return d


def class_ok(j, cls):
    """目标类别规则 (re/battle_formula_tables.json 0xC22): 怪物 118/119/120, 我方木甲 = 云狐"""
    if not cls:
        return True
    if j['t_party']:
        mech = j.get('t_member') == 1
        return not (cls & 4 and mech) and not (cls & 8 and not mech)
    sb = j.get('t_sub', 0)
    return not (cls & 1 and sb in (118, 119)) and not (cls & 2 and sb in (119, 120)) and not (cls & 8 and sb not in (118, 119))


def expected(j):
    """返回 (hp 最小, hp 最大, 即死可能) 或 None (不适用)"""
    fx1 = j['fx1'] + [0] * 6
    heal = -amount(int(fx1[0]), j['t_hp_max'])
    if j['sub'] in (202, 203, 302) or j['kind'] not in (3,) and not (j['kind'] == 2 and j['sub'] == 201):
        return (heal, heal, False)
    base = max(1, tdiv(tdiv(j['att_matk'] * j['power'] - j['t_mdef'] * 1000, 10), 100))
    E = elem_mod(j['elem'], j['t_elem'])
    vals = []
    for rnd in range(-5, 6):
        if j['att_party']:
            L = min(max(1.0 + 0.05 * (j['att_lv'] - j['t_lv']), 1.0), 2.0)
            d = base + tdiv(base * (int(E * L) + rnd), 100)
        else:
            d = base + tdiv(base * (E + rnd), 100)
            d += j['att_lv'] if d > 0 else (-j['att_lv'] if d < 0 else 0)
        vals.append(common_mod(d, j) + heal)
    # 施加「死亡」(§5): 造成等于当前 HP 的伤害; 0xC23 无效对象不施加
    death = bool(j.get('status_mask', 0) & 2 and j.get('status_op') in (0x2000, 0x8000) and class_ok(j, j.get('immune', 0)))
    return (min(vals), max(vals), death)


def main(log, out=None):
    cur = None
    res = {}
    order = []
    for line in open(log, encoding='utf-8', errors='replace'):
        if line.startswith('SKILLTEST_BEGIN '):
            p = line.split()
            cur = {'id': int(p[1]), 'name': p[2], 'begin': line.strip(), 'settles': [], 'result': None, 'fxmiss': []}
            res[len(order)] = cur   # 同一招可以放多次, 按施放顺序记
            order.append(len(order))
        elif line.startswith('SETTLEJ ') and cur:
            cur['settles'].append(json.loads(line[8:]))
        elif line.startswith('MECHSCOUT ') and cur:
            cur['scout'] = True
        elif line.startswith('MECHBREAK ') and cur:
            kv = dict(x.split('=') for x in line.split()[1:])
            cur.setdefault('mech', []).append({'tier': int(kv['tier']), 'r': int(kv['r']), 'is118': kv['is118'] == 'true'})
        elif line.startswith('SKILLBUFF ') and cur:
            cur.setdefault('buffs', []).append(json.loads(line[10:]))
        elif line.startswith('SKILLTEST ') and cur:
            cur['result'] = line.strip()
        elif line.startswith('SKILLTEST_STUCK') and cur:
            cur['stuck'] = True
        elif line.startswith('FXMISS') and cur:
            cur['fxmiss'].append(line.split()[1])
    bad = 0
    rows = []
    for idx in order:
        r = res[idx]
        sid = r['id']
        notes = []
        if r['result'] is None:
            notes.append('没有结束')
        if r.get('stuck'):
            notes.append('超过 25 秒')
        if r['fxmiss']:
            notes.append('缺特效 ' + ','.join(sorted(set(r['fxmiss']))))
        if not r['settles'] and not r.get('mech') and not r.get('scout'):
            notes.append('没有结算')
        ok_n = 0
        for j in r['settles']:
            # roll_hit 顺序 (§2): 恢复 / 特殊 / 木甲修复 (sub 202/305/302) 先判必中, 不过类别过滤
            if j['sub'] not in (202, 305, 302) and not class_ok(j, j.get('target_class', 0)):
                # 0xC22 目标类别过滤: 应判无效 (roll_hit 返回 5)
                if j['hit'] == 5:
                    ok_n += 1
                else:
                    notes.append('%s→%s 目标类别 %d 应无效, 引擎判 %d' % (j['att'], j['t'], j.get('target_class', 0), j['hit']))
                continue
            if j['miss']:
                continue
            e = expected(j)
            if e is None:
                continue
            if e[0] <= j['hp'] <= e[1] or (e[2] and j['hp'] >= j.get('t_hp', 0)):
                ok_n += 1
            elif j['hit'] == 5:
                notes.append('%s→%s 被判无效 (目标类别 %d)' % (j['att'], j['t'], j.get('target_class', 0)))
            else:
                notes.append('%s→%s 引擎 %d, 公式 %d..%d' % (j['att'], j['t'], j['hp'], e[0], e[1]))
        # 木甲术 拆解 / 卸甲 / 瘫痪 (re/verify_mech_skills.md §3): 按等级和骰子定结果, 减益按 118 / 其他 取百分比, 5 回合
        if 6025 <= sid <= 6027:
            for m in r.get('mech', []):
                tier, rr, is118 = m['tier'], m['r'], m['is118']
                if rr <= (15, 10, 5)[tier - 1] or (rr >= (90, 85, 80)[tier - 1] and is118):
                    expect_buff = None
                else:
                    expect_buff = ((45, 15), (75, 25), (100, 30))[tier - 1][0 if is118 else 1]
                stats = {6025: ('atk', 'matk'), 6026: ('def', 'mdef'), 6027: ('spd',)}[sid]
                got = {k: v for b in r.get('buffs', []) for k, v in b['buffs'].items()}
                if expect_buff is None:
                    if got:
                        notes.append('木甲术 r=%d 应无减益, 引擎有 %s' % (rr, got))
                    else:
                        ok_n += 1
                    continue
                for k in stats:
                    v = got.get(k)
                    exp_v = -(v[2] * expect_buff // 100) if v else None
                    if not v or v[0] != exp_v or v[1] != 5:
                        notes.append('木甲术 r=%d %s 引擎 %s, 规格 −%d%% 5回合' % (rr, k, v, expect_buff))
                    else:
                        ok_n += 1
            r['buffs'] = []
        # 增减益 (§5 0x434b2b): 值 = amount(效果值, 目标基础值), 回合 = rec 0xBC0[2]
        for b in r.get('buffs', []):
            fx1 = b['fx1'] + [0] * 6
            fx2 = b['fx2'] + [0] * 7
            src = {'atk': fx1[2], 'def': fx1[3], 'hit': fx1[4], 'eva': fx1[5], 'matk': fx2[1], 'mdef': fx2[2],
                   'mhit': fx2[3], 'meva': fx2[4], 'spd': fx2[5]}
            for k, (v, turns, base) in b['buffs'].items():
                exp_v = amount(int(src.get(k, 0)), base)
                exp_t = max(b['turns'], 1)
                if v != exp_v or turns != exp_t:
                    notes.append('%s 的 %s 增减益 引擎 %+d/%d回合, 公式 %+d/%d回合' % (b['t'], k, v, turns, exp_v, exp_t))
                else:
                    ok_n += 1
        misses = sum(1 for j in r['settles'] if j['miss'])
        status = '通过' if not notes else '不符'
        if notes:
            bad += 1
        rows.append({'id': sid, 'name': r['name'], 'status': status, 'settles': len(r['settles']), 'ok': ok_n,
                     'miss': misses, 'notes': notes, 'result': r['result']})
        print('%-6s %d %-8s 结算 %d 次 (符合 %d, 未命中 %d) %s' % (status, sid, r['name'], len(r['settles']), ok_n, misses,
                                                        '; '.join(notes)))
    print('共 %d 招, 不符 %d 招' % (len(order), bad))
    if out:
        json.dump(rows, open(out, 'w'), ensure_ascii=False, indent=1)


if __name__ == '__main__':
    main(*sys.argv[1:])
