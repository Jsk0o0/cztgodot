# 轩辕剑外传·苍之涛 资源提取 / 同人复刻
# 用法: make help
# 游戏目录只读, 绝不修改。换机器时: make GAME=/path/to/轩辕剑4外传苍之涛 ...

GAME   ?= /Volumes/Users/kingsearch/Desktop/czt/轩辕剑4外传苍之涛
OUT    ?= extracted
GODOT  ?= /Applications/Godot-stable.app/Contents/MacOS/Godot
ESRGAN ?= $(HOME)/Downloads/realesrgan-ncnn-vulkan-20220424-macos/realesrgan-ncnn-vulkan
HD_OUT ?= $(OUT)_hd
UHD_OUT ?= $(OUT)_4k
# make start HD=1 用高清素材, HD=0 用普通素材; 不写则按游戏里的设置 (默认普通)
HD     ?=
HD_ARG := $(if $(filter 1,$(HD)),--hd,$(if $(filter 0,$(HD)),--sd,))
VENV   := .venv
PY     := $(VENV)/bin/python -I
T      := tools

# 产物的「代表文件」: 存在且比依赖新就不重做
TEXTURES := $(OUT)/textures/.done
UI       := $(OUT)/ui/index.json
MODELS   := $(OUT)/models/models_index.json
SCENES   := $(OUT)/scenes/.done
TEXT     := $(OUT)/text/maps.json
SCENEMAP := $(OUT)/scene_map.json
LEVELS   := $(OUT)/levels/levels_index.json
STATS    := $(OUT)/stats/monsters.json
MUSIC    := $(OUT)/text/music.json
SCRIPTS  := $(OUT)/scripts/coverage.json
PSEUDO   := $(OUT)/scripts/pseudo/.done
AI       := $(OUT)/scripts/battle/AI/.done
VIDEOS   := $(OUT)/video/.done
PREVIEW  := $(OUT)/preview/skills.json
EFFECTS  := $(OUT)/effects/effects.json
STORY    := $(OUT)/story/index.html
VALIDATOR := $(T)/validate/node_modules/.package-lock.json

.DEFAULT_GOAL := help
.PHONY: win-lite help setup all assets data scripts textures ui models scenes text scene-map levels stats music \
        disasm pseudo ai game-data story story-open autoplay demo-video hd hd-video video validate start preview preview-data effects godot godot-import godot-shot check-game check-godot clean clean-godot

help: ## 显示所有命令
	@echo "游戏目录: $(GAME)"
	@echo "输出目录: $(OUT)"
	@echo
	@grep -E '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  make %-13s %s\n", $$1, $$2}'

# ---------------- 环境 ----------------

setup: $(VENV)/.ok ## 创建 Python 虚拟环境并安装依赖

$(VENV)/.ok:
	python3 -m venv $(VENV)
	$(VENV)/bin/pip install -q pillow numpy opencc-python-reimplemented
	@touch $@

check-game:
	@test -d "$(GAME)/Model" || { echo "找不到游戏目录: $(GAME)  (用 make GAME=... 指定)"; exit 1; }

# ---------------- 总目标 ----------------

all: assets data scripts ## 全部提取 (贴图、界面、模型、场景、文本、关卡、数值、脚本)

assets: textures ui models scenes ## 美术: 贴图 + 2D 界面 + 模型 + 场景

data: text scene-map levels stats music ## 数据: 文本、关卡、数值、音乐表

scripts: disasm pseudo ai ## 脚本: 反汇编 + 伪代码 + AI 人话

# ---------------- 美术 ----------------

textures: $(TEXTURES) ## 贴图 → PNG (~30s)
$(TEXTURES): $(T)/tex2png.py $(T)/lzo1x.py | setup check-game
	$(PY) $(T)/tex2png.py "$(GAME)" $(OUT)/textures
	@touch $@

