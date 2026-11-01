"""导出战斗系统运行时数据 → extracted/game/battle.json (依据 SWDMD_GB.EXE 战斗流程与公式逆向)

用法: python export_battle.py <游戏目录> <extracted 目录>
内容:
  battlefields  战场 N (事件 start_battle N): BattleField.dat 第 N-1 条 —— 场景 (场景 ACT → WLD), 敌人 (编号/坐标/朝向);
                战斗剧情脚本 = FIGTALK 第 N-1 槽 (与其他 GLL 一样「编号 − 1」; 对白内容与敌人对得上)
  objs          单位与动作记录, 键 = 游戏编号 (ObjDATA 下标 + 1, read_Item 0x4037b2), 字段直接取 ObjDATA 键值 (见 OBJ_FIELDS)
  growth/exp    LEVEL.GLL: 三位主角每级增量 (列: HP MP SP 攻 防 仙攻 仙防 命中 回避 仙命中 仙回避 速度 习得法术), 累计经验表
  atk           ATK.GLL 招式演出: ATK 编号 → 步骤 (tools/skill_catalog.steps_of; 开头 random_jump 的拆成 variants)
  ai            AI.GLL 战斗 AI: AI 编号 → [位置, 操作码, 操作数(u16...), 跳转目标...] (解释器 0x401ae0, 语义见 decompile_ai.py)
  figtalk       FIGTALK.GLL 战斗剧情: 槽位 → [位置, 指令名, 操作数..., 跳转目标] (指令表 tools/battle_vm.json)
"""
import json
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import decompile_ai as AI  # noqa: E402
import mapsdat as M  # noqa: E402
from disasm_script import BATTLE_VM, TEXT_RE, battle_jumps, battle_table, big5, decode_bytes, read_gll  # noqa: E402
from extract_stats import level_tables, load_objdata, read_gll as read_level  # noqa: E402
from skill_catalog import steps_of, variants_of  # noqa: E402


def s16(b, n):
    return list(struct.unpack('<%dh' % n, b[:2 * n]))


def u16(b, n):
    return list(struct.unpack('<%dH' % n, b[:2 * n]))


