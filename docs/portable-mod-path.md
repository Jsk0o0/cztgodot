# 便携 + 上游修复合并处理指南（补丁产物改造）—— 项目更新后的处理

> 适用场景：上游发行包 / 「懒人补丁包.exe」更新后，需要重新让 `game\` 满足
> "整个文件夹拷到任意机器、双击 `czt.exe` 即用"（存档 / Mod / 设置 / 音频目录全便携，
> 不依赖 APPDATA、不使用目录联接），**同时保住上游 PR 对 battle/main_menu 等被补丁
> 整替脚本的修复**。
> **项目更新后在新对话中处理本问题时，直接按第 4 节流程执行即可。**

---

## 1. 结论（TL;DR）

补丁器整替 14 个脚本字节码，且**基于旧版 main 编译**——上游新修复只要涉及这 14 个
脚本，打完补丁就会在运行时被覆盖（源码合码无效，改的是 pck）。两类改动都通过
"反编译补丁产物 → 改 → 重编译 → 注回"处理，工具链已实测无损（GDRE v2.7.4 原样往返
字节一致）：

1. **便携 Mod 路径**：`tools/make_portable_mods.py` ——
   `mod_manager` 的 `const ROOT := "user://mods"` 替换为
   `Portable.path_in("mods", "user://mods")`。Mod 走引擎原生路径 `<程序目录>\userdata\mods`。
2. **上游修复合入补丁**：`tools/merge_pr_items.py` —— 目前包含 PR #15（道具修复）在
   `battle` / `field/main_menu` 补丁字节码中的 5 处函数级拼接（与补丁作者自有改动不重叠，
   已按函数逐一取证）。上游再出新 PR 时，按同样格式在 BATTLE/MAIN_MENU 表里加块即可。
3. 每次上游补丁更新后的固定流水线：**打官方补丁 → make_portable_mods.py →
   merge_pr_items.py**，见第 4 节。两个脚本都内置无损自检，不通过即拒绝修改。

## 2. 背景与原理

### 2.1 问题

第三方「懒人补丁包.exe」是 .NET 补丁器，会**整体替换 14 个脚本的字节码**
（`game` / `title` / `mod_manager` / `hd_textures` / `field` / `battle` 等）。
补丁版 `mod_manager.gdc` 把 Mod 目录写死为常量 `user://mods`（= APPDATA），
导致拷贝到新机器后 Mod 落在 APPDATA、识别不到游戏文件夹里的 `packs/`。

### 2.2 补丁整替清单（实测 cmp_pck.py，v22 = 14 个脚本）

`game / title / mod_manager / hd_textures / fx / field/dialog / field/field /
field/field_actor / field/main_menu / field/menu_jizai / field/menu_tianshu /
field/minimap / battle/battle / battle/battle_hud`

**上游 PR 只要动这 14 个文件，运行时就会被补丁覆盖**（例：PR #15 动了 battle/main_menu，
state.gd 不在清单所以它的修复不受影响）。处理办法 = merge_pr_items.py 的函数级拼接；
拼接前先 diff 补丁版 vs 旧官方反编译，确认作者自有改动与 PR 改动函数不重叠（PR #15 已核：
battle 作者加的是物理插值/遮挡物/调试 HUD，main_menu 作者改动不涉及 PR #15 的 5 个函数）。

### 2.3 便携架构（v3 + 路线 A）

| 数据 | 机制 | 宿主是否被补丁替换 |
|---|---|---|
| 存档 / 认识度 | `state`/`fame` 脚本直接经 `Portable.path_in()` 写 `<程序目录>\userdata` | 否（补丁清单不含 state/fame/boot/portable） |
| 设置 settings.cfg | `Boot` autoload（排 `Game` 前）启动最早期 `Portable.sync_settings()` 双向同步（新者胜） | `game.gd` 被替换，但路径固定 `user://settings.cfg` 改不了 → 用同步兜底 |
| 原版音频 game_dir | `Portable.heal_game_dir()` 启动时自动把 `<程序目录>\orig` 写进设置（仅缺失/无效时） | 补丁版 game.gd 无 orig 回退逻辑 → 由 Boot 补 |
| **Mod 目录** | **路线 A：直接改补丁版 `mod_manager.gdc` 的 ROOT 为 `Portable.path_in("mods", "user://mods")`** | 是 → 所以改补丁产物本身 |
| logs / shader_cache | 留在系统目录（引擎 `_ready` 前就持有，挪不动，也无需挪） | — |