ui: $(UI) ## ACT/*.tsw 2D 界面/立绘/图标 → PNG (~30s)
$(UI): $(T)/tsw2png.py $(T)/tex2png.py | setup check-game
	$(PY) $(T)/tsw2png.py "$(GAME)" $(OUT)/ui

models: $(MODELS) ## 角色/道具/法术模型 → GLB (~2min)
$(MODELS): $(T)/batch_export.py $(T)/ply2gltf.py $(T)/ply.py | setup check-game
	$(PY) $(T)/batch_export.py "$(GAME)" $(OUT)/models

scenes: $(SCENES) ## 场景 WLD → GLB (~20s)
$(SCENES): $(T)/wld2gltf.py $(T)/wld.py $(T)/ply2gltf.py $(T)/scene_anim.py | setup check-game
	$(PY) $(T)/wld2gltf.py "$(GAME)" $(OUT)/scenes
	@touch $@

# ---------------- 数据 ----------------

text: $(TEXT) ## 对白、任务、物件、地图、战场 → JSON/简体文本
$(TEXT): $(T)/extract_text.py | setup check-game
	$(PY) $(T)/extract_text.py "$(GAME)" $(OUT)/text

scene-map: $(SCENEMAP) ## 关卡地图 ↔ 场景模型配对
$(SCENEMAP): $(T)/match_scenes.py $(TEXT)
	$(PY) $(T)/match_scenes.py "$(GAME)" $(OUT)/text/maps.json $(OUT)/text/wld_models.json $@

levels: $(LEVELS) ## 每张地图的触发区 (世界坐标 / glTF 坐标)
$(LEVELS): $(T)/build_levels.py $(SCENEMAP) $(TEXT)
	$(PY) $(T)/build_levels.py $(OUT)/text/maps.json $(SCENEMAP) $(OUT)/text/map_graph.json $(OUT)/levels

stats: $(STATS) ## 角色/怪物/道具/装备/法术数值表
$(STATS): $(T)/extract_stats.py | setup check-game
	$(PY) $(T)/extract_stats.py "$(GAME)" $(OUT)/stats

music: $(MUSIC) ## 曲目 ID → 文件名, 地图默认音乐
$(MUSIC): $(T)/extract_music.py $(TEXT)
	$(PY) $(T)/extract_music.py "$(GAME)" $@

# ---------------- 脚本 ----------------

disasm: $(SCRIPTS) ## 事件/FIGTALK/ATK 脚本反汇编 + 指令表 opcodes.md
$(SCRIPTS): $(T)/disasm_script.py $(T)/battle_vm.json $(TEXT) $(MUSIC) $(STATS)
	$(PY) $(T)/disasm_script.py "$(GAME)" $(OUT)/scripts

pseudo: $(PSEUDO) ## 事件脚本 → 结构化伪代码
$(PSEUDO): $(T)/decompile_script.py $(T)/disasm_script.py $(TEXT) $(MUSIC)
	$(PY) $(T)/decompile_script.py "$(GAME)" $(OUT)/scripts/pseudo
	@touch $@

ai: $(AI) ## 战斗 AI → 人话
$(AI): $(T)/decompile_ai.py $(STATS)
	$(PY) $(T)/decompile_ai.py "$(GAME)" $(OUT)/scripts/battle/AI
	@touch $@

game-data: $(TEXT) $(STATS) $(SCRIPTS) $(PREVIEW) ## Godot 正式游戏的数据: 事件脚本 / 地图 / 碰撞 / 战斗 (战场、数值、招式、AI、战斗剧情) / 序章角色模型 / 战斗特效
	$(PY) $(T)/export_game.py "$(GAME)" $(OUT)
	$(PY) $(T)/export_battle.py "$(GAME)" $(OUT)
	$(PY) $(T)/game_lists.py $(OUT)
	$(PY) $(T)/export_records.py "$(GAME)" $(OUT)
	$(PY) $(T)/export_tianshu.py "$(GAME)" $(OUT)
	$(PY) $(T)/export_actors.py "$(GAME)" $(OUT)/game/actors --list $(OUT)/game/actors_needed.txt
	$(PY) $(T)/export_held.py "$(GAME)" $(OUT)
	$(PY) $(T)/export_faces.py "$(GAME)" $(OUT)
	$(PY) $(T)/export_ui_acts.py "$(GAME)" $(OUT)
	$(PY) $(T)/export_minimap.py "$(GAME)" $(OUT)
	$(PY) $(T)/effects.py "$(GAME)" $(OUT)/effects --skills $(OUT)/preview/skills.json,$(OUT)/game/battle_fx_src.json,$(OUT)/game/field_fx_src.json --extra 7042:0-1,8139:0-7,8117:0 --particles 2095,2023

