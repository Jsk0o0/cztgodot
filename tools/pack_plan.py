"""发行版分包规划: 运行时要读的提取结果 → 公共包 + 各章节包 (+ 2K / 4K 覆盖包各一个)

用法: python pack_plan.py <extracted> <游戏目录> <输出 plan.json> [--hd2 <extracted_hd>] [--hd4 <extracted_4k>]
输出: {"packs": {包名: [[res 路径, 源文件], ...]}, "sizes": {包名: 字节}, "chapter_of": {...统计用}}
  包名: common / ch01 … ch10 (标清, 路径 res://extracted/…); hd2 (res://extracted_hd/…); hd4 (res://extracted_4k/…)
  高清包只放和标清不同的文件 (放大的图片、视频), GLB 不放整份: 只放对照表 <模型>.tex.json + 用到的贴图 tex/* (tools/hd_textures.py),
  运行时读标清 GLB 再换贴图 (godot/scripts/hd_textures.gd)

运行时要读的 (按游戏代码逐处核对): game/ 全部、scenes/、effects/、ui/、video/、models/SYS/SYS00017.glb;
  音乐 Music/ 和音效 ACT/all.snd: 第一次从游戏目录复制到 <extracted>/audio/, 包里同路径 (Game.audio_path)。
  不进包: text/ stats/ scripts/ story/ preview/ levels/ textures/ models/ 其余 (开发工具 / 编辑器用)
章节归属 (只影响素材落在哪个包, 启动时所有包都会加载, 分错也不影响游戏):
  地图 → 章节: 自动通关每段日志 out/ap/stageN.log 里出现过的 map=, 加上剧情快照 (stage, map)
  事件 → 章节: 剧情快照 (stage, eid)
  场景模型 / 标记 / 碰撞 ← 用到它的地图; 战场 (场景 + bf 碰撞 + 敌人模型) ← 地图遇敌区 + 事件 start_battle;
  过场动画 ← 事件 play_video; 地图常驻 NPC 的模型 ← 地图
  只在一章出现 → 那一章; 多章共用或统计不到 → 公共
"""
import glob
import json
import os
import re
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
INCLUDE_DIRS = ['game', 'scenes', 'effects', 'ui', 'video']
INCLUDE_FILES = ['models/SYS/SYS00017.glb']
NCH = 10


def chapters_of_maps_events():
    maps, events = {}, {}
    for st in range(1, NCH + 1):
        p = os.path.join(ROOT, 'out', 'ap', 'stage%d.log' % st)
        if os.path.exists(p):
            for m in re.finditer(r'\bmap=(\d+)', open(p, encoding='utf-8', errors='replace').read()):
                maps.setdefault(int(m.group(1)), set()).add(st)
    for f in glob.glob(os.path.join(ROOT, 'extracted', 'story', 'snapshots', '*.json')):
        d = json.load(open(f, encoding='utf-8'))
        st = int(d.get('stage') or 0)
        if not 1 <= st <= NCH:
            continue
        events.setdefault(int(d['eid']), set()).add(st)
        if d.get('map'):
            maps.setdefault(int(d['map']), set()).add(st)
    return maps, events


