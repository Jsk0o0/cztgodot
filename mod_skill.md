# 苍之涛同人复刻 · Mod 制作指南（给 AI 用）

这份文档写给帮人做 Mod 的 AI（也适合人看）。按顺序照做，最后得到一个能放进游戏「创意工坊」的 `.pod` 文件。

所有格式都以游戏端 `godot/scripts/mod_manager.gd` 开头的注释为准。这份文档跟它不一致时，以代码为准。

---

## 0. 先弄清楚几件事

- **Mod 只有数据，不能带代码。** 能做的是：加 NPC、写剧情事件、改原版事件、加物品 / 怪物 / 战斗 / 任务 / 技能、改队员和开局、加模型、加对白配音，以及用 `tweaks.json` 加原版没有的操作和画面微调（大地图按键开菜单、滚轮调镜头、战斗伤害数字样式）。
- **事件脚本只能用原版出现过的指令**（第 5 节有完整列表）。出现一个不认识的指令，整个 Mod 拒绝加载。
- **做出来的东西分两种形态**：
  - 明文文件夹：开发、测试用，用命令行 `--mod=文件夹` 加载；
  - `.pod` 加密包：发布用，玩家放进 mod 文件夹，在工坊里启用。
- **不要往 Mod 里放原版游戏的台词、图片、模型**。原版素材有版权；Mod 只放自己写的内容，需要原版的东西就用编号引用。

---

## 1. 准备环境

| 需要 | 用途 |
|---|---|
| 本仓库 | `git clone https://github.com/Jsk0o0/cztgodot` |
| Godot 4.7 | 运行游戏、测试 Mod |
| 已提取的原版数据 `extracted/` | 按 README「素材提取」做。查坐标、模型号、物品号，以及游戏校验事件指令都要用 |
| Go 1.23+ | 编译打包工具 podtool |
| Python 3 | 生成密钥文件 |

常用数据位置（都在 `extracted/game/` 下）：

| 文件 | 内容 |
|---|---|
| `names.json` | `people` 人物号 → 名字，`items` 物品号 → 名字，`maps` 地图号 → 地图名 |
| `maps.json` | 每张地图的原版 NPC（`npcs`：角色号、`act` 模型、`pos` 坐标、`event` 对话事件）、遇敌区域 |
| `events/*.json` | 原版事件：`events` 事件号 → 代码键，`codes` 代码键 → 指令列表。写事件时照着抄格式最稳 |
| `battle.json` | `objs` 物品 / 怪物 / 技能记录，`battlefields` 战场 |
| `records.json` | 任务、图鉴等 |

城镇地图号：12201 令狐国东城、12203 曲沃城、12204 临淄城、12205 郢都、12206 雍城、12207 北狄聚落、12208 狐戎聚落、12209 晋国驿站、12210 齐国驿站、12211 楚国驿站、12212 秦国驿站。

---

## 2. 密钥

### 2.1 主密钥（公开）

正式版游戏和所有 `.pod` 用的主密钥是公开的：

```
d36258d736eaf7d61428ee81e2edf19a39c6eec80df6f49859e89bc0ed0e2306
```

在仓库根目录运行：

```sh
make pod-key      # 写出 tools/podtool/pod/masterkey.go 和 godot/scripts/pod_key.gd，内容就是上面这把
```

没有 `make` 时，运行 `python3 tools/gen_pod_key.py` 效果一样。也可以手写 `tools/podtool/pod/masterkey.go`：

```go
package pod

import "encoding/hex"

var masterKey, _ = hex.DecodeString("d36258d736eaf7d61428ee81e2edf19a39c6eec80df6f49859e89bc0ed0e2306")
```

**不要换主密钥**。用别的密钥打出来的包，正式版游戏读不了（会显示「内容密钥无效」）。

### 2.2 作者私钥（每个作者自己的，保密）

`.pod` 要用作者私钥签名。工坊里显示的「作者指纹」就来自它，玩家靠它分辨是不是同一个作者发布的。

```sh
make podtool                 # 编译 → out/podtool
out/podtool keygen           # 生成 ~/.config/czt-pod/author.pem（RSA-2048），已有就别再生成
```

私钥不要提交到任何地方，也不要发给别人。换了私钥，作者指纹就跟着变。

---

## 3. Mod 文件夹结构

```
mods/作者.名字/
  mod.json            必须
  preview.png         可选：工坊封面，建议 640×360
  maps/<地图号>.json   可选：在这张图上加 / 改 / 删 NPC，加遇敌
  events.json         可选：Mod 自己的事件（NPC 对话、剧情）
  overrides.json      可选：整段替换原版事件
  items.json          可选：自定义物品
  monsters.json       可选：自定义怪物
  battles.json        可选：自定义战斗
  quests.json         可选：任务（记载里显示）
  skills.json         可选：新技能 / 改原版技能
  characters.json     可选：改队员数值、成长、地图模型
  newgame.json        可选：改开局（金钱、物品、法术、队伍）
  models.json + models/*.glb   可选：自定义模型
  voice/<key>.ogg     可选：对白配音
  tweaks.json         可选：操作 / 画面微调（大地图开菜单的键、滚轮镜头、伤害数字样式）
  fonts/ images/      可选：tweaks.json 用到的字体、图片（路径随意，和 JSON 里写的一致即可）
```

