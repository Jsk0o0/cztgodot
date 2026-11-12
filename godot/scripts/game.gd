extends Node
## 全局: 素材路径、字体、音乐、设置。
## 项目本身不包含任何原版素材: 运行时从玩家本机的游戏目录 / 提取目录读取。

const DISCLAIMER := "本作为非官方、非商业同人作品，与大宇资讯、软星科技无关。\n《轩辕剑外传·苍之涛》全部角色、美术、音乐、剧情等素材之版权，均归大宇资讯股份有限公司所有。\n运行本作需自备正版游戏。"

## 原版全局标志 [0x9f2e90] (0x4658cb 设置, 只被选项按钮输入 0x465656 读): 0 = 取消键等于选第一项。
## 程序启动时为 0, 不存档; 只有 11 个界面会改它 (商店、存档覆盖、物品提示、离开游戏、封印之蛋、地图入口), 战斗 / 换图 / 读档都不重置
var cancel_lock := 0
## 「已取消」标记 [0xa84cf4]: 取消键在标志为 0 时置位; 下一个用 0x46559d 读回答的提示 (商店主提示、存档覆盖、离开游戏…) 会把回答当成 −1 并清掉它
var cancel_residual := false

## 0x46559d 的读法: 有「已取消」标记时回答当成 −1 (取消), 并清掉标记
func take_answer(k: int) -> int:
	if cancel_residual:
		cancel_residual = false
		return -1
	return k

var game_dir := ""        # 原版安装目录 (Music/ 等)
var extracted_dir := ""   # tools/ 提取结果 (scenes/ models/ textures/ ...)
var hd_dir := ""          # 高清素材 (tools/hd_assets.py, Real-ESRGAN ×2 / 4K ×4), 只含图片; GLB 的贴图在 tex/ (hd_textures.gd 换图); 默认为 <extracted_dir>_hd
var hd := false           # 是否使用高清素材: 命令行 --hd / --sd 优先, 否则取设置 video/hd
var hd_scale := 2        # 高清素材的放大倍数: 2K 为 2, 4K (tools/hd_assets.py --base) 为 4
var hd_dirs := {}         # 能用的高清素材 {2: 2K 目录, 4: 4K 目录}; 两个都有时设定里二选一 (video/hd_res)
var settings := ConfigFile.new()
var skill_viewer := false   # 技能观看器 (skill_preview 场景进入): field 按 VIEWER_ARGS 直接开战
var demo := OS.get_cmdline_user_args().has("--demo")   # 自动演示 (录视频): 标题自动开始, 对白读完自动翻页
const SETTINGS_PATH := "user://settings.cfg"

var font_title: SystemFont
var font_menu: SystemFont
var font_body: SystemFont
var cursor: GameCursor       # 原版鼠标光标 (scripts/game_cursor.gd), 各画面每帧 cursor.set_state(ACT, QQ)

var _music: AudioStreamPlayer
var _music_tween: Tween


var _hd_tex_ext: GLTFDocumentExtension


func _ready() -> void:
	_amd_to_d3d12()   # 要重启时这一帧末尾退出; 下面照常初始化, 免得同一帧里标题画面取不到字体等报错
	_load_paths()
	_hd_tex_ext = preload("res://scripts/hd_textures.gd").new()
	GLTFDocument.register_gltf_document_extension(_hd_tex_ext)
	settings.load(SETTINGS_PATH)
	for a in OS.get_cmdline_user_args():
		if a == "--no-auto-quality":
			_q_off = true
		elif a.begins_with("--fake-slow="):
			_q_slow_ms = int(a.substr(12))
	font_title = _sys_font(["Xingkai SC", "STXingkai", "Kaiti SC", "STKaiti", "Songti SC"])
	font_menu = _sys_font(["Kaiti SC", "STKaiti", "KaiTi", "BiauKai", "Songti SC"])
	# 注意: Godot 在 macOS 上会把「PingFang SC」解析成 PingFang HK (缺「远」等简体字, 回退也不生效), 所以冬青黑体排在前面
	font_body = _sys_font(["Hiragino Sans GB", "PingFang SC", "Source Han Sans SC", "Noto Sans CJK SC", "Microsoft YaHei", "Songti SC"])
	_music = AudioStreamPlayer.new()
	_music.bus = "Master"
	add_child(_music)
	apply_settings()
	cursor = GameCursor.new()
	add_child.call_deferred(cursor)