def obj_record(r):
    """ObjDATA 记录 → 战斗用字段 (键 → 记录偏移见 battle_formula_re: read_Item 0x4037b2)"""
    kv = r['kv']
    o = {'name': r.get('name', ''), 'kind': r.get('kind'), 'sub': r.get('sub'), 'desc': r.get('desc', '')}
    if 0x232B in kv:
        o['level'] = u16(kv[0x232B], 1)[0]
    elif 'level' in r:
        o['level'] = r['level']
    if 0xBBA in kv:
        o['hp'], o['mp'], o['sp'] = s16(kv[0xBBA], 3)          # 上限 (装备上为加值)
    if 0xBB9 in kv:
        o['atk'], o['def'], o['spd'], o['matk'], o['mdef'] = s16(kv[0xBB9], 5)
    if 0xBBB in kv:
        o['eva'], o['hit'], o['meva'], o['mhit'] = s16(kv[0xBBB], 4)
    if 0x3EF in kv:
        o['crit'] = kv[0x3EF][0]
    if 0x3E9 in kv:
        o['elem'] = s16(kv[0x3E9], 7)                         # 木 火 土 金 水 物理5 物理6
    if 0x3EB in kv:
        o['chant'] = kv[0x3EB][0]                             # 吟咒速度 (0 = 立即施放)
    if 0x3EC in kv:
        o['ai'] = u16(kv[0x3EC], 1)[0]
    if 0x3ED in kv:
        o['atk_id'] = u16(kv[0x3ED], 1)[0]                    # 招式演出 ATK 编号
    if 0x3EE in kv:
        o['atk2_id'] = u16(kv[0x3EE], 1)[0]                   # 奋力一击的演出
    if 0x3F0 in kv:
        o['knock'] = u16(kv[0x3F0], 2)[0]
    if 0x3F1 in kv:
        o['power'] = u16(kv[0x3F1], 1)[0]                     # 法术威力 (千分比) / 单位的普攻武器编号
    if 0x3F2 in kv:
        o['status_rate'], o['buff_rate'] = kv[0x3F2][0], kv[0x3F2][1]
    if 0x3F3 in kv:
        o['skills'] = u16(kv[0x3F3], 5)
        o['uses'] = list(kv.get(0x3F4, b'\0' * 5))
    if 0x3F5 in kv:
        rw = u16(kv[0x3F5], 7)
        o['reward'] = {'money': rw[0], 'res': rw[1:4], 'exp': rw[4] | (rw[5] << 16), 'tech': rw[6]}
    if 0x3F6 in kv:
        o['drops'] = [list(struct.unpack_from('<BH', kv[0x3F6], 3 * k)) for k in range(3)]
    if 0x3FA in kv:
        o['drain'] = u16(kv[0x3FA], 1)[0]
    if 0x3FB in kv:
        o['flee'] = list(kv[0x3FB])
    if 0xBB8 in kv:
        o['users'] = kv[0xBB8][0]
    if 0xBC0 in kv:
        o['field_use'] = kv[0xBC0][3]                          # 1/2 = 地图上可使用 (奇术页 rec+0xde = 0xBC0 第 4 字节)
    if r.get('note'):
        o['note'] = r['note']
    if 0xBC0 in kv:
        o['side'], o['scope'], o['turns'] = kv[0xBC0][0], kv[0xBC0][1], kv[0xBC0][2]
    if 0xBC1 in kv:
        b = kv[0xBC1]
        o['cost'] = {'hp': struct.unpack_from('<H', b, 0)[0], 'sp': struct.unpack_from('<H', b, 2)[0],
                     'mp': struct.unpack_from('<H', b, 4)[0], 'juji': struct.unpack_from('<b', b, 6)[0]}
    if 0xC1E in kv:
        o['fx1'] = s16(kv[0xC1E], 6)                          # HP SP 攻 防 命中 回避
    if 0xC1F in kv:
        o['fx2'] = s16(kv[0xC1F], 7)                          # MP 仙攻 仙防 仙命中 仙回避 速度 ?
    if 0xC20 in kv:
        o['juji_gain'] = kv[0xC20][0]
    if 0xC21 in kv:
        o['status'], o['status_op'] = u16(kv[0xC21], 2)
    if 0xC22 in kv:
        o['target_class'] = kv[0xC22][0]
    if 0xC23 in kv:
        o['immune'] = kv[0xC23][0]                            # 状态无效对象 (0x435935, 同 0xC22 的类别规则)
    if 0xBBF in kv:
        o['craft'] = list(kv[0xBBF][:4])                      # 生产能力 冶金 / 整备 / 制药 / 神技 (记录 +0xd4..+0xd7, 视破面板 0x4515d8)
    if 0x3F8 in kv:
        o['special_skill'] = struct.unpack_from('<H', kv[0x3F8], 0)[0]   # 可学习技能 (记录 +0x40, 视破面板)
    if 0xC1D in kv:
        # 0xC1D: 第 0 字节 = 可卖标志, 第 1 字节起 u32 = 价格 (0x45eb92 / 0x45e178)
        o['sellable'] = kv[0xC1D][0]
        o['price'] = struct.unpack_from('<I', kv[0xC1D], 1)[0]
    return o