### 3.1 mod.json

```json
{
  "id": "yourname.cheyun-gold",
  "name": "车芸的盘缠",
  "version": "1.0.0",
  "author": "yourname",
  "game": "0.1.25",
  "description": "在令狐国东城新增一位老伯，和他交谈可获得 9999 金，只能领一次。"
}
```

- `id` 写成「作者.名字」，只用英文小写、数字、`-` 和 `.`，**发布后不要改**：`@flag`、`@npc` 这些编号是按 id 的哈希分配的，改了 id，玩家存档里记录的状态就对不上了。
- `game` 写你测试时用的游戏版本。

### 3.2 符号引用（Mod 里的编号）

Mod 自己的东西用 `"@类型:N"` 写，游戏加载时换成不会和原版、别的 Mod 冲突的实际编号。原版的东西直接写数字。

| 写法 | 指什么 | N 的范围 |
|---|---|---|
| `"@npc:N"` | 本 Mod 的 NPC（角色号） | 1–255（0 号留给 Mod 变量） |
| `"@event:N"` | 本 Mod 的事件 | 1–999 |
| `"@flag:N"` | 本 Mod 的旗标（存档里的开关） | 1–999 |
| `"@item:N"` | 本 Mod 的物品 | 1–255 |
| `"@monster:N"` | 本 Mod 的怪物 | 1–255 |
| `"@battle:N"` | 本 Mod 的战斗 | 1–63 |
| `"@skill:N"` | 本 Mod 的技能 | 1–255 |
| `"@model:N"` | 本 Mod 的模型 | 1–63 |

**不要直接写原版没用过的大编号，也不要改写原版旗标**（除非你就是想改原版剧情）。Mod 的状态一律用 `@flag`。

---

## 4. 各文件格式

下面的例子都来自仓库 `mods/` 目录里能跑通的验收用例，可以直接打开参考。

### 4.1 加 NPC：`maps/<地图号>.json`

```json
{
  "npcs": [
    { "id": "@npc:1", "name": "送盘缠的老伯", "act": 114, "pose": 0, "facing": 0,
      "pos": [24300, 1501, 15450], "event": "@event:1", "ai": 0, "flags": 8224 }
  ]
}
```

- `act`：模型号。用原版模型就抄 `maps.json` 里某个原版 NPC 的 `act`（114 是普通村民）；用自定义模型写 `"@model:N"`。
- `pos`：坐标 `[x, y, z]`，y 是高度。最稳的做法：在 `maps.json` 里找同一张图上一个原版 NPC，在它的 x、z 上加减两三百，y 照抄。
- `facing`：朝向角度。
- `event`：玩家和他对话时执行的事件。
- `flags`：可以对话的普通 NPC 照抄 `8224`。
- `ai`：0 = 站着不动。

改 / 删原版 NPC（`npc_edits`），以及加遇敌（`encounters`）：

```json
{
  "npc_edits": [
    {"actor": 2009, "remove": true},
    {"actor": 2011, "name": "猪肉西施", "pos": [22573, 1501, 17476]},
    {"actor": 2005, "event": "@event:1"}
  ],
  "encounters": [{"battle": "@battle:1", "weight": 20, "zones": []}],
  "npcs": []
}
```

- `npc_edits` 只改写出来的那几项，其他（包括 NPC 的出现条件）照旧。
- `encounters`：`weight` 取 1–20；`zones` 写遇敌区域序号，空着表示全部区域。只能加到原版本来就有遇敌的地图上。

### 4.2 事件：`events.json` / `overrides.json`

格式和原版 `extracted/game/events/*.json` 的 `codes` 一样：

```json
{ "1": [ [位置, "指令", 参数...], ... ] }
```

- **位置**：从小到大的整数，不要求连续。跳转指令的「目标」写的是位置值，不是第几条。习惯上每条加 2–40。
- 每个事件最后要有 `["end"]`；对话事件的结构是 `script_begin … script_end, end`。
- `overrides.json` 的键是**原版事件号**，内容整段替换原版那个事件。多个 Mod 改同一个事件时，后加载的生效。

#### 模板 A：NPC 说话，只给一次奖励

