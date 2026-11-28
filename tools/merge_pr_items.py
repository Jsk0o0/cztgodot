"""把上游 PR #15 (道具修复) 合入「懒人补丁包」整替的 battle / field/main_menu 字节码.

背景: 补丁器 v22 基于旧版官方源码, 整替 14 个脚本的 .gdc (实测清单: game/title/mod_manager/
hd_textures/fx/dialog/field/field_actor/main_menu/menu_jizai/menu_tianshu/minimap/battle/
battle_hud). 上游 PR #15 修的正是 battle/main_menu → 双击懒人补丁会把修复覆盖掉.
补丁作者在这两个脚本里的自有改动 (物理插值/遮挡物调试/插值开关等) 与 PR #15 修改的函数
(_party_unit/_finish/_key_items/_item_effect/_draw_equip) 不重叠, 所以按函数级拼接合并:

    pck(已含 mod_manager ROOT 注入) 提取补丁版 gdc → 反编译 → 替换 5 处为 PR #15 逻辑
    → 重编译 → 注回 pck.   无损自检 (原样往返字节一致) 不通过即拒绝修改.

(补丁作者若已含 PR #15 —— 未来某版补丁基于新 main —— 脚本检测后自动跳过该文件.)

用法: merge_pr_items.py <GDRE目录> <czt.pck> [--check]
依赖同 make_portable_mods.py (GDRE v2.7+, venv 的 zstandard).
"""
import os
import re
import sys
import tempfile

import make_portable_mods as mpm

