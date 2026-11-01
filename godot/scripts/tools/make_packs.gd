extends SceneTree
## 按 tools/pack_plan.py 的规划写 .pck (Godot PCKPacker; 文件原样放进包里, 不经过导入, 游戏用 FileAccess / Image / GLTFDocument 直接读)
## godot --headless --path godot -s res://scripts/tools/make_packs.gd -- <plan.json> <输出目录> [只做这些包, 逗号分隔]


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var plan: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(a[0]))
	var out: String = a[1]
	var only := a[2].split(",") if a.size() > 2 and a[2] != "" else PackedStringArray()
	DirAccess.make_dir_recursive_absolute(out)
	var t0 := Time.get_ticks_msec()
	for name in plan.packs:
		if only.size() and not only.has(name):
			continue
		var pk := PCKPacker.new()
		var path := out.path_join(name + ".pck")
		if pk.pck_start(path) != OK:
			printerr("PACK 无法写入 ", path)
			quit(1)
			return
		var n := 0
		for e in plan.packs[name]:
			if pk.add_file(str(e[0]), str(e[1])) != OK:
				printerr("PACK 加不进去 ", e[1])
				quit(1)
				return
			n += 1
		pk.flush()
		print("PACK %s %d 个文件 %.1f MB" % [name, n, _size(path) / 1048576.0])
	print("PACK 完成 %.1fs" % ((Time.get_ticks_msec() - t0) / 1000.0))
	quit()


func _size(p: String) -> int:
	var f := FileAccess.open(p, FileAccess.READ)
	return f.get_length() if f else 0
