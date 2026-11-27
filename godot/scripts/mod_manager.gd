extends Node
## 创意工坊 mod 加载 (自动加载 Mods)。
## 来源: user://mods/ 下的 *.pod (正式发布的加密包, 见 pod.gd / tools/podtool) 和含 mod.json 的子文件夹 (明文, 开发用),
##       加上命令行 --mod=路径 (文件夹或 .pod, 可多个, 总是启用)。
## 启用 / 停用、加载顺序存在设置里: mods/disabled = [mod id], mods/order = [mod id] (越靠前越先加载)。改动在下次启动游戏时生效。
##
## mod 内容 (文件夹或 .pod 归档里的路径):
##   mod.json         {"id": "作者.名字", "name": 显示名, "version": "1.0.0", "author": 作者, "game": 适配版本, "description": 简介}
##   maps/<地图号>.json {"npcs": [{"id": "@npc:1", "name": 显示名, "act": 模型 ACT, "pose": 0, "facing": 0,
##                                "pos": [x, y, z], "event": "@event:1", "ai": 0, "flags": 8224}]}   追加到原版地图角色表
##   events.json      {"1": [[位置, 指令, 参数...], ...]}   格式同 extracted/game/events/*.json 的 codes (跳转写目标位置)
##   preview.png      工坊里显示的封面 (可选)
##   models.json      自定义模型 (M4): {"1": {"name", "file": "models/x.glb", "scale": 1.0, "yaw": 0, "ground": 脚底高度,
##                      "poses": {"0": {"clip": 动画名, "loop": true, "ticks": 帧数 (35 帧/秒)}, "4": {...}}}}
##                    NPC 的 "act" 写 "@model:N" 用它; 动作号对应原版 (0 待机, 4 行走…), 没给的动作保持当前动画
##   voice/<key>.ogg  对白配音 (Ogg Vorbis): key = 剧本 text 原文 md5 前 16 位 (Game.voice_key, 生成见 tools/gen_voice.py);
##                    多个 mod 有同一句时后加载的生效。设定「对白配音」开着就播 (Game.play_voice)
##   quests.json      任务 (M7): {"1": {"text": "☆任务名", "accept": "@flag:N", "done": "@flag:M"}}
##                    同原版 records.quests (★主线 / ☆支线 写在文字开头): 接受旗标置位、完成旗标未置位 → 记载「未完成任务」,
##                    完成旗标置位 → 「已完成任务」。旗标只能用本 mod 的 @flag
##   items.json       自定义物品 (M6): {"1": {"base": 原版物品号, "name", "desc", "price", "fx1": [6 个], "fx2": [7 个]}}
##                    = 复制原版那条 ObjDATA 记录 (battle.json objs: 分类 sub、图标、使用演出 atk_id、范围、可用场合…),
##                    只改上面这几个字段; fx1[0] 生命 / fx1[1] 体力 / fx2[0] 灵力 的恢复量编码同 Formula.amount
##                    (≤10000 定值, 10001–10099 百分比 (≥99 = 全满), >20000 上限倍数)。菜单 / 商店 / 地图使用 / 战斗都读这条记录
##   tweaks.json      界面 / 操作微调 (T1, 原版没有的功能交给 mod 做; 没有 mod 写时一切照原版): 三节都可选, 不认识的键拒绝加载
##     "field_menu":  {"keys": ["Escape", ...], "page": "status"}  大地图上这些键也打开主菜单 (原版只有 Enter / 点右上角卷轴),
##                    page = 打开后直接到哪页: status / item / equip / qishu / jiguan / tianshu / jizai / system
##                    (键名同 OS.find_keycode_from_string; 按着 Shift / Ctrl / Alt 时不算, 不占原版 Shift+Esc)
##     "camera":      {"wheel": "pitch" / "distance" / "both", "invert": false, "pitch_step": 2, "pitch_min": 5, "pitch_max": 75,
##                     "dist_step": 100, "dist_min": 800, "dist_max": 4000}
##                    大地图上滚轮调镜头 (往上滚 = 俯仰角变小 / 拉近, invert 反过来); 事件里、菜单开着、禁止转镜头的地图 (标志 0x20) 不动;
##                    当前值已经在范围外时只往范围里走; Tab 回正时一起恢复滚动前的俯仰角和距离
##     "damage_numbers": 战斗飘字 hp / heal / mp / sp / money 换成 mod 自己的样式 (miss / 无效 / 宣告死亡照原版图)
##                    {"font": "fonts/x.ttf" 或 "digits": "images/digits.png" (一行 10 格 0–9 等宽), "size": 字高 36,
##                     "spacing": 字间距 0, "outline_size": 描边 0, "color": "#rrggbb[aa]", "outline_color", "prefix": "",
##                     "splash": 墨迹底图 png, "splash_color", "splash_scale": 1.4 (相对整串数字宽),
##                     "kinds": {"hp": {上面的 color / outline_color / prefix / splash / splash_color / splash_scale 可逐项覆盖}, ...},
##                     "anim": {"duration": 1.2, "fade": 0.4, "rise": 30, "rise_time": 0.3, "scale_from": 1.0, "scale_time": 0.15,
##                              "stagger": 0.04, "bounce": 8, "tilt": 0, "splash_time": 0.2}}
##                    写了 kinds 就只换列出的类型, 没写 kinds 五种都换; 字体 / 图片 ≤ 8MB
##                    多个 mod 写了同一节: 后加载的整节生效 (记一条冲突)
## 符号引用 (加载时换成实际编号, 原版的东西直接写数字):
##   "@npc:N"   → 角色号 0x9000 + 槽 × 256 + N   (N < 256)
##   "@event:N" → 事件号 1000000 + 槽' × 1000 + N
##   "@flag:N"  → 旗标 200000000 + 槽' × 1000 + N
##   "@model:N" → 虚拟 ACT 号 5000000 + 槽'' × 64 + N   (N < 64; 原版 ACT 最大 1 万多)
##   monsters.json    自定义怪物 (M8): {"1": {"base": 原版怪物号, "name", "desc", "level", "hp", "mp", "sp", "atk", "def", "spd",
##                      "matk", "mdef", "hit", "eva", "mhit", "meva", "exp", "money", "drop": [几率 %, 物品]}}
##                    = 复制原版那条怪物记录 (模型 / 普攻演出 / 技能 / AI / 属性抗性 / 偷窃物 / 资源 照抄), 只改上面这些;
##                    原版怪物 = 某个战场里出现过的敌人 (分类 110–120)。图鉴条目复制原版那条再改名字 / 说明 / 数值
##                    战斗模型 (M9, 可选): "model": "@model:N", "poses": {"动作号": 动画名, ...}
##                    = 动作表照抄来源怪物的 ACT (每个动作的帧数、命中 / 特效记号、音效、位移、颜色), 只把画面换成自定义模型的动画:
##                    不循环的动作把动画拉伸到原版帧数 (命中时刻和原版一样); 没指定的动作用待机 (14) 的动画;
##                    ACT 的缩放不套 (大小用模型自己的 scale), 位移按原缩放换算成同样的距离
##   battles.json     自定义战斗 (M8): {"1": {"base": 原版战场号, "enemies": [{"monster": 怪物号或 "@monster:N", "at": 站位}]}}
##                    = 复制原版战场 (场景、镜头、战斗脚本 FIGTALK、雾), 敌人换掉; 站位 at 是原版战场第几个敌人的位置 / 朝向。
##                    只能选战斗脚本只有「音乐 / 先手 / 开场演出 / 回合」的普通战场 (BATTLE_SIMPLE_OPS), 剧情战的脚本会点名单位
##                    事件里 start_battle "@battle:N" 开打; 剧情战一样输了回标题
##                    "counter": N = 被打倒时 mod 变量 N +1 (见下面「变量」); mod 怪物不能收化
##   变量 (M10)       = 本 mod 0 号角色 (@npc:0, NPC 从 1 号起所以空着) 的角色变量: 事件里用原版的
##                    set_actor_var / add_actor_var / if_actor_var_ge_goto / if_actor_var_eq_goto ("@npc:0", N, 值), 跟存档保存 (0–65535)
##   maps/<地图号>.json 的 "encounters" (M10): [{"battle": "@battle:N", "weight": 1–20, "zones": [区域序号...] (不写 = 全部)}]
##                    = 把本 mod 的战斗加进这张图原版遇敌区域的战场列表 weight 次 (原版列表里重复 = 权重, 0x404f17);
##                    只能加到原版就有遇敌的地图
##   overrides.json   方案改原版事件 (E2): {"原版事件号": [[位置, 指令, 参数...], ...]} 整段替换原版那个事件的代码
##                    (同 events.json 的检查: 只能用原版出现过的指令); 多个 mod 改同一个事件, 后加载的生效 (记一条冲突)
##   maps/<地图号>.json 的 "npc_edits" (E2): [{"actor": 原版角色号, "remove": true}
##                    或 {"actor": 号, "pos": [x, y, z], "act": ACT 或 "@model:N", "pose", "facing", "event": 事件号或 "@event:N", "name"}]
##                    = 改 / 删原版地图上的 NPC (只改写的这几项, 出现条件等照旧)
##   characters.json  改队员 (E4): {"1": {"name", "desc", "level", "hp", "mp", "sp", "atk", "def", "spd", "matk", "mdef", "hit", "eva",
##                    "mhit", "meva", "crit", "growth": [[等级, HP, MP, SP, 攻, 防, 仙攻, 仙防, 命中, 回避, 仙命中, 仙回避, 速度, 习得法术], ...],
##                    "map_act": ACT 或 "@model:N"}} —— 1 车芸 / 2 嬴诗 / 3 桓远之。初始数值覆盖 ObjDATA 主角记录 (State.member 首次用到时读),
##                    成长表同 LEVEL.GLL (升级加这一行, 第 13 列 = 这一级习得的法术, State.add_exp); map_act = 车芸在地图上的模型
##                    (新游戏的全局角色记录); 只影响新开的游戏 (读档的队员数值在存档里)
##   newgame.json     改开局 (E4): {"money", "items": [物品...], "equip": {"1": [8 格]}, "skills": {"1": [法术...]}, "party": [1, 2, 3]}
##                    (同 new_game.json init; party = 开局在队的, 设旗标 1/2/3 —— 战斗 / 菜单都按这三个旗标判断谁在队)
##   skills.json      技能 / 绝技 (E5): {"1": {"base": 原版技能号, "name", "desc", "power", "cost": {"hp", "sp", "mp", "juji"}, "fx1", "fx2"}}
##                    = 新技能: 复制原版技能 (演出 atk_id、范围、属性、状态照抄), 只改这几项; 只能复制 攻击 201 / 恢复 202 / 辅助 203 / 绝技 305
##                    (修复 302 只对云狐、木甲 306 的 6024–6027 按编号走机关逻辑 battle._mech_skill, 复制了会丢);
##                    {"6401": {"power", ...}} (键是原版技能号、不写 base) = 改原版技能的这几项。
##                    学会: characters.json 成长表第 13 列 (第几级学会) 或 newgame.json 的 skills (开局就会), 都可以写 "@skill:N"
##   "@skill:N" → 技能号 30000000 + 槽'' × 256 + N   (N < 256)
##   "@item:N"  → 物品号 6000000 + 槽'' × 256 + N   (N < 256; 原版 ObjDATA 最大 7516)
##   "@monster:N" → 怪物号 10000000 + 槽'' × 256 + N   (N < 256)
##   "@battle:N"  → 战场号 20000000 + 槽'' × 64 + N    (N < 64; 原版战场 0–300 多)
##   槽 / 槽' 由 mod id 的哈希决定 (不随加载顺序变化, 存档里的旗标 / 角色状态才稳定); 原版最大: 角色 7978、事件 7978、旗标 8080
## 安全: mod 只有数据; 事件只能用原版事件数据里出现过的指令 (解释器都实现了), 不认识的整个 mod 拒绝加载;
##       .pod 签名 / 校验不过的拒绝加载