```json
{
  "1": [
    [0, "if_flag_goto", "@flag:1", 200],
    [8, "script_begin"],
    [10, "set_flag", 8080],
    [14, "reset_move_speed"],
    [16, "set_pose", 1, 0],
    [22, "set_caption", "@npc:1"],
    [26, "window_color", 150, 10, 10, 10],
    [36, "text", "@npc:1", 0, 0, 0, 0, 0, 6, 0, 0, 8192, "姑娘辛苦了，这点盘缠拿去吧！"],
    [80, "wait_text", "@npc:1"],
    [84, "set_caption", 1],
    [88, "window_color", 150, 10, 10, 10],
    [98, "text", 1, 0, 0, 0, 0, 0, 6, 0, 0, 8192, "多谢老伯！"],
    [130, "wait_text", 1],
    [134, "play_sound", 527],
    [138, "add_money", 9999],
    [142, "text", 65281, 0, 320, 240, 320, 240, 0, 0, 1, 16384, "%C0%S0%S0得到【%C099999 金%C0】"],
    [180, "wait_text", 65281],
    [184, "set_flag", "@flag:1"],
    [188, "clear_flag", 8080],
    [192, "script_end"],
    [194, "end"],
    [200, "script_begin"],
    [202, "set_flag", 8080],
    [206, "set_caption", "@npc:1"],
    [210, "window_color", 150, 10, 10, 10],
    [220, "text", "@npc:1", 0, 0, 0, 0, 0, 6, 0, 0, 8192, "钱已经给过你啦，路上小心。"],
    [260, "wait_text", "@npc:1"],
    [264, "clear_flag", 8080],
    [268, "script_end"],
    [270, "end"]
  ]
}
```

要点：

- `set_flag 8080` / `clear_flag 8080`：旗标 8080 打开时不画鼠标光标。原版每个对话事件都是开头打开、结尾关掉，照着写就行。漏了也不会卡住，事件结束时游戏会自动清掉。
- `reset_move_speed` + `set_pose 1, 0`：让主角（角色 1）停下站好。
- `set_caption 角色号`：对话框上显示谁在说话（显示该角色号的名字）。
- `text` 后面接 `wait_text 同一个角色号`，等玩家翻页。

#### `text` 指令

`["text", 角色号, 9 个数字参数, "台词"]`。9 个数字参数决定对话框的位置和样式，**直接照抄下面两种**：

| 用途 | 写法 |
|---|---|
| 角色头顶的对话框（谁说话就写谁的角色号；1 = 车芸） | `"text", 角色号, 0, 0, 0, 0, 0, 6, 0, 0, 8192, "台词"` |
| 屏幕中间的系统提示（得到物品等） | `"text", 65281, 0, 320, 240, 320, 240, 0, 0, 1, 16384, "提示"` |

台词里的控制码：

| 控制码 | 作用 |
|---|---|
| `%C<数字>` | 换文字颜色：`%C0` 白，`%C5` 米色（名字），`%C9` 橙色（物品、重点），共 0–10 |
| `%S<数字>` | 打字速度 |
| `%N` | 换行 |
| `%P` | 分页 |
| `%B文字.` | 选项（用 `.` 结尾），配合 `menu_switch` |
| `%T物品号.` | 显示物品名 |

#### 模板 B：选项分支

```json
[40, "text", "@npc:1", 0, 0, 0, 0, 0, 6, 0, 0, 8192, "要不要帮我？%N%B帮忙. %B不帮."],
[44, "wait_text", "@npc:1"],
[48, "menu_switch", [60, 100]],
[60, "...选「帮忙」走这里..."],
[100, "...选「不帮」走这里..."]
```

`menu_switch [目标1, 目标2, …]` 按玩家选了第几个选项，跳到对应的位置。

#### 常用指令

| 指令 | 参数 | 说明 |
|---|---|---|
| `if_flag_goto` | 旗标, 目标 | 旗标开着就跳 |
| `if_not_flag_goto` | 旗标, 目标 | 旗标没开就跳 |
| `set_flag` / `clear_flag` | 旗标 | 打开 / 关闭旗标 |
| `goto` | 目标 | 无条件跳 |
| `give_item` | 物品号, 数量 | 给物品 |
| `take_item` | 物品号, 数量 | 拿走物品 |
| `if_item_goto` | 物品号, 数量, 目标 | 有这么多就跳 |
| `add_money` | 金额（可为负） | 加 / 减钱 |
| `if_money_ge_goto` | 金额, 目标 | 钱够就跳 |
| `play_sound` | 音效号 | 527 = 得到东西 |
| `open_shop` | [物品号…] | 打开商店，Mod 物品写 `"@item:N"` |
| `start_battle` | 战场号 | 开战（Mod 战斗写 `"@battle:N"`） |
| `set_actor_var` / `add_actor_var` | 角色号, 变量号, 值 | 角色变量；Mod 自己的变量用 `"@npc:0"` |
| `if_actor_var_ge_goto` / `if_actor_var_eq_goto` | 角色号, 变量号, 值, 目标 | 变量 ≥ / = 值就跳 |
| `random_goto` | [目标…] | 随机跳到其中一个 |
| `call_event` | 事件号 | 执行另一个事件 |
| `wait` | 时长 | 等待 |
| `set_pose` | 角色号, 动作号 | 播动作（0 待机，4 行走…） |
| `hide_actor` / `show_actor` | 角色号 | 隐藏 / 显示角色 |

