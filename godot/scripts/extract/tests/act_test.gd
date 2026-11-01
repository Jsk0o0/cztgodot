extends SceneTree
const Act := preload("res://scripts/extract/act.gd")
const Cmp := preload("res://scripts/extract/tests/cmp.gd")


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var ref: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(a[1]))
	var t0 := Time.get_ticks_msec()
	var mine := {}
	for k in Act.ACT_FILES.size():
		var d := FileAccess.get_file_as_bytes(a[0].path_join("ACT").path_join(Act.ACT_FILES[k]))
		for slot in Act.read_index(d):
			var r := Act.actions(d, k * 3000 + int(slot))
			var m := {}
			for q in r:
				m[str(q)] = r[q]
			mine[str(k * 3000 + int(slot))] = m
	var mine2: Variant = JSON.parse_string(JSON.stringify(mine))
	var dd := Cmp.diff(ref, mine2, 1e-4)
	for x in dd:
		print("D ", x)
	print("ACT acts=%d diffs=%d time=%.1fs" % [ref.size(), dd.size(), (Time.get_ticks_msec() - t0) / 1000.0])
	quit()