const ACTOR_BASE := 0x9000
const EVENT_BASE := 1000000
const FLAG_BASE := 200000000
const MODEL_BASE := 5000000
const ITEM_BASE := 6000000
const ITEM_KEYS := ["name", "desc", "price", "fx1", "fx2"]   # mod 物品能改的字段, 其余照抄原版
const ITEM_SUBS := [201, 202, 203, 204, 205, 206, 207, 208, 209, 210, 211]   # ObjDATA 物品分类 (攻击…剧情, 同 main_menu ITEM_TABS)
const MONSTER_BASE := 10000000
const BATTLE_BASE := 20000000
const SKILL_BASE := 30000000
const SKILL_KEYS := ["name", "desc", "power", "cost", "fx1", "fx2"]
const SKILL_SUBS := [201, 202, 203, 305]   # 能复制的技能分类 (攻击 / 恢复 / 辅助 / 绝技)
const CHAR_KEYS := ["name", "desc", "level", "hp", "mp", "sp", "atk", "def", "spd", "matk", "mdef", "hit", "eva", "mhit", "meva", "crit"]
const MONSTER_STATS := ["level", "hp", "mp", "sp", "atk", "def", "spd", "matk", "mdef", "hit", "eva", "mhit", "meva"]
const MONSTER_KEYS := ["name", "desc", "exp", "money", "drop", "counter"] + MONSTER_STATS   # mod 怪物能改的字段
const BATTLE_SIMPLE_OPS := ["set_battle_music", "play_battle_music", "set_initiative", "start_battle", "run_battle_turns", "end_script", "end"]
const MAX_MODEL_BYTES := 20 * 1024 * 1024
var ROOT: String = Game.ModsDir if Game.portable_root != "" else "user://mods"   # 便携模式: 程序旁 orig/ 存在时 Mod 放程序目录的 userdata/mods

## 找到的全部 mod (工坊菜单列表用): {id, name, version, author, description, kind: "dir"/"pod", path, size, fingerprint,
##   dev (命令行指定), enabled, status: "loaded" / "disabled" / "error", error, preview: PackedByteArray}
var installed: Array = []
var mods: Array = []      # 已加载的 (installed 的子集)
var events := {}          # 实际事件号 → 代码
var names := {}           # 实际角色号 → 显示名
var map_npcs := {}        # 地图号 (字符串) → [NPC 记录]
var models := {}          # 虚拟 ACT 号 → {bytes, meta (同 act_<ACT>.json 的格式), scale, yaw}
var items := {}           # 物品号 → 合并后的 ObjDATA 记录 (已注入 Battle.db.objs)
var monsters := {}        # 怪物号 → 合并后的 ObjDATA 记录 (已注入 Battle.db.objs)
var bestiary: Array = []  # 图鉴条目 (格式同 records.bestiary), 记载「人」页接在原版后面
var battles := {}         # 战场号 → 战场记录 (已注入 Battle.db.battlefields)
var _injected_bf: Array = []
var overrides := {}       # 原版事件号 → 方案改过的代码
var skills := {}          # 新技能号 → 合并后的 ObjDATA 记录 (注入 Battle.db.objs)
var skill_edits := {}     # 原版技能号 → 改的字段
var chars := {}           # 队员号 → 改过的字段 (含 growth / map_act)
var newgame := {}         # 改开局 (newgame.json)
var _orig := {}           # 被覆盖的原版数据备份 ("obj:1" / "growth:1" → 原值), reload 时还原
var map_npc_edits := {}   # 地图号 (字符串) → [改 / 删原版 NPC]
var map_encounters := {}  # 地图号 (字符串) → [{battle, weight, zones}]
var voices := {}          # 配音 key → Ogg Vorbis 字节 (voice/<key>.ogg)
var voice_mod := ""       # 提供 voices 的那个配音包 (只用加载顺序里第一个启用的)
var quests: Array = []    # 任务 (格式同 records.quests: text / flag_accept / flag_done / main), 记载页接在原版后面
var _injected: Array = [] # 上次注入 Battle.db.objs 的物品号 (reload 时先清掉)
var errors: Array = []
var tweaks := {}          # tweaks.json 合并结果: field_menu / camera / damage_numbers (已解析: 键码、字体、贴图、颜色)
const TWEAK_KINDS := ["hp", "heal", "mp", "sp", "money"]
const MENU_PAGES := ["status", "item", "equip", "qishu", "jiguan", "tianshu", "jizai", "system"]
const MAX_ASSET_BYTES := 8 * 1024 * 1024


