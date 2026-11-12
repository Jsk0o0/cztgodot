class_name Updater
extends Node
## 自动更新 (发行版): 读发布仓库 (CNB corumol/swd, 私有, 游戏内置只读令牌) 里签过名的清单 latest.json →
##   主程序有新版本: 下载更新包 (czt.exe / czt.pck / 说明) → 交给提取程序替换后重启
##   提取程序没有 / 和清单里的不一样: 下载提取程序包, 游戏自己解压到 extractor/ (那时提取程序没在运行, 直接换)
## 清单 + 签名 (latest.json / latest.json.sig) 由 tools/release.py publish 生成并上传; 签名 = 作者密钥 RSA-SHA256 (PKCS#1 v1.5), base64,
##   验签公钥在 update_key.gd。令牌只是让游戏读得到私有仓库, 防伪靠签名: 验不过 / 读不到 / 格式不对一律当作没有清单, 不影响离线游玩
## 清单字段: build (整数, 比 Game.BUILD 大才算新)、version、min_build (Game.BUILD 比它小 = 必须更新)、platform (同 OS.get_name())、
##   date、notice {id, title, text} (可选)、zip {url, size, sha256} (主程序)、extractor {url, size, sha256} (提取程序, 可选)、
##   esrgan {url, size, sha256} (高清放大程序, 可选; 玩家生成高清素材时才下载)、page (可选)
## 包放在仓库的 Git LFS 里 (czt/pkg/), 地址 = OpenAPI GET /corumol/swd/-/lfs/<sha256>?name=<文件名> (只要 repo-code:r), 302 到预签名地址
## 下载: 第一跳带令牌、不自动跟随跳转; 拿到跳转地址 (LFS 对象存储的预签名地址) 后不带令牌下载, 令牌不会发给别的网站
## 调试参数 (只在调试版生效): --update-url= --update-token= --update-pubkey=公钥 PEM 文件 --update-target=安装目录 --update-relaunch=重启程序

signal checked(info: Dictionary)          # {} = 没有可用的清单; 否则清单 + newer / required / manual / extractor_needed
signal progress(done: int, total: int)
signal downloaded(ok: bool, message: String)

## 清单地址 (CNB OpenAPI 读仓库文件: GET /{repo}/-/git/raw/{分支}/{路径}, 要令牌 repo-code:r)
const MANIFEST_URL := "https://api.cnb.cool/corumol/swd/-/git/raw/main/czt/latest.json"
const KEY_SCRIPT := "res://scripts/cnb_read_key.gd"   # make cnb-key 从 .cnbkey 生成 (不进仓库); 没有就不带令牌
const TIMEOUT := 10.0
const PKG_MARK := ".package_sha256"   # extractor/ 里记下装的是哪个提取程序包

var manifest_url := MANIFEST_URL
var info := {}
var zip_path := ""
var _pem: String = preload("res://scripts/update_key.gd").PEM
var _token := ""
var _target := ""
var _relaunch := ""
var _dl: HTTPRequest
var _dl_size := 0
var _cancelled := false


func _init() -> void:
	_target = OS.get_executable_path().get_base_dir()
	_relaunch = OS.get_executable_path()
	if ResourceLoader.exists(KEY_SCRIPT):
		_token = str(load(KEY_SCRIPT).TOKEN)
	if not OS.is_debug_build():
		return
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--update-url="):
			manifest_url = a.substr(13)
		elif a.begins_with("--update-token="):
			_token = a.substr(15)
		elif a.begins_with("--update-pubkey="):
			_pem = FileAccess.get_file_as_string(a.substr(16))
		elif a.begins_with("--update-target="):
			_target = a.substr(16)
		elif a.begins_with("--update-relaunch="):
			_relaunch = a.substr(18)


## 要不要检查: 导出的发行版; 调试时给了 --update-url
func enabled() -> bool:
	return manifest_url != "" and (OS.has_feature("template") or OS.is_debug_build() and MANIFEST_URL != manifest_url)


func update_dir() -> String:
	return _target.path_join("update")


func extractor_dir() -> String:
	return _target.path_join("extractor")