# ---- PR #15 拼接: (old_block, new_block) 逐字对照 git show pr15 的两处 diff, 缩进=1 tab ----
BATTLE = [
    # ① _party_unit: base 属性先行, hp/mp/sp 封顶, 状态位带入战斗 (旧块=旧官方原文; 补丁未动此块)
    (
        "\tu.hp = int(mem.hp)\n"
        "\tu.hp_max = int(mem.hp_max)\n"
        "\tu.mp = int(mem.mp)\n"
        "\tu.mp_max = int(mem.mp_max)\n"
        "\tu.sp = int(mem.sp)\n"
        "\tu.sp_max = int(mem.sp_max)\n"
        "\tu.juji = int(mem.get(\"juji\", 0))\n"
        "\tu.base = State.member_stats(m)\n"
        "\tu.crit = int(u.base.get(\"crit\", 0))\n"
    ,
        "\tu.base = State.member_stats(m)\n"
        "\tu.crit = int(u.base.get(\"crit\", 0))\n"
        "\tu.hp_max = int(u.base.get(\"hp_max\", mem.hp_max))\n"
        "\tu.mp_max = int(u.base.get(\"mp_max\", mem.mp_max))\n"
        "\tu.sp_max = int(u.base.get(\"sp_max\", mem.sp_max))\n"
        "\tu.hp = mini(int(mem.hp), u.hp_max)\n"
        "\tu.mp = mini(int(mem.mp), u.mp_max)\n"
        "\tu.sp = mini(int(mem.sp), u.sp_max)\n"
        "\tu.juji = int(mem.get(\"juji\", 0))\n"
        "\tvar st_mask := State.status_mask(m)\n"
        "\tfor b in Formula.STATUS_NAMES:\n"
        "\t\tif st_mask & int(b):\n"
        "\t\t\tu.add_status(int(b), 255)\n"
    ),
    # ② _finish: 战斗状态位带回地图
    ("\t\t\tm.juji = u.juji\n",
     "\t\t\tm.juji = u.juji\n"
     "\t\t\tm.status = u.status & 0x0BFC\n"),
]
MAIN_MENU = [
    # ③ _key_items: 剧情机关道具明确提示
    ("\t\telif iid == 3801:\n\t\t\t_use_mystery_fruit()\n",
     "\t\telif iid == 3801:\n\t\t\t_use_mystery_fruit()\n"
     "\t\telif iid in [3903, 3904]:\n"
     "\t\t\tGame.play_sound(Game.SFX_UI_ERROR)\n"
     "\t\t\t_say(\"这是剧情机关，不能从物品菜单直接使用\")\n"),
    # ④ _item_effect a: 属性药字段修正 (回避=fx1[5], 仙命中=fx2[3], 仙回避=fx2[4])
    (
        "\t\t\t[\"hit\", int(fx1[4])], [\"eva\", int(fx2[4])], [\"mhit\", int(r.get(\"mhit\", 0))], [\"meva\", int(r.get(\"meva\", 0))], \n"
    ,
        "\t\t\t[\"hit\", int(fx1[4]) if int(fx1[4]) else int(r.get(\"hit\", 0))],\n"
        "\t\t\t[\"eva\", int(fx1[5]) if int(fx1[5]) else int(r.get(\"eva\", 0))],\n"
        "\t\t\t[\"mhit\", int(fx2[3]) if int(fx2[3]) else int(r.get(\"mhit\", 0))],\n"
        "\t\t\t[\"meva\", int(fx2[4]) if int(fx2[4]) else int(r.get(\"meva\", 0))],\n"
    ),
    # ④b _item_effect: 神兵令 juji_gain (插在 atk/def 永久加值循环之后, 即 sp 段之前)
    ("\tvar hp: = 0\n",
     "\t# 神兵令: 蓄劲 juji_gain (PR#15)\n"
     "\tvar jj := int(r.get(\"juji_gain\", 0))\n"
     "\tif jj > 0 and int(d.get(\"juji\", 0)) < 100:\n"
     "\t\td.juji = mini(100, int(d.get(\"juji\", 0)) + jj)\n"
     "\t\teff = true\n"
     "\tvar hp: = 0\n"),
    # ④c _item_effect: 状态药真正解除 (sop&0x5000 → State.clear_status; 0x10000000 只看 status 本字段)
    (
        "\tvar st: = int(r.get(\"status\", 0)) | (int(r.get(\"status_op\", 0)) << 16)\n"
        "\tvar dead: = int(d.hp) <= 0\n"
        "\tif st & 268435456:\n"
        "\t\teff = true\n"
        "\t\tif st & 2:\n"
        "\t\t\tdead = false\n",
        "\tvar smask := int(r.get(\"status\", 0)) & 0x0BFC\n"
        "\tvar revive := int(r.get(\"status\", 0)) & 0x2\n"
        "\tvar sop := int(r.get(\"status_op\", 0))\n"
        "\tvar dead: = int(d.hp) <= 0\n"
        "\tif sop & 0x5000:\n"
        "\t\tvar cleared := State.clear_status(m, smask)\n"
        "\t\tif cleared:\n"
        "\t\t\teff = true\n"
        "\t\tif revive and dead:\n"
        "\t\t\td.hp = maxi(int(d.hp), 1)\n"
        "\t\t\tdead = false\n"
        "\t\t\teff = true\n"
        "\tif int(r.get(\"status\", 0)) & 0x10000000:\n"
        "\t\teff = true\n"
        "\t\tif revive and dead:\n"
        "\t\t\tdead = false\n"
        "\t\t\td.hp = maxi(int(d.hp), 1)\n",
    ),
    # ⑤ _draw_equip: 上限用 cur (装备加成后), cur 声明上移
    (
        "\tvar d: = State.member(m)\n"
        "\tif _members.size() > 1:\n",
        "\tvar d: = State.member(m)\n"
        "\tvar cur: = State.member_stats(m)\n"
        "\tif _members.size() > 1:\n",
    ),
    (
        "\tvar rows: = [[\"生命:\", int(d.hp), int(d.hp_max), 0 if m == 1 else 1, 17 if m == 1 else 18], \n"
        "\t\t[\"灵力:\", int(d.mp), int(d.mp_max), 2, 19], [\"体力:\", int(d.sp), int(d.sp_max), 3, 20]]\n",
        "\tvar rows: = [[\"生命:\", int(d.hp), int(cur.hp_max), 0 if m == 1 else 1, 17 if m == 1 else 18],\n"
        "\t\t[\"灵力:\", int(d.mp), int(cur.mp_max), 2, 19], [\"体力:\", int(d.sp), int(cur.sp_max), 3, 20]]\n",
    ),
    ("\tvar cur: = State.member_stats(m)\n\tvar nxt: = cur\n", "\tvar nxt: = cur\n"),
]
CHECKS = {   # 合并后从新 gdc 反编译回来, 必须出现的 PR #15 独有行 (行级最可靠:
             # 明文串会被 zstd 前缀复用压缩, 标识符断言不可靠 — 实测 add_status/STATUS_NAMES 均不可见)
    "battle": ["State.status_mask(m)", "u.add_status(int(b), 255)",
               "m.status = u.status & 3068", "mini(int(mem.hp), u.hp_max)"],
    "main_menu": ["int(fx1[5]) if int(fx1[5])", "State.clear_status(m, smask)",
                  "r.get(\"juji_gain\", 0)", "int(cur.hp_max)", "iid in [3903, 3904]"],
}
PR_MARKS = {  # 补丁版已含 PR #15 的特征 (作者日后基于新 main 重编补丁 → 自动跳过)
    "battle": "State.status_mask",
    "main_menu": "juji_gain",
}