func _ready() -> void:
	reload()


## 重新扫描并加载 (工坊菜单改了启用 / 顺序后, 回到标题画面时调用; 进了游戏的地图数据在下次读图时才用到新结果)
func reload() -> void:
	installed.clear()
	mods.clear()
	events.clear()
	names.clear()
	map_npcs.clear()
	models.clear()
	items.clear()
	monsters.clear()
	bestiary.clear()
	battles.clear()
	map_encounters.clear()
	overrides.clear()
	map_npc_edits.clear()
	chars.clear()
	newgame.clear()
	skills.clear()
	skill_edits.clear()
	quests.clear()
	voices.clear()
	voice_mod = ""
	tweaks.clear()
	errors.clear()
	var srcs: Array = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--mod="):
			srcs.append({"path": a.substr(6), "dev": true})
	if DirAccess.dir_exists_absolute(ROOT):
		for d in DirAccess.get_directories_at(ROOT):
			if FileAccess.file_exists(ROOT.path_join(d).path_join("mod.json")):
				srcs.append({"path": ROOT.path_join(d), "dev": false})
		for f in DirAccess.get_files_at(ROOT):
			if f.get_extension().to_lower() == "pod":
				srcs.append({"path": ROOT.path_join(f), "dev": false})
	var enabled := _enabled_ids(srcs)
	for s in srcs:
		var m := _read_source(str(s.path), bool(s.dev), enabled)
		if m.status == "error":
			errors.append("%s: %s" % [m.path.get_file(), m.error])
		installed.append(m)
	# 加载顺序: 命令行的最先, 其余按设置 mods/order, 没排过的按 id
	var order: Array = Game.get_setting("mods", "order", [])
	installed.sort_custom(func(x, y):
		if x.dev != y.dev:
			return x.dev
		var ix := order.find(x.id)
		var iy := order.find(y.id)
		ix = ix if ix >= 0 else 1 << 20
		iy = iy if iy >= 0 else 1 << 20
		return ix < iy if ix != iy else str(x.id) < str(y.id))
	for m in installed:
		if m.status == "pending":
			_load_mod(m)
	_inject_items()
	for e in errors:
		push_warning("MOD " + str(e))
	if mods.size():
		print("MODS %s" % str(mods.map(func(m): return "%s %s" % [m.id, m.version])))


## 启用的 mod (设置 mods/enabled): 新放进文件夹的 mod 默认不启用 (用户要求), 要在工坊里手动启用。
## 旧版设置记的是停用列表 mods/disabled: 第一次升级时把当时没停用的都记成启用, 保持原状
func _enabled_ids(srcs: Array) -> Array:
	if Game.has_setting("mods", "enabled"):
		return Game.get_setting("mods", "enabled", [])
	if not Game.has_setting("mods", "disabled"):
		return []
	var disabled: Array = Game.get_setting("mods", "disabled", [])
	var ids: Array = []
	for s in srcs:
		if not s.dev:
			var m := _read_source(str(s.path), false, [])
			if m.status != "error" and not m.id in disabled and not m.id in ids:
				ids.append(m.id)
	Game.set_setting("mods", "enabled", ids)
	return ids


## 读来源 → {元信息, files} (status = pending / disabled / error); 命令行 --mod= 的开发 mod 总是启用
func _read_source(path: String, dev: bool, enabled: Array) -> Dictionary:
	var m := {"id": path.get_file(), "name": path.get_file(), "version": "", "author": "", "description": "", "path": path,
		"kind": "pod" if path.get_extension().to_lower() == "pod" else "dir", "dev": dev, "size": 0, "fingerprint": "",
		"enabled": true, "status": "pending", "error": "", "preview": PackedByteArray(), "files": {}}
	var files := {}
	if m.kind == "pod":
		var r := Pod.read_file(path)
		var fa := FileAccess.open(path, FileAccess.READ)   # 只要大小, 不整个读进来 (配音包 300MB+)
		m.size = fa.get_length() if fa else 0
		if not r.ok:
			m.status = "error"
			m.error = r.error
			return m
		files = r.files
		m.fingerprint = r.fingerprint
		m.id = r.id
	else:
		files = _read_dir(path, "")
		for v in files.values():
			m.size += (v as PackedByteArray).size()
	var man: Variant = JSON.parse_string((files.get("mod.json", PackedByteArray()) as PackedByteArray).get_string_from_utf8())
	if not man is Dictionary or str(man.get("id", "")) == "":
		m.status = "error"
		m.error = "缺少 mod.json 或 id"
		return m
	if m.kind == "pod" and str(man.id) != m.id:
		m.status = "error"
		m.error = "包头 id 和 mod.json 不一致"
		return m
	for k in ["id", "name", "version", "author", "description"]:
		if man.has(k):
			m[k] = str(man[k])
	m.preview = files.get("preview.png", PackedByteArray())
	m.files = files
	if installed.any(func(o): return o.id == m.id and o.status != "error"):
		m.status = "error"
		m.error = "重复的 mod id"
		return m
	if not dev and not m.id in enabled:
		m.enabled = false
		m.status = "disabled"
	return m


func _read_dir(dir: String, rel: String) -> Dictionary:
	var out := {}
	var full := dir.path_join(rel) if rel != "" else dir
	for f in DirAccess.get_files_at(full):
		if not f.begins_with("."):
			out[(rel + "/" + f) if rel != "" else f] = FileAccess.get_file_as_bytes(full.path_join(f))
	for d in DirAccess.get_directories_at(full):
		if not d.begins_with("."):
			out.merge(_read_dir(dir, (rel + "/" + d) if rel != "" else d))
	return out


func _slot(mod_id: String, n: int) -> int:
	return absi(mod_id.hash()) % n


func actor_id(mod_id: String, n: int) -> int:
	return ACTOR_BASE + _slot(mod_id, 96) * 256 + n


func event_id(mod_id: String, n: int) -> int:
	return EVENT_BASE + _slot(mod_id, 100000) * 1000 + n


func flag_id(mod_id: String, n: int) -> int:
	return FLAG_BASE + _slot(mod_id, 100000) * 1000 + n


func model_id(mod_id: String, n: int) -> int:
	return MODEL_BASE + _slot(mod_id, 10000) * 64 + n


func item_id(mod_id: String, n: int) -> int:
	return ITEM_BASE + _slot(mod_id, 10000) * 256 + n


func monster_id(mod_id: String, n: int) -> int:
	return MONSTER_BASE + _slot(mod_id, 10000) * 256 + n


func skill_id(mod_id: String, n: int) -> int:
	return SKILL_BASE + _slot(mod_id, 10000) * 256 + n


func battle_id(mod_id: String, n: int) -> int:
	return BATTLE_BASE + _slot(mod_id, 10000) * 64 + n


## 能当 mod 怪物底子的原版怪物: 分类 110–120、在某个战场里当过敌人 (战斗模型 / 动作都齐)
var _enemy_ids := {}


func is_base_monster(id: int) -> bool:
	Battle.load_db()
	if _enemy_ids.is_empty():
		for b in Battle.db.battlefields.values():
			for e in b.get("enemies", []):
				_enemy_ids[int(e.id)] = true
	var r: Dictionary = Battle.db.objs.get(str(id), {})
	return _enemy_ids.has(id) and int(r.get("sub", 0)) >= 110 and int(r.get("sub", 0)) <= 120


## 能当 mod 战斗底子的原版战场: 战斗脚本只有 BATTLE_SIMPLE_OPS (不点名单位、没有剧情对白)
func is_base_battle(id: int) -> bool:
	Battle.load_db()
	var b: Dictionary = Battle.db.battlefields.get(str(id), {})
	if b.is_empty() or id >= BATTLE_BASE:
		return false
	var ft: Variant = Battle.db.figtalk.get(str(int(b.get("figtalk", -1))))
	if not ft is Array or (ft as Array).is_empty():
		return false
	for ins in ft:
		if str(ins[1]) not in BATTLE_SIMPLE_OPS:
			return false
	return true