## 读清单 + 验签; 结果从 checked 发出
func check() -> void:
	if not enabled():
		checked.emit({})
		return
	var body := await _fetch(manifest_url)
	var sig := await _fetch(manifest_url + ".sig") if not body.is_empty() else PackedByteArray()
	var d := verify_manifest(body, sig, _pem)
	if d.is_empty():
		checked.emit({})
		return
	d["newer"] = int(d.build) > Game.BUILD
	d["required"] = Game.BUILD < int(d.min_build)
	info = d
	d["extractor_needed"] = pkg_needed("extractor")   # 先记下: manual_reason 要看 extractor_needed (没有提取程序但能下载 = 可以自动更新)
	d["manual"] = d.newer and manual_reason() != ""
	checked.emit(d)


static func _pkg_ok(z) -> bool:
	return z is Dictionary and z.get("url") is String and str(z.url).begins_with("http") and (z.get("size") is float or z.get("size") is int) \
		and z.get("sha256") is String and str(z.sha256).length() == 64


## 验签 + 检查字段; 不合格返回 {} (静态, 测试直接调)
static func verify_manifest(body: PackedByteArray, sig_b64: PackedByteArray, pem: String) -> Dictionary:
	if body.is_empty() or sig_b64.is_empty() or body.size() > 65536:
		return {}
	var sig := Marshalls.base64_to_raw(sig_b64.get_string_from_utf8().strip_edges())
	var key := CryptoKey.new()
	if sig.is_empty() or key.load_from_string(pem, true) != OK:
		return {}
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(body)
	if not Crypto.new().verify(HashingContext.HASH_SHA256, h.finish(), sig, key):
		return {}
	var d = JSON.parse_string(body.get_string_from_utf8())
	if not d is Dictionary:
		return {}
	for k in ["build", "min_build"]:
		if not (d.get(k) is float or d.get(k) is int):
			return {}
	if not d.get("version") is String or d.get("platform", "") != OS.get_name() or not _pkg_ok(d.get("zip")):
		return {}
	for k in ["extractor", "esrgan"]:
		if d.has(k) and not _pkg_ok(d[k]):
			d.erase(k)
	if d.has("notice") and not (d.notice is Dictionary and d.notice.get("text") is String):
		d.erase("notice")
	return d


## 不能自动更新主程序的原因 ("" = 可以): 没有提取程序 (替换要靠它)、安装目录写不进去 (例 装在 Program Files)
func manual_reason() -> String:
	if not writable():
		return "游戏目录没有写入权限：" + _target
	if Game.extractor_path() == "" and not info.get("extractor_needed", false):
		return "找不到更新程序（extractor 文件夹）"
	return ""


func writable() -> bool:
	DirAccess.make_dir_recursive_absolute(update_dir())
	var probe := update_dir().path_join(".write_test")
	var f := FileAccess.open(probe, FileAccess.WRITE)
	if f == null:
		return false
	f.close()
	DirAccess.remove_absolute(probe)
	return true


func _auth() -> PackedStringArray:
	return PackedStringArray(["Authorization: Bearer " + _token]) if _token != "" else PackedStringArray()


## 读小文件 (清单 / 签名): GET 带令牌、不跟随跳转; 跳转了就不带令牌再读跳转地址
func _fetch(url: String, auth := true) -> PackedByteArray:
	var r := HTTPRequest.new()
	r.timeout = TIMEOUT
	r.body_size_limit = 65536
	r.max_redirects = 0 if auth else 8
	add_child(r)
	if r.request(url, _auth() if auth else PackedStringArray()) != OK:
		r.queue_free()
		return PackedByteArray()
	var res: Array = await r.request_completed
	r.queue_free()
	if auth and res[1] in [301, 302, 303, 307, 308]:
		var loc := _location(url, res[2])
		return await _fetch(loc, false) if loc != "" else PackedByteArray()
	if res[0] != HTTPRequest.RESULT_SUCCESS or res[1] != 200:
		return PackedByteArray()
	return res[3]


static func _location(url: String, headers: PackedStringArray) -> String:
	for hd in headers:
		if hd.to_lower().begins_with("location:"):
			var loc := hd.substr(9).strip_edges()
			if loc.begins_with("/"):   # 相对地址
				loc = url.substr(0, url.find("/", url.find("//") + 2)) + loc
			return loc
	return ""


