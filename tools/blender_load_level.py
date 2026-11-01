"""在 Blender 中载入一个关卡: 场景模型 + 触发区盒子
传送区=绿色, 事件区=橙色, 附加触发点=红色; 自定义属性里记录 event_id / target_map。
用法 (界面中: Scripting 面板运行, 或命令行):
  blender --python tools/blender_load_level.py -- extracted/levels/12201.json [--keep-backdrop]
"""
import json
import os
import sys

import bpy

argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
level_path = os.path.abspath(argv[0])
keep_backdrop = '--keep-backdrop' in argv
root = os.path.dirname(os.path.dirname(level_path))  # extracted/
lv = json.load(open(level_path, encoding='utf-8'))

if lv['scene_glb']:
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(root, lv['scene_glb']))
    for o in set(bpy.data.objects) - before:
        if 'backdrop' in o.name and not keep_backdrop:
            o.hide_set(True)
            o.hide_render = True

coll = bpy.data.collections.new(f"triggers_{lv['map_id']}")
bpy.context.scene.collection.children.link(coll)
COLORS = {'portal': (0.1, 0.9, 0.2, 1), 'event': (1.0, 0.55, 0.0, 1), 'point': (0.95, 0.1, 0.1, 1)}
for t in lv['triggers']:
    x, y, z = t['gltf']
    loc = (x, -z, y)  # glTF Y 朝上 -> Blender Z 朝上
    if t['box_min']:
        size = [(t['box_max'][i] - t['box_min'][i]) * 0.01 for i in range(3)]
        bpy.ops.mesh.primitive_cube_add(location=loc)
        o = bpy.context.active_object
        o.scale = (max(size[0], 0.05) / 2, max(size[2], 0.05) / 2, max(size[1], 0.05) / 2)
    else:
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.3, location=loc)
        o = bpy.context.active_object
    o.name = f"{t['kind']}_{t['event_id']}_{t['name'] or ''}"
    o.color = COLORS[t['kind']]
    o['event_id'] = t['event_id']
    if t['target_map']:
        o['target_map'] = t['target_map']
    for c in o.users_collection:
        c.objects.unlink(o)
    coll.objects.link(o)
print(f"loaded {lv['name']}: {len(lv['triggers'])} triggers")