## 物品记录并进 Battle.db.objs (菜单 / 商店 / 战斗都用 Battle.obj 取物品)
func _inject_items() -> void:
	Battle.load_db()
	for k in _injected:
		Battle.db.objs.erase(str(k))
	_injected.clear()
	for k in items:
		Battle.db.objs[str(k)] = items[k]
		_injected.append(k)
	for k in monsters:
		Battle.db.objs[str(k)] = monsters[k]
		_injected.append(k)
	for key in _orig:   # 先还原上次覆盖的原版数据
		var kk := str(key).get_slice(":", 1)
		if str(key).begins_with("obj:"):
			Battle.db.objs[kk] = _orig[key]
		else:
			Battle.db.growth[kk] = _orig[key]
	_orig.clear()
	for k in skills:
		Battle.db.objs[str(k)] = skills[k]
		_injected.append(k)
	for sid in skill_edits:   # 改原版技能: 备份后覆盖这几项
		var ks := str(sid)
		_orig["obj:" + ks] = Battle.db.objs[ks]
		var srec: Dictionary = (Battle.db.objs[ks] as Dictionary).duplicate(true)
		srec.merge(skill_edits[sid], true)
		Battle.db.objs[ks] = srec
	for c in chars:
		var sk := str(c)
		var e: Dictionary = chars[c]
		_orig["obj:" + sk] = Battle.db.objs[sk]
		var rec: Dictionary = (Battle.db.objs[sk] as Dictionary).duplicate(true)
		for key in CHAR_KEYS:
			if e.has(key):
				rec[key] = str(e[key]) if key in ["name", "desc"] else int(e[key])
		Battle.db.objs[sk] = rec
		if e.has("growth"):
			_orig["growth:" + sk] = Battle.db.growth.get(sk, [])
			Battle.db.growth[sk] = e.growth
	for k in _injected_bf:
		Battle.db.battlefields.erase(str(k))
	_injected_bf.clear()
	for k in battles:
		Battle.db.battlefields[str(k)] = battles[k]
		_injected_bf.append(k)


var _recs := {}


## 战斗模型: 自定义模型 + 来源怪物 ACT 的动作表 (见文件头 monsters.json)
func _battle_model(base_act: int, model: Dictionary, clips: Dictionary) -> Dictionary:
	var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(Game.extracted_dir.path_join("game/actors/act_%d.json" % base_act)))
	if not j is Dictionary or not (j as Dictionary).has("poses"):
		return {}
	var idle := str(clips.get("14", ""))
	var poses := {}
	for q in j.poses:
		var bp: Dictionary = j.poses[q]
		var xf: Array = []
		for row in bp.get("xform", []):
			var r: Array = (row as Array).duplicate()
			if r.size() > 6:
				for c in 3:   # 位移 = PD × 缩放 (field_actor._apply_xform); 缩放改成 1, 位移乘回去, 距离不变
					r[4 + c] = float(r[4 + c]) * float(r[1 + c])
					r[1 + c] = 1.0
			xf.append(r)
		var loop := bool(bp.get("loop", false))
		poses[str(q)] = {"g": 0, "clip": str(clips.get(str(q), idle)), "ticks": int(bp.ticks), "loop": loop, "fit": not loop,
			"marks": bp.get("marks", []), "sounds": bp.get("sounds", []), "bbox": bp.get("bbox", []), "xform": xf}
	var out := model.duplicate()
	out.meta = {"act": base_act, "poses": poses, "groups": [{"glb": "@mod"}]}
	return out


## records.json 的图鉴按怪物号索引 (复制图鉴条目用)
func _records() -> Dictionary:
	if _recs.is_empty():
		var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(Game.extracted_dir.path_join("game/records.json")))
		var by := {}
		if j is Dictionary:
			for b in j.get("bestiary", []):
				by[int(b.id)] = b
		_recs = {"bestiary_by_id": by}
	return _recs


## 把 "@npc:N" / "@event:N" / "@flag:N" 换成实际编号 (递归处理数组 / 字典)
func _resolve(v: Variant, mod_id: String) -> Variant:
	if v is String and (v as String).begins_with("@"):
		var kind := (v as String).substr(1).get_slice(":", 0)
		var n := int((v as String).get_slice(":", 1))
		match kind:
			"npc":
				return actor_id(mod_id, n)
			"event":
				return event_id(mod_id, n)
			"flag":
				return flag_id(mod_id, n)
			"model":
				return model_id(mod_id, n)
			"item":
				return item_id(mod_id, n)
			"monster":
				return monster_id(mod_id, n)
			"battle":
				return battle_id(mod_id, n)
			"skill":
				return skill_id(mod_id, n)
		return v
	if v is Array:
		return (v as Array).map(func(x): return _resolve(x, mod_id))
	if v is Dictionary:
		var out := {}
		for k in v:
			out[k] = _resolve(v[k], mod_id)
		return out
	return v


var _ops := {}


func _known_ops() -> Dictionary:
	if _ops.is_empty():
		var d := Game.extracted_dir.path_join("game/events")
		for f in DirAccess.get_files_at(d):
			if not f.ends_with(".json"):
				continue
			var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(d.path_join(f)))
			if j is Dictionary:
				for code in j.get("codes", {}).values():
					for ins in code:
						_ops[str(ins[1])] = true
	return _ops


func _json(files: Dictionary, path: String) -> Variant:
	if not files.has(path):
		return null
	return JSON.parse_string((files[path] as PackedByteArray).get_string_from_utf8())


## tweaks.json → 解析好的 {field_menu, camera, damage_numbers} (没有文件 = {}); 有错 → _reject 并返回 null
func _parse_tweaks(m: Dictionary, files: Dictionary) -> Variant:
	if not files.has("tweaks.json"):
		return {}
	var tw: Variant = _json(files, "tweaks.json")
	if not tw is Dictionary:
		_reject(m, "tweaks.json 不是 JSON 对象")
		return null
	var out := {}
	for sec in tw:
		var v: Variant = tw[sec]
		if not v is Dictionary:
			_reject(m, "tweaks.json 的 %s 要写成对象" % sec)
			return null
		var r: Variant
		match str(sec):
			"field_menu":
				r = _tweak_menu(m, v)
			"camera":
				r = _tweak_camera(m, v)
			"damage_numbers":
				r = _tweak_numbers(m, v, files)
			_:
				_reject(m, "tweaks.json 不认识的项 %s" % sec)
				return null
		if r == null:
			return null
		out[str(sec)] = r
	return out


func _tweak_bad(m: Dictionary, sec: String, d: Dictionary, allowed: Array) -> bool:
	for k in d:
		if not str(k) in allowed:
			_reject(m, "tweaks.json 的 %s 不认识 %s" % [sec, k])
			return true
	return false


func _tweak_menu(m: Dictionary, d: Dictionary) -> Variant:
	if _tweak_bad(m, "field_menu", d, ["keys", "page"]):
		return null
	var codes: Array = []
	var ks: Variant = d.get("keys", [])
	if not ks is Array:
		_reject(m, "field_menu.keys 要写成键名列表")
		return null
	for k in ks:
		var c := OS.find_keycode_from_string(str(k))
		if c == KEY_NONE:
			_reject(m, "field_menu.keys 不认识的键名 %s" % str(k))
			return null
		codes.append(c)
	var page := str(d.get("page", "status"))
	if not page in MENU_PAGES:
		_reject(m, "field_menu.page 只能是 %s" % ", ".join(MENU_PAGES))
		return null
	return {"keys": codes, "page": page}


func _tweak_camera(m: Dictionary, d: Dictionary) -> Variant:
	var nums := {"pitch_step": 2.0, "pitch_min": 5.0, "pitch_max": 75.0, "dist_step": 100.0, "dist_min": 800.0, "dist_max": 4000.0}
	if _tweak_bad(m, "camera", d, ["wheel", "invert"] + nums.keys()):
		return null
	var wheel := str(d.get("wheel", "pitch"))
	if not wheel in ["pitch", "distance", "both"]:
		_reject(m, "camera.wheel 只能是 pitch / distance / both")
		return null
	var out := {"wheel": wheel, "invert": bool(d.get("invert", false))}
	for k in nums:
		var x: Variant = d.get(k, nums[k])
		if not (x is float or x is int):
			_reject(m, "camera.%s 要写数字" % k)
			return null
		out[k] = float(x)
	if out.pitch_min > out.pitch_max or out.dist_min > out.dist_max or out.pitch_min < -89 or out.pitch_max > 89 or out.dist_min < 1:
		_reject(m, "camera 的范围不对 (pitch −89–89, min ≤ max, dist_min ≥ 1)")
		return null
	return out


