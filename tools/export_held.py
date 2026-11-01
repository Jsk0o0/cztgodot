"""导出角色手持物 (事件指令 0x8a set_weapon_model / 战斗中队员的武器) → extracted/game/held/

用法: python export_held.py <游戏目录> <extracted 目录>
  手持物 = 道具 ACT (all_item.act, 编号 = 物品游戏编号) 的第 qq 号动作的模型, 挂到角色挂点 n 的骨骼上
  (0x8a 参数: 角色, 物品, qq, n; n = 0 卸下。例: 开场车芸收云狐 1, 5521 天书残简, 1, 1)
输出: held/item_<物品>_<qq>.glb (动画 held, 35 帧/秒)
      并给 game/actors/act_*.json 的每个模型组补上 "marker_basis": {挂点: [sx, sy, sz]}
      —— 武器矩阵 = 挂点段矩阵旋转部分取负 [-R | t] (exe 0x419eee); 导出时该段骨骼若被 X 翻转 (ply2gltf.unmirror),
         相对骨骼的基为 diag(1,-1,-1), 否则 diag(-1,-1,-1) (同 skill_catalog 的嬴诗武器)
"""
import glob
import json
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from act import actions  # noqa: E402
from ply import parse  # noqa: E402
from ply2gltf import export  # noqa: E402

FPS = 35.0
MARKERS = (1, 2, 3)   # 3 = 云狐嘴部 (车芸的刀衔在嘴里)


def held_list(ext):
    need = set()
    for f in glob.glob(os.path.join(ext, 'game', 'events', '*.json')):
        d = json.load(open(f))
        for code in d['codes'].values():
            for ins in code:
                if ins[1] == 'set_weapon_model' and ins[3]:
                    need.add((ins[3], ins[4]))
    # 队员可装备的武器 (战斗中手持, qq 1)
    for e in json.load(open(os.path.join(ext, 'stats', 'equipment.json'))):
        if e.get('部位 slot') == '武器':
            need.add((e['编号 id'], 1))
    # 敌方单位的普攻武器 (ObjDATA +0x3F1 = 武器物品编号, 例 晋兵 5307「敌方士兵枪」), 战斗中挂在挂点 1
    bj = os.path.join(ext, 'game', 'battle.json')
    if os.path.exists(bj):
        for o in json.load(open(bj))['objs'].values():
            w = int(o.get('power') or 0)
            if o.get('kind') == 1 and 3000 <= w < 6000:
                need.add((w, 1))
    # 法宝小游戏的 3D 道具: 鼠槌的锤子 (5212 qq1, 8 帧), 四非真面的脸谱本体 + 喜怒哀乐四个标签 (5210 qq1..5)
    need |= {(5212, 1), (5210, 1), (5210, 2), (5210, 3), (5210, 4), (5210, 5)}
    # 四首木甲 (2024 / 2124 / 2224 / 2324, exe 0x43dba7): 武器 ACT 5474 的第 3 号动作 = 四个头的转盘 (80 帧, 本体矩阵下播放,
    # 变化号 0/1/2/3 停在第 1/61/21/41 帧), 第 4+变化号 号动作 = 眼光 (31 帧循环), 画在转盘模型挂点 (30,31)/(34,35)/(36,37)/(32,33), 缩放 3
    need |= {(5474, q) for q in (3, 4, 5, 6, 7)}
    return sorted(need)


def marker_basis(game, files, cache):
    out = {}
    for m in MARKERS:
        dets = []
        for f in files:
            if f not in cache:
                try:
                    cache[f] = parse(os.path.join(game, 'Model', f + '.PLY'))
                except Exception:  # noqa: BLE001
                    cache[f] = None
            p = cache[f]
            if p is None:
                continue
            seg = [i for i, sg in enumerate(p.segments) if sg.flags >> 24 == m]
            if seg:
                dets.append(np.linalg.det(p.matrices[:, seg[0], :3, :3].astype(float)))
        if dets:
            d = np.concatenate(dets)
            out[m] = [1, -1, -1] if (d < -1e-9).sum() > (d > 1e-9).sum() else [-1, -1, -1]
    return out


def main(game, ext):
    out = os.path.join(ext, 'game', 'held')
    os.makedirs(out, exist_ok=True)
    items = open(os.path.join(game, 'ACT', 'all_item.act'), 'rb').read()
    n = 0
    for item, qq in held_list(ext):
        dst = os.path.join(out, 'item_%d_%d.glb' % (item, qq))
        try:
            h = actions(items, item).get(qq)
        except (KeyError, IndexError):
            h = None
        if not h or not os.path.exists(os.path.join(game, 'Model', h['model'] + '.PLY')):
            continue
        if os.path.exists(dst):
            # 有逐帧顶点变形 (UV 动画, 例 解封轩辕剑 4115 剑身光流) 但还没有 sidecar 的旧导出要重导
            from export_actors import uv_animated
            if os.path.exists(dst + '.morph.json') or not uv_animated(game, h['model'], {}):
                continue
        # sidecar: 引擎按 <glb>.morph.json 逐帧换 UV (glTF 的 UV morph Godot 不认)
        from export_actors import uv_animated
        export(game, [h['model']], dst, fps=FPS, clips=[('held', 0, h['aps'] or [0])], sidecar=uv_animated(game, h['model'], {}))
        n += 1
    cache = {}
    k = 0
    for p in glob.glob(os.path.join(ext, 'game', 'actors', 'act_*.json')):
        if p.endswith('.morph.json'):
            continue   # 模型的逐帧变形 sidecar, 不是角色表
        d = json.load(open(p))
        if all(g.get('marker_set') == list(MARKERS) for g in d['groups']):
            continue   # 已按当前挂点表算过
        for g in d['groups']:
            g['marker_basis'] = marker_basis(game, g['files'], cache)
            g['marker_set'] = list(MARKERS)
        json.dump(d, open(p, 'w', encoding='utf-8'), ensure_ascii=False)
        k += 1
    print('手持物 %d 个新导出, 角色挂点基 %d 个' % (n, k))


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
