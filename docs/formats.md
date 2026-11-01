# 资源提取：产出与格式说明


## 命令（Makefile）
```sh
make help          # 列出所有命令
make all           # 全部提取：贴图、界面、模型、场景、文本、关卡、数值、脚本
make assets        # 只做美术：textures ui models scenes
make data          # 只做数据：text scene-map levels stats music
make scripts       # 只做脚本：disasm pseudo ai
make validate      # 用官方 glTF Validator 检查全部 GLB
make start         # 启动游戏 (Godot 同人复刻原型; 缺少的素材会先自动提取)
make GAME=/其他/路径/轩辕剑4外传苍之涛 all   # 游戏目录在别处时
```
- 首次运行会自动创建 `.venv` 并安装依赖（`make setup`）。
- 每个目标都会检查依赖：只重做比工具脚本或上游数据旧的部分。例如改了 `tools/decompile_ai.py` 之后，`make scripts` 只会重跑 AI 翻译。
- 依赖顺序：`text` → `scene-map` → `levels`；`text` → `music`；`text` + `music` + `stats` → `disasm`；`stats` → `ai`。
- `make video` 把 VIDEO/*.bik 转成 Godot 能播放的 .ogv，需要带 libtheora 的 ffmpeg。
- 单个模型：`tools/ply2gltf.py "$G" out.glb CHR00001 CHR00002 …`（同网格的多个文件 = 多条动画）
- 快速预览：`tools/render_preview.py "$G" out.png CHR00001`
- 在 Blender 里打开关卡（场景 + 触发区）：`blender --python tools/blender_load_level.py -- extracted/levels/12201.json`

## 产出
| 目录 | 内容 |
|---|---|
| `extracted/textures/<类别>/ALLxxxxx.png` | 4266 张贴图，透明贴图为 RGBA |
| `extracted/effects/` | 战斗技能特效（`make effects`）：`effects.json` 记录招式里用到的全部特效组合（ACT 特效脚本逐帧轨道、事件、粒子发射器），`models/` 是 MGC 特效模型 GLB，`*.morph.json` 是逐帧顶点和 UV 变形，`sprites/` 是精灵帧。详见 `tools/effects.py` 的文档说明 |
| `extracted/preview/` | 技能图鉴：`skills.json`（主角技能 → ATK 动作序列）和每个角色的 GLB（同一网格的全部动作），供 Godot 技能预览场景使用（`make preview-data`） |
| `extracted/ui/<tsw>/<条目号>_<名字>/<帧>.png` | ACT/*.tsw 2D 图库：标题画面、界面、立绘表情、图标等，共 292 项、2678 帧（4 帧解码失败）；`index.json` 是条目索引 |
| `extracted/models/<类别>/*.glb` | 1055 个模型（由 5947 个 PLY 合并），带贴图、骨骼、全部动作，以及逐帧顶点变形（morph target）；`models_index.json` 记录每个 GLB 由哪些 PLY 组成 |
| `extracted/scenes/MAPxxxxx.glb` | 166 个场景，分为三个子节点：`_scene` 主体，`_backdrop` 天空穹顶/远景，`_fx` 加法混合光效。会动的物体（共 1530 个：移动/旋转、旗帜水波变形、流水 UV 滚动）单独成 `objN_texM` 节点，动画合并为一条和场景同名的动画；`*.markers.json` 记录无贴图的标记物位置 |
| `extracted/scene_map.json` | 128 张关卡地图 ↔ 场景模型的配对和坐标偏移，含置信度 |
| `extracted/levels/<map_id>.json` | 每张地图的传送区、事件区、触发点，已换算到世界坐标和 glTF 坐标；传送区附目标地图 |
| `extracted/stats/` | 角色 4、怪物 177、道具 128、装备 158、法术 413、建筑 26，等级成长表、经验表、法宝修练表；JSON 和 CSV（UTF-8 BOM，可直接用 Excel 打开）；字段说明和证据见该目录的 `README.md` |
| `extracted/story/` | **剧情 / 文本浏览页**（`make story`，`make story-open` 直接打开）：本地 HTML，按章节列出全部事件的台词、旁白、选项和条件分支，并标注场景、战斗、任务；另有按地图归类的 NPC 对话、任务与史料、战斗对白、图鉴和全文搜索。原版没有章节编号，章节按事件编号与地区划分；NPC 所在地图来自 MAPS.DAT 段 2 的 NPC 摆放表。**页面含原版全部文本，仅供本机查阅，不要分发** |
| `extracted_hd/` | **高清素材**（`make hd`，需要 Real-ESRGAN 的 `realesrgan-ncnn-vulkan`，路径用 `ESRGAN=` 指定）：用 `realesr-animevideov3` 模型放大 2 倍界面图、特效精灵图，以及场景 / 角色 / 特效 / 技能预览 GLB 里的贴图（不透明贴图改存 JPEG 质量 92），约 1.5 GB，处理约 2 分钟（Apple M3 Max）。`make start HD=1` 用高清、`HD=0` 用普通，不写时按游戏「設定」里的「高清素材」开关；高清图按原尺寸排版，高清目录里没有的文件自动用原版 |
| `extracted/scripts/` | 指令语义全部来自 exe 解释器逆向。`pseudo/` 是 1787 条事件脚本的结构化伪代码（if/switch/random、台词、任务、音乐都带名字）；`talks*/` 是逐条反汇编；`battle/FIGTALK`、`battle/ATK` 是战斗剧情 / 招式脚本反汇编；`battle/AI` 是 AI 的人话翻译；`opcodes.md` 是全部指令表；`events_index.json` 可以从地图触发区查到对应脚本。说明见该目录的 `README.md` |
| `extracted/text/` | 对白（简体）、任务、物件/怪物、地图连接图、战场和敌人配置；格式说明见该目录的 `README.md` |

所有 GLB 都已通过官方 glTF Validator（0 错误）。

## 格式要点
- **压缩**：PLY 和 TEX 是 `[u32 解压大小][u32 压缩大小][LZO1X]`；WLD 的这个头在 0x94，解压结果和逻辑文件偏移一一对应
- **ACT**（动作表）：`all_char.act` 里每个 ACT 是一个角色（战斗中 ACT 号 = ObjDATA 编号，例如嬴诗 1、桓远之 2、云狐 10）；每个动作带 `FR` 模型编号，类别 = 编号 ÷ 3000（0 CHR / 1 ITM / 2 MGC），文件 = 前缀 + 编号 mod 3000。详见 `tools/act.py`
- **TSW**（2D 图库）：44 字节一条的条目表（名字 Big5）；每个条目先是 36 字节一条的帧表，每帧数据是 LZO1X 压缩的 TEX 图像。详见 `tools/tsw2png.py`
- **TEX**：`FFFF, w, h, flags`，之后逐行 RLE（`0x8000` 表示行首是不透明段，`0xC000|n` 表示跳过 n 个透明像素），像素为 RGB555。详见 `tools/tex2png.py`
- **PLY**：段表（刚性蒙皮）+ 40 字节顶点 + u16 索引 + 材质组（贴图 ID → `Tex/<类别>/ALL{id:05}.TEX`，flags bit0 = 加法混合）+ 每帧每段的 4×4 绝对矩阵 + 每帧顶点变形。详见 `tools/ply.py`
- **WLD**：对象表；每个对象带贴图 ID、40 字节顶点、索引、每帧 3×4 矩阵、可选的逐帧顶点变形，flags bit0 = 加法混合。详见 `tools/wld.py`
- **MAP ↔ WLD**：`MAP.world_size` 等于 WLD 头部包围盒跨度；世界坐标 = MAP 坐标 + 包围盒最小角
- **文本**：Big5 编码，存放在 GLL022 偏移表里
- **坐标系**：所有导出（PLY/WLD → glTF、特效、关卡坐标）都保留游戏原始坐标，没有做轴转换。原版是 D3D 左手系，在右手系引擎里直接渲染会得到左右镜像的画面；Godot 技能预览把 3D 画面水平翻转后显示，与原版一致（战场上我方在 −Z 一侧面朝 +Z）
- **UV**：PLY/WLD 的 v 坐标多为负数，要原样使用（D3D 在 wrap 寻址下取小数部分：v=−0.22 → 0.78）。如果取反（−v），每张贴图都会上下颠倒，例如嬴诗的脸会采到头发区域而发黑
- **法线**：原数据存的法线约 30% 指向模型内侧，三角形绕序则 85% 以上朝外。导出时按几何重新计算平滑法线（`ply2gltf.geometric_normals`）
- **动画通道**：每条动画都写全部骨骼的通道（不变的只写 1 个关键帧）。Godot 等引擎切换动画时不会把骨骼复位，缺通道的骨骼会停在上一条动画的姿势上
- **骨骼动画**：PLY 的每帧矩阵大多带镜像（行列式 < 0）。导出时对这些部件把顶点 X 取反，矩阵右乘 diag(−1,1,1) 抵消，骨骼上只剩旋转和正缩放；最终顶点位置不变（逐帧对比误差 < 0.002 游戏单位）

## 已知限制
- 加法混合在 glTF 里用「alpha = 亮度 + BLEND」近似，引擎里可以改成真正的 additive 材质
- 模型和场景的 UV 变形（流水、贴图滚动）写在 morph target 的 TEXCOORD_0 里：符合 glTF 规范，但 Blender 导入时会忽略，位置变形和变换动画正常
- `extracted/models/` 里每个 PLY 按原始帧顺序、20fps 导出（估算值）。原版实际是按 ACT 播放表（`AP` 帧号序列）以 35 帧/秒播放，会跳帧、取子区间；`extracted/preview/` 里的角色 GLB 已经按播放表导出（`pose_<动作号>`，35fps）
- MAP ↔ WLD 配对是推断的（游戏 exe 加了壳，没找到权威映射表）。67 个唯一匹配，其余靠几何和名称打分；同尺寸的商店、民房可能配到相同布局的其他城市版本
- 脚本：事件 1786/1787、FIGTALK 283/283、ATK 754/754、AI 297/297 完整解析，剩下那 1 条是原数据残缺。所有操作码都对应到了 exe 里的处理函数；其中一部分标为 P（看得出写了哪个字段，具体用途是推断），详见 `extracted/scripts/README.md`
- 任务没有专门指令，而是用旗标表示：接取 = 任务 ID，完成 = 任务 ID + 256。背景音乐指令是事件指令 `0x90`
- 数值表里还有部分字段未确认（成长表第 5、6 列哪个是防御哪个是仙攻、两种属性的名称等），详见 `extracted/stats/README.md`。随机遇敌表还没找到

`godot/` 是 Godot 4 同人复刻原型，目前做了按原版还原的标题画面，说明见 `godot/README.md`。

> 素材版权归大宇/软星所有。本工具仅用于学习研究和二创参考。