其他指令（镜头、移动、换图、淡入淡出……）见第 5 节的完整列表。参数含义不确定时，在 `extracted/game/events/*.json` 里搜这个指令，**照原版的用法抄**，不要猜。

### 4.3 物品：`items.json`

```json
{"1": {"base": 3001, "name": "熊掌蜜饯", "desc": "熊掌柜秘制的蜜饯，吃了恢复一半生命。", "price": 80,
       "fx1": [10050, 0, 0, 0, 0, 0]}}
```

- 复制原版物品 `base` 的整条记录（分类、图标、使用演出、可用场合……），只改 `name`、`desc`、`price`、`fx1`（6 个数）、`fx2`（7 个数）。
- `fx1[0]` 是生命恢复量，`fx1[1]` 是体力，`fx2[0]` 是灵力。数值编码：
  - ≤ 10000：定值；
  - 10001–10099：百分比（10050 = 50%，≥ 10099 = 全满）；
  - \> 20000：上限的倍数。
- 发给玩家用事件里的 `give_item "@item:1" 数量`，或者 `open_shop`。

### 4.4 怪物、战斗、遇敌

`monsters.json`：复制原版怪物 `base`（模型、动作、技能、AI、抗性照抄），只改数值。

```json
{"1": {"base": 1017, "name": "山贼熊", "desc": "跟着强盗混饭吃的熊。", "level": 12, "hp": 600, "mp": 320, "sp": 340,
       "atk": 360, "def": 180, "spd": 110, "matk": 220, "mdef": 260, "hit": 90, "eva": 0, "mhit": 90, "meva": 0,
       "exp": 120, "money": 150, "drop": [100, 3001], "counter": 1}}
```

- `drop`：[掉落几率 %, 物品号]。
- `counter`：可选，被打倒时 Mod 变量 N 加 1，事件里用 `if_actor_var_ge_goto "@npc:0" N 次数 目标` 判断。
- Mod 怪物不能被收化。

`battles.json`：复制原版战场 `base`（场景、镜头、音乐），只换敌人。`at` 是原版战场里第几个敌人的站位。

```json
{"1": {"base": 74, "enemies": [{"at": 0, "monster": "@monster:1"}, {"at": 1, "monster": 1034}]}}
```

只能选普通战场作 `base`（战斗脚本只有音乐 / 先手 / 回合的那种），剧情战不行，会加载失败。事件里用 `start_battle "@battle:1"` 开打；要随机遇敌，见 4.1 的 `encounters`。

### 4.5 任务：`quests.json`

```json
{"1": {"text": "☆带 3 株草药给熊掌柜", "accept": "@flag:901", "done": "@flag:951"}}
```

`★` 表示主线，`☆` 表示支线，写在文字开头。`accept` 旗标打开、`done` 旗标还没开：任务在记载里显示为「未完成」；`done` 也打开了：显示为「已完成」。这两个旗标在事件里用 `set_flag` 打开。只能用本 Mod 的 `@flag`。

### 4.6 技能：`skills.json`

```json
{"1": {"base": 6401, "name": "恨心诀·改", "desc": "更强的恨心诀。", "power": 4600,
       "cost": {"hp": 0, "sp": 30, "mp": 0, "juji": 0}},
 "6701": {"power": 5000}}
```

- 键是数字：新技能，复制 `base` 来改。只能复制分类为攻击 201、恢复 202、辅助 203、绝技 305 的技能。
- 键是原版技能号、不写 `base`：直接改原版这个技能。
- 让队员学会：用 `characters.json` 成长表第 13 列（升到这一级时学会），或 `newgame.json` 的 `skills`（开局就会），都可以写 `"@skill:N"`。

### 4.7 队员和开局：`characters.json` / `newgame.json`

```json
{"1": {"name": "车芸", "hp": 300, "atk": 40,
       "growth": [[1, 0,0,0,0,0,0,0,0,0,0,0,0, 0], [2, 41,14,18,17,9,9,13,0,0,0,0,2, 0]],
       "map_act": "@model:1"}}
```

- 队员号：1 车芸、2 嬴诗、3 桓远之。
- `growth` 每一行：[等级, HP, MP, SP, 攻, 防, 仙攻, 仙防, 命中, 回避, 仙命中, 仙回避, 速度, 习得法术]，表示升到这一级时各项加多少。
- `map_act`：车芸在地图上用的模型。

```json
{"money": 5000, "items": [3001, 3001, 3005], "party": [1, 2], "skills": {"2": [6401, "@skill:1"]}}
```

`newgame.json` 只对新开的游戏生效，读档进来的不受影响。

### 4.8 自定义模型：`models.json` + `models/*.glb`

```json
{"1": {"name": "木头人", "file": "models/muren.glb", "scale": 1.0, "yaw": 0, "ground": 0,
       "poses": {"0": {"clip": "idle", "loop": true, "ticks": 35}, "4": {"clip": "walk", "loop": true, "ticks": 35}}}}
```

