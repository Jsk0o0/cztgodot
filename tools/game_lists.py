"""从导出的游戏数据算出需要的角色模型和战斗特效清单 (序章: 地图 + 剧情 + 战斗)

用法: python game_lists.py <extracted 目录>
输出: game/actors_needed.txt (ACT 号, 每行一个), game/battle_fx_src.json (要生成特效的 ATK 步骤),
      game/field_fx_src.json (地图事件的动画特效 act/qq)
"""
import json
import os
import sys

PROLOGUE_MAPS = [12403, 12201, 12202, 12412, 12603, 12607, 12602, 12605, 12606, 12609, 12610, 12604, 13029,   # 13029 天书世界 (兔子箱进入)
                 12001, 12203, 12401, 12402, 12404, 12405, 13003, 13030]   # 序章途经: 晋国大地图、曲沃城、令狐国各屋、天书相关
PROLOGUE_BATTLES = [18, 19, 245, 246, 247, 248, 249, 25, 251, 274] + list(range(8, 25))


def main(ext):
    global PROLOGUE_MAPS, PROLOGUE_BATTLES
    g = os.path.join(ext, 'game')
    maps = json.load(open(os.path.join(g, 'maps.json')))
    B = json.load(open(os.path.join(g, 'battle.json')))
    # 第一章起改为全游戏: 所有地图、所有战场 (一次导出, 后面各章不用再补)
    PROLOGUE_MAPS = sorted(int(k) for k in maps)
    PROLOGUE_BATTLES = sorted(int(k) for k in B['battlefields'])
    O = B['objs']
    acts = {1, 2, 3, 11}
    for m in PROLOGUE_MAPS:
        for n in maps[str(m)]['npcs']:
            if 0 < n['act'] < 12000 or n['act'] >= 15000:   # 12000–14999 是场景 (WLD)
                acts.add(n['act'])
    # 被脚本搬到其他地图的角色 (place_actor_map, 例: 神秘兔子 2461 记录在 13031) 用它原始记录的 ACT
    base_act = {n['actor']: n['act'] for mp in maps.values() for n in mp['npcs']}
    for f in os.listdir(os.path.join(g, 'events')):
        d = json.load(open(os.path.join(g, 'events', f)))
        for code in d['codes'].values():
            for ins in code:
                if ins[1] == 'place_actor_map' and ins[3] in PROLOGUE_MAPS:
                    a2 = base_act.get(ins[2], 0)
                    if 0 < a2 < 12000 or a2 >= 15000:
                        acts.add(a2)
                if ins[1] == 'set_act' and (0 < ins[3] < 12000 or ins[3] >= 15000):
                    acts.add(ins[3])
    atk = set()

    def unit(i):
        o = O.get(str(i), {})
        acts.add(i)
        for k in ('atk_id', 'atk2_id'):
            if o.get(k):
                atk.add(o[k])
        for s in o.get('skills') or []:
            if s and O.get(str(s), {}).get('atk_id'):
                atk.add(O[str(s)]['atk_id'])
    for n in PROLOGUE_BATTLES:
        for e in B['battlefields'][str(n)]['enemies']:
            unit(e['id'])
        for ins in B['figtalk'].get(str(n - 1), []):
            if ins[1] == 'start_battle':
                atk |= {ins[2], ins[3]}
            elif ins[1] == 'add_unit_at':
                unit(ins[2])
            elif ins[1] == 'change_unit_obj':
                unit(ins[3])
    for c in (1, 2, 3, 11):
        unit(c)
    # 记载页的怪物图鉴、天书居民 / 配置画面会显示任意怪物的模型 (ObjDATA 大类 1, 种族子类 110–120)
    for k, o in O.items():
        if o.get('kind') == 1 and 110 <= int(o.get('sub') or 0) <= 120:
            acts.add(int(k))
    # 天书房舍模型 (9501 茅草屋 … 9526 转生台, 含工房各等级)
    acts |= set(range(9501, 9527))
    for o in O.values():   # 主角能用的技能 / 装备 / 道具
        if o.get('kind') in (2, 3) and o.get('atk_id'):
            atk.add(o['atk_id'])
    atk = {a for a in atk if str(a) in B['atk']}
    # 地图动画特效 (事件 0x5b/0x5c/0x5d add_ani_*: act/qq; 9200 是回忆插图, 走 2D)
    field_fx = set()
    for f in os.listdir(os.path.join(g, 'events')):
        d = json.load(open(os.path.join(g, 'events', f)))
        for code in d['codes'].values():
            for ins in code:
                if ins[1] == 'add_ani_on_actor':
                    field_fx.add((ins[3], ins[4]))
                elif ins[1] in ('add_ani_move', 'add_ani_to_actor', 'add_actor_effect'):
                    field_fx.add((ins[-2], ins[-1]))
    field_fx.update({(8001, 5), (8001, 6)})   # 标题画面的竹叶 (0x470b53: 两套粒子, 资源 ACT 8001 动作 5 / 6)
    field_fx.add((8001, 2))
    field_fx.update({(8003, 5), (8003, 6), (8120, 0)})   # 收化: 法器 8003 动作 5 (出) / 6 (收), 粒子外观 8120   # 下雪 (事件 0x6b / 地图标志 0x08): 雪花方片 MGC00179
    field_fx = sorted(x for x in field_fx if x[0] and x[0] != 9200)
    with open(os.path.join(g, 'field_fx_src.json'), 'w') as f:
        json.dump({'fps': 35, 'steps': [{'t': 'effect', 'id': a, 'sub': q, 'at': 'field'} for a, q in field_fx]}, f)
    with open(os.path.join(g, 'actors_needed.txt'), 'w') as f:
        f.write('\n'.join(str(a) for a in sorted(x for x in acts if 0 < x < 12000 or x >= 15000)))
    with open(os.path.join(g, 'battle_fx_src.json'), 'w') as f:
        json.dump({'atk': {a: B['atk'][str(a)] for a in sorted(atk)}}, f)
    print('角色模型 %d 个, 招式 %d 个, 地图特效 %d 个' % (len(acts), len(atk), len(field_fx)))


if __name__ == '__main__':
    main(sys.argv[1])
