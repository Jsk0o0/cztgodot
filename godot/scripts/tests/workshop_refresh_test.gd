extends SceneTree
## 测试: 旧设置迁移 / 新 mod 默认不启用 / 刷新识别新增和删除
## godot --headless --path godot -s res://scripts/tests/workshop_refresh_test.gd -- <明文 mod 目录>


func _initialize() -> void:
	await process_frame
	var Mods = root.get_node("/root/Mods")
	var Game = root.get_node("/root/Game")
	var src: String = OS.get_cmdline_user_args()[0]
	var ok := true
	print("WS 迁移后 enabled=", Game.get_setting("mods", "enabled", null), " installed=", Mods.installed.map(func(m): return "%s:%s" % [m.id, m.status]))
	var dst: String = Mods.ROOT.path_join("zz_refresh_test")
	DirAccess.make_dir_recursive_absolute(dst)
	for f in DirAccess.get_files_at(src):
		DirAccess.copy_absolute(src.path_join(f), dst.path_join(f))
	Mods.reload()
	var m: Array = Mods.installed.filter(func(x): return str(x.path) == dst)
	print("WS 放入后 ", m.map(func(x): return "%s enabled=%s status=%s" % [x.id, x.enabled, x.status]))
	ok = ok and m.size() == 1 and not m[0].enabled and m[0].status == "disabled"
	for f in DirAccess.get_files_at(dst):
		DirAccess.remove_absolute(dst.path_join(f))
	DirAccess.remove_absolute(dst)
	Mods.reload()
	var gone: bool = Mods.installed.filter(func(x): return str(x.path) == dst).is_empty()
	print("WS 删除后已不在列表: ", gone)
	ok = ok and gone
	print("WS ", "PASS" if ok else "FAIL")
	quit()