story: $(STORY) ## 剧情 / 文本浏览页 (本地 HTML, 按章节、NPC、任务、战斗对白、图鉴整理; 含原版文本, 请勿分发)
$(STORY): $(T)/story_html.py $(wildcard $(T)/story_assets/*) $(PSEUDO) $(SCRIPTS) $(STATS) $(TEXT)
	$(PY) $(T)/story_html.py $(OUT) $(OUT)/story --game "$(GAME)"

story-open: $(STORY) ## 生成并用浏览器打开剧情浏览页
	open $(STORY)

autoplay: ## 自动通关测试: 机器人从新游戏一路触发剧情直到到达第二段曲沃城, 日志 out/autoplay.log (AP DONE / AP STUCK)
	@mkdir -p out
	cd godot && "$(GODOT)" --headless --path . res://scenes/field.tscn -- --sd --autoplay --speed=4 --auto-battle --auto-advance=0.05 --no-encounter --ap-limit=3600 > ../out/autoplay.log 2>&1; \
	  grep -E "^AP .*(PROGRESS|DONE|STUCK|LIMIT)|SCRIPT ERROR|AP BATTLE" ../out/autoplay.log | tail -40

.PHONY: test-boss-hp test-item-use test-pad test-minimap packs win editor editor-run editor-test podtool pod-key test-mod-m1 test-mod-m6 test-mod-m7 test-mod-m8 test-mod-m9 test-mod-m10 test-mod-e2 test-mod-e4
pod-key: ## 生成 .pod 主密钥的本地副本 (不进仓库; 已有 masterkey.go 时沿用, 只补游戏端)
	python3 -I $(T)/gen_pod_key.py

EXTRACTOR_SRC ?= /Volumes/Users/kingsearch/Desktop/cztextractor
extractor-src: ## 同步提取程序源码到 Windows 打包目录 $(EXTRACTOR_SRC) (那边双击 build.bat → czt_extract.zip); 不含密钥 / 发布脚本
	@mkdir -p "$(EXTRACTOR_SRC)/tools" "$(EXTRACTOR_SRC)/godot/data/title_glyphs"
	@rm -f "$(EXTRACTOR_SRC)"/tools/*.py
	@for f in $(T)/*.py; do case "$$(basename $$f)" in gen_pod_key.py|gen_cnb_key.py|release.py|test_update_e2e.py) ;; *) cp "$$f" "$(EXTRACTOR_SRC)/tools/";; esac; done
	cp $(T)/battle_vm.json $(T)/extractor.spec "$(EXTRACTOR_SRC)/tools/"
	cp godot/data/title_glyphs/masks.bin "$(EXTRACTOR_SRC)/godot/data/title_glyphs/"
	cp $(T)/extractor_build/build.ps1 $(T)/extractor_build/build.bat $(T)/extractor_build/说明.txt "$(EXTRACTOR_SRC)/"
	@echo "已同步到 $(EXTRACTOR_SRC) ($$(ls "$(EXTRACTOR_SRC)/tools" | wc -l | tr -d ' ') 个文件)"

cnb-key: ## 生成游戏内置的 CNB 只读令牌 godot/scripts/cnb_read_key.gd (自动更新用; 取 .cnbkey 的 swd-read 段, 不进仓库, 不打印)
	python3 -I $(T)/gen_cnb_key.py

test-update: ## 自动更新: 替换程序 (AU) + 端到端 (UE, 本地 http 模拟 CNB, 测试密钥; 不碰 CNB)
	.venv/bin/python $(T)/test_apply_update.py | grep -E "^AU (FAIL|PASS)"
	.venv/bin/python $(T)/test_update_e2e.py "$(GODOT)" | grep -E "^UE (FAIL|PASS)"

editor: pod-key ## 构建工坊编辑器 (Go + Wails + shadcn/ui) → editor/build/bin/苍之涛工坊编辑器.app (外部链接 + ad-hoc 签名, 原因同 podtool)
	cd editor && wails build -ldflags "-linkmode=external" && codesign -s - --deep -f "build/bin/苍之涛工坊编辑器.app"

editor-run: editor ## 构建并启动工坊编辑器
	open "editor/build/bin/苍之涛工坊编辑器.app"

editor-test: pod-key ## 编辑器后端测试 (事件积木编译、校验、存取); EDITOR_M1_OUT=目录 时把 M1 工程存下来给游戏端验收
	cd editor && go test -ldflags=-linkmode=external . ./internal/...

podtool: pod-key ## 构建 .pod 打包工具 → out/podtool (Go 1.22.4 在新 macOS 上要外部链接 + ad-hoc 签名, 否则缺 LC_UUID 被拒绝运行)
	@mkdir -p out
	cd tools/podtool && go build -ldflags=-linkmode=external -o ../../out/podtool ./cmd/podtool && codesign -s - -f ../../out/podtool

test-pad: ## 手柄验收: 用模拟的手柄事件走一遍地图 / 菜单 / 镜头 → PAD PASS / FAIL
	"$(GODOT)" --path godot res://scenes/field.tscn -- --bg --map=12609 --pos=20997,1448,17745 --no-encounter --pad-test 2>&1 | grep -E "^  (ok|FAIL)|^PAD"

test-minimap: ## 小地图验收: 三态、按钮、拖动、楼层、事件中隐藏、存档字段 → MINIMAP PASS / FAIL
	"$(GODOT)" --path godot res://scenes/field.tscn -- --bg --map=12606 --pos=5912,7843,8029 --no-encounter --ts-init --minimap-test 2>&1 | grep -E "^  (ok|FAIL)|^MINIMAP"

test-mod-m1: ## 创意工坊 M1 验收: 加载 mods/cheyun-gold, 令狐国东城老伯对话给 9999 金 (只一次, 存档保持) → M1 PASS / FAIL
	cd godot && "$(GODOT)" --headless --path . res://scenes/field.tscn -- --mod=../mods/cheyun-gold --map=12201 --sd --auto-advance=0.05 --mod-m1-test 2>&1 | grep -E "^M1 (ok|FAIL|PASS)"

test-boss-hp: ## 魔王生命上限按无符号 16 位读 (0x403b36 movzx; 睚眦 42000 / 最终桓远之 64800 等 22 个, 以前被截成 1) → BOSSHP PASS / FAIL
	$(GODOT) --headless --path godot -s res://scripts/tests/boss_hp_test.gd 2>&1 | grep -E "^BOSSHP"

test-hidden-spot: ## 隐藏调查点: 令狐国古井 2060 (开局隐藏, 乞丐说出秘密后 show_actor) 调查 21 次得一百钱、再 11 次得恩居图一 → HS PASS / FAIL
	cd godot && "$(GODOT)" --headless --path . res://scenes/field.tscn -- --map=12201 --sd --auto-advance=0.05 --no-encounter --no-music --hidden-spot-test 2>&1 | grep -E "^HS (ok|FAIL|PASS)"

test-item-use: ## 地图菜单使用道具: 可用判断 (0x488af9)、永久加值 / 回复 / 对象类别 / 全体 / 复活 (0x48982f, 0x488ffa) → IU PASS / FAIL
	cd godot && "$(GODOT)" --headless --path . res://scenes/field.tscn -- --map=12201 --sd --no-encounter --no-music --item-use-test 2>&1 | grep -E "^IU (ok|FAIL|PASS)|SCRIPT ERROR"

test-mod-m6: ## 创意工坊 M6 验收: mods/m6-items 自定义物品 (复制原版记录、对话拿到、地图使用、存读档、失效物品) → M6 PASS / FAIL
	cd godot && "$(GODOT)" --headless --path . res://scenes/field.tscn -- --mod=../mods/m6-items --map=12201 --sd --auto-advance=0.05 --mod-m6-test --quit-after=6000 2>&1 | grep -E "^M6 (ok|FAIL|PASS)"

test-mod-m7: ## 创意工坊 M7 验收: mods/m7-quest 任务 (接任务、记载页、交物品、完成) → M7 PASS / FAIL
	cd godot && "$(GODOT)" --headless --path . res://scenes/field.tscn -- --mod=../mods/m7-quest --map=12201 --sd --auto-advance=0.05 --mod-m7-test --quit-after=6000 2>&1 | grep -E "^M7 (ok|FAIL|PASS)"

test-mod-m8: ## 创意工坊 M8 验收: mods/m8-battle 自定义怪物 + 战斗 (复制原版熊 / 战场、对话开战、经验金钱掉落、图鉴) → M8 PASS / FAIL
	cd godot && "$(GODOT)" --headless --path . res://scenes/field.tscn -- --mod=../mods/m8-battle --map=12201 --sd --auto-battle --speed=4 --auto-advance=0.05 --mod-m8-test --quit-after=12000 2>&1 | grep -E "^M8 (ok|FAIL|PASS)|SCRIPT ERROR"

test-mod-m9: ## 创意工坊 M9 验收: mods/m9-model 自定义战斗模型 (动作表照抄原版熊、普攻 / 受伤播自定义动画、打赢) → M9 PASS / FAIL
	cd godot && "$(GODOT)" --headless --path . res://scenes/field.tscn -- --mod=../mods/m9-model --map=12201 --sd --auto-battle --speed=4 --auto-advance=0.05 --mod-m9-test --quit-after=30000 2>&1 | grep -E "^M9 |SCRIPT ERROR"

test-mod-m10: ## 创意工坊 M10 验收: mods/m10-encounter 遇敌 + 变量 (晋国大地图遇敌加 mod 战斗、打倒计数、mod 怪物不能收化、按计数领赏) → M10 PASS / FAIL
	cd godot && "$(GODOT)" --headless --path . res://scenes/field.tscn -- --mod=../mods/m10-encounter --map=12201 --sd --auto-battle --speed=4 --auto-advance=0.05 --mod-m10-test --quit-after=20000 2>&1 | grep -E "^M10 |SCRIPT ERROR"

test-mod-e2: ## 创意工坊 E2 验收: mods/e2-override 方案覆盖原版 (改原版事件、改 / 删原版 NPC、原版没改的照旧) → E2 PASS / FAIL
	cd godot && "$(GODOT)" --headless --path . res://scenes/field.tscn -- --mod=../mods/e2-override --map=12201 --sd --auto-advance=0.05 --mod-e2-test --quit-after=8000 2>&1 | grep -E "^E2 |SCRIPT ERROR"

test-mod-e4: ## 创意工坊 E4 验收: mods/e4-chars 改队员 (名字 / 初始数值 / 成长表 / 地图模型) 和开局 (金钱 / 物品 / 开局队伍) → E4 PASS / FAIL
	cd godot && "$(GODOT)" --headless --path . res://scenes/field.tscn -- --mod=../mods/e4-chars --map=12201 --sd --mod-e4-test --quit-after=6000 2>&1 | grep -E "^E4 |SCRIPT ERROR"

demo-video: ## 录制演示视频: 声明 → 标题 → 序章开场演出 (Godot 录像模式, 自动翻页) → out/prologue_demo.mp4 (含原版素材, 请勿分发)
	@mkdir -p out
	cd godot && "$(GODOT)" --path . --write-movie ../out/prologue_demo.avi --fixed-fps 30 -- --demo $(HD_ARG)
	ffmpeg -v error -y -i out/prologue_demo.avi -c:v libx264 -preset slow -crf 20 -pix_fmt yuv420p -c:a aac -b:a 192k -movflags +faststart out/prologue_demo.mp4
	rm -f out/prologue_demo.avi

hd: ## 高清素材: Real-ESRGAN (realesr-animevideov3 ×2) 放大界面图、精灵图和场景/角色/特效 GLB 的贴图 → $(HD_OUT)
	@test -x "$(ESRGAN)" || { echo "找不到 realesrgan-ncnn-vulkan: $(ESRGAN)  (用 make hd ESRGAN=... 指定)"; exit 1; }
	$(PY) $(T)/hd_assets.py $(OUT) $(HD_OUT) --esrgan "$(ESRGAN)" --keep-cache
	$(PY) $(T)/hd_textures.py $(OUT) $(HD_OUT)

hd4: ## 4K 素材: 2K 的放大结果再 Real-ESRGAN ×2 (= ×4) → $(UHD_OUT) (先 make hd); 过场视频 4K 版还没做, 先硬链接 2K 版
	@test -x "$(ESRGAN)" || { echo "找不到 realesrgan-ncnn-vulkan: $(ESRGAN)"; exit 1; }
	$(PY) $(T)/hd_assets.py $(OUT) $(UHD_OUT) --esrgan "$(ESRGAN)" --base $(abspath $(HD_OUT))/_cache/out_realesr-animevideov3_x2 --no-glb --keep-cache
	$(PY) $(T)/hd_textures.py $(OUT) $(UHD_OUT) 4
	@mkdir -p $(UHD_OUT)/video && ln -f $(HD_OUT)/video/*.ogv $(UHD_OUT)/video/

test-hd-tex: ## 高清贴图换图: 标清 GLB + hd_textures.gd 的贴图是标清的 2 / 4 倍, 2K 再和完整高清 GLB 逐像素比较 → HDTEX PASS / FAIL (开窗口跑; 4K: K4=1)
	cd godot && "$(GODOT)" --path . -s res://scripts/tests/hd_textures_test.gd -- --bg $(if $(filter 1,$(K4)),--4k,--2k) 2>&1 | grep -E "^HDTEX"

# ---------------- 视频 ----------------

hd-video: ## 高清过场视频: 逐帧 Real-ESRGAN ×2 → $(HD_OUT)/video/*.ogv (很慢, 约为片长的 6 倍)
	@test -x "$(ESRGAN)" || { echo "找不到 realesrgan-ncnn-vulkan: $(ESRGAN)"; exit 1; }
	$(PY) $(T)/convert_video.py "$(GAME)" $(OUT) --hd $(HD_OUT) --esrgan "$(ESRGAN)"


video: $(VIDEOS) ## VIDEO/*.bik → Theora .ogv (供 Godot 播放; 需要 ffmpeg 和 ffmpeg2theora: brew install ffmpeg2theora)
$(VIDEOS): | check-game
	$(PY) $(T)/convert_video.py "$(GAME)" $(OUT)
	@touch $@

# ---------------- 检查 ----------------

validate: $(VALIDATOR) ## 用官方 glTF Validator 检查全部模型和场景 GLB
	node $(T)/validate/validate.mjs $(OUT)/models $(OUT)/scenes

$(VALIDATOR): $(T)/validate/package.json
	cd $(T)/validate && npm install --silent

# ---------------- Godot ----------------

start: $(UI) $(TEXT) godot-import ## 启动游戏 (缺少的素材会先自动提取); make start HD=1 高清 / HD=0 普通
	"$(GODOT)" --path godot -- $(HD_ARG)

godot: start ## 同 make start

preview-data: $(PREVIEW) ## 生成技能预览数据 (主角技能 → ATK 动作序列 + 角色 GLB)
$(PREVIEW): $(T)/skill_catalog.py $(T)/act.py $(T)/ply2gltf.py $(STATS) | setup check-game
	$(PY) $(T)/skill_catalog.py "$(GAME)" $(OUT)/preview

effects: $(EFFECTS) ## 技能特效 (ATK 特效编号 → ACT 特效动作 + MGC 模型/精灵/粒子)
$(EFFECTS): $(T)/effects.py $(T)/ply2gltf.py $(PREVIEW) | setup check-game
	$(PY) $(T)/effects.py "$(GAME)" $(OUT)/effects --skills $(PREVIEW),$(OUT)/game/battle_fx_src.json,$(OUT)/game/field_fx_src.json

CHAR ?= 嬴诗
preview: $(EFFECTS) $(UI) $(TEXT) godot-import ## 技能观看器: 用战斗引擎施放游戏里的全部技能 (三人 + 怪物)
	"$(GODOT)" --path godot res://scenes/skill_preview.tscn -- $(HD_ARG)

PACKS ?= out/packs
HD2   ?= 1
HD4   ?= 0
packs: check-godot ## 发行版素材包: 提取结果按 公共 + 各章节 打成 .pck → $(PACKS); 默认含 2K 覆盖包 hd2.pck (不要: make packs HD2=0; 4K 包 hd4.pck: HD4=1, 先 make hd4)
	@rm -f $(PACKS)/*.pck
	$(PY) $(T)/pack_plan.py $(OUT) "$(GAME)" $(PACKS)/plan.json $(if $(filter 1,$(HD2)),--hd2 $(HD_OUT),) $(if $(filter 1,$(HD4)),--hd4 $(UHD_OUT),)
	"$(GODOT)" --headless --path godot -s res://scripts/tools/make_packs.gd -- $(abspath $(PACKS))/plan.json $(abspath $(PACKS))

win: check-godot ## 导出 Windows 版 → out/win/czt.exe (+ czt.pck), 素材包硬链接到 out/win/packs/ (先 make packs); 4K 包单独放 out/hd4.pck (另外分发)
	@mkdir -p out/win/packs
	"$(GODOT)" --headless --path godot --export-release "Windows Desktop" ../out/win/czt.exe
	@rm -f out/win/packs/*.pck
	@for f in $(PACKS)/*.pck; do case "$$f" in */hd4.pck) ln -f "$$f" out/hd4.pck;; *) ln -f "$$f" out/win/packs/;; esac; done
	@cp tools/win_readme.txt out/win/说明.txt