def figtalk(game):
    b, offs, nxt = read_gll(os.path.join(game, 'FIGTALK.GLL'))
    table = battle_table('FIGTALK.GLL')
    ops = BATTLE_VM['FIGTALK.GLL']['ops']
    out = {}
    for slot, o in enumerate(offs):
        if o == 0xFFFFFFFF:
            continue
        s = o + 16
        d = b[s:nxt[s]]
        ins, st = decode_bytes(d, table)
        code = []
        for p, op, q in ins:
            if op == 0xFFFF:
                code.append([p, 'end'])
                continue
            e = ops.get('0x%04x' % op, {})
            vals, k = [], p + 2
            for t in e.get('types', ''):
                if t == 'T':
                    m = TEXT_RE.match(d, k)
                    vals.append(big5(m.group()[:-2]))
                    k = m.end()
                elif t in 'rR':
                    k += 4  # 跳转目标统一放在末尾
                elif t == 'c':
                    vals.append(d[k])
                    k += 1
                elif t == 'd':
                    vals.append(struct.unpack_from('<i', d, k)[0])
                    k += 4
                elif t == 's':
                    vals.append(struct.unpack_from('<h', d, k)[0])
                    k += 2
                else:
                    vals.append(struct.unpack_from('<H', d, k)[0])
                    k += 2
            code.append([p, e.get('name', 'op_%04x' % op)] + vals + [[t for _, t in battle_jumps(d, p, q, e)]])
        out[slot] = code
    return out


def ai_scripts(game):
    b, offs, nxt = read_gll(os.path.join(game, 'AI.GLL'))
    out = {}
    for slot, o in enumerate(offs):
        if o == 0xFFFFFFFF:
            continue
        s = o + 16
        d = b[s:nxt[s]]
        ins, st = AI.decode(d)
        code = []
        for p, op, q, tg in ins:
            if op == 0x1F4:       # (权重 u32, rel32) 对列表
                pairs, k = [], p + 2
                while struct.unpack_from('<I', d, k)[0] != 0xFFFFFFFF:
                    pairs.append(struct.unpack_from('<I', d, k)[0])
                    k += 8
                code.append([p, op, pairs, tg])
                continue
            n = (q - p - 2) // 2
            code.append([p, op, list(struct.unpack_from('<%dH' % n, d, p + 2)) if n else [], tg])
        out[slot + 1] = code   # AI 编号 N 用槽位 N-1 (0x401b5d)
    return out