const NUM_STYLE_KEYS := ["color", "outline_color", "prefix", "splash", "splash_color", "splash_scale"]
const NUM_ANIM := {"duration": 1.2, "fade": 0.4, "rise": 30.0, "rise_time": 0.3, "scale_from": 1.0, "scale_time": 0.15,
	"stagger": 0.04, "bounce": 8.0, "tilt": 0.0, "splash_time": 0.2}


func _tweak_numbers(m: Dictionary, d: Dictionary, files: Dictionary) -> Variant:
	if _tweak_bad(m, "damage_numbers", d, ["font", "digits", "size", "spacing", "outline_size", "kinds", "anim"] + NUM_STYLE_KEYS):
		return null
	var out := {"font": null, "digits": null}
	if d.has("font") == d.has("digits"):
		_reject(m, "damage_numbers 要写 font 或 digits (只写一个)")
		return null
	if d.has("font"):
		var b: Variant = _asset(m, files, str(d.font), "damage_numbers.font")
		if b == null:
			return null
		var sig := (b as PackedByteArray).slice(0, 4)
		if not (sig == PackedByteArray([0, 1, 0, 0]) or sig.get_string_from_ascii() in ["OTTO", "true", "ttcf"]):
			_reject(m, "damage_numbers.font 不是 ttf / otf 字体")
			return null
		var f := FontFile.new()
		f.data = b
		out.font = f
	else:
		var tex: Variant = _png(m, files, str(d.digits), "damage_numbers.digits")
		if tex == null:
			return null
		out.digits = tex
	for k in ["size", "spacing", "outline_size"]:
		var x: Variant = d.get(k, {"size": 36, "spacing": 0, "outline_size": 0}[k])
		if not (x is float or x is int):
			_reject(m, "damage_numbers.%s 要写数字" % k)
			return null
		out[k] = float(x)
	if out.size < 4 or out.size > 200:
		_reject(m, "damage_numbers.size 要在 4–200 之间")
		return null
	var base: Variant = _num_style(m, files, d, {"color": Color.WHITE, "outline_color": Color.BLACK, "prefix": "", "splash": null,
		"splash_color": Color.WHITE, "splash_scale": 1.4}, "damage_numbers")
	if base == null:
		return null
	var kinds := {}
	var kd: Variant = d.get("kinds", null)
	if kd != null:
		if not kd is Dictionary:
			_reject(m, "damage_numbers.kinds 要写成对象")
			return null
		for k in kd:
			if not str(k) in TWEAK_KINDS or not kd[k] is Dictionary:
				_reject(m, "damage_numbers.kinds 只能有 %s (各写成对象)" % ", ".join(TWEAK_KINDS))
				return null
			if _tweak_bad(m, "damage_numbers.kinds." + str(k), kd[k], NUM_STYLE_KEYS):
				return null
			var ks: Variant = _num_style(m, files, kd[k], base, "damage_numbers.kinds." + str(k))
			if ks == null:
				return null
			kinds[str(k)] = ks
	else:
		for k in TWEAK_KINDS:
			kinds[k] = base
	out.kinds = kinds
	var anim := NUM_ANIM.duplicate()
	var ad: Variant = d.get("anim", {})
	if not ad is Dictionary:
		_reject(m, "damage_numbers.anim 要写成对象")
		return null
	if _tweak_bad(m, "damage_numbers.anim", ad, NUM_ANIM.keys()):
		return null
	for k in ad:
		if not (ad[k] is float or ad[k] is int) or float(ad[k]) < 0:
			_reject(m, "damage_numbers.anim.%s 要写非负数字" % k)
			return null
		anim[k] = float(ad[k])
	anim.duration = clampf(anim.duration, 0.2, 5.0)
	anim.fade = minf(anim.fade, anim.duration)
	out.anim = anim
	return out


## 一组飘字样式 (颜色 / 前缀 / 墨迹), 没写的项沿用 base
func _num_style(m: Dictionary, files: Dictionary, d: Dictionary, base: Dictionary, sec: String) -> Variant:
	var st := base.duplicate()
	for k in ["color", "outline_color", "splash_color"]:
		if d.has(k):
			if not d[k] is String or not Color.html_is_valid(str(d[k])):
				_reject(m, "%s.%s 要写颜色 #rrggbb 或 #rrggbbaa" % [sec, k])
				return null
			st[k] = Color.html(str(d[k]))
	if d.has("prefix"):
		st.prefix = str(d.prefix).left(4)
	if d.has("splash_scale"):
		if not (d.splash_scale is float or d.splash_scale is int):
			_reject(m, "%s.splash_scale 要写数字" % sec)
			return null
		st.splash_scale = float(d.splash_scale)
	if d.has("splash"):
		var tex: Variant = _png(m, files, str(d.splash), sec + ".splash")
		if tex == null:
			return null
		st.splash = tex
	return st


func _asset(m: Dictionary, files: Dictionary, path: String, what: String) -> Variant:
	if not files.has(path):
		_reject(m, "%s 的文件 %s 不存在" % [what, path])
		return null
	var b: PackedByteArray = files[path]
	if b.size() > MAX_ASSET_BYTES:
		_reject(m, "%s 超过 8MB" % what)
		return null
	return b


func _png(m: Dictionary, files: Dictionary, path: String, what: String) -> Variant:
	var b: Variant = _asset(m, files, path, what)
	if b == null:
		return null
	var img := Image.new()
	if img.load_png_from_buffer(b) != OK:
		_reject(m, "%s 不是 png 图片" % what)
		return null
	return ImageTexture.create_from_image(img)


## 大地图: 这个键是不是 mod 加的「打开主菜单」键 (按着修饰键不算); 是 → 要打开的页, 否则 ""
func field_menu_page(e: InputEventKey) -> String:
	var fm: Dictionary = tweaks.get("field_menu", {})
	if fm.is_empty() or e.shift_pressed or e.ctrl_pressed or e.alt_pressed or e.meta_pressed or not e.keycode in fm.keys:
		return ""
	return fm.page


func _reject(m: Dictionary, msg: String) -> void:
	m.status = "error"
	m.error = msg
	errors.append("%s: %s" % [m.id, msg])