## 下载主程序更新包 (kind "app") 或提取程序包 (kind "extractor") 到 update/; 进度从 progress、结果从 downloaded 发出
func download(kind := "app") -> void:
	var z: Dictionary = info.zip if kind == "app" else info[kind]
	_cancelled = false
	DirAccess.make_dir_recursive_absolute(update_dir())
	var name := ("czt_%d.zip" % int(info.build)) if kind == "app" else "czt_%s.zip" % kind
	var part := update_dir().path_join(name + ".part")
	DirAccess.remove_absolute(part)
	_dl_size = int(z.size)
	var to := [str(z.url), true]   # 第一跳 GET 带令牌、不跟随跳转 (CNB 的 LFS 接口不支持 HEAD, 返回 404)
	var res: Array = []
	for hop in 2:
		_dl = HTTPRequest.new()
		_dl.download_file = part
		_dl.use_threads = true
		_dl.download_chunk_size = 1 << 20
		_dl.max_redirects = 0 if to[1] else 8
		add_child(_dl)
		if _dl.request(to[0], _auth() if to[1] else PackedStringArray()) != OK:
			_finish_download(part, false, "无法开始下载")
			return
		res = await _dl.request_completed
		if _cancelled:
			return
		if not (to[1] and res[1] in [301, 302, 303, 307, 308]):
			break
		var loc := _location(str(to[0]), res[2])   # GET 才跳转: 不带令牌去跳转地址
		_dl.queue_free()
		_dl = null
		if loc == "":
			break
		to = [loc, false]
	if res[0] != HTTPRequest.RESULT_SUCCESS or res[1] != 200:
		_finish_download(part, false, "下载失败（%s）" % (("HTTP %d" % res[1]) if res[0] == HTTPRequest.RESULT_SUCCESS else "网络错误 %d" % res[0]))
		return
	var f := FileAccess.open(part, FileAccess.READ)
	if f == null or f.get_length() != int(z.size):
		_finish_download(part, false, "下载的文件大小不对")
		return
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	var n := 0
	while f.get_position() < f.get_length():
		h.update(f.get_buffer(1 << 20))
		n += 1
		if n % 16 == 0:
			await get_tree().process_frame   # 别让界面卡住
	f.close()
	if h.finish().hex_encode() != str(z.sha256).to_lower():
		_finish_download(part, false, "下载的文件校验失败")
		return
	var done := part.trim_suffix(".part")
	DirAccess.remove_absolute(done)
	if DirAccess.rename_absolute(part, done) != OK:
		_finish_download(part, false, "无法保存下载的文件")
		return
	if kind == "app":
		zip_path = done
		_finish_download(part, true, "")
		return
	var err := install_pkg(kind, done, str(z.sha256))
	DirAccess.remove_absolute(done)
	_finish_download(part, err == "", err)


func _finish_download(part: String, ok: bool, msg: String) -> void:
	if _dl:
		_dl.queue_free()
		_dl = null
	if not ok:
		DirAccess.remove_absolute(part)
	downloaded.emit(ok, msg)


func cancel() -> void:
	_cancelled = true
	if _dl:
		_dl.cancel_request()
		_dl.queue_free()
		_dl = null
	downloaded.emit(false, "已取消")


func _process(_d: float) -> void:
	if _dl:
		progress.emit(_dl.get_downloaded_bytes(), _dl_size)


## 程序包 (kind → 目录 / 必须有的程序): 提取程序、高清放大程序 (Real-ESRGAN ncnn Vulkan, 只在玩家要生成高清素材时下载)
const PKGS := {
	"extractor": {"dir": "extractor", "exe": ["czt_extract.exe", "czt_extract"], "what": "提取程序"},
	"esrgan": {"dir": "esrgan", "exe": ["realesrgan-ncnn-vulkan.exe", "realesrgan-ncnn-vulkan"], "what": "高清放大程序"},
}


func pkg_dir(kind: String) -> String:
	return _target.path_join(PKGS[kind].dir)


## 已装的程序包里的程序路径 ("" = 没装)
func pkg_exe(kind: String) -> String:
	for n in PKGS[kind].exe:
		if FileAccess.file_exists(pkg_dir(kind).path_join(n)):
			return pkg_dir(kind).path_join(n)
	return ""


## 要不要 (重新) 下载: 清单里有这个包, 且没装 / 装的不是这个版本
func pkg_needed(kind: String) -> bool:
	if not info.has(kind):
		return false
	var mark := FileAccess.get_file_as_string(pkg_dir(kind).path_join(PKG_MARK)).strip_edges().to_lower()
	return pkg_exe(kind) == "" or mark != str(info[kind].sha256).to_lower()


