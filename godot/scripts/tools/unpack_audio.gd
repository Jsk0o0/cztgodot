extends SceneTree
## 从素材包取回音频到本地提取目录 (原版目录不可用时; 之后 pack_plan 直接用 extracted/audio)
## godot --headless --path godot -s res://scripts/tools/unpack_audio.gd -- <common.pck> <extracted 目录>


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	ProjectSettings.load_resource_pack(a[0], false)
	var n := 0
	for sub in ["Music", "ACT"]:
		var src: String = "res://extracted/audio/" + sub
		var dst: String = a[1].path_join("audio").path_join(sub)
		DirAccess.make_dir_recursive_absolute(dst)
		for f in DirAccess.get_files_at(src):
			var b := FileAccess.get_file_as_bytes(src.path_join(f))
			var o := FileAccess.open(dst.path_join(f), FileAccess.WRITE)
			o.store_buffer(b)
			o.close()
			n += 1
	print("AUDIO %d 个文件" % n)
	quit()