- 只接受 `.glb`，每个不超过 20MB。
- `poses` 的键是原版动作号（0 待机、4 行走……），`clip` 是 glb 里的动画名，`ticks` 按每秒 35 帧计。
- NPC 的 `act` 写 `"@model:1"` 就会用这个模型。
- 怪物也能换战斗模型：在 `monsters.json` 里加 `"model": "@model:N"` 和 `"poses": {"动作号": "动画名"}`。

### 4.9 对白配音：`voice/<key>.ogg`

- `key` = 剧本里这句 `text` 指令的台词原文（包括 `%C`、`%N` 这些控制码），按 UTF-8 算 MD5，取十六进制的前 16 位。
- 文件是 Ogg Vorbis，建议单声道。
- 配音包一次只能启用一个。生成工具见 `tools/gen_voice.py`。

### 4.10 操作和画面微调：`tweaks.json`

原版没有、但玩家想要的小改动，用这个文件做。三节都可选，只写需要的那节。**没有任何 Mod 写这些时，游戏和原版完全一样。**

```json
{
  "field_menu": {"keys": ["Escape"], "page": "status"},
  "camera": {"wheel": "pitch", "pitch_step": 2, "pitch_min": 5, "pitch_max": 75},
  "damage_numbers": {
    "font": "fonts/brush.ttf",
    "size": 44,
    "outline_size": 3,
    "color": "#141010",
    "outline_color": "#f2e8d0cc",
    "splash": "images/ink.png",
    "splash_color": "#00000055",
    "kinds": {
      "hp":   {"color": "#f6eedd", "outline_color": "#20000099", "splash_color": "#9a1212e0"},
      "heal": {"prefix": "+", "color": "#f6eedd", "splash_color": "#1d4f7ae0"},
      "mp": {}, "sp": {}, "money": {}
    },
    "anim": {"duration": 1.4, "scale_from": 2.4, "scale_time": 0.12, "stagger": 0.05, "bounce": 0, "tilt": 7, "rise": 16}
  }
}
```

**`field_menu`：大地图上用别的键打开主菜单**（原版只有 Enter 和点右上角卷轴）

| 字段 | 说明 |
|---|---|
| `keys` | 键名列表，写法同 Godot 的键名：`"Escape"`、`"F1"`、`"Q"`、`"Backspace"`…… 按着 Shift / Ctrl / Alt 时不算（原版的 Shift+Esc 不受影响） |
| `page` | 打开后直接到哪一页：`status`（默认，和点卷轴一样）/ `item` / `equip` / `qishu` / `jiguan` / `tianshu` / `jizai` / `system` |

- 事件、对话进行中不会打开。菜单里按 Esc 照原版一层层退出，不会关了又马上打开。

**`camera`：大地图上用鼠标滚轮调镜头**（原版滚轮不动镜头，只能左右转）

| 字段 | 默认 | 说明 |
|---|---|---|
| `wheel` | `"pitch"` | `pitch` 调俯仰角 / `distance` 调远近 / `both` 两个一起 |
| `invert` | `false` | 默认往上滚 = 俯仰角变小（镜头放低）、拉近；`true` 反过来 |
| `pitch_step` / `pitch_min` / `pitch_max` | 2 / 5 / 75 | 每格改几度、范围（−89 到 89） |
| `dist_step` / `dist_min` / `dist_max` | 100 / 800 / 4000 | 每格改多少、范围（原版地图镜头距离多在 1000–2000） |

- 事件中、菜单开着、禁止转镜头的地图上，滚轮没作用。
- 当前值已经超出范围时（有的地图原版镜头就在范围外），只会往范围里走，不会一下子跳到边界。
- 按 Tab（原版的「镜头回正」）时，俯仰角和距离也回到滚动之前。

**`damage_numbers`：战斗里飘出来的数字换成自己的样式**（例如水墨毛笔字）

- 管伤害 `hp`、回复生命 `heal`、灵力 `mp`、体力 `sp`、金钱 `money` 这五种。「失误」「无效」和宣告死亡的倒数照旧用原版图。
- 字形二选一：
  - `font`：Mod 里的字体文件（ttf / otf / ttc）。**字体要能随 Mod 发布**，比如 Google Fonts 上 OFL 协议的毛笔字体 Ma Shan Zheng（马善政楷书）、Zhi Mang Xing（行书）、Liu Jian Mao Cao（草书），协议文件一起放进 Mod。Windows、macOS 自带的字体不能放。
  - `digits`：自己画的数字图（png），一行 10 格依次是 0–9，每格一样宽；用白色画，颜色由 `color` 决定。用数字图时 `prefix` 不显示。
- 字体和图片每个不超过 8MB。

