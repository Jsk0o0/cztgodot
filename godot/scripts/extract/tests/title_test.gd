extends SceneTree
const TB := preload("res://scripts/extract/title_buttons.gd")


func _init() -> void:
	var bad := 0
	var n := 0
	for pair in [["/tmp/claude-501/tb_sd", "/Users/kp/Desktop/czt/extracted"], ["/tmp/claude-501/tb_hd", "/Users/kp/Desktop/czt/extracted_hd"]]:
		var s := 1 if pair[0].ends_with("sd") else 2
		TB.build(pair[0], s)
		for f in DirAccess.get_files_at(pair[1].path_join("ui/custom")):
			var a := Image.load_from_file(pair[1].path_join("ui/custom").path_join(f))
			var b := Image.load_from_file(pair[0].path_join("ui/custom").path_join(f))
			a.convert(Image.FORMAT_RGB8)
			n += 1
			if b == null or a.get_data() != b.get_data():
				bad += 1
				var dmax := 0
				if b:
					var da := a.get_data()
					var db := b.get_data()
					for i in da.size():
						dmax = maxi(dmax, absi(da[i] - db[i]))
				print("DIFF ", s, " ", f, " max=", dmax)
	print("TITLE n=%d bad=%d" % [n, bad])
	quit()