win-lite: check-godot cnb-key ## 导出 Windows 本机提取版 → out/win_lite/ (czt.exe + czt.pck + 说明; 提取程序由游戏从 CNB 自动下载, 见 updater.gd); 发布: tools/release.py publish
	@rm -rf out/win_lite && mkdir -p out/win_lite
	"$(GODOT)" --headless --path godot --export-release "Windows Desktop" ../out/win_lite/czt.exe
	@cp tools/win_lite_readme.txt out/win_lite/说明.txt

check-godot:
	@test -x "$(GODOT)" || { echo "找不到 Godot: $(GODOT)  (用 make GODOT=... 指定 Godot 4.7 可执行文件)"; exit 1; }

godot-import: check-godot ## 让 Godot 导入/刷新项目 (首次运行前)
	"$(GODOT)" --headless --path godot --import >/dev/null 2>&1 || true

SHOT ?= /tmp/czt_title.png
godot-shot: godot-import ## 标题画面截图 (make godot-shot SHOT=out.png)
	"$(GODOT)" --path godot res://scenes/title.tscn -- --bg --shot=$(abspath $(SHOT)) --shot-delay=3
	@echo "截图: $(abspath $(SHOT))"

# ---------------- 清理 ----------------

clean: ## 删除全部提取结果 (extracted/)
	rm -rf ./extracted

clean-godot: ## 删除 Godot 导入缓存 (godot/.godot)
	rm -rf ./godot/.godot
