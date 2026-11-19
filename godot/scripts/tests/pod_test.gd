extends SceneTree
## 测试: .pod 读取 (流式解密解包) —— 大包内容和打包前的源文件逐字节一致; 改一个字节 / 截断都要拒绝。
## godot --path godot -s res://scripts/tests/pod_test.gd -- --bg --pod=<包> --src=<打包前的目录> --small=<小包>  → POD PASS / FAIL

var _fail := 0


func _ok(c: bool, what: String) -> void:
	print("  %s %s" % ["ok" if c else "FAIL", what])
	if not c:
		_fail += 1


func _arg(k: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % k):
			return a.substr(k.length() + 3)
	return ""


func _list(dir: String, rel: String, out: Array) -> void:
	for f in DirAccess.get_files_at(dir.path_join(rel)):
		out.append(rel.path_join(f) if rel != "" else f)
	for d in DirAccess.get_directories_at(dir.path_join(rel)):
		_list(dir, rel.path_join(d) if rel != "" else d, out)


func _initialize() -> void:
	await process_frame
	var Pod = load("res://scripts/pod.gd")
	var pod := _arg("pod")
	var src := _arg("src")
	var t0 := Time.get_ticks_msec()
	var r: Dictionary = Pod.read_file(pod)
	print("  读 %s: %d ms" % [pod.get_file(), Time.get_ticks_msec() - t0])
	_ok(r.ok, "大包能读 (%s)" % r.get("error", ""))
	if r.ok:
		var names: Array = []
		_list(src, "", names)
		_ok(r.files.size() == names.size(), "文件数一致 (%d / %d)" % [r.files.size(), names.size()])
		var same := 0
		for n in names:
			if r.files.has(n) and r.files[n] == FileAccess.get_file_as_bytes(src.path_join(n)):
				same += 1
		_ok(same == names.size(), "内容逐字节一致 (%d / %d)" % [same, names.size()])
	r = {}
	var small := FileAccess.get_file_as_bytes(_arg("small"))
	_ok(Pod.read_bytes(small).ok, "小包能读")
	var bad := small.duplicate()
	bad[bad.size() / 2] ^= 0x5a
	_ok(not Pod.read_bytes(bad).ok, "改一个字节被拒绝 (%s)" % Pod.read_bytes(bad).error)
	_ok(not Pod.read_bytes(small.slice(0, small.size() - 40)).ok, "截断被拒绝")
	print("POD %s" % ("PASS" if _fail == 0 else "FAIL (%d)" % _fail))
	quit(1 if _fail else 0)