关键文件：

- `godot/scripts/portable.gd` — `class_name Portable`：root 检测（程序旁有 `orig/` 即便携）、
  `path_in()`、`sync_settings()`、`heal_game_dir()`。
- `godot/scripts/boot.gd` — autoload `Boot`，只做 `sync_settings()` + `heal_game_dir()`。
- `tools/make_portable_mods.py` — 便携 ROOT 注入（pck 提取 → 反编译 → 替换 ROOT →
  重编译 → `--pck-patch` 注回）。
- `tools/merge_pr_items.py` — 上游 PR 修复合入补丁字节码（同一流水线；当前含 PR #15 的
  5 处 battle/main_menu 拼接）。**上游新 PR 若动 2.2 清单内文件，就在这里加块**：
  `git diff origin/main..<PR>` 逐函数抄成 (旧块 → 新块)，锚点必须在补丁反编译文本中唯一。
- `tools/cmp_pck.py` — 比对两个 pck 的条目差异 = 补丁器实际替换清单（补丁换版本时先用它核对）。
- 工具链：`D:\AI\Work\test\tools-bin\gdre\`（GDRE Tools v2.7.4 / gdsdecomp）。

### 2.3 为什么无损性重要

`mod_manager.gdc` 是 GDSC 字节码（zstd 压缩，bytecode ver 101，对应 Godot 4.7.2）。
只有在「不改代码原样往返 = 字节完全一致」的前提下，替换一行后重编译的产物才可信。
实测 GDRE v2.7.4 + `--bytecode=4.7.2` 对本发行是 BYTE-IDENTICAL；
`make_portable_mods.py` 每次运行都先做这个自检，版本不匹配时直接拒绝修改，不会悄悄改坏补丁。

## 3. 已验证的事实与坑（勿重复踩）

- **Godot API**：`OS.set_user_data_dir` 不存在；`._sc_` 自包含模式对导出游戏无效；
  `use_custom_user_dir` 只接受 app_userdata 子目录名且运行时改无效；
  取 mtime 唯一可用的是 `FileAccess.get_modified_time`（静态方法）；
  `DirAccess.is_link` 对 Windows junction 返回 true（4.7.2 实测）。
- **旧 junction 方案已退役**：user:// 根目录联接 + RESTART 不可行（引擎 `_ready` 前已持有
  `user://logs`；headless 沙箱 `create_process` 子进程不执行；`--log-file` 不生效）。
  曾改用 mods 子目录 junction，路线 A 落地后彻底移除。
- **GDRE CLI 坑**：`--path` 必须空格分隔（`--path=` 拒绝）；选项值不能含反斜杠
  （脚本内统一 `replace("\\","/")`）；反编译/编译输出按 **cwd** 解析 `res://`，
  必须 `cwd=工作目录`；`--pck-patch` 注回需 `--pck-version=4 --pck-engine-version=4.4.0`
  （索引带 sha256 字段须 4.5+ 引擎写回，gdRE 内置 4.8 满足）。
- **单文件反编译检查**会出现 `Identifier not found: Game` 假象——是 autoload 单例不在
  检查上下文所致，对照组已证明与改动无关，忽略即可。
- **补丁容器格式**：懒人补丁包内嵌 `.text` 中 `[path\0 | u32 长度 | GDSC blob]`；
  补丁作者本版本只加了 skins 系统、未动路径逻辑，与本项目改动无冲突。
- 中文路径建联接需 `chcp 65001` 的 UTF-8 bat（`Portable._make_link` 仍保留该函数，
  但发行流程已不使用 junction；`portable_subdir()` 为遗留接口，boot.gd 不再调用）。
- **无损性只对「补丁版字节码」成立**：gdRE 往返对官方自编译的 .gdc 不保证字节一致
  （差异可达数万字节）。两个工具都必须跑在**打完懒人补丁的 pck** 上，顺序不可颠倒，
  也不能对着未打补丁的发行 pck 跑（自检会拒绝，这是特性不是故障）。
- **字节码明文不能用作合并特征**：新增标识符（`add_status` 等）经 zstd 前缀复用压缩后
  在明文里不可见。合并结果验证必须"重编译 → 再反编译 → 行级断言"（merge_pr_items 已内置）。
- 合并块幂等：apply_blocks 以"锚点不在且目标在"判已合并，重跑安全；作者日后若把补丁
  基于含 PR 的新 main 重编，PR_MARKS 检测到特征自动跳过对应文件。

