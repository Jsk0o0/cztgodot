# 便携 Mod 路径方案（补丁产物改路径）—— 项目更新后的处理指南

> 适用场景：上游发行包 / 「懒人补丁包.exe」更新后，需要重新让 `game\` 满足
> "整个文件夹拷到任意机器、双击 `czt.exe` 即用"（存档 / Mod / 设置 / 音频目录全便携，
> 不依赖 APPDATA、不使用目录联接）。
> **项目更新后在新对话中处理本问题时，直接按第 4 节流程执行即可。**

---

## 1. 结论（TL;DR）

- Mod 目录便携**不再用 mklink 目录联接**，而是**直接修改补丁产物里的字节码**：
  用 GDRE Tools 把补丁版 `mod_manager.gdc` 反编译，将
  `const ROOT := "user://mods"` 替换为
  `var ROOT: String = Portable.path_in("mods", "user://mods")`，
  重编译后注回 `czt.pck`。便携时 Mod 走引擎原生路径 `<程序目录>\userdata\mods`。
- 一键工具：`tools/make_portable_mods.py`（已进仓库），内置**无损自检**
  （不改代码原样往返必须与原 `.gdc` 字节一致，不通过就拒绝修改）。
- 每次上游补丁更新后的固定流水线：**打官方补丁 → 跑 make_portable_mods.py**，见第 4 节。

## 2. 背景与原理

### 2.1 问题

第三方「懒人补丁包.exe」是 .NET 补丁器，会**整体替换 14 个脚本的字节码**
（`game` / `title` / `mod_manager` / `hd_textures` / `field` / `battle` 等）。
补丁版 `mod_manager.gdc` 把 Mod 目录写死为常量 `user://mods`（= APPDATA），
导致拷贝到新机器后 Mod 落在 APPDATA、识别不到游戏文件夹里的 `packs/`。

### 2.2 便携架构（v3 + 路线 A）

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
- `tools/make_portable_mods.py` — 本方案核心工具（pck 提取 → 反编译 → 替换 ROOT →
  重编译 → `--pck-patch` 注回）。
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

## 4. 项目更新后的处理流程（新对话按此执行）

前提：`D:\AI\Work\test\tools-bin\gdre\`（GDRE v2.7.4）与项目 venv 的 `zstandard` 可用。

```text
① 备份当前 pck（唯一回滚点，勿留多份）：
   copy game\czt.pck  game\czt.pck.beforepatch_<日期>

② 对新版发行 pck 双击运行 懒人补丁包.exe（或上游给出的新补丁器）

③ 无损自检（只验证工具链与本发行是否匹配，不写回）：
   python tools\make_portable_mods.py D:\AI\Work\test\tools-bin\gdre game\czt.pck --check
   - 通过 → 继续 ④
   - 失败（往返字节不一致）→ 停止。说明 GDRE 版本或补丁字节码与发行不符，
     需先对齐 GDRE / --bytecode 版本，不要强行修改。

④ 正式注入（ROOT → Portable.path_in）：
   python tools\make_portable_mods.py D:\AI\Work\test\tools-bin\gdre game\czt.pck
   - 若报「没找到 ROOT = "user://mods" 行」→ 上游补丁结构已变：
     手工反编译 mod_manager.gdc 核对新写法，更新脚本里的 ROOT_RE/NEW_ROOT 后重跑。

⑤ 确认 game\ 内其余便携件在位（它们不被补丁替换，一般无需动）：
   czt.exe / packs\ / orig\ / userdata\ ；boot 与 Portable 类编译在 exe 侧，
   若本项目仓库有更新则重新 make win 出 exe。

⑥ 端到端验证：
   1. 删除 %APPDATA%\<游戏名>\mods（旧联接或残留）
   2. 双击 czt.exe → MODS 应直接从 game\userdata\mods 加载配音包
   3. 确认 %APPDATA%\<游戏名>\ 不再出现 mods 目录；控制台无 SCRIPT ERROR
   4. 再启动一次（幂等性）；拷贝整个 game\ 到空目录/另一台机器重复验证
```

## 5. 判定边界

- 便携判定 = 程序（或编辑器工程上级目录）旁**存在 `orig/`**。没有 `orig/` 时
  `Portable.root == ""`，`path_in()` 返回原 `user://` 路径、Boot 全部空操作——
  与官方单机安装行为完全一致。
- 上游补丁更新本身**不需要**重新发明方案：只要 ③ 自检通过，重跑 ②④ 即可；
  自检失败或 ROOT 行匹配失败才需要人工介入（见 ③④ 的失败分支）。
