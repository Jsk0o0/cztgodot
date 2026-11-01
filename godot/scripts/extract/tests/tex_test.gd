extends SceneTree
## 测试: GDScript 解码全部 Tex/*.TEX, 和 Python 提取的 extracted/textures/*.png 逐像素比较
## godot --headless --path godot -s res://scripts/extract/tests/tex_test.gd -- <游戏目录> <extracted 目录> [上限]
const Tex := preload("res://scripts/extract/tex.gd")


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var game: String = a[0]
	var ext: String = a[1]
	var limit := int(a[2]) if a.size() > 2 else 1 << 30
	var t0 := Time.get_ticks_msec()
	var n := 0
	var bad := 0
	var px := 0
	var root := game.path_join("Tex")
	for cat in DirAccess.get_directories_at(root):
		for f in DirAccess.get_files_at(root.path_join(cat)):
			if not f.to_upper().ends_with(".TEX") or n >= limit:
				continue
			var img := Tex.load_file(root.path_join(cat).path_join(f))
			var ref := Image.load_from_file(ext.path_join("textures/%s/%s.png" % [cat, f.get_basename()]))
			n += 1
			if img == null or ref == null:
				bad += 1
				print("MISS ", cat, "/", f)
				continue
			px += img.get_width() * img.get_height()
			if ref.get_format() != img.get_format():
				ref.convert(img.get_format())
			if img.get_size() != ref.get_size() or img.get_data() != ref.get_data():
				bad += 1
				if bad <= 5:
					print("DIFF ", cat, "/", f, " ", img.get_size(), " ", img.get_format(), " vs ", ref.get_size())
	print("TEX n=%d bad=%d px=%d time=%.1fs" % [n, bad, px, (Time.get_ticks_msec() - t0) / 1000.0])
	quit()