## 4. 项目更新后的处理流程（新对话按此执行）

前提：`D:\AI\Work\test\tools-bin\gdre\`（GDRE v2.7.4）与项目 venv 的 `zstandard` 可用。
（用 `cztgodot\.venv\Scripts\python.exe` 跑，PATH 里裸 python 没有 zstandard。）

```text
① 仓库侧先合上游：git fetch origin; git merge origin/main (或对应 PR ref)；
   make win 重出 czt.exe + czt.pck（boot/portable 等源码改动走 exe/pck 正常导出）
   → 拷入 game\（回滚点只保留一份最新的 beforepatch_*）

② 对新版发行 pck 双击运行 懒人补丁包.exe（或上游给出的新补丁器）
   补丁器换新版本时先用 tools/cmp_pck.py 比对新旧 pck，核对 2.2 替换清单是否变化；
   清单扩大了（新动到上游 PR 的文件）→ 需给 merge_pr_items.py 补对应块

③ 无损自检（只验证工具链与本发行是否匹配，不写回）：
   python tools\make_portable_mods.py D:\AI\Work\test\tools-bin\gdre game\czt.pck --check
   python tools\merge_pr_items.py    D:\AI\Work\test\tools-bin\gdre game\czt.pck --check
   - 通过 → 继续 ④
   - 失败（往返字节不一致）→ 停止。说明 GDRE 版本或补丁字节码与发行不符，
     需先对齐 GDRE / --bytecode 版本，不要强行修改。

④ 注入（顺序固定：先便携 ROOT，再 PR 合并；两脚本可重复跑、幂等）：
   python tools\make_portable_mods.py D:\AI\Work\test\tools-bin\gdre game\czt.pck
   python tools\merge_pr_items.py    D:\AI\Work\test\tools-bin\gdre game\czt.pck
   - make_portable_mods 报「没找到 ROOT 行」→ 补丁结构已变：反编译 mod_manager.gdc
     核对新写法，更新 ROOT_RE/NEW_ROOT 后重跑。
   - merge_pr_items 报「锚点出现 0/多次」→ 对应 PR 的锚点函数被补丁作者动过：
     反编译该脚本人工核对，更新对应块后重跑。
   - 报「补丁已含 PR #15, 无需合并」→ 作者补丁已基于新 main，正常现象。

⑤ 内容级验证（从最终 pck 反编译回来看行）：
   PR #15 五处在 battle/main_menu、mod_manager ROOT = Portable.path_in、
   补丁作者自有特性（如 battle 的 physics_interpolation）仍在。
   （merge_pr_items 注回前已自动做过行级断言，这步是独立复核。）

⑥ 端到端验证：
   1. 删除 %APPDATA%\<游戏名>\mods（旧联接或残留）
   2. 双击 czt.exe（或无头冒烟：czt.exe --write-movie 跑 ~25s 看日志）
      → PORTABLE game_dir / MODS [...配音包...] / TITLE screen entered；无 SCRIPT ERROR
      （--write-movie 在 Windows 下报一次 "Can't find movie writer: nul" 属正常，忽略）
   3. 确认 %APPDATA%\<游戏名>\ 不再出现 mods 目录
   4. 再启动一次（幂等性）；拷贝整个 game\ 到空目录/另一台机器重复验证
   5. 游戏内核对 PR #15：地图吃状态药真解除异常状态、神兵令蓄劲+、属性药加对字段、
      装备页上限显示含装备加成
```

## 5. 判定边界

- 便携判定 = 程序（或编辑器工程上级目录）旁**存在 `orig/`**。没有 `orig/` 时
  `Portable.root == ""`，`path_in()` 返回原 `user://` 路径、Boot 全部空操作——
  与官方单机安装行为完全一致。
- 上游补丁更新本身**不需要**重新发明方案：只要 ③ 自检通过，重跑 ②④ 即可；
  自检失败或锚点匹配失败才需要人工介入（见 ③④ 的失败分支）。
- **不在 2.2 清单里的文件**（state/fame/boot/portable/dialog 之外的 field 多数脚本等）：
  上游修复经 ① 的源码合码 + make win 直接生效，无需字节码合并。
- **在清单里但没有对应合并块的 PR**：会被补丁静默覆盖。所以每次上游有合并的 PR，
  若其 diff 涉及 2.2 清单文件，就要给 merge_pr_items.py 加块（这是硬约束，不是可选项）。
