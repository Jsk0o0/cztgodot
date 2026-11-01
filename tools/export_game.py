"""导出 Godot 复刻版运行时要用的游戏数据 (从玩家自备的游戏目录读取, 输出到 extracted/game/)

用法: python export_game.py <游戏目录> <extracted 目录>
输出:
  game/events/<gll名>.json  {事件号: {"code": 代码键}} 与 {"codes": {代码键: [[位置, 指令名, 操作数...], ...]}}
      操作数: 跳转 (r) 已换算成脚本内绝对位置; 跳转表 (R) 为位置列表; 文本 (T) 为简体字符串 (保留 %N %Cn %Sn 等控制码);
      旗标列表 (F) 为整数列表; 其余为整数。共享同一段代码的事件指向同一个代码键。
  game/maps.json  每张地图: 场景 (MAP 头场景 ACT → WLD)、坐标偏移 (渲染坐标 = 地图坐标 + 偏移)、事件框、NPC 常驻表、
      遇敌区域、地图标志、默认音乐 (格式见 tools/mapsdat.py)
  game/collision/<WLD>.bin  地面三角形与阻挡盒 (地图坐标)
  game/new_game.json  新游戏初始金钱 / 道具 / 装备 / 技能, 全局角色 (主控车芸), 遇敌概率组
  game/names.json  角色名 (Name.gll, 键 = 角色号)、道具名 (ObjDATA)、地图名、战场名、曲目文件名
指令语义见 tools/disasm_script.py 的 OPS 表 (每条都有 exe 处理函数的地址作证据)。
"""
import json
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import disasm_script as D  # noqa: E402
import mapsdat as M  # noqa: E402


def convert(ins):
    out = []
    for p, op, q, args in ins:
        if op is None:
            out.append([p, 'data', q])  # 无法解析的数据块: 跳到 q
            continue
        if op == 0xFFFF:
            out.append([p, 'end'])
            continue
        name = D.OPS[op][1]
        vals = []
        rlist = []
        for t, v, fld in args:
            if t == 'r':
                tgt = fld + v
                if D.OPS[op][0].endswith('R'):
                    rlist.append(tgt)
                else:
                    vals.append(tgt)
            elif t == 'T':
                vals.append(D.big5(v))
            else:
                vals.append(v)
        if rlist:
            vals.append(rlist)
        out.append([p, name] + vals)
    return out


def main(game, ext):
    out = os.path.join(ext, 'game')
    os.makedirs(os.path.join(out, 'events'), exist_ok=True)
    stats = {}
    for fn, lo, hi in D.FILES:
        b, offs, nxt = D.read_gll(os.path.join(game, fn))
        codes, events, bad = {}, {}, 0
        default = offs[lo - 1]  # 槽位 = 事件号 - 1; 空槽都指向本文件的第一段脚本
        for slot, o in enumerate(offs):
            eid = slot + 1
            if o == 0xFFFFFFFF or not lo <= eid <= hi or (o == default and eid != lo):
                continue
            key = str(o)
            if key not in codes:
                s = o + 16
                ins, st = D.decode(b[s:nxt[s]])
                codes[key] = convert(ins)
                bad += st != 'ok'
            events[str(eid)] = key
        with open(os.path.join(out, 'events', fn.lower().replace('.gll', '') + '.json'), 'w', encoding='utf-8') as f:
            json.dump({'file': fn, 'first': lo, 'events': events, 'codes': codes}, f, ensure_ascii=False, separators=(',', ':'))
        stats[fn] = (len(events), len(codes), bad)

    # 地图: 权威场景 (MAP 头的场景 ACT) + 偏移 (WLD 包围盒最小角) + 事件框 + NPC 常驻表 + 遇敌 + 默认音乐 + 碰撞
    md = M.MapsDat(game)
    actors = md.actors()
    index = md.map_index()
    zones = md.encounter_zones()
    talisman = md.talisman_events()
    disp = md.map_names()
    music = {r['map_id']: [r['track_a'], r['count_a'], r['track_b'], r['count_b']]
             for r in json.load(open(os.path.join(ext, 'text', 'music.json')))['map_default_music']}
    names_tr = {m['map_id']: m['name_simplified'] for m in json.load(open(os.path.join(ext, 'text', 'maps.json')))}
    os.makedirs(os.path.join(out, 'collision'), exist_ok=True)
    maps, done_wld = {}, {}
    for mid in sorted(names_tr):
        wld = M.scene_of(game, mid)
        if wld not in done_wld:
            bmin, tris, boxes = M.collision(game, wld)
            # 碰撞: u32 三角形数, u32 阻挡盒数, 三角形 9×f32, 阻挡盒 6×f32 (地图坐标)
            with open(os.path.join(out, 'collision', wld + '.bin'), 'wb') as f:
                f.write(struct.pack('<2I', len(tris), len(boxes)))
                for t in tris:
                    f.write(struct.pack('<9f', *t))
                for bx in boxes:
                    f.write(struct.pack('<6f', *bx))
            done_wld[wld] = [round(x, 2) for x in bmin]
        mi = index.get(mid, {})
        # MAP 头 +0x56 的 6 个 float = 雾 (0x4146bb → 0x412d09): p0..p2 雾色, p3/p4 起点, p5 → 偏移 1.01−p5; p4 > 0 才开
        fog = None
        mp = os.path.join(game, 'MAP', 'WLD%d.MAP' % mid)
        if os.path.exists(mp):
            with open(mp, 'rb') as fh:
                hdr = fh.read(0x56 + 24)
            if len(hdr) >= 0x56 + 24:
                p6 = struct.unpack_from('<6f', hdr, 0x56)
                if p6[4] > 0:
                    fog = [round(x, 4) for x in p6]
        maps[mid] = {'name': names_tr[mid], 'title': D._cc(disp.get(mid, '')), 'scene': 'scenes/%s.glb' % wld, 'wld': wld,
                     'offset': done_wld[wld], 'boxes': M.map_boxes(game, mid),
                     'npcs': [a for a in actors if a['map'] == mid],
                     'encounters': bool(mi.get('encounters')), 'flags': mi.get('flags', 0),
                     'zones': [z for z in zones if z['map'] == mid], 'music': music.get(mid), 'fog': fog,
                     'talisman_event': talisman.get(mid)}   # 在这张图用土地神符启动的事件 (MAPS.DAT 第 17 段)
    with open(os.path.join(out, 'maps.json'), 'w', encoding='utf-8') as f:
        json.dump(maps, f, ensure_ascii=False, separators=(',', ':'))
    with open(os.path.join(out, 'new_game.json'), 'w', encoding='utf-8') as f:
        json.dump({'init': md.new_game(), 'actors': [a for a in actors if a['map'] == 0 and a['actor']],
                   'encounter_groups': md.encounter_groups()}, f, ensure_ascii=False, indent=1)
    print('地图 %d 张 (场景 %d 个), 常驻角色 %d 条' % (len(maps), len(done_wld), len(actors)))

    names = D.Names(os.path.join(ext, 'text'))
    with open(os.path.join(out, 'names.json'), 'w', encoding='utf-8') as f:
        json.dump({'people': names.people, 'items': names.items, 'maps': names.maps, 'battlefields': names.bf,
                   'music': names.music}, f, ensure_ascii=False, indent=0)
    for fn, (ne, nc, bad) in stats.items():
        print('%-12s %4d 事件 %4d 段代码 %d 段未完整解析' % (fn, ne, nc, bad))


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
