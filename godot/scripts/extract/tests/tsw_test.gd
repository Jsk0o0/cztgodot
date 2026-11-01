extends SceneTree
## 测试: GDScript 提取 .tsw 到临时目录, 和 Python 的 extracted/ui 比较 (index.json 内容 + 每张 PNG 像素)
## godot --headless --path godot -s res://scripts/extract/tests/tsw_test.gd -- <游戏目录> <extracted 目录> <临时输出目录>
const Tsw := preload("res://scripts/extract/tsw.gd")


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var game: String = a[0]
	var ref_dir: String = a[1].path_join("ui")
	var out: String = a[2]
	var t0 := Time.get_ticks_msec()
	var idx: Dictionary = Tsw.extract(game, out)
	var t1 := Time.get_ticks_msec()
	var ref: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ref_dir.path_join("index.json")))
	var mine: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(out.path_join("index.json")))
	var bad := 0
	var n := 0
	for stem in ref:
		var ra: Array = ref[stem]
		var ma: Array = mine.get(stem, [])
		if ra.size() != ma.size():
			print("COUNT ", stem, " ", ra.size(), " vs ", ma.size())
			bad += 1
			continue
		for i in ra.size():
			var r: Dictionary = ra[i]
			var m: Dictionary = ma[i]
			for k in ["index", "name", "name_simplified", "dir"]:
				if str(r[k]) != str(m[k]):
					bad += 1
					print("FIELD ", stem, " ", k, " ", r[k], " vs ", m[k])
			for j in r.frames.size():
				var rf: Dictionary = r.frames[j]
				var mf: Dictionary = m.frames[j] if j < m.frames.size() else {}
				if rf.has("error") != mf.has("error"):
					bad += 1
					print("ERRFLAG ", r.dir, " ", j)
					continue
				if rf.has("error"):
					continue
				n += 1
				var p := "%s/%03d.png" % [r.dir, j]
				var i1 := Image.load_from_file(ref_dir.path_join(p))
				var i2 := Image.load_from_file(out.path_join(p))
				if i1.get_format() != i2.get_format():
					i1.convert(i2.get_format())
				if i1.get_size() != i2.get_size() or i1.get_data() != i2.get_data():
					bad += 1
					if bad < 6:
						print("PIX ", p)
	print("TSW frames=%d bad=%d extract=%.1fs" % [n, bad, (t1 - t0) / 1000.0])
	quit()
