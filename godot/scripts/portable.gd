class_name Portable
extends RefCounted
## 便携模式 (第三方「懒人补丁包」等发行补丁会整体替换 game/title/mod_manager 等脚本的字节码, 所以便携逻辑放这个独立类里;
## 已实测补丁替换清单不含本类 / boot / state / fame):
##   程序 (或编辑器工程上级目录) 旁边有 orig/ 时, 整个文件夹是自包含便携包:
##   1. path_in(): 存档/认识度经本类直接落 <程序目录>/userdata (宿主 state/fame 不被补丁替换, 天然生效)。
##   2. heal_game_dir(): 补丁版 game.gd 没有「game_dir 回退到 orig」的逻辑, 新机器上 settings 又没这个键时会找不到
##      原版音频; 启动时把 <程序目录>/orig 写进设置 (仅缺失或无效时)。
##   3. portable_subdir(): 设置/Mod 的宿主 (game/mod_manager) 会被补丁替换, 路径代码改不动 —— 用目录联接把
##      user:// 下的 mods/ 指到 <程序目录>/userdata/mods, 引擎级生效, 不需要被替换的脚本配合。logs/shader_cache
##      等缓存仍在系统目录 (引擎在 _ready 前就持有它们, 挪不动, 也无需挪)。
##   没有 orig/ 时 root 为空, 所有路径等于原来的 user:// 位置, 行为与官方一致。

const ORIGINAL_DIRS := ["ACT", "MAP", "Model", "Music", "sound", "Tex", "VIDEO"]   # game.gd check_game_dir 同款 (本类不依赖 game.gd, 复制一份)
const SETTINGS := "user://settings.cfg"

static var root := _find()

static func _find() -> String:
	for base in [OS.get_executable_path().get_base_dir(), ProjectSettings.globalize_path("res://").path_join("..")]:
		if base == "" or base == "." or not DirAccess.dir_exists_absolute(base.path_join("orig")):
			continue
		DirAccess.make_dir_recursive_absolute(base.path_join("userdata"))
		return base
	return ""

## 便携时 <root>/userdata/<sub>, 否则返回调用方原来的 user:// 路径 (行为不变)
static func path_in(sub: String, user_default: String) -> String:
	return root.path_join("userdata").path_join(sub) if root != "" else user_default

## settings.cfg 双向同步 (其宿主 game.gd 会被补丁替换, 路径固定 user://settings.cfg, 改不了; Boot 两份代码都不被替换):
## 启动最早期 (Game._ready 读设置之前) 把较新一侧复制到另一侧 —— 拷到新机器: 游戏目录副本较新 → 种进 user://,
## 启用配音等设置直接生效; 本机日常: 游戏写 user://, 下次启动同步回游戏目录, 复制文件夹带走最新设置。
static func sync_settings() -> void:
	if root == "":
		return
	var portable := root.path_join("userdata").path_join("settings.cfg")
	var user := ProjectSettings.globalize_path(SETTINGS)
	if not FileAccess.file_exists(portable) and not FileAccess.file_exists(user):
		return
	if FileAccess.file_exists(portable) \
			and (not FileAccess.file_exists(user) or _mtime(portable) > _mtime(user)):
		DirAccess.copy_absolute(portable, user)
		print("PORTABLE 设置已从游戏目录同步到 user://")
	elif FileAccess.file_exists(user) \
			and (not FileAccess.file_exists(portable) or _mtime(user) > _mtime(portable)):
		DirAccess.make_dir_recursive_absolute(root.path_join("userdata"))
		DirAccess.copy_absolute(user, portable)   # 游戏目录副本更新, 复制文件夹时带上最新设置


static func heal_game_dir() -> void:
	if root == "":
		return
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)   # 文件不存在也 OK: 后面 save 会新建
	var orig := root.path_join("orig")
	var dir: String = cfg.get_value("paths", "game_dir", "")
	if dir == orig and _valid_game_dir(orig):
		return   # 已正确
	if not _valid_game_dir(orig):
		push_warning("便携模式: orig/ 缺少原版目录必需的文件夹, 无法自动设置原版目录")
		return
	if dir != "" and _valid_game_dir(dir):
		return
	cfg.set_value("paths", "game_dir", orig)
	cfg.save(SETTINGS)
	print("PORTABLE game_dir -> " + orig)

