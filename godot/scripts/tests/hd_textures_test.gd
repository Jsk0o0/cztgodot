extends SceneTree
## 测试: 标清 GLB + hd_textures.gd 换图 得到的贴图
##   每张都是标清的 hd_scale 倍大小 (对照表里没有高清版的除外, 应与标清相同);
##   2K 另有完整高清 GLB 时, 再和其中的贴图逐像素比较
## godot --path godot -s res://scripts/tests/hd_textures_test.gd -- [每隔几个抽一个, 默认 1] [--2k | --4k]
## (要开窗口跑: 无头模式读不回贴图像素)


func _initialize() -> void:
	await process_frame
	var Game = root.get_node("/root/Game")
	var args := OS.get_cmdline_user_args()
	var step := 1
	for a in args:
		if a.is_valid_int():
			step = int(a)
	var rels: Array = []
	for d in ["scenes", "game/actors", "effects/models"]:
		for f in DirAccess.get_files_at(Game.extracted_dir.path_join(d)):
			if f.ends_with(".glb") and FileAccess.file_exists(Game.hd_dir.path_join(d).path_join(f + ".tex.json")):
				rels.append(d.path_join(f))
	rels.sort()
	var n := 0
	var bad := 0
	var imgs := 0
	for i in range(0, rels.size(), step):
		var rel: String = rels[i]
		Game.hd = false
		var sd: Array = _images(Game.extracted_dir.path_join(rel))
		Game.hd = true
		var a: Array = _images(Game.extracted_dir.path_join(rel))   # 标清 GLB, 经过换图
		var names: Array = JSON.parse_string(FileAccess.get_file_as_string(Game.hd_dir.path_join(rel + ".tex.json"))).tex
		var full: String = Game.hd_dir.path_join(rel)              # 完整高清 GLB (不在 extracted_dir 下, 不换图), 只有 2K 有
		var b: Array = _images(full) if FileAccess.file_exists(full) else []
		n += 1
		var same := a.size() == sd.size() and a.size() == names.size() and (b.is_empty() or b.size() == a.size())
		for k in mini(a.size(), mini(sd.size(), names.size())):
			imgs += 1
			var want: Vector2i = sd[k].get_size() * (Game.hd_scale if names[k] != null else 1)
			if a[k].get_size() != want:
				same = false
			if k < b.size() and (a[k].get_size() != b[k].get_size() or a[k].get_data() != b[k].get_data()):
				same = false
		if not same:
			bad += 1
			print("HDTEX 不一致 ", rel, " ", a.map(func(x): return x.get_size()), " 标清 ", sd.map(func(x): return x.get_size()))
	print("HDTEX ×%d 模型 %d 个, 贴图 %d 张, 不一致 %d" % [Game.hd_scale, n, imgs, bad])
	print("HDTEX ", "PASS" if bad == 0 and n > 0 else "FAIL")
	quit()


func _images(path: String) -> Array:
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	if doc.append_from_file(path, st) != OK:
		return []
	var out := []
	for t in st.get_images():
		var im: Image = (t as Texture2D).get_image() if t else null
		out.append(im if im else Image.new())
	return out