func _load_mod(m: Dictionary) -> void:
	var mod_id: String = m.id
	var files: Dictionary = m.files
	# 事件: 先全部检查, 有不认识的指令就整个 mod 不加载
	var evs: Variant = _json(files, "events.json")
	var new_events := {}
	if evs is Dictionary:
		for k in evs:
			var code: Array = _resolve(evs[k], mod_id)
			for ins in code:
				if not (ins is Array) or (ins as Array).size() < 2 or not _known_ops().has(str(ins[1])):
					_reject(m, "事件 %s 有不认识的指令 %s" % [k, str(ins)])
					return
			new_events[event_id(mod_id, int(k))] = code
	# 改原版事件 (方案)
	var new_over := {}
	var ov: Variant = _json(files, "overrides.json")
	if ov is Dictionary:
		for k in ov:
			if int(k) <= 0 or int(k) >= EVENT_BASE or not ov[k] is Array:
				_reject(m, "overrides.json 的 %s 不是原版事件号" % k)
				return
			var code: Array = _resolve(ov[k], mod_id)
			for ins in code:
				if not (ins is Array) or (ins as Array).size() < 2 or not _known_ops().has(str(ins[1])):
					_reject(m, "改原版事件 %s 有不认识的指令 %s" % [k, str(ins)])
					return
			new_over[int(k)] = code
	# 自定义模型: GLB 留在内存里, 角色用到时再解析 (instantiate_model)
	var new_models := {}
	var mdl: Variant = _json(files, "models.json")
	if mdl is Dictionary:
		for k in mdl:
			var e: Dictionary = mdl[k]
			var fpath := str(e.get("file", ""))
			if int(k) < 1 or int(k) >= 64:
				_reject(m, "模型编号要在 1–63 之间")
				return
			if not files.has(fpath):
				_reject(m, "模型 %s 的文件 %s 不存在" % [k, fpath])
				return
			var bytes: PackedByteArray = files[fpath]
			if bytes.size() > MAX_MODEL_BYTES or bytes.size() < 20 or bytes.slice(0, 4).get_string_from_ascii() != "glTF":
				_reject(m, "模型 %s 不是 .glb 或超过 20 MB" % k)
				return
			var aid := model_id(mod_id, int(k))
			var poses := {}
			for q in e.get("poses", {}):
				var pq: Dictionary = e.poses[q]
				poses[str(int(q))] = {"g": 0, "clip": str(pq.get("clip", "")), "ticks": maxi(1, int(pq.get("ticks", 35))),
					"loop": bool(pq.get("loop", true)), "marks": [], "sounds": [], "bbox": e.get("bbox", [-25, 0, -25, 25, 160, 25])}
			if not poses.has("0"):
				poses["0"] = {"g": 0, "clip": "", "ticks": 1, "loop": true, "marks": [], "sounds": [], "bbox": e.get("bbox", [-25, 0, -25, 25, 160, 25])}
			new_models[aid] = {"bytes": bytes, "scale": float(e.get("scale", 1.0)), "yaw": float(e.get("yaw", 0.0)),
				"ground": float(e.get("ground", 0.0)),
				"meta": {"act": aid, "poses": poses, "groups": [{"glb": "@mod"}]}}
	# 自定义物品: 复制原版物品记录, 只改允许的字段
	var new_items := {}
	var itm: Variant = _json(files, "items.json")
	if itm is Dictionary:
		Battle.load_db()
		for k in itm:
			var e: Variant = itm[k]
			if int(k) < 1 or int(k) >= 256 or not e is Dictionary:
				_reject(m, "物品编号要在 1–255 之间")
				return
			var base: Dictionary = Battle.db.objs.get(str(int(e.get("base", 0))), {})
			if base.is_empty() or int(base.get("sub", 0)) not in ITEM_SUBS:
				_reject(m, "物品 %s 的 base %s 不是原版物品" % [k, str(e.get("base"))])
				return
			var rec: Dictionary = base.duplicate(true)
			for key in e:
				if key == "base":
					continue
				if key not in ITEM_KEYS:
					_reject(m, "物品 %s 不能改字段 %s" % [k, key])
					return
				var v: Variant = e[key]
				if key in ["fx1", "fx2"]:
					var want := 6 if key == "fx1" else 7
					if not v is Array or (v as Array).size() != want:
						_reject(m, "物品 %s 的 %s 要是 %d 个数" % [k, key, want])
						return
					v = (v as Array).map(func(x): return int(x))
				elif key == "price":
					v = clampi(int(v), 0, 9999999)
				else:
					v = str(v)
				rec[key] = v
			rec["mod"] = mod_id
			rec["base"] = int(e.base)
			new_items[item_id(mod_id, int(k))] = rec
	# 自定义怪物: 复制原版怪物记录, 只改允许的字段
	var new_monsters := {}
	var new_bestiary: Array = []
	var mon: Variant = _json(files, "monsters.json")
	if mon is Dictionary:
		var recs: Dictionary = _records().get("bestiary_by_id", {})
		for k in mon:
			var e: Variant = mon[k]
			if int(k) < 1 or int(k) >= 256 or not e is Dictionary:
				_reject(m, "怪物编号要在 1–255 之间")
				return
			var bid := int(e.get("base", 0))
			if not is_base_monster(bid):
				_reject(m, "怪物 %s 的 base %s 不是原版怪物" % [k, str(e.get("base"))])
				return
			var rec: Dictionary = Battle.db.objs[str(bid)].duplicate(true)
			var mid := monster_id(mod_id, int(k))
			for key in e:
				if key in ["base", "model", "poses"]:   # model / poses 在下面单独处理
					continue
				if key not in MONSTER_KEYS:
					_reject(m, "怪物 %s 不能改字段 %s" % [k, key])
					return
				var v: Variant = _resolve(e[key], mod_id)
				match key:
					"name", "desc":
						rec[key] = str(v)
					"exp", "money":
						rec.reward[key] = clampi(int(v), 0, 9999999)
					"counter":
						rec["kill_var"] = [actor_id(mod_id, 0), clampi(int(v), 1, 999)]
					"drop":   # 战后掉落 = 掉落表第 0 组 [几率 %, 物品] (第 1 组偷窃、第 2 组机关侦查照抄)
						if not v is Array or (v as Array).size() != 2:
							_reject(m, "怪物 %s 的 drop 要是 [几率, 物品]" % k)
							return
						var it := int(v[1])
						if it != 0 and not (Battle.db.objs.has(str(it)) and int(Battle.db.objs[str(it)].get("sub", 0)) in ITEM_SUBS) and not new_items.has(it):
							_reject(m, "怪物 %s 掉落的 %s 不是物品" % [k, str(e[key][1])])
							return
						rec.drops[0] = [clampi(int(v[0]), 0, 100), it]
					_:
						rec[key] = clampi(int(v), 1 if key in ["level", "hp"] else 0, 9999999)
			rec["mod"] = mod_id
			rec["base"] = bid
			rec["act"] = int(Battle.db.objs[str(bid)].get("act", bid))   # 战斗模型 / 动作用原版怪物的 ACT
			if e.has("model"):
				var maid: Variant = _resolve(e.model, mod_id)
				if not (maid is int and new_models.has(maid)):
					_reject(m, "怪物 %s 的 model 要用本 mod 的 @model:N" % k)
					return
				var bm := _battle_model(bid, new_models[maid], e.get("poses", {}))
				if bm.is_empty():
					_reject(m, "怪物 %s 的来源 %d 没有动作表" % [k, bid])
					return
				new_models[mid] = bm   # 虚拟 ACT 号 = 怪物号 (FieldActor 按 ACT 号找 Mods.models)
				rec["act"] = mid
			new_monsters[mid] = rec
			var be: Dictionary = recs.get(bid, {})
			if not be.is_empty():
				be = be.duplicate(true)
				be.id = mid
				be.name = rec.name
				be.desc = rec.desc
				for key in MONSTER_STATS:
					if be.has(key):
						be[key] = rec[key]
				be["mod"] = mod_id
				be["model_act"] = rec.act   # 有战斗模型时图鉴也显示它
				new_bestiary.append(be)
	# 自定义战斗: 复制原版普通战场, 换敌人
	var new_battles := {}
	var bts: Variant = _json(files, "battles.json")
	if bts is Dictionary:
		for k in bts:
			var e: Variant = bts[k]
			if int(k) < 1 or int(k) >= 64 or not e is Dictionary:
				_reject(m, "战斗编号要在 1–63 之间")
				return
			var bid := int(e.get("base", -1))
			if not is_base_battle(bid):
				_reject(m, "战斗 %s 的 base %s 不是可用的原版战场" % [k, str(e.get("base"))])
				return
			var base: Dictionary = Battle.db.battlefields[str(bid)]
			var rec: Dictionary = base.duplicate(true)
			rec.enemies = []
			var used := {}
			for en in e.get("enemies", []):
				var at := int(en.get("at", -1)) if en is Dictionary else -1
				if at < 0 or at >= base.enemies.size() or used.has(at):
					_reject(m, "战斗 %s 的站位 %s 不对 (原版战场有 %d 个位置)" % [k, str(at), base.enemies.size()])
					return
				used[at] = true
				var mid: Variant = _resolve(en.get("monster"), mod_id)
				if mid is float and mid == floorf(mid):   # JSON 数字读进来是浮点
					mid = int(mid)
				if not (mid is int and (new_monsters.has(mid) or is_base_monster(mid))):
					_reject(m, "战斗 %s 的敌人 %s 不是怪物" % [k, str(en.get("monster"))])
					return
				var slot: Dictionary = base.enemies[at]
				rec.enemies.append({"id": mid, "pos": slot.pos, "facing": slot.get("facing", 0.0)})
			if rec.enemies.is_empty():
				_reject(m, "战斗 %s 没有敌人" % k)
				return
			rec["mod"] = mod_id
			rec["base"] = bid
			new_battles[battle_id(mod_id, int(k))] = rec
	# 技能 / 绝技
	var new_skills := {}
	var new_sedits := {}
	var sk: Variant = _json(files, "skills.json")
	if sk is Dictionary:
		Battle.load_db()
		for k in sk:
			var e: Variant = sk[k]
			if not e is Dictionary:
				_reject(m, "技能 %s 格式不对" % k)
				return
			var orig_edit := not (e as Dictionary).has("base")
			var bid := int(k) if orig_edit else int(e.base)
			var base: Dictionary = Battle.db.objs.get(str(bid), {})
			if base.is_empty() or int(base.get("kind", 0)) != 3:
				_reject(m, "技能 %s: %d 不是原版技能" % [k, bid])
				return
			if not orig_edit and (int(k) < 1 or int(k) >= 256 or int(base.get("sub", 0)) not in SKILL_SUBS):
				_reject(m, "新技能 %s: 编号要在 1–255 之间, 只能复制攻击 / 恢复 / 辅助 / 绝技" % k)
				return
			var fields := {}
			for key in e:
				if key == "base":
					continue
				if key not in SKILL_KEYS:
					_reject(m, "技能 %s 不能改字段 %s" % [k, key])
					return
				var v: Variant = e[key]
				match key:
					"name", "desc":
						v = str(v)
					"power":
						v = clampi(int(v), 0, 999999)
					"cost":
						if not v is Dictionary:
							_reject(m, "技能 %s 的 cost 要是 {hp, sp, mp, juji}" % k)
							return
						var c: Dictionary = (base.get("cost", {}) as Dictionary).duplicate()
						for ck in ["hp", "sp", "mp", "juji"]:
							if (v as Dictionary).has(ck):
								c[ck] = clampi(int(v[ck]), 0, 99999)
						v = c
					"fx1", "fx2":
						var want := 6 if key == "fx1" else 7
						if not v is Array or (v as Array).size() != want:
							_reject(m, "技能 %s 的 %s 要是 %d 个数" % [k, key, want])
							return
						v = (v as Array).map(func(x): return int(x))
				fields[key] = v
			if orig_edit:
				new_sedits[bid] = fields
			else:
				var rec: Dictionary = base.duplicate(true)
				rec.merge(fields, true)
				rec["mod"] = mod_id
				rec["base"] = bid
				new_skills[skill_id(mod_id, int(k))] = rec
	# 改队员 / 开局
	var new_chars := {}
	var ch: Variant = _json(files, "characters.json")
	if ch is Dictionary:
		for k in ch:
			if int(k) not in [1, 2, 3] or not ch[k] is Dictionary:
				_reject(m, "characters.json 只能改 1 车芸 / 2 嬴诗 / 3 桓远之")
				return
			var e: Dictionary = _resolve(ch[k], mod_id)
			for key in e:
				if key not in CHAR_KEYS and key not in ["growth", "map_act"]:
					_reject(m, "队员 %s 不能改字段 %s" % [k, key])
					return
			if e.has("growth"):
				for row in e.growth:
					if not row is Array or (row as Array).size() != 14:
						_reject(m, "队员 %s 的成长表每行要 14 个数" % k)
						return
				e.growth = (e.growth as Array).map(func(r): return (r as Array).map(func(x): return int(x)))
			if e.has("map_act") and not (e.map_act is int or e.map_act is float):
				_reject(m, "队员 %s 的 map_act 要是 ACT 号或 @model:N" % k)
				return
			new_chars[int(k)] = e
	var ng: Variant = _json(files, "newgame.json")
	var new_ng := {}
	if ng is Dictionary:
		for key in ng:
			if key not in ["money", "items", "equip", "skills", "party"]:
				_reject(m, "newgame.json 不能改 %s" % key)
				return
		new_ng = _resolve(ng, mod_id)
	# 任务: 只能用本 mod 的旗标 (不能把原版任务的旗标挂到别处)
	var new_quests: Array = []
	var qs: Variant = _json(files, "quests.json")
	if qs is Dictionary:
		var keys: Array = qs.keys()
		keys.sort_custom(func(x, y): return int(x) < int(y))
		for k in keys:
			var e: Variant = qs[k]
			if not e is Dictionary or str(e.get("text", "")).strip_edges() == "":
				_reject(m, "任务 %s 没有文字" % k)
				return
			var fa: Variant = _resolve(e.get("accept"), mod_id)
			var fd: Variant = _resolve(e.get("done"), mod_id)
			var lo := flag_id(mod_id, 0)
			if not (fa is int and fd is int and fa > lo and fa < lo + 1000 and fd > lo and fd < lo + 1000):
				_reject(m, "任务 %s 的旗标要用本 mod 的 @flag:N" % k)
				return
			var text := str(e.text)
			new_quests.append({"text": text, "flag_accept": fa, "flag_done": fd, "main": text.begins_with("★"), "mod": mod_id})
	var new_npcs := {}
	var new_names := {}
	var new_enc := {}
	var new_edits := {}
	for f in files:
		if not (str(f).begins_with("maps/") and str(f).ends_with(".json")):
			continue
		var mid := str(f).get_file().get_basename()
		var patch: Variant = _json(files, f)
		if not patch is Dictionary:
			_reject(m, "%s 不是 JSON 对象" % f)
			return
		for ed in patch.get("npc_edits", []):
			var e2: Dictionary = _resolve(ed, mod_id) if ed is Dictionary else {}
			var who := int(e2.get("actor", 0))
			if who <= 0 or who >= ACTOR_BASE:
				_reject(m, "%s 的 npc_edits 要写原版角色号" % f)
				return
			for key in e2:
				if key not in ["actor", "remove", "pos", "act", "pose", "facing", "event", "name"]:
					_reject(m, "%s 的 npc_edits 不能改 %s" % [f, key])
					return
			new_edits.get_or_add(mid, []).append(e2)
		for en in patch.get("encounters", []):
			var bt: Variant = _resolve(en.get("battle") if en is Dictionary else null, mod_id)
			if not (bt is int and new_battles.has(bt)):
				_reject(m, "%s 的遇敌战斗要用本 mod 的 @battle:N" % f)
				return
			var w := int(en.get("weight", 1))
			if w < 1 or w > 20:
				_reject(m, "%s 的遇敌权重要在 1–20 之间" % f)
				return
			new_enc.get_or_add(mid, []).append({"battle": bt, "weight": w, "zones": (en.get("zones", []) as Array).map(func(x): return int(x)), "mod": mod_id})
		for r in patch.get("npcs", []):
			var rec: Dictionary = _resolve(r, mod_id)
			rec["map"] = int(mid)
			rec["actor"] = int(rec.get("id", 0))
			rec.erase("id")
			if rec.actor < ACTOR_BASE or rec.actor >= 0xf000:
				_reject(m, "NPC 编号要用 @npc:N (N < 256)")
				return
			for key in ["act", "pose", "facing", "event", "ai", "flags"]:
				rec[key] = int(rec.get(key, 0))
			if rec.has("name"):
				new_names[rec.actor] = str(rec.name)
			new_npcs.get_or_add(mid, []).append(rec)
	var new_tweaks: Variant = _parse_tweaks(m, files)
	if new_tweaks == null:
		return
	events.merge(new_events)
	names.merge(new_names)
	models.merge(new_models)
	items.merge(new_items)
	monsters.merge(new_monsters)
	bestiary.append_array(new_bestiary)
	battles.merge(new_battles)
	quests.append_array(new_quests)
	for mid in new_npcs:
		map_npcs.get_or_add(mid, []).append_array(new_npcs[mid])
	for k in new_over:
		if overrides.has(k):
			errors.append("%s 和之前的 mod 都改了原版事件 %d, 用 %s 的" % [mod_id, k, mod_id])
		overrides[k] = new_over[k]
	for mid in new_edits:
		map_npc_edits.get_or_add(mid, []).append_array(new_edits[mid])
	skills.merge(new_skills)
	for k in new_sedits:
		skill_edits.get_or_add(k, {}).merge(new_sedits[k], true)
	for k in new_chars:   # 同一个队员多个 mod 都改: 逐字段后加载的覆盖
		chars.get_or_add(k, {}).merge(new_chars[k], true)
	newgame.merge(new_ng, true)
	for mid in new_enc:
		map_encounters.get_or_add(mid, []).append_array(new_enc[mid])
	for k in new_tweaks:
		if tweaks.has(k):
			errors.append("%s 和之前的 mod 都写了 tweaks.json 的 %s, 用 %s 的" % [mod_id, k, mod_id])
		tweaks[k] = new_tweaks[k]
	m.voice = is_voice_pack(m)
	if m.voice and voice_mod == "":   # 配音包一次只用一个 (同一句台词各包都有, 混用会一句四川话一句台湾话)
		voice_mod = m.id
		for f in m.files:
			var fs := str(f)
			if fs.begins_with("voice/") and fs.ends_with(".ogg"):
				voices[fs.get_file().get_basename()] = m.files[f]
	m.status = "loaded"
	m.files = {}   # 内容已经并进来了, 不再留着
	mods.append(m)