def main(game, ext):
    recs = load_objdata(os.path.join(game, 'ObjDATA.GLL'))
    objs = {i + 1: obj_record(r) for i, r in recs.items() if r.get('kind') in (1, 2, 3)}
    # 说明用简体版 (text/objdata.json 的 desc_simplified, index = ObjDATA 下标)
    simp = {int(x['index']): x for x in json.load(open(os.path.join(ext, 'text', 'objdata.json')))}
    for i, o in objs.items():
        x = simp.get(i - 1, {})
        o['desc'] = x.get('desc_simplified') or o.get('desc', '')
        if x.get('name_simplified'):
            o['name'] = x['name_simplified']
    names = {i + 1: r.get('name', '') for i, r in recs.items()}
    lv = level_tables(os.path.join(game, 'LEVEL.GLL'), names)
    who = {'车芸': 1, '嬴诗': 2, '桓远之': 3}
    growth = {who[k]: [[row[c] for c in list(row)[:14]] for row in rows] for k, rows in lv['growth'].items()}
    exp = [[r['等级 level'], r['升级所需经验 exp_to_next(推测)']] for r in lv['exp_table']]
    # 战场
    bf = json.load(open(os.path.join(ext, 'text', 'battlefields.json')))['battlefields']
    battlefields = {}
    bf_coll = {}
    for x in bf:
        n = x['index'] + 1
        wld = M.wld_of_act(game, x['scene_act']) if x['scene_act'] else None
        battlefields[n] = {'name': x['name_simplified'], 'scene': wld, 'scene_act': x['scene_act'],
                           'enemies': [{'id': i, 'pos': p, 'facing': f} for i, p, f in
                                       zip(x['enemy_ids'], x['enemy_pos'], x.get('enemy_facing', []))],
                           'figtalk': n - 1, 'fog': x.get('fog')}
        # 战场地面碰撞 (召唤找位置时判断「这里有没有地面」, exe 0x443678): 三角形坐标以场景包围盒最小角为原点
        if wld and wld not in bf_coll:
            try:
                bmin, tris, _ = M.collision(game, wld)
            except (OSError, KeyError, struct.error):
                bmin, tris = None, []
            if bmin is not None:
                os.makedirs(os.path.join(ext, 'game', 'collision'), exist_ok=True)
                with open(os.path.join(ext, 'game', 'collision', 'bf_%s.bin' % wld), 'wb') as f:
                    f.write(struct.pack('<I3f', len(tris), *bmin))
                    for t in tris:
                        f.write(struct.pack('<9f', *t))
            bf_coll[wld] = True
    # ATK 招式演出 (编号 N = 槽位 N-1)
    b, offs, nxt = read_gll(os.path.join(game, 'ATK.GLL'))
    table = battle_table('ATK.GLL')
    atk = {}
    for slot, o in enumerate(offs):
        if o == 0xFFFFFFFF:
            continue
        d = b[o + 16:nxt[o + 16]]
        ins, _ = decode_bytes(d, table)
        vs = variants_of(d, ins)
        if vs:
            atk[slot + 1] = {'variants': [{'weight': w, 'steps': steps_of(d, ins, s)} for s, w in vs]}
        else:
            atk[slot + 1] = {'steps': steps_of(d, ins)}
    # 物品大图标 (战斗清单左侧 0x45811c: ACT = 物品编号, 第 0 号动作的 FR → all_item.tsw 条目, AP = 帧)
    from act import actions as act_actions
    items_act = open(os.path.join(game, 'ACT', 'all_item.act'), 'rb').read()
    ui = json.load(open(os.path.join(ext, 'ui', 'index.json')))
    tsw = ['all_char', 'all_item', 'all_magic', 'all_sys', 'all_map1', 'all_map2']
    dirs = {k: {int(e['index']): e['dir'] for e in (v if isinstance(v, list) else v.values())} for k, v in ui.items()}
    for i, o in objs.items():
        if o.get('kind') != 2:
            continue
        try:
            h = act_actions(items_act, i).get(0)
        except (KeyError, IndexError):
            continue
        if h and h['aps']:
            d = dirs.get(tsw[h['fr'] // 3000], {}).get(h['fr'] % 3000)
            if d and os.path.exists(os.path.join(ext, 'ui', d, '%03d.png' % h['aps'][0])):
                o['icon'] = 'ui/%s/%03d.png' % (d, h['aps'][0])
    # 法宝修练表 (LEVEL.GLL 条目 4-19): 法宝编号 → 5 级 [所需修练值, 参数...] (参数为数值编码, 同 Formula.amount)
    refine = {}
    for i, o2, d in read_level(os.path.join(game, 'LEVEL.GLL')):
        if d is None or not 4 <= i <= 19:
            continue
        body = d[:-4] if d.endswith(b'\xb1\x26\xff\xff') else d
        v = list(struct.unpack('<%di' % (len(body) // 4), body))
        per = (len(v) - 1) // 5
        refine[v[0]] = [v[1 + k * per + 1:1 + (k + 1) * per] for k in range(5)]
    # 木甲技术点数表 (LEVEL.GLL 条目 20): 每条 u16 等级, u16 该级获得点数, u16 累计上限 (机关页 0x40360c / 0x4035e1)
    techpts = []
    for i, o2, d in read_level(os.path.join(game, 'LEVEL.GLL')):
        if i == 20 and d is not None:
            for k in range(len(d) // 6):
                lv, gain, cap = struct.unpack_from('<3H', d, k * 6)
                if lv == 0 or lv > 99:
                    break
                techpts.append([lv, gain, cap])
    out = {'battlefields': battlefields, 'objs': objs, 'growth': growth, 'exp': exp, 'atk': atk, 'refine': refine, 'techpts': techpts,
           'ai': ai_scripts(game), 'figtalk': figtalk(game)}
    with open(os.path.join(ext, 'game', 'battle.json'), 'w', encoding='utf-8') as f:
        json.dump(out, f, ensure_ascii=False, separators=(',', ':'))
    print('战场 %d, 记录 %d, ATK %d, AI %d, FIGTALK %d' % (len(battlefields), len(objs), len(atk), len(out['ai']),
                                                      len(out['figtalk'])))


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