def apply_blocks(text, blocks, name):
    for old, new in blocks:
        if old not in text:               # 锚点已不在: 合并过(或整文件已被 PR_MARKS 拦下), 校验目标在则跳过
            if new in text or new == old:
                print(f"  {name}: 块已合并, 跳过")
                continue
            sys.exit(f"{name}: 锚点与目标都不存在, 补丁结构已变, 需人工核对: {old.strip()[:60]}")
        if text.count(old) != 1:
            sys.exit(f"{name}: 锚点出现 {text.count(old)} 次 (应为 1), 需人工核对: {old.strip()[:60]}")
        text = text.replace(old, new)
    return text


def main():
    args = [a for a in sys.argv[1:] if a != "--check"]
    check_only = "--check" in sys.argv[1:]
    if len(args) < 2:
        sys.exit(__doc__)
    mpm.GDRE_DIR, pck = os.path.abspath(args[0]), os.path.abspath(args[1])
    for name, blocks in (("battle", BATTLE), ("main_menu", MAIN_MENU)):
        res = f"res://scripts/{'battle/battle' if name == 'battle' else 'field/main_menu'}.gdc"
        orig = mpm.gdc_from_pck_named(pck, name + ".gdc")
        with tempfile.TemporaryDirectory(prefix=f"czt_{name}_") as wd:
            gd = mpm.decompile_named(wd, orig, name)
            rt = mpm.compile_gd(wd, mpm.write_gd_named(wd, gd, name), os.path.join(wd, "rt"))
            if rt != orig:
                sys.exit(f"{name}: 无损自检失败 (往返字节不一致), 拒绝修改")
            print(f"{name}: 无损自检通过 ({len(orig)}B)")
            if PR_MARKS[name] in gd:
                print(f"{name}: 补丁已含 PR #15, 无需合并")
                continue
            if check_only:
                continue
            merged = apply_blocks(gd, blocks, name)
            newgdc = mpm.compile_gd(wd, mpm.write_gd_named(wd, merged, name), os.path.join(wd, "fin"))
            # 验证: 重编译 → 再反编译, 行级确认 PR #15 逻辑进了字节码 (重编译丢代码在这里会被抓住)
            back = mpm.decompile_named(os.path.join(wd, "ver"), newgdc, name)
            for mark in CHECKS[name]:
                assert mark in back, f"{name}: 合并后反编译缺 PR#15 行: {mark}"
            assert "physics_interpolation" in back or name != "battle", \
                "battle: 补丁作者自有改动丢失"   # 作者特性 (PI 开关) 必须仍在
            mpm.inject_named(pck, res, newgdc, name)
            print(f"{name}: PR #15 已合入并注回 ({len(orig)}→{len(newgdc)}B)")


if __name__ == "__main__":
    main()