## 带对白配音 (voice/*.ogg) 的 mod; 加载后 files 清空了, 看 m.voice
func is_voice_pack(m: Dictionary) -> bool:
	if m.get("voice", false):
		return true
	for f in m.get("files", {}):
		if str(f).begins_with("voice/"):
			return true
	return false


## 工坊菜单: 启用 / 停用 (记进设置, 下次 reload 生效)。启用配音包时停掉别的配音包 (一次只能用一个),
## 返回因此被停用的 mod 名字
func set_enabled(mod_id: String, on: bool) -> Array:
	var enabled: Array = Game.get_setting("mods", "enabled", []).duplicate()
	enabled.erase(mod_id)
	if on:
		enabled.append(mod_id)
	var off: Array = []
	var me: Array = installed.filter(func(o): return o.id == mod_id)
	if on and me.size() and is_voice_pack(me[0]):
		for o in installed:
			if o.id != mod_id and o.enabled and not o.dev and o.status != "error" and is_voice_pack(o):
				enabled.erase(o.id)
				o.enabled = false
				o.status = "disabled"
				off.append(str(o.name))
	Game.set_setting("mods", "enabled", enabled)
	for m in installed:
		if m.id == mod_id and m.status != "error":
			m.enabled = on
	return off


## 工坊菜单: 调整加载顺序 (列表当前顺序写进设置)
func set_order(ids: Array) -> void:
	Game.set_setting("mods", "order", ids)


