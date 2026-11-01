# 轩辕剑外传·苍之涛 同人复刻（Godot）

非官方、非商业的同人复刻项目，用 Godot 4 重新实现《轩辕剑外传·苍之涛》，并提供素材提取工具、创意工坊（Mod）和工坊编辑器。

> **本仓库不含任何原版素材。** 运行前必须自备正版游戏，再用本仓库的工具从中提取素材。
> 《轩辕剑外传·苍之涛》的全部角色、美术、音乐、剧情等版权归大宇资讯股份有限公司所有。本项目与大宇资讯、软星科技无关。
> 请勿公开分发提取出的素材或打好的素材包（`.pck`），也不要用于商业用途。

## 目录

- [平台状态](#平台状态)
- [仓库结构](#仓库结构)
- [环境要求](#环境要求)
- [快速开始](#快速开始)
- [工具用法](#工具用法)
- [导出素材包（pck）](#导出素材包pck)
- [Windows 打包](#windows-打包)
- [Android 打包](#android-打包)
- [iOS 打包](#ios-打包)
- [创意工坊（Mod）](#创意工坊mod)
- [测试](#测试)
- [许可证](#许可证)

## 平台状态

| 平台 | 状态 | 说明 |
|---|---|---|
| macOS | 可开发运行 | 主要开发环境，通过 `make start` 运行 |
| Windows | 可导出 | `make win` 导出；已有导出预设 |
| Android | **未适配** | 没有导出预设，也没有触屏操作，详见 [Android 打包](#android-打包) |
| iOS | **未适配** | 同上，详见 [iOS 打包](#ios-打包) |

画面保持原版 4:3 比例。

## 仓库结构

```text
godot/    Godot 工程（scenes/ 场景，scripts/ 游戏代码，data/ 随程序分发的少量非原版数据）
tools/    素材提取、脚本反汇编、分包工具（Python），podtool（Go）
editor/   工坊编辑器（Go + Wails + React + shadcn/ui）
mods/     Mod 示例和验收用例
docs/     素材产出与文件格式说明
Makefile  全部命令入口，运行 make help 查看
```

## 环境要求

| 工具 | 用途 | 是否必需 |
|---|---|---|
| [Godot 4.7.2](https://godotengine.org/) 和同版本导出模板 | 运行、导出 | 必需 |
| Python 3 | 素材提取，首次运行时自动创建 `.venv` | 必需 |
| 正版《轩辕剑外传·苍之涛》 | 素材来源（开发时用 v1.04），目录只读，工具不会写入 | 必需 |
| ffmpeg、ffmpeg2theora | 过场视频转码（`make video`） | 需要过场动画时 |
| [Real-ESRGAN ncnn Vulkan](https://github.com/xinntao/Real-ESRGAN) | 生成 2K / 4K 素材（`make hd` / `make hd4`） | 可选 |
| Go 1.23+、Wails v2、Node.js | 构建 podtool 和工坊编辑器 | 做 Mod 时 |

Makefile 里的 `GAME`、`GODOT` 默认值是开发机的路径，换机器时要在命令行指定（也可以写成环境变量后加 `make -e`）：

```sh
make GAME="/path/to/轩辕剑4外传苍之涛" GODOT="/path/to/godot" help
```

`make` 需要类 Unix 环境，Windows 上请用 WSL 或 Git Bash；`make editor`、`make podtool` 用到的 `codesign` 只有 macOS 才有，其他系统需要去掉这一步。

## 快速开始

```sh
# 1. 克隆仓库
git clone git@github.com:Jsk0o0/cztgodot.git && cd cztgodot

# 2. 配置素材路径
cp godot/local_paths.cfg.example godot/local_paths.cfg
# 编辑 godot/local_paths.cfg，填入 game_dir（游戏目录）和 extracted_dir（提取目录）

# 3. 提取全部素材（下面以 GAME、GODOT 已在命令行或环境中指定为例）
make all game-data effects video

# 4. 启动游戏
make start          # 按游戏设置选择画质
make start HD=1     # 使用高清素材（需先 make hd）
make start HD=0     # 使用标清素材
```

每个提取目标都会检查依赖，只重做比脚本或上游数据旧的部分，可以放心重复运行。

## 工具用法

运行 `make help` 可查看全部命令，常用命令如下。

### 素材提取

| 命令 | 作用 | 输出 |
|---|---|---|
| `make all` | 全部提取：`assets` + `data` + `scripts` | `extracted/` |
| `make assets` | 贴图、界面、模型、场景 | `extracted/textures`、`ui`、`models`、`scenes` |
| `make data` | 文本、关卡、数值、音乐表 | `extracted/text`、`levels`、`stats` |
| `make scripts` | 事件 / 战斗脚本反汇编、伪代码、AI 翻译 | `extracted/scripts` |
| `make game-data` | 生成 Godot 正式游戏要读的数据 | `extracted/game` |
| `make effects` | 技能特效 | `extracted/effects` |
| `make video` | 过场视频 Bink → Theora | `extracted/video` |
| `make hd` | Real-ESRGAN ×2 放大素材，用 `ESRGAN=` 指定程序路径 | `extracted_hd/` |
| `make hd4` | 在 2K 基础上再 ×2 成 4K（先 `make hd`） | `extracted_4k/` |
| `make hd-video` | 过场视频 ×2，很慢，约为片长的 6 倍 | `extracted_hd/video` |
| `make validate` | 用官方 glTF Validator 检查全部 GLB | — |

提取结果的结构和原版文件格式见 [docs/formats.md](docs/formats.md)。

### 查看与调试

| 命令 | 作用 |
|---|---|
| `make story` / `make story-open` | 生成 / 打开本地剧情文本浏览页（含原版文本，请勿分发） |
| `make preview` | 技能观看器，用战斗引擎施放全部技能 |
| `make godot-shot SHOT=out.png` | 标题画面截图 |
| `make autoplay` | 自动通关测试，日志在 `out/autoplay.log` |

单个模型的命令：

```sh
python tools/ply2gltf.py "$GAME" out.glb CHR00001 CHR00002   # 同网格的多个文件合并为多条动画
python tools/render_preview.py "$GAME" out.png CHR00001      # 快速预览
blender --python tools/blender_load_level.py -- extracted/levels/12201.json  # 在 Blender 里打开关卡
```

## 导出素材包（pck）

发行版不要求玩家提取素材，而是把提取结果预先打成 `.pck`。**这些包含有原版素材，只能自用，不要公开分发。**

### 步骤

```sh
# 1. 准备素材：缺哪一项，游戏里对应的内容就缺失
make all game-data effects video

# 2A. 只打标清包
make packs HD2=0

# 2B. 标清 + 2K（默认，先 make hd，过场动画另需 make hd-video）
make hd
make packs

# 2C. 标清 + 2K + 4K（再先 make hd4）
make hd4
make packs HD4=1
```

产物在 `out/packs/`，可用 `PACKS=目录` 改位置：

| 文件 | 内容 | 参考大小 |
|---|---|---|
| `common.pck` | 多章共用的素材，必需 | 约 2.0 GB |
| `ch01.pck` … `ch10.pck` | 各章节素材，全部必需 | 合计约 1.2 GB |
| `hd2.pck` | 2K 覆盖包，可选，必须和标清包同时存在 | 约 2.1 GB |
| `hd4.pck` | 4K 覆盖包，可选，必须和标清包同时存在 | 约 4.2 GB |

### 说明

- 启动时游戏读取**程序同目录下的 `packs/`**，有 `common.pck` 才会加载，然后加载目录里全部 `.pck`。
- 2K 和 4K 包同时存在时用 4K。高清包只含放大的图片、视频和模型贴图，不含网格。
- `tools/pack_plan.py` 负责分包规划。章节归属只决定文件落在哪个包；统计不到的文件归入 `common.pck`，不影响运行。规划用到 `out/ap/` 的自动通关日志，没有日志时章节包会变小、公共包变大。
- 开发机上测试发行版：

```sh
"$GODOT" --path godot -- --packs=/绝对路径/out/packs
```

## Windows 打包

Windows 是目前唯一配置了导出预设的平台，可以在 macOS 上交叉导出。

1. 安装 Godot 4.7.2 的导出模板（编辑器菜单「编辑器 → 管理导出模板」）。
2. 按上一节生成素材包。
3. 运行：

```sh
make win
```

输出到 `out/win/`：

```text
czt.exe      主程序
czt.pck      游戏代码和数据
packs/       素材包（硬链接自 out/packs）
说明.txt     玩家说明（来自 tools/win_readme.txt）
```

`czt.exe`、`czt.pck` 和 `packs/` 必须放在同一目录。4K 包不放进 `out/win/packs/`，而是输出到 `out/hd4.pck`，单独分发。

`make win` 等价于下面的命令，加上复制素材包和说明的步骤：

```sh
"$GODOT" --headless --path godot --export-release "Windows Desktop" ../out/win/czt.exe
```

存档、设置和 Mod 在 `%APPDATA%\Godot\app_userdata\轩辕剑外传·苍之涛 同人复刻（非官方）\`。

## Android 打包

> **当前状态：未适配，也未实测。** 下面的步骤基于 Godot 官方导出流程，可以打出安装包，但在完成下方的适配之前，装好后进不了游戏。

### 需要先完成的适配

1. **素材包路径**：`godot/scripts/game.gd` 的 `_load_packs()` 从程序同目录读 `packs/`，移动端沙盒没有这个目录。需要改成读 `user://`，并提供把素材包放进去的方法（首次运行下载，或在应用内导入）。
2. **触屏操作**：游戏目前只支持键鼠和手柄，没有虚拟摇杆和触屏按钮；Godot 默认把触摸当作鼠标点击，但不够完成全部操作。
3. **体积**：标清素材约 3.2 GB，不适合直接放进安装包。
4. **性能**：没有在移动 GPU 上测试过。游戏已有自动降画质，能否够用还不清楚。

### 打包步骤

1. 安装 Godot 4.7.2 导出模板、JDK 17 和 Android SDK，并在「编辑器设置 → 导出 → Android」填写 Java SDK 和 Android SDK 路径。
2. 在「项目设置 → 渲染 → 纹理 → VRAM 压缩」打开 **Import ETC2 ASTC**，然后重新导入工程。
3. 打开「项目 → 导出 → 添加 → Android」，将预设命名为 `Android`，并配置：
   - **包名**：填写自己的包名，例如 `com.example.czt`。
   - **架构**：勾选 `arm64-v8a`。
   - **资源页**：与 Windows 预设保持一致，包含 `data/*`，排除 `local_paths.cfg, tests/*, scripts/tests/*, scripts/extract/tests/*, scripts/tools/*`。
4. 生成发布用签名密钥（不要提交到仓库）：

```sh
keytool -genkeypair -v -keystore czt-release.keystore -alias czt \
  -keyalg RSA -keysize 2048 -validity 10000
```

5. 通过环境变量提供签名信息并导出：

```sh
export GODOT_ANDROID_KEYSTORE_RELEASE_PATH=/绝对路径/czt-release.keystore
export GODOT_ANDROID_KEYSTORE_RELEASE_USER=czt
export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=你的密码

mkdir -p out/android
"$GODOT" --headless --path godot --export-release "Android" ../out/android/czt.apk
```

调试时可以改用 `--export-debug`，安装用 `adb install out/android/czt.apk`。

## iOS 打包

> **当前状态：未适配，也未实测。** 需要先完成 [Android 一节列出的适配](#需要先完成的适配)，其中素材包路径、触屏操作和体积问题同样存在。

iOS 只能在 macOS 上打包，需要 Xcode 和 Apple 开发者账号。

1. 安装 Godot 4.7.2 导出模板和 Xcode。
2. 在「项目设置 → 渲染 → 纹理 → VRAM 压缩」打开 **Import ETC2 ASTC**。
3. 打开「项目 → 导出 → 添加 → iOS」，将预设命名为 `iOS`，并配置：
   - **App Store Team ID**：填写 Apple 开发者团队 ID。
   - **Bundle Identifier**：填写自己的标识，例如 `com.example.czt`。
   - **资源页**：与 Windows 预设保持一致。
4. 导出 Xcode 工程：

```sh
mkdir -p out/ios
"$GODOT" --headless --path godot --export-release "iOS" ../out/ios/czt.ipa
```

5. 在预设里打开 `application/export_project_only` 时只生成 Xcode 工程，用 Xcode 打开 `out/ios/czt.xcodeproj`，选择签名团队后真机运行或归档。

## 创意工坊（Mod）

Mod 有两种形式：

- **明文文件夹**：含 `mod.json`，用于开发，通过 `--mod=文件夹` 加载或放进 `user://mods/`。
- **`.pod` 加密包**：用于发布，放进 `user://mods/` 后在游戏「工坊」里启用。

### 主密钥

`.pod` 的主密钥不在仓库里，首次构建前需要生成：

```sh
make pod-key
```

这条命令生成 `tools/podtool/pod/masterkey.go` 和 `godot/scripts/pod_key.gd`，两个文件都被 Git 忽略；`make podtool`、`make editor` 会自动调用它。

因此，**自己编译的游戏和工具只能互相读取，无法读取别的构建打出的 `.pod`**。没有主密钥时游戏可以正常运行，只是读不了 `.pod`。

### podtool

```sh
make podtool
out/podtool keygen                                  # 生成作者私钥，默认 ~/.config/czt-pod/author.pem
out/podtool pack mods/cheyun-gold out/gold.pod      # 打包并签名
out/podtool info out/gold.pod                       # 校验并列出内容
```

作者私钥决定 Mod 的作者身份，请妥善保管，不要提交到仓库。

### 工坊编辑器

可视化编辑地图、NPC、事件、物品、任务、怪物和战斗，并打包 `.pod`。

```sh
make editor        # 构建到 editor/build/bin/
make editor-run    # 构建并启动
make editor-test   # 后端测试
```

## 测试

下面的验收命令需要先提取素材，结果输出 `PASS` / `FAIL`：

```sh
make test-pad        # 手柄
make test-minimap    # 小地图
make test-mod-m1     # 工坊验收，另有 m6、m7、m8、m10、e2、e4
```

`make test-mod-m9` 依赖第三方模型，这个模型不随仓库分发，克隆后无法运行。

## 许可证

本仓库的源代码采用 [PolyForm Noncommercial License 1.0.0](LICENSE)：可以学习、修改和分发，但不得用于商业用途。

- 这个许可证只覆盖本仓库的源代码，**不授予原版游戏及其素材的任何权利**。
- `godot/data/text/` 的简繁转换词表来自 [OpenCC](https://github.com/BYVoid/OpenCC)（Apache-2.0），声明见 `OPENCC_NOTICE.txt`。
- 其余第三方依赖遵循各自的许可证，见 `editor/go.mod`、`editor/frontend/package.json`。