## AMD 显卡在 Windows 的 Vulkan 下, 画面增强的影子层会把地面画成大片黑 (用户反馈令狐国东城, 软影子颗粒边);
## 同一台机器 --rendering-driver d3d12 正常 → 驱动问题。只对 AMD 自动改用 D3D12:
## 在 exe 旁写 override.cfg (rendering_device/driver.windows = d3d12, 以后启动直接用), 并立刻带 --rendering-driver d3d12 重启一次。
## 只试一次 (设定 render/amd_d3d12_tried): D3D12 起不来时 Godot 会退回 Vulkan, 不能每次都重启。
## 命令行自己给了 --rendering-driver 时不管 (想强制 Vulkan: czt.exe --rendering-driver vulkan)
func _amd_to_d3d12() -> bool:
	if OS.get_name() != "Windows" or OS.has_feature("editor"):
		return false
	if RenderingServer.get_current_rendering_driver_name() != "vulkan" or OS.get_cmdline_args().has("--rendering-driver"):
		return false
	var v := RenderingServer.get_video_adapter_vendor().to_lower()
	if not (v.contains("amd") or v.contains("advanced micro") or v.begins_with("ati")):
		return false
	var st := ConfigFile.new()
	st.load(SETTINGS_PATH)
	if st.get_value("render", "amd_d3d12_tried", false):
		return false
	var oc := OS.get_executable_path().get_base_dir().path_join("override.cfg")
	var cf := ConfigFile.new()
	cf.load(oc)
	cf.set_value("rendering", "rendering_device/driver.windows", "d3d12")
	var err := cf.save(oc)
	if err == OK:   # 写不进 (exe 目录只读) 就不记「试过」: 以后每次启动都带参数重启一次 (重启的那个带了 --rendering-driver, 不会循环)
		st.set_value("render", "amd_d3d12_tried", true)
		st.save(SETTINGS_PATH)
	print("AMD 显卡 (%s): 改用 D3D12, override.cfg 写入%s" % [RenderingServer.get_video_adapter_vendor(), "成功" if err == OK else "失败 %d" % err])
	var args := PackedStringArray(["--rendering-driver", "d3d12"])
	args.append_array(OS.get_cmdline_args())
	if OS.create_process(OS.get_executable_path(), args) <= 0:
		return false   # 重启失败: 这次照常用 Vulkan, 下次启动读 override.cfg
	get_tree().quit.call_deferred()
	return true


## 原版按格子排字: 半角字 (数字、字母) 占字号一半宽。原版字体的数字本来就窄, 我们的系统字体数字更宽, 加上描边相邻数字会贴在一起
## (用户反馈「数字都快叠一起了」)。半角字的字号最多缩到 90% (再小就看不清), 另外每个半角格加宽 HALF_GAP 像素
const HALF_GAP := 1.0
var _half_fs := {}