| 字段 | 默认 | 说明 |
|---|---|---|
| `size` | 36 | 字高（按 800×600 画面算） |
| `spacing` | 0 | 字间距，可以是负数 |
| `outline_size` | 0 | 描边粗细（只对字体有效） |
| `color` / `outline_color` | 白 / 黑 | 颜色写 `#rrggbb` 或 `#rrggbbaa` |
| `prefix` | 无 | 数字前面加的字，例如 `"+"`、`"-"`，最多 4 个字 |
| `splash` | 无 | 数字后面的墨迹底图（png，白色画，按 `splash_color` 着色） |
| `splash_color` / `splash_scale` | 白 / 1.4 | 墨迹颜色；墨迹宽度是整串数字宽的几倍 |
| `kinds` | — | 按类型改上面的 `color` / `outline_color` / `prefix` / `splash` / `splash_color` / `splash_scale`。**写了 `kinds` 就只换列出的类型**（例如只写 `hp`，回复数字仍是原版图）；想全换又不改颜色就写成 `"mp": {}`。不写 `kinds` 则五种全换 |
| `anim` | 见下 | 动画参数 |

`anim`（时间单位为秒，都要写非负数字）：

| 字段 | 默认 | 说明 |
|---|---|---|
| `duration` | 1.2 | 一共显示多久（0.2–5），原版 1.2 |
| `fade` | 0.4 | 最后多少秒淡出 |
| `rise` / `rise_time` | 30 / 0.3 | 往上飘多少像素、飘多久 |
| `scale_from` / `scale_time` | 1.0 / 0.15 | 每个字从几倍大缩到 1 倍、用多久。设成 2 以上就是「落笔砸下来」的效果 |
| `stagger` | 0.04 | 后一个字比前一个晚出现多久 |
| `bounce` | 8 | 出现时往上弹几像素（0 = 不弹，原版会弹） |
| `tilt` | 0 | 每个字随机倾斜的最大角度（度），手写感 |
| `splash_time` | 0.2 | 墨迹从 60% 大小晕开到全尺寸用多久 |

**通用规则**

- 写了不认识的项或值不对（例如 `"wheel": "spin"`、颜色写错、文件不存在），整个 Mod 拒绝加载，工坊里显示原因。
- 多个 Mod 都写了同一节（例如都有 `camera`），加载顺序靠后的那个整节生效，控制台记一条冲突。不同节可以来自不同 Mod。
- 这些设置在 Mod 启用后生效，游戏的「设定」里没有对应开关；不想要就在工坊里停用这个 Mod。
- 例子：仓库里的 `mods/t1-tweaks`（Esc 打开系统页、滚轮同时调俯仰和远近、数字图 + 墨迹），验收测试 `make test-mod-t1`。

---

## 5. 事件指令完整列表

只有这些指令能用（数据来自原版全部事件）。参数个数和例子都取自原版；含义不确定的，去 `extracted/game/events/*.json` 里搜同名指令，看原版怎么用。