static func _valid_game_dir(dir: String) -> bool:
	return dir != "" and DirAccess.dir_exists_absolute(dir) \
		and ORIGINAL_DIRS.filter(func(x): return not DirAccess.dir_exists_absolute(dir.path_join(x))).is_empty()

## 让 user://<sub> (如 mods) 变成指向 <程序目录>/userdata/<sub> 的目录联接; 非便携返回 false。
## 联接已存在则直接成功 (不重复建)。旧的散落数据在系统目录时尽力挪一次 (新者胜), 被占用的文件跳过。
static func portable_subdir(sub: String) -> bool:
	if root == "":
		return false
	var target := root.path_join("userdata").path_join(sub)
	DirAccess.make_dir_recursive_absolute(target)
	var link := ProjectSettings.globalize_path("user://").path_join(sub)   # 尾斜杠拼出来无妨, API 都容忍
	var parent_d := DirAccess.open(link.get_base_dir())
	if parent_d != null and parent_d.is_link(link.get_file()):   # is_link 对 Windows junction 返回 true (4.7.2 实测)
		return true
	if DirAccess.dir_exists_absolute(link):
		_move_contents(link, target)
		if not _is_empty_dir(link):
			push_warning("便携模式: user://%s 非空且含正在使用的文件, 未建链接" % sub)
			return false
		DirAccess.remove_absolute(link)
	if _make_link(link, target):
		print("PORTABLE user://%s -> %s" % [sub, target])
		return true
	push_warning("便携模式: 无法创建链接 %s -> %s" % [link, target])
	return false

## 目录内容挪进便携目录 (文件级, 新者胜; 目录结构保留一层). 失败的文件 (占用) 跳过。
static func _move_contents(src_dir: String, dst_dir: String) -> void:
	for f in DirAccess.get_files_at(src_dir):
		var s := src_dir.path_join(f)
		var t := dst_dir.path_join(f)
		if not FileAccess.file_exists(t) or _mtime(s) > _mtime(t):
			_move_into(s, dst_dir, true)
		else:
			DirAccess.remove_absolute(s)   # 便携目录的版本更新, 删旧
	for sub in DirAccess.get_directories_at(src_dir):   # 只下探一层 (mods/saves 内无更深结构)
		DirAccess.make_dir_recursive_absolute(dst_dir.path_join(sub))
		_move_contents(src_dir.path_join(sub), dst_dir.path_join(sub))

static func _move_into(src: String, dst_dir: String, overwrite := false) -> void:
	DirAccess.make_dir_recursive_absolute(dst_dir)
	var dst := dst_dir.path_join(src.get_file())
	if overwrite and FileAccess.file_exists(dst):
		DirAccess.remove_absolute(dst)
	if DirAccess.rename_absolute(src, dst) == OK:   # 同盘直接改名; 跨盘官方自动退回复制
		return
	if DirAccess.copy_absolute(src, dst) == OK:
		DirAccess.remove_absolute(src)
	else:
		print("PORTABLE 跳过 (被占用?): " + src)

static func _mtime(p: String) -> int:
	return FileAccess.get_modified_time(p)   # Unix 秒; 4.7 里 DirAccess 的取修改时间方法都不可用 (实测), 只有这个静态方法可用; 取不到返回 -1

static func _is_empty_dir(p: String) -> bool:
	var d := DirAccess.open(p)
	if d == null:
		return false
	d.list_dir_begin()
	var n := d.get_next()
	while n != "":
		d.list_dir_end()
		return false   # 有内容
	return true

## 链接: Windows 用 cmd mklink /J (目录联接, 无需管理员权限, 可跨盘)。路径含中文 → 经 chcp 65001 的 UTF-8 bat 执行
## (直接 OS.execute("cmd", ["mklink"...]) 走 GBK 代码页, 中文名会写成乱码, 实测); 其他系统 ln -s。
static func _make_link(link: String, target: String) -> bool:
	if OS.get_name() == "Windows":
		var bat := OS.get_temp_dir().path_join("czt_link.bat")
		var f := FileAccess.open(bat, FileAccess.WRITE)
		if f == null:
			return false
		f.store_string("@echo off\r\nchcp 65001 >nul\r\nmklink /J \"%s\" \"%s\"\r\n" % [link, target])
		f.close()
		OS.execute("cmd", ["/c", bat.replace("/", "\\")])
		DirAccess.remove_absolute(bat)
	else:
		OS.execute("ln", ["-s", target, link])
	var d := DirAccess.open(link.get_base_dir())
	return d != null and d.is_link(link.get_file())