func half_size(size: int, outline := 2) -> int:
	var key := size * 16 + outline
	if not _half_fs.has(key):
		var cell := size * 0.5 + HALF_GAP - 1.0
		var fs := size
		while fs > roundi(size * 0.9):
			var w := 0.0
			for d in "0123456789":
				w = maxf(w, font_body.get_string_size(d, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
			if w + outline <= cell:
				break
			fs -= 1
		_half_fs[key] = fs
	return _half_fs[key]


## 3D 画面 (SubViewport) 的渲染尺寸 = 界面区域在窗口里实际占的像素。
## 不能直接用窗口尺寸: 全屏时窗口是 16:9 / 16:10, 界面按 4:3 留黑边, 用窗口比例渲染再塞进 4:3 会把画面横向压扁
func view_px() -> Vector2i:
	var win := Vector2(get_tree().root.size)
	var vr := get_tree().root.get_visible_rect().size
	var s := minf(win.x / vr.x, win.y / vr.y)
	return Vector2i(maxi(int(vr.x * s), 1), maxi(int(vr.y * s), 1))


func _sys_font(names: Array) -> SystemFont:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(names)
	f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	f.allow_system_fallback = true   # 缺字 (如繁体字) 时回退到系统字体, 不显示方框
	return f


func _load_paths() -> void:
	# 优先级: user://settings.cfg > 项目目录下的 local_paths.cfg (本机开发用, 不分发)
	var cfg := ConfigFile.new()
	if cfg.load("res://local_paths.cfg") == OK:
		game_dir = cfg.get_value("paths", "game_dir", "")
		extracted_dir = cfg.get_value("paths", "extracted_dir", "")
	var user := ConfigFile.new()
	if user.load(SETTINGS_PATH) == OK:
		game_dir = user.get_value("paths", "game_dir", game_dir)
		extracted_dir = user.get_value("paths", "extracted_dir", extracted_dir)
	hd = user.get_value("video", "hd", false) if user.has_section("video") else false
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--extracted="):   # 调试: 用另一份提取结果 (例 本机提取程序的输出), 不改设置
			extracted_dir = a.substr(12)
	_load_packs(args)
	if not packs_loaded and extracted_dir == "":   # 发行版 (本机提取): 设置文件丢了也认已提取好的 (只检查, 不建目录)
		for d in [OS.get_executable_path().get_base_dir().path_join("extracted"), OS.get_user_data_dir().path_join("extracted")]:
			if extract_complete(d):
				extracted_dir = d
				break
	if not packs_loaded and not hd_from_pack:
		_local_hd_cfg = cfg.get_value("paths", "hd_dir", "")
		scan_local_hd()
	if (packs_loaded or hd_from_pack) and not hd_dirs.is_empty() and not user.has_section_key("video", "hd"):
		hd = true   # 发行版默认带 2K 包 (用户要求): 玩家没在设定里改过就用高清
	_pick_hd_dir(4 if args.has("--4k") else 2 if args.has("--2k") else int(user.get_value("video", "hd_res", 4)))   # 默认 4K: 玩家放了 4K 包就是想用它
	if args.has("--hd"):
		hd = true
	elif args.has("--sd"):
		hd = false
	if hd and hd_dirs.is_empty():
		push_warning("没有高清素材 (先运行 make hd)")
		hd = false


var _local_hd_cfg := ""   # local_paths.cfg 的 hd_dir (开发机)
const HD_VERSION := 3      # 同 tools/extractor.py 的 HD_VERSION: 本机生成的高清目录版本不同就不用


## 磁盘上的高清目录: 开发机 make hd / make hd4, 发行版玩家本机生成 (提取程序 --hd, 见 title.gd 生成高清素材)
##   <extracted_dir>_hd = 2K, <extracted_dir>_4k = 4K; 提取程序生成的目录 (有 .steps) 要做完 (.steps/complete) 且版本对才算
func scan_local_hd() -> void:
	var base := extracted_dir.rstrip("/\\")
	var dirs := {2: _local_hd_cfg if _local_hd_cfg != "" else base + "_hd", 4: base + "_4k"}
	for k in dirs:
		var d: String = dirs[k]
		if not DirAccess.dir_exists_absolute(d):
			continue
		if DirAccess.dir_exists_absolute(d.path_join(".steps")) and (not FileAccess.file_exists(d.path_join(".steps/complete"))
				or FileAccess.get_file_as_string(d.path_join(".steps/hdversion")).strip_edges() != str(HD_VERSION)):
			continue   # 没做完, 或旧规则生成的 (可能有全黑贴图, 要重新生成)
		hd_dirs[k] = d


## 选 2K / 4K; 要的那种没有就用另一种
func _pick_hd_dir(scale: int) -> void:
	if hd_dirs.is_empty():
		hd_dir = ""
		return
	hd_scale = scale if hd_dirs.has(scale) else int(hd_dirs.keys()[0])
	hd_dir = hd_dirs[hd_scale]


## 设定里切换 标清 / 2K / 4K, 不用重启: 已缓存的模型和特效贴图是旧清晰度, 清掉重读
func set_hd(on: bool, scale: int) -> void:
	hd = on and not hd_dirs.is_empty()
	_pick_hd_dir(scale)
	clear_glb_cache()
	Fx.clear_cache()


## 发行版: 素材预先打成 .pck 随游戏分发 (tools/pack_plan.py + make packs), 放在程序旁边的 packs/ 目录:
##   common.pck + ch01…ch10.pck (标清, res://extracted/…); 可选 hd2.pck (2K, res://extracted_hd/…) / hd4.pck (4K, res://extracted_4k/…), 都在时设定里二选一
##   高清包只有图片 / 视频和模型贴图 (tex/ + *.tex.json), 不含网格, 必须和标清包一起用
## 有 common.pck 就全部加载 (高清包也加载, 用不用由设置「高清」决定, 切换不用重启), 素材路径改指向包里
## 调试: --packs=目录 指定包目录 (开发机上测发行版)
var packs_loaded := false
var hd_from_pack := false   # 高清来自发行包 (标清包版或本机提取版): 玩家没改过设置时默认开高清


func _load_packs(args: PackedStringArray) -> void:
	var dir := OS.get_executable_path().get_base_dir().path_join("packs")
	for a in args:
		if a.begins_with("--packs="):
			dir = a.substr(8)
	if not FileAccess.file_exists(dir.path_join("common.pck")):
		# 本机提取版: 没有标清包, 但可以单独放高清包 (只有图片 / 贴图, 按相对路径对上磁盘上的提取目录)
		for k in [2, 4]:
			var f := dir.path_join("hd%d.pck" % k)
			if FileAccess.file_exists(f) and ProjectSettings.load_resource_pack(f, true):
				hd_dirs[k] = "res://extracted_hd" if k == 2 else "res://extracted_4k"
				hd_from_pack = true
		return
	var names := Array(DirAccess.get_files_at(dir)).filter(func(f): return f.get_extension() == "pck")
	names.sort()
	names.erase("common.pck")
	names.push_front("common.pck")   # 公共包先加载
	var has := {"hd2": false, "hd4": false}
	for f in names:
		if not ProjectSettings.load_resource_pack(dir.path_join(f), true):
			push_warning("素材包加载失败: " + f)
			continue
		for k in has:
			if f.get_basename() == k:
				has[k] = true
	packs_loaded = true
	hd_from_pack = has.hd2 or has.hd4
	extracted_dir = "res://extracted"
	if has.hd2:
		hd_dirs[2] = "res://extracted_hd"
	if has.hd4:
		hd_dirs[4] = "res://extracted_4k"


## 验证正版: 只看原版安装目录里的资源文件夹在不在 (用户要求不比对文件内容, 各版本都能过)
const ORIGINAL_DIRS := ["ACT", "MAP", "Model", "Music", "sound", "Tex", "VIDEO"]


## 检查原版游戏目录; 通过返回 "", 否则返回给玩家看的原因
func check_game_dir(dir: String) -> String:
	if dir == "" or not DirAccess.dir_exists_absolute(dir):
		return "还没有选择游戏目录。"
	var miss := ORIGINAL_DIRS.filter(func(d): return not DirAccess.dir_exists_absolute(dir.path_join(d)))
	if not miss.is_empty():
		return "这个目录里缺少 %s 文件夹，请选择《轩辕剑外传·苍之涛》的安装目录。" % "、".join(miss)
	return ""


func data_ready() -> bool:
	if extracted_dir != "" and DirAccess.dir_exists_absolute(extracted_dir.path_join(".steps")):
		return extract_complete(extracted_dir)   # 提取程序建的目录: 要全部完成且版本对
	return DirAccess.dir_exists_absolute(extracted_dir.path_join("ui/all_sys")) \
		and (DirAccess.dir_exists_absolute(extracted_dir.path_join("audio/Music")) or DirAccess.dir_exists_absolute(game_dir.path_join("Music")))


## 游戏版本 (自动更新比较 BUILD; tools/release.py 从这里读): 每次发布 BUILD 加 1, VERSION 是给人看的
const BUILD := 18
const VERSION := "0.1.17"


## 发行版本机提取 (方案 A): 程序旁边 extractor/czt_extract(.exe) (tools/extractor.py 打包), 第一次启动时从正版目录提取 (title.gd 引导)
## 提取规则版本, 和 tools/extractor.py 的 VERSION 一起改: 不同时 (更新过提取工具) 要重新提取
const EXTRACT_VERSION := 1


## 提取程序路径; 没有 (开发机、素材包版) 返回 ""。调试: --extractor=路径
func extractor_path() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--extractor="):
			return a.substr(12)
	var base := OS.get_executable_path().get_base_dir().path_join("extractor")
	for n in ["czt_extract.exe", "czt_extract"]:
		if FileAccess.file_exists(base.path_join(n)):
			return base.path_join(n)
	return ""


## 提取到哪: 程序旁边的 extracted/ 能写就用它, 否则 (装在 Program Files 之类) 用户数据目录。会建目录, 只在要开始提取时调用
func default_extract_dir() -> String:
	var d := OS.get_executable_path().get_base_dir().path_join("extracted")
	if DirAccess.make_dir_recursive_absolute(d) == OK:
		var t := d.path_join(".write_test")
		var f := FileAccess.open(t, FileAccess.WRITE)
		if f:
			f.close()
			DirAccess.remove_absolute(t)
			return d
	return OS.get_user_data_dir().path_join("extracted")


## 提取程序写的完成标记: <dir>/.steps/complete 内容 = 版本
func extract_complete(dir: String) -> bool:
	var f := FileAccess.open(dir.path_join(".steps/complete"), FileAccess.READ)
	return f != null and f.get_as_text().strip_edges() == str(EXTRACT_VERSION)


## 提取目录的状态: "new" 没提取过 / "partial" 上次没做完 / "old" 版本旧了要重来 / "done"
func extract_state(dir: String) -> String:
	if extract_complete(dir):
		return "done"
	var v := FileAccess.open(dir.path_join(".steps/version"), FileAccess.READ)
	if v == null:
		return "new"
	return "partial" if v.get_as_text().strip_edges() == str(EXTRACT_VERSION) else "old"


# ---------------- 素材 ----------------

## 过场动画按原版完整显示: 原版视频都是 16:9 画面 (800×450, 或 800×600 上下各 75 像素黑边做在视频里; 4K 版已去掉黑边),
## 按宽度放进 800 宽的画面、上下居中, 16:9 画面上下各留 75 黑边 (用户要求: 左右不裁)
func fit_video(vp: VideoStreamPlayer, _file := "") -> void:
	for k in 10:   # 第一帧解码出来才有尺寸
		await get_tree().process_frame
		if not is_instance_valid(vp):
			return
		var tex := vp.get_video_texture()
		if tex and tex.get_width() > 0:
			var size := Vector2(800.0, 800.0 * tex.get_height() / tex.get_width())
			vp.set_anchors_preset(Control.PRESET_TOP_LEFT)
			vp.position = Vector2(400, 300) - size * 0.5
			vp.size = size
			return


## 素材路径: 高清模式下优先用 hd_dir 里的同名文件, 没有就用原版
## GLB 一律读标清 (网格 / 动画只存一份), 高清贴图由 hd_textures.gd 在解析时换上
func asset_path(rel: String) -> String:
	if hd and not rel.ends_with(".glb"):
		var p := hd_dir.path_join(rel)
		if FileAccess.file_exists(p):
			return p
	return extracted_dir.path_join(rel)


## 过场动画: 高清模式下优先用 4K 版 (hd_dir/video_4k, convert_video.py --uhd, 16:9 不带黑边), 再是 2 倍高清版, 最后原版
func video_path(file: String) -> String:
	var name := file.get_file().get_basename() + ".ogv"
	if hd and not OS.get_cmdline_user_args().has("--no-4k"):
		var p := hd_dir.path_join("video_4k").path_join(name)
		if FileAccess.file_exists(p):
			return p
	return asset_path("video/" + name)


## 绝对路径版 (例如特效系统自己拼出的 extracted/effects/... 路径)
func asset_abs(path: String) -> String:
	if hd and path.begins_with(extracted_dir):
		return asset_path(path.substr(extracted_dir.length()).trim_prefix("/"))
	return path


## 图片 → 纹理; 高清图用 set_size_override 报告原尺寸, 界面排版、精灵大小、九宫格坐标都不变
func image_texture(path: String) -> ImageTexture:
	var real := asset_abs(path)
	var img := Image.load_from_file(real)
	if img == null:
		return null
	var t := ImageTexture.create_from_image(img)
	if real != path:
		t.set_size_override(Vector2i(maxi(img.get_width() / hd_scale, 1), maxi(img.get_height() / hd_scale, 1)))
	return t


## 运行时载入一个 GLB (例如 "scenes/MAP00145.glb"), 失败返回 null
func load_glb(rel: String) -> Node3D:
	var path := asset_path(rel)
	if _glb_cache.has(path):
		return (_glb_cache[path] as Node3D).duplicate()
	return _build_glb(path)


func _build_glb(path: String) -> Node3D:
	if not FileAccess.file_exists(path):
		push_warning("找不到素材: " + path)
		return null
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(path, state) != OK:
		push_warning("GLB 读取失败: " + path)
		return null
	return doc.generate_scene(state) as Node3D


## 后台线程读 GLB (换地图时用: 主线程继续画读取画面, 不卡、鼠标不转圈)
var _glb_cache := {}         # 绝对路径 → 已建好的节点模板 (load_glb 取它的副本)


## 后台线程只读文件 + 解析 glTF (append_from_file, 最耗时); 建节点 (generate_scene, 要创建网格 / 贴图) 回主线程做 ——
## 在线程里建网格会和渲染线程反复同步, 反而更慢
static func _parse_glb(path: String) -> Array:
	if not FileAccess.file_exists(path):
		return []
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(path, state) != OK:
		return []
	return [doc, state]


func load_glb_async(rel: String) -> Node3D:
	var path := asset_path(rel)
	if _glb_cache.has(path):
		return (_glb_cache[path] as Node3D).duplicate()
	var res: Array = [[]]
	var id := WorkerThreadPool.add_task(func(): res[0] = _parse_glb(path))
	while not WorkerThreadPool.is_task_completed(id):
		await get_tree().process_frame
	WorkerThreadPool.wait_for_task_completion(id)
	var parsed: Array = res[0]
	if parsed.is_empty():
		push_warning("GLB 读取失败: " + path)
		return null
	return (parsed[0] as GLTFDocument).generate_scene(parsed[1]) as Node3D


## 预读一批 GLB 进缓存 (全部任务同时交给线程池), on_progress(已完成数, 总数)
## 缓存跨地图保留 (最近用过的最多 GLB_CACHE_MAX 个), 回到去过的地图或遇到同样的角色时不用再读
const GLB_CACHE_MAX := 160
var _glb_order: Array = []


func preload_glbs(rels: Array, on_progress := Callable(), background := false) -> void:
	var paths: Array = []
	for rel in rels:
		var p := asset_path(str(rel))
		_glb_order.erase(p)
		_glb_order.append(p)
		if not _glb_cache.has(p) and not paths.has(p):
			paths.append(p)
	while _glb_order.size() > GLB_CACHE_MAX:
		var old: String = _glb_order.pop_front()
		if _glb_cache.has(old):
			(_glb_cache[old] as Node).free()
			_glb_cache.erase(old)
	# 前台 (读取画面): 全部同时交给线程池, 每帧在主线程建 30ms;
	# 后台 (玩的时候预读下一张图): 同时只解析 2 个, 每帧只建 4ms, 不跟游戏抢 CPU、不卡帧
	var max_tasks := 2 if background else paths.size()
	var budget_ms := 4 if background else 30
	var res: Array = []
	res.resize(paths.size())
	var ids: Array = []
	var built := {}
	var next := 0
	while built.size() < paths.size():
		while next < paths.size() and ids.size() - built.size() < max_tasks:
			var p: String = paths[next]
			var k := next
			if background:
				# 后台: 连建节点也放在线程里 (节点还没进场景树, 可以在线程里建), 主线程只收结果, 不卡帧
				ids.append(WorkerThreadPool.add_task(func():
					var pr: Array = _parse_glb(p)
					res[k] = [(pr[0] as GLTFDocument).generate_scene(pr[1])] if pr.size() else []))
			else:
				ids.append(WorkerThreadPool.add_task(func(): res[k] = _parse_glb(p)))
			next += 1
		var t0 := Time.get_ticks_msec()
		for i in ids.size():
			if built.has(i) or not WorkerThreadPool.is_task_completed(ids[i]):
				continue
			WorkerThreadPool.wait_for_task_completion(ids[i])
			built[i] = true
			var parsed: Array = res[i]
			res[i] = null
			if parsed.size() and not _glb_cache.has(paths[i]):
				_glb_cache[paths[i]] = parsed[0] if background else (parsed[0] as GLTFDocument).generate_scene(parsed[1])
			elif parsed.size() and background:
				(parsed[0] as Node).free()
			if Time.get_ticks_msec() - t0 > budget_ms:
				break
		if on_progress.is_valid():
			on_progress.call(built.size(), paths.size())
		if built.size() < paths.size():
			await get_tree().process_frame


# ---------------- 自动降画质 ----------------
## 用户反馈战斗掉到 10 帧以下; 机器性能未知, 所以运行时看帧时间: 连续 3 秒的中位数低于 Q_MIN_FPS 就降一档 (中位数不受单帧卡顿影响)。
## 只降不升 (升降反复本身就是帧数波动), 下次启动重新判断。开销依据: 1600×1200 下 4×MSAA 的渲染目标约占 170MB
const Q_MIN_FPS := 28.0
const Q_WINDOW := 3.0
const Q_MSAA := [Viewport.MSAA_4X, Viewport.MSAA_2X, Viewport.MSAA_DISABLED, Viewport.MSAA_DISABLED, Viewport.MSAA_DISABLED]
const Q_SCALE := [1.0, 1.0, 1.0, 0.75, 0.6]
var quality := 0
var _q_views: Array = []
var _q_dts := PackedFloat32Array()
var _q_acc := 0.0
var _q_hold := 0.0
var _q_off := false
var _q_slow_ms := 0        # 调试 --fake-slow=毫秒: 每帧多等这么久, 模拟慢机器


## 3D 视口 (地图 / 战斗) 建好后登记, 马上按当前档位设置
func quality_view(vp: SubViewport) -> void:
	if not _q_views.has(vp):
		_q_views.append(vp)
	_q_apply(vp)
	quality_hold()


## 读取 / 换场景时暂停统计, 不把加载算成慢
func quality_hold() -> void:
	_q_hold = 1.5
	_q_acc = 0.0
	_q_dts.clear()


func _q_apply(vp: SubViewport) -> void:
	vp.msaa_3d = Q_MSAA[quality]
	vp.scaling_3d_scale = Q_SCALE[quality]
	var cam3 := vp.get_camera_3d()
	if cam3 and quality >= 1:
		cam3.attributes = null              # 画面增强的景深
	var sun := vp.find_child("EnhanceSun", true, false) as DirectionalLight3D
	if sun and quality >= 2:
		sun.shadow_enabled = false          # 画面增强的影子


func _process(delta: float) -> void:
	if _q_off:
		return
	if _q_slow_ms > 0:
		OS.delay_msec(_q_slow_ms)
	_q_views = _q_views.filter(func(v): return is_instance_valid(v))
	if _q_views.is_empty() or quality >= Q_MSAA.size() - 1:
		return
	if not get_window().has_focus() and _q_slow_ms == 0:
		quality_hold()                      # 切到后台时系统可能限帧, 不算
		return
	if _q_hold > 0.0:
		_q_hold -= delta
		return
	_q_dts.append(delta)
	_q_acc += delta
	if _q_acc < Q_WINDOW:
		return
	_q_dts.sort()
	var med := _q_dts[_q_dts.size() / 2]
	_q_acc = 0.0
	_q_dts.clear()
	if med > 1.0 / Q_MIN_FPS:
		quality += 1
		_q_hold = 0.5
		print("QUALITY %d (median %.0fms) views=%d" % [quality, med * 1000.0, _q_views.size()])
		for v in _q_views:
			_q_apply(v)


func clear_glb_cache() -> void:
	for n in _glb_cache.values():
		(n as Node).free()
	_glb_cache.clear()


## 运行时载入提取出的图片 (例如 "ui/all_sys/0100_000_标题介面800x600/000.png")
func load_texture(rel: String) -> Texture2D:
	var t := image_texture(extracted_dir.path_join(rel))
	if t == null:
		push_warning("找不到图片: " + extracted_dir.path_join(rel))
	return t


## 原版音频: 发行版的提取程序把 Music/ 和 ACT/all.snd 复制到提取目录的 audio/ 下 (运行时不再读原版目录);
## 开发环境没复制过时退回原版目录
func audio_path(rel: String) -> String:
	var p := extracted_dir.path_join("audio").path_join(rel)
	return p if FileAccess.file_exists(p) else game_dir.path_join(rel)


func load_music(file_name: String) -> AudioStream:
	var path := audio_path("Music".path_join(file_name))
	if not FileAccess.file_exists(path):
		push_warning("找不到音乐: " + path)
		return null
	if file_name.get_extension().to_lower() == "mp3":
		return AudioStreamMP3.load_from_file(path)
	return AudioStreamWAV.load_from_file(path)


var _music_file := ""


func play_music(file_name: String, fade := 2.0) -> void:
	if OS.get_cmdline_user_args().has("--no-music"):
		return   # 录像: 只留音效, 配乐后期统一加
	if _music.playing and _music_file == file_name:
		return  # 同一首曲子 (例如换地图) 不从头重播
	_music_file = file_name
	var s := load_music(file_name)
	if s == null:
		return
	if s is AudioStreamMP3:
		(s as AudioStreamMP3).loop = true
	_music.stream = s
	_music.volume_db = -60.0
	_music.play()
	_fade_music(_target_db(), fade)


# ---------------- 音效 (ACT/all.snd) ----------------
## all.snd: +0x18 u32 条数, +0x1c 起每条 44 字节 = 名字[20] (如「527_獲得寶物1」), u32 大小, u32 偏移, u32 编号;
## 数据 = WAVEFORMATEX 16 字节 (全部是 PCM: 8/16 位, 单 / 双声道, 11025–44100 Hz) + 样本。事件 0x69 play_sound N 的 N 即编号
## 发行版提取时复制到 audio/ACT/all.snd (audio_path)
const SFX_UI_SELECT := 513
const SFX_UI_OK := 512
const SFX_UI_CANCEL := 511
const SFX_UI_PAGE := 530
const SFX_UI_ERROR := 526

var _sfx_dir := {}            # 编号 → [偏移, 大小]
var _sfx_cache := {}          # 编号 → AudioStreamWAV
var _sfx_players: Array = []


func _sfx_index() -> bool:
	if not _sfx_dir.is_empty():
		return true
	var f := FileAccess.open(audio_path("ACT/all.snd"), FileAccess.READ)
	if f == null:
		return false
	f.seek(0x18)
	var n := f.get_32()
	for i in n:
		f.seek(0x1c + 44 * i + 20)
		var size := f.get_32()
		var off := f.get_32()
		_sfx_dir[int(f.get_32())] = [off, size]
	return true


func _sfx_stream(id: int) -> AudioStreamWAV:
	if _sfx_cache.has(id):
		return _sfx_cache[id]
	if not _sfx_index() or not _sfx_dir.has(id):
		return null
	var f := FileAccess.open(audio_path("ACT/all.snd"), FileAccess.READ)
	var e: Array = _sfx_dir[id]
	f.seek(int(e[0]))
	var raw := f.get_buffer(int(e[1]))
	if raw.size() < 16:
		return null
	var ch := raw.decode_u16(2)
	var rate := raw.decode_u32(4)
	var bits := raw.decode_u16(14)
	var data := raw.slice(16)
	var s := AudioStreamWAV.new()
	s.mix_rate = rate
	s.stereo = ch == 2
	if bits == 8:
		for i in data.size():   # WAV 的 8 位样本无符号, Godot 要有符号
			data[i] = (data[i] + 128) & 0xff
		s.format = AudioStreamWAV.FORMAT_8_BITS
	else:
		s.format = AudioStreamWAV.FORMAT_16_BITS
	s.data = data
	if _sfx_cache.size() > 64:
		_sfx_cache.erase(_sfx_cache.keys()[0])
	_sfx_cache[id] = s
	return s


func play_sound(id: int) -> void:
	if id <= 0:
		return
	var s := _sfx_stream(id)
	if s == null:
		return
	var p: AudioStreamPlayer = null
	for q in _sfx_players:
		if not (q as AudioStreamPlayer).playing:
			p = q
			break
	if p == null:
		if _sfx_players.size() >= 12:
			p = _sfx_players[0]
		else:
			p = AudioStreamPlayer.new()
			add_child(p)
			_sfx_players.append(p)
	p.stream = s
	p.volume_db = linear_to_db(clampf(float(settings.get_value("audio", "sfx", 0.8)), 0.0, 1.0) + 0.0001)
	p.play()


## 循环音效 (原版 0x4befee 循环次数 -1; 呼风唤雨的雨声 491): 同一编号只开一个, stop_sound_loop 停
var _loop_players := {}


func play_sound_loop(id: int) -> void:
	if _loop_players.has(id) and is_instance_valid(_loop_players[id]):
		return
	var s := _sfx_stream(id)
	if s == null:
		return
	var ls := s.duplicate() as AudioStreamWAV
	ls.loop_mode = AudioStreamWAV.LOOP_FORWARD
	ls.loop_end = ls.data.size() / (2 if ls.format == AudioStreamWAV.FORMAT_16_BITS else 1) / (2 if ls.stereo else 1)
	var p := AudioStreamPlayer.new()
	add_child(p)
	p.stream = ls
	p.volume_db = linear_to_db(clampf(float(settings.get_value("audio", "sfx", 0.8)), 0.0, 1.0) + 0.0001)
	p.play()
	_loop_players[id] = p


func stop_sound_loop(id: int) -> void:
	if _loop_players.has(id):
		if is_instance_valid(_loop_players[id]):
			_loop_players[id].queue_free()
		_loop_players.erase(id)


func stop_music(fade := 1.5) -> void:
	_music_file = ""
	_fade_music(-60.0, fade, true)


func _fade_music(db: float, t: float, stop_after := false) -> void:
	if _music_tween:
		_music_tween.kill()
	_music_tween = create_tween()
	_music_tween.tween_property(_music, "volume_db", db, t)
	if stop_after:
		_music_tween.tween_callback(_music.stop)


func _target_db() -> float:
	var v: float = settings.get_value("audio", "music", 0.8)
	return linear_to_db(maxf(v, 0.0001))


# ---------------- 设置 ----------------

func get_setting(section: String, key: String, default: Variant) -> Variant:
	return settings.get_value(section, key, default)


func has_setting(section: String, key: String) -> bool:
	return settings.has_section_key(section, key)


func set_setting(section: String, key: String, value: Variant) -> void:
	settings.set_value(section, key, value)
	settings.save(SETTINGS_PATH)
	apply_settings()


## 把鼠标移到窗口坐标 p; --bg 后台测试 / 录制时不动玩家真实的鼠标
func warp_mouse(p: Vector2) -> void:
	if not OS.get_cmdline_user_args().has("--bg"):
		get_viewport().warp_mouse(p)


func apply_settings() -> void:
	if _music and _music.playing and not (_music_tween and _music_tween.is_running()):
		_music.volume_db = _target_db()
	var bg_run := OS.get_cmdline_user_args().has("--bg")   # 测试: 不全屏、不抢焦点, 窗口放到屏幕外后台跑 (不写设置)
	var fs: bool = settings.get_value("video", "fullscreen", false) and not bg_run
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fs else DisplayServer.WINDOW_MODE_WINDOWED
	if bg_run and DisplayServer.get_name() != "headless":
		get_window().unfocusable = true
		get_window().position = DisplayServer.screen_get_size() - Vector2i(1, 1)
	if DisplayServer.window_get_mode() != mode and DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(mode)


## 退出时自己注销高清贴图扩展: 不注销的话它要等引擎最后清理 GLTF 模块时才释放, 那时脚本系统已经关闭
## (Windows 上退出卡死时加的, 是否就是原因还要在 Windows 上确认)
func _exit_tree() -> void:
	if _hd_tex_ext:
		GLTFDocument.unregister_gltf_document_extension(_hd_tex_ext)
		_hd_tex_ext = null
	clear_glb_cache()   # 缓存的模型不在场景树里, 不手动释放会被当成泄漏 (退出时一大串报错)
	Fx.clear_cache()


func _notification(what: int) -> void:   # 调试: 自动测试时记录非正常退出的来源
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		print("AP QUIT via window close request")
	elif what == NOTIFICATION_CRASH:
		print("AP CRASH")