| 指令 | 参数个数 | 原版用了几次 | 原版里的一个例子 (参数部分) |
|---|---|---|---|
| `text` | 11 | 16662 | （台词 / 文件名，见正文） |
| `window_color` | 4 | 16536 | `[1, 0, 0, 0]` |
| `text_char_spacing` | 1 | 16496 | `[3]` |
| `text_line_spacing` | 1 | 16496 | `[5]` |
| `wait_text` | 1 | 16362 | `[1]` |
| `set_pose` | 2 | 13017 | `[1, 0]` |
| `end` | 0 | 4780 | `[]` |
| `clear_flag` | 1 | 4551 | `[15]` |
| `reset_move_speed` | 0 | 3887 | `[]` |
| `set_flag` | 1 | 3881 | `[8080]` |
| `set_expression` | 3 | 3664 | `[1, 10001, 5]` |
| `script_begin` | 0 | 3636 | `[]` |
| `script_end` | 0 | 3622 | `[]` |
| `play_sound` | 1 | 3227 | `[527]` |
| `if_flag_goto` | 2 | 3148 | `[38, 6177]` |
| `wait_anim` | 2 | 3136 | `[1, 0]` |
| `set_caption` | 1 | 3135 | `[27]` |
| `camera_control` | 1 | 3015 | `[1]` |
| `goto` | 1 | 2954 | `[4070]` |
| `camera_mode` | 1 | 2691 | `[1]` |
| `camera_angle` | 4 | 2545 | `[30, 0, 0, 0]` |
| `camera_distance` | 1 | 2541 | `[1700]` |
| `fade` | 6 | 2396 | `[10, 0, 0, 0, 0, 255]` |
| `camera_target` | 3 | 2373 | `[1110, 355, 915]` |
| `hide_actor` | 1 | 2201 | `[101]` |
| `set_facing` | 3 | 1824 | `[1, 90, 0]` |
| `if_near_actor_goto` | 3 | 1652 | `[506, 150, 100]` |
| `camera_zoom` | 3 | 1574 | `[1, 0, 10]` |
| `look_at` | 3 | 1426 | `[1, 27, 0]` |
| `wait` | 1 | 1317 | `[100]` |
| `if_actor_var_ge_goto` | 4 | 1265 | `[101, 1, 3, 376]` |
| `place_actor` | 4 | 912 | `[1, 983, 305, 1112]` |
| `nop` | 0 | 896 | `[]` |
| `add_actor_var` | 3 | 873 | `[176, 1, 1]` |
| `add_wood` | 1 | 825 | `[3]` |
| `show_actor` | 1 | 807 | `[101]` |
| `give_item` | 2 | 799 | `[5508, 1]` |
| `set_trigger` | 2 | 778 | `[12, 0]` |
| `cutscene_begin` | 0 | 759 | `[]` |
| `cutscene_end` | 0 | 733 | `[]` |
| `add_metal` | 1 | 619 | `[20]` |
| `camera_angle_speed` | 1 | 617 | `[100]` |
| `camera_distance_speed` | 1 | 612 | `[25]` |
| `camera_target_speed` | 1 | 607 | `[500]` |
| `place_actor_map` | 5 | 598 | `[101, 12201, 20551, 1501, 15426]` |
| `wait_move` | 1 | 583 | `[1]` |
| `camera_nowait` | 0 | 511 | `[]` |
| `add_money` | 1 | 466 | `[-800]` |
| `change_map` | 6 | 422 | `[12623, 13248, 3192, 14461, 0, 20000]` |
| `set_actor_event` | 2 | 354 | `[101, 31]` |
| `random_goto` | 1 | 339 | `[[78, 235]]` |
| `walk_to` | 4 | 316 | `[1, 1138, 236, 870]` |
| `move_to_follow_cam` | 5 | 308 | `[1, 5749, 1268, 4759, 100]` |
| `camera_restore` | 0 | 215 | `[]` |
| `add_coal` | 1 | 209 | `[50]` |
| `heal_member` | 4 | 199 | `[2, 9999, 9999, 9999]` |
| `menu_switch` | 1 | 190 | `[[7863, 13803]]` |
| `camera_target_actor` | 3 | 164 | `[1, 1, 100]` |
| `set_act` | 2 | 154 | `[1, 187]` |
| `add_ani_on_actor` | 3 | 126 | `[2461, 8140, 1]` |
| `set_weapon_model` | 4 | 120 | `[1, 5521, 1, 1]` |
| `set_0073_mode` | 0 | 115 | `[]` |
| `play_music` | 5 | 114 | `[16, 0, 16, 0, 2]` |
| `set_collision` | 2 | 112 | `[1, 0]` |
| `set_floor` | 1 | 108 | `[4]` |
| `camera_batch_begin` | 0 | 107 | `[]` |
| `camera_batch_end` | 0 | 107 | `[]` |
| `set_actor_flag_80` | 2 | 104 | `[2, 0]` |
| `take_item` | 2 | 94 | `[5501, 1]` |
| `set_self_flag_66d` | 1 | 90 | `[1]` |
| `start_battle` | 1 | 86 | `[245]` |
| `wait_camera` | 0 | 84 | `[]` |
| `call_event` | 1 | 79 | `[10]` |
| `if_all_flags_goto` | 2 | 78 | `[[1308, 1309], 330]` |
| `del_ani_wait` | 2 | 70 | `[8140, 0]` |
| `if_item_goto` | 3 | 53 | `[3301, 1, 582]` |
| `set_actor_ai` | 2 | 50 | `[2021, 0]` |
| `music_control` | 1 | 46 | `[1]` |
| `open_save_menu` | 0 | 44 | `[]` |
| `set_music_fade` | 1 | 42 | `[50]` |
| `if_money_ge_goto` | 2 | 40 | `[800, 552]` |
| `if_not_flag_goto` | 2 | 40 | `[7075, 1702]` |
| `set_actor_flag_1a8` | 1 | 39 | `[2461]` |
| `if_actor_var_eq_goto` | 4 | 39 | `[176, 1, 6, 692]` |
| `clear_actor_flag3` | 1 | 38 | `[11]` |
| `del_ani` | 2 | 37 | `[9200, 1]` |
| `add_ani` | 5 | 36 | `[9200, 1, 0, 0, 0]` |
| `fade_actor_alpha` | 4 | 36 | `[30, 0, 200, 10]` |
| `open_shop` | 1 | 35 | `[[4002, 4003, 4302, 4602, 4901, 4902]]` |
| `set_move_speed` | 1 | 34 | `[3]` |
| `narration_mode` | 1 | 33 | `[1]` |
| `set_map_music` | 5 | 29 | `[12604, 22, 0, 22, 0]` |
| `wait_actor_fade` | 1 | 29 | `[30]` |
| `wait_turn` | 1 | 27 | `[18]` |
| `camera_wait` | 0 | 25 | `[]` |
| `crossfade_speed` | 1 | 24 | `[60]` |
| `set_anim_speed` | 2 | 21 | `[28, 6]` |
| `play_video` | 1 | 20 | （台词 / 文件名，见正文） |
| `set_actor_flag3` | 1 | 20 | `[2]` |
| `set_actor_flag_1000` | 2 | 20 | `[11, 1]` |
| `add_ani_move` | 9 | 20 | `[18054, 5670, 17085, 18054, 5670, 17085, 0, 8177, 0]` |
| `screen_shake` | 1 | 18 | `[1]` |
| `wait_crossfade` | 0 | 18 | `[]` |
| `camera_type` | 1 | 17 | `[1]` |
| `actor_path_to` | 7 | 15 | `[1, 14151, 3291, 16954, 203, 45, 0]` |
| `set_actor_var` | 3 | 14 | `[101, 1, 2]` |
| `wait_ani` | 2 | 10 | `[8130, 0]` |
| `free_models` | 0 | 8 | `[]` |
| `if_has_monster_goto` | 2 | 7 | `[1051, 774]` |
| `add_tech_points` | 1 | 6 | `[100]` |
| `if_any_flag_goto` | 2 | 6 | `[[5901, 5902], 5761]` |
| `set_event_active` | 1 | 6 | `[1]` |
| `weather_effect` | 1 | 5 | `[1]` |
| `set_ghost_move` | 2 | 3 | `[716, 0]` |
| `learn_skill` | 2 | 3 | `[3, 6712]` |
| `add_member_magic_def` | 2 | 3 | `[0, -1]` |
| `if_monster_room_goto` | 1 | 3 | `[3214]` |
| `add_monster` | 1 | 3 | `[1001]` |
| `return_to_title` | 0 | 2 | `[]` |
| `add_actor_effect` | 3 | 2 | `[2463, 9007, 10]` |
| `remove_actor_effect` | 3 | 2 | `[2463, 9007, 10]` |
| `reset_frame_rate` | 0 | 1 | `[]` |
| `replace_item` | 2 | 1 | `[4101, 4115]` |
| `game_clear_save` | 0 | 1 | `[]` |
| `data` | 1 | 1 | `[1705]` |
| `set_registry_swdonline` | 0 | 1 | `[]` |
| `sub_money` | 1 | 1 | `[5000]` |
| `set_battle_countdown` | 8 | 1 | `[20, 12606, 0, 0, 0, 0, 0, 0]` |