def main(ext, game, out, hd2=None, hd4=None):
    ext, game = os.path.abspath(ext), os.path.abspath(game)
    hd2, hd4 = (os.path.abspath(hd2) if hd2 else None), (os.path.abspath(hd4) if hd4 else None)
    map_ch, ev_ch = chapters_of_maps_events()
    maps = json.load(open(os.path.join(ext, 'game', 'maps.json'), encoding='utf-8'))
    battle = json.load(open(os.path.join(ext, 'game', 'battle.json'), encoding='utf-8'))
    use = {}   # 相对路径 → 章节集合

    def add(rel, chs):
        if chs:
            use.setdefault(rel, set()).update(chs)

    bf_ch = {}
    for mid, m in maps.items():
        chs = map_ch.get(int(mid), set())
        if m.get('scene'):
            scene = os.path.basename(m['scene'])[:-4]
            add('scenes/%s.glb' % scene, chs)
            add('scenes/%s.markers.json' % scene, chs)
        if m.get('wld'):
            add('game/collision/%s.bin' % m['wld'], chs)
        for r in m.get('npcs', []):
            a = int(r.get('act', 0))
            if 0 < a < 12000 or a >= 15000:
                for f in glob.glob(os.path.join(ext, 'game', 'actors', 'act_%d_g*.glb*' % a)) + [os.path.join(ext, 'game', 'actors', 'act_%d.json' % a)]:
                    add(os.path.relpath(f, ext), chs)
        for z in m.get('zones', []):
            for b in z.get('battlefields', []):
                bf_ch.setdefault(int(b), set()).update(chs)
    for f in glob.glob(os.path.join(ext, 'game', 'events', '*.json')):
        ev = json.load(open(f, encoding='utf-8'))
        owners = {}   # codes 的键是脚本偏移, events 是 事件编号 → 偏移
        for eid, key in ev['events'].items():
            owners.setdefault(str(key), []).append(int(eid))
        for key, code in ev['codes'].items():
            chs = set().union(*[ev_ch.get(e, set()) for e in owners.get(key, [])])
            if not chs:
                continue
            for ins in code:
                if ins[1] == 'start_battle':
                    bf_ch.setdefault(int(ins[2]), set()).update(chs)
                elif ins[1] == 'play_video':
                    add('video/%s.ogv' % os.path.splitext(str(ins[2]))[0], chs)
    for bf, chs in bf_ch.items():
        b = battle['battlefields'].get(str(bf))
        if not b:
            continue
        if b.get('scene'):
            add('scenes/%s.glb' % b['scene'], chs)
            add('scenes/%s.markers.json' % b['scene'], chs)
            add('game/collision/bf_%s.bin' % b['scene'], chs)
        for e in b.get('enemies', []):
            a = int(battle['objs'].get(str(e['id']), {}).get('act', e['id']))
            for f in glob.glob(os.path.join(ext, 'game', 'actors', 'act_%d_g*.glb*' % a)) + [os.path.join(ext, 'game', 'actors', 'act_%d.json' % a)]:
                add(os.path.relpath(f, ext), chs)

    def pack_of(rel):
        chs = use.get(rel, set())
        return 'ch%02d' % next(iter(chs)) if len(chs) == 1 else 'common'

    files = []
    for d in INCLUDE_DIRS:
        for f in glob.glob(os.path.join(ext, d, '**', '*'), recursive=True):
            if os.path.isfile(f):
                files.append(os.path.relpath(f, ext).replace(os.sep, '/'))
    files += [f for f in INCLUDE_FILES if os.path.isfile(os.path.join(ext, f))]
    packs, sizes = {}, {}

    def put(name, res, src):
        packs.setdefault(name, []).append([res, src])
        sizes[name] = sizes.get(name, 0) + os.path.getsize(src)

    for rel in sorted(files):
        put(pack_of(rel), 'res://extracted/' + rel, os.path.join(ext, rel))
    # 音频: 先复制到 <extracted>/audio/ (之后打包不再需要原版目录; 游戏开发环境也优先读这里, 同 Game.audio_path)
    aud = os.path.join(ext, 'audio')
    if not os.path.isfile(os.path.join(aud, 'ACT', 'all.snd')):
        import shutil
        os.makedirs(os.path.join(aud, 'ACT'), exist_ok=True)
        shutil.copytree(os.path.join(game, 'Music'), os.path.join(aud, 'Music'), dirs_exist_ok=True)
        shutil.copy2(os.path.join(game, 'ACT', 'all.snd'), os.path.join(aud, 'ACT', 'all.snd'))
    for f in sorted(os.listdir(os.path.join(aud, 'Music'))):
        put('common', 'res://extracted/audio/Music/' + f, os.path.join(aud, 'Music', f))
    put('common', 'res://extracted/audio/ACT/all.snd', os.path.join(aud, 'ACT', 'all.snd'))
    # 高清覆盖包: 不分章节 (启动时全部加载, 分开没好处; 同一张贴图常被多章的模型共用, 合在一起只存一份)
    import filecmp
    for tag, hd, prefix in (('hd2', hd2, 'extracted_hd'), ('hd4', hd4, 'extracted_4k')):
        if not hd:
            continue
        tex = set()
        for rel in sorted(files):
            if rel.endswith('.glb'):
                idx = os.path.join(hd, rel + '.tex.json')
                if os.path.isfile(idx):
                    put(tag, 'res://%s/%s.tex.json' % (prefix, rel), idx)
                    tex.update(t for t in json.load(open(idx))['tex'] if t)
                continue
            src = os.path.join(hd, rel)
            if os.path.isfile(src) and not filecmp.cmp(src, os.path.join(ext, rel), shallow=False):
                put(tag, 'res://%s/%s' % (prefix, rel), src)
        for t in sorted(tex):
            put(tag, 'res://%s/tex/%s' % (prefix, t), os.path.join(hd, 'tex', t))
    plan = {'packs': packs, 'sizes': sizes,
            'chapter_of': {'maps': {str(k): sorted(v) for k, v in sorted(map_ch.items())}, 'battlefields': {str(k): sorted(v) for k, v in sorted(bf_ch.items())}}}
    json.dump(plan, open(out, 'w', encoding='utf-8'), ensure_ascii=False)
    for k in sorted(sizes):
        print('%-12s %5d 个文件 %7.1f MB' % (k, len(packs[k]), sizes[k] / 1048576))


if __name__ == '__main__':
    a = sys.argv[1:]
    opt = {}
    for k in ('--hd2', '--hd4'):
        if k in a:
            i = a.index(k)
            opt[k[2:]] = a[i + 1]
            del a[i:i + 2]
    main(a[0], a[1], a[2], **opt)