## 工坊菜单: 删除 (只删 user://mods 里的; 命令行指定的不删)
func uninstall(mod_id: String) -> bool:
	for m in installed:
		if m.id == mod_id and not m.dev:
			var p: String = m.path
			var ok := (DirAccess.remove_absolute(p) == OK) if m.kind == "pod" else OS.move_to_trash(ProjectSettings.globalize_path(p)) == OK
			if ok:
				installed.erase(m)
			return ok
	return false


## field 读完原版数据后调用: 把 mod 的 NPC 追加进地图角色表、名字加进人名表
func apply(maps: Dictionary, people: Dictionary, item_names: Dictionary = {}) -> void:
	for iid in items:   # 对白里的 %T物品号. 用这张表
		item_names[str(iid)] = str(items[iid].get("name", ""))
	for mid in map_npcs:
		if maps.has(mid):
			maps[mid].get_or_add("npcs", []).append_array(map_npcs[mid])
		else:
			errors.append("没有地图 %s" % mid)
	for aid in names:
		people[str(aid)] = names[aid]
	for c in chars:   # 改队员名字: 对话框标题 / 人名表
		if chars[c].has("name"):
			people[str(c)] = str(chars[c].name)
	for mid in map_npc_edits:   # 改 / 删原版 NPC (按角色号找地图角色表里的记录)
		if not maps.has(mid):
			errors.append("没有地图 %s" % mid)
			continue
		var list: Array = maps[mid].get("npcs", [])
		for ed in map_npc_edits[mid]:
			var hit := false
			for i in range(list.size() - 1, -1, -1):
				var r: Dictionary = list[i]
				if int(r.get("actor", 0)) != int(ed.actor):
					continue
				hit = true
				if ed.get("remove", false):
					list.remove_at(i)
					continue
				for key in ["pos", "act", "pose", "facing", "event"]:
					if ed.has(key):
						r[key] = ed[key] if key == "pos" else int(ed[key])
			if ed.has("name"):
				people[str(int(ed.actor))] = str(ed.name)
			if not hit:
				errors.append("地图 %s 上没有原版角色 %d" % [mid, int(ed.actor)])
	for mid in map_encounters:   # 遇敌: mod 战斗按权重加进原版遇敌区域的战场列表
		var zones: Array = maps.get(mid, {}).get("zones", [])
		if not maps.has(mid) or not maps[mid].get("encounters", false) or zones.is_empty():
			errors.append("地图 %s 原版没有遇敌, mod 遇敌没加上" % mid)
			continue
		for en in map_encounters[mid]:
			for zi in zones.size():
				if (en.zones as Array).is_empty() or (en.zones as Array).has(zi):
					for k in int(en.weight):
						zones[zi].battlefields.append(en.battle)


func has_model(act: int) -> bool:
	return models.has(act)


## 角色用的动作表 (格式同 extracted/game/actors/act_<ACT>.json)
func model_meta(act: int) -> Dictionary:
	return (models[act].meta as Dictionary).duplicate(true) if models.has(act) else {}


## 解析 GLB 生成模型节点: 外层节点交给 FieldActor 套 ACT 变换, 里层按 mod 给的朝向 / 缩放修正
## (glTF 惯例正面朝 +Z; 游戏里朝向 0 = 面向 −Z, 见 field_actor.dir_of), 失败返回 null
func instantiate_model(act: int) -> Node3D:
	if not models.has(act):
		return null
	var e: Dictionary = models[act]
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	if doc.append_from_buffer(e.bytes, "", st) != OK:
		push_warning("MOD 模型 %d 解析失败" % act)
		return null
	var scene := doc.generate_scene(st) as Node3D
	if scene == null:
		return null
	var outer := Node3D.new()
	var inner := Node3D.new()
	inner.rotation_degrees.y = 180.0 + float(e.yaw)
	inner.scale = Vector3.ONE * float(e.scale)
	scene.position.y = -float(e.ground)   # 脚底贴地: ground = 待机姿势最低点 (模型单位, 编辑器保存时算好)
	inner.add_child(scene)
	outer.add_child(inner)
	return outer


## 改开局 / 车芸地图模型: field 读完 new_game.json 后调用 (newgame = 原版 MAPS.DAT 段 1 + 全局角色)
func apply_newgame(ng: Dictionary) -> void:
	if newgame.is_empty() and not chars.has(1):
		return
	var ini: Dictionary = ng.init
	if newgame.has("money"):
		ini.money = int(newgame.money)
	if newgame.has("items"):
		ini["items"] = (newgame["items"] as Array).map(func(x): return int(x))
	for key in ["equip", "skills"]:
		if newgame.has(key):
			for k in newgame[key]:
				ini[key][str(k)] = (newgame[key][k] as Array).map(func(x): return int(x))
	if newgame.has("party"):
		ng["party"] = (newgame.party as Array).map(func(x): return int(x))
	if chars.has(1) and chars[1].has("map_act"):
		for r in ng.get("actors", []):
			if int(r.actor) == 1:
				r.act = int(chars[1].map_act)


## 方案改过的原版事件 (field.event_code 先查这里)
func has_override(eid: int) -> bool:
	return overrides.has(eid)


func override_code(eid: int) -> Array:
	return overrides.get(eid, [])


func has_event(eid: int) -> bool:
	return events.has(eid)


func event_code(eid: int) -> Array:
	return events.get(eid, [])


## 存档里记一笔启用了哪些 mod (读档时缺了只提示)
func active_list() -> Array:
	return mods.map(func(m): return {"id": m.id, "version": m.version})