---

## 6. 测试

用明文文件夹直接在游戏里加载（命令行加载的 Mod 总是启用）：

```sh
godot --path godot -- --mod=/绝对路径/mods/yourname.cheyun-gold
```

- 加载失败时，控制台会打印 `MOD <id>: 原因`，比如「事件 1 有不认识的指令 …」「模型 1 不是 .glb」；工坊里这个 Mod 也会显示「无法加载」和原因。
- 加载成功时，控制台打印 `MODS ["yourname.cheyun-gold 1.0.0"]`。
- 进游戏走到 NPC 那里对话，把每条分支都走一遍；领奖类的要确认只能领一次；存档、读档后状态还在。
- 仓库自带的验收测试可以照着改：`make test-mod-m1` 等（见 Makefile）。

自查清单：

- [ ] `mod.json` 的 `id` 唯一，格式是「作者.名字」
- [ ] 每个 `@event` 都在 `events.json` 里定义了；每个 NPC 的 `event` 都指向存在的事件
- [ ] 每个事件以 `end` 结尾；所有跳转目标都是存在的位置
- [ ] 对话事件开头 `set_flag 8080`，结尾 `clear_flag 8080`（照原版写法）
- [ ] 每个 `text` 后面都有 `wait_text 同一角色号`
- [ ] 只用了第 5 节里的指令
- [ ] 没有放原版素材和原版台词

---

## 7. 打包成 .pod

```sh
make pod-key                 # 第 2.1 节，只需一次
make podtool                 # → out/podtool
out/podtool keygen           # 第 2.2 节，只需一次（已有私钥就跳过）
out/podtool pack mods/yourname.cheyun-gold "out/车芸的盘缠.pod"
out/podtool info "out/车芸的盘缠.pod"    # 校验：能列出文件就说明主密钥、签名都对
```

- `pack` 会读 `mod.json` 的 `id`，把整个文件夹加密、签名。
- 不在 macOS 上编译时，`make podtool` 里的 `codesign` 那一步可以去掉，直接 `cd tools/podtool && go build -o ../../out/podtool ./cmd/podtool`。

**发布前在游戏里装一遍**：把 `.pod` 放进游戏的 mod 文件夹（标题画面 → 创意工坊 → 打开 mod 文件夹），回工坊点「刷新」→ 选中 → 启用 → 重启游戏，确认能用。

---

## 8. 也可以用工坊编辑器

不想手写 JSON 的话，仓库里有可视化编辑器（`make editor-run`），可以在地图上摆 NPC，用积木写事件，最后直接导出 `.pod`。编辑器的工程文件是 Mod 里的 `editor.json`，游戏不读它。

编辑器还不能编辑 `tweaks.json`：手写好放进 Mod 文件夹，编辑器导出 `.pod` 时会一起打包。