## 程序包 → <安装目录>/<dir>/: 先整个解压到 update/<dir>_new/, 再把旧的改名让位、新的改名进去; 返回 "" 或原因
func install_pkg(kind: String, zip: String, sha: String) -> String:
	var spec: Dictionary = PKGS[kind]
	var zr := ZIPReader.new()
	if zr.open(zip) != OK:
		return "%s包打不开" % spec.what
	var tmp := update_dir().path_join(spec.dir + "_new")
	_remove_tree(tmp)
	var has_exe := false
	for rel in zr.get_files():
		if rel.ends_with("/"):
			continue
		if rel.begins_with("/") or rel.contains("..") or rel.contains(":") or rel.contains("\\"):
			zr.close()
			_remove_tree(tmp)
			return "%s包里有不安全的路径：%s" % [spec.what, rel]
		has_exe = has_exe or rel in spec.exe
		var p := tmp.path_join(rel)
		DirAccess.make_dir_recursive_absolute(p.get_base_dir())
		var f := FileAccess.open(p, FileAccess.WRITE)
		if f == null:
			zr.close()
			_remove_tree(tmp)
			return "无法写入：" + p
		f.store_buffer(zr.read_file(rel))
		f.close()
	zr.close()
	if not has_exe:
		_remove_tree(tmp)
		return "%s包里没有 %s" % [spec.what, spec.exe[0]]
	if OS.get_name() != "Windows":
		for n in spec.exe:
			if FileAccess.file_exists(tmp.path_join(n)):
				OS.execute("chmod", ["+x", tmp.path_join(n)])
	var fm := FileAccess.open(tmp.path_join(PKG_MARK), FileAccess.WRITE)
	if fm:
		fm.store_string(sha.to_lower() + "\n")
		fm.close()
	var dst := pkg_dir(kind)
	var old := update_dir().path_join(spec.dir + "_old")
	_remove_tree(old)
	if DirAccess.dir_exists_absolute(dst) and DirAccess.rename_absolute(dst, old) != OK:
		_remove_tree(tmp)
		return "旧的%s正在使用，无法替换" % spec.what
	if DirAccess.rename_absolute(tmp, dst) != OK:
		if DirAccess.dir_exists_absolute(old):
			DirAccess.rename_absolute(old, dst)
		_remove_tree(tmp)
		return "无法安装%s" % spec.what
	_remove_tree(old)
	return ""


static func _remove_tree(p: String) -> void:
	if not DirAccess.dir_exists_absolute(p):
		return
	var d := DirAccess.open(p)
	if d == null:
		return
	d.include_hidden = true
	for f in d.get_files():
		DirAccess.remove_absolute(p.path_join(f))
	for sub in d.get_directories():
		_remove_tree(p.path_join(sub))
	DirAccess.remove_absolute(p)


## 启动替换程序后退出游戏; 返回 "" 或失败原因
func apply() -> String:
	var ex := Game.extractor_path()
	if ex == "" or zip_path == "":
		return "找不到更新程序"
	var args := PackedStringArray(["--apply-update", zip_path, "--sha256", str(info.zip.sha256), "--target", _target,
		"--wait-pid", str(OS.get_process_id()), "--relaunch", _relaunch])
	if OS.create_process(ex, args) <= 0:
		return "无法启动更新程序：" + ex
	get_tree().quit()
	return ""


## 启动时: 删掉上次更新留下的旧文件 (update/cleanup.txt) 和装提取程序剩下的目录
func cleanup() -> void:
	for k in PKGS:
		_remove_tree(update_dir().path_join(PKGS[k].dir + "_old"))
		_remove_tree(update_dir().path_join(PKGS[k].dir + "_new"))
	var list := update_dir().path_join("cleanup.txt")
	if not FileAccess.file_exists(list):
		return
	var left := PackedStringArray()
	for rel in FileAccess.get_file_as_string(list).split("\n", false):
		rel = rel.strip_edges()
		var name := rel.replace("\\", "/").get_file()
		if rel.contains("..") or rel.is_absolute_path() or not (name.contains(".czt-old") or name.ends_with(".czt-new")):
			continue   # 只删替换程序改过名的文件
		var p := _target.path_join(rel)
		if FileAccess.file_exists(p) and DirAccess.remove_absolute(p) != OK:
			left.append(rel)
	if left.is_empty():
		DirAccess.remove_absolute(list)
	else:
		var f := FileAccess.open(list, FileAccess.WRITE)
		if f:
			f.store_string("\n".join(left) + "\n")
